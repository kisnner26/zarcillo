import AppKit
import AVFoundation
import Network

@MainActor
final class Server: ObservableObject {
    @Published private(set) var passcode: String
    @Published private(set) var devices: [String] = [] {
        didSet { presence.set(!devices.isEmpty) }
    }
    let presence = Presence()
    @Published private(set) var canControl = Input.isTrusted
    @Published private(set) var listening = false
    @Published private(set) var problem: String?

    @Published private(set) var canCapture = ScreenGrabber.allowed

    let hud = HUD()
    let laser = Laser()
    let photos = PhotoDrop()
    let lights = Lights()
    let liveClass = LiveClass()
    private let beats = BeatDetector()
    private var beatListeners: Set<ObjectIdentifier> = []
    private let posture = PostureCoach()
    private var cameraBusy = false
    private var slouching = false
    let guardian = Guardian()
    let near = ProximityLock()
    let guest = GuestSprout()
    let mixer = Mixer()
    /// Estado de los permisos de macOS; el menú y el iPhone lo muestran.
    @Published private(set) var permissions: [PermissionEntry] = Permissions.all()
    /// La ventana desprendida, si la hay: el stream manda solo esa.
    private var detachTarget: String?
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
        lights.onChange = { [weak self] in self?.broadcastLights() }
        beats.onBeat = { [weak self] strength in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hud.pulse(strength)
                    for key in self.beatListeners { self.reply(key, .beat(strength)) }
                }
            }
        }
        posture.onReading = { [weak self] r in
            MainActor.assumeIsolated {
                guard let self, self.posture.active else { return }
                self.slouching = r.slouching
                self.broadcast(.postureState(on: true, slouching: r.slouching, calibrating: r.calibrating,
                                             seen: r.seen, score: r.score))
            }
        }
        posture.onAlert = { [weak self] in
            MainActor.assumeIsolated {
                self?.hud.showMessage("endereza la espalda", symbol: "figure.stand")
            }
        }
        guardian.onAlert = { [weak self] reason, photo in
            guard let self else { return }
            self.broadcast(.guardianAlert(reason: reason, photo: photo))
        }
        near.passcode = passcode
        near.onChange = { [weak self] in self?.broadcastNear() }
        near.onReturn = { [weak self] in
            // Enciende la pantalla, lista para Touch ID.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-u", "-t", "2"]
            try? p.run()
            self?.hud.showMessage("bienvenido de vuelta", symbol: "hand.wave.fill")
        }
        near.start()
        guest.onPhoto = { [weak self] data, name in
            guard let self else { return }
            self.photos.receive(data)
            self.hud.showMessage("\(name) te lanzó una foto", symbol: "leaf.fill")
            self.broadcast(.status("\(name) lanzó una foto al Mac"))
        }
        guest.onChange = { [weak self] in self?.broadcastGuest() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.broadcastFrontApp() }
        }
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
        near.passcode = passcode
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
        if watchers.isEmpty { detachTarget = nil }
        inFlight.remove(key)
        beatListeners.remove(key)
        if beatListeners.isEmpty { Task { await beats.stop() } }
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
            reply(key, .lights(devices: lights.devices, ambient: lights.ambient, brightness: lights.brightness))
            reply(key, .macPermissions(permissions))
            reply(key, .guardianState(on: guardian.armed, siren: guardian.siren))
            reply(key, .nearState(on: near.on, rssi: near.rssi, threshold: near.threshold, locked: near.locked))
            reply(key, .guestPass(url: guest.url, expires: guest.expires?.timeIntervalSince1970))
            if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier {
                reply(key, .frontApp(id: id, name: app.localizedName ?? ""))
            }
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

        case .lightsScan:
            lights.scan()
        case .lightsAmbient(let on):
            lights.setAmbient(on)
            hud.showMessage(on ? "luces siguiendo la pantalla" : "luces en pausa", symbol: "lightbulb.fill")
        case .lightsBrightness(let v):
            lights.setBrightness(v)
        case .lightZone(let id, let zone):
            lights.setZone(zone, for: id)
        case .lightIdentify(let id):
            lights.identify(id)

        case .photoToss(let data, let angle, let side):
            photos.receive(data, side: side, angle: angle)
            reply(key, .status("foto recibida en el Mac"))

        case .file(let name, let data):
            photos.receive(data, name: name)
            reply(key, .status("\(name) está en el bolsillo"))

        case .openURL(let s):
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                hud.showMessage(url.host ?? "link", symbol: "link")
            }

        case .harvest(let x, let y, let w, let h):
            Task { @MainActor in
                if let png = await ScreenGrabber.region(x: x, y: y, w: w, h: h) {
                    self.reply(key, .harvested(png))
                    self.hud.showMessage("cosechado", symbol: "leaf.fill")
                } else {
                    self.reply(key, .status("no pude recortar: falta el permiso de pantalla"))
                }
            }

        case .scanPages(let pages):
            if let url = NotesArchive.save(pages) {
                hud.showMessage("apuntes guardados", symbol: "doc.viewfinder")
                reply(key, .status("guardado en Documentos › Zarcillo › Apuntes"))
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case .transcriptStart(let title, _):
            liveClass.start(title: title)
            hud.showMessage("transcribiendo \(title)", symbol: "waveform")

        case .transcript(let text, let translation, let final):
            liveClass.update(text: text, translation: translation, final: final)

        case .transcriptMark:
            liveClass.mark()

        case .transcriptEnd:
            if let url = liveClass.end() {
                hud.showMessage("clase guardada", symbol: "doc.text.fill")
                reply(key, .status("guardada en Documentos › Zarcillo › Clases"))
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case .blow:
            let gone = Scatter.toggle()
            hud.showMessage(gone ? "escritorio despejado" : "todo de vuelta", symbol: "wind")

        case .beats(let on):
            if on { beatListeners.insert(key) } else { beatListeners.remove(key) }
            Task { @MainActor in
                if self.beatListeners.isEmpty { await self.beats.stop() } else { await self.beats.start() }
            }

        case .posture(let on):
            if on {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .denied, .restricted:
                    reply(key, .status("Zarcillo no tiene permiso de cámara: actívalo en Ajustes › Privacidad › Cámara"))
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    reply(key, .postureState(on: false, slouching: false, calibrating: false, seen: false, score: 0))
                    return
                default:
                    if AVCaptureDevice.default(for: .video) == nil {
                        reply(key, .status("este Mac no tiene cámara disponible"))
                        return
                    }
                }
                posture.start()
            } else {
                posture.stop()
            }
            broadcast(.postureState(on: on, slouching: false, calibrating: on, seen: false, score: 0))
            hud.showMessage(on ? "cuidando tu postura" : "postura en pausa", symbol: "figure.stand")

        case .guardian(let on, let siren):
            if on { guardian.arm(siren: siren) } else { guardian.disarm() }
            guardian.setSiren(siren)
            broadcast(.guardianState(on: guardian.armed, siren: guardian.siren))
            hud.showMessage(on ? "guardián activo" : "guardián en reposo", symbol: on ? "lock.shield.fill" : "shield")

        case .guardianSilence:
            guardian.silence()

        case .proximity(let on, let threshold):
            near.configure(on: on, threshold: threshold)

        case .guest(let on):
            if on { guest.open(macName: macName) } else { guest.close() }
            hud.showMessage(on ? "brote invitado abierto" : "brote invitado cerrado", symbol: "qrcode")

        case .detach(let window, let width):
            detachTarget = window
            watchers[key] = window != nil ? min(max(width, 480), 2400) : nil
            if window != nil, !ScreenGrabber.allowed {
                ScreenGrabber.requestAccess()
                reply(key, .permissions(accessibility: Input.isTrusted, screen: false))
            }
            reply(key, .detached(title: window.flatMap { Windows.frame($0)?.title }))
            updateStreaming()

        case .tapWindow(let x, let y, let button):
            guard allowed(key), let id = detachTarget, let t = Windows.frame(id) else { return }
            // La ventana tiene que estar al frente para recibir el clic.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != t.pid { Windows.focus(id) }
            let p = CGPoint(x: t.frame.minX + t.frame.width * min(1, max(0, x)),
                            y: t.frame.minY + t.frame.height * min(1, max(0, y)))
            Input.queue.asyncAfter(deadline: .now() + 0.05) {
                Input.warp(to: p)
                Input.click(button)
            }

        case .mixerList:
            reply(key, .mixer(mixer.list()))

        case .mixerGain(let pid, let gain):
            mixer.set(pid, gain: gain)
            reply(key, .mixer(mixer.list()))

        case .pointTo(let x, let y):
            guard allowed(key) else { return }
            let b = CGDisplayBounds(CGMainDisplayID())
            let p = CGPoint(x: b.minX + b.width * min(1, max(0, x)), y: b.minY + b.height * min(1, max(0, y)))
            Input.queue.async { Input.warp(to: p) }

        case .pullTab:
            musicQueue.async { [weak self] in
                let tab = BrowserTab.front()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let tab {
                            self?.reply(key, .tab(url: tab.url, title: tab.title))
                            self?.hud.showMessage("pestaña al iPhone", symbol: "safari")
                        } else {
                            self?.reply(key, .status("no hay una pestaña abierta en el navegador del Mac"))
                        }
                    }
                }
            }

        case .requestPermission(let kind):
            Permissions.request(kind)
            hud.showMessage("mira el aviso en el Mac", symbol: kind.symbol)
            reply(key, .status("pidiendo \(kind.title) en el Mac"))

        case .grab:
            musicQueue.async { [weak self] in
                let front = MacGrab.fromFrontApp()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        Task { @MainActor in
                            var item = front ?? MacGrab.fromClipboard()
                            if item == nil { item = await MacGrab.screen() }
                            guard let item else {
                                self.reply(key, .status("no hay nada que agarrar en el Mac"))
                                return
                            }
                            self.reply(key, .grabbed(kind: item.kind, name: item.name, data: item.data, text: item.text))
                            self.hud.showMessage("el reloj agarró \(item.name)", symbol: "applewatch")
                        }
                    }
                }
            }

        case .photo(let data):
            photos.receive(data)
            reply(key, .status("foto recibida en el Mac"))
        }
    }

    private func broadcastFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        broadcast(.frontApp(id: id, name: app.localizedName ?? ""))
    }

    /// Si algún permiso cambió (en Ajustes, o al aceptar el aviso), el menú y el iPhone se enteran.
    private func refreshPermissions() {
        let now = Permissions.all()
        guard now != permissions else { return }
        permissions = now
        broadcast(.macPermissions(now))
    }

    private func broadcastNear() {
        broadcast(.nearState(on: near.on, rssi: near.rssi, threshold: near.threshold, locked: near.locked))
    }

    private func broadcastGuest() {
        broadcast(.guestPass(url: guest.url, expires: guest.expires?.timeIntervalSince1970))
    }

    private func broadcastLights() {
        broadcast(.lights(devices: lights.devices, ambient: lights.ambient, brightness: lights.brightness))
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
                case .openAppNamed(let n):
                    if AppFinder.open(n) == nil { broadcast(.status("no encontré la app “\(n)” en el Mac")) }
                case .quitApp(let n):
                    if let name = AppFinder.quit(n) { hud.showMessage("cerrando \(name)", symbol: "xmark.app") }
                    else { broadcast(.status("“\(n)” no está abierta")) }
                case .hideApp(let n):
                    if AppFinder.hide(n) == nil { broadcast(.status("“\(n)” no está abierta")) }
                case .quitAllApps:
                    AppFinder.quitAll()
                    hud.showMessage("cerrando todo", symbol: "xmark.square")
                case .volumeBy(let d):
                    let v = min(1, max(0, (Volume.get() ?? 0.5) + d))
                    Volume.set(v)
                    hud.showLevel(.volume, v)
                case .brightnessBy(let d):
                    let v = min(1, max(0, (Brightness.get() ?? 0.5) + d))
                    Brightness.set(v)
                    hud.showLevel(.brightness, v)
                case .typeText(let t): if Input.isTrusted { Typing.type(t) }
                case .openFolder(let f):
                    if AppFinder.openFolder(f) == nil { broadcast(.status("no sé qué carpeta es “\(f)”")) }
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
            await screen.start(width: width, window: self.detachTarget)
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
        // ¿Empezó o terminó una videollamada?
        // La postura y la foto del guardián usan la cámara: eso no es una videollamada.
        let busy = CameraWatcher.inUse && !posture.running && !guardian.usingCamera
        if busy != cameraBusy {
            cameraBusy = busy
            broadcast(.cameraInUse(busy))
        }
        canControl = Input.isTrusted
        refreshPermissions()
        mixer.refresh()
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
