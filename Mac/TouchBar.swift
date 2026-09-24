import AppKit

/// El color que eligió el usuario en el iPhone. El Mac lo usa en el HUD y en la
/// Touch Bar para que las dos pantallas se vean como el mismo aparato.
enum Accent {
    static var hex: Int {
        get { UserDefaults.standard.object(forKey: "accent") as? Int ?? 0xF08A4B }
        set { UserDefaults.standard.set(newValue, forKey: "accent") }
    }

    static var nsColor: NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Zarcillo en la Touch Bar.
///
/// Una app de barra de menús nunca está al frente, así que no puede usar la
/// Touch Bar normal: esa es de la app activa. Se usa la Control Strip (la zona
/// fija de la derecha), igual que el control de volumen del sistema. Tocar la
/// hoja despliega la barra completa por encima de la de la app activa.
///
/// Apple no expone esto públicamente: son las mismas funciones privadas que usan
/// apps como Pock o MTMR. Se buscan en tiempo de ejecución, y en un Mac sin
/// Touch Bar (o si Apple las quita) simplemente no pasa nada.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private static let tray = NSTouchBarItem.Identifier("com.kisnner.zarcillo.tray")
    private static let status = NSTouchBarItem.Identifier("zarcillo.status")
    private static let playing = NSTouchBarItem.Identifier("zarcillo.playing")
    private static let media = NSTouchBarItem.Identifier("zarcillo.media")
    private static let volume = NSTouchBarItem.Identifier("zarcillo.volume")
    private static let brightness = NSTouchBarItem.Identifier("zarcillo.brightness")
    private static let routines = NSTouchBarItem.Identifier("zarcillo.routines")

    private weak var server: Server?
    private var bar: NSTouchBar?
    private var trayButton: NSButton?

    // Vistas que se refrescan
    private let statusButton = NSButton(title: "", target: nil, action: nil)
    private let artView = NSImageView()
    private let songLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton()
    private var volumeItem: NSSliderTouchBarItem?
    private var brightnessItem: NSSliderTouchBarItem?
    private let routineStack = NSStackView()

    /// Si la barra completa está a la vista: solo entonces vale la pena leer la música.
    var isShowing: Bool { bar?.isVisible == true }

