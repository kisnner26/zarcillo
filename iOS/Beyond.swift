import ARKit
import SwiftUI

// MARK: - Desprender ventana

/// Eliges una ventana del Mac y se "desprende": solo ella viaja al iPhone, a
/// pantalla completa, y se usa con el dedo como si fuera una app del iPhone.
struct DetachPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var open: WindowInfo?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s)], spacing: Space.s) {
                ForEach(remote.windows.filter { !$0.minimized }) { w in
                    Button {
                        Detents.shared.press()
                        open = w
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            if let icon = remote.icons[w.appID] {
                                Image(uiImage: icon).resizable().frame(width: 40, height: 40)
                            } else {
                                Image(systemName: "macwindow").font(.system(size: 28)).foregroundStyle(Tone.ember)
                                    .frame(width: 40, height: 40)
                            }
                            Text(w.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ink)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(Space.m)
            .padding(.top, 48)
            if remote.windows.isEmpty {
                Text("sin ventanas, o falta el permiso de Accesibilidad en el Mac")
                    .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5)).padding(Space.xl)
            }
        }
        .scrollIndicators(.hidden)
        .task { remote.send(.listWindows) }
        .fullScreenCover(item: $open) { w in DetachedWindow(window: w) }
    }
}

struct DetachedWindow: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let window: WindowInfo
    @State private var zoom: CGFloat = 1
    @State private var lastScroll: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Tone.recess.ignoresSafeArea()
                LiveScreen(zoomable: true, zoomOut: $zoom) { x, y, button in
                    remote.send(.tapWindow(x: x, y: y, button: button))
                }
                .ignoresSafeArea(edges: .bottom)
                // Rueda: deslizar por el borde derecho desplaza la ventana.
                Capsule().fill(Tone.ink.opacity(0.12))
                    .frame(width: 6)
                    .padding(.vertical, 90)
                    .frame(width: 44)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            let d = v.translation.height - lastScroll
                            lastScroll = v.translation.height
                            remote.scroll(dx: 0, dy: Double(d) * 2.5)
                        }
                        .onEnded { _ in lastScroll = 0 })
                    .frame(maxHeight: .infinity)
                HStack(spacing: Space.s) {
                    Text(remote.detachedTitle ?? window.title)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.7)).lineLimit(1)
                    Button {
                        Detents.shared.press()
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Tone.onEmber)
                            .frame(width: 44, height: 44).background(Circle().fill(Tone.ember))
                    }
                    .accessibilityLabel("volver a pegar la ventana")
                }
                .padding(.leading, 14)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(Space.m)
            }
            .onAppear {
                let px = Int(max(geo.size.width, geo.size.height) * UIScreen.main.scale)
                remote.send(.detach(window: window.id, width: min(px, 2000)))
            }
        }
        .onDisappear { remote.send(.detach(window: nil, width: 0)) }
        .statusBarHidden()
    }
}

// MARK: - Mezclador

