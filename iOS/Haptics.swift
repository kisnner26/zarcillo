import CoreHaptics
import UIKit

/// Hápticos a medida. Los generadores de UIKit dan un golpe fijo; Core Haptics
/// deja variar fuerza y filo, así la perilla se siente más pesada o más suelta
/// según lo rápido que gire.
final class Detents {
    static let shared = Detents()
    private var engine: CHHapticEngine?

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private func transient(_ intensity: Float, _ sharpness: Float, at t: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    /// Una marca de la perilla. `speed` 0…1: más rápido = más suave y más agudo.
    func detent(speed: Double) {
        let s = Float(min(1, max(0, speed)))
        play([transient(0.75 - s * 0.35, 0.45 + s * 0.4)])
    }

    /// El tope: 0 o 100. Un golpe seco y un rebote.
    func wall() {
        play([transient(1, 0.2), transient(0.4, 0.1, at: 0.05)])
    }

    /// Presionar la perilla: se hunde y vuelve.
    func press() {
        play([transient(0.9, 0.35), transient(0.35, 0.6, at: 0.07)])
    }
}
