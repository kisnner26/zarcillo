import AppKit
import ApplicationServices
import CoreMedia
import CoreImage
import ScreenCaptureKit
import SwiftUI

// MARK: - Teclado remoto

enum Typing {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Escribe texto tal cual, sin depender de la distribución del teclado: cada
    /// evento lleva los caracteres en Unicode, así que tildes, ñ y emojis salen bien.
    static func type(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 { Input.key(36, []) }   // salto de línea = Intro
            var utf16 = Array(line.utf16)
            while !utf16.isEmpty {
                // Más de ~20 unidades por evento algunas apps las truncan.
                let chunk = Array(utf16.prefix(16))
                utf16.removeFirst(chunk.count)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    e?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    static func key(named name: String) {
        _ = Input.shortcut(Shortcut(title: "", key: name))
    }
}

// MARK: - Portapapeles

enum Clipboard {
    static func set(text: String?, image: Data?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let image, let img = NSImage(data: image) {
            pb.writeObjects([img])
        } else if let text {
            pb.setString(text, forType: .string)
        }
    }

    /// Texto o imagen del portapapeles. Las imágenes grandes se achican: una
    /// captura 5K pesaría decenas de MB y no hace falta para pegarla en el iPhone.
    static func get() -> (text: String?, image: Data?) {
        let pb = NSPasteboard.general
        if let img = NSImage(pasteboard: pb), pb.string(forType: .string) == nil {
            return (nil, png(img, maxSide: 2400))
        }
        return (pb.string(forType: .string), nil)
    }

    private static func png(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Lo que suena

/// Música y Spotify se leen con AppleScript. Es la vía que Apple deja abierta:
/// el framework privado de "Ahora suena" ya no responde a apps de terceros.
/// La primera vez macOS pregunta si Zarcillo puede controlar cada app.
enum NowPlayingReader {
    private static let players: [(bundle: String, app: String, name: String, spotify: Bool)] = [
        ("com.spotify.client", "Spotify", "Spotify", true),
        ("com.apple.Music", "Music", "Música", false),
    ]

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// Solo consulta apps abiertas: preguntarle a una cerrada la abriría.
    static func read() -> NowPlaying? {
        var paused: NowPlaying?
        for p in players where isRunning(p.bundle) {
            let duration = p.spotify ? "((duration of t) / 1000)" : "(duration of t)"
            let id = p.spotify ? "(id of t)" : "((database ID of t) as text)"
            let script = """
            tell application "\(p.app)"
                if player state is stopped then return ""
                set t to current track
                set s to ASCII character 31
                return (name of t) & s & (artist of t) & s & (album of t) & s & \(duration) & s & (player position) & s & (player state as text) & s & \(id)
            end tell
            """
            guard let raw = run(script)?.stringValue, !raw.isEmpty else { continue }
            let f = raw.components(separatedBy: "\u{1F}")
            guard f.count >= 7 else { continue }
            func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            let np = NowPlaying(source: p.name, title: f[0], artist: f[1], album: f[2],
                                duration: num(f[3]), position: num(f[4]),
                                playing: f[5] == "playing", trackID: p.name + ":" + f[6])
            if np.playing { return np }
            paused = paused ?? np
        }
        return paused
    }

    static func artwork(for np: NowPlaying) -> Data? {
        if np.source == "Spotify" {
            guard let s = run(#"tell application "Spotify" to return artwork url of current track"#)?.stringValue,
                  let url = URL(string: s) else { return nil }
            return try? Data(contentsOf: url)
        }
        return run(#"tell application "Music" to return raw data of artwork 1 of current track"#)?.data
    }

    static func seek(_ seconds: Double, in np: NowPlaying) {
        let app = np.source == "Spotify" ? "Spotify" : "Music"
        _ = run(#"tell application "\#(app)" to set player position to \#(Int(seconds))"#)
    }
}

// MARK: - Láser

/// Punto de luz que flota sobre todo, sin robar clics. Se mueve con los giros
/// del iPhone y deja una estela corta.
@MainActor
final class Laser: ObservableObject {
    @Published private(set) var trail: [CGPoint] = []
    private var panel: NSPanel?
    private var position = CGPoint.zero
    private var screen: NSScreen?

    func setOn(_ on: Bool) {
        if on {
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            guard let s = screen else { return }
            let p = panel ?? makePanel()
            p.setFrame(s.frame, display: true)
            position = CGPoint(x: s.frame.width / 2, y: s.frame.height / 2)
            trail = [position]
            p.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
            trail = []
        }
    }

    func move(dx: Double, dy: Double) {
        guard let s = screen, panel?.isVisible == true else { return }
        position.x = min(s.frame.width, max(0, position.x + dx))
        position.y = min(s.frame.height, max(0, position.y + dy))
        trail.append(position)
        if trail.count > 14 { trail.removeFirst(trail.count - 14) }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = fixedHost(LaserView(laser: self))
        panel = p
        return p
    }
}

private struct LaserView: View {
    @ObservedObject var laser: Laser
    /// El láser brilla con el color del tema.
    private var hot: Color { MacTone.ember }

    var body: some View {
        Canvas { ctx, _ in
            let pts = laser.trail
            guard let head = pts.last else { return }
            for (i, p) in pts.enumerated() {
                let t = Double(i + 1) / Double(pts.count)
                let r = 3 + 7 * t
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(hot.opacity(0.35 * t)))
            }
            var glow = ctx
            glow.addFilter(.blur(radius: 14))
            glow.fill(Path(ellipseIn: CGRect(x: head.x - 26, y: head.y - 26, width: 52, height: 52)), with: .color(hot.opacity(0.9)))
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)), with: .color(hot))
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)), with: .color(.white))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pantalla en vivo

enum ScreenGrabber {
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccess() { _ = CGRequestScreenCaptureAccess() }

    /// Toque en la imagen del iPhone → clic en ese punto de la pantalla real.
    static func tap(x: Double, y: Double, button: MouseButton) {
        let b = CGDisplayBounds(CGMainDisplayID())
        let p = CGPoint(x: b.minX + b.width * min(1, max(0, x)), y: b.minY + b.height * min(1, max(0, y)))
        Input.warp(to: p)
        Input.click(button)
    }
}

/// Pantalla en vivo como un stream continuo de ScreenCaptureKit, no una foto
/// por vez: el sistema entrega un fotograma solo cuando algo cambia, ya en la
/// resolución pedida, y la compresión a JPEG va en su propia cola.
final class ScreenStream: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "zarcillo.screen", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private(set) var width = 0
    private(set) var window: String?
    /// Se llama en la cola del stream con cada JPEG listo.
    var onFrame: ((Data) -> Void)?

    /// Toda la pantalla, o solo una ventana (`window` es el id de `Windows`).
    func start(width: Int, window: String? = nil) async {
        guard width != self.width || window != self.window || stream == nil else { return }
        await stop()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
            else { return }
            let cfg = SCStreamConfiguration()
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: width > 1200 ? 24 : 20)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = true
            cfg.queueDepth = 3
            let filter: SCContentFilter
            if let window, let target = Windows.frame(window),
               let w = Self.match(target, in: content.windows) {
                filter = SCContentFilter(desktopIndependentWindow: w)
                cfg.width = width
                cfg.height = min(2400, Int(Double(width) * w.frame.height / max(w.frame.width, 1)))
                cfg.showsCursor = false
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
                cfg.width = width
                cfg.height = Int(Double(width) * Double(display.height) / Double(max(display.width, 1)))
            }
            let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await s.startCapture()
            stream = s
            self.width = width
            self.window = window
        } catch {
            stream = nil
            self.width = 0
        }
    }

