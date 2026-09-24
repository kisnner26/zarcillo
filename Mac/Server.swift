import AppKit
import Network

@MainActor
final class Server: ObservableObject {
    @Published private(set) var passcode: String
    @Published private(set) var devices: [String] = []
    @Published private(set) var canControl = Input.isTrusted
    @Published private(set) var listening = false
    @Published private(set) var problem: String?

    @Published private(set) var canCapture = ScreenGrabber.allowed

    let hud = HUD()
    let laser = Laser()
    let photos = PhotoDrop()
    let macName = Host.current().localizedName ?? "Mac"

    /// Clientes que están mirando la pantalla en vivo.
    /// Quién mira la pantalla en vivo y con qué ancho.
    private var watchers: [ObjectIdentifier: Int] = [:]
    /// Fotograma en camino por cliente: si la Wi-Fi no dio abasto con el
    /// anterior, el nuevo se descarta en vez de encolarse (menos retraso).
    private var inFlight: Set<ObjectIdentifier> = []
    private let screen = ScreenStream()
    /// AppleScript tarda decenas de ms: va en su propia cola para no frenar el puntero.
    private let musicQueue = DispatchQueue(label: "zarcillo.music")
    private var nowPlaying: NowPlaying?
    private var artworkSent: String?
    private var artworkTrack: String?

    /// Lo que la Touch Bar muestra por su cuenta.
    var currentTrack: NowPlaying? { nowPlaying }
    private(set) var currentArtwork: NSImage?
    /// Las escenas que armaste en el iPhone; el Mac guarda una copia para la Touch Bar.
    private(set) var routines: [Routine] = {
        guard let d = UserDefaults.standard.data(forKey: "routines"),
              let list = try? JSONDecoder().decode([Routine].self, from: d) else { return [] }
        return list
    }()
    private var touchBar: TouchBarController?
    private var routineTask: Task<Void, Never>?

    private var listener: NWListener?
    private var clients: [ObjectIdentifier: (channel: Channel, name: String)] = [:]
    private var lastLevelEdit = Date.distantPast
    private var lastLevels: (Double?, Double?) = (nil, nil)
    private var lastPermissionNag = Date.distantPast
    private var appsRefresh: DispatchWorkItem?

