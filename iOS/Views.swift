import SwiftUI
import UIKit

// MARK: - Tono

/// La paleta del panel de navegación (anillo y perilla): cerámica cálida. No cambia
/// con el resto del diseño.
enum Panel {
    static let ink = Color(red: 0.96, green: 0.91, blue: 0.86)
    static let body = Color(red: 0.106, green: 0.078, blue: 0.067)
    static let recess = Color(red: 0.07, green: 0.051, blue: 0.043)
    static let key = Color(red: 0.165, green: 0.125, blue: 0.11)
    static let stroke = Color(red: 0.23, green: 0.17, blue: 0.145)
    static var ember: Color { Theme.shared.accent }
    static var emberDeep: Color { Theme.shared.accent.mix(with: .black, by: 0.28) }
    static var onEmber: Color { Theme.shared.isLight ? body : ink }
    static let leaf = Color(red: 0.62, green: 0.85, blue: 0.62)
}

/// Invernadero de noche: verde casi negro, vidrio esmerilado con filos de luz y
/// texto blanco frío. Es la paleta de todo lo que no es el panel.
enum Tone {
    /// Texto: blanco frío, como luz de luna.
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.92)
    /// El fondo de la noche.
    static let body = Color(red: 0.035, green: 0.062, blue: 0.052)
    /// Hueco: vidrio oscuro. Tarjeta: vidrio un poco más claro. Filo: la luz en el borde del vidrio.
    static let recess = Color(red: 0.05, green: 0.085, blue: 0.072).opacity(0.72)
    static let key = Color.white.opacity(0.065)
    static let stroke = Color.white.opacity(0.11)
    /// El acento que eligió el usuario.
    static var ember: Color { Theme.shared.accent }
    static var emberDeep: Color { Theme.shared.accent.mix(with: .black, by: 0.28) }
    /// Texto sobre el acento.
    static var onEmber: Color { Theme.shared.isLight ? Color(red: 0.04, green: 0.06, blue: 0.05) : .white }
    static let leaf = Color(red: 0.55, green: 0.86, blue: 0.62)
    /// Verde de invernadero para detalles y líneas.
    static let moss = Color(red: 0.36, green: 0.62, blue: 0.48)
    // Nombres viejos, para los efectos que aún los usan.
    static var peach: Color { Theme.shared.accent.mix(with: .white, by: 0.45) }
    static var orange: Color { ember }
}

/// Tipografía del nuevo diseño: títulos en serif, como etiquetas de herbario.
enum Typo {
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func label(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static func catalog(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

/// Superficie de vidrio esmerilado con filo de luz arriba: el material del nuevo diseño.
struct Glass: ViewModifier {
    var radius: CGFloat = 22
    var tint: Color = .clear

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                // Sin desenfoque propio: las fichas ya viven sobre el escenario de vidrio, y
                // decenas de desenfoques a la vez pesaban mucho en la GPU.
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.085), tint.opacity(0.10), Color.white.opacity(0.03)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06), .white.opacity(0.10)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
    }
}

extension View {
    func glass(_ radius: CGFloat = 22, tint: Color = .clear) -> some View { modifier(Glass(radius: radius, tint: tint)) }
}

/// El fondo: noche de invernadero. Arriba, luz de luna fría y sombras de hojas
/// que se mecen; abajo, el calor del acento donde vive el panel.
struct Glow: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduce || ProcessInfo.processInfo.isLowPowerModeEnabled)) { tl in
            let t = Float(reduce ? 0 : tl.date.timeIntervalSinceReferenceDate)
            let warm = Tone.ember.opacity(0.30 + 0.05 * Double(sin(t * 0.7)))
            let moon = Color(red: 0.16, green: 0.26, blue: 0.23)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + 0.05 * sin(t * 0.2), 0], [1, 0],
                    [0, 0.5 + 0.03 * sin(t * 0.3)], [0.5 + 0.06 * sin(t * 0.25), 0.58], [1, 0.5 + 0.03 * cos(t * 0.3)],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Tone.body.mix(with: moon, by: 0.55), moon, Tone.body.mix(with: moon, by: 0.4),
                    Tone.body, Tone.body.mix(with: Tone.moss, by: 0.06), Tone.body,
                    Panel.body.mix(with: Tone.ember, by: 0.14), warm, Panel.body.mix(with: Tone.ember, by: 0.14),
                ]
            )
        }
        .overlay(LeafShadows().opacity(reduce ? 0.5 : 1))
        .overlay(Grain(opacity: 0.05))
        .ignoresSafeArea()
    }
}

