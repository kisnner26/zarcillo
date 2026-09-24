import Combine
import SwiftUI
import WatchConnectivity
import WatchKit

/// El reloj habla con el Mac a través del iPhone: le pide agarrar cosas, le
/// avisa cuando las lanzas y recibe de él el estado (música, volumen, color).
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    static let shared = PhoneLink()

    struct Held: Equatable {
        let id: String
        let kind: String      // image, file, url, text
        let name: String
        let from: String      // mac, iphone
        let thumb: UIImage?
        let text: String?

        /// Hacia dónde va al lanzarlo: al otro lado de donde vino.
        var target: String { from == "mac" ? "iphone" : "mac" }
    }

    enum Hand: Equatable {
        case empty
        case grabbing(String)       // de dónde
        case holding(Held)
        case flying(Held)
        case landed(String)         // dónde cayó
        case failed(String)
    }

    @Published var hand: Hand = .empty
    @Published private(set) var mac = ""
    @Published private(set) var connected = false
    @Published private(set) var accentHex = 0xF27A9E
    @Published var volume = 0.5
    @Published private(set) var routines: [String] = []
    @Published private(set) var title: String?
    @Published private(set) var artist = ""
    @Published private(set) var playing = false
    @Published private(set) var reachable = false

    var accent: Color {
        Color(red: Double((accentHex >> 16) & 0xFF) / 255, green: Double((accentHex >> 8) & 0xFF) / 255,
              blue: Double(accentHex & 0xFF) / 255)
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func hello() {
        send(["op": "hello"]) { [weak self] reply in self?.apply(reply) }
    }

    // MARK: Mano

    func grab(from side: String) {
        hand = .grabbing(side)
        send(["op": "grab", "from": side])
        // Si en 12 s no llegó nada, algo falló (el iPhone dormido, el Mac lejos).
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .grabbing = self.hand else { return }
                self.hand = .failed(side == "mac" ? "el Mac no respondió" : "el iPhone no respondió")
            }
        }
    }

    func throwHeld() {
        guard case .holding(let h) = hand else { return }
        hand = .flying(h)
        send(["op": "throw", "id": h.id])
    }

    func drop() {
        if case .holding(let h) = hand { send(["op": "drop", "id": h.id]) }
        hand = .empty
    }

    // MARK: Mando

    func media(_ key: String) { send(["op": "media", "key": key]) }
    func setVolume(_ v: Double) { send(["op": "volume", "value": v]) }
    func run(_ routine: String) { send(["op": "routine", "name": routine]) }
    func lock() { send(["op": "lock"]) }

    // MARK: Transporte

    private func send(_ m: [String: Any], reply: (([String: Any]) -> Void)? = nil) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(m, replyHandler: { r in
                Task { @MainActor in reply?(r) }
            }, errorHandler: { _ in
                s.transferUserInfo(m)
            })
        } else {
            s.transferUserInfo(m)
        }
    }

    private func apply(_ s: [String: Any]) {
        if let v = s["mac"] as? String { mac = v }
        if let v = s["connected"] as? Bool { connected = v }
        if let v = s["accent"] as? Int { accentHex = v }
        if let v = s["volume"] as? Double { volume = v }
        if let v = s["routines"] as? [String] { routines = v }
        title = s["title"] as? String
        artist = s["artist"] as? String ?? ""
        playing = s["playing"] as? Bool ?? false
    }

    fileprivate func receive(_ m: [String: Any]) {
        switch m["op"] as? String {
        case "held":
            guard let id = m["id"] as? String else { return }
            let held = Held(id: id, kind: m["kind"] as? String ?? "file", name: m["name"] as? String ?? "",
                            from: m["from"] as? String ?? "mac",
                            thumb: (m["thumb"] as? Data).flatMap { UIImage(data: $0) },
                            text: m["text"] as? String)
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { hand = .holding(held) }
            WKInterfaceDevice.current().play(.click)
        case "landed":
            let to = m["to"] as? String ?? "mac"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    withAnimation(.spring(duration: 0.4)) { self?.hand = .landed(to) }
                    WKInterfaceDevice.current().play(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        MainActor.assumeIsolated {
                            if case .landed = self?.hand { withAnimation { self?.hand = .empty } }
                        }
                    }
                }
            }
        case "fail":
            hand = .failed(m["text"] as? String ?? "no se pudo")
            WKInterfaceDevice.current().play(.failure)
        default:
            apply(m)
        }
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let reach = session.isReachable
        Task { @MainActor in
            self.apply(ctx)
            self.reachable = reach
            self.hello()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reach = session.isReachable
        Task { @MainActor in
            self.reachable = reach
            if reach { self.hello() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let ctx = applicationContext
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let m = message
        Task { @MainActor in self.receive(m) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let m = userInfo
        Task { @MainActor in self.receive(m) }
    }
}
