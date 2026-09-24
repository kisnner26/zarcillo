import SwiftUI
import UIKit

// La app como un solo instrumento:
//
//  · el cuerpo es de Brasa: cerámica oscura, perilla naranja, pad hundido;
//  · la navegación es de Órbita: los modos giran en un anillo alrededor de la
//    perilla y arriba se lee en grande lo que está elegido;
//  · el alma es de Enredadera: la perilla dibuja un zarcillo que se enrosca con
//    el valor, las apps son brotes en un tallo y "más" es un tallo vertical.
//
// La perilla es el control universal: girar elige o ajusta, tocar ejecuta.

enum DeckMode: Int, CaseIterable, Identifiable {
    case pad, apps, music, screen, more
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .pad: "pad"
        case .apps: "apps"
        case .music: "música"
        case .screen: "pantalla"
        case .more: "más"
        }
    }

    var symbol: String {
        switch self {
        case .pad: "hand.point.up.left"
        case .apps: "leaf"
        case .music: "music.note"
        case .screen: "display"
        case .more: "ellipsis"
        }
    }
}

enum MoreItem: Int, CaseIterable, Identifiable {
    case brightness, gestures, laser, power, routines, shortcuts
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .brightness: "brillo"
        case .gestures: "gestos"
        case .laser: "láser"
        case .power: "energía"
        case .routines: "escenas"
        case .shortcuts: "atajos"
        }
    }

    var detail: String {
        switch self {
        case .brightness: "gira la perilla"
        case .gestures: "escritorios y Spotlight"
        case .laser: "apunta con el iPhone"
        case .power: "bloquear, suspender, despertar"
        case .routines: "varias acciones de un toque"
        case .shortcuts: "teclas del pad"
        }
    }

    var symbol: String {
        switch self {
        case .brightness: "sun.max"
        case .gestures: "hand.draw"
        case .laser: "light.beacon.max"
        case .power: "power"
        case .routines: "sparkles"
        case .shortcuts: "command"
        }
    }
}

/// Lo que la perilla y el escenario comparten: modo, selección y qué está abierto.
@MainActor
final class Deck: ObservableObject {
    @Published var mode: DeckMode = .pad
    @Published var appIndex = 0
    @Published var moreIndex = 0
    @Published var moreOpen: MoreItem?
    @Published var launches = 0
}

// MARK: - Raíz

struct Instrument: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @StateObject private var deck = Deck()

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Header()
                        Stage().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.leading, 16).padding(.top, 10).padding(.bottom, 8)
                    ControlDeck(ring: 104, knob: 100)
                        .frame(width: 350)
                }
            } else {
                VStack(spacing: 0) {
                    Header().padding(.horizontal, 22).padding(.top, 20)
                    Stage()
                        .padding(.horizontal, 14).padding(.top, 10)
                        .frame(maxHeight: .infinity)
                    ControlDeck(ring: 128, knob: 124)
                        .frame(height: 372)
                }
            }
        }
        .environmentObject(deck)
    }
}

// MARK: - Encabezado (Órbita)

/// Lo elegido, en grande. Cambia con un fundido cada vez que la perilla se mueve.
struct Header: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Tone.ember)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.interpolate)
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tone.ink.opacity(0.55))
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35), value: title)
    }

    private var selectedApp: AppTile? {
        remote.apps.indices.contains(deck.appIndex) ? remote.apps[deck.appIndex] : nil
    }

    private var title: String {
        switch deck.mode {
        case .pad: return "Pad"
        case .apps: return selectedApp?.name ?? "Apps"
        case .music: return remote.nowPlaying?.title ?? "Música"
        case .screen: return "Pantalla"
        case .more:
            if let open = deck.moreOpen { return open.title.capitalized }
            return MoreItem(rawValue: deck.moreIndex)?.title.capitalized ?? "Más"
        }
    }

    private var subtitle: String {
        switch deck.mode {
        case .pad: return remote.macName
        case .apps:
            guard let app = selectedApp else { return "cargando el Dock…" }
            let n = remote.windows(of: app.id).count
            if !app.running { return "cerrada · toca la perilla para abrirla" }
            return n == 1 ? "1 ventana" : "\(n) ventanas"
        case .music:
            guard let np = remote.nowPlaying else { return "nada sonando" }
            return "\(np.artist) · \(np.source)"
        case .screen: return remote.canCapture ? "toca la imagen para hacer clic" : "falta permiso en el Mac"
        case .more:
            if deck.moreOpen != nil { return "toca la perilla para volver" }
            return MoreItem(rawValue: deck.moreIndex)?.detail ?? ""
        }
    }
}