/// Sombras de hojas grandes y difusas que se mecen despacio, como luz entre plantas.
/// Se dibujan una sola vez (con su desenfoque); el vaivén es solo una transformación.
struct LeafShadows: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var sway = false

    var body: some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 22))
            for k in 0..<9 {
                let fx = (Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
                let fy = (Double(k) * 0.23 + 0.05).truncatingRemainder(dividingBy: 0.55)
                var c = ctx
                c.translateBy(x: fx * size.width, y: fy * size.height)
                c.rotate(by: .degrees(Double(k) * 41))
                let h = size.width * (0.28 + 0.12 * ((Double(k) * 0.61).truncatingRemainder(dividingBy: 1)))
                c.fill(LeafShape().path(in: CGRect(x: -h * 0.28, y: -h / 2, width: h * 0.56, height: h)),
                       with: .color(.black.opacity(0.22)))
            }
        }
        .drawingGroup()
        .rotationEffect(.degrees(sway ? 1.6 : -1.6), anchor: .top)
        .offset(x: sway ? 8 : -8)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { sway = true }
        }
        .allowsHitTesting(false)
    }
}

/// Grano de cerámica: una baldosa de ruido que se genera una sola vez y se
/// repite. Sin él las superficies oscuras se ven planas, como plástico.
struct Grain: View {
    var opacity: Double