    func stop() async {
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        width = 0
        window = nil
    }

    /// La ventana de ScreenCaptureKit que corresponde a la de Accesibilidad:
    /// misma app y casi el mismo marco.
    private static func match(_ t: (pid: pid_t, frame: CGRect, title: String), in windows: [SCWindow]) -> SCWindow? {
        let mine = windows.filter { $0.owningApplication?.processID == t.pid && $0.windowLayer == 0 }
        return mine.first { abs($0.frame.minX - t.frame.minX) < 6 && abs($0.frame.minY - t.frame.minY) < 6
            && abs($0.frame.width - t.frame.width) < 6 }
            ?? mine.first { $0.title == t.title && !t.title.isEmpty }
            ?? mine.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = buffer.imageBuffer else { return }
        // Los fotogramas "sin cambios" no traen imagen nueva: no se mandan.
        if let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) != .complete { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let jpeg = context.jpegRepresentation(
            of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5])
        else { return }
        onFrame?(jpeg)
    }
}

// MARK: - Ventanas

/// Las ventanas se leen con la API de Accesibilidad: da los títulos sin pedir
/// grabación de pantalla, y permite traer al frente una ventana concreta.
enum Windows {
    private static func axWindows(_ pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func list() -> [WindowInfo] {
        guard Input.isTrusted else { return [] }
        var out: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier else { continue }
            for (i, w) in axWindows(app.processIdentifier).enumerated() {
                let subrole: String? = attr(w, kAXSubroleAttribute)
                guard subrole == nil || subrole == (kAXStandardWindowSubrole as String) else { continue }
                let title: String = attr(w, kAXTitleAttribute) ?? ""
                let minimized: Bool = attr(w, kAXMinimizedAttribute) ?? false
                out.append(WindowInfo(id: "\(app.processIdentifier):\(i)", appID: bundle,
                                      title: title.isEmpty ? (app.localizedName ?? "ventana") : title,
                                      minimized: minimized))
            }
        }
        return out
    }