// MARK: - Escenario

/// El hueco de la cerámica donde vive el contenido de cada modo.
struct Stage: View {
    @EnvironmentObject private var deck: Deck

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Tone.recess)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Tone.stroke, lineWidth: 1.2)
            Group {
                switch deck.mode {
                case .pad: PadStage()
                case .apps: VineApps()
                case .music: MusicStage()
                case .screen: ScreenPage()
                case .more: MoreStage()
                }
            }
            .id(deck.mode)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                    removal: .opacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.spring(duration: 0.4, bounce: 0.2), value: deck.mode)
    }
}

// MARK: - Consola: anillo + perilla

struct ControlDeck: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    /// Radio del anillo de modos y diámetro de la perilla.
    let ring: CGFloat
    let knob: CGFloat
    @State private var idle: DispatchWorkItem?

    var body: some View {
        ZStack {
            OrbitRing(radius: ring)
            Knob(diameter: knob, value: knobValue, caption: caption,
                 onTick: tick, onPress: press)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Qué muestra la espiral: el volumen, o el brillo si está abierto.
    private var knobValue: Double {
        if deck.mode == .more, deck.moreOpen == .brightness { return remote.brightness ?? 0 }
        return remote.volume
    }

    private var caption: String {
        switch deck.mode {
        case .pad, .music: return "\(Int((remote.volume * 100).rounded()))"
        case .apps: return "abrir"
        case .screen: return "clic"
        case .more:
            if deck.moreOpen == .brightness { return "\(Int(((remote.brightness ?? 0) * 100).rounded()))" }
            return deck.moreOpen == nil ? "entrar" : "volver"
        }
    }

    private func tick(_ step: Int) {
        switch deck.mode {
        case .pad, .music:
            nudge(.volume, step)
        case .apps:
            guard !remote.apps.isEmpty else { return }
            deck.appIndex = min(remote.apps.count - 1, max(0, deck.appIndex + step))
        case .screen:
            remote.send(.scroll(dx: 0, dy: Double(-step) * 36))
        case .more:
            if deck.moreOpen == .brightness { nudge(.brightness, step); return }
            guard deck.moreOpen == nil else { return }
            deck.moreIndex = (deck.moreIndex + step + MoreItem.allCases.count) % MoreItem.allCases.count
        }
    }

    private func press() {
        switch deck.mode {
        case .pad, .music:
            remote.send(.media(.playPause))
        case .apps:
            guard remote.apps.indices.contains(deck.appIndex) else { return }
            remote.launch(remote.apps[deck.appIndex])
            deck.launches += 1
        case .screen:
            remote.send(.click(button: .left))
        case .more:
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                deck.moreOpen = deck.moreOpen == nil ? MoreItem(rawValue: deck.moreIndex) : nil
            }
        }
    }

    /// Cada marca de la perilla es un 2 %; el valor final se confirma al soltar.
    private func nudge(_ kind: LevelKind, _ step: Int) {
        let current = kind == .volume ? remote.volume : (remote.brightness ?? 0)
        let v = min(1, max(0, current + Double(step) * 0.02))
        remote.editingLevel = true
        remote.setLevel(kind, v, final: false)
        idle?.cancel()
        let work = DispatchWorkItem {
            remote.setLevel(kind, v, final: true)
            remote.editingLevel = false
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

/// Los modos orbitan la perilla. El elegido sube a la cima del anillo.
struct OrbitRing: View {
    @EnvironmentObject private var deck: Deck
    let radius: CGFloat
    @State private var dragStart: Int?

    private var step: Double { 360.0 / Double(DeckMode.allCases.count) }

    var body: some View {
        ZStack {
            Circle().stroke(Tone.stroke, lineWidth: 1).frame(width: radius * 2, height: radius * 2)
            Circle().stroke(Tone.stroke.opacity(0.5), lineWidth: 1).frame(width: radius * 2 + 56, height: radius * 2 + 56)
            ForEach(DeckMode.allCases) { m in
                let angle = (Double(m.rawValue - deck.mode.rawValue) * step - 90) * .pi / 180
                let selected = m == deck.mode
                Button {
                    select(m)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: m.symbol).font(.system(size: selected ? 17 : 14, weight: .semibold))
                        Text(m.label).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected ? Tone.body : Tone.ink.opacity(0.6))
                    .frame(width: 62, height: 50)
                    .background(Capsule().fill(selected ? Tone.ember : Tone.key))
                    .overlay(Capsule().stroke(selected ? .clear : Tone.stroke, lineWidth: 1))
                }
                .buttonStyle(PressScale())
                .offset(x: cos(angle) * (radius + 26), y: sin(angle) * (radius + 26))
                .animation(.spring(duration: 0.55, bounce: 0.25), value: deck.mode)
            }
        }
        // Arrastrar en el anillo lo hace girar de a un modo.
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            let dx = v.translation.width
            guard abs(dx) > 30 else { return }
            let next = (deck.mode.rawValue + (dx < 0 ? 1 : -1) + DeckMode.allCases.count) % DeckMode.allCases.count
            select(DeckMode(rawValue: next)!)
        })
    }

    private func select(_ m: DeckMode) {
        guard m != deck.mode else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        deck.moreOpen = nil
        deck.mode = m
    }
}

