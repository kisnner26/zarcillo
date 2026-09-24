import AppKit
import Darwin
import SwiftUI

/// La carga del procesador y el momento en que termina algo largo (mucho rato
/// trabajando a fondo y de golpe descansa): eso es la aurora del iPhone.
@MainActor
final class Vitals {
    private var previous: host_cpu_load_info?
    private var smooth = 0.0
    private var busySince: Date?
    private var auroraUntil = Date.distantPast

    func sample() -> (cpu: Double, aurora: Bool) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (smooth, false) }
        defer { previous = info }
        guard let p = previous else { return (0, false) }
        func d(_ a: UInt32, _ b: UInt32) -> Double { Double(a &- b) }
        let user = d(info.cpu_ticks.0, p.cpu_ticks.0), system = d(info.cpu_ticks.1, p.cpu_ticks.1)
        let idle = d(info.cpu_ticks.2, p.cpu_ticks.2), nice = d(info.cpu_ticks.3, p.cpu_ticks.3)
        let total = user + system + idle + nice
        let load = total > 0 ? (user + system + nice) / total : 0
        smooth += (load - smooth) * 0.5

        let now = Date()
        if smooth > 0.55 {
            if busySince == nil { busySince = now }
        } else if smooth < 0.25, let start = busySince {
            // Estuvo al menos 25 s a fondo y ya descansa: terminó algo largo.
            if now.timeIntervalSince(start) >= 25 { auroraUntil = now.addingTimeInterval(20) }
            busySince = nil
        }
        return (smooth, now < auroraUntil)
    }
}

// MARK: - Aura de Claude

/// Un borde de luz alrededor de toda la pantalla mientras el cerebro trabaja:
/// el color del acento al pensar, ámbar si espera tu permiso, verde al terminar
/// bien y rojo si algo falló. No roba clics ni foco.
@MainActor
final class Aura {
    enum State: Equatable { case thinking, confirm, done(Bool) }

    fileprivate final class Model: ObservableObject {
        @Published var color: Color = .clear
        @Published var visible = false
    }

    fileprivate let model = Model()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ state: State) {
        let color: Color
        switch state {
        case .thinking: color = MacTone.ember
        case .confirm: color = Color(red: 1.0, green: 0.72, blue: 0.2)
        case .done(let ok): color = ok ? Color(red: 0.4, green: 0.9, blue: 0.5) : Color(red: 0.95, green: 0.3, blue: 0.3)
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let p = panel ?? makePanel(screen.frame)
        panel = p
        if p.frame != screen.frame { p.setFrame(screen.frame, display: false) }
        p.orderFrontRegardless()
        withAnimation(.easeInOut(duration: 0.4)) {
            model.color = color
            model.visible = true
        }
        hideWork?.cancel()
        // Terminó: se apaga sola. Pensando o esperando permiso: tope de un minuto por si algo se cuelga.
        var hold = 60.0
        if case .done = state { hold = 1.8 }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        withAnimation(.easeOut(duration: 0.5)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel(_ frame: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = fixedHost(AuraView(model: model))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }
}

private struct AuraView: View {
    @ObservedObject var model: Aura.Model

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let spin = Angle.degrees((t * 70).truncatingRemainder(dividingBy: 360))
            let pulse = 0.75 + 0.25 * sin(t * 3)
            let gradient = AngularGradient(colors: [model.color, model.color.opacity(0.25), model.color, model.color.opacity(0.25), model.color],
                                           center: .center, angle: spin)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(gradient, lineWidth: 26).blur(radius: 22)
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(gradient, lineWidth: 8).blur(radius: 6)
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(model.color.opacity(0.9), lineWidth: 2)
            }
            .opacity(model.visible ? pulse : 0)
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Enseñar por demostración

/// Mira lo que haces (apps que abres y atajos de teclado) y lo convierte en
/// pasos. No graba lo que escribes: solo combinaciones con ⌘ o ⌃.
@MainActor
final class Teacher {
    private(set) var recording = false
    private var name = ""
    private var steps: [BrainStep] = []
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    var onChange: ((Bool, Int, String?) -> Void)?

    private static let special: [UInt16: String] = [
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
        123: "left", 124: "right", 125: "down", 126: "up",
    ]

    func start(name: String) {
        cancel()
        recording = true
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        steps = []
        if let front = NSWorkspace.shared.frontmostApplication { noteApp(front) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.noteApp(app) }
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.noteKey(e) }
        }
        onChange?(true, 0, nil)
    }

    func stop() -> (String, [BrainStep])? {
        guard recording else { return nil }
        let result = (name, steps)
        teardown()
        return result
    }

    func cancel() {
        guard recording else { return }
        teardown()
        onChange?(false, 0, nil)
    }

    private func teardown() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let o = observer { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        monitor = nil
        observer = nil
    }

    private func noteApp(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier, let n = app.localizedName, steps.count < 30 else { return }
        if steps.last?.kind == "openApp", steps.last?.text == n { return }
        steps.append(BrainStep(kind: "openApp", text: n))
        onChange?(true, steps.count, nil)
    }

    private func noteKey(_ e: NSEvent) {
        guard steps.count < 30, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let f = e.modifierFlags
        guard f.contains(.command) || f.contains(.control) else { return }
        let key = Self.special[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "").lowercased()
        guard key.count == 1 || Self.special.values.contains(key) else { return }
        var mods = 0
        if f.contains(.command) { mods |= DeckAction.cmd }
        if f.contains(.shift) { mods |= DeckAction.shift }
        if f.contains(.option) { mods |= DeckAction.option }
        if f.contains(.control) { mods |= DeckAction.control }
        // Tras abrir una app hay que darle un momento antes del atajo.
        if steps.last?.kind == "openApp" { steps.append(BrainStep(kind: "wait", number: 0.6)) }
        steps.append(BrainStep(kind: "shortcut", key: key, mods: mods))
        onChange?(true, steps.count, nil)
    }
}