    private static let tile: UIImage = {
        let side = 96
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            var rng = SystemRandomNumberGenerator()
            for y in 0..<side {
                for x in 0..<side {
                    let v = CGFloat(Double(rng.next() % 1000) / 1000)
                    ctx.cgContext.setFillColor(UIColor(white: v, alpha: 1).cgColor)
                    ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// Regla de marcas a lo largo de los bordes.
struct EdgeTicks: View {
    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 10, step: CGFloat = 16
            let color = GraphicsContext.Shading.color(Tone.ink.opacity(0.32))
            func tick(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: color, style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            var i = 0
            var x = inset + step
            while x < size.width - inset {
                let long = i % 5 == 0
                tick(CGPoint(x: x, y: inset), CGPoint(x: x, y: inset + (long ? 12 : 6)), long ? 1.6 : 1)
                tick(CGPoint(x: x, y: size.height - inset), CGPoint(x: x, y: size.height - inset - (long ? 12 : 6)), long ? 1.6 : 1)
                x += step; i += 1
            }
            i = 0
            var y = inset + step
            while y < size.height - inset {
                let long = i % 5 == 0
                tick(CGPoint(x: inset, y: y), CGPoint(x: inset + (long ? 12 : 6), y: y), long ? 1.6 : 1)
                tick(CGPoint(x: size.width - inset, y: y), CGPoint(x: size.width - inset - (long ? 12 : 6), y: y), long ? 1.6 : 1)
                y += step; i += 1
            }
        }
        .allowsHitTesting(false)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.25), value: configuration.isPressed)
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thump() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Raíz

/// Horizontal = la ventana es más ancha que alta. Se mide el tamaño real y no
/// la clase de tamaño: en la Duplicación del iPhone la ventana puede estar
/// acostada con la clase de tamaño todavía "regular".
extension EnvironmentValues {
    @Entry var measuredLandscape: Bool? = nil
    var isLandscape: Bool { measuredLandscape ?? (verticalSizeClass == .compact) }
}

struct RootView: View {
    @EnvironmentObject private var remote: Remote
    /// El instrumento se muestra un momento después de conectar: primero la
    /// enredadera se agarra al Mac y luego se entra, como si se abriera su pantalla.
    @State private var inside = false
    /// Se acaba de escribir el código: toca la celebración completa.
    @State private var pairedNow = false
    @AppStorage("app.orientation") private var orientation: AppOrientation = .auto

    var body: some View {
        ForceLandscape(enabled: orientation == .landscape) {
            GeometryReader { g in
                root.environment(\.measuredLandscape, g.size.width > g.size.height * 1.05)
            }
        }
        .background(Tone.body.ignoresSafeArea())
    }

    private var root: some View {
        ZStack {
            Glow()
            if inside {
                Instrument()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                ConnectView(onCode: { pairedNow = true })
                    .transition(.opacity.combined(with: .scale(scale: 1.25)))
            }
        }
        .onAppear { if case .connected = remote.phase { inside = true } }
        .onChange(of: remote.phase) { _, phase in
            guard case .connected = phase else {
                if inside { withAnimation(.spring(duration: 0.5)) { inside = false } }
                return
            }
            // Al reconectar solo (volver a la app), casi sin espera; tras el código, la escena entera.
            let hold = pairedNow ? 1.9 : 0.5
            pairedNow = false
            Task {
                try? await Task.sleep(for: .seconds(hold))
                guard case .connected = remote.phase else { return }
                withAnimation(.spring(duration: 0.7, bounce: 0.15)) { inside = true }
            }
        }
    }
}

// MARK: - Gestos

struct GesturePage: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var shown: DesktopGesture?
    @State private var clear: DispatchWorkItem?
    @State private var burst = 0
    @State private var flashed: DesktopGesture = .spaceRight
    @State private var trail: [(CGPoint, Date)] = []

    var body: some View {
        ZStack {
            // El área de deslizar: un marco punteado con aire alrededor.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Tone.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7]))
                .padding(Space.m)
                .allowsHitTesting(false)
            EdgeFlash(gesture: flashed)
                .keyframeAnimator(initialValue: 0.0, trigger: burst) { v, o in v.opacity(o) } keyframes: { _ in
                    LinearKeyframe(1, duration: 0.07)
                    CubicKeyframe(0, duration: 0.7)
                }
            TimelineView(.animation(paused: trail.isEmpty)) { tl in
                FingerTrail(points: trail, now: tl.date)
            }
            // La flecha sale disparada hacia donde va el escritorio.
            Image(systemName: flashed.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Tone.ember)
                .shadow(color: Tone.ember, radius: 14)
                .keyframeAnimator(initialValue: FlyState(), trigger: burst) { v, f in
                    v.offset(x: flashed.direction.dx * f.travel, y: flashed.direction.dy * f.travel)
                        .scaleEffect(f.scale)
                        .opacity(f.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.travel) {
                        LinearKeyframe(-30, duration: 0.001)
                        CubicKeyframe(170, duration: 0.55)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.12)
                        CubicKeyframe(0, duration: 0.45)
                    }
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.25, duration: 0.2)
                        CubicKeyframe(flashed == .spotlight ? 2.2 : 0.8, duration: 0.4)
                    }
                }
                .allowsHitTesting(false)
            VStack(spacing: Space.s) {
                Image(systemName: shown?.symbol ?? "hand.draw")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(shown == nil ? Tone.ink.opacity(0.8) : Tone.ember)
                Text((shown?.label ?? "desliza").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Tone.ink.opacity(0.85))
                if shown == nil {
                    Text("doble toque · Spotlight")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tone.ink.opacity(0.4))
                        .padding(.top, 2)
                }
            }
            .id(shown)
            .transition(.scale(scale: 0.7).combined(with: .opacity))

            // Cada indicación vive en el borde hacia el que se desliza.
            hint(.missionControl, "arrow.up", "Mission Control").frame(maxHeight: .infinity, alignment: .top)
            hint(.appWindows, "arrow.down", "ventanas").frame(maxHeight: .infinity, alignment: .bottom)
            hint(.spaceLeft, "arrow.left", "escritorio").frame(maxWidth: .infinity, alignment: .leading)
            hint(.spaceRight, "arrow.right", "escritorio").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { fire(.spotlight) }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    let now = Date()
                    trail.append((v.location, now))
                    trail.removeAll { now.timeIntervalSince($0.1) > 0.45 }
                }
                .onEnded { v in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { trail.removeAll() }
                guard hypot(v.translation.width, v.translation.height) > 30 else { return }
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > abs(dy) {
                    // Como en el trackpad: deslizar a la izquierda trae el escritorio de la derecha.
                    fire(dx < 0 ? .spaceRight : .spaceLeft)
                } else {
                    fire(dy < 0 ? .missionControl : .appWindows)
                }
            }
        )
    }

    /// Indicación de borde: se enciende con el color de acento al usarla.
    private func hint(_ g: DesktopGesture, _ symbol: String, _ text: String) -> some View {
        let lit = shown == g
        let vertical = g == .missionControl || g == .appWindows
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 4))
        return layout {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(lit ? Tone.ember : Tone.ink.opacity(0.45))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(lit ? Tone.ember.opacity(0.15) : Tone.key.opacity(0.6)))
        .padding(Space.l)
        .scaleEffect(lit ? 1.08 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: lit)
        .allowsHitTesting(false)
    }

    private func fire(_ g: DesktopGesture) {
        Haptic.thump()
        remote.send(.gesture(g))
        flashed = g
        burst += 1
        withAnimation(.spring(duration: 0.3)) { shown = g }
        clear?.cancel()
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.3)) { shown = nil } }
        clear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }
}

