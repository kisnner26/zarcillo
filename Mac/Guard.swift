import AppKit
import AVFoundation
import CoreBluetooth
import CoreImage
import IOKit.ps
import Network

// MARK: - Guardián de biblioteca

/// Dejas el Mac en la mesa y vas por un café: si alguien toca el teclado o el
/// trackpad, lo desenchufa, lo despierta o cierra la tapa, el iPhone suena y
/// recibe una foto de la cámara del Mac. El Mac también puede sonar.
@MainActor
final class Guardian {
    private(set) var armed = false
    private(set) var siren = true
    var onAlert: ((String, Data?) -> Void)?

    private var armedAt = Date()
    private var timer: Timer?
    private var onAC = true
    private var lastAlert = Date.distantPast
    private var sound: NSSound?
    private var savedVolume: Double?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private let snap = CameraSnap()

    func arm(siren: Bool) {
        self.siren = siren
        guard !armed else { return }
        armed = true
        armedAt = Date()
        onAC = Self.onAC
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            // Cerrar la tapa duerme el Mac: hay que avisar antes de que se apague la red.
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trigger("el Mac se está durmiendo: ¿cerraron la tapa?", photo: false) }
            },
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trigger("alguien despertó la pantalla") }
            },
        ]
        let dn = DistributedNotificationCenter.default()
        distributedObservers = [
            dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trigger("alguien desbloqueó el Mac") }
            },
        ]
    }

    func setSiren(_ on: Bool) {
        siren = on
        if !on { silence() }
    }

    func disarm() {
        armed = false
        timer?.invalidate()
        timer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers = []
        distributedObservers = []
        silence()
    }

    func silence() {
        sound?.stop()
        sound = nil
        if let v = savedVolume { Volume.set(v) }
        savedVolume = nil
    }

    private static var onAC: Bool {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() != nil
    }

    private func check() {
        // Unos segundos de gracia para alejarse después de armarlo.
        guard Date().timeIntervalSince(armedAt) > 6 else { onAC = Self.onAC; return }
        let ac = Self.onAC
        if onAC, !ac { trigger("desconectaron el cargador") }
        onAC = ac
        let anyInput = CGEventType(rawValue: ~0)!
        if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput) < 0.8 {
            trigger("alguien tocó el teclado o el trackpad")
        }
    }

    private func trigger(_ reason: String, photo: Bool = true) {
        guard armed, Date().timeIntervalSince(armedAt) > 6 else { return }
        // Un toque dispara muchos eventos seguidos: un aviso cada 15 s basta.
        guard Date().timeIntervalSince(lastAlert) > 15 else { return }
        lastAlert = Date()
        if siren, photo { ring() }
        guard photo else { onAlert?(reason, nil); return }
        // Primero el aviso, al instante; la foto llega detrás.
        onAlert?(reason, nil)
        snap.take { [weak self] jpeg in
            guard let jpeg else { return }
            MainActor.assumeIsolated { self?.onAlert?(reason, jpeg) }
        }
    }

    private func ring() {
        guard sound == nil else { return }
        if savedVolume == nil { savedVolume = Volume.get() }
        Volume.set(1)
        let s = NSSound(contentsOfFile: "/System/Library/Sounds/Sosumi.aiff", byReference: true)
        s?.loops = true
        s?.play()
        sound = s
    }
}

/// Una sola foto con la cámara del Mac, con un instante para que ajuste la luz.
final class CameraSnap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "zarcillo.snap")
    private var session: AVCaptureSession?
    private var started = Date()
    private var completion: ((Data?) -> Void)?
    private let context = CIContext()

    func take(_ done: @escaping (Data?) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { done(nil) }; return }
            self.queue.async {
                guard self.session == nil,
                      let camera = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: camera) else {
                    DispatchQueue.main.async { done(nil) }
                    return
                }
                let s = AVCaptureSession()
                s.sessionPreset = .high
                guard s.canAddInput(input) else { DispatchQueue.main.async { done(nil) }; return }
                s.addInput(input)
                let out = AVCaptureVideoDataOutput()
                out.alwaysDiscardsLateVideoFrames = true
                out.setSampleBufferDelegate(self, queue: self.queue)
                if s.canAddOutput(out) { s.addOutput(out) }
                self.completion = done
                self.started = Date()
                self.session = s
                s.startRunning()
                // Si la cámara no entrega nada, no se queda encendida.
                self.queue.asyncAfter(deadline: .now() + 5) { self.finish(nil) }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard completion != nil, Date().timeIntervalSince(started) > 0.9, let px = buffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: px)
        let jpeg = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6])
        finish(jpeg)
    }

    private func finish(_ jpeg: Data?) {
        guard let done = completion else { return }
        completion = nil
        session?.stopRunning()
        session = nil
        DispatchQueue.main.async { done(jpeg) }
    }
}

