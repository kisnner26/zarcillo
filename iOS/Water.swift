import SwiftUI

/// Ondas de agua donde tocas la pantalla del Mac: tres anillos que se abren uno
/// tras otro, con un borde claro y otro oscuro para que parezcan relieve de vidrio,
/// y una lente suave en el centro. El clic ya salió: esto solo se ve encima.
struct WaterRipple: View {
    let point: CGPoint
    let trigger: Int

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, t in
                Canvas { ctx, _ in
                    for i in 0..<3 {
                        let p = min(1, max(0, (t - Double(i) * 0.14) / 0.72))
                        guard p > 0, p < 1 else { continue }
                        let ease = 1 - pow(1 - p, 2.4)
                        let r = 10 + ease * 118
                        let fade = pow(1 - p, 1.3)
                        let ring = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                        // Cresta clara por fuera y valle oscuro por dentro: relieve.
                        ctx.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(0.55 * fade)), lineWidth: 3.2 * (1 - p) + 0.6)
                        ctx.stroke(Path(ellipseIn: ring.insetBy(dx: 3.5, dy: 3.5)), with: .color(.black.opacity(0.28 * fade)), lineWidth: 2.4 * (1 - p) + 0.4)
                        if i == 0 {
                            ctx.fill(Path(ellipseIn: ring), with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.16 * fade), .clear]),
                                center: .zero, startRadius: 0, endRadius: r))
                        }
                    }
                }
                .frame(width: 320, height: 320)
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
            } keyframes: { _ in
                KeyframeTrack { LinearKeyframe(0, duration: 0.001); CubicKeyframe(1, duration: 1.05) }
            }
            .position(point)
            .allowsHitTesting(false)
    }
}
