import AppKit
import UniformTypeIdentifiers

/// Lo que el reloj puede agarrar del Mac, en este orden: lo seleccionado en el
/// Finder, la página del navegador que está al frente, lo copiado y, si no hay
/// nada, una foto de la pantalla.
enum MacGrab {
    struct Item {
        var kind: String       // image, file, url, text
        var name: String
        var data: Data?
        var text: String?
    }

    static let limit = 25 * 1024 * 1024

    /// Finder o navegador al frente. Usa AppleScript: llamar fuera del hilo principal.
    static func fromFrontApp() -> Item? {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front == "com.apple.finder", let item = finderSelection() { return item }
        let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                                     "com.brave.Browser", "com.microsoft.edgemac"]
        if let front, browsers.contains(front), let tab = BrowserTab.front() {
            return Item(kind: "url", name: tab.title.isEmpty ? tab.url : tab.title, data: nil, text: tab.url)
        }
        return nil
    }

    static func fromClipboard() -> Item? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first, let item = file(first) {
            return item
        }
        if let img = NSImage(pasteboard: pb), let data = jpeg(img) {
            return Item(kind: "image", name: "imagen copiada", data: data, text: nil)
        }
        if let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            if let u = URL(string: s), let scheme = u.scheme, ["http", "https"].contains(scheme) {
                return Item(kind: "url", name: u.host ?? s, data: nil, text: s)
            }
            return Item(kind: "text", name: String(s.prefix(40)), data: nil, text: s)
        }
        return nil
    }

    static func screen() async -> Item? {
        guard let png = await ScreenGrabber.region(x: 0, y: 0, w: 1, h: 1),
              let img = NSImage(data: png), let data = jpeg(img) else { return nil }
        return Item(kind: "image", name: "pantalla del Mac", data: data, text: nil)
    }

    private static func finderSelection() -> Item? {
        let script = """
        tell application "Finder"
            set s to selection
            if (count of s) is 0 then return ""
            return POSIX path of (item 1 of s as alias)
        end tell
        """
        var error: NSDictionary?
        guard let path = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue, !path.isEmpty else { return nil }
        return file(URL(fileURLWithPath: path))
    }

    /// Un archivo: si es imagen, viaja como imagen (se puede tirar como hoja).
    private static func file(_ url: URL) -> Item? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true, let img = NSImage(contentsOf: url), let data = jpeg(img) {
            return Item(kind: "image", name: url.lastPathComponent, data: data, text: nil)
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size < limit, let data = try? Data(contentsOf: url) else { return nil }
        return Item(kind: "file", name: url.lastPathComponent, data: data, text: nil)
    }

    /// JPEG de hasta 2400 px: viaja rápido y se ve bien en el iPhone.
    static func jpeg(_ img: NSImage, max side: CGFloat = 2400) -> Data? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let k = min(1, side / max(w, h))
        let size = NSSize(width: (w * k).rounded(), height: (h * k).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
