import AppKit
import Network

@MainActor
final class Server: ObservableObject {
    @Published private(set) var passcode: String
    @Published private(set) var devices: [String] = []
    @Published private(set) var canControl = Input.isTrusted
    @Published private(set) var listening = false
    @Published private(set) var problem: String?

    let hud = HUD()
    let macName = Host.current().localizedName ?? "Mac"

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
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(command, from: key) } }
        }
        channel.start()
    }

    private func drop(_ key: ObjectIdentifier) {
        clients[key] = nil
        devices = clients.values.map(\.name)
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
            Input.move(dx: dx, dy: dy)

        case .click(let button):
            guard allowed(key) else { return }
            Input.click(button)

        case .press(let down):
            guard allowed(key) else { return }
            Input.press(down: down)

        case .scroll(let dx, let dy):
            guard allowed(key) else { return }
            Input.scroll(dx: dx, dy: dy)

        case .media(let media):
            guard allowed(key) else { return }
            Input.media(media)

        case .shortcut(let shortcut):
            guard allowed(key) else { return }
            if Input.shortcut(shortcut) {
                hud.showMessage(shortcut.title, symbol: "command")
                reply(key, .status(shortcut.title))
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
        canControl = Input.isTrusted
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