    /// Dónde está la ventana ahora, en coordenadas globales (origen arriba a la izquierda).
    static func frame(_ id: String) -> (pid: pid_t, frame: CGRect, title: String)? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let pid = pid_t(parts[0]), let index = Int(parts[1]) else { return nil }
        let wins = axWindows(pid)
        guard wins.indices.contains(index) else { return nil }
        let w = wins[index]
        var pos = CGPoint.zero, size = CGSize.zero
        if let v: AXValue = attr(w, kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &pos) }
        if let v: AXValue = attr(w, kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &size) }
        guard size.width > 0 else { return nil }
        return (pid, CGRect(origin: pos, size: size), attr(w, kAXTitleAttribute) ?? "")
    }

    @discardableResult
    static func focus(_ id: String) -> String? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let pid = pid_t(parts[0]), let index = Int(parts[1]),
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let wins = axWindows(pid)
        guard wins.indices.contains(index) else { return nil }
        let w = wins[index]
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let url = app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        return attr(w, kAXTitleAttribute)
    }
}

// MARK: - Energía

enum Power {
    private typealias LockFn = @convention(c) () -> Int32

    static func perform(_ action: PowerAction) {
        switch action {
        case .lock:
            // `SACLockScreenImmediate` es lo que usa el menú  › Bloquear pantalla.
            if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
               let sym = dlsym(h, "SACLockScreenImmediate") {
                _ = unsafeBitCast(sym, to: LockFn.self)()
            } else {
                _ = Input.shortcut(Shortcut(title: "", key: "q", command: true, control: true))
            }
        case .sleep:
            pmset("sleepnow")
        case .displayOff:
            pmset("displaysleepnow")
        }
    }

    private static func pmset(_ arg: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = [arg]
        try? p.run()
    }

    static func runShortcut(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }

    /// Dirección física e IP con las que el Mac está en la red, para despertarlo
    /// desde el iPhone.
    ///
    /// Desde macOS 26 las apps reciben 02:00:00:00:00:00 en vez de la dirección
    /// real (por privacidad), así que casi siempre vuelve `nil`; el iPhone
    /// despierta el Mac pidiendo su servicio Bonjour, no con Wake-on-LAN.
    static func machine() -> (hardware: String?, ip: String?) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        p.arguments = ["en0"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return (nil, nil) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var hardware: String?, ip: String?
        for line in out.split(separator: "\n") {
            // Las líneas de ifconfig empiezan con tabulación.
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            if parts[0] == "ether" { hardware = parts[1] }
            if parts[0] == "inet" { ip = parts[1] }
        }
        // Una app no ve la dirección real: macOS devuelve esta, que no sirve.
        if hardware == "02:00:00:00:00:00" { hardware = nil }
        return (hardware, ip)
    }
}

// MARK: - Cosechar

extension ScreenGrabber {
    /// Un recorte de la pantalla principal en resolución completa. Las
    /// coordenadas vienen de 0 a 1 sobre la imagen que ve el iPhone.
    static func region(x: Double, y: Double, w: Double, h: Double) async -> Data? {
        guard allowed else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
            else { return nil }
            let dw = Double(display.width), dh = Double(display.height)
            let rect = CGRect(x: x * dw, y: y * dh, width: max(4, w * dw), height: max(4, h * dh))
            let scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = rect
            cfg.width = Int(rect.width * scale)
            cfg.height = Int(rect.height * scale)
            cfg.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }
}

// MARK: - Apuntes escaneados

import PDFKit
import Vision

/// Guarda páginas escaneadas (pizarra, proyector, cuaderno) como un PDF por
/// escaneo, en Documentos › Zarcillo › Apuntes › fecha, con el texto
/// reconocido al lado para que Spotlight lo encuentre.
enum NotesArchive {
    static func save(_ pages: [Data]) -> URL? {
        let images = pages.compactMap { NSImage(data: $0) }
        guard !images.isEmpty else { return nil }
        let day = DateFormatter(), hour = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        hour.dateFormat = "HH.mm"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Zarcillo/Apuntes/\(day.string(from: Date()))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("apuntes \(hour.string(from: Date())).pdf")

        let pdf = PDFDocument()
        for (i, img) in images.enumerated() {
            if let page = PDFPage(image: img) { pdf.insert(page, at: i) }
        }
        pdf.write(to: url)

        // Texto reconocido, en un .txt al lado: Spotlight lo indexa.
        var text = ""
        for (i, data) in pages.enumerated() {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US"]
            try? VNImageRequestHandler(data: data).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            text += "— página \(i + 1) —\n" + lines.joined(separator: "\n") + "\n\n"
        }
        try? text.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        return url
    }
}
