import SwiftUI
import UIKit

// La app como un solo instrumento:
//
//  · el cuerpo es de Brasa: cerámica oscura, perilla naranja, pad hundido;
//  · la navegación es de Órbita: los modos giran en un anillo alrededor de la
//    perilla y arriba se lee en grande lo que está elegido;
//  · el alma es de Enredadera: la perilla dibuja un zarcillo que se enrosca con
//    el valor, las apps son brotes en un tallo y "más" es un tallo vertical.
//
// La perilla es el control universal: girar elige o ajusta, tocar ejecuta.

/// Medidas compartidas. Todo lo que se toca mide al menos `tap`.
enum Space {
    static let xs: CGFloat = 6
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let tap: CGFloat = 48
    static let stageRadius: CGFloat = 32
}

enum DeckMode: Int, CaseIterable, Identifiable {
    case pad, apps, music, screen, more
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .pad: "pad"
        case .apps: "apps"
        case .music: "música"
        case .screen: "pantalla"
        case .more: "más"
        }
    }

    var symbol: String {
        switch self {
        case .pad: "hand.point.up.left"
        case .apps: "leaf"
        case .music: "music.note"
        case .screen: "display"
        case .more: "ellipsis"
        }
    }
}

enum MoreItem: Int, CaseIterable, Identifiable {
    case photos, brightness, color, touchBar, gestures, laser, power, routines, shortcuts
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .photos: "fotos"
        case .brightness: "brillo"
        case .color: "color"
        case .touchBar: "touch bar"
        case .gestures: "gestos"
        case .laser: "láser"
        case .power: "energía"
        case .routines: "escenas"
        case .shortcuts: "atajos"
        }
    }

    var detail: String {
        switch self {
        case .photos: "tíralas al Mac como hojas"
        case .brightness: "gira la perilla"
        case .color: "el acento de la app"
        case .touchBar: "elige qué muestra en el Mac"
        case .gestures: "escritorios y Spotlight"
        case .laser: "apunta con el iPhone"
        case .power: "bloquear, suspender, despertar"
        case .routines: "varias acciones de un toque"
        case .shortcuts: "teclas del pad"
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .brightness: "sun.max"
        case .color: "paintpalette"
        case .touchBar: "rectangle.split.3x1"
        case .gestures: "hand.draw"
        case .laser: "light.beacon.max"
        case .power: "power"
        case .routines: "sparkles"
        case .shortcuts: "command"
        }
    }
}

extension MoreItem {
    /// Las opciones que tienen sentido para este Mac (sin Touch Bar, no se ofrece).
    static func visible(touchBar: Bool) -> [MoreItem] {
        allCases.filter { $0 != .touchBar || touchBar }
    }
}

/// Lo que la perilla y el escenario comparten: modo, selección y qué está abierto.
@MainActor
final class Deck: ObservableObject {
    @Published var mode: DeckMode = .pad
    @Published var appIndex = 0
    @Published var moreIndex = 0
    @Published var moreOpen: MoreItem?
    @Published var launches = 0
}

// MARK: - Raíz

struct Instrument: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @StateObject private var deck = Deck()

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Header()
                        Stage().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ControlDeck(ring: 100, knob: 100)
                        .frame(width: 330)
                }
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            } else {
                VStack(spacing: 0) {
                    Header()
                        .padding(.horizontal, Space.l)
                        .padding(.top, Space.s)
                    Stage()
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.m)
                        .frame(maxHeight: .infinity)
                    ControlDeck(ring: 124, knob: 128)
                        .frame(height: 360)
                }
            }
        }
        .environmentObject(deck)
    }
}

// MARK: - Encabezado (Órbita)

