import SwiftUI
import UIKit

// MARK: - Tono

enum Tone {
    static let ink = Color(red: 0.17, green: 0.07, blue: 0.03)
    static let peach = Color(red: 1.0, green: 0.80, blue: 0.64)
    static let orange = Color(red: 0.97, green: 0.55, blue: 0.30)
    static let ember = Color(red: 0.83, green: 0.30, blue: 0.13)
}

/// La superficie del control: naranja cálido que brilla, como una lámpara.
struct Glow: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Tone.peach, Tone.orange, Tone.ember],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.38), .clear],
                           center: UnitPoint(x: 0.28, y: 0.18), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
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
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thump() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Raíz

/// En un iPhone, horizontal = altura compacta.
extension EnvironmentValues {
    var isLandscape: Bool { verticalSizeClass == .compact }
}

struct RootView: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var page = 0

    var body: some View {
        ZStack {
            Glow()
            if case .connected = remote.phase {
                // En horizontal sobra ancho y falta alto: la barra pasa a un riel a la izquierda.
                let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    if landscape { PageBar(page: $page, vertical: true) }
                    Group {
                        switch page {
                        case 0: AppsPage()
                        case 1: DialPage()
                        case 2: GesturePage()
                        default: PadPage()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    if !landscape { PageBar(page: $page, vertical: false) }
                }
            } else {
                ConnectView()
            }
        }
        .overlay(alignment: .top) { StatusPill() }
    }
}

/// La pastilla negra de arriba: con qué Mac se habla, o lo último que pasó.
struct StatusPill: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        let connected: Bool = { if case .connected = remote.phase { true } else { false } }()
        if connected || remote.pill != nil {
            HStack(spacing: 6) {
                if remote.pill == nil {
                    Circle().fill(remote.canControl ? Color.green : Color.orange).frame(width: 6, height: 6)
                }
                Text(remote.pill ?? remote.macName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black))
            .padding(.top, 6)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct PageBar: View {
    @Binding var page: Int
    var vertical: Bool
    private let items = [("square.grid.2x2.fill", "apps"), ("dial.medium.fill", "dial"),
                         ("hand.draw.fill", "gestos"), ("hand.point.up.left.fill", "pad")]

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    Haptic.tap()
                    withAnimation(.easeInOut(duration: 0.2)) { page = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].0).font(.system(size: 17, weight: .semibold))
                        Text(items[i].1).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(page == i ? .white : .white.opacity(0.5))
                    .frame(maxWidth: vertical ? 56 : .infinity, maxHeight: vertical ? .infinity : nil)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(page == i ? Color.white.opacity(0.16) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(.black.opacity(0.82)))
        .padding(vertical ? .vertical : .horizontal, vertical ? 10 : 22)
        .padding(vertical ? .leading : .bottom, 6)
    }
}

// MARK: - Conectar

struct ConnectView: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 40) {
                    brand
                    VStack(spacing: 14) { content }.frame(maxWidth: 380)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 18) {
                    Spacer()
                    brand
                    content
                    Spacer()
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 28)
        .onChange(of: remote.phase) { _, p in
            if case .needsCode = p { code = ""; focused = true }
        }
        .onAppear { if case .needsCode = remote.phase { focused = true } }
    }

    private var brand: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(Tone.ink.opacity(0.8))
            Text("Zarcillo").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
        }
    }

    @ViewBuilder private var content: some View {
            switch remote.phase {
            case .searching:
                ProgressView().tint(Tone.ink)
                hint(remote.networkDenied
                     ? "Zarcillo no tiene permiso de red local. Actívalo en Ajustes › Zarcillo."
                     : "Buscando tu Mac… abre Zarcillo en el Mac y usa la misma Wi-Fi.")
            case .choosing:
                hint("¿Qué Mac quieres controlar?")
                VStack(spacing: 8) {
                    ForEach(remote.macs, id: \.self) { mac in
                        Button { remote.choose(mac) } label: {
                            Label(remote.name(mac), systemImage: "laptopcomputer")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: 280).padding(.vertical, 12)
                                .background(Capsule().fill(.black.opacity(0.85)))
                        }
                    }
                }
            case .needsCode(let mac):
                hint("Escribe el código que muestra \(mac) en la barra de menús (icono de la hoja).")
                codeBoxes
                if let e = remote.codeError {
                    Text(e).font(.footnote.weight(.semibold)).foregroundStyle(Color(red: 0.45, green: 0.05, blue: 0.02))
                }
            case .connecting(let mac):
                ProgressView().tint(Tone.ink)
                hint("Conectando con \(mac)…")
            case .connected:
                EmptyView()
            }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(Tone.ink.opacity(0.75)).multilineTextAlignment(.center)
    }

    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.01)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    if digits.count == 6 { remote.submit(code: digits) }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(i < chars.count ? 0.85 : 0.35)))
                    if i == 2 { Spacer().frame(width: 6) }
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Apps