/// La perilla de Brasa con el zarcillo de Enredadera en la cara.
struct Knob: View {
    let diameter: CGFloat
    let value: Double
    let caption: String
    let onTick: (Int) -> Void
    let onPress: () -> Void

    @State private var angle: Double = 0        // giro visual acumulado (grados)
    @State private var last: Double?
    @State private var travel: Double = 0
    @State private var pressed = false
    @State private var presses = 0
    private let detent = 18.0                   // 20 marcas por vuelta
    private let selection = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack {
            // Base hundida
            Circle().fill(Tone.key).frame(width: diameter + 26, height: diameter + 26)
            Circle().stroke(Tone.stroke, lineWidth: 1).frame(width: diameter + 26, height: diameter + 26)

            // Cuerpo naranja con estrías que giran con el dedo
            ZStack {
                Circle().fill(Tone.ember)
                ForEach(0..<20, id: \.self) { i in
                    Capsule().fill(Tone.emberDeep)
                        .frame(width: 3, height: i % 5 == 0 ? 14 : 8)
                        .offset(y: -diameter / 2 + 10)
                        .rotationEffect(.degrees(Double(i) * 18))
                }
                Tendril(tightness: value)
                    .stroke(Tone.body, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: diameter * 0.62, height: diameter * 0.62)
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: pressed)
            .animation(.easeOut(duration: 0.25), value: value)

            // Lectura fija (no gira)
            Text(caption)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tone.ember)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Tone.body))
                .offset(y: diameter / 2 - 6)
                .contentTransition(.numericText())
                .animation(.snappy, value: caption)

            Ripple(trigger: presses, cornerRadius: diameter / 2, color: Tone.ember)
                .frame(width: diameter, height: diameter)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    pressed = true
                    let c = CGPoint(x: (diameter + 26) / 2, y: (diameter + 26) / 2)
                    let a = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi
                    if let l = last {
                        var d = a - l
                        if d > 180 { d -= 360 }
                        if d < -180 { d += 360 }
                        travel += abs(d)
                        angle += d
                        // Cada vez que se cruza una marca: un paso y un golpecito.
                        let before = Int(((angle - d) / detent).rounded(.down))
                        let after = Int((angle / detent).rounded(.down))
                        if after != before {
                            selection.selectionChanged()
                            onTick(after > before ? 1 : -1)
                        }
                    } else {
                        selection.prepare()
                    }
                    last = a
                }
                .onEnded { _ in
                    pressed = false
                    if travel < 8 {
                        presses += 1
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onPress()
                    }
                    last = nil
                    travel = 0
                }
        )
        .frame(width: diameter + 26, height: diameter + 26)
    }
}