/// Lo elegido, en grande. Los avisos del Mac aparecen aquí mismo, en naranja,
/// en vez de tapar la pantalla con una pastilla.
struct Header: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tone.ember)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.interpolate)
                HStack(spacing: 6) {
                    if remote.pill != nil {
                        Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.ember)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(remote.pill ?? subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(remote.pill != nil ? Tone.ember : Tone.ink.opacity(0.55))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            StatusLED()
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35), value: title)
        .animation(.spring(duration: 0.35), value: remote.pill)
    }

    private var selectedApp: AppTile? {
        remote.apps.indices.contains(deck.appIndex) ? remote.apps[deck.appIndex] : nil
    }

    private var title: String {
        switch deck.mode {
        case .pad: return "Pad"
        case .apps: return selectedApp?.name ?? "Apps"
        case .music:
            guard let np = remote.nowPlaying else { return "Música" }
            return np.playing ? "Sonando" : "En pausa"
        case .screen: return "Pantalla"
        case .more:
            if let open = deck.moreOpen { return open.title.capitalized }
            let items = MoreItem.visible(touchBar: remote.hasTouchBar)
            return items.indices.contains(deck.moreIndex) ? items[deck.moreIndex].title.capitalized : "Más"
        }
    }

    private var subtitle: String {
        switch deck.mode {
        case .pad: return remote.macName
        case .apps:
            guard let app = selectedApp else { return "cargando el Dock…" }
            let n = remote.windows(of: app.id).count
            if !app.running { return "cerrada · toca la perilla" }
            return n == 1 ? "1 ventana · mantén para verla" : "\(n) ventanas · mantén para verlas"
        case .music:
            guard let np = remote.nowPlaying else { return "nada sonando" }
            return "\(np.source) · compártelo con ↗"
        case .screen: return remote.canCapture ? "toca la imagen para hacer clic" : "falta permiso en el Mac"
        case .more:
            if deck.moreOpen != nil { return "toca la perilla para volver" }
            let items = MoreItem.visible(touchBar: remote.hasTouchBar)
            return items.indices.contains(deck.moreIndex) ? items[deck.moreIndex].detail : ""
        }
    }
}

/// El piloto del aparato: verde si el Mac obedece, ámbar si falta un permiso.
struct StatusLED: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        let color = remote.canControl ? Tone.leaf : Tone.ember
        Button {
            Haptic.tap()
            remote.flash(remote.canControl ? "conectado a \(remote.macName)" : "falta el permiso de Accesibilidad en el Mac")
        } label: {
            Circle().fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.9), radius: 6)
                .phaseAnimator([1.0, 0.45]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 1.4) }
                .frame(width: Space.tap, height: Space.tap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(remote.canControl ? "conectado" : "falta un permiso")
    }
}

// MARK: - Escenario

/// El hueco de la cerámica: más oscuro, con un borde que lo hunde.
struct Stage: View {
    @EnvironmentObject private var deck: Deck

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Space.stageRadius, style: .continuous)
        ZStack {
            shape.fill(Tone.recess)
            Group {
                switch deck.mode {
                case .pad: PadStage()
                case .apps: VineApps()
                case .music: MusicStage()
                case .screen: ScreenPage()
                case .more: MoreStage()
                }
            }
            .id(deck.mode)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                    removal: .opacity))
            // Sombra interior: oscuro arriba, un filo de luz abajo. Se lee hundido.
            shape.strokeBorder(
                LinearGradient(colors: [.black.opacity(0.7), Tone.stroke, Tone.ink.opacity(0.10)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: deck.mode)
    }
}

// MARK: - Consola: anillo + perilla

