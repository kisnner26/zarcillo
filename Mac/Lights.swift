import AppKit
import CoreMedia
import Darwin
import ScreenCaptureKit

/// Luces que siguen a la pantalla (tipo Ambilight) con focos Govee por red local.
///
/// Govee expone una API por UDP en la red local ("LAN Control", que hay que
/// activar en la app Govee Home para cada foco): se descubren con un mensaje a
/// 239.255.255.250:4001, responden en el puerto 4002 y aceptan órdenes en el
/// 4003. Es rápida y no pasa por internet, que es lo que hace falta para seguir
/// la pantalla varias veces por segundo.
final class GoveeLAN: @unchecked Sendable {
    struct Device: Hashable {
        let id: String
        let sku: String
        let ip: String
    }

    private let queue = DispatchQueue(label: "zarcillo.govee")
    private var rx: Int32 = -1
    private var tx: Int32 = -1
    private(set) var devices: [String: Device] = [:]
    var onChange: (() -> Void)?

    init() {
        queue.async { self.open() }
    }

    private func open() {
        tx = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var ttl: UInt8 = 2
        setsockopt(tx, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        rx = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var yes: Int32 = 1
        setsockopt(rx, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(rx, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(4002).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(rx, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        Thread.detachNewThread { [weak self] in self?.listen() }
    }

    private func listen() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while rx >= 0 {
            let n = recv(rx, &buffer, buffer.count, 0)
            guard n > 0 else { continue }
            let data = Data(buffer[0..<n])
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = obj["msg"] as? [String: Any], msg["cmd"] as? String == "scan",
                  let d = msg["data"] as? [String: Any],
                  let ip = d["ip"] as? String, let id = d["device"] as? String else { continue }
            let device = Device(id: id, sku: d["sku"] as? String ?? "Govee", ip: ip)
            queue.async {
                guard self.devices[id] != device else { return }
                self.devices[id] = device
                DispatchQueue.main.async { self.onChange?() }
            }
        }
    }

    func scan() {
        queue.async {
            for _ in 0..<3 {
                self.send(["msg": ["cmd": "scan", "data": ["account_topic": "reserve"]]], to: "239.255.255.250", port: 4001)
            }
        }
    }

    func color(_ r: Int, _ g: Int, _ b: Int, to ip: String) {
        queue.async {
            self.send(["msg": ["cmd": "colorwc", "data": ["color": ["r": r, "g": g, "b": b], "colorTemInKelvin": 0]]],
                      to: ip, port: 4003)
        }
    }

    func brightness(_ percent: Int, to ip: String) {
        queue.async { self.send(["msg": ["cmd": "brightness", "data": ["value": max(1, min(100, percent))]]], to: ip, port: 4003) }
    }

    func power(_ on: Bool, to ip: String) {
        queue.async { self.send(["msg": ["cmd": "turn", "data": ["value": on ? 1 : 0]]], to: ip, port: 4003) }
    }

    private func send(_ json: [String: Any], to host: String, port: UInt16) {
        guard tx >= 0, let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        _ = data.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(tx, raw.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

/// Mira la pantalla en muy baja resolución (96 píxeles de ancho) y entrega el
/// color de cada zona: izquierda, centro, derecha y toda.
final class ScreenColors: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "zarcillo.colors", qos: .userInitiated)
    var onColors: (([LightZone: (Double, Double, Double)]) -> Void)?

    func start() async {
        guard stream == nil, CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
            else { return }
            let cfg = SCStreamConfiguration()
            cfg.width = 96
            cfg.height = max(1, Int(96.0 * Double(display.height) / Double(max(display.width, 1))))
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 15)
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.showsCursor = false
            let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await s.startCapture()
            stream = s
        } catch {
            stream = nil
        }
    }

    func stop() async {
        if let s = stream { try? await s.stopCapture() }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let px = buffer.imageBuffer else { return }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px), row = CVPixelBufferGetBytesPerRow(px)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        func average(_ x0: Int, _ x1: Int) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for y in stride(from: 0, to: h, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    let p = bytes + y * row + x * 4
                    b += Double(p[0]); g += Double(p[1]); r += Double(p[2]); n += 1
                }
            }
            return n > 0 ? (r / n / 255, g / n / 255, b / n / 255) : (0, 0, 0)
        }
        let third = w / 3
        onColors?([.left: average(0, third), .center: average(third, 2 * third),
                   .right: average(2 * third, w), .all: average(0, w)])
    }
}

