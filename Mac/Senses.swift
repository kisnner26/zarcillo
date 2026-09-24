import AppKit
import AVFoundation
import CoreMediaIO
import ScreenCaptureKit
import Vision

// MARK: - Sopla

/// Soplar al iPhone: todas las apps se esconden y queda el escritorio limpio;
/// soplar otra vez las devuelve.
@MainActor
enum Scatter {
    private static var hidden: [NSRunningApplication] = []

    static func toggle() -> Bool {
        if hidden.isEmpty {
            hidden = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isHidden && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    && $0.bundleIdentifier != "com.apple.finder"
            }
            hidden.forEach { $0.hide() }
            return true
        } else {
            hidden.forEach { $0.unhide() }
            hidden = []
            return false
        }
    }
}

// MARK: - Sentir la música

/// Escucha el audio del propio Mac (lo que sale por los parlantes) y detecta
/// los golpes: cuando la energía de un tramo supera bastante al promedio
/// reciente. Usa ScreenCaptureKit, que también captura el audio del sistema.
final class BeatDetector: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "zarcillo.beats", qos: .userInteractive)
    private var average: Float = 0
    private var lastBeat = Date.distantPast
    var onBeat: ((Double) -> Void)?

    var running: Bool { stream != nil }

    func start() async {
        guard stream == nil, CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 44_100
            cfg.channelCount = 1
            // La imagen no se usa: la mínima posible.
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
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
        guard type == .audio else { return }
        var list = AudioBufferList()
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr,
              let data = list.mBuffers.mData else { return }
        let n = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard n > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        var energy: Float = 0
        for i in 0..<n { energy += samples[i] * samples[i] }
        energy /= Float(n)

        // Promedio móvil lento; un golpe es un salto claro por encima.
        average = average * 0.95 + energy * 0.05
        let now = Date()
        if energy > average * 1.8, energy > 0.0004, now.timeIntervalSince(lastBeat) > 0.22 {
            lastBeat = now
            let strength = Double(min(1, (energy / max(average, 0.0001) - 1.8) / 3 + 0.35))
            onBeat?(strength)
        }
    }
}

// MARK: - Cámara en uso

/// Si alguna app está usando la cámara (Zoom, Meet, FaceTime…). Se pregunta a
/// CoreMediaIO, sin abrir la cámara.
enum CameraWatcher {
    static var inUse: Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            if CMIOObjectGetPropertyData(id, &runAddr, 0, nil, runSize, &runSize, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }
}

// MARK: - Postura

/// Mira con la cámara del Mac, dos veces por segundo y en baja resolución, la
/// posición de la cabeza respecto de los hombros. Los primeros segundos toma tu
/// postura de referencia; si durante un minuto la cabeza queda bastante más
/// baja o más cerca de la pantalla, avisa. No guarda ni envía imágenes.
final class PostureCoach: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "zarcillo.posture")
    private var baseline: (neck: CGFloat, width: CGFloat)?
    private var samples: [(CGFloat, CGFloat)] = []
    private var badSince: Date?
    private var lastFrame = Date.distantPast
    private var lastAlert = Date.distantPast
    var onState: ((Bool) -> Void)?
    var onAlert: (() -> Void)?
    private(set) var running = false

    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            self.queue.async { self.configure() }
        }
    }

    func stop() {
        queue.async {
            self.session.stopRunning()
            self.running = false
            self.baseline = nil
            self.samples = []
            self.badSince = nil
        }
    }

    private func configure() {
        if session.inputs.isEmpty {
            session.sessionPreset = .low
            guard let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.startRunning()
        running = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) > 0.5, let px = buffer.imageBuffer else { return }
        lastFrame = now
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cvPixelBuffer: px).perform([request])
        guard let body = request.results?.first,
              let neck = try? body.recognizedPoint(.neck), neck.confidence > 0.3,
              let left = try? body.recognizedPoint(.leftShoulder), let right = try? body.recognizedPoint(.rightShoulder),
              left.confidence > 0.3, right.confidence > 0.3,
              let nose = try? body.recognizedPoint(.nose), nose.confidence > 0.3 else { return }
        // Distancia nariz–cuello (vertical) y ancho de hombros (cercanía a la pantalla).
        let neckGap = nose.location.y - neck.location.y
        let shoulders = abs(left.location.x - right.location.x)

        guard let base = baseline else {
            samples.append((neckGap, shoulders))
            if samples.count >= 16 {
                let n = CGFloat(samples.count)
                baseline = (samples.map(\.0).reduce(0, +) / n, samples.map(\.1).reduce(0, +) / n)
            }
            return
        }
        // Encorvado: la cabeza se hunde hacia los hombros, o te acercas mucho.
        let slouching = neckGap < base.neck * 0.72 || shoulders > base.width * 1.3
        DispatchQueue.main.async { self.onState?(slouching) }
        if slouching {
            if badSince == nil { badSince = now }
            if let since = badSince, now.timeIntervalSince(since) > 60, now.timeIntervalSince(lastAlert) > 300 {
                lastAlert = now
                DispatchQueue.main.async { self.onAlert?() }
            }
        } else {
            badSince = nil
        }
    }
}