// MARK: - Bloqueo por cercanía

/// El iPhone se anuncia por Bluetooth; el Mac se conecta, comprueba que es el
/// tuyo (una huella del código de enlace) y mide la señal. Si te alejas, se
/// bloquea; al volver, la pantalla se enciende y te recibe.
@MainActor
final class ProximityLock: NSObject {
    private(set) var on = UserDefaults.standard.bool(forKey: "near.on")
    private(set) var threshold = UserDefaults.standard.object(forKey: "near.threshold") as? Int ?? -72
    private(set) var rssi: Int?
    private(set) var locked = false
    var passcode = ""
    var onChange: (() -> Void)?
    var onReturn: (() -> Void)?

    private var central: CBCentralManager?
    private var phone: CBPeripheral?
    private var trusted = false
    private var smooth: Double?
    private var farSince: Date?
    private var lostSince: Date?
    private var lockedByUs = false
    private var timer: Timer?

    override init() {
        super.init()
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true; self?.onChange?() }
        }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.locked = false
                self?.lockedByUs = false
                self?.onChange?()
            }
        }
    }

    func start() {
        guard on else { return }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func configure(on: Bool, threshold: Int) {
        self.on = on
        self.threshold = min(-40, max(-100, threshold))
        UserDefaults.standard.set(on, forKey: "near.on")
        UserDefaults.standard.set(self.threshold, forKey: "near.threshold")
        if on {
            start()
        } else {
            timer?.invalidate()
            timer = nil
            if let phone { central?.cancelPeripheralConnection(phone) }
            central?.stopScan()
            phone = nil
            trusted = false
            rssi = nil
            smooth = nil
        }
        onChange?()
    }

    private func scan() {
        guard let central, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: [CBUUID(string: NearBeacon.service)])
    }

    private func tick() {
        guard on else { return }
        if trusted, let phone, phone.state == .connected {
            phone.readRSSI()
            lostSince = nil
        } else {
            scan()
            if lostSince == nil { lostSince = Date() }
        }
        let far: Bool
        if let s = smooth, trusted, phone?.state == .connected {
            far = s < Double(threshold)
        } else {
            // Sin señal: te fuiste lejos (o el iPhone se apagó). Solo cuenta si
            // antes estuvo cerca, para no bloquear apenas se activa.
            far = rssi != nil && Date().timeIntervalSince(lostSince ?? Date()) > 10
        }
        if far {
            if farSince == nil { farSince = Date() }
            if let since = farSince, Date().timeIntervalSince(since) > 6, !locked {
                lockedByUs = true
                Power.perform(.lock)
            }
        } else {
            farSince = nil
            if lockedByUs, locked {
                lockedByUs = false
                // No se puede desbloquear por ti: se enciende la pantalla lista para Touch ID.
                onReturn?()
            }
        }
    }

    fileprivate func got(_ value: Int) {
        guard value < 0 else { return }   // 127 = lectura inválida
        smooth = smooth.map { $0 * 0.7 + Double(value) * 0.3 } ?? Double(value)
        rssi = Int(smooth!.rounded())
        onChange?()
    }
}

