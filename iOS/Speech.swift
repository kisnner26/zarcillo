import AVFoundation
import Speech
import SwiftUI

/// Reconocimiento de voz continuo en el propio iPhone.
///
/// El reconocedor de Apple va acumulando una sola frase que crece sin fin;
/// para una clase de una hora eso no sirve. Aquí, cuando hay una pausa de
/// 1,4 s, lo dicho se da por cerrado como una frase y se empieza otra.
@MainActor
final class LiveSpeech: ObservableObject {
    @Published private(set) var partial = ""
    @Published private(set) var running = false
    @Published private(set) var denied = false
    /// Nivel de la voz 0…1, para animar.
    @Published private(set) var level: Double = 0

    /// Palabras que conviene reconocer bien (nombres de apps, escenas).
    var hints: [String] = []
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var pause: DispatchWorkItem?

    /// El audio llega en un hilo propio; la petición activa se comparte así.
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SFSpeechAudioBufferRecognitionRequest?
        func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); value = r; lock.unlock() }
        func append(_ b: AVAudioPCMBuffer) { lock.lock(); value?.append(b); lock.unlock() }
        func end() { lock.lock(); value?.endAudio(); lock.unlock() }
    }

    func start(locale: String) async {
        guard !running else { return }
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { denied = true; return }
        denied = false
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let box = self.box
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            box.append(buffer)
            // Nivel aproximado para la animación.
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: n, by: 8) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, n / 8)))
            let lvl = min(1, Double(rms) * 12)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.level = lvl } }
        }
        engine.prepare()
        do { try engine.start() } catch { return }
        running = true
        begin()
    }

    func stop() {
        guard running else { return }
        running = false
        pause?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        box.end()
        task?.cancel()
        task = nil
        if !partial.isEmpty { onFinal?(partial) }
        partial = ""
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func begin() {
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.addsPunctuation = true
        r.contextualStrings = hints
        if recognizer?.supportsOnDeviceRecognition == true { r.requiresOnDeviceRecognition = true }
        box.set(r)
        task = recognizer?.recognitionTask(with: r) { [weak self] result, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.close(text)
                        } else {
                            self.partial = text
                            self.onPartial?(text)
                            self.schedulePause(for: text)
                        }
                    } else if error != nil {
                        self.close(self.partial)
                    }
                }
            }
        }
    }

    /// 1,4 s sin cambios = fin de frase.
    private func schedulePause(for text: String) {
        pause?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.partial == text else { return }
                self.close(text)
            }
        }
        pause = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func close(_ text: String) {
        pause?.cancel()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { onFinal?(t) }
        partial = ""
        task?.cancel()
        box.end()
        if running { begin() }
    }
}
