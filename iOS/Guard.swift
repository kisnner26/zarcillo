import AVFoundation
import CoreBluetooth
import CoreImage.CIFilterBuiltins
import SwiftUI
import UserNotifications

// MARK: - Sirena

/// Mientras el guardián está activo, un audio silencioso mantiene viva la app
/// en segundo plano (y con ella la conexión con el Mac). Si el Mac avisa,
/// el mismo motor pasa a sonar como sirena.
@MainActor
final class Siren {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let state = State()
    private var buzz: Timer?

    private final class State: @unchecked Sendable {
        var ringing = false
        var phase: Double = 0
        var t: Double = 0
    }

    func keepAlive(_ on: Bool) {
        if on { startEngine() } else if !state.ringing { stopEngine() }
    }

    func ring() {
        state.ringing = true
        startEngine()
        buzz?.invalidate()
        buzz = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func stopRing(keepAlive: Bool) {
        state.ringing = false
        buzz?.invalidate()
        buzz = nil
        if !keepAlive { stopEngine() }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let st = state
        let n = AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            for f in 0..<Int(frames) {
                var v: Float = 0
                if st.ringing {
                    // Dos tonos que se alternan dos veces por segundo.
                    let freq = Int(st.t * 4) % 2 == 0 ? 1320.0 : 990.0
                    st.phase += freq / rate
                    if st.phase > 1 { st.phase -= 1 }
                    v = st.phase < 0.5 ? 0.5 : -0.5
                }
                st.t += 1 / rate
                for b in buffers { b.mData?.assumingMemoryBound(to: Float.self)[f] = v }
            }
            return noErr
        }
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: format)
        node = n
        try? engine.start()
    }

    private func stopEngine() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }
}

struct GuardianAlarm: Identifiable, Equatable {
    let id = UUID()
    let reason: String
    var photo: UIImage?
    let at: Date
}

// MARK: - Faro Bluetooth

/// El iPhone se anuncia por Bluetooth para que el Mac mida qué tan cerca está.
/// Guarda la huella para seguir anunciándose aunque la app se reinicie.
final class PhoneBeacon: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager?
    private var token: Data?

    override init() {
        super.init()
        if let saved = UserDefaults.standard.data(forKey: "near.token") { start(token: saved) }
    }

    func start(token: Data) {
        self.token = token
        UserDefaults.standard.set(token, forKey: "near.token")
        if let manager, manager.state == .poweredOn {
            publish()
        } else if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
    }

    func stop() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "near.token")
        manager?.stopAdvertising()
        manager?.removeAllServices()
    }

    private func publish() {
        guard let manager, let token else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        let c = CBMutableCharacteristic(type: CBUUID(string: NearBeacon.token), properties: [.read],
                                        value: token, permissions: [.readable])
        let service = CBMutableService(type: CBUUID(string: NearBeacon.service), primary: true)
        service.characteristics = [c]
        manager.add(service)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn { publish() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: NearBeacon.service)],
                                     CBAdvertisementDataLocalNameKey: "Zarcillo"])
    }
}

// MARK: - Páginas

struct GuardianPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var pulse = false

    var body: some View {
        StagePage { side in
            Button {
                Detents.shared.press()
                remote.setGuardian(!remote.guardianOn)
            } label: {
                ZStack {
                    Circle().fill(Tone.ember.opacity(remote.guardianOn ? 0.28 : 0))
                        .frame(width: side * (pulse ? 0.92 : 0.76), height: side * (pulse ? 0.92 : 0.76)).blur(radius: 22)
                    Circle().fill(remote.guardianOn ? Tone.ember : Tone.key)
                        .frame(width: side * 0.62, height: side * 0.62)
                        .overlay(Circle().stroke(Tone.stroke, lineWidth: remote.guardianOn ? 0 : 1))
                    VStack(spacing: 6) {
                        Image(systemName: remote.guardianOn ? "lock.shield.fill" : "shield")
                            .font(.system(size: 40, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(remote.guardianOn ? "vigilando" : "activar").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(remote.guardianOn ? Tone.onEmber : Tone.ink.opacity(0.8))
                }
                .frame(width: side, height: side)
            }
            .buttonStyle(PressScale())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
        } controls: {
            ToggleCard(title: "que el Mac también suene", detail: "sirena al máximo volumen hasta que la silencies",
                       isOn: Binding(get: { remote.guardianSiren }, set: { remote.setGuardian(remote.guardianOn, siren: $0) }))
            Hint("Avisa si alguien toca el teclado o el trackpad, desenchufa el cargador, despierta la pantalla o cierra la tapa, con una foto de la cámara del Mac. El iPhone suena aunque esté bloqueado.")
            ForEach(remote.alarms.reversed()) { a in
                HStack(spacing: Space.s) {
                    if let p = a.photo {
                        Image(uiImage: p).resizable().scaledToFill().frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "exclamationmark.shield.fill").font(.system(size: 22))
                            .foregroundStyle(Tone.ember).frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.reason).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ink)
                        Text(a.at, style: .time).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(Space.s)
                .glass(18)
            }
        }
        .animation(.spring(duration: 0.4), value: remote.guardianOn)
    }
}

/// La alarma a pantalla completa: el motivo, la foto y un botón para callarla.
struct AlarmView: View {
    @EnvironmentObject private var remote: Remote
    let alarm: GuardianAlarm
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.red.opacity(flash ? 0.85 : 0.55).ignoresSafeArea()
            VStack(spacing: Space.l) {
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white).symbolEffect(.pulse)
                Text(alarm.reason).font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                if let p = alarm.photo {
                    Image(uiImage: p).resizable().scaledToFit().frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .transition(.scale.combined(with: .opacity))
                }
                Button {
                    remote.silenceAlarm()
                } label: {
                    Text("silenciar").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.red).frame(maxWidth: .infinity).frame(height: 60)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressScale())
            }
            .padding(Space.l)
        }
        .animation(.spring(duration: 0.4), value: alarm.photo != nil)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { flash = true }
        }
    }
}

