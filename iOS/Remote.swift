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
