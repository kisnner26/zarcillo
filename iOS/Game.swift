import CoreMotion
import SwiftUI
import UIKit

// MARK: - Teclas

/// Cómo se traducen los controles a teclas del Mac.
enum GameLayout: String, CaseIterable, Identifiable {
    case arrows, wasd
    var id: String { rawValue }
    var title: String { self == .arrows ? "flechas" : "WASD" }
    var detail: String { self == .arrows ? "flechas · Z X C V" : "W A S D · espacio ⇧ E Q" }
    var up: String { self == .arrows ? "up" : "w" }
    var down: String { self == .arrows ? "down" : "s" }
    var left: String { self == .arrows ? "left" : "a" }
    var right: String { self == .arrows ? "right" : "d" }
    var a: String { self == .arrows ? "z" : "space" }
    var b: String { self == .arrows ? "x" : "shift" }
    var x: String { self == .arrows ? "c" : "e" }
    var y: String { self == .arrows ? "v" : "q" }
}

enum GameMode: String, CaseIterable, Identifiable {
    case pad, wheel
    var id: String { rawValue }
    var title: String { self == .pad ? "mando" : "volante" }
    var symbol: String { self == .pad ? "gamecontroller.fill" : "steeringwheel" }
}

/// Lleva la cuenta de qué teclas están abajo: solo manda cambios, y al salir suelta todo.
@MainActor
final class GameKeys: ObservableObject {
    @Published private(set) var down: Set<String> = []
    weak var remote: Remote?
    private let tap = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    func set(_ key: String, _ on: Bool, haptic: Bool = true) {
        guard on != down.contains(key) else { return }
        if on { down.insert(key) } else { down.remove(key) }
        remote?.send(.gameKey(name: key, down: on))
        if haptic {
            if on { tap.impactOccurred(intensity: 0.9) } else { soft.impactOccurred(intensity: 0.4) }
        }
    }

    func releaseAll() {
        down = []
        remote?.send(.gameRelease)
    }
}

// MARK: - Página

struct GamePage: View {
    @EnvironmentObject private var remote: Remote
    @AppStorage("game.mode") private var mode: GameMode = .pad
    @AppStorage("game.layout") private var layout: GameLayout = .arrows
    @AppStorage("game.feel") private var feel = true
    @State private var playing = false

    var body: some View {
        StageScroll(spacing: Space.m) {
            Image(systemName: mode.symbol).font(.system(size: 50, weight: .semibold)).foregroundStyle(Tone.ember)
                .contentTransition(.symbolEffect(.replace))
                .padding(.top, Space.s)

            HStack(spacing: Space.s) {
                ForEach(GameMode.allCases) { m in
                    choice(m.title, m.symbol, selected: mode == m) { mode = m }
                }
            }
            HStack(spacing: Space.s) {
                ForEach(GameLayout.allCases) { l in
                    choice(l.title, nil, detail: l.detail, selected: layout == l) { layout = l }
                }
            }
            ToggleCard(title: "sentir el juego", detail: "el iPhone vibra con los golpes y explosiones que suenan en el Mac", isOn: $feel)

            Button {
                Detents.shared.press()
                playing = true
            } label: {
                Label("jugar", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Tone.onEmber)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Capsule().fill(Tone.ember))
            }
            .buttonStyle(PressScale())

            Hint(mode == .pad
                 ? "Gira el iPhone en horizontal. Palanca a la izquierda, botones A B X Y a la derecha: el juego los recibe como teclas del Mac."
                 : "Sujétalo en horizontal como un volante y gíralo. Derecha acelera, izquierda frena. Toca el centro del volante para volver a centrarlo.")
        }
        .fullScreenCover(isPresented: $playing) {
            GameController(mode: mode, layout: layout, feel: feel).environmentObject(remote)
        }
    }

    private func choice(_ title: String, _ symbol: String?, detail: String? = nil, selected: Bool, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(duration: 0.3)) { run() }
        } label: {
            VStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 20, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                if let detail { Text(detail).font(.system(size: 11)).opacity(0.7).multilineTextAlignment(.center) }
            }
            .foregroundStyle(selected ? Tone.onEmber : Tone.ink.opacity(0.85))
            .frame(maxWidth: .infinity).frame(minHeight: 76)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? Tone.ember : Tone.key))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tone.stroke, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Mando a pantalla completa