struct ControlDeck: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    /// Radio del anillo de modos y diámetro de la perilla.
    let ring: CGFloat
    let knob: CGFloat
    @State private var idle: DispatchWorkItem?

    var body: some View {
        ZStack {
            OrbitRing(radius: ring)
            Knob(diameter: knob, value: knobValue, caption: caption,
                 onTick: tick, onPress: press)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var knobValue: Double {
        if deck.mode == .more, deck.moreOpen == .brightness { return remote.brightness ?? 0 }
        return remote.volume
    }

    private var caption: String {
        switch deck.mode {
        case .pad, .music: return "\(Int((remote.volume * 100).rounded()))"
        case .apps: return "abrir"
        case .screen: return "clic"
        case .more:
            if deck.moreOpen == .brightness { return "\(Int(((remote.brightness ?? 0) * 100).rounded()))" }
            return deck.moreOpen == nil ? "entrar" : "volver"
        }
    }

    /// Un paso de la perilla. Devuelve `false` si chocó con un tope.
    private func tick(_ step: Int) -> Bool {
        switch deck.mode {
        case .pad, .music:
            return nudge(.volume, step)
        case .apps:
            guard !remote.apps.isEmpty else { return false }
            let next = deck.appIndex + step
            guard remote.apps.indices.contains(next) else { return false }
            withAnimation(.snappy(duration: 0.3)) { deck.appIndex = next }
            return true
        case .screen:
            remote.scroll(dx: 0, dy: Double(-step) * 36)
            return true
        case .more:
            if deck.moreOpen == .brightness { return nudge(.brightness, step) }
            guard deck.moreOpen == nil else { return false }
            let n = MoreItem.visible(touchBar: remote.hasTouchBar).count
            deck.moreIndex = (deck.moreIndex + step + n) % n
            return true
        }
    }

    private func press() {
        switch deck.mode {
        case .pad, .music:
            remote.send(.media(.playPause))
        case .apps:
            guard remote.apps.indices.contains(deck.appIndex) else { return }
            remote.launch(remote.apps[deck.appIndex])
            deck.launches += 1
        case .screen:
            remote.send(.click(button: .left))
        case .more:
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                let items = MoreItem.visible(touchBar: remote.hasTouchBar)
                deck.moreOpen = deck.moreOpen == nil && items.indices.contains(deck.moreIndex) ? items[deck.moreIndex] : nil
            }
        }
    }

    /// Cada marca es un 2 %; el valor final se confirma cuando la perilla se queda quieta.
    private func nudge(_ kind: LevelKind, _ step: Int) -> Bool {
        let current = kind == .volume ? remote.volume : (remote.brightness ?? 0)
        let v = min(1, max(0, current + Double(step) * 0.02))
        guard abs(v - current) > 0.0001 else { return false }
        remote.editingLevel = true
        remote.setLevel(kind, v, final: false)
        idle?.cancel()
        let work = DispatchWorkItem {
            remote.setLevel(kind, v, final: true)
            remote.editingLevel = false
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        return true
    }
}

/// Los modos orbitan la perilla. Solo el elegido muestra su nombre; los demás
/// son botones redondos de icono, así el anillo respira.
struct OrbitRing: View {
    @EnvironmentObject private var deck: Deck
    let radius: CGFloat

    private var step: Double { 360.0 / Double(DeckMode.allCases.count) }

    var body: some View {
        ZStack {
            Circle().stroke(Tone.stroke.opacity(0.9), lineWidth: 1)
                .frame(width: radius * 2 + 48, height: radius * 2 + 48)
            ForEach(DeckMode.allCases) { m in
                let angle = (Double(m.rawValue - deck.mode.rawValue) * step - 90) * .pi / 180
                let selected = m == deck.mode
                Button { select(m) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.symbol).font(.system(size: 16, weight: .semibold))
                        if selected {
                            Text(m.label).font(.system(size: 14, weight: .bold, design: .rounded))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(selected ? Tone.onEmber : Tone.ink.opacity(0.7))
                    .padding(.horizontal, selected ? 16 : 0)
                    .frame(minWidth: Space.tap, minHeight: Space.tap)
                    .background(Capsule().fill(selected ? Tone.ember : Tone.key))
                    .overlay(Capsule().stroke(selected ? .clear : Tone.stroke, lineWidth: 1))
                    .shadow(color: selected ? Tone.ember.opacity(0.45) : .clear, radius: 12)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(m.label)
                .offset(x: cos(angle) * (radius + 24), y: sin(angle) * (radius + 24))
                .animation(.spring(duration: 0.55, bounce: 0.25), value: deck.mode)
            }
        }
        // Deslizar sobre el anillo lo gira de a un modo.
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            let dx = v.translation.width
            guard abs(dx) > 36 else { return }
            let n = DeckMode.allCases.count
            select(DeckMode(rawValue: (deck.mode.rawValue + (dx < 0 ? 1 : -1) + n) % n)!)
        })
    }

    private func select(_ m: DeckMode) {
        guard m != deck.mode else { return }
        Detents.shared.detent(speed: 0.2)
        deck.moreOpen = nil
        deck.mode = m
    }
}

/// La perilla de Brasa con el zarcillo de Enredadera en la cara.
///
/// Gira con el dedo marca a marca (20 por vuelta), y si la lanzas sigue girando
/// y frena sola. La luz no gira con ella: está pintada con un shader encima.
struct Knob: View {
    let diameter: CGFloat
    let value: Double
    let caption: String
    let onTick: (Int) -> Bool
    let onPress: () -> Void