/// Espiral de zarcillo: más vueltas cuanto mayor el valor.
struct Tendril: Shape {
    var tightness: Double
    var animatableData: Double {
        get { tightness }
        set { tightness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let turns = 0.6 + tightness * 2.4
        let steps = 140
        var p = Path()
        // Tallo que entra desde abajo a la izquierda y se enrosca hacia el centro.
        let startAngle = Double.pi * 0.75
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = startAngle - t * turns * 2 * .pi
            let rr = r * (1 - t * 0.88)
            let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

// MARK: - Apps: brotes en un tallo

struct VineApps: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    private let spacing: CGFloat = 84

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let h = geo.size.height
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            Vine(count: remote.apps.count, spacing: spacing, height: h)
                                .stroke(Tone.ink.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            ForEach(Array(remote.apps.enumerated()), id: \.element.id) { i, app in
                                Bud(app: app, image: remote.icons[app.id], selected: i == deck.appIndex,
                                    launches: i == deck.appIndex ? deck.launches : 0,
                                    windows: remote.windows(of: app.id),
                                    onWindow: { remote.send(.focusWindow(id: $0.id)); Haptic.thump() }) {
                                    deck.appIndex = i
                                    remote.launch(app)
                                    deck.launches += 1
                                }
                                .position(Vine.point(i, spacing: spacing, height: h))
                                .id(i)
                            }
                        }
                        .frame(width: CGFloat(max(remote.apps.count, 1)) * spacing + 60, height: h)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: deck.appIndex) { _, i in
                        withAnimation(.spring(duration: 0.45)) { proxy.scrollTo(i, anchor: .center) }
                    }
                }
            }
            if remote.apps.isEmpty {
                ProgressView().tint(Tone.ember).padding(.bottom, 40)
            }
            RoutineStrip().padding(.bottom, 6)
        }
        .task {
            while !Task.isCancelled {
                remote.send(.listWindows)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// El tallo: una onda suave que pasa por cada brote.
struct Vine: Shape {
    let count: Int
    let spacing: CGFloat
    let height: CGFloat

    static func point(_ i: Int, spacing: CGFloat, height: CGFloat) -> CGPoint {
        let x = 60 + CGFloat(i) * spacing
        let y = height / 2 + sin(CGFloat(i) * 1.1) * height * 0.18
        return CGPoint(x: x, y: y)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard count > 0 else { return p }
        p.move(to: CGPoint(x: 0, y: Vine.point(0, spacing: spacing, height: height).y + 30))
        for i in 0..<count {
            let pt = Vine.point(i, spacing: spacing, height: height)
            let prev = i == 0 ? CGPoint(x: 0, y: pt.y + 30) : Vine.point(i - 1, spacing: spacing, height: height)
            let midX = (prev.x + pt.x) / 2
            p.addCurve(to: pt, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: pt.y))
        }
        // Remate en espiral, como la punta de un zarcillo.
        let end = Vine.point(count - 1, spacing: spacing, height: height)
        p.addQuadCurve(to: CGPoint(x: end.x + 40, y: end.y - 26), control: CGPoint(x: end.x + 36, y: end.y + 8))
        p.addArc(center: CGPoint(x: end.x + 30, y: end.y - 26), radius: 10, startAngle: .degrees(0), endAngle: .degrees(300), clockwise: true)
        return p
    }
}

/// Un brote: icono en una yema oscura. El elegido crece y florece.
struct Bud: View {
    let app: AppTile
    let image: UIImage?
    let selected: Bool
    let launches: Int
    let windows: [WindowInfo]
    let onWindow: (WindowInfo) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptic.thump()
            action()
        }) {
            ZStack {
                // Pétalos que se abren al elegir el brote.
                ForEach(0..<8, id: \.self) { k in
                    Ellipse()
                        .fill(Tone.ember.opacity(0.9))
                        .frame(width: 16, height: 30)
                        .offset(y: selected ? -40 : -12)
                        .rotationEffect(.degrees(Double(k) * 45))
                        .opacity(selected ? 1 : 0)
                }
                Circle().fill(Tone.body).frame(width: 64, height: 64)
                Circle().stroke(selected ? Tone.ember : Tone.stroke, lineWidth: 2).frame(width: 64, height: 64)
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).frame(width: 44, height: 44)
                }
                if app.running {
                    // Hoja: la app está abierta.
                    Ellipse().fill(Tone.leaf).frame(width: 14, height: 7)
                        .rotationEffect(.degrees(-35))
                        .offset(x: 30, y: -26)
                }
                Ripple(trigger: launches, cornerRadius: 40, color: Tone.ember)
                    .frame(width: 70, height: 70)
            }
            .scaleEffect(selected ? 1.18 : 0.9)
            .boing(launches)
            .animation(.spring(duration: 0.45, bounce: 0.4), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .contextMenu {
            Section(app.name) {
                if windows.isEmpty { Text(app.running ? "sin ventanas abiertas" : "no está abierta") }
                ForEach(windows) { w in
                    Button { onWindow(w) } label: {
                        Label(w.title, systemImage: w.minimized ? "arrow.up.right.square" : "macwindow")
                    }
                }
            }
        }
    }
}