struct NearPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        StagePage { side in
            radar(side)
        } controls: {
            Text(status).font(.system(size: 17, weight: .bold)).foregroundStyle(Tone.ink)
                .contentTransition(.numericText())
            WideButton(title: remote.nearOn ? "desactivar" : "bloquear al alejarme",
                       symbol: remote.nearOn ? "pause.fill" : "lock.fill", filled: !remote.nearOn) {
                remote.setNear(!remote.nearOn, threshold: remote.nearThreshold)
            }
            if remote.nearOn {
                HStack {
                    Text("cerca").font(.system(size: 12, weight: .semibold))
                    VineSlider(value: Binding(get: { Double(-remote.nearThreshold) },
                                              set: { remote.setNear(true, threshold: -Int($0)) }),
                               in: 50...95, step: 1)
                    Text("lejos").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Tone.ink.opacity(0.6))
                if let r = remote.nearRSSI {
                    Button("bloquear desde donde estoy ahora") {
                        Detents.shared.press()
                        remote.setNear(true, threshold: r - 2)
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ember).frame(height: 44)
                }
            }
            Hint("El Mac mide la señal Bluetooth de este iPhone. Si te alejas más de la raya, se bloquea; al volver se enciende la pantalla, lista para Touch ID.")
        }
        .animation(.spring(duration: 0.5), value: remote.nearRSSI)
    }

    private var status: String {
        guard remote.nearOn else { return "apagado" }
        if remote.nearLocked { return "Mac bloqueado" }
        guard let r = remote.nearRSSI else { return "buscando al Mac…" }
        return r >= remote.nearThreshold ? "cerca · \(r) dBm" : "lejos · \(r) dBm"
    }

    /// Anillos: el Mac al centro, tú como una hoja a la distancia de la señal
    /// y la raya del acento donde se bloquea.
    private func radar(_ size: CGFloat) -> some View {
        func radius(_ dbm: Int) -> CGFloat {
            let t = CGFloat(min(95, max(40, -dbm)) - 40) / 55
            return 24 + t * (size / 2 - 30)
        }
        return ZStack {
            ForEach(1..<4) { i in
                Circle().stroke(Tone.stroke, lineWidth: 1).frame(width: size * CGFloat(i) / 3, height: size * CGFloat(i) / 3)
            }
            Circle().stroke(Tone.ember, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(width: radius(remote.nearThreshold) * 2, height: radius(remote.nearThreshold) * 2)
                .opacity(remote.nearOn ? 1 : 0.2)
            Image(systemName: "laptopcomputer").font(.system(size: 22, weight: .semibold)).foregroundStyle(Tone.ink)
            if let r = remote.nearRSSI, remote.nearOn {
                Image(systemName: "leaf.fill").font(.system(size: 20))
                    .foregroundStyle(r >= remote.nearThreshold ? Tone.leaf : Tone.ember)
                    .offset(y: -radius(r))
                    .shadow(color: Tone.ember.opacity(0.5), radius: 8)
            }
        }
        .frame(width: size, height: size)
    }
}

struct GuestPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        StagePage { side in
            Group {
                if let url = remote.guestURL, let qr = QR.image(url) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .padding(side * 0.07)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Tone.ink))
                        .shadow(color: Tone.ember.opacity(0.35), radius: 24)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(systemName: "qrcode").font(.system(size: side * 0.36, weight: .light))
                        .foregroundStyle(Tone.ember)
                }
            }
            .frame(width: side, height: side)
        } controls: {
            if remote.guestURL != nil {
                Text("que tu amigo lo escanee con la cámara").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tone.ink).multilineTextAlignment(.center)
                if let exp = remote.guestExpires {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(exp.timeIntervalSince(ctx.date)))
                        Text("se marchita en \(left / 60):\(String(format: "%02d", left % 60))")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Tone.ink.opacity(0.5))
                    }
                }
                WideButton(title: "cerrar", symbol: "xmark", filled: false) { remote.send(.guest(false)) }
            } else {
                Text("Un amigo lanza fotos a tu Mac desde su teléfono, sin instalar nada.")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Tone.ink).multilineTextAlignment(.center)
                WideButton(title: "abrir brote invitado", symbol: "leaf.fill") { remote.send(.guest(true)) }
            }
            Hint("Debe estar en la misma Wi-Fi. El enlace solo acepta fotos y caduca en una hora.")
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: remote.guestURL)
    }
}

enum QR {
    static func image(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum Notify {
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func now(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .defaultCritical
        c.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