/// Une el descubrimiento de focos con los colores de la pantalla.
@MainActor
final class Lights {
    private let govee = GoveeLAN()
    private let colors = ScreenColors()
    private var smoothed: [String: (Double, Double, Double)] = [:]
    private var lastSent: [String: (Int, Int, Int)] = [:]
    private var lastSentAt: [String: Date] = [:]

    private(set) var ambient = false
    private(set) var brightness: Double = UserDefaults.standard.object(forKey: "lights.brightness") as? Double ?? 0.8
    /// Se llama cuando cambian los focos o el estado, para avisar al iPhone.
    var onChange: (() -> Void)?

    init() {
        govee.onChange = { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
        colors.onColors = { [weak self] zones in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(zones) } }
        }
        govee.scan()
    }

    var devices: [LightInfo] {
        govee.devices.values.sorted { $0.ip < $1.ip }.map {
            LightInfo(id: $0.id, sku: $0.sku, ip: $0.ip, zone: zone(of: $0.id))
        }
    }

    func scan() { govee.scan() }

    func setAmbient(_ on: Bool) {
        ambient = on
        Task {
            if on {
                for d in govee.devices.values {
                    govee.power(true, to: d.ip)
                    govee.brightness(Int(brightness * 100), to: d.ip)
                }
                await colors.start()
            } else {
                await colors.stop()
            }
        }
        onChange?()
    }

    func setBrightness(_ v: Double) {
        brightness = min(1, max(0.01, v))
        UserDefaults.standard.set(brightness, forKey: "lights.brightness")
        for d in govee.devices.values { govee.brightness(Int(brightness * 100), to: d.ip) }
        onChange?()
    }

    func setZone(_ zone: LightZone, for id: String) {
        UserDefaults.standard.set(zone.rawValue, forKey: "lights.zone.\(id)")
        onChange?()
    }

    /// Hace parpadear un foco para saber cuál es cuál.
    func identify(_ id: String) {
        guard let d = govee.devices[id] else { return }
        let accent = Accent.hex
        let r = (accent >> 16) & 0xFF, g = (accent >> 8) & 0xFF, b = accent & 0xFF
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                if i % 2 == 0 { self.govee.color(r, g, b, to: d.ip) } else { self.govee.color(255, 255, 255, to: d.ip) }
            }
        }
    }

    private func zone(of id: String) -> LightZone {
        LightZone(rawValue: UserDefaults.standard.string(forKey: "lights.zone.\(id)") ?? "") ?? .all
    }

    /// Color suavizado y con más saturación, a lo sumo ~8 veces por segundo por
    /// foco, y solo si cambió lo suficiente: los focos no dan abasto con más, y
    /// sin suavizar la luz parpadea.
    private func apply(_ zones: [LightZone: (Double, Double, Double)]) {
        guard ambient else { return }
        let now = Date()
        for d in govee.devices.values {
            guard let target = zones[zone(of: d.id)] else { continue }
            let prev = smoothed[d.id] ?? target
            let s = (prev.0 + (target.0 - prev.0) * 0.35,
                     prev.1 + (target.1 - prev.1) * 0.35,
                     prev.2 + (target.2 - prev.2) * 0.35)
            smoothed[d.id] = s
            let rgb = vivid(s)
            if let last = lastSent[d.id],
               abs(last.0 - rgb.0) + abs(last.1 - rgb.1) + abs(last.2 - rgb.2) < 12 { continue }
            if let at = lastSentAt[d.id], now.timeIntervalSince(at) < 0.12 { continue }
            govee.color(rgb.0, rgb.1, rgb.2, to: d.ip)
            lastSent[d.id] = rgb
            lastSentAt[d.id] = now
        }
    }

    /// Las pantallas suelen tener colores apagados: se sube la saturación para
    /// que la luz del cuarto se note, y se evita el negro total.
    private func vivid(_ c: (Double, Double, Double)) -> (Int, Int, Int) {
        let color = NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let boosted = NSColor(hue: h, saturation: min(1, s * 1.5), brightness: max(0.12, min(1, v * 1.3)), alpha: 1)
        return (Int(boosted.redComponent * 255), Int(boosted.greenComponent * 255), Int(boosted.blueComponent * 255))
    }
}