struct GameController: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let mode: GameMode
    let layout: GameLayout
    let feel: Bool
    @StateObject private var keys = GameKeys()

    var body: some View {
        ForceLandscape { pad }
            .background(Tone.body.ignoresSafeArea())
    }

    private var pad: some View {
        GeometryReader { geo in
            ZStack {
                background
                if mode == .pad {
                    PadLayout(layout: layout, keys: keys, size: geo.size)
                } else {
                    WheelLayout(layout: layout, keys: keys, size: geo.size)
                }
            }
            .overlay(alignment: .top) { topBar }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            keys.remote = remote
            Orientation.request(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
            if feel { remote.send(.beats(true)) }
        }
        .onDisappear {
            keys.releaseAll()
            if feel { remote.send(.beats(false)) }
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.request(.allButUpsideDown, restoring: true)
        }
    }

    private var background: some View {
        ZStack {
            Tone.body
            RadialGradient(colors: [Tone.ember.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 420)
            // Hojas grabadas en la carcasa.
            Canvas { ctx, size in
                for k in 0..<14 {
                    let x = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1) * size.width
                    let y = (Double(k) * 0.414 + 0.2).truncatingRemainder(dividingBy: 1) * size.height
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(Double(k) * 47))
                    c.fill(LeafShape().path(in: CGRect(x: -9, y: -18, width: 18, height: 36)), with: .color(Tone.ink.opacity(0.035)))
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Space.s) {
            GameButton(label: "select", key: "escape", keys: keys, style: .pill)
            Button {
                Detents.shared.press()
                dismiss()
            } label: {
                GlyphView(.close, size: 17).foregroundStyle(Tone.ink.opacity(0.8))
                    .frame(width: 44, height: 44).background(Circle().fill(Tone.key))
                    .overlay(Circle().stroke(Tone.stroke, lineWidth: 1))
            }
            .accessibilityLabel("salir del mando")
            GameButton(label: "start", key: "return", keys: keys, style: .pill)
        }
        .padding(.top, 14)
    }
}

// MARK: - Botón

struct GameButton: View {
    enum Style { case face(Color), pill, pedal(String) }
    let label: String
    let key: String
    @ObservedObject var keys: GameKeys
    var style: Style = .face(.white)
    @State private var pressed = false

    var body: some View {
        content
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(duration: 0.15, bounce: 0.4), value: pressed)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true; keys.set(key, true) }
                }
                .onEnded { _ in
                    pressed = false
                    keys.set(key, false)
                })
            .accessibilityLabel(label)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .face(let tint):
            Text(label).font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(pressed ? Tone.onEmber : tint)
                .frame(width: 72, height: 72)
                .background(Circle().fill(pressed ? Tone.ember : Tone.key))
                .overlay(Circle().stroke(pressed ? Tone.ember : tint.opacity(0.45), lineWidth: 2))
                .shadow(color: pressed ? Tone.ember.opacity(0.7) : .black.opacity(0.4), radius: pressed ? 16 : 8, y: pressed ? 0 : 4)
        case .pill:
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(1)
                .foregroundStyle(pressed ? Tone.onEmber : Tone.ink.opacity(0.7))
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(pressed ? Tone.ember : Tone.key))
                .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
                .frame(minHeight: 44)
        case .pedal(let symbol):
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 30, weight: .bold))
                Text(label).font(.system(size: 13, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(1)
            }
            .foregroundStyle(pressed ? Tone.onEmber : Tone.ink.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(pressed ? Tone.ember : Tone.key))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
            .shadow(color: pressed ? Tone.ember.opacity(0.6) : .clear, radius: 18)
        }
    }
}

// MARK: - Mando

