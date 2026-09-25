import Network
import Security
import SwiftUI
import UIKit

/// Solo guarda el código de cada Mac, bajo el nombre con que se anuncia.
enum Keychain {
    private static let service = "com.kisnner.zarcillo"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, _ account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Lo que el cerebro está haciendo con tu última orden.
enum BrainState: Equatable {
    case idle
    case thinking
    case confirm(BrainPlan)
    case done(BrainDone)
}

struct BrainDone: Equatable {
    let id: String
    let ok: Bool
    let reply: String
    let source: String
    let output: String?
    let intent: String?
}

/// Una captura de pantalla que llegó del Mac.
struct Shot: Identifiable {
    let id = UUID()
    let name: String
    let image: UIImage
    let data: Data
    let at: Date
}

@MainActor
final class Remote: ObservableObject {
    enum Phase: Equatable {
        case searching
        case choosing
        case needsCode(String)
        case connecting(String)
        case connected(String)
    }

    @Published private(set) var phase: Phase = .searching
    @Published private(set) var macs: [NWBrowser.Result] = []
    @Published private(set) var apps: [AppTile] = []
    @Published private(set) var icons: [String: UIImage] = [:]
    @Published var volume: Double = 0.5
    @Published var brightness: Double?
    @Published private(set) var canControl = true
    @Published private(set) var pill: String?
    @Published private(set) var codeError: String?
    @Published private(set) var networkDenied = false
    @Published var shortcuts: [Shortcut] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }
    @Published var routines: [Routine] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(routines), forKey: "routines")
            send(.syncRoutines(routines))
        }
    }

    @Published private(set) var nowPlaying: NowPlaying?
    /// Cuándo llegó `nowPlaying`: la barra de progreso avanza sola entre lecturas.
    @Published private(set) var nowPlayingAt = Date()
    @Published private(set) var artwork: UIImage?
    /// Colores de la carátula actual, para el póster de música.
    @Published private(set) var palette: ArtPalette?
    @Published private(set) var frame: UIImage?
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var canCapture = true
    @Published private(set) var hasTouchBar = false
    @Published var touchBar = TouchBarConfig.standard
    @Published private(set) var lights: [LightInfo] = []
    @Published var lightsAmbient = false
    @Published var lightsBrightness = 0.8
    /// La app al frente en el Mac.
    @Published private(set) var frontAppID = ""
    @Published private(set) var frontAppName = ""
    var context: AppContext? { AppContext.for(frontAppID) }
    /// Lo último cosechado del Mac, para la animación de la hoja que cae.
    @Published private(set) var harvestImage: UIImage?
    @Published private(set) var harvests = 0
    /// Hay una clase transcribiéndose: tocar la perilla marca el momento.
    @Published var transcribing = false
    @Published private(set) var knobMarks = 0
    func markFromKnob() { knobMarks += 1 }

    /// Pulsa una acción de la app del Mac; un momento después se refresca lo más usado.
    func press(_ action: DeckAction) {
        send(.pressAction(action))
    }

    func requestAppActions() { send(.requestAppActions) }

    // MARK: Cerebro

    func ask(_ text: String) {
        withAnimation(.spring(duration: 0.35)) { brain = .thinking }
        suggestions = []
        send(.ask(text: text))
    }

    func brainConfirm(_ plan: BrainPlan, ok: Bool) {
        if ok { withAnimation(.spring(duration: 0.35)) { brain = .thinking } } else { dismissBrain() }
        send(.brainConfirm(id: plan.id, ok: ok))
    }

    func brainWrong(_ intent: String) {
        send(.brainFeedback(id: intent, good: false))
        flash("lo olvidé: la próxima vez decide Claude")
        dismissBrain()
    }

    func teach(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        send(.teachStart(name: n))
    }

    func setPrivacy(_ on: Bool) {
        let d = UserDefaults.standard
        privacyOn = on
        send(.privacy(on: on, strength: d.object(forKey: "privacy.strength") as? Double ?? 0.6,
                      focus: d.bool(forKey: "privacy.focus"), onlookers: d.bool(forKey: "privacy.onlookers")))
    }

    func teachStop() { send(.teachStop) }
    func teachCancel() { send(.teachCancel) }

    func dismissBrain() { withAnimation(.easeOut(duration: 0.25)) { brain = .idle } }

    /// La tarjeta del resultado se va sola, salvo que haya algo pendiente.
    private func scheduleBrainHide(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            MainActor.assumeIsolated {
                if case .done(let d) = self?.brain, d.id == id { self?.dismissBrain() }
            }
        }
    }

    func setScreenshots(_ on: Bool) {
        screenshotsOn = on
        send(.screenshotsToPhone(on))
    }

    /// Una captura del Mac: se copia al portapapeles y/o se guarda en Fotos según lo que elijas,
    /// y cae una hoja en la pantalla.
    private func receiveShot(_ name: String, _ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let shot = Shot(name: name, image: image, data: data, at: Date())
        shots.insert(shot, at: 0)
        if shots.count > 12 { shots.removeLast(shots.count - 12) }
        let d = UserDefaults.standard
        if d.object(forKey: "shots.copy") as? Bool ?? true { UIPasteboard.general.image = image }
        if d.bool(forKey: "shots.save") { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
        showLeaf(image)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flash(d.object(forKey: "shots.copy") as? Bool ?? true ? "captura del Mac copiada" : "captura del Mac lista")
    }

    func removeShot(_ shot: Shot) { shots.removeAll { $0.id == shot.id } }

    /// Pide el permiso en el Mac: sale el aviso del sistema o se abre Ajustes allí.
    func requestPermission(_ kind: PermissionKind) {
        send(.requestPermission(kind))
        flash("mira el aviso en el Mac")
    }

    /// Los permisos que faltan (la automatización solo cuenta si se negó).
    var missingPermissions: [PermissionKind] {
        PermissionKind.allCases.filter { kind in
            guard let s = permissions[kind] else { return false }
            return PermissionEntry(kind: kind, state: s).needsAttention
        }
    }
    /// Sentir la música: cada golpe vibra en la mano.
    @Published var feelingBeats = false
    @Published private(set) var beatCount = 0
    @Published private(set) var cameraInUse = false
    @Published private(set) var postureOn = false
    @Published private(set) var slouching = false
    @Published private(set) var postureCalibrating = false
    @Published private(set) var postureSeen = false
    @Published private(set) var postureScore = 0.0
    /// Guardián de biblioteca.
    @Published private(set) var guardianOn = false
    @Published private(set) var guardianSiren = true
    @Published private(set) var alarm: GuardianAlarm?
    @Published private(set) var alarms: [GuardianAlarm] = []
    let siren = Siren()
    /// Bloqueo por cercanía.
    @Published private(set) var nearOn = false
    @Published private(set) var nearRSSI: Int?
    @Published private(set) var nearThreshold = -72
    @Published private(set) var nearLocked = false
    let beacon = PhoneBeacon()
    /// Brote invitado.
    @Published private(set) var guestURL: String?
    @Published private(set) var guestExpires: Date?
    @Published private(set) var detachedTitle: String?
    /// El cerebro (Claude + lo aprendido): lo que se ve en la tarjeta de arriba.
    @Published private(set) var brain: BrainState = .idle
    @Published private(set) var brainInfo: BrainInfo?
    /// Carga del procesador del Mac (0…1) y hasta cuándo dura la aurora de "terminó algo largo".
    @Published private(set) var cpu = 0.0
    @Published private(set) var auroraUntil = Date.distantPast
    /// Enseñar por demostración: el Mac está mirando y anotando pasos.
    @Published private(set) var teaching = false
    /// Modo privacidad del Mac y si ahora mismo hay alguien más mirando.
    @Published private(set) var privacyOn = false
    @Published private(set) var onlooker = false
    @Published private(set) var teachSteps = 0
    @Published private(set) var suggestions: [BrainSuggestion] = []
    /// Botones de la app que está al frente en el Mac (sus menús, lo esencial, lo más usado).
    @Published private(set) var appActions: AppActions?
    /// Capturas de pantalla del Mac que llegaron (la más nueva primero).
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var screenshotsOn = true
    /// Permisos de macOS que el Mac tiene dados (o no).
    @Published private(set) var permissions: [PermissionKind: PermissionState] = [:]
    /// Lo que el Mac entregó cuando el reloj pidió agarrar algo.
    var onGrabbed: ((String, String, Data?, String?) -> Void)?
    /// Órdenes que llegaron sin conexión (por ejemplo, del reloj con la app dormida): salen al conectar.
    private var outbox: [Command] = []
    @Published private(set) var mixerApps: [MixerApp] = []

    // Puntero y desplazamiento se acumulan y salen una vez por fotograma.
    private var pendingMove = CGVector.zero
    private var pendingScroll = CGVector.zero
    private var flushLink: CADisplayLink?
    private var lastInput = CACurrentMediaTime()

    /// Mientras el dedo gira el dial, lo que el Mac informa no lo pisa.
    var editingLevel = false

    private var browser: NWBrowser?
    private var channel: Channel?
    private var target: NWBrowser.Result?
    private var pillWork: DispatchWorkItem?
    private var lastLevelSend = Date.distantPast
    private var connectTimeout: DispatchWorkItem?

    init() {
        if let data = UserDefaults.standard.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = saved
        } else {
            shortcuts = Shortcut.defaults
        }
        if let data = UserDefaults.standard.data(forKey: "routines"),
           let saved = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = saved
        } else {
            routines = Routine.defaults
        }
        browse()
        // El Mac pinta el HUD y la Touch Bar con el color que elijas aquí.
        NotificationCenter.default.addObserver(forName: Theme.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.accent(hex: Int(Theme.shared.hex))) }
        }
    }

    var macName: String {
        switch phase {
        case .connected(let n), .connecting(let n), .needsCode(let n): n
        default: ""
        }
    }

    // MARK: Búsqueda

    func browse() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjour(type: ZarcilloService.type, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.found(Array(results)) } }
        }
        b.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch state {
                    case .ready: self.networkDenied = false
                    case .waiting(let e), .failed(let e):
                        // -65570 es el rechazo del permiso de red local.
                        if case .dns(let code) = e, code == -65570 { self.networkDenied = true }
                        if case .failed = state {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { self.browse() } }
                        }
                    default: break
                    }
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func name(_ r: NWBrowser.Result) -> String {
        if case let .service(name, _, _, _) = r.endpoint { return name }
        return "Mac"
    }

    private func found(_ results: [NWBrowser.Result]) {
        macs = results.sorted { name($0) < name($1) }
        guard channel == nil else { return }
        if case .needsCode(let n) = phase, macs.contains(where: { name($0) == n }) { return }
        if let known = macs.first(where: { Keychain.get(name($0)) != nil }) {
            connect(known)
        } else if macs.count == 1 {
            target = macs[0]
            phase = .needsCode(name(macs[0]))
        } else {
            phase = macs.isEmpty ? .searching : .choosing
        }
    }

    func choose(_ r: NWBrowser.Result) {
        target = r
        if Keychain.get(name(r)) != nil { connect(r) } else { phase = .needsCode(name(r)) }
    }

    func submit(code: String) {
        guard case .needsCode(let mac) = phase,
              let r = target ?? macs.first(where: { name($0) == mac }) else { return }
        Keychain.set(code, mac)
        connect(r)
    }

    func forget() {
        let mac = macName
        channel?.cancel()
        channel = nil
        Keychain.set(nil, mac)
        apps = []
        phase = .searching
        found(macs)
    }

    // MARK: Conexión

    private func connect(_ r: NWBrowser.Result) {
        let mac = name(r)
        guard let code = Keychain.get(mac) else { phase = .needsCode(mac); return }
        target = r
        channel?.cancel()
        let ch = Channel(NWConnection(to: r.endpoint, using: .zarcillo(passcode: code)))
        channel = ch
        phase = .connecting(mac)

        ch.onState = { [weak self, weak ch] state in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let ch, self.channel === ch else { return }
                    self.update(state, mac: mac)
                }
            }
        }
        ch.onData = { [weak self] data in
            // Fotogramas de la pantalla en vivo: binarios, y se decodifican aquí,
            // fuera del hilo principal, para que dibujarlos no trabe nada.
            if data.first == Fast.frame {
                guard let image = UIImage(data: data.dropFirst())?.preparingForDisplay() else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.frame = image } }
                return
            }
            guard let event = try? JSONDecoder().decode(Event.self, from: data) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        ch.start()

        // Un código incorrecto a veces no da error TLS sino un corte seco: si en
        // 6 s no hubo saludo, se trata igual.
        connectTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.channel === ch, case .connecting = self.phase else { return }
                self.wrongCode(mac)
            }
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func update(_ state: NWConnection.State, mac: String) {
        switch state {
        case .ready:
            connectTimeout?.cancel()
            codeError = nil
            phase = .connected(mac)
            UserDefaults.standard.set(mac, forKey: "lastMac")
            send(.hello(device: UIDevice.current.name))
            send(.syncRoutines(routines))
            send(.accent(hex: Int(Theme.shared.hex)))
            let queued = outbox
            outbox = []
            queued.forEach { send($0) }
        case .waiting(let error), .failed(let error):
            if case .tls = error, case .connecting = phase { wrongCode(mac); return }
            if case .failed = state { lost() }
        case .cancelled:
            lost()
        default:
            break
        }
    }

    private func wrongCode(_ mac: String) {
        channel?.cancel()
        channel = nil
        Keychain.set(nil, mac)
        codeError = "Ese código no coincide con el del Mac."
        phase = .needsCode(mac)
    }

    private func lost() {
        // Con el guardián activo, perder al Mac también es una alarma.
        if guardianOn { raise("perdí la conexión con el Mac") }
        channel?.cancel()
        channel = nil
        guard let t = target else { found(macs); return }
        phase = .connecting(name(t))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            MainActor.assumeIsolated {
                guard self.channel == nil else { return }
                if let fresh = self.macs.first(where: { self.name($0) == self.name(t) }) { self.connect(fresh) } else { self.found(self.macs) }
            }
        }
    }

    /// Al volver a la app: si la conexión se cayó mientras estaba en segundo plano, se retoma.
    func resume() {
        if channel == nil { found(macs) }
    }

    // MARK: Mensajes

    private func handle(_ event: Event) {
        switch event {
        case .welcome(_, let v, let b, let can):
            if let v { volume = v }
            brightness = b
            canControl = can
            if !can { flash("da permiso de Accesibilidad en el Mac") }
        case .apps(let list):
            apps = list
            var map: [String: UIImage] = [:]
            for a in list { map[a.id] = icons[a.id] ?? UIImage(data: a.icon) }
            icons = map
        case .levels(let v, let b):
            guard !editingLevel else { return }
            if let v { volume = v }
            if let b { brightness = b }
        case .status(let text):
            if text.contains("Accesibilidad") { canControl = false }
            flash(text)
        case .machine(let hw, let ip):
            UserDefaults.standard.set([hw ?? "", ip ?? ""], forKey: "machine::" + macName)
        case .permissions(let accessibility, let screen):
            canControl = accessibility
            canCapture = screen
        case .clipboard(let text, let image):
            if let image, let img = UIImage(data: image) {
                UIPasteboard.general.image = img
                flash("imagen del Mac copiada")
            } else if let text, !text.isEmpty {
                UIPasteboard.general.string = text
                flash("texto del Mac copiado")
            } else {
                flash("el portapapeles del Mac está vacío")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .nowPlaying(let np):
            if np?.trackID != nowPlaying?.trackID { artwork = nil; palette = nil }
            nowPlaying = np
            nowPlayingAt = Date()
        case .artwork(let id, let data):
            if id == nowPlaying?.trackID, let img = UIImage(data: data) {
                withAnimation(.smooth(duration: 0.8)) {
                    artwork = img
                    palette = ArtPalette.from(img)
                }
            }
        case .frame(let data):
            frame = UIImage(data: data)
        case .windows(let list):
            windows = list
        case .capabilities(let bar):
            hasTouchBar = bar
        case .touchBarConfig(let config):
            touchBar = config
        case .harvested(let data):
            guard let img = UIImage(data: data) else { return }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            UIPasteboard.general.image = img
            harvestImage = img
            harvests += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("guardado en Fotos y en el portapapeles")
        case .beat(let strength):
            guard feelingBeats else { return }
            Detents.shared.beat(strength)
            beatCount += 1
        case .cameraInUse(let busy):
            cameraInUse = busy
        case .postureState(let on, let bad, let calibrating, let seen, let score):
            // Al empezar a encorvarse, un toque en la mano.
            if on, bad, !slouching { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            postureOn = on
            slouching = bad
            postureCalibrating = calibrating
            postureSeen = seen
            postureScore = score
        case .guardianState(let on, let sirenOn):
            guardianOn = on
            guardianSiren = sirenOn
            siren.keepAlive(on)
        case .guardianAlert(let reason, let photo):
            let img = photo.flatMap { UIImage(data: $0) }
            IntruderLog.shared.record(reason, photo: img)
            // La foto llega después del aviso: se suma al mismo.
            if let img, let last = alarms.last, last.reason == reason, Date().timeIntervalSince(last.at) < 30 {
                alarms[alarms.count - 1].photo = img
                if alarm?.id == last.id { alarm?.photo = img }
                return
            }
            raise(reason, photo: img)
        case .nearState(let on, let rssi, let threshold, let locked):
            nearOn = on
            nearRSSI = rssi
            nearThreshold = threshold
            nearLocked = locked
            if on, let code = Keychain.get(macName) { beacon.start(token: NearBeacon.token(passcode: code)) }
            if !on { beacon.stop() }
        case .guestPass(let url, let expires):
            guestURL = url
            guestExpires = expires.map { Date(timeIntervalSince1970: $0) }
        case .appActions(let a):
            appActions = a
        case .brainThinking:
            withAnimation(.spring(duration: 0.35)) { brain = .thinking }
        case .brainPlan(let plan):
            Haptic.tap()
            withAnimation(.spring(duration: 0.35)) { brain = .confirm(plan) }
        case .brainResult(let id, let ok, let reply, let source, let output, let intent):
            UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
            withAnimation(.spring(duration: 0.35)) {
                brain = .done(BrainDone(id: id, ok: ok, reply: reply, source: source, output: output, intent: intent))
            }
            scheduleBrainHide(id)
        case .brainSuggest(let list):
            suggestions = list
        case .brainInfo(let info):
            brainInfo = info
        case .vitals(let load, let aurora):
            cpu = load
            if aurora, auroraUntil < Date() { auroraUntil = Date().addingTimeInterval(20) }
        case .privacyState(let on, let seen):
            privacyOn = on
            if seen && !onlooker { UINotificationFeedbackGenerator().notificationOccurred(.warning); flash("alguien más mira tu Mac") }
            onlooker = seen
        case .teachState(let recording, let steps, let saved):
            teaching = recording
            teachSteps = steps
            if let saved { flash("aprendí “\(saved)”"); UINotificationFeedbackGenerator().notificationOccurred(.success) }
        case .herbCard(let card):
            HerbStore.shared.complete(card)
        case .screenshotsState(let on):
            screenshotsOn = on
        case .screenshot(let name, let data):
            receiveShot(name, data)
        case .macPermissions(let list):
            permissions = Dictionary(uniqueKeysWithValues: list.map { ($0.kind, $0.state) })
        case .grabbed(let kind, let name, let data, let text):
            onGrabbed?(kind, name, data, text)
        case .detached(let title):
            detachedTitle = title
        case .mixer(let list):
            mixerApps = list
        case .tab(let url, let title):
            guard let u = URL(string: url) else { return }
            UIApplication.shared.open(u)
            flash(title.isEmpty ? "abriendo la pestaña del Mac" : title)
        case .frontApp(let id, let name):
            frontAppID = id
            frontAppName = name
        case .lights(let devices, let ambient, let brightness):
            lights = devices
            lightsAmbient = ambient
            lightsBrightness = brightness
        }
    }

    // MARK: Funciones

    func setGuardian(_ on: Bool, siren sirenOn: Bool? = nil) {
        if on { Notify.ask() }
        guardianOn = on
        if let sirenOn { guardianSiren = sirenOn }
        siren.keepAlive(on)
        send(.guardian(on: on, siren: guardianSiren))
    }

    private func raise(_ reason: String, photo: UIImage? = nil) {
        let a = GuardianAlarm(reason: reason, photo: photo, at: Date())
        alarms.append(a)
        if alarms.count > 20 { alarms.removeFirst() }
        guard alarm == nil else { return }
        withAnimation(.spring(duration: 0.3)) { alarm = a }
        siren.ring()
        Notify.now("Alguien está en tu Mac", reason)
    }

    func silenceAlarm() {
        withAnimation(.easeOut(duration: 0.25)) { alarm = nil }
        siren.stopRing(keepAlive: guardianOn)
        send(.guardianSilence)
    }

    func setNear(_ on: Bool, threshold: Int) {
        nearOn = on
        nearThreshold = threshold
        if on, let code = Keychain.get(macName) {
            beacon.start(token: NearBeacon.token(passcode: code))
        } else if !on {
            beacon.stop()
        }
        send(.proximity(on: on, threshold: threshold))
    }

    /// Copia el portapapeles del iPhone al Mac. Leerlo hace que iOS pregunte la
    /// primera vez si Zarcillo puede pegar.
    func pushClipboard() {
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image, let data = img.jpegData(compressionQuality: 0.85) {
            send(.pushClipboard(text: nil, image: data))
        } else if pb.hasStrings, let text = pb.string {
            send(.pushClipboard(text: text, image: nil))
        } else {
            flash("el portapapeles del iPhone está vacío")
        }
    }

    func windows(of appID: String) -> [WindowInfo] {
        windows.filter { $0.appID == appID }
    }

    /// Posición estimada de la canción ahora mismo.
    func position(at date: Date) -> Double {
        guard let np = nowPlaying else { return 0 }
        let elapsed = np.playing ? date.timeIntervalSince(nowPlayingAt) : 0
        return min(np.duration, np.position + elapsed)
    }

    /// Despertar el Mac. macOS ya no deja que las apps lean su dirección física,
    /// así que no hay paquete Wake-on-LAN posible: se vuelve a pedir su servicio
    /// Bonjour, y el proxy de reposo (un HomePod o Apple TV en la misma red)
    /// despierta al Mac para atenderlo. Si el Mac sí dio su dirección, se manda
    /// además el paquete clásico por si la red lo deja pasar.
    func wake() {
        let name = macName.isEmpty ? (UserDefaults.standard.string(forKey: "lastMac") ?? "") : macName
        if let info = UserDefaults.standard.stringArray(forKey: "machine::" + name), info.count == 2,
           !info[0].isEmpty, !info[1].isEmpty {
            let bytes = info[0].split(separator: ":").compactMap { UInt8($0, radix: 16) }
            if bytes.count == 6 {
                var packet = Data(repeating: 0xFF, count: 6)
                for _ in 0..<16 { packet.append(contentsOf: bytes) }
                let conn = NWConnection(host: NWEndpoint.Host(info[1]), port: 9, using: .udp)
                conn.start(queue: .main)
                for _ in 0..<3 { conn.send(content: packet, completion: .contentProcessed { _ in }) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { conn.cancel() }
            }
        }
        flash("buscando \(name.isEmpty ? "tu Mac" : name)…")
        channel?.cancel()
        channel = nil
        browse()
    }

    func send(_ command: Command) {
        channel?.send(command)
    }

    /// Como `send`, pero si aún no hay conexión la guarda y la manda al conectar.
    func deliver(_ command: Command) {
        if case .connected = phase, let channel {
            channel.send(command)
        } else {
            outbox.append(command)
            if outbox.count > 20 { outbox.removeFirst() }
            if channel == nil { found(macs) }
        }
    }

    /// Una hoja que cae en la pantalla del iPhone con esta imagen.
    func showLeaf(_ img: UIImage) {
        harvestImage = img
        harvests += 1
    }

    // MARK: Entrada rápida

    /// Suma un movimiento del puntero; sale en el próximo fotograma.
    func move(dx: Double, dy: Double) {
        pendingMove.dx += dx
        pendingMove.dy += dy
        kick()
    }

    func scroll(dx: Double, dy: Double) {
        pendingScroll.dx += dx
        pendingScroll.dy += dy
        kick()
    }

    private func kick() {
        lastInput = CACurrentMediaTime()
        guard flushLink == nil else { return }
        let link = CADisplayLink(target: LinkTarget { [weak self] in self?.flush() }, selector: #selector(LinkTarget.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        flushLink = link
    }

    private func flush() {
        if pendingMove != .zero {
            channel?.sendRaw(Fast.vector(Fast.move, pendingMove.dx, pendingMove.dy))
            pendingMove = .zero
        }
        if pendingScroll != .zero {
            channel?.sendRaw(Fast.vector(Fast.scroll, pendingScroll.dx, pendingScroll.dy))
            pendingScroll = .zero
        }
        // Medio segundo sin tocar nada: se apaga hasta el próximo movimiento.
        if CACurrentMediaTime() - lastInput > 0.5 {
            flushLink?.invalidate()
            flushLink = nil
        }
    }

    // MARK: Touch Bar

    func setTouchBar(_ config: TouchBarConfig) {
        touchBar = config
        send(.touchBar(config))
    }

    func flash(_ text: String) {
        withAnimation(.spring(duration: 0.35)) { pill = text }
        pillWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.3)) { self?.pill = nil } }
        }
        pillWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func launch(_ app: AppTile) {
        send(.launch(id: app.id))
    }

    /// El dial manda como mucho 30 cambios por segundo; el último siempre llega.
    func setLevel(_ kind: LevelKind, _ value: Double, final: Bool) {
        if kind == .volume { volume = value } else { brightness = value }
        if final || Date().timeIntervalSince(lastLevelSend) > 1.0 / 30 {
            send(.setLevel(kind: kind, value: value))
            lastLevelSend = Date()
        }
    }
}

/// `CADisplayLink` necesita un objeto de Objective-C como destino.
final class LinkTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}
