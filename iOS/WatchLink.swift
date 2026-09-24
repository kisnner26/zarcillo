import Combine
import Photos
import SwiftUI
import UIKit
import UserNotifications
import WatchConnectivity

/// La foto de arriba de la pila en "fotos": lo primero que el reloj agarra del iPhone.
@MainActor
final class PhotoTray {
    static let shared = PhotoTray()
    var top: Data?
}

/// Puente con el reloj. El reloj no puede hablar con el Mac por su cuenta, así
/// que el iPhone hace de mensajero: el reloj "agarra" algo del Mac o del
/// iPhone (el iPhone lo guarda y le manda una miniatura) y al lanzarlo con la
/// muñeca el iPhone lo entrega del otro lado.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    struct Item {
        let id: String
        var kind: String          // image, file, url, text
        var name: String
        var data: Data?
        var text: String?
        var from: String          // mac, iphone
    }

    private weak var remote: Remote?
    private var hand: [String: Item] = [:]
    private var waitingForMac = false
    private var bag: Set<AnyCancellable> = []
    private var pendingURL: URL?

    func start(_ remote: Remote) {
        self.remote = remote
        remote.onGrabbed = { [weak self] kind, name, data, text in
            self?.grabbedFromMac(kind: kind, name: name, data: data, text: text)
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // Lo que el reloj muestra (música, volumen, escenas, color) va como contexto: solo cuenta el último.
        Publishers.Merge4(remote.$nowPlaying.map { _ in () }, remote.$volume.map { _ in () },
                          remote.$phase.map { _ in () }, remote.$routines.map { _ in () })
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.pushState() }
            .store(in: &bag)
        NotificationCenter.default.addObserver(forName: Theme.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushState() }
        }
    }

    /// Al volver a la app, abrir el link que llegó mientras estaba en segundo plano.
    func becameActive() {
        if let url = pendingURL {
            pendingURL = nil
            UIApplication.shared.open(url)
        }
    }

    // MARK: Estado para el reloj

    private func state() -> [String: Any] {
        var s: [String: Any] = [
            "mac": remote?.macName ?? "",
            "connected": { if case .connected = remote?.phase { return true } else { return false } }(),
            "accent": Int(Theme.shared.hex),
            "volume": remote?.volume ?? 0.5,
            "routines": remote?.routines.map(\.name) ?? [],
        ]
        if let np = remote?.nowPlaying {
            s["title"] = np.title
            s["artist"] = np.artist
            s["playing"] = np.playing
        }
        return s
    }

    private func pushState() {
        guard WCSession.default.activationState == .activated, WCSession.default.isPaired else { return }
        try? WCSession.default.updateApplicationContext(state())
    }

    private func tell(_ message: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(message, replyHandler: nil) { _ in s.transferUserInfo(message) }
        } else {
            s.transferUserInfo(message)
        }
    }

    // MARK: Agarrar

    /// Del iPhone: la foto que tengas en la pila de "fotos", o la última de tu carrete.
    private func grabFromPhone() {
        if let data = PhotoTray.shared.top {
            give(Item(id: UUID().uuidString, kind: "image", name: "foto del iPhone", data: data, text: nil, from: "iphone"))
            return
        }
        Task {
            guard let data = await Self.latestPhoto() else {
                tell(["op": "fail", "text": "abre Zarcillo en el iPhone y dale acceso a Fotos"])
                return
            }
            give(Item(id: UUID().uuidString, kind: "image", name: "última foto", data: data, text: nil, from: "iphone"))
        }
    }

    /// Desde la pila de "fotos": esta foto pasa a la mano del reloj.
    func handToWatch(_ data: Data) {
        give(Item(id: UUID().uuidString, kind: "image", name: "foto del iPhone", data: data, text: nil, from: "iphone"))
        remote?.flash("en la mano del reloj: lánzala con la muñeca")
    }

    private func grabFromMac() {
        guard let remote else { return }
        waitingForMac = true
        remote.deliver(.grab)
    }

    private func grabbedFromMac(kind: String, name: String, data: Data?, text: String?) {
        guard waitingForMac else { return }
        waitingForMac = false
        give(Item(id: UUID().uuidString, kind: kind, name: name, data: data, text: text, from: "mac"))
    }

    private func give(_ item: Item) {
        hand = [item.id: item]     // una mano: un objeto a la vez
        var m: [String: Any] = ["op": "held", "id": item.id, "kind": item.kind, "name": item.name, "from": item.from]
        if item.kind == "image", let d = item.data, let thumb = Self.thumbnail(d) { m["thumb"] = thumb }
        if let t = item.text { m["text"] = String(t.prefix(200)) }
        tell(m)
    }

    // MARK: Lanzar

    private func land(_ id: String) {
        guard let item = hand.removeValue(forKey: id) else {
            tell(["op": "fail", "text": "se me cayó: vuelve a agarrarlo"])
            return
        }
        let bg = UIApplication.shared.beginBackgroundTask(withName: "lanzar")
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 20) { UIApplication.shared.endBackgroundTask(bg) } }
        if item.from == "iphone" {
            toMac(item)
            tell(["op": "landed", "id": id, "to": "mac"])
        } else {
            toPhone(item)
            tell(["op": "landed", "id": id, "to": "iphone"])
        }
    }

    private func toMac(_ item: Item) {
        guard let remote else { return }
        switch item.kind {
        case "image": if let d = item.data { remote.deliver(.photoToss(data: d, angle: 0, side: "top")) }
        case "file": if let d = item.data { remote.deliver(.file(name: item.name, data: d)) }
        case "url": if let t = item.text { remote.deliver(.openURL(t)) }
        default: if let t = item.text { remote.deliver(.pushClipboard(text: t, image: nil)) }
        }
    }

    private func toPhone(_ item: Item) {
        let active = UIApplication.shared.applicationState == .active
        switch item.kind {
        case "image":
            guard let d = item.data, let img = UIImage(data: d) else { return }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            remote?.showLeaf(img)
            if !active { notify("Cayó en tu iPhone", "\(item.name) está en Fotos") }
        case "url":
            guard let t = item.text, let url = URL(string: t) else { return }
            if active { UIApplication.shared.open(url) } else {
                pendingURL = url
                notify("Cayó en tu iPhone", "toca para abrir \(url.host ?? t)")
            }
        case "file":
            guard let d = item.data else { return }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Del Mac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? d.write(to: dir.appendingPathComponent(item.name))
            remote?.flash("\(item.name) está en Archivos › Zarcillo")
            if !active { notify("Cayó en tu iPhone", "\(item.name) está en Archivos › Zarcillo › Del Mac") }
        default:
            guard let t = item.text else { return }
            UIPasteboard.general.string = t
            remote?.flash("texto del Mac copiado")
            if !active { notify("Cayó en tu iPhone", "texto copiado: \(t.prefix(60))") }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Imágenes

    static func thumbnail(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side: CGFloat = 180
        let k = side / max(img.size.width, img.size.height)
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.6)
    }

    static func latestPhoto() async -> Data? {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return nil }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject else { return nil }
        return await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            o.isSynchronous = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 2400, height: 2400),
                                                  contentMode: .aspectFit, options: o) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                c.resume(returning: img?.jpegData(compressionQuality: 0.85))
            }
        }
    }

    // MARK: Órdenes del reloj

    fileprivate func handle(_ m: [String: Any], reply: (([String: Any]) -> Void)?) {
        let op = m["op"] as? String ?? ""
        switch op {
        case "hello":
            reply?(state())
            return
        case "grab":
            (m["from"] as? String) == "mac" ? grabFromMac() : grabFromPhone()
        case "throw":
            if let id = m["id"] as? String { land(id) }
        case "drop":
            if let id = m["id"] as? String { hand[id] = nil }
        case "media":
            if let k = m["key"] as? String, let key = MediaKey(rawValue: k) { remote?.deliver(.media(key)) }
        case "volume":
            if let v = m["value"] as? Double { remote?.setLevel(.volume, v, final: true) }
        case "routine":
            if let name = m["name"] as? String, let r = remote?.routines.first(where: { $0.name == name }) {
                remote?.deliver(.runRoutine(r))
            }
        case "lock":
            remote?.deliver(.power(.lock))
        default:
            break
        }
        reply?(["ok": true])
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let m = message
        Task { @MainActor in self.handle(m, reply: nil) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let m = message
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in self.handle(m, reply: reply) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let m = userInfo
        Task { @MainActor in self.handle(m, reply: nil) }
    }
}
