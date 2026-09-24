import AppKit
import AVFoundation
import SwiftUI
import Vision

/// Modo privacidad: un filtro "antiespía" hecho por software. Oscurece los
/// costados de la pantalla (lo que ve quien mira de lado), le pone una trama de
/// láminas finas como la de un filtro real, puede dejar clara solo la zona del
/// cursor y, si la cámara ve a una segunda persona, tapa la pantalla con un velo.
/// No cambia el ángulo físico del panel: eso solo lo hace un filtro de verdad.
@MainActor
final class PrivacyShield {
    fileprivate final class Model: ObservableObject {
        @Published var on = false
        @Published var strength = 0.6
        @Published var focus = false
        @Published var onlooker = false
        @Published var mouse: CGPoint = .zero   // en coordenadas de la vista, origen arriba a la izquierda
    }

    fileprivate let model = Model()
    private var panels: [NSPanel] = []
    private var tracker: Timer?
    private let watcher = OnlookerWatch()
    var onChange: ((Bool, Bool) -> Void)?

    var isOn: Bool { model.on }
    /// La cámara la está usando el velo: no es una videollamada.
    var usingCamera: Bool { watcher.usingCamera }

    init() {
        watcher.onChange = { [weak self] seen in
            guard let self else { return }
            withAnimation(.easeInOut(duration: seen ? 0.25 : 0.6)) { self.model.onlooker = seen }
            self.onChange?(self.model.on, seen)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.model.on == true { self?.layout() } }
        }
    }

    func set(on: Bool, strength: Double, focus: Bool, onlookers: Bool) {
        model.strength = min(1, max(0.1, strength))
        model.focus = focus
        if on {
            if !model.on { layout() }
            withAnimation(.easeInOut(duration: 0.6)) { model.on = true }
            startTracking()
        } else if model.on {
            withAnimation(.easeInOut(duration: 0.5)) { model.on = false }
            tracker?.invalidate(); tracker = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.model.on else { return }
                self.panels.forEach { $0.orderOut(nil) }
            }
        }
        if on && onlookers { watcher.start() } else {
            watcher.stop()
            model.onlooker = false
        }
        onChange?(model.on, model.onlooker)
    }

    /// Un panel por pantalla, por encima de todo (también la barra de menús) y sin robar clics.
    private func layout() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            // No sale en capturas ni en la pantalla que ve el iPhone.
            p.sharingType = .none
            let host = fixedHost(ShieldView(model: model, screen: screen.frame))
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            host.autoresizingMask = [.width, .height]
            p.contentView = host
            p.setFrame(screen.frame, display: false)
            p.orderFrontRegardless()
            return p
        }
    }

    /// El cursor, solo si hace falta (foco): 60 veces por segundo, barato.
    private func startTracking() {
        tracker?.invalidate()
        tracker = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.focus else { return }
                let m = NSEvent.mouseLocation
                if m != self.model.mouse { self.model.mouse = m }
            }
        }
    }
}

private struct ShieldView: View {
    @ObservedObject var model: PrivacyShield.Model
    let screen: CGRect

    var body: some View {
        GeometryReader { geo in
            let s = model.strength
            let w = geo.size.width
            ZStack {
                // Costados: lo que un filtro real le quita a quien mira de lado.
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.78 * s), location: 0),
                    .init(color: .black.opacity(0.42 * s), location: 0.12),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.66),
                    .init(color: .black.opacity(0.42 * s), location: 0.88),
                    .init(color: .black.opacity(0.78 * s), location: 1),
                ], startPoint: .leading, endPoint: .trailing)

                // Trama de láminas verticales, muy fina: el aspecto del filtro.
                Canvas { ctx, size in
                    var x = 0.0
                    var lines = Path()
                    while x < size.width {
                        lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                        x += 3
                    }
                    ctx.fill(lines, with: .color(.black.opacity(0.07 * s)))
                }
                .drawingGroup()

                // Un brillo oblicuo casi imperceptible, como el reflejo de la lámina.
                LinearGradient(colors: [.clear, .white.opacity(0.025 * s), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)

                // Foco: solo la zona del cursor queda clara, con borde suave.
                if model.focus {
                    let p = CGPoint(x: model.mouse.x - screen.minX, y: screen.maxY - model.mouse.y)
                    let r = max(w * 0.2, 240)
                    Canvas { ctx, size in
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.6 * s)))
                        ctx.blendMode = .destinationOut
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                                        .init(color: .clear, location: 1)]),
                                                       center: p, startRadius: 0, endRadius: r))
                    }
                    .transition(.opacity)
                }

                if model.onlooker { OnlookerVeil().transition(.opacity) }
            }
            .opacity(model.on ? 1 : 0)
        }
        .ignoresSafeArea()
    }
}

/// Se tapa todo cuando hay alguien más mirando.
private struct OnlookerVeil: View {
    var body: some View {
        ZStack {
            VisualBlur()
            Color.black.opacity(0.45)
            VStack(spacing: 14) {
                Image(systemName: "eye.slash.fill").font(.system(size: 54, weight: .semibold)).foregroundStyle(MacTone.ember)
                Text("alguien más está mirando").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(MacTone.ink)
                Text("la pantalla vuelve cuando se vaya").font(.system(size: 15)).foregroundStyle(MacTone.ink.opacity(0.6))
            }
        }
    }
}

private struct VisualBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Cuenta caras con la cámara del Mac, dos veces por segundo. Dos o más un par
/// de lecturas seguidas = alguien más mira; se quita tras unos segundos sin verla.
final class OnlookerWatch: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "zarcillo.onlooker")
    private var lastFrame = Date.distantPast
    private var hits = 0
    private var lastSeen = Date.distantPast
    private var seen = false
    private var running = false
    /// Hasta cuándo se considera nuestra la cámara: tarda unos segundos en figurar como libre.
    private var releasedAt = Date.distantPast
    var onChange: ((Bool) -> Void)?

    var usingCamera: Bool { running || Date().timeIntervalSince(releasedAt) < 4 }

    func start() {
        guard !running else { return }
        running = true
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { self.running = false; return }
            self.queue.async {
                if self.session.inputs.isEmpty {
                    self.session.sessionPreset = self.session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
                    guard let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam),
                          self.session.canAddInput(input) else { return }
                    self.session.addInput(input)
                    let out = AVCaptureVideoDataOutput()
                    out.alwaysDiscardsLateVideoFrames = true
                    out.setSampleBufferDelegate(self, queue: self.queue)
                    if self.session.canAddOutput(out) { self.session.addOutput(out) }
                }
                self.session.startRunning()
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        releasedAt = Date()
        queue.async {
            self.session.stopRunning()
            self.hits = 0
            self.update(false)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) > 0.45, let px = buffer.imageBuffer else { return }
        lastFrame = now
        let req = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: px).perform([req])
        // Caras pequeñas lejísimos no cuentan; una persona detrás del hombro sí.
        let faces = (req.results ?? []).filter { $0.boundingBox.height > 0.08 }.count
        if faces >= 2 { hits += 1; if hits >= 2 { lastSeen = now; update(true) } } else { hits = 0 }
        if seen, now.timeIntervalSince(lastSeen) > 3 { update(false) }
    }

    private func update(_ v: Bool) {
        guard v != seen else { return }
        seen = v
        DispatchQueue.main.async { self.onChange?(v) }
    }
}
