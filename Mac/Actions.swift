import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio

// MARK: - Volumen (CoreAudio)

enum Volume {
    private static func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr ? id : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static func get() -> Double? {
        guard let dev = device() else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &volumeAddress, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func set(_ v: Double) {
        guard let dev = device() else { return }
        var value = Float32(min(1, max(0, v)))
        AudioObjectSetPropertyData(dev, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        // Subir el volumen de un Mac silenciado no se oye: se quita el silencio.
        var mute = UInt32(value > 0 ? 0 : 1)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(dev, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
    }
}

// MARK: - Brillo (DisplayServices)

/// El brillo de la pantalla integrada no tiene API pública. `DisplayServices`
/// es el framework privado que usa el propio Centro de control; se carga con
/// `dlopen` para que, si algún día desaparece, la app siga funcionando sin brillo.
enum Brightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    private static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static func get() -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? Double(value) : nil
    }

    static func set(_ v: Double) {
        _ = setFn?(display, Float(min(1, max(0, v))))
    }
}

// MARK: - Teclado y ratón (CGEvent)

enum Input {
    private static let source = CGEventSource(stateID: .hidSystemState)
    private static var dragging = false
    private static var lastClick = (time: Date.distantPast, button: MouseButton.left, count: 0)

    /// Publicar eventos en otras apps exige el permiso de Accesibilidad.
    ///
    /// Se guarda en memoria y se refresca cada segundo y medio: preguntarle al
    /// sistema en cada movimiento del puntero (cientos por segundo) sumaba latencia.
    nonisolated(unsafe) private(set) static var isTrusted = AXIsProcessTrusted()

    static func refreshTrust() { isTrusted = AXIsProcessTrusted() }

    /// Toda la entrada (puntero, clics, desplazamiento) va por esta cola, en
    /// orden y sin esperar al hilo principal.
    static let queue = DispatchQueue(label: "zarcillo.input", qos: .userInteractive)

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        _ = CGRequestPostEventAccess()
    }

    private static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Unión de todas las pantallas, para que el cursor no se escape.
    private static var desktop: CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
    }

    static func move(dx: Double, dy: Double) {
        let bounds = desktop
        var p = location
        p.x = min(bounds.maxX - 1, max(bounds.minX, p.x + dx))
        p.y = min(bounds.maxY - 1, max(bounds.minY, p.y + dy))
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Dos toques seguidos en el iPhone llegan como dos clics sueltos; acá se
    /// numeran para que el Mac los lea como doble clic.
    static func click(_ button: MouseButton) {
        let now = Date()
        let isRepeat = button == lastClick.button && now.timeIntervalSince(lastClick.time) < NSEvent.doubleClickInterval
        let count = isRepeat ? min(lastClick.count + 1, 3) : 1
        lastClick = (now, button, count)

        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton) =
            button == .left ? (.leftMouseDown, .leftMouseUp, .left) : (.rightMouseDown, .rightMouseUp, .right)
        let p = location
        for type in [down, up] {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: cgButton)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Lleva el cursor a un punto exacto (para la pantalla en vivo).
    static func warp(to p: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func press(down: Bool) {
        dragging = down
        CGEvent(mouseEventSource: source, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    static func scroll(dx: Double, dy: Double) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        var flags = flags
        // Las flechas de un teclado real llevan estas dos banderas; sin ellas,
        // ⌃← no cambia de escritorio.
        if (123...126).contains(code) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func shortcut(_ s: Shortcut) -> Bool {
        guard let code = keyCodes[s.key.lowercased()] else { return false }
        var flags = CGEventFlags()
        if s.command { flags.insert(.maskCommand) }
        if s.shift { flags.insert(.maskShift) }
        if s.option { flags.insert(.maskAlternate) }
        if s.control { flags.insert(.maskControl) }
        key(code, flags)
        return true
    }

    static func gesture(_ g: DesktopGesture) {
        switch g {
        case .spaceLeft: key(123, .maskControl)
        case .spaceRight: key(124, .maskControl)
        case .appWindows: key(125, .maskControl)
        case .spotlight: key(49, .maskCommand)
        case .missionControl:
            // Abrir la app no depende de que ⌃↑ siga asignado en Ajustes.
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        }
    }

    /// Teclas multimedia: son eventos de sistema (NX_KEYTYPE_*), no teclas normales.
    static func media(_ key: MediaKey) {
        let code: Int = switch key {
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (code << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                               timestamp: 0, windowNumber: 0, context: nil,
                               subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Códigos virtuales de un teclado ANSI.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}

// MARK: - Apps del Dock

enum Apps {
    private static var iconCache: [String: Data] = [:]

    /// Las apps fijadas en el Dock, en su orden, más las que estén abiertas.
    /// Es la lista que el usuario ya curó: no hace falta pedirle que elija favoritas.
    static func dock() -> [AppTile] {
        var urls: [URL] = []
        if let dock = UserDefaults(suiteName: "com.apple.dock"),
           let items = dock.array(forKey: "persistent-apps") as? [[String: Any]] {
            for item in items {
                guard let tile = item["tile-data"] as? [String: Any],
                      let file = tile["file-data"] as? [String: Any],
                      let string = file["_CFURLString"] as? String,
                      let url = URL(string: string) else { continue }
                urls.append(url)
            }
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in running {
            if let url = app.bundleURL, !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                urls.append(url)
            }
        }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))

        var seen = Set<String>()
        return urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return AppTile(id: id, name: name, icon: icon(for: url), running: runningIDs.contains(id))
        }
    }

    private static func icon(for url: URL) -> Data {
        if let cached = iconCache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        let side = 144
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:]) ?? Data()
        iconCache[url.path] = data
        return data
    }

    static func launch(_ id: String) -> (name: String, icon: NSImage)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // `openApplication` también trae al frente una app ya abierta; `activate()`
        // desde una app de fondo el sistema lo puede ignorar.
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }
}
