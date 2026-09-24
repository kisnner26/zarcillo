import AVFoundation
import CoreMotion
import SwiftUI

// MARK: - Soplar

/// Detecta un soplido en el micrófono: sonido fuerte y sostenido un momento.
/// Hablar no lo dispara; soplar de cerca, sí.
@MainActor
final class BlowDetector: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var level: Double = 0
    var onBlow: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var loudSince: Date?
    private var cooldown = Date.distantPast

    func start() async {
        guard !listening, await AVAudioApplication.requestRecordPermission() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blow.caf")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        listening = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        recorder?.stop()
        recorder = nil
        listening = false
        level = 0
    }

    private func sample() {
        guard let r = recorder else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)      // -160…0
        level = Double(max(0, min(1, (db + 50) / 50)))
        let now = Date()
        if db > -12 {
            if loudSince == nil { loudSince = now }
            if let since = loudSince, now.timeIntervalSince(since) > 0.3, now > cooldown {
                cooldown = now.addingTimeInterval(1.5)
                loudSince = nil
                onBlow?()
            }
        } else {
            loudSince = nil
        }
    }
}

struct BlowCard: View {
    @EnvironmentObject private var remote: Remote
    @StateObject private var blow = BlowDetector()
    @State private var blows = 0

    var body: some View {
        Button {
            Detents.shared.press()
            if blow.listening { blow.stop() } else {
                blow.onBlow = {
                    blows += 1
                    Detents.shared.wall()
                    remote.send(.blow)
                }
                Task { await blow.start() }
            }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "wind").font(.system(size: 16, weight: .bold))
                    .symbolEffect(.bounce, value: blows)
                Text(blow.listening ? "sopla al micrófono" : "soplar").font(.system(size: 13, weight: .semibold))
                if blow.listening {
                    Capsule().fill(Tone.ember).frame(width: 40 * blow.level + 4, height: 4)
                }
            }
            .foregroundStyle(blow.listening ? Tone.onEmber : Tone.ink.opacity(0.8))
            .padding(.horizontal, 14).frame(height: 44)
            .background(Capsule().fill(blow.listening ? Tone.ember : Tone.key))
        }
        .buttonStyle(PressScale())
        .onDisappear { blow.stop() }
    }
}

// MARK: - Brújula de ventanas

/// Las ventanas del Mac en un arco a tu alrededor: giras el iPhone como una
/// linterna y la ventana que apuntas se enciende. Un toque la trae al frente.
struct CompassPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var heading: Double = 0
    @State private var origin: Double?
    @State private var selected = 0
    private let motion = CMMotionManager()

    var body: some View {
        let windows = remote.windows
        GeometryReader { geo in
            ZStack {
                // El haz de la linterna.
                Circle()
                    .trim(from: 0.40, to: 0.60)
                    .fill(RadialGradient(colors: [Tone.ember.opacity(0.35), .clear], center: .center,
                                         startRadius: 0, endRadius: geo.size.width * 0.7))
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.width * 1.4, height: geo.size.width * 1.4)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.9)
                ForEach(Array(windows.enumerated()), id: \.element.id) { i, w in
                    let n = max(windows.count - 1, 1)
                    let angle = -70.0 + 140.0 * Double(i) / Double(n)
                    let on = i == selected
                    VStack(spacing: 4) {
                        if let icon = remote.icons[w.appID] {
                            Image(uiImage: icon).resizable().frame(width: on ? 46 : 32, height: on ? 46 : 32)
                        }
                        Text(w.title).font(.system(size: on ? 13 : 10, weight: .semibold))
                            .foregroundStyle(on ? Tone.ember : Tone.ink.opacity(0.5))
                            .lineLimit(1).frame(maxWidth: 110)
                    }
                    .scaleEffect(on ? 1.15 : 1)
                    .shadow(color: on ? Tone.ember.opacity(0.7) : .clear, radius: 12)
                    .position(x: geo.size.width / 2 + sin(angle * .pi / 180) * geo.size.width * 0.38,
                              y: geo.size.height * 0.62 - cos(angle * .pi / 180) * geo.size.height * 0.42)
                    .animation(.spring(duration: 0.3, bounce: 0.35), value: selected)
                }
                if windows.isEmpty {
                    Text("sin ventanas abiertas, o falta el permiso de Accesibilidad en el Mac")
                        .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5))
                        .multilineTextAlignment(.center).padding(Space.xl)
                } else {
                    VStack {
                        Spacer()
                        Text("gira el iPhone para apuntar · toca para traerla")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Tone.ink.opacity(0.45))
                            .padding(.bottom, Space.l)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                guard windows.indices.contains(selected) else { return }
                Detents.shared.press()
                remote.send(.focusWindow(id: windows[selected].id))
            }
        }
        .onAppear { start() }
        .onDisappear { motion.stopDeviceMotionUpdates() }
        .task {
            while !Task.isCancelled {
                remote.send(.listWindows)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let yaw = data?.attitude.yaw else { return }
            let deg = yaw * 180 / .pi
            if origin == nil { origin = deg }
            var d = (origin ?? 0) - deg
            while d > 180 { d -= 360 }
            while d < -180 { d += 360 }
            let windows = remote.windows
            guard !windows.isEmpty else { return }
            let n = max(windows.count - 1, 1)
            let idx = Int(((min(70, max(-70, d)) + 70) / 140 * Double(n)).rounded())
            if idx != selected {
                selected = idx
                Detents.shared.detent(speed: 0.2)
            }
        }
    }
}