extension ProximityLock: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { if central.state == .poweredOn { scan() } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard phone == nil || phone?.state != .connected else { return }
            phone = peripheral
            trusted = false
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            central.stopScan()
            peripheral.discoverServices([CBUUID(string: NearBeacon.service)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            smooth = nil
            onChange?()
            // Una conexión pendiente no caduca: cuando el iPhone vuelva al alcance, se retoma sola.
            if on, trusted { central.connect(peripheral) } else { phone = nil; scan() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { phone = nil; scan() }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: NearBeacon.service) }) else {
                central?.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.discoverCharacteristics([CBUUID(string: NearBeacon.token)], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let c = service.characteristics?.first(where: { $0.uuid == CBUUID(string: NearBeacon.token) }) else { return }
            peripheral.readValue(for: c)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            // Solo tu iPhone: el que conoce el código de este Mac.
            if characteristic.value == NearBeacon.token(passcode: passcode) {
                trusted = true
                peripheral.readRSSI()
            } else {
                central?.cancelPeripheralConnection(peripheral)
                phone = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        MainActor.assumeIsolated { got(RSSI.intValue) }
    }
}

// MARK: - Brote invitado

/// Un servidor web mínimo en la red local: el iPhone muestra un QR, un amigo lo
/// escanea con la cámara y, desde su navegador, lanza fotos que caen como hojas
/// en el Mac. El enlace caduca en una hora y solo acepta imágenes.
@MainActor
final class GuestSprout {
    private var listener: NWListener?
    private(set) var token: String?
    private(set) var expires: Date?
    private(set) var url: String?
    var onPhoto: ((Data, String) -> Void)?
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "zarcillo.guest")

    func open(macName: String) {
        close()
        let t = (0..<16).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! }.map(String.init).joined()
        token = t
        expires = Date().addingTimeInterval(3600)
        guard let l = try? NWListener(using: .tcp) else { return }
        let q = queue
        let page = GuestPage(macName: macName, accent: Accent.hex)
        l.newConnectionHandler = { [weak self] conn in
            GuestRequest(conn, token: t, page: page) { [weak self] data, name in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.token == t, (self.expires ?? .distantPast) > Date() else { return }
                        self.onPhoto?(data, name)
                    }
                }
            }.start(on: q)
        }
        l.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = l.port?.rawValue else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.token == t, let ip = Power.machine().ip else { return }
                    self.url = "http://\(ip):\(port)/g/\(t)"
                    self.onChange?()
                }
            }
        }
        l.start(queue: queue)
        listener = l
        // Se marchita sola al cumplir la hora.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3600) { [weak self] in
            MainActor.assumeIsolated { if self?.token == t { self?.close() } }
        }
    }

    func close() {
        listener?.cancel()
        listener = nil
        token = nil
        expires = nil
        url = nil
        onChange?()
    }
}

/// La página que ve el invitado, con el color de la app.
private struct GuestPage {
    let macName: String
    let accent: Int