// MARK: - Pad

struct PadStage: View {
    @EnvironmentObject private var remote: Remote
    @State private var typing = false
    @State private var bumps = [0, 0, 0, 0, 0]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.body.opacity(0.6))
                Circle().fill(Tone.ember).frame(width: 6, height: 6).opacity(0.7)
                Trackpad(remote: remote)
            }
            .padding([.horizontal, .top], 10)

            HStack(spacing: 8) {
                key("keyboard", "teclado", 0) { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { typing = true } }
                key("arrow.up.doc.on.clipboard", "al Mac", 1) { remote.pushClipboard() }
                key("arrow.down.doc.on.clipboard", "del Mac", 2) { remote.send(.pullClipboard) }
                key("cursorarrow.click", "clic", 3) { remote.send(.click(button: .left)) }
                key("cursorarrow.click.2", "derecho", 4) { remote.send(.click(button: .right)) }
            }
            .padding(.horizontal, 10)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(remote.shortcuts) { s in
                        Button {
                            Haptic.tap()
                            remote.send(.shortcut(s))
                        } label: {
                            Text(s.glyphs)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Tone.ink.opacity(0.85))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(Tone.key))
                                .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
                        }
                        .buttonStyle(PressScale())
                        .accessibilityLabel(s.title)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) {
            if typing {
                KeyboardBar(shown: $typing).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Tecla grabada en la cerámica.
    private func key(_ symbol: String, _ title: String, _ i: Int, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            bumps[i] += 1
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: bumps[i])
                Text(title).font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Tone.ink.opacity(0.8))
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tone.key))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Música

