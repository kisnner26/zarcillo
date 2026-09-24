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
        VStack(spacing: Space.l) {
            Spacer()
            Button {
                Detents.shared.press()
                manual = true
            } label: {
                ZStack {
                    Circle().fill(Color(red: 1, green: 0.88, blue: 0.7)).frame(width: 130, height: 130)
                        .shadow(color: Color(red: 1, green: 0.85, blue: 0.6).opacity(0.7), radius: 30)
                    VStack(spacing: 4) {
                        Image(systemName: "light.max").font(.system(size: 32, weight: .semibold))
                        Text("encender").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black.opacity(0.7))
                }
            }
            .buttonStyle(PressScale())
            Toggle(isOn: $auto) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("encender sola en videollamadas").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink)
                    Text("cuando una app use la cámara del Mac")
                        .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
                }
            }
            .tint(Tone.ember)
            .padding(.horizontal, Space.m).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
            Text("Apoya el iPhone detrás del Mac, mirándote. Su pantalla hará de luz suave.")
                .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5)).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Space.m)
        .fullScreenCover(isPresented: $manual) { CallLight(shown: $manual) }
    }
}

// MARK: - Postura

struct PosturePage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            ZStack {
                Circle().fill(remote.postureOn ? (remote.slouching ? Tone.ember : Tone.leaf).opacity(0.25) : .clear)
                    .frame(width: 180, height: 180).blur(radius: 20)
                Image(systemName: remote.slouching ? "figure.fall" : "figure.stand")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(remote.postureOn ? (remote.slouching ? Tone.ember : Tone.leaf) : Tone.ink.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(!remote.postureOn ? "apagado" : (remote.slouching ? "te estás encorvando" : "buena postura"))
                .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
            WideButton(title: remote.postureOn ? "dejar de vigilar" : "vigilar mi postura",
                       symbol: remote.postureOn ? "pause.fill" : "figure.stand",
                       filled: !remote.postureOn) {
                remote.send(.posture(!remote.postureOn))
            }
            Text("Usa la cámara del Mac dos veces por segundo, en baja resolución, sin guardar imágenes. Los primeros segundos siéntate derecho: es tu referencia. Si pasas un minuto encorvado, el Mac te avisa.")
                .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.45)).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Space.m)
        .animation(.spring(duration: 0.4), value: remote.slouching)
    }
}