struct AppsPage: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape

    var body: some View {
        ScrollView {
            if remote.apps.isEmpty {
                ProgressView().tint(Tone.ink).padding(.top, 140)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: landscape ? 70 : 74), spacing: 16)],
                      spacing: landscape ? 16 : 22) {
                ForEach(remote.apps) { app in
                    Button {
                        Haptic.thump()
                        remote.launch(app)
                    } label: {
                        VStack(spacing: 6) {
                            if let image = remote.icons[app.id] {
                                Image(uiImage: image).resizable().interpolation(.high)
                                    .frame(width: landscape ? 62 : 70, height: landscape ? 62 : 70)
                                    .shadow(color: Tone.ink.opacity(0.35), radius: 8, y: 5)
                            }
                            Circle().fill(Tone.ink.opacity(app.running ? 0.7 : 0)).frame(width: 5, height: 5)
                        }
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(app.name)
                }
            }
            .padding(.horizontal, 20).padding(.top, landscape ? 44 : 60).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .refreshable { remote.send(.listApps) }
    }
}

// MARK: - Dial

struct DialPage: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var kind: LevelKind = .volume

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) { chips }
                    dial.padding(.vertical, 26)
                }
            } else {
                VStack(spacing: 26) {
                    HStack(spacing: 8) { chips }
                    dial.frame(maxWidth: 330, maxHeight: 330).padding(.horizontal, 20)
                }
                .padding(.top, 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(EdgeTicks())
    }

    @ViewBuilder private var chips: some View {
        chip("volumen", "speaker.wave.2.fill", .volume)
        chip("brillo", "sun.max.fill", .brightness).disabled(remote.brightness == nil)
    }

    private var dial: some View {
        Dial(value: kind == .volume ? remote.volume : (remote.brightness ?? 0),
             symbol: kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill") { value, phase in
            switch phase {
            case .began: remote.editingLevel = true
            case .changed: remote.setLevel(kind, value, final: false)
            case .ended:
                remote.setLevel(kind, value, final: true)
                remote.editingLevel = false
            }
        }
    }

    private func chip(_ title: String, _ symbol: String, _ k: LevelKind) -> some View {
        Button {
            Haptic.tap()
            kind = k
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind == k ? .white : Tone.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(kind == k ? Color.black.opacity(0.85) : Tone.ink.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct Dial: View {
    enum Phase { case began, changed, ended }

    let value: Double
    let symbol: String
    let onEdit: (Double, Phase) -> Void

    private let ticks = 49
    private let start = 135.0, sweep = 270.0
    @State private var lastTick = -1
    @State private var dragging = false
    private let selection = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach(0..<ticks, id: \.self) { i in
                    let t = Double(i) / Double(ticks - 1)
                    let on = t <= value + 0.0001
                    Capsule()
                        .fill(on ? Tone.ink : Tone.ink.opacity(0.2))
                        .frame(width: i % 6 == 0 ? 4 : 3, height: i % 6 == 0 ? 24 : 14)
                        .offset(y: -side / 2 + 16)
                        .rotationEffect(.degrees(start + sweep * t + 90))
                }
                // Marcador: un triángulo que apunta al valor.
                Image(systemName: "triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(180))
                    .offset(y: -side / 2 + 48)
                    .rotationEffect(.degrees(start + sweep * value + 90))
                Circle()
                    .fill(.black.opacity(0.88))
                    .frame(width: side * 0.5, height: side * 0.5)
                    .shadow(color: Tone.ink.opacity(0.4), radius: 14, y: 8)
                VStack(spacing: 2) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: side * 0.15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragging = true; selection.prepare(); onEdit(value, .began) }
                        onEdit(level(at: v.location, center: center), .changed)
                    }
                    .onEnded { v in
                        dragging = false
                        onEdit(level(at: v.location, center: center), .ended)
                    }
            )
            .animation(.easeOut(duration: 0.08), value: value)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Ángulo del dedo → 0…1 dentro del arco de 270°. En el hueco de abajo se
    /// pega al extremo más cercano en vez de saltar de 100 a 0.
    private func level(at p: CGPoint, center c: CGPoint) -> Double {
        var angle = atan2(p.y - c.y, p.x - c.x) * 180 / .pi - start
        while angle < 0 { angle += 360 }
        while angle >= 360 { angle -= 360 }
        let t = angle <= sweep ? angle / sweep : (angle < sweep + 45 ? 1 : 0)
        let tick = Int((t * Double(ticks - 1)).rounded())
        if tick != lastTick {
            selection.selectionChanged()
            lastTick = tick
        }
        return t
    }
}

// MARK: - Gestos

struct GesturePage: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var shown: DesktopGesture?
    @State private var clear: DispatchWorkItem?

    var body: some View {
        ZStack {
            EdgeTicks()
            VStack(spacing: 12) {
                Image(systemName: shown?.symbol ?? "hand.draw")
                    .font(.system(size: 46, weight: .light))
                Text((shown?.label ?? "desliza").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
            }
            .foregroundStyle(Tone.ink.opacity(0.85))
            .id(shown)
            .transition(.scale(scale: 0.7).combined(with: .opacity))

            VStack {
                Spacer()
                Text(landscape
                     ? "← →  escritorios   ·   ↑  Mission Control   ·   ↓  ventanas de la app   ·   doble toque  Spotlight"
                     : "← →  escritorios   ·   ↑  Mission Control\n↓  ventanas de la app   ·   doble toque  Spotlight")
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tone.ink.opacity(0.55))
                    .padding(.bottom, landscape ? 16 : 22)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { fire(.spotlight) }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
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

    private func fire(_ g: DesktopGesture) {
        Haptic.thump()
        remote.send(.gesture(g))
        withAnimation(.spring(duration: 0.3)) { shown = g }
        clear?.cancel()
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.3)) { shown = nil } }
        clear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }
}

// MARK: - Pad

struct PadPage: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var editing = false

    var body: some View {
        Group {
            if landscape {
                // El trackpad se aprovecha a lo ancho, como el de un portátil.
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        surface
                        clickRow
                    }
                    VStack(spacing: 12) {
                        HStack(spacing: 10) { mediaButtons }
                        ScrollView {
                            VStack(spacing: 8) { shortcutChips }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(width: 200)
                }
                .padding(.top, 40)
                .padding(.trailing, 6)
            } else {
                VStack(spacing: 14) {
                    surface.padding(.top, 52)
                    clickRow
                    HStack(spacing: 18) { mediaButtons }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { shortcutChips }.padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $editing) { ShortcutEditor().environmentObject(remote) }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Tone.ink.opacity(0.1))
            RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Tone.ink.opacity(0.2), lineWidth: 1)
            Text("un dedo mueve · toque = clic · dos toques = doble clic\ndos dedos desplazan · toque con dos a la vez = clic derecho\ntoca y arrastra, o mantén, para arrastrar")
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Tone.ink.opacity(0.4))
                .allowsHitTesting(false)
            Trackpad(remote: remote)
        }
    }

    // Botones de clic, como los de un portátil: para cuando un toque no es cómodo.
    private var clickRow: some View {
        HStack(spacing: 2) {
            clickButton("clic", .left)
            clickButton("clic derecho", .right)
        }
        .clipShape(Capsule())
    }

    @ViewBuilder private var mediaButtons: some View {
        media("backward.fill", .previous)
        media("playpause.fill", .playPause)
        media("forward.fill", .next)
    }

    @ViewBuilder private var shortcutChips: some View {
        ForEach(remote.shortcuts) { s in
            Button {
                Haptic.tap()
                remote.send(.shortcut(s))
            } label: {
                VStack(spacing: 1) {
                    Text(s.glyphs).font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(s.title).font(.system(size: 10, weight: .medium)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: landscape ? .infinity : nil)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.85)))
            }
            .buttonStyle(PressScale())
        }
        Button { editing = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tone.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Tone.ink.opacity(0.12)))
        }
    }

    private func clickButton(_ title: String, _ button: MouseButton) -> some View {
        Button {
            Haptic.tap()
            remote.send(.click(button: button))
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.black.opacity(0.82))
        }
        .buttonStyle(PressScale())
    }

    private func media(_ symbol: String, _ key: MediaKey) -> some View {
        Button {
            Haptic.tap()
            remote.send(.media(key))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: landscape ? 50 : 56, height: landscape ? 50 : 56)
                .background(Circle().fill(.black.opacity(0.85)))
        }
        .buttonStyle(PressScale())
    }
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
            remote.send(.move(dx: dx * gain, dy: dy * gain))
        }
        v.onScroll = { dx, dy in remote.send(.scroll(dx: dx * 2, dy: dy * 2)) }
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
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
                self.onPress?(true)
            }
        }
        for t in touches { active[t] = t.location(in: self) }
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
        for t in touches { active[t] = nil }
        guard active.isEmpty else { return }
        holdTimer?.invalidate()

        let quick = Date().timeIntervalSince(firstDown) < 0.28 && travel < 10
        if dragging {
            dragging = false
            onPress?(false)
        } else if quick {
            tapHaptic.impactOccurred()
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

// MARK: - Editor de atajos

struct ShortcutEditor: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach($remote.shortcuts) { $s in
                    NavigationLink {
                        ShortcutForm(shortcut: $s)
                    } label: {
                        HStack {
                            Text(s.title)
                            Spacer()
                            Text(s.glyphs).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { remote.shortcuts.remove(atOffsets: $0) }
                .onMove { remote.shortcuts.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    remote.shortcuts.append(Shortcut(title: "nuevo atajo", key: "a", command: true))
                } label: {
                    Label("Agregar atajo", systemImage: "plus")
                }
                Button("Restaurar los de fábrica", role: .destructive) {
                    remote.shortcuts = Shortcut.defaults
                }
            }
            .navigationTitle("Atajos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } }
            }
        }
    }
}

struct ShortcutForm: View {
    @Binding var shortcut: Shortcut

    private static let keys: [String] =
        "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        + ["space", "tab", "return", "escape", "delete", "left", "right", "up", "down", "-", "=", ",", ".", "/"]

    var body: some View {
        Form {
            Section("Nombre") {
                TextField("nombre", text: $shortcut.title)
            }
            Section("Teclas") {
                Toggle("⌘  Comando", isOn: $shortcut.command)
                Toggle("⇧  Mayúsculas", isOn: $shortcut.shift)
                Toggle("⌥  Opción", isOn: $shortcut.option)
                Toggle("⌃  Control", isOn: $shortcut.control)
                Picker("Tecla", selection: $shortcut.key) {
                    ForEach(Self.keys, id: \.self) { k in
                        Text(Shortcut(title: "", key: k).keyGlyph).tag(k)
                    }
                }
            }
            Section {
                Text(shortcut.glyphs).font(.system(size: 28, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(shortcut.title)
    }
}