/// Un fader por app que está sonando, como una mesa de mezclas.
struct MixerPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        VStack(spacing: Space.m) {
            if remote.mixerApps.isEmpty {
                Spacer()
                Image(systemName: "slider.vertical.3").font(.system(size: 56, weight: .light)).foregroundStyle(Tone.ember)
                Text("ninguna app está sonando en el Mac").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: Space.m) {
                        ForEach(remote.mixerApps) { app in Fader(app: app) }
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minWidth: UIScreen.main.bounds.width)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 56)
            }
            Text("Cada app suena con su propio volumen; el volumen general sigue en la perilla. La primera vez, el Mac pide permiso para tomar el audio de las apps.")
                .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.45)).multilineTextAlignment(.center)
                .padding(.horizontal, Space.m).padding(.bottom, Space.m)
        }
        .task {
            while !Task.isCancelled {
                remote.send(.mixerList)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct Fader: View {
    @EnvironmentObject private var remote: Remote
    let app: MixerApp
    @State private var value: Double?
    @State private var lastSend = Date.distantPast
    private let height: CGFloat = 300

    var body: some View {
        let v = value ?? app.gain
        VStack(spacing: Space.s) {
            Text("\(Int(v * 100))").font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Tone.ink.opacity(0.7)).contentTransition(.numericText())
            ZStack(alignment: .bottom) {
                Capsule().fill(Tone.recess).frame(width: 58, height: height)
                    .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
                Capsule().fill(LinearGradient(colors: [Tone.emberDeep, Tone.ember], startPoint: .bottom, endPoint: .top))
                    .frame(width: 58, height: max(58, height * v))
                    .shadow(color: Tone.ember.opacity(0.4 * v), radius: 12)
                if let data = app.icon, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().frame(width: 40, height: 40)
                        .padding(.bottom, 9)
                        .saturation(v < 0.02 ? 0 : 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let nv = min(1, max(0, 1 - g.location.y / height))
                    if Int(nv * 20) != Int(v * 20) { Detents.shared.detent(speed: 0.2) }
                    value = nv
                    if Date().timeIntervalSince(lastSend) > 0.1 {
                        lastSend = Date()
                        remote.send(.mixerGain(pid: app.id, gain: nv))
                    }
                }
                .onEnded { _ in
                    if let value { remote.send(.mixerGain(pid: app.id, gain: value)) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { value = nil }
                })
            Text(app.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tone.ink).lineLimit(1)
                .frame(width: 80)
            Button {
                Detents.shared.press()
                let nv: Double = v < 0.02 ? 1 : 0
                value = nv
                remote.send(.mixerGain(pid: app.id, gain: nv))
            } label: {
                Image(systemName: v < 0.02 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(v < 0.02 ? Tone.onEmber : Tone.ink.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(v < 0.02 ? Tone.ember : Tone.key))
            }
            .buttonStyle(PressScale())
        }
    }
}

// MARK: - Mirada

/// El cursor del Mac sigue hacia dónde miras: la cámara frontal del iPhone
/// (la de Face ID) sigue tu cabeza y tus ojos. Guiñar un ojo hace clic.
@MainActor
final class GazeTracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var running = false
    @Published private(set) var tracked = false
    @Published private(set) var point = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var calibrating = false
    @Published private(set) var clicks = 0
    var onPoint: ((CGPoint) -> Void)?
    var onClick: (() -> Void)?
    /// Cuántos grados de giro recorren toda la pantalla.
    var reach: Double = 14
    var mirrored = false

    static var supported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var center: (yaw: Double, pitch: Double)?
    private var samples: [(Double, Double)] = []
    private var smooth = CGPoint(x: 0.5, y: 0.5)
    private var winkSince: Date?
    private var lastClick = Date.distantPast
    private var lastSend = Date.distantPast

    func start() {
        guard Self.supported else { return }
        session.delegate = self
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = false
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        running = true
        recalibrate()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        session.pause()
        running = false
        tracked = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Mira al centro de la pantalla del Mac un segundo: esa es la referencia.
    func recalibrate() {
        center = nil
        samples = []
        calibrating = true
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let transform = face.transform
        let look = face.lookAtPoint
        let tracked = face.isTracked
        let blinkL = face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0
        let blinkR = face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0
        // Dirección de la mirada: los ojos, girados con la cabeza.
        let d = transform * simd_float4(look.x, look.y, look.z, 0)
        let dir = simd_normalize(simd_float3(d.x, d.y, d.z))
        let yaw = atan2(Double(dir.x), Double(dir.z)) * 180 / .pi
        let pitch = atan2(Double(dir.y), Double(dir.z)) * 180 / .pi
        MainActor.assumeIsolated { self.update(yaw: yaw, pitch: pitch, tracked: tracked, blinkL: blinkL, blinkR: blinkR) }
    }

    private func update(yaw: Double, pitch: Double, tracked: Bool, blinkL: Double, blinkR: Double) {
        self.tracked = tracked
        guard tracked else { return }
        // Un ojo cerrado y el otro abierto: guiño. El cursor se queda quieto mientras.
        let winking = (blinkL > 0.65 && blinkR < 0.3) || (blinkR > 0.65 && blinkL < 0.3)
        if winking {
            if winkSince == nil { winkSince = Date() }
            if let since = winkSince, Date().timeIntervalSince(since) > 0.18, Date().timeIntervalSince(lastClick) > 0.8 {
                lastClick = Date()
                clicks += 1
                onClick?()
            }
            return
        }
        winkSince = nil
        if blinkL > 0.5 && blinkR > 0.5 { return }   // parpadeo normal

        if calibrating {
            samples.append((yaw, pitch))
            if samples.count >= 30 {
                let n = Double(samples.count)
                center = (samples.map(\.0).reduce(0, +) / n, samples.map(\.1).reduce(0, +) / n)
                calibrating = false
                Detents.shared.wall()
            }
            return
        }
        guard let c = center else { return }
        var dx = (yaw - c.yaw) / reach
        if !mirrored { dx = -dx }
        let dy = -(pitch - c.pitch) / (reach * 0.7)
        let target = CGPoint(x: min(1, max(0, 0.5 + dx / 2)), y: min(1, max(0, 0.5 + dy / 2)))
        // Suavizado: rápido en saltos grandes, firme cuando la mirada se detiene.
        let dist = hypot(target.x - smooth.x, target.y - smooth.y)
        let k = dist > 0.08 ? 0.35 : 0.12
        smooth = CGPoint(x: smooth.x + (target.x - smooth.x) * k, y: smooth.y + (target.y - smooth.y) * k)
        point = smooth
        if Date().timeIntervalSince(lastSend) > 1.0 / 40 {
            lastSend = Date()
            onPoint?(smooth)
        }
    }
}

struct GazePage: View {
    @EnvironmentObject private var remote: Remote
    @StateObject private var gaze = GazeTracker()
    @AppStorage("gaze.reach") private var reach = 14.0
    @AppStorage("gaze.mirrored") private var mirrored = false

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: 40)
            // Un Mac en miniatura con el punto donde miras.
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tone.recess)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                    Circle().fill(Tone.ember).frame(width: 18, height: 18)
                        .shadow(color: Tone.ember, radius: 10)
                        .position(x: gaze.point.x * geo.size.width, y: gaze.point.y * geo.size.height)
                        .opacity(gaze.running && !gaze.calibrating ? 1 : 0)
                    if gaze.calibrating && gaze.running {
                        VStack(spacing: 6) {
                            Image(systemName: "eye").font(.system(size: 26)).symbolEffect(.pulse)
                            Text("mira al centro de la pantalla del Mac").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Tone.ink.opacity(0.8))
                    }
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .padding(.horizontal, Space.m)

            if !GazeTracker.supported {
                Text("Este iPhone no tiene cámara TrueDepth (Face ID).")
                    .font(.system(size: 14)).foregroundStyle(Tone.ember)
            } else {
                WideButton(title: gaze.running ? "detener" : "mover el cursor con la mirada",
                           symbol: gaze.running ? "stop.fill" : "eye", filled: !gaze.running) {
                    gaze.running ? gaze.stop() : gaze.start()
                }
                if gaze.running {
                    HStack(spacing: Space.s) {
                        pill("recalibrar", "scope") { gaze.recalibrate() }
                        pill(mirrored ? "normal" : "invertir", "arrow.left.and.right") { mirrored.toggle(); gaze.mirrored = mirrored }
                    }
                    HStack {
                        Text("fino").font(.system(size: 12, weight: .semibold))
                        Slider(value: $reach, in: 6...24).tint(Tone.ember)
                            .onChange(of: reach) { _, r in gaze.reach = r }
                        Text("amplio").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Tone.ink.opacity(0.6))
                }
            }
            Text("Apoya el iPhone bajo la pantalla del Mac, mirándote. Guiña un ojo para hacer clic.")
                .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.45)).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Space.m)
        .onAppear {
            gaze.reach = reach
            gaze.mirrored = mirrored
            gaze.onPoint = { p in remote.send(.pointTo(x: p.x, y: p.y)) }
            gaze.onClick = {
                Detents.shared.press()
                remote.send(.click(button: .left))
            }
        }
        .onDisappear { gaze.stop() }
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            action()
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tone.ink.opacity(0.8))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Capsule().fill(Tone.key))
        }
        .buttonStyle(PressScale())
    }
}