struct FlyState {
    var travel = 0.0
    var opacity = 0.0
    var scale = 1.0
}

/// Superficie táctil con varios dedos. SwiftUI no distingue cuántos dedos hay
/// en un arrastre, así que se baja a UIKit.
struct Trackpad: UIViewRepresentable {
    let remote: Remote

    func makeUIView(context: Context) -> TrackpadSurface {
        let v = TrackpadSurface()
        v.onMove = { dx, dy in
            // Aceleración: movimientos lentos son precisos, rápidos cruzan la pantalla.
            let speed = hypot(dx, dy)
            let gain = 1.3 + min(speed, 30) * 0.11
            remote.move(dx: dx * gain, dy: dy * gain)
        }
        v.onScroll = { dx, dy in remote.scroll(dx: dx * 2, dy: dy * 2) }
        v.onClick = { remote.send(.click(button: $0)) }
        v.onPress = { remote.send(.press(down: $0)) }
        return v
    }

    func updateUIView(_ uiView: TrackpadSurface, context: Context) {}
}

final class TrackpadSurface: UIView {
    var onMove: ((Double, Double) -> Void)?
    var onScroll: ((Double, Double) -> Void)?
    var onClick: ((MouseButton) -> Void)?
    var onPress: ((Bool) -> Void)?

    /// Dedos apoyados EN ESTA VISTA, con su última posición. No se usa
    /// `event.allTouches`: incluye toques de otras vistas y toques viejos que
    /// el sistema aún no dio por terminados, y un solo dedo se leía como dos.
    private var active: [UITouch: CGPoint] = [:]
    private var firstDown = Date.distantPast
    /// Dedos que tocaron casi a la vez (en 0,2 s). Un segundo dedo que llega
    /// tarde no convierte el toque en clic derecho.
    private var together = 0
    private var travel: CGFloat = 0
    private var scrolled = false
    private var holdTimer: Timer?
    private var dragging = false
    private var lastTap = Date.distantPast
    private var tapDragArmed = false

    private var velocity = CGVector.zero
    private var lastScrollAt = CACurrentMediaTime()
    private var momentum: CADisplayLink?

    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let holdHaptic = UIImpactFeedbackGenerator(style: .rigid)

    /// Luz bajo cada dedo. Son capas de Core Animation y no vistas de SwiftUI:
    /// siguen al dedo a 120 Hz sin reconstruir nada.
    private var glows: [UITouch: CALayer] = [:]
    private var lastPoint = CGPoint.zero
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        layer.cornerRadius = 30
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    // MARK: Efectos