    /// Los MacBook Pro con Touch Bar, por modelo. No hay una API pública que lo
    /// diga, y el identificador de modelo no cambia.
    static let hasTouchBar: Bool = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        let model = String(cString: chars)
        let withBar: Set<String> = ["MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3",
                                    "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
                                    "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
                                    "MacBookPro17,1", "Mac14,7"]
        return withBar.contains(model)
    }()

    /// Lo que eligió el usuario desde el iPhone.
    static var config: TouchBarConfig {
        get {
            guard let d = UserDefaults.standard.data(forKey: "touchBar"),
                  let c = try? JSONDecoder().decode(TouchBarConfig.self, from: d) else { return .standard }
            return c
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "touchBar") }
    }

    func apply(_ config: TouchBarConfig) {
        Self.config = config
        if isShowing { present() }
    }

    func setShown(_ show: Bool) {
        if show {
            present()
        } else if let bar {
            for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
                let sel = NSSelectorFromString(name)
                if (NSTouchBar.self as AnyObject).responds(to: sel) {
                    _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar)
                    break
                }
            }
        }
    }

    init(server: Server) {
        self.server = server
        super.init()
        installTray()
    }

    // MARK: Control Strip

    private func installTray() {
        let item = NSCustomTouchBarItem(identifier: Self.tray)
        let button = NSButton(image: NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Zarcillo")!,
                              target: self, action: #selector(present))
        button.bezelColor = Accent.nsColor
        item.view = button
        trayButton = button

        let add = NSSelectorFromString("addSystemTrayItem:")
        guard (NSTouchBarItem.self as AnyObject).responds(to: add) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(add, with: item)

        typealias Presence = @convention(c) (CFString, Bool) -> Void
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW),
              let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(sym, to: Presence.self)(Self.tray.rawValue as CFString, true)
    }

    @objc private func present() {
        let b = NSTouchBar()
        b.delegate = self
        // En el orden y con las piezas que elegiste en el iPhone.
        let map: [TouchBarConfig.Kind: NSTouchBarItem.Identifier] = [
            .playing: Self.playing, .media: Self.media, .volume: Self.volume,
            .brightness: Self.brightness, .routines: Self.routines, .status: Self.status,
        ]
        let hasBrightness = Brightness.get() != nil
        b.defaultItemIdentifiers = Self.config.slots
            .filter { $0.on && ($0.kind != .brightness || hasBrightness) }
            .compactMap { map[$0.kind] }
        bar = b

        for name in ["presentSystemModalTouchBar:systemTrayItemIdentifier:",
                     "presentSystemModalFunctionBar:systemTrayItemIdentifier:"] {
            let sel = NSSelectorFromString(name)
            if (NSTouchBar.self as AnyObject).responds(to: sel) {
                _ = (NSTouchBar.self as AnyObject).perform(sel, with: b, with: Self.tray.rawValue)
                break
            }
        }
        refresh()
    }

    // MARK: Contenido

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case Self.status:
            let item = NSCustomTouchBarItem(identifier: id)
            statusButton.target = self
            statusButton.action = #selector(showStatus)
            statusButton.imagePosition = .imageLeading
            statusButton.translatesAutoresizingMaskIntoConstraints = false
            statusButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            statusButton.setContentHuggingPriority(.required, for: .horizontal)
            item.view = statusButton
            return item

        case Self.playing:
            let item = NSCustomTouchBarItem(identifier: id)
            artView.imageScaling = .scaleProportionallyUpOrDown
            artView.wantsLayer = true
            artView.layer?.cornerRadius = 4
            artView.layer?.masksToBounds = true
            artView.translatesAutoresizingMaskIntoConstraints = false
            artView.widthAnchor.constraint(equalToConstant: 30).isActive = true
            artView.heightAnchor.constraint(equalToConstant: 30).isActive = true
            songLabel.font = .systemFont(ofSize: 13, weight: .medium)
            songLabel.lineBreakMode = .byTruncatingTail
            songLabel.translatesAutoresizingMaskIntoConstraints = false
            songLabel.widthAnchor.constraint(equalToConstant: 170).isActive = true
            let stack = NSStackView(views: [artView, songLabel])
            stack.spacing = 8
            item.view = stack
            return item

        case Self.media:
            let item = NSCustomTouchBarItem(identifier: id)
            let prev = symbolButton("backward.fill", #selector(previous))
            playButton.target = self
            playButton.action = #selector(playPause)
            playButton.bezelColor = Accent.nsColor
            playButton.translatesAutoresizingMaskIntoConstraints = false
            playButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let next = symbolButton("forward.fill", #selector(nextTrack))
            let stack = NSStackView(views: [prev, playButton, next])
            stack.spacing = 6
            item.view = stack
            return item

        case Self.volume:
            let item = slider(id, symbolLow: "speaker.fill", symbolHigh: "speaker.wave.3.fill", action: #selector(volumeChanged(_:)))
            volumeItem = item
            return item

        case Self.brightness:
            let item = slider(id, symbolLow: "sun.min.fill", symbolHigh: "sun.max.fill", action: #selector(brightnessChanged(_:)))
            brightnessItem = item
            return item

        case Self.routines:
            let item = NSCustomTouchBarItem(identifier: id)
            routineStack.spacing = 6
            item.view = routineStack
            return item

        default:
            return nil
        }
    }

    /// Botón de icono angosto: la Touch Bar es corta y todo tiene que caber.
    private func symbolButton(_ name: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!, target: self, action: action)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return b
    }

    private func slider(_ id: NSTouchBarItem.Identifier, symbolLow: String, symbolHigh: String, action: Selector) -> NSSliderTouchBarItem {
        let item = NSSliderTouchBarItem(identifier: id)
        item.slider.minValue = 0
        item.slider.maxValue = 1
        item.slider.trackFillColor = Accent.nsColor
        item.minimumValueAccessory = NSSliderAccessory(image: NSImage(systemSymbolName: symbolLow, accessibilityDescription: nil)!)
        item.maximumValueAccessory = NSSliderAccessory(image: NSImage(systemSymbolName: symbolHigh, accessibilityDescription: nil)!)
        item.minimumSliderWidth = 90
        item.maximumSliderWidth = 160
        item.target = self
        item.action = action
        return item
    }

    /// Pone al día todo lo visible. Lo llama el servidor cada segundo mientras
    /// la barra está desplegada, y al llegar música o escenas nuevas.
    func refresh() {
        guard let server else { return }
        let accent = Accent.nsColor
        trayButton?.bezelColor = accent
        playButton.bezelColor = accent
        volumeItem?.slider.trackFillColor = accent
        brightnessItem?.slider.trackFillColor = accent

        if server.devices.isEmpty {
            statusButton.title = "código \(server.passcode.prefix(3)) \(server.passcode.suffix(3))"
            statusButton.image = NSImage(systemSymbolName: "iphone.slash", accessibilityDescription: nil)
        } else {
            statusButton.title = server.devices.first ?? "iPhone"
            statusButton.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        }

        if let np = server.currentTrack {
            songLabel.stringValue = "\(np.title) — \(np.artist)"
            playButton.image = NSImage(systemSymbolName: np.playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        } else {
            songLabel.stringValue = "nada sonando"
            playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        }
        artView.image = server.currentArtwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)

        if let v = Volume.get(), !(volumeItem?.slider.isHighlighted ?? false) { volumeItem?.slider.doubleValue = v }
        if let b = Brightness.get(), !(brightnessItem?.slider.isHighlighted ?? false) { brightnessItem?.slider.doubleValue = b }

        let routines = server.routines.prefix(4)
        let titles = routines.map(\.name)
        let current = routineStack.arrangedSubviews.compactMap { ($0 as? NSButton)?.toolTip }
        if titles != current {
            routineStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for (i, r) in routines.enumerated() {
                // Solo el icono: el nombre va en la ayuda de accesibilidad.
                let b = NSButton(image: NSImage(systemSymbolName: r.symbol, accessibilityDescription: r.name)
                                 ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: r.name)!,
                                 target: self, action: #selector(runRoutine(_:)))
                b.tag = i
                b.toolTip = r.name
                b.translatesAutoresizingMaskIntoConstraints = false
                b.widthAnchor.constraint(equalToConstant: 44).isActive = true
                routineStack.addArrangedSubview(b)
            }
        }
    }

    // MARK: Acciones

    @objc private func showStatus() {
        guard let server else { return }
        server.hud.showMessage(server.devices.isEmpty ? "código \(server.passcode)" : "conectado", symbol: "iphone")
    }

    @objc private func playPause() { Input.media(.playPause) }
    @objc private func previous() { Input.media(.previous) }
    @objc private func nextTrack() { Input.media(.next) }

    @objc private func volumeChanged(_ item: NSSliderTouchBarItem) {
        Volume.set(item.slider.doubleValue)
        server?.hud.showLevel(.volume, item.slider.doubleValue)
    }

    @objc private func brightnessChanged(_ item: NSSliderTouchBarItem) {
        Brightness.set(item.slider.doubleValue)
        server?.hud.showLevel(.brightness, item.slider.doubleValue)
    }

    @objc private func runRoutine(_ sender: NSButton) {
        guard let server, server.routines.indices.contains(sender.tag) else { return }
        server.runFromMac(server.routines[sender.tag])
    }
}
