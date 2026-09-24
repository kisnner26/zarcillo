import SwiftUI

// Efectos compartidos. Todos respetan "Reducir movimiento": con esa opción
// activada, lo que se mueve solo se queda quieto y lo que responde a un toque
// se reduce a un cambio de opacidad.

/// Ondas que se expanden desde el centro: "estoy buscando".
struct RadarRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var go = false
    var color: Color = Tone.ink

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(go ? 2.4 : 0.6)
                    .opacity(go ? 0 : 0.8)
                    .animation(reduce ? nil : .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                               value: go)
            }
        }
        .onAppear { go = !reduce }
        .allowsHitTesting(false)
    }
}

/// Flota suavemente, como una hoja en el aire.
struct Floating: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        if reduce {
            content
        } else {
            content.phaseAnimator([false, true]) { v, up in
                v.offset(y: up ? -5 : 5).rotationEffect(.degrees(up ? -5 : 5))
            } animation: { _ in .easeInOut(duration: 2.4) }
        }
    }
}

/// Sacudida de "no": se dispara cada vez que cambia `trigger`.
struct Shake: ViewModifier {
    var trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { v, x in
            v.offset(x: x)
        } keyframes: { _ in
            for x in [-12.0, 10, -8, 6, -3, 0] { SpringKeyframe(x, duration: 0.06) }
        }
    }
}

/// Rebote al pulsar: se encoge, se pasa y vuelve.
struct Boing: ViewModifier {
    var trigger: Int
    var amount = 0.14

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { v, s in
            v.scaleEffect(s)
        } keyframes: { _ in
            CubicKeyframe(1 - amount, duration: 0.08)
            SpringKeyframe(1 + amount * 0.8, duration: 0.16)
            SpringKeyframe(1, duration: 0.3, spring: .bouncy)
        }
    }
}

/// Anillo que se expande y desaparece: "¡hecho!".
struct Ripple: View {
    var trigger: Int
    var cornerRadius: CGFloat = 18
    var color: Color = .white

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(color, lineWidth: 2.5)
            .keyframeAnimator(initialValue: RippleState(), trigger: trigger) { v, s in
                v.scaleEffect(s.scale).opacity(s.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.001)
                    CubicKeyframe(1.55, duration: 0.55)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.001)
                    CubicKeyframe(0, duration: 0.55)
                }
            }
            .allowsHitTesting(false)
    }
}

struct RippleState {
    var scale = 1.0
    var opacity = 0.0
}

extension View {
    func floating() -> some View { modifier(Floating()) }
    func shake(_ trigger: Int) -> some View { modifier(Shake(trigger: trigger)) }
    func boing(_ trigger: Int, amount: Double = 0.14) -> some View { modifier(Boing(trigger: trigger, amount: amount)) }
}

/// Resplandor que entra por el borde del que llega el escritorio nuevo.
struct EdgeFlash: View {
    let gesture: DesktopGesture

    var body: some View {
        GeometryReader { geo in
            let thick: CGFloat = 140
            switch gesture {
            case .spaceRight:
                LinearGradient(colors: [.clear, .white.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: thick).frame(maxWidth: .infinity, alignment: .trailing)
            case .spaceLeft:
                LinearGradient(colors: [.white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: thick).frame(maxWidth: .infinity, alignment: .leading)
            case .missionControl:
                LinearGradient(colors: [.white.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: thick).frame(maxHeight: .infinity, alignment: .top)
            case .appWindows:
                LinearGradient(colors: [.clear, .white.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: thick).frame(maxHeight: .infinity, alignment: .bottom)
            case .spotlight:
                RadialGradient(colors: [.white.opacity(0.7), .clear], center: .center,
                               startRadius: 0, endRadius: min(geo.size.width, geo.size.height) * 0.5)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension DesktopGesture {
    /// Hacia dónde vuela la flecha al disparar el gesto.
    var direction: CGVector {
        switch self {
        case .spaceLeft: CGVector(dx: -1, dy: 0)
        case .spaceRight: CGVector(dx: 1, dy: 0)
        case .missionControl: CGVector(dx: 0, dy: -1)
        case .appWindows: CGVector(dx: 0, dy: 1)
        case .spotlight: .zero
        }
    }
}

/// Estela luminosa que sigue al dedo y se apaga sola.
struct FingerTrail: View {
    let points: [(CGPoint, Date)]
    let now: Date

    var body: some View {
        Canvas { ctx, _ in
            guard points.count > 1 else { return }
            ctx.addFilter(.blur(radius: 1.5))
            for i in 1..<points.count {
                let age = now.timeIntervalSince(points[i].1)
                let life = max(0, 1 - age / 0.45)
                guard life > 0 else { continue }
                var p = Path()
                p.move(to: points[i - 1].0)
                p.addLine(to: points[i].0)
                let w = 3 + 13 * life * Double(i) / Double(points.count)
                ctx.stroke(p, with: .color(.white.opacity(0.75 * life)),
                           style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
