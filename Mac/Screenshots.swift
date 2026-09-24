import AppKit

/// Cuando tomas una captura (⇧⌘3, ⇧⌘4, ⇧⌘5) macOS guarda un archivo en una
/// carpeta (el Escritorio, salvo que lo cambies). Aquí se vigila esa carpeta y
/// cada captura nueva se manda al iPhone.
@MainActor
final class ScreenshotWatcher {
    var onShot: ((String, Data) -> Void)?
    private(set) var enabled: Bool
    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []
    private var folder: URL?

    init() {
        enabled = UserDefaults.standard.object(forKey: "screenshots.send") as? Bool ?? true
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "screenshots.send")
        on ? start() : stop()
    }

    /// Donde macOS guarda las capturas hoy.
    static var location: URL {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start() {
        stop()
        let url = Self.location
        folder = url
        seen = Set(names(in: url))
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Si el usuario cambió la carpeta de capturas, se sigue la nueva.
    func recheckLocation() {
        guard enabled, folder != Self.location else { return }
        start()
    }

    private func names(in url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    private func scan() {
        guard let folder else { return }
        for name in names(in: folder) where !seen.contains(name) {
            seen.insert(name)
            let file = folder.appendingPathComponent(name)
            guard Self.isScreenshot(file) else { continue }
            // macOS acaba de crearlo: un instante para que termine de escribirse.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                MainActor.assumeIsolated { self?.deliver(file) }
            }
        }
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased()) else { return false }
        // Las capturas de macOS llevan esta marca; el nombre es el respaldo (según el idioma).
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 { return true }
        return ["Screenshot", "Captura de pantalla", "Captura de Pantalla", "Bildschirmfoto", "Capture d’écran"]
            .contains { name.hasPrefix($0) }
    }

    private func deliver(_ file: URL) {
        guard var data = try? Data(contentsOf: file), !data.isEmpty else { return }
        var name = file.lastPathComponent
        // Una captura Retina completa pesa varios MB: en JPEG llega mucho más rápido.
        if data.count > 6_000_000, let img = NSImage(data: data), let jpeg = MacGrab.jpeg(img, max: 3200) {
            data = jpeg
            name = (name as NSString).deletingPathExtension + ".jpg"
        }
        onShot?(name, data)
    }
}