    @State private var angle: Double = 0          // giro visual acumulado, en grados
    @State private var last: (angle: Double, time: TimeInterval)?
    @State private var velocity: Double = 0       // grados por segundo
    @State private var travel: Double = 0
    @State private var pressed = false
    @State private var presses = 0
    @State private var spin: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let detent = 18.0

    private var base: CGFloat { diameter + 28 }

    var body: some View {
        ZStack {
            // Asiento hundido en la cerámica.
            Circle().fill(Tone.recess).frame(width: base, height: base)
            Circle().strokeBorder(
                LinearGradient(colors: [.black.opacity(0.6), Tone.ink.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5)
                .frame(width: base, height: base)

            // Cuerpo: estrías y zarcillo giran; la luz se queda quieta.
            ZStack {
                Circle().fill(Tone.ember)
                ForEach(0..<40, id: \.self) { i in
                    Capsule().fill(Tone.emberDeep)
                        .frame(width: i % 2 == 0 ? 3 : 2, height: i % 10 == 0 ? 16 : (i % 2 == 0 ? 10 : 6))
                        .offset(y: -diameter / 2 + 10)
                        .rotationEffect(.degrees(Double(i) * 9))
                }
                Tendril(tightness: value)
                    .stroke(Tone.body, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            // La luz va después del giro: la perilla rota "debajo" de ella,
            // como un objeto real bajo una lámpara.
            .overlay {
                ZStack {
                    RadialGradient(colors: [.white.opacity(0.42), .clear],
                                   center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: diameter * 0.45)
                        .blendMode(.softLight)
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2)
                    Circle().fill(Tone.ember.opacity(pressed ? 0.18 : 0)).blendMode(.plusLighter)
                    Grain(opacity: 0.12).clipShape(Circle())
                }
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
            .shadow(color: Tone.ember.opacity(pressed ? 0.55 : 0.3), radius: pressed ? 26 : 16)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.45), value: pressed)
            .animation(.easeOut(duration: 0.25), value: value)

            Ripple(trigger: presses, cornerRadius: diameter / 2, color: Tone.ember)
                .frame(width: diameter, height: diameter)

            // Lectura: una placa fija en el borde inferior del asiento.
            Text(caption)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tone.ember)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Tone.body))
                .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
                .offset(y: base / 2 - 2)
                .contentTransition(.numericText())
                .animation(.snappy, value: caption)
        }
        .frame(width: base, height: base)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if !pressed { spin?.cancel(); pressed = true }
                    let c = CGPoint(x: base / 2, y: base / 2)
                    let a = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi
                    let now = v.time.timeIntervalSinceReferenceDate
                    if let l = last {
                        var d = a - l.angle
                        if d > 180 { d -= 360 }
                        if d < -180 { d += 360 }
                        travel += abs(d)
                        let dt = max(now - l.time, 1.0 / 240)
                        velocity = velocity * 0.6 + (d / dt) * 0.4
                        _ = advance(by: d)
                    }
                    last = (a, now)
                }
                .onEnded { _ in
                    pressed = false
                    last = nil
                    if travel < 8 {
                        presses += 1
                        Detents.shared.press()
                        onPress()
                    } else if abs(velocity) > 260, !reduce {
                        coast()
                    }
                    travel = 0
                }
        )
        .accessibilityElement()
        .accessibilityLabel("perilla")
        .accessibilityValue(caption)
        .accessibilityAdjustableAction { dir in
            _ = onTick(dir == .increment ? 1 : -1)
        }
        .accessibilityAction { onPress() }
    }

    /// Gira `d` grados y dispara un paso por cada marca cruzada. Si un paso
    /// choca con un tope, la perilla no sigue: se siente la pared.
    private func advance(by d: Double) -> Bool {
        let before = Int((angle / detent).rounded(.down))
        let after = Int(((angle + d) / detent).rounded(.down))
        guard after != before else { angle += d; return true }
        let dir = after > before ? 1 : -1
        for _ in 0..<abs(after - before) {
            if !onTick(dir) {
                Detents.shared.wall()
                velocity = 0
                return false
            }
            Detents.shared.detent(speed: abs(velocity) / 900)
        }
        angle += d
        return true
    }

    /// Inercia: la perilla sigue girando y frena sola, marcando cada paso.
    private func coast() {
        spin?.cancel()
        spin = Task { @MainActor in
            while !Task.isCancelled, abs(velocity) > 50 {
                try? await Task.sleep(for: .milliseconds(16))
                velocity *= 0.93
                if !advance(by: velocity / 60) { break }
            }
            velocity = 0
        }
    }
}