    var html: String {
        let color = String(format: "#%06X", accent)
        let mac = macName.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: "&", with: "")
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <title>Zarcillo · \(mac)</title>
        <style>
        :root{--a:\(color);--ink:#F5E8DB;--body:#1B1411;--key:#2A201C}
        *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
        body{margin:0;min-height:100vh;background:radial-gradient(120% 70% at 50% 110%,color-mix(in srgb,var(--a) 45%,transparent),transparent 70%),var(--body);
        color:var(--ink);font:17px -apple-system,system-ui,sans-serif;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px 16px;text-align:center;overflow:hidden}
        h1{font:700 34px ui-rounded,-apple-system,sans-serif;margin:0 0 4px;letter-spacing:-.5px}
        p{margin:0 0 28px;opacity:.6}
        input[type=text]{width:100%;max-width:320px;height:52px;border-radius:26px;border:1px solid #3B2B25;background:var(--key);color:var(--ink);font-size:17px;padding:0 20px;margin-bottom:16px;text-align:center}
        label.btn{display:flex;align-items:center;justify-content:center;gap:10px;width:100%;max-width:320px;height:64px;border-radius:32px;background:var(--a);color:var(--body);font-weight:700;font-size:19px;box-shadow:0 10px 40px color-mix(in srgb,var(--a) 50%,transparent);transition:transform .15s}
        label.btn:active{transform:scale(.96)}
        input[type=file]{display:none}
        #s{margin-top:18px;min-height:24px;opacity:.75}
        .leaf{position:fixed;left:50%;bottom:120px;width:40px;height:40px;background:var(--a);border-radius:0 100% 0 100%;animation:up 1.4s cubic-bezier(.2,.7,.3,1) forwards;pointer-events:none}
        @keyframes up{to{transform:translate(var(--x),-80vh) rotate(540deg);opacity:0}}
        </style></head><body>
        <h1>zarcillo</h1>
        <p>lanza fotos a \(mac)</p>
        <input id="n" type="text" placeholder="tu nombre" maxlength="30">
        <label class="btn">🍃 lanzar fotos<input id="f" type="file" accept="image/*" multiple></label>
        <div id="s"></div>
        <script>
        const n=document.getElementById('n'),s=document.getElementById('s');
        n.value=localStorage.getItem('n')||'';
        function leaf(){const l=document.createElement('div');l.className='leaf';l.style.setProperty('--x',(Math.random()*200-100)+'px');document.body.appendChild(l);setTimeout(()=>l.remove(),1500)}
        async function shrink(file){const img=await createImageBitmap(file);const k=Math.min(1,2400/Math.max(img.width,img.height));
        const c=document.createElement('canvas');c.width=img.width*k;c.height=img.height*k;c.getContext('2d').drawImage(img,0,0,c.width,c.height);
        return new Promise(r=>c.toBlob(r,'image/jpeg',.85))}
        document.getElementById('f').onchange=async e=>{
          localStorage.setItem('n',n.value);let ok=0;const files=[...e.target.files];
          for(const file of files){s.textContent='lanzando '+(ok+1)+' de '+files.length+'…';
            try{const body=await shrink(file);const r=await fetch(location.pathname+'/drop?name='+encodeURIComponent(n.value||'alguien'),{method:'POST',body});
              if(r.ok){ok++;leaf()}else{s.textContent=r.status==410?'este enlace ya caducó':'no se pudo lanzar';return}}
            catch(_){s.textContent='no se pudo lanzar';return}}
          s.textContent=ok==1?'¡cayó en el Mac!':'¡cayeron '+ok+' fotos en el Mac!';e.target.value=''};
        </script></body></html>
        """
    }
}

/// Una petición HTTP: se lee la cabecera, luego el cuerpo según su largo, y se responde y cierra.
private final class GuestRequest: @unchecked Sendable {
    private let conn: NWConnection
    private let token: String
    private let page: GuestPage
    private let onPhoto: (Data, String) -> Void
    private var buffer = Data()
    private var keepAlive: GuestRequest?
    private static let limit = 30 * 1024 * 1024

    init(_ conn: NWConnection, token: String, page: GuestPage, onPhoto: @escaping (Data, String) -> Void) {
        self.conn = conn
        self.token = token
        self.page = page
        self.onPhoto = onPhoto
    }

    func start(on queue: DispatchQueue) {
        keepAlive = self
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.keepAlive = nil
            default: break
            }
        }
        conn.start(queue: queue)
        read()
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in self?.conn.cancel() }
    }

    private func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > Self.limit { self.respond(413, "text/plain", Data("muy grande".utf8)); return }
            if self.tryHandle() { return }
            if done || error != nil { self.conn.cancel(); return }
            self.read()
        }
    }

    /// true si ya respondió.
    private func tryHandle() -> Bool {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { respond(400, "text/plain", Data()); return true }
        let method = String(parts[0]), target = String(parts[1])
        let path = target.split(separator: "?").first.map(String.init) ?? target
        let base = "/g/\(token)"

        if method == "GET", path == base {
            respond(200, "text/html; charset=utf-8", Data(page.html.utf8))
            return true
        }
        if method == "POST", path == base + "/drop" {
            let length = lines.first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard length > 0, length < Self.limit else { respond(400, "text/plain", Data()); return true }
            let bodyStart = end.upperBound
            guard buffer.count - bodyStart >= length else { return false }
            let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
            guard NSImage(data: body) != nil else { respond(415, "text/plain", Data("solo imágenes".utf8)); return true }
            var name = "alguien"
            if let q = URLComponents(string: target)?.queryItems?.first(where: { $0.name == "name" })?.value,
               !q.trimmingCharacters(in: .whitespaces).isEmpty {
                name = String(q.prefix(30))
            }
            onPhoto(body, name)
            respond(200, "text/plain", Data("ok".utf8))
            return true
        }
        // Cualquier otra dirección, o un enlace viejo.
        respond(path.hasPrefix("/g/") ? 410 : 404, "text/html; charset=utf-8",
                Data("<meta name=viewport content='width=device-width'><body style='font:18px -apple-system;background:#1B1411;color:#F5E8DB;text-align:center;padding-top:40vh'>este brote ya se marchitó 🍂".utf8))
        return true
    }

    private func respond(_ code: Int, _ type: String, _ body: Data) {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 410: "Gone", 413: "Payload Too Large", 415: "Unsupported Media Type"][code] ?? "OK"
        var out = Data("HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { [weak self] _ in self?.conn.cancel() })
    }
}