// MARK: - Luz para videollamadas

/// La pantalla del iPhone como panel de luz cálida para iluminarte la cara.
struct CallLight: View {
    @Binding var shown: Bool
    @AppStorage("light.intensity") private var intensity = 0.9
    @AppStorage("light.warmth") private var warmth = 0.5
    @State private var previous: CGFloat = 0.5

    private var color: Color {
        // De blanco neutro a cálido.
        Color(red: 1, green: 0.96 - warmth * 0.16, blue: 0.92 - warmth * 0.42)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            color.opacity(0.35 + intensity * 0.65).ignoresSafeArea()
            VStack(spacing: Space.s) {
                slider("intensidad", "sun.max.fill", $intensity)
                slider("calidez", "flame.fill", $warmth)
                Button("apagar luz") {
                    Detents.shared.press()
                    shown = false
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
                .frame(height: 44)
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.35)))
            .padding(Space.m)
        }
        .statusBarHidden()
        .onAppear {
            previous = screen?.brightness ?? 0.5
            screen?.brightness = 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            screen?.brightness = previous
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }

    private func slider(_ title: String, _ symbol: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).foregroundStyle(.black.opacity(0.55)).frame(width: 24)
            Slider(value: value, in: 0...1).tint(.black.opacity(0.5))
        }
        .accessibilityLabel(title)
    }
}

struct CallLightPage: View {
    @EnvironmentObject private var remote: Remote
    @AppStorage("light.auto") private var auto = true
    @State private var manual = false

    var body: some View {
        StagePage { side in
            Button {
                Detents.shared.press()
                manual = true
            } label: {
                ZStack {
                    Circle().fill(Color(red: 1, green: 0.88, blue: 0.7)).frame(width: side * 0.6, height: side * 0.6)
                        .shadow(color: Color(red: 1, green: 0.85, blue: 0.6).opacity(0.7), radius: 30)
                    VStack(spacing: 4) {
                        Image(systemName: "light.max").font(.system(size: 32, weight: .semibold))
                        Text("encender").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black.opacity(0.7))
                }
                .frame(width: side, height: side)
            }
            .buttonStyle(PressScale())
        } controls: {
            ToggleCard(title: "encender sola en videollamadas", detail: "cuando otra app use la cámara del Mac", isOn: $auto)
            Hint("Apoya el iPhone detrás del Mac, mirándote. Su pantalla hará de luz suave.")
        }
        .fullScreenCover(isPresented: $manual) { CallLight(shown: $manual) }
    }
}

// MARK: - Postura

struct PosturePage: View {
    @EnvironmentObject private var remote: Remote

    private var tint: Color {
        guard remote.postureOn else { return Tone.ink.opacity(0.4) }
        if !remote.postureSeen || remote.postureCalibrating { return Tone.ink.opacity(0.7) }
        return remote.slouching ? Tone.ember : Tone.leaf
    }

    private var status: String {
        guard remote.postureOn else { return "apagado" }
        if !remote.postureSeen { return "no te veo: ponte frente al Mac" }
        if remote.postureCalibrating { return "siéntate derecho un momento…" }
        return remote.slouching ? "te estás encorvando" : "buena postura"
    }

    var body: some View {
        StagePage { side in
            ZStack {
                Circle().fill(remote.postureOn ? tint.opacity(0.22) : .clear)
                    .frame(width: side * 0.8, height: side * 0.8).blur(radius: 20)
                // Medidor: el arco se llena a medida que te alejas de tu postura de referencia.
                Circle().stroke(Tone.stroke, lineWidth: 6).frame(width: side * 0.66, height: side * 0.66)
                Circle().trim(from: 0, to: remote.postureOn && !remote.postureCalibrating ? min(1, remote.postureScore) : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: side * 0.66, height: side * 0.66)
                    .animation(.spring(duration: 0.5), value: remote.postureScore)
                if remote.postureCalibrating && remote.postureOn {
                    Circle().trim(from: 0, to: 0.25)
                        .stroke(Tone.ink.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: side * 0.66, height: side * 0.66)
                        .rotationEffect(.degrees(remote.postureCalibrating ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: remote.postureCalibrating)
                }
                Image(systemName: !remote.postureSeen && remote.postureOn ? "person.fill.questionmark"
                      : remote.slouching ? "figure.fall" : "figure.stand")
                    .font(.system(size: side * 0.24, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: side, height: side)
        } controls: {
            Text(status)
                .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            WideButton(title: remote.postureOn ? "dejar de vigilar" : "vigilar mi postura",
                       symbol: remote.postureOn ? "pause.fill" : "figure.stand",
                       filled: !remote.postureOn) {
                remote.send(.posture(!remote.postureOn))
            }
            if remote.postureOn {
                Button {
                    Detents.shared.press()
                    remote.send(.posture(true))   // estando encendido, vuelve a tomar la referencia
                } label: {
                    Label("tomar mi postura de nuevo", systemImage: "scope")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ember)
                        .frame(height: 44)
                }
            }
            Hint("La cámara del Mac mira tu cara dos veces por segundo, sin guardar imágenes. Al empezar, siéntate derecho: esa es tu referencia. El iPhone vibra cuando te encorvas y, si sigues así 20 segundos, el Mac te avisa.")
        }
        .animation(.spring(duration: 0.4), value: remote.slouching)
        .animation(.spring(duration: 0.4), value: remote.postureSeen)
    }
}