private struct PadLayout: View {
    let layout: GameLayout
    @ObservedObject var keys: GameKeys
    let size: CGSize

    var body: some View {
        let stick = min(size.height * 0.62, 200)
        HStack {
            Stick(layout: layout, keys: keys, diameter: stick)
                .padding(.leading, max(40, size.width * 0.07))
            Spacer()
            // A B X Y en rombo, como un mando.
            ZStack {
                GameButton(label: "Y", key: layout.y, keys: keys, style: .face(Color(red: 0.98, green: 0.82, blue: 0.4))).offset(y: -72)
                GameButton(label: "X", key: layout.x, keys: keys, style: .face(Color(red: 0.55, green: 0.75, blue: 1))).offset(x: -72)
                GameButton(label: "B", key: layout.b, keys: keys, style: .face(Color(red: 1, green: 0.55, blue: 0.5))).offset(x: 72)
                GameButton(label: "A", key: layout.a, keys: keys, style: .face(Tone.leaf)).offset(y: 72)
            }
            .frame(width: 220, height: 220)
            .padding(.trailing, max(40, size.width * 0.07))
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 30)
    }
}

/// Palanca de 8 direcciones: arrastras desde cualquier punto de su círculo.
private struct Stick: View {
    let layout: GameLayout
    @ObservedObject var keys: GameKeys
    let diameter: CGFloat
    @State private var knob: CGSize = .zero

    var body: some View {
        let r = diameter / 2
        ZStack {
            Circle().fill(Tone.recess)
                .overlay(Circle().stroke(Tone.stroke, lineWidth: 1.5))
            // Marcas de las cuatro direcciones, encendidas si están pulsadas.
            ForEach(0..<4, id: \.self) { i in
                let key = [layout.up, layout.right, layout.down, layout.left][i]
                Image(systemName: "chevron.up").font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(keys.down.contains(key) ? Tone.ember : Tone.ink.opacity(0.25))
                    .offset(y: -r + 20)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Circle()
                .fill(RadialGradient(colors: [Tone.key.mix(with: .white, by: 0.12), Tone.key], center: .topLeading, startRadius: 0, endRadius: r))
                .frame(width: diameter * 0.46, height: diameter * 0.46)
                .overlay(Circle().stroke(knob == .zero ? Tone.stroke : Tone.ember, lineWidth: 2))
                .overlay(Image(systemName: "leaf.fill").font(.system(size: 16)).foregroundStyle(Tone.ember.opacity(0.8)))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                .offset(knob)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - r, dy = v.location.y - r
                let len = max(1, hypot(dx, dy))
                let limit = r * 0.5
                let k = min(1, limit / len)
                knob = CGSize(width: dx * k, height: dy * k)
                apply(dx, dy, len, dead: r * 0.18)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.25, bounce: 0.5)) { knob = .zero }
                for key in [layout.up, layout.down, layout.left, layout.right] { keys.set(key, false, haptic: false) }
            })
        .accessibilityLabel("palanca de dirección")
    }

    /// Diagonales incluidas: cada eje cuenta si pesa al menos un 38 % del empuje.
    private func apply(_ dx: CGFloat, _ dy: CGFloat, _ len: CGFloat, dead: CGFloat) {
        let active = len > dead
        keys.set(layout.left, active && dx < -len * 0.38)
        keys.set(layout.right, active && dx > len * 0.38)
        keys.set(layout.up, active && dy < -len * 0.38)
        keys.set(layout.down, active && dy > len * 0.38)
    }
}

// MARK: - Volante