    init() {
        let saved = UserDefaults.standard.string(forKey: "passcode")
        passcode = saved ?? Self.newCode()
        UserDefaults.standard.set(passcode, forKey: "passcode")
        start()

        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollMusic()
                if self?.touchBar?.isShowing == true { self?.touchBar?.refresh() }
            }
        }
        touchBar = TouchBarController(server: self)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAppsRefresh() }
            }
        }
    }

    static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

    /// Un código nuevo desconecta a todos: el iPhone tiene que volver a pedirlo.
    func regenerate() {
        passcode = Self.newCode()
        UserDefaults.standard.set(passcode, forKey: "passcode")
        start()
    }

    // MARK: Red

    private func start() {
        listener?.cancel()
        clients.values.forEach { $0.channel.cancel() }
        clients = [:]
        devices = []
        do {
            let l = try NWListener(using: .zarcillo(passcode: passcode))
            l.service = NWListener.Service(name: macName, type: ZarcilloService.type)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        switch state {
                        case .ready:
                            self.listening = true
                            self.problem = nil
                        case .failed(let error):
                            self.listening = false
                            self.problem = error.localizedDescription
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { self.start() } }
                        default: break
                        }
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.accept(conn) } }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            problem = error.localizedDescription
        }
    }

    private func accept(_ connection: NWConnection) {
        let channel = Channel(connection)
        let key = ObjectIdentifier(channel)
        clients[key] = (channel, "iPhone")
        channel.onState = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.drop(key) } }
            default: break
            }
        }
        // `DispatchQueue.main.async` y no `Task`: garantiza que los movimientos
        // del puntero se ejecuten en el orden en que llegaron.
        channel.onData = { [weak self] data in
            // Camino rápido: puntero y desplazamiento en binario, directo a la
            // cola de entrada, sin JSON ni hilo principal.
            if let tag = data.first, tag != UInt8(ascii: "{") {
                guard Input.isTrusted, let v = Fast.readVector(data) else { return }
                Input.queue.async {
                    if tag == Fast.move { Input.move(dx: v.0, dy: v.1) }
                    else if tag == Fast.scroll { Input.scroll(dx: v.0, dy: v.1) }
                }
                return
            }
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { return }
            // Clics y arrastres también van por la cola de entrada, en orden con el puntero.
            switch command {
            case .click(let button):
                if Input.isTrusted { Input.queue.async { Input.click(button) } }
            case .press(let down):
                if Input.isTrusted { Input.queue.async { Input.press(down: down) } }
            case .tapScreen(let x, let y, let button):
                if Input.isTrusted { Input.queue.async { ScreenGrabber.tap(x: x, y: y, button: button) } }
            default:
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(command, from: key) } }
            }
        }
        channel.start()
    }

    private func drop(_ key: ObjectIdentifier) {
        clients[key] = nil
        devices = clients.values.map(\.name)
        watchers[key] = nil
        inFlight.remove(key)
        updateStreaming()
        if clients.isEmpty { laser.setOn(false) }
    }

    private func reply(_ key: ObjectIdentifier, _ event: Event) {
        clients[key]?.channel.send(event)
    }

    private func broadcast(_ event: Event) {
        clients.values.forEach { $0.channel.send(event) }
    }

    // MARK: Órdenes

    private func handle(_ command: Command, from key: ObjectIdentifier) {
        switch command {
        case .hello(let device):
            clients[key]?.name = device
            devices = clients.values.map(\.name)
            reply(key, .welcome(mac: macName, volume: Volume.get(), brightness: Brightness.get(), canControl: Input.isTrusted))
            reply(key, .apps(Apps.dock()))
            let m = Power.machine()
            reply(key, .machine(hardwareAddress: m.hardware, ip: m.ip))
            reply(key, .permissions(accessibility: Input.isTrusted, screen: ScreenGrabber.allowed))
            reply(key, .nowPlaying(nowPlaying))
            reply(key, .capabilities(touchBar: TouchBarController.hasTouchBar))
            reply(key, .touchBarConfig(TouchBarController.config))
            artworkSent = nil
            hud.showMessage("\(device) conectado", symbol: "iphone")

        case .listApps:
            reply(key, .apps(Apps.dock()))

        case .launch(let id):
            if let app = Apps.launch(id) {
                hud.showMessage(app.name, symbol: nil, icon: app.icon)
                reply(key, .status("abriendo \(app.name)"))
            }

        case .setLevel(let kind, let value):
            lastLevelEdit = Date()
            switch kind {
            case .volume: Volume.set(value)
            case .brightness: Brightness.set(value)
            }
            hud.showLevel(kind, value)

        case .gesture(let gesture):
            guard allowed(key) else { return }
            Input.gesture(gesture)
            hud.showMessage(gesture.label, symbol: gesture.symbol)
            reply(key, .status(gesture.label))

        case .move(let dx, let dy):
            guard allowed(key) else { return }
            Input.queue.async { Input.move(dx: dx, dy: dy) }

        case .click, .press:
            _ = allowed(key)   // ya se ejecutó en la cola de entrada; aquí solo se avisa si falta permiso

        case .scroll(let dx, let dy):
            guard allowed(key) else { return }
            Input.queue.async { Input.scroll(dx: dx, dy: dy) }

        case .media(let media):
            guard allowed(key) else { return }
            Input.media(media)

        case .shortcut(let shortcut):
            guard allowed(key) else { return }
            if Input.shortcut(shortcut) {
                hud.showMessage(shortcut.title, symbol: "command")
                reply(key, .status(shortcut.title))
            }

        case .type(let text):
            guard allowed(key) else { return }
            Typing.type(text)

        case .key(let name):
            guard allowed(key) else { return }
            Typing.key(named: name)

        case .pushClipboard(let text, let image):
            Clipboard.set(text: text, image: image)
            hud.showMessage(image != nil ? "imagen copiada" : "texto copiado", symbol: "doc.on.clipboard")
            reply(key, .status("copiado en el Mac"))

        case .pullClipboard:
            let c = Clipboard.get()
            reply(key, .clipboard(text: c.text, image: c.image))

        case .seek(let seconds):
            guard let np = nowPlaying else { return }
            musicQueue.async { NowPlayingReader.seek(seconds, in: np) }

        case .laser(let on):
            laser.setOn(on)

        case .laserMove(let dx, let dy):
            laser.move(dx: dx, dy: dy)

        case .screen(let on, let width):
            watchers[key] = on ? min(max(width, 480), 2400) : nil
            if on, !ScreenGrabber.allowed {
                ScreenGrabber.requestAccess()
                reply(key, .permissions(accessibility: Input.isTrusted, screen: false))
            }
            updateStreaming()

        case .tapScreen:
            break   // va por la cola de entrada

        case .listWindows:
            if Input.isTrusted { reply(key, .windows(Windows.list())) }

        case .focusWindow(let id):
            guard allowed(key) else { return }
            if let title = Windows.focus(id) {
                hud.showMessage(title, symbol: "macwindow")
            }

        case .runRoutine(let routine):
            hud.showMessage(routine.name, symbol: routine.symbol)
            reply(key, .status(routine.name))
            run(routine)

        case .power(let action):
            Power.perform(action)

        case .syncRoutines(let list):
            routines = list
            UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "routines")
            touchBar?.refresh()

        case .accent(let hex):
            Accent.hex = hex
            // Todo lo que pinta el Mac lee el acento al dibujarse: el menú se
            // entera por aquí, el HUD y la Touch Bar en su próximo repintado.
            objectWillChange.send()
            touchBar?.refresh()

        case .touchBar(let config):
            touchBar?.apply(config)

        case .touchBarShow(let show):
            touchBar?.setShown(show)

        case .photo(let data):
            photos.receive(data)
            reply(key, .status("foto recibida en el Mac"))
        }
    }

    /// Una escena lanzada desde la Touch Bar.
    func runFromMac(_ routine: Routine) {
        hud.showMessage(routine.name, symbol: routine.symbol)
        run(routine)
    }

    // MARK: Escenas

    /// Los pasos van en orden con una pausa corta: abrir una app y bajar el
    /// volumen al mismo tiempo a veces pierde el segundo paso.
    private func run(_ routine: Routine) {
        routineTask?.cancel()
        routineTask = Task { @MainActor in
            for step in routine.steps {
                if Task.isCancelled { return }
                switch step {
                case .openApp(let id, _): _ = Apps.launch(id)
                case .openURL(let s): if let url = URL(string: s) { NSWorkspace.shared.open(url) }
                case .volume(let v): Volume.set(v)
                case .brightness(let v): Brightness.set(v)
                case .media(let m): if Input.isTrusted { Input.media(m) }
                case .shortcut(let sc): if Input.isTrusted { _ = Input.shortcut(sc) }
                case .runShortcut(let name): Power.runShortcut(name)
                case .gesture(let g): if Input.isTrusted { Input.gesture(g) }
                case .power(let p): Power.perform(p)
                case .wait(let s): try? await Task.sleep(for: .seconds(s))
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    // MARK: Pantalla en vivo

    /// Arranca, ajusta o detiene el stream según quién esté mirando. Se usa el
    /// ancho más grande pedido (pantalla completa pide más).
    private func updateStreaming() {
        let width = watchers.values.max()
        Task { @MainActor in
            guard let width, ScreenGrabber.allowed else { await screen.stop(); return }
            screen.onFrame = { [weak self] jpeg in
                var body = Data([Fast.frame])
                body.append(jpeg)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.deliver(body) } }
            }
            await screen.start(width: width)
        }
    }

    private func deliver(_ frame: Data) {
        for key in watchers.keys where !inFlight.contains(key) {
            guard let channel = clients[key]?.channel else { continue }
            inFlight.insert(key)
            channel.sendRaw(frame) { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { _ = self?.inFlight.remove(key) } }
            }
        }
    }

    // MARK: Música

    private func pollMusic() {
        guard !clients.isEmpty || touchBar?.isShowing == true else { return }
        musicQueue.async { [weak self] in
            let np = NowPlayingReader.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.nowPlaying = np
                    self.broadcast(.nowPlaying(np))
                    if np == nil { self.currentArtwork = nil; self.artworkTrack = nil }
                    if let np, np.trackID != self.artworkSent || np.trackID != self.artworkTrack {
                        self.artworkSent = np.trackID
                        self.artworkTrack = np.trackID
                        self.musicQueue.async {
                            guard let art = NowPlayingReader.artwork(for: np) else { return }
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    self.currentArtwork = NSImage(data: art)
                                    self.broadcast(.artwork(trackID: np.trackID, data: art))
                                    self.touchBar?.refresh()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Sin Accesibilidad los eventos se pierden en silencio; mejor avisar (sin
    /// inundar al iPhone con un aviso por cada movimiento del dedo).
    private func allowed(_ key: ObjectIdentifier) -> Bool {
        if Input.isTrusted { return true }
        if Date().timeIntervalSince(lastPermissionNag) > 3 {
            lastPermissionNag = Date()
            reply(key, .status("falta permiso de Accesibilidad en el Mac"))
        }
        return false
    }

    // MARK: Sincronía

    /// Si el volumen o el brillo cambian desde el propio Mac (teclas, Centro de
    /// control), el dial del iPhone se entera.
    private func tick() {
        let wasCapture = canCapture
        Input.refreshTrust()
        canControl = Input.isTrusted
        canCapture = ScreenGrabber.allowed
        if canCapture != wasCapture {
            broadcast(.permissions(accessibility: canControl, screen: canCapture))
            updateStreaming()
        }
        guard !clients.isEmpty, Date().timeIntervalSince(lastLevelEdit) > 1 else { return }
        let now = (Volume.get(), Brightness.get())
        func changed(_ a: Double?, _ b: Double?) -> Bool { abs((a ?? -1) - (b ?? -1)) > 0.01 }
        if changed(now.0, lastLevels.0) || changed(now.1, lastLevels.1) {
            lastLevels = now
            broadcast(.levels(volume: now.0, brightness: now.1))
        }
    }

    private func scheduleAppsRefresh() {
        appsRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.clients.isEmpty else { return }
                self.broadcast(.apps(Apps.dock()))
            }
        }
        appsRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