struct MusicStage: View {
    @EnvironmentObject private var remote: Remote
    @State private var scrub: Double?
    @State private var taps = [0, 0]

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                // Disco que gira mientras suena.
                Circle().fill(Tone.body)
                Circle().stroke(Tone.stroke, lineWidth: 1)
                ForEach(1..<4, id: \.self) { k in
                    Circle().stroke(Tone.ink.opacity(0.06), lineWidth: 1).padding(CGFloat(k) * 14)
                }
                Group {
                    if let art = remote.artwork {
                        Image(uiImage: art).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(Tone.ember)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Tone.key)
                    }
                }
                .clipShape(Circle())
                .padding(38)
                Circle().fill(Tone.recess).frame(width: 14, height: 14)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 230)
            .modifier(Spin(on: remote.nowPlaying?.playing == true))

            if let np = remote.nowPlaying {
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    let pos = scrub ?? remote.position(at: tl.date)
                    VStack(spacing: 4) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Tone.key)
                                Capsule().fill(Tone.ember)
                                    .frame(width: max(6, g.size.width * (np.duration > 0 ? pos / np.duration : 0)))
                            }
                            .frame(height: 6).frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in scrub = max(0, min(1, v.location.x / g.size.width)) * np.duration }
                                .onEnded { _ in
                                    if let s = scrub { remote.send(.seek(seconds: s)) }
                                    Haptic.tap()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { scrub = nil }
                                })
                        }
                        .frame(height: 20)
                        HStack {
                            Text(clock(pos))
                            Spacer()
                            Text("-" + clock(max(0, np.duration - pos)))
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Tone.ink.opacity(0.5))
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack(spacing: 40) {
                skip("backward.fill", .previous, 0)
                skip("forward.fill", .next, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func skip(_ symbol: String, _ key: MediaKey, _ i: Int) -> some View {
        Button {
            Haptic.tap()
            taps[i] += 1
            remote.send(.media(key))
        } label: {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tone.ink.opacity(0.85))
                .symbolEffect(.bounce, value: taps[i])
                .frame(width: 58, height: 44)
                .background(Capsule().fill(Tone.key))
                .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Giro lento y continuo, como un disco.
private struct Spin: ViewModifier {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !on || reduce)) { tl in
            content.rotationEffect(.degrees(on && !reduce
                ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) * 30 : 0))
        }
    }
}

// MARK: - Más: un tallo vertical

struct MoreStage: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck

    var body: some View {
        Group {
            if let open = deck.moreOpen {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            withAnimation(.spring(duration: 0.4)) { deck.moreOpen = nil }
                        } label: {
                            Label("más", systemImage: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Tone.ink.opacity(0.8))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(Tone.key))
                        }
                        Spacer()
                    }
                    .padding(10)
                    page(open).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                stem.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var stem: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MoreItem.allCases) { item in
                    let selected = item.rawValue == deck.moreIndex
                    Button {
                        Haptic.tap()
                        deck.moreIndex = item.rawValue
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.moreOpen = item }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                // El tallo pasa por detrás de cada nudo.
                                Rectangle().fill(Tone.ink.opacity(0.2)).frame(width: 3)
                                Circle().fill(selected ? Tone.ember : Tone.key).frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Tone.stroke, lineWidth: selected ? 0 : 1))
                                Image(systemName: item.symbol).font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selected ? Tone.body : Tone.ink.opacity(0.75))
                            }
                            .frame(width: 40, height: 62)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selected ? Tone.ember : Tone.ink)
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.3), value: selected)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func page(_ item: MoreItem) -> some View {
        switch item {
        case .brightness:
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill").font(.system(size: 40)).foregroundStyle(Tone.ember)
                    .symbolEffect(.pulse)
                Text(remote.brightness == nil ? "este Mac no deja cambiar el brillo"
                                              : "gira la perilla para cambiar el brillo")
                    .font(.callout).foregroundStyle(Tone.ink.opacity(0.6))
            }
        case .gestures: GesturePage()
        case .laser: LaserPage()
        case .power: PowerPage()
        case .routines: NavigationStack { RoutineList().background(Tone.recess) }
        case .shortcuts: NavigationStack { ShortcutEditorPage().background(Tone.recess) }
        }
    }
}