@MainActor
private final class Steering: ObservableObject {
    @Published var angle = 0.0          // grados, positivo = derecha
    private let motion = CMMotionManager()
    private var base: Double?
    private var timer: Timer?
    private var phase = 0.0
    private var lastSide = 0
    weak var keys: GameKeys?
    var left = "left", right = "right"

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            // Girar el iPhone sobre su pantalla, como un volante: el ángulo de la gravedad en el plano de la pantalla.
            let a = atan2(g.y, g.x) * 180 / .pi
            if self.base == nil { self.base = a }
            var d = a - self.base!
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            self.angle += (max(-90, min(90, d)) - self.angle) * 0.35
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        timer?.invalidate()
        keys?.set(left, false, haptic: false)
        keys?.set(right, false, haptic: false)
    }

    func recenter() { base = nil }

    /// Giro suave con teclas: la tecla se pulsa una fracción del tiempo según cuánto giras
    /// (como un mando analógico); a partir de 32° queda pulsada del todo.
    private func tick() {
        guard let keys else { return }
        let mag = abs(angle)
        let duty = min(1, max(0, (mag - 5) / 27))
        phase = (phase + 1 / 60 / 0.12).truncatingRemainder(dividingBy: 1)
        let on = duty >= 0.97 || phase < duty
        let side = duty == 0 ? 0 : (angle > 0 ? 1 : -1)
        keys.set(right, on && side == 1, haptic: false)
        keys.set(left, on && side == -1, haptic: false)
        if side != lastSide {
            if side != 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
            lastSide = side
        }
    }
}

private struct WheelLayout: View {
    let layout: GameLayout
    @ObservedObject var keys: GameKeys
    let size: CGSize
    @StateObject private var steer = Steering()

    var body: some View {
        let wheel = min(size.height * 0.7, 250)
        HStack(spacing: Space.l) {
            GameButton(label: "freno", key: layout.down, keys: keys, style: .pedal("arrow.down.to.line"))
                .frame(width: max(120, size.width * 0.2))
            VStack(spacing: Space.s) {
                SteeringWheel(angle: steer.angle)
                    .frame(width: wheel, height: wheel)
                    .contentShape(Circle())
                    .onTapGesture {
                        Detents.shared.press()
                        steer.recenter()
                    }
                    .accessibilityLabel("volante; toca para centrarlo")
                HStack(spacing: Space.s) {
                    GameButton(label: "nitro", key: layout.a, keys: keys, style: .pill)
                    GameButton(label: "B", key: layout.b, keys: keys, style: .pill)
                }
            }
            GameButton(label: "acelerar", key: layout.up, keys: keys, style: .pedal("arrow.up.to.line"))
                .frame(width: max(120, size.width * 0.2))
        }
        .padding(.horizontal, max(30, size.width * 0.05))
        .padding(.top, 70).padding(.bottom, 26)
        .onAppear {
            steer.keys = keys
            steer.left = layout.left
            steer.right = layout.right
            steer.start()
        }
        .onDisappear { steer.stop() }
    }
}

/// Un volante con aro, tres radios y la hoja en el centro; un arco muestra cuánto giras.
private struct SteeringWheel: View {
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // Arco de giro.
                Circle().trim(from: 0, to: min(0.25, abs(angle) / 360 * 1.0))
                    .stroke(Tone.ember, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: angle < 0 ? -1 : 1)
                    .frame(width: d, height: d)
                Group {
                    Circle().stroke(
                        AngularGradient(colors: [Tone.key.mix(with: .white, by: 0.15), Tone.key, Tone.key.mix(with: .white, by: 0.15)], center: .center),
                        lineWidth: d * 0.1)
                        .frame(width: d * 0.84, height: d * 0.84)
                    // Marca superior.
                    Capsule().fill(Tone.ember).frame(width: d * 0.035, height: d * 0.1).offset(y: -d * 0.42)
                    ForEach([90.0, 210.0, 330.0], id: \.self) { a in
                        Capsule().fill(Tone.key).frame(width: d * 0.06, height: d * 0.34)
                            .offset(y: d * 0.17).rotationEffect(.degrees(a - 90))
                    }
                    Circle().fill(Tone.recess).frame(width: d * 0.26, height: d * 0.26)
                        .overlay(Circle().stroke(Tone.stroke, lineWidth: 1.5))
                        .overlay(Image(systemName: "leaf.fill").font(.system(size: d * 0.09)).foregroundStyle(Tone.ember))
                }
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