// MARK: - Apps: brotes en un tallo

struct VineApps: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    /// Ancho de cada brote en el tallo.
    private let cell: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let h = geo.size.height
                ScrollView(.horizontal) {
                    // Una fila real de celdas iguales: el desplazamiento sabe dónde
                    // está cada brote y puede centrarlo exacto.
                    LazyHStack(spacing: 0) {
                        ForEach(Array(remote.apps.enumerated()), id: \.offset) { i, app in
                            Bud(app: app, image: remote.icons[app.id], selected: i == deck.appIndex,
                                launches: i == deck.appIndex ? deck.launches : 0,
                                windows: remote.windows(of: app.id),
                                onWindow: { remote.send(.focusWindow(id: $0.id)); Haptic.thump() }) {
                                withAnimation(.snappy) { deck.appIndex = i }
                                remote.launch(app)
                                deck.launches += 1
                            }
                            .frame(width: cell, height: h)
                            .offset(y: Vine.lift(i, height: h))
                            .id(i)
                        }
                    }
                    .scrollTargetLayout()
                    .background(alignment: .leading) {
                        Vine(count: remote.apps.count, cell: cell, height: h)
                            .stroke(Tone.ink.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: CGFloat(remote.apps.count) * cell, height: h)
                    }
                }
                // Márgenes de medio escenario: el primer y el último brote también
                // pueden quedar al centro.
                .contentMargins(.horizontal, max(0, (geo.size.width - cell) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: selection, anchor: .center)
                .scrollIndicators(.hidden)
            }
            if remote.apps.isEmpty {
                ProgressView().tint(Tone.ember).padding(.bottom, 40)
            }
            RoutineStrip().padding(.bottom, Space.s)
        }
        .task {
            while !Task.isCancelled {
                remote.send(.listWindows)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Desplazar el tallo elige el brote que queda al centro, y la perilla
    /// mueve el tallo: son la misma selección.
    private var selection: Binding<Int?> {
        Binding(
            get: { remote.apps.isEmpty ? nil : deck.appIndex },
            set: { new in
                guard let new, new != deck.appIndex else { return }
                deck.appIndex = new
                Detents.shared.detent(speed: 0.3)
            }
        )
    }
}

/// El tallo: una onda suave que pasa por el centro de cada brote.
struct Vine: Shape {
    let count: Int
    let cell: CGFloat
    let height: CGFloat

    /// Cuánto sube o baja el brote `i` respecto de la línea media.
    static func lift(_ i: Int, height: CGFloat) -> CGFloat {
        sin(CGFloat(i) * 1.1) * height * 0.16
    }

    private func point(_ i: Int) -> CGPoint {
        CGPoint(x: cell / 2 + CGFloat(i) * cell, y: height / 2 + Vine.lift(i, height: height))
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard count > 0 else { return p }
        let first = point(0)
        p.move(to: CGPoint(x: first.x - cell, y: first.y + 34))
        var prev = p.currentPoint ?? first
        for i in 0..<count {
            let pt = point(i)
            let midX = (prev.x + pt.x) / 2
            p.addCurve(to: pt, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: pt.y))
            prev = pt
        }
        // Remate en espiral, como la punta de un zarcillo.
        let end = point(count - 1)
        p.addQuadCurve(to: CGPoint(x: end.x + 44, y: end.y - 28), control: CGPoint(x: end.x + 40, y: end.y + 8))
        p.addArc(center: CGPoint(x: end.x + 33, y: end.y - 28), radius: 11,
                 startAngle: .degrees(0), endAngle: .degrees(300), clockwise: true)
        return p
    }
}

