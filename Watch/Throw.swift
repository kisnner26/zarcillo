import CoreMotion
import WatchKit

/// El gesto de lanzar, el mismo de Girasol: un pico brusco de aceleración de la
/// muñeca. Se dispara en cuanto la señal empieza a bajar del pico, para que se
/// sienta inmediato, y espera un momento antes de aceptar otro.
struct ThrowDetector {
    var threshold = 1.15      // g, sin gravedad
    var cooldown = 1.0
    var minDuration = 0.03

    private var above = false
    private var startT = 0.0
    private var peak = 0.0
    private var lastEmit = -Double.infinity

    /// Devuelve la fuerza del lanzamiento (en g) cuando termina el gesto.
    mutating func feed(t: Double, accel: CMAcceleration) -> Double? {
        let mag = (accel.x * accel.x + accel.y * accel.y + accel.z * accel.z).squareRoot()
        if !above {
            guard mag >= threshold, t - lastEmit >= cooldown else { return nil }
            above = true
            startT = t
            peak = mag
            return nil
        }
        peak = max(peak, mag)
        guard mag < peak * 0.85 || t - startT > 0.35 else { return nil }
        above = false
        guard t - startT >= minDuration else { return nil }
        lastEmit = t
        return peak
    }
}

/// Escucha la muñeca mientras hay algo en la mano. Una sesión extendida mantiene
/// los sensores vivos aunque la pantalla se apague al girar la muñeca.
@MainActor
final class Wrist: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = Wrist()
    private let motion = CMMotionManager()
    private var detector = ThrowDetector()
    private var runtime: WKExtendedRuntimeSession?
    var onThrow: ((Double) -> Void)?

    func listen() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        detector = ThrowDetector()
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            MainActor.assumeIsolated {
                guard let self, let power = self.detector.feed(t: m.timestamp, accel: m.userAcceleration) else { return }
                self.onThrow?(power)
            }
        }
        if runtime == nil || runtime?.state == .invalid {
            let rt = WKExtendedRuntimeSession()
            rt.delegate = self
            rt.start()
            runtime = rt
        }
    }

    func stop() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        if runtime?.state == .running { runtime?.invalidate() }
        runtime = nil
    }

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
}