    private func makeGlow(at p: CGPoint) -> CALayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.bounds = CGRect(x: 0, y: 0, width: 150, height: 150)
        g.position = p
        g.opacity = 0
        layer.addSublayer(g)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        g.add(fade, forKey: "in")
        g.opacity = 1
        return g
    }

    private func dropGlow(_ g: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { g.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = g.opacity
        fade.toValue = 0
        fade.duration = 0.35
        g.add(fade, forKey: "out")
        g.opacity = 0
        CATransaction.commit()
    }

    /// En modo arrastre la luz se vuelve más grande y cálida: se nota que "agarraste" algo.
    private func setDragLook(_ on: Bool) {
        for g in glows.values {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            g.setAffineTransform(on ? CGAffineTransform(scaleX: 1.5, y: 1.5) : .identity)
            (g as? CAGradientLayer)?.colors = on
                ? [UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.8).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
                : [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            CATransaction.commit()
        }
    }

    /// Onda del clic: una para el izquierdo, dos para el derecho.
    private func ripple(at p: CGPoint, rings: Int) {
        for i in 0..<rings {
            let ring = CAShapeLayer()
            let r: CGFloat = 34
            ring.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).cgPath
            ring.position = p
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor.white.cgColor
            ring.lineWidth = 2.5
            ring.opacity = 0
            layer.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.35
            scale.toValue = reduceMotion ? 0.35 : 1.7
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.95
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 0.5
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.1
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .backwards
            CATransaction.begin()
            CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
            ring.add(group, forKey: "ripple")
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()
        if active.isEmpty {
            firstDown = Date()
            together = 0
            travel = 0
            scrolled = false
            // Tocar justo después de un toque y mover = arrastrar, como en el trackpad del Mac.
            tapDragArmed = Date().timeIntervalSince(lastTap) < 0.3
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, self.active.count == 1, self.travel < 8, !self.dragging else { return }
                self.dragging = true
                self.holdHaptic.impactOccurred()
                self.setDragLook(true)
                self.onPress?(true)
            }
        }
        for t in touches {
            let p = t.location(in: self)
            active[t] = p
            glows[t] = makeGlow(at: p)
            lastPoint = p
        }
        if Date().timeIntervalSince(firstDown) < 0.2 { together = max(together, active.count) }
        if active.count > 1 { holdTimer?.invalidate() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var dx: CGFloat = 0, dy: CGFloat = 0, n: CGFloat = 0
        for t in touches {
            guard let prev = active[t] else { continue }
            let p = t.location(in: self)
            dx += p.x - prev.x
            dy += p.y - prev.y
            active[t] = p
            n += 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glows[t]?.position = p
            CATransaction.commit()
            lastPoint = p
        }
        guard n > 0 else { return }
        dx /= n
        dy /= n
        travel += hypot(dx, dy)
        if travel > 8, !dragging { holdTimer?.invalidate() }

        if active.count >= 2, !dragging {
            scrolled = true
            let now = CACurrentMediaTime()
            let dt = max(now - lastScrollAt, 1.0 / 240)
            lastScrollAt = now
            // Velocidad suavizada para la inercia al soltar.
            velocity = CGVector(dx: velocity.dx * 0.6 + dx / dt * 0.4, dy: velocity.dy * 0.6 + dy / dt * 0.4)
            onScroll?(dx, dy)
        } else {
            if tapDragArmed, !dragging, travel > 4 {
                dragging = true
                holdHaptic.impactOccurred()
                setDragLook(true)
                onPress?(true)
            }
            onMove?(dx, dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for t in touches {
            active[t] = nil
            if let g = glows.removeValue(forKey: t) { dropGlow(g) }
        }
        guard active.isEmpty else { return }
        holdTimer?.invalidate()

        let quick = Date().timeIntervalSince(firstDown) < 0.28 && travel < 10
        if dragging {
            dragging = false
            onPress?(false)
        } else if quick {
            tapHaptic.impactOccurred()
            ripple(at: lastPoint, rings: together >= 2 ? 2 : 1)
            if together >= 2 {
                onClick?(.right)
            } else {
                onClick?(.left)
                lastTap = Date()
            }
        } else if scrolled, CACurrentMediaTime() - lastScrollAt < 0.08 {
            startMomentum()
        }
        tapDragArmed = false
    }

    // MARK: Inercia del desplazamiento

    private func startMomentum() {
        guard hypot(velocity.dx, velocity.dy) > 150 else { velocity = .zero; return }
        let link = CADisplayLink(target: self, selector: #selector(glide(_:)))
        link.add(to: .main, forMode: .common)
        momentum = link
    }

    @objc private func glide(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        onScroll?(velocity.dx * dt, velocity.dy * dt)
        let decay = pow(0.05, dt)   // pierde ~95 % de la velocidad por segundo
        velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
        if hypot(velocity.dx, velocity.dy) < 20 { stopMomentum() }
    }

    private func stopMomentum() {
        momentum?.invalidate()
        momentum = nil
        velocity = .zero
    }
}