/// Un brote: icono en una yema oscura. El elegido crece y florece.
struct Bud: View {
    let app: AppTile
    let image: UIImage?
    let selected: Bool
    let launches: Int
    let windows: [WindowInfo]
    let onWindow: (WindowInfo) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptic.thump()
            action()
        }) {
            ZStack {
                // Pétalos que se abren al elegir el brote.
                ForEach(0..<8, id: \.self) { k in
                    Ellipse()
                        .fill(Tone.ember.opacity(0.9))
                        .frame(width: 16, height: 30)
                        .offset(y: selected ? -40 : -12)
                        .rotationEffect(.degrees(Double(k) * 45))
                        .opacity(selected ? 1 : 0)
                }
                Circle().fill(Tone.body).frame(width: 64, height: 64)
                Circle().stroke(selected ? Tone.ember : Tone.stroke, lineWidth: 2).frame(width: 64, height: 64)
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).frame(width: 44, height: 44)
                }
                if app.running {
                    // Hoja: la app está abierta.
                    Ellipse().fill(Tone.leaf).frame(width: 14, height: 7)
                        .rotationEffect(.degrees(-35))
                        .offset(x: 30, y: -26)
                }
                Ripple(trigger: launches, cornerRadius: 40, color: Tone.ember)
                    .frame(width: 70, height: 70)
            }
            .scaleEffect(selected ? 1.18 : 0.9)
            .boing(launches)
            .animation(.spring(duration: 0.45, bounce: 0.4), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .contextMenu {
            Section(app.name) {
                if windows.isEmpty { Text(app.running ? "sin ventanas abiertas" : "no está abierta") }
                ForEach(windows) { w in
                    Button { onWindow(w) } label: {
                        Label(w.title, systemImage: w.minimized ? "arrow.up.right.square" : "macwindow")
                    }
                }
            }
        }
    }
}

// MARK: - Pad

struct PadStage: View {
    @EnvironmentObject private var remote: Remote
    @State private var typing = false
    @State private var shortcuts = false
    @State private var bumps = [0, 0, 0, 0]

    var body: some View {
        VStack(spacing: Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tone.body.opacity(0.55))
                Circle().fill(Tone.ember).frame(width: 6, height: 6).opacity(0.6)
                Trackpad(remote: remote)
            }

            // Cuatro teclas grabadas, con aire entre ellas.
            HStack(spacing: Space.s + 2) {
                key("keyboard", "teclado", 0) { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { typing = true } }
                key("command", "atajos", 1) { shortcuts = true }
                Menu {
                    Button { remote.pushClipboard() } label: { Label("Enviar al Mac", systemImage: "arrow.up.doc.on.clipboard") }
                    Button { remote.send(.pullClipboard) } label: { Label("Traer del Mac", systemImage: "arrow.down.doc.on.clipboard") }
                } label: {
                    keyFace("doc.on.clipboard", "portapapeles", 2)
                }
                .simultaneousGesture(TapGesture().onEnded { Haptic.tap(); bumps[2] += 1 })
                key("cursorarrow.click.2", "clic der.", 3) { remote.send(.click(button: .right)) }
            }
        }
        .padding(Space.m)
        .overlay(alignment: .bottom) {
            if typing {
                KeyboardBar(shown: $typing).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $shortcuts) {
            ShortcutSheet().environmentObject(remote)
        }
    }

    private func key(_ symbol: String, _ title: String, _ i: Int, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            bumps[i] += 1
            action()
        } label: { keyFace(symbol, title, i) }
        .buttonStyle(PressScale())
    }

    /// Tecla grabada en la cerámica.
    private func keyFace(_ symbol: String, _ title: String, _ i: Int) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: bumps[i])
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Tone.ink.opacity(0.85))
        .frame(maxWidth: .infinity).frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Tone.ink.opacity(0.14), .black.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Los atajos, en grande y con aire: una hoja que sube desde abajo.
struct ShortcutSheet: View {
    @EnvironmentObject private var remote: Remote
    @State private var editing = false
    @State private var taps: [UUID: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s + 2)], spacing: Space.s + 2) {
                    ForEach(remote.shortcuts) { s in
                        Button {
                            Detents.shared.press()
                            taps[s.id, default: 0] += 1
                            remote.send(.shortcut(s))
                        } label: {
                            VStack(spacing: 6) {
                                Text(s.glyphs).font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Tone.ember)
                                Text(s.title).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Tone.ink.opacity(0.7)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).frame(height: 88)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                            .boing(taps[s.id, default: 0], amount: 0.08)
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(Space.m)
            }
            .navigationTitle("Atajos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Editar") { ShortcutEditorPage(hidesBar: false) }
                }
            }
            .background(Tone.body)
        }
        .tint(Tone.ember)
        .presentationDetents([.medium, .large])
        .presentationBackground(Tone.body)
        .presentationCornerRadius(32)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Más: un tallo vertical

struct MoreStage: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck

    var body: some View {
        Group {
            if let open = deck.moreOpen {
                Group {
                    if open == .routines || open == .shortcuts {
                        // Estas tienen su propia barra de navegación: el botón va en una fila.
                        VStack(spacing: 0) {
                            HStack { backButton; Spacer() }.padding(Space.m)
                            page(open).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // El resto usa todo el escenario; volver flota en la esquina.
                        page(open)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .topLeading) { backButton.padding(Space.m) }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                stem.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var backButton: some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(duration: 0.4)) { deck.moreOpen = nil }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Tone.ink.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Tone.key))
                .overlay(Circle().stroke(Tone.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("volver a más")
    }

    private var stem: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(MoreItem.visible(touchBar: remote.hasTouchBar).enumerated()), id: \.element) { index, item in
                    let selected = index == deck.moreIndex
                    Button {
                        Haptic.tap()
                        deck.moreIndex = index
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.moreOpen = item }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                // El tallo pasa por detrás de cada nudo.
                                Rectangle().fill(Tone.ink.opacity(0.2)).frame(width: 3)
                                Circle().fill(selected ? Tone.ember : Tone.key).frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(Tone.stroke, lineWidth: selected ? 0 : 1))
                                Image(systemName: item.symbol).font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selected ? Tone.onEmber : Tone.ink.opacity(0.75))
                            }
                            .frame(width: 44, height: 68)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selected ? Tone.ember : Tone.ink)
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.3), value: selected)
                }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func page(_ item: MoreItem) -> some View {
        switch item {
        case .brightness:
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill").font(.system(size: 40)).foregroundStyle(Tone.ember)
                    .symbolEffect(.pulse)
                Text(remote.brightness == nil ? "este Mac no deja cambiar el brillo"
                                              : "gira la perilla para cambiar el brillo")
                    .font(.callout).foregroundStyle(Tone.ink.opacity(0.6))
            }
        case .photos: TossPage()
        case .color: ColorPage()
        case .touchBar: TouchBarPage()
        case .gestures: GesturePage()
        case .laser: LaserPage()
        case .power: PowerPage()
        case .routines: NavigationStack { RoutineList() }.tint(Tone.ember)
        case .shortcuts: NavigationStack { ShortcutEditorPage() }.tint(Tone.ember)
        }
    }
}

// MARK: - Color

/// Elegir el acento: una corola de pétalos, uno por color, y el tuyo propio al centro.
struct ColorPage: View {
    @State private var custom = Theme.shared.accent
    @State private var picks = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - Space.l * 2
            let presets = Theme.presets
            ZStack {
                ForEach(Array(presets.enumerated()), id: \.element.id) { i, p in
                    let angle = Double(i) / Double(presets.count) * 2 * .pi - .pi / 2
                    let selected = Theme.shared.hex == p.hex
                    Button {
                        Detents.shared.press()
                        picks += 1
                        withAnimation(.smooth(duration: 0.45)) { Theme.shared.set(hex: p.hex) }
                        custom = Theme.color(p.hex)
                    } label: {
                        Ellipse()
                            .fill(Theme.color(p.hex))
                            .frame(width: side * 0.15, height: side * 0.30)
                            .overlay(Ellipse().stroke(Tone.ink, lineWidth: selected ? 3 : 0))
                            .scaleEffect(selected ? 1.12 : 1)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(p.name)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: cos(angle) * side * 0.33, y: sin(angle) * side * 0.33)
                    .animation(.spring(duration: 0.4, bounce: 0.4), value: selected)
                }
                // Centro de la flor: el selector libre.
                ZStack {
                    Circle().fill(Tone.ember).frame(width: side * 0.3, height: side * 0.3)
                        .boing(picks, amount: 0.1)
                    ColorPicker("color propio", selection: $custom, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(1.5)
                }
                .onChange(of: custom) { _, c in Theme.shared.set(c) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
