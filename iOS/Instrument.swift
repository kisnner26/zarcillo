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

/// Medidas compartidas. Todo lo que se toca mide al menos `tap`.
enum Space {
    static let xs: CGFloat = 6
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let tap: CGFloat = 48
    static let stageRadius: CGFloat = 36
}

enum DeckMode: Int, CaseIterable, Identifiable {
    case pad, deck, apps, music, screen, more
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .pad: "pad"
        case .deck: "botones"
        case .apps: "apps"
        case .music: "música"
        case .screen: "pantalla"
        case .more: "más"
        }
    }

    var glyph: Glyph {
        switch self {
        case .pad: .pad
        case .deck: .deck
        case .apps: .apps
        case .music: .music
        case .screen: .screen
        case .more: .more
        }
    }

    var symbol: String {
        switch self {
        case .pad: "hand.point.up.left"
        case .deck: "square.grid.3x3.fill"
        case .apps: "leaf"
        case .music: "music.note"
        case .screen: "display"
        case .more: "ellipsis"
        }
    }
}

enum MoreItem: Int, CaseIterable, Identifiable {
    case classes, privacy, game, orientation, photos, send, scan, shots, garden, herbarium, layers, brain, detach, mixer, gaze, guardian, near, guest, compass, callLight, posture, lights, brightness, color, touchBar, gestures, laser, power, routines, shortcuts, permissions
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .classes: "clases"
        case .brain: "cerebro"
        case .privacy: "privacidad"
        case .game: "mando"
        case .orientation: "giro"
        case .shots: "capturas"
        case .garden: "jardín"
        case .herbarium: "herbario"
        case .layers: "capas"
        case .permissions: "permisos"
        case .detach: "desprender"
        case .mixer: "mezclador"
        case .gaze: "mirada"
        case .guardian: "guardián"
        case .near: "cercanía"
        case .guest: "invitado"
        case .compass: "brújula"
        case .callLight: "luz de llamada"
        case .posture: "postura"
        case .photos: "fotos"
        case .send: "enviar"
        case .scan: "escanear"
        case .lights: "luces"
        case .brightness: "brillo"
        case .color: "color"
        case .touchBar: "touch bar"
        case .gestures: "gestos"
        case .laser: "láser"
        case .power: "energía"
        case .routines: "escenas"
        case .shortcuts: "atajos"
        }
    }

    var detail: String {
        switch self {
        case .classes: "transcribe y traduce en vivo"
        case .brain: "Claude y lo que va aprendiendo"
        case .privacy: "filtro antiespía en la pantalla"
        case .game: "mando o volante para juegos"
        case .orientation: "horizontal fija, sin depender del bloqueo"
        case .shots: "las del Mac, reveladas al llegar"
        case .garden: "lo que aprendió, hecho planta"
        case .herbarium: "fotografía una planta y guarda su ficha"
        case .layers: "las ventanas del Mac en 3D"
        case .permissions: "lo que el Mac te deja usar"
        case .detach: "una ventana del Mac en tu mano"
        case .mixer: "volumen por app"
        case .gaze: "el cursor sigue tus ojos"
        case .guardian: "si alguien toca tu Mac, suena"
        case .near: "se bloquea cuando te alejas"
        case .guest: "un amigo lanza fotos con un QR"
        case .compass: "apunta a una ventana del Mac"
        case .callLight: "tu iPhone te ilumina en videollamadas"
        case .posture: "la cámara del Mac te avisa si te encorvas"
        case .photos: "tíralas al Mac como hojas"
        case .send: "archivos, links y texto al Mac"
        case .scan: "texto al cursor, pizarra a PDF"
        case .lights: "siguen los colores de la pantalla"
        case .brightness: "gira la perilla"
        case .color: "el acento de la app"
        case .touchBar: "elige qué muestra en el Mac"
        case .gestures: "escritorios y Spotlight"
        case .laser: "apunta con el iPhone"
        case .power: "bloquear, suspender, despertar"
        case .routines: "varias acciones de un toque"
        case .shortcuts: "teclas del pad"
        }
    }

    var symbol: String {
        switch self {
        case .classes: "waveform"
        case .brain: "brain.head.profile"
        case .privacy: "eye.slash"
        case .game: "gamecontroller.fill"
        case .orientation: "rectangle.landscape.rotate"
        case .shots: "camera.viewfinder"
        case .garden: "camera.macro"
        case .herbarium: "leaf.circle"
        case .layers: "square.3.layers.3d"
        case .permissions: "checkmark.shield"
        case .detach: "macwindow.badge.plus"
        case .mixer: "slider.vertical.3"
        case .gaze: "eye"
        case .guardian: "lock.shield"
        case .near: "wave.3.right"
        case .guest: "qrcode"
        case .compass: "location.north.line"
        case .callLight: "light.max"
        case .posture: "figure.stand"
        case .photos: "photo.on.rectangle.angled"
        case .send: "tray.and.arrow.up"
        case .scan: "doc.viewfinder"
        case .lights: "lightbulb.2"
        case .brightness: "sun.max"
        case .color: "paintpalette"
        case .touchBar: "rectangle.split.3x1"
        case .gestures: "hand.draw"
        case .laser: "light.beacon.max"
        case .power: "power"
        case .routines: "sparkles"
        case .shortcuts: "command"
        }
    }
}

/// Las funciones de "más", agrupadas por lo que hacen.
enum MoreGroup: Int, CaseIterable, Identifiable {
    case mac, send, ambience, security, custom
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mac: "controlar el Mac"
        case .send: "enviar y capturar"
        case .ambience: "ambiente"
        case .security: "seguridad"
        case .custom: "personalizar"
        }
    }

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .send: "arrow.up.forward.app"
        case .ambience: "sparkles"
        case .security: "lock.shield"
        case .custom: "slider.horizontal.3"
        }
    }

    /// Cada rama con su propio verde, ámbar o azul: se distinguen de un vistazo.
    var hue: Color {
        switch self {
        case .mac: Color(red: 0.96, green: 0.62, blue: 0.45)
        case .send: Color(red: 0.55, green: 0.82, blue: 0.58)
        case .ambience: Color(red: 0.98, green: 0.80, blue: 0.42)
        case .security: Color(red: 0.52, green: 0.72, blue: 0.98)
        case .custom: Color(red: 0.80, green: 0.64, blue: 0.96)
        }
    }

    var items: [MoreItem] {
        switch self {
        case .mac: [.game, .detach, .mixer, .gaze, .laser, .gestures, .power, .brightness]
        case .send: [.photos, .send, .scan, .shots, .classes]
        case .ambience: [.lights, .callLight, .posture]
        case .security: [.privacy, .guardian, .near, .guest]
        case .custom: [.orientation, .garden, .herbarium, .brain, .routines, .shortcuts, .touchBar, .color, .permissions]
        }
    }
}

extension MoreItem {
    /// La rama de "Más" a la que pertenece (para su color).
    var group: MoreGroup { MoreGroup.allCases.first { $0.items.contains(self) } ?? .custom }
}

extension MoreItem {
    /// Las opciones que tienen sentido para este Mac (sin Touch Bar, no se
    /// ofrece), en el orden de sus grupos: así la perilla las recorre igual
    /// que se ven.
    static func visible(touchBar: Bool) -> [MoreItem] {
        MoreGroup.allCases.flatMap(\.items).filter { $0 != .touchBar || touchBar }
    }

    static func groups(touchBar: Bool) -> [(group: MoreGroup, items: [MoreItem])] {
        MoreGroup.allCases.map { g in (g, g.items.filter { $0 != .touchBar || touchBar }) }.filter { !$0.items.isEmpty }
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
    @StateObject private var voice = VoiceCommander()
    @State private var callLight = false
    @AppStorage("light.auto") private var autoLight = true
    /// Alto del teclado sobre la pantalla: el escenario sube lo que el teclado invade.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        Group {
            if landscape && deck.mode == .screen {
                // El Mac a pantalla completa: sin perilla ni anillo. Al volver a
                // vertical, el instrumento reaparece.
                LandscapeScreen { withAnimation(.spring(duration: 0.4)) { deck.mode = .pad } }
                    .transition(.opacity)
            } else if landscape {
                HStack(spacing: Space.m) {
                    Stage().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, keyboard)
                    ControlDeck(ring: 100, knob: 100)
                        .frame(width: 330)
                }
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            } else {
                VStack(spacing: 0) {
                    Stage()
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.s)
                        // El teclado cubre la perilla (360 pt); solo lo que pase de ahí sube el escenario.
                        .padding(.bottom, max(0, keyboard - 360))
                        .frame(maxHeight: .infinity)
                    ControlDeck(ring: 124, knob: 128)
                        .frame(height: 360)
                }
            }
        }
        // El teclado tapa la perilla en vez de aplastar el escenario (si no,
        // los campos de arriba se montan sobre el botón de volver).
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds.height
            let h = max(0, screen - end.minY)
            withAnimation(.spring(duration: 0.3)) { keyboard = h }
        }
        // Los avisos del Mac: una notificación breve arriba, solo cuando hay algo que decir.
        .overlay(alignment: .top) { Toast() }
        .overlay { HarvestFall() }
        .overlay(alignment: .top) { VoiceOverlay(voice: voice).padding(.top, Space.s) }
        .overlay(alignment: .top) { BrainOverlay().padding(.top, Space.s) }
        .overlay { AuraEdge() }
        .fullScreenCover(isPresented: $callLight) { CallLight(shown: $callLight) }
        .overlay {
            if let a = remote.alarm {
                AlarmView(alarm: a).transition(.opacity)
            }
        }
        .onChange(of: remote.cameraInUse) { _, busy in
            if autoLight { callLight = busy }
        }
        .onAppear { voice.attach(remote) }
        .environmentObject(voice)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: landscape && deck.mode == .screen)
        // La pantalla en vivo se pide desde aquí, según el modo y la orientación:
        // en horizontal, con el doble de resolución.
        .onChange(of: screenWidth, initial: true) { _, w in
            remote.send(.screen(on: w > 0, width: w))
        }
        .environmentObject(deck)
    }

    private var screenWidth: Int {
        guard deck.mode == .screen else { return 0 }
        return landscape ? 1800 : 960
    }
}

/// Aviso breve del Mac ("abriendo Safari", "foto recibida"…).
struct Toast: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        if let text = remote.pill {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.ember)
                Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial).environment(\.colorScheme, .dark))
            .overlay(Capsule().stroke(Tone.ember.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.4, bounce: 0.3), value: remote.pill)
        }
    }
}

/// La pantalla del Mac a lo ancho del iPhone girado, con zoom y un botón
/// discreto para volver al instrumento.
struct LandscapeScreen: View {
    let exit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            LiveScreen(zoomable: true).ignoresSafeArea()
            Button {
                Haptic.tap()
                exit()
            } label: {
                GlyphView(.close, size: 16)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("salir de la pantalla del Mac")
            .padding(Space.s)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Escenario

/// El hueco de la cerámica: más oscuro, con un borde que lo hunde.
struct Stage: View {
    @EnvironmentObject private var deck: Deck

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Space.stageRadius, style: .continuous)
        ZStack {
            // Vidrio esmerilado: deja ver el invernadero de fondo, borroso.
            shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.05), Tone.body.opacity(0.55), Tone.body.opacity(0.75)],
                                      startPoint: .top, endPoint: .bottom))
            Group {
                switch deck.mode {
                case .pad: PadStage()
                case .deck: DeckStage()
                case .apps: VineApps()
                case .music: MusicStage()
                case .screen: ScreenPage()
                case .more: MoreStage()
                }
            }
            .id(deck.mode)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)).combined(with: .offset(y: 8)),
                                    removal: .opacity))
            // Filo de luz: brillante arriba, casi nada abajo. Se lee como un panel de vidrio.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.07), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .animation(.spring(duration: 0.45, bounce: 0.18), value: deck.mode)
    }
}

// MARK: - Consola: anillo + perilla

struct ControlDeck: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    @EnvironmentObject private var voice: VoiceCommander
    /// Radio del anillo de modos y diámetro de la perilla.
    let ring: CGFloat
    let knob: CGFloat
    @State private var idle: DispatchWorkItem?

    var body: some View {
        ZStack {
            OrbitRing(radius: ring)
            Knob(diameter: knob, value: knobValue, caption: caption,
                 onTick: tick, onPress: press,
                 onHold: { holding in holding ? voice.begin() : voice.end() })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var knobValue: Double {
        if deck.mode == .more, deck.moreOpen == .brightness { return remote.brightness ?? 0 }
        return remote.volume
    }

    /// En pad y botones, la perilla hace lo que tenga sentido en la app del frente.
    private var contextKnob: AppContext.Knob {
        guard deck.mode == .pad || deck.mode == .deck else { return .volume }
        return remote.context?.knob ?? .volume
    }

    private var caption: String {
        if contextKnob != .volume { return contextKnob.caption }
        switch deck.mode {
        case .pad, .deck, .music: return "\(Int((remote.volume * 100).rounded()))"
        case .apps: return "abrir"
        case .screen: return "clic"
        case .more:
            if deck.moreOpen == .brightness { return "\(Int(((remote.brightness ?? 0) * 100).rounded()))" }
            return deck.moreOpen == nil ? "entrar" : "volver"
        }
    }

    /// Un paso de la perilla. Devuelve `false` si chocó con un tope.
    private func tick(_ step: Int) -> Bool {
        switch contextKnob {
        case .frames, .slides:
            remote.send(.key(name: step > 0 ? "right" : "left"))
            return true
        case .zoom:
            remote.send(.shortcut(Shortcut(title: "", key: step > 0 ? "=" : "-", command: true)))
            return true
        case .scroll:
            remote.scroll(dx: 0, dy: Double(-step) * 40)
            return true
        case .volume:
            break
        }
        switch deck.mode {
        case .pad, .deck, .music:
            return nudge(.volume, step)
        case .apps:
            guard !remote.apps.isEmpty else { return false }
            let next = deck.appIndex + step
            guard remote.apps.indices.contains(next) else { return false }
            withAnimation(.snappy(duration: 0.3)) { deck.appIndex = next }
            return true
        case .screen:
            remote.scroll(dx: 0, dy: Double(-step) * 36)
            return true
        case .more:
            if deck.moreOpen == .brightness { return nudge(.brightness, step) }
            guard deck.moreOpen == nil else { return false }
            let n = MoreItem.visible(touchBar: remote.hasTouchBar).count
            deck.moreIndex = (deck.moreIndex + step + n) % n
            return true
        }
    }

    private func press() {
        // Con una clase en marcha, la perilla marca el momento.
        if remote.transcribing {
            remote.markFromKnob()
            return
        }
        switch contextKnob {
        case .frames:
            remote.send(.key(name: "space"))
            return
        case .zoom:
            remote.send(.shortcut(Shortcut(title: "", key: "0", command: true)))
            return
        case .slides:
            remote.send(.key(name: "right"))
            return
        case .scroll, .volume:
            break
        }
        switch deck.mode {
        case .pad, .deck, .music:
            remote.send(.media(.playPause))
        case .apps:
            guard remote.apps.indices.contains(deck.appIndex) else { return }
            remote.launch(remote.apps[deck.appIndex])
            deck.launches += 1
        case .screen:
            remote.send(.click(button: .left))
        case .more:
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                let items = MoreItem.visible(touchBar: remote.hasTouchBar)
                deck.moreOpen = deck.moreOpen == nil && items.indices.contains(deck.moreIndex) ? items[deck.moreIndex] : nil
            }
        }
    }

    /// Cada marca es un 2 %; el valor final se confirma cuando la perilla se queda quieta.
    private func nudge(_ kind: LevelKind, _ step: Int) -> Bool {
        let current = kind == .volume ? remote.volume : (remote.brightness ?? 0)
        let v = min(1, max(0, current + Double(step) * 0.02))
        guard abs(v - current) > 0.0001 else { return false }
        remote.editingLevel = true
        remote.setLevel(kind, v, final: false)
        idle?.cancel()
        let work = DispatchWorkItem {
            remote.setLevel(kind, v, final: true)
            remote.editingLevel = false
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        return true
    }
}

/// Los modos orbitan la perilla. Solo el elegido muestra su nombre; los demás
/// son botones redondos de icono, así el anillo respira.
struct OrbitRing: View {
    @EnvironmentObject private var deck: Deck
    let radius: CGFloat

    private var step: Double { 360.0 / Double(DeckMode.allCases.count) }

    var body: some View {
        ZStack {
            Circle().stroke(Panel.stroke.opacity(0.9), lineWidth: 1)
                .frame(width: radius * 2 + 48, height: radius * 2 + 48)
            ForEach(DeckMode.allCases) { m in
                let angle = (Double(m.rawValue - deck.mode.rawValue) * step - 90) * .pi / 180
                let selected = m == deck.mode
                Button { select(m) } label: {
                    HStack(spacing: 6) {
                        GlyphView(m.glyph, size: 19)
                        if selected {
                            Text(m.label).font(.system(size: 14, weight: .bold, design: .rounded))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(selected ? Panel.onEmber : Panel.ink.opacity(0.7))
                    .padding(.horizontal, selected ? 16 : 0)
                    .frame(minWidth: Space.tap, minHeight: Space.tap)
                    .background(Capsule().fill(selected ? Panel.ember : Panel.key))
                    .overlay(Capsule().stroke(selected ? .clear : Panel.stroke, lineWidth: 1))
                    .shadow(color: selected ? Panel.ember.opacity(0.45) : .clear, radius: 12)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(m.label)
                .offset(x: cos(angle) * (radius + 24), y: sin(angle) * (radius + 24))
                .animation(.spring(duration: 0.55, bounce: 0.25), value: deck.mode)
            }
        }
        // Deslizar sobre el anillo lo gira de a un modo.
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            let dx = v.translation.width
            guard abs(dx) > 36 else { return }
            let n = DeckMode.allCases.count
            select(DeckMode(rawValue: (deck.mode.rawValue + (dx < 0 ? 1 : -1) + n) % n)!)
        })
    }

    private func select(_ m: DeckMode) {
        guard m != deck.mode else { return }
        Detents.shared.detent(speed: 0.2)
        deck.moreOpen = nil
        deck.mode = m
    }
}

/// La perilla de Brasa con el zarcillo de Enredadera en la cara.
///
/// Gira con el dedo marca a marca (20 por vuelta), y si la lanzas sigue girando
/// y frena sola. La luz no gira con ella: está pintada con un shader encima.
struct Knob: View {
    let diameter: CGFloat
    let value: Double
    let caption: String
    let onTick: (Int) -> Bool
    let onPress: () -> Void
    /// Mantener la perilla quieta medio segundo: hablarle.
    var onHold: ((Bool) -> Void)? = nil
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    @State private var angle: Double = 0          // giro visual acumulado, en grados
    @State private var last: (angle: Double, time: TimeInterval)?
    @State private var velocity: Double = 0       // grados por segundo
    @State private var travel: Double = 0
    @State private var pressed = false
    @State private var presses = 0
    @State private var spin: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let detent = 18.0

    private var base: CGFloat { diameter + 28 }

    var body: some View {
        ZStack {
            // Asiento hundido en la cerámica.
            Circle().fill(Panel.recess).frame(width: base, height: base)
            Circle().strokeBorder(
                LinearGradient(colors: [.black.opacity(0.6), Panel.ink.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5)
                .frame(width: base, height: base)

            // Cuerpo: estrías y zarcillo giran; la luz se queda quieta.
            ZStack {
                Circle().fill(Panel.ember)
                ForEach(0..<40, id: \.self) { i in
                    Capsule().fill(Panel.emberDeep)
                        .frame(width: i % 2 == 0 ? 3 : 2, height: i % 10 == 0 ? 16 : (i % 2 == 0 ? 10 : 6))
                        .offset(y: -diameter / 2 + 10)
                        .rotationEffect(.degrees(Double(i) * 9))
                }
                Tendril(tightness: value)
                    .stroke(Panel.body, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            // La luz va después del giro: la perilla rota "debajo" de ella,
            // como un objeto real bajo una lámpara.
            .overlay {
                ZStack {
                    RadialGradient(colors: [.white.opacity(0.42), .clear],
                                   center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: diameter * 0.45)
                        .blendMode(.softLight)
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2)
                    Circle().fill(Panel.ember.opacity(pressed ? 0.18 : 0)).blendMode(.plusLighter)
                    Grain(opacity: 0.12).clipShape(Circle())
                }
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
            .shadow(color: Panel.ember.opacity(pressed ? 0.55 : 0.3), radius: pressed ? 26 : 16)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.45), value: pressed)
            .animation(.easeOut(duration: 0.25), value: value)

            Ripple(trigger: presses, cornerRadius: diameter / 2, color: Panel.ember)
                .frame(width: diameter, height: diameter)

            // Lectura: una placa fija en el borde inferior del asiento.
            Text(caption)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Panel.ember)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Panel.body))
                .overlay(Capsule().stroke(Panel.stroke, lineWidth: 1))
                .offset(y: base / 2 - 2)
                .contentTransition(.numericText())
                .animation(.snappy, value: caption)
        }
        .frame(width: base, height: base)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if !pressed {
                        spin?.cancel()
                        pressed = true
                        holdTask?.cancel()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(550))
                            guard !Task.isCancelled, pressed, travel < 8 else { return }
                            holding = true
                            Detents.shared.wall()
                            onHold?(true)
                        }
                    }
                    let c = CGPoint(x: base / 2, y: base / 2)
                    let a = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi
                    let now = v.time.timeIntervalSinceReferenceDate
                    if let l = last {
                        var d = a - l.angle
                        if d > 180 { d -= 360 }
                        if d < -180 { d += 360 }
                        travel += abs(d)
                        let dt = max(now - l.time, 1.0 / 240)
                        velocity = velocity * 0.6 + (d / dt) * 0.4
                        _ = advance(by: d)
                    }
                    last = (a, now)
                }
                .onEnded { _ in
                    pressed = false
                    last = nil
                    holdTask?.cancel()
                    if holding {
                        holding = false
                        onHold?(false)
                    } else if travel < 8 {
                        presses += 1
                        Detents.shared.press()
                        onPress()
                    } else if abs(velocity) > 260, !reduce {
                        coast()
                    }
                    travel = 0
                }
        )
        .accessibilityElement()
        .accessibilityLabel("perilla")
        .accessibilityValue(caption)
        .accessibilityAdjustableAction { dir in
            _ = onTick(dir == .increment ? 1 : -1)
        }
        .accessibilityAction { onPress() }
    }

    /// Gira `d` grados y dispara un paso por cada marca cruzada. Si un paso
    /// choca con un tope, la perilla no sigue: se siente la pared.
    private func advance(by d: Double) -> Bool {
        let before = Int((angle / detent).rounded(.down))
        let after = Int(((angle + d) / detent).rounded(.down))
        guard after != before else { angle += d; return true }
        let dir = after > before ? 1 : -1
        for _ in 0..<abs(after - before) {
            if !onTick(dir) {
                Detents.shared.wall()
                velocity = 0
                return false
            }
            Detents.shared.detent(speed: abs(velocity) / 900)
        }
        angle += d
        return true
    }

    /// Inercia: la perilla sigue girando y frena sola, marcando cada paso.
    private func coast() {
        spin?.cancel()
        spin = Task { @MainActor in
            while !Task.isCancelled, abs(velocity) > 50 {
                try? await Task.sleep(for: .milliseconds(16))
                velocity *= 0.93
                if !advance(by: velocity / 60) { break }
            }
            velocity = 0
        }
    }
}

// MARK: - Apps: brotes en un tallo

struct VineApps: View {
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck
    /// Ancho de cada brote en el tallo.
    private let cell: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let h = geo.size.height
                ScrollView(.horizontal) {
                    // Una fila real de celdas iguales: el desplazamiento sabe dónde
                    // está cada brote y puede centrarlo exacto.
                    LazyHStack(spacing: 0) {
                        ForEach(Array(remote.apps.enumerated()), id: \.offset) { i, app in
                            Bud(app: app, image: remote.icons[app.id], selected: i == deck.appIndex,
                                launches: i == deck.appIndex ? deck.launches : 0,
                                windows: remote.windows(of: app.id),
                                onWindow: { remote.send(.focusWindow(id: $0.id)); Haptic.thump() }) {
                                withAnimation(.snappy) { deck.appIndex = i }
                                remote.launch(app)
                                deck.launches += 1
                            }
                            .frame(width: cell, height: h)
                            .offset(y: Vine.lift(i, height: h))
                            .id(i)
                        }
                    }
                    .scrollTargetLayout()
                    .background(alignment: .leading) {
                        Vine(count: remote.apps.count, cell: cell, height: h)
                            .stroke(Tone.ink.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: CGFloat(remote.apps.count) * cell, height: h)
                    }
                }
                // Márgenes de medio escenario: el primer y el último brote también
                // pueden quedar al centro.
                .contentMargins(.horizontal, max(0, (geo.size.width - cell) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: selection, anchor: .center)
                .scrollIndicators(.hidden)
            }
            if remote.apps.isEmpty {
                WaitingDots().padding(.bottom, 40)
            }
            RoutineStrip().padding(.bottom, Space.s)
        }
        .task {
            while !Task.isCancelled {
                remote.send(.listWindows)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Desplazar el tallo elige el brote que queda al centro, y la perilla
    /// mueve el tallo: son la misma selección.
    private var selection: Binding<Int?> {
        Binding(
            get: { remote.apps.isEmpty ? nil : deck.appIndex },
            set: { new in
                guard let new, new != deck.appIndex else { return }
                deck.appIndex = new
                Detents.shared.detent(speed: 0.3)
            }
        )
    }
}

/// El tallo: una onda suave que pasa por el centro de cada brote.
struct Vine: Shape {
    let count: Int
    let cell: CGFloat
    let height: CGFloat

    /// Cuánto sube o baja el brote `i` respecto de la línea media.
    static func lift(_ i: Int, height: CGFloat) -> CGFloat {
        sin(CGFloat(i) * 1.1) * height * 0.16
    }

    private func point(_ i: Int) -> CGPoint {
        CGPoint(x: cell / 2 + CGFloat(i) * cell, y: height / 2 + Vine.lift(i, height: height))
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard count > 0 else { return p }
        let first = point(0)
        p.move(to: CGPoint(x: first.x - cell, y: first.y + 34))
        var prev = p.currentPoint ?? first
        for i in 0..<count {
            let pt = point(i)
            let midX = (prev.x + pt.x) / 2
            p.addCurve(to: pt, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: pt.y))
            prev = pt
        }
        // Remate en espiral, como la punta de un zarcillo.
        let end = point(count - 1)
        p.addQuadCurve(to: CGPoint(x: end.x + 44, y: end.y - 28), control: CGPoint(x: end.x + 40, y: end.y + 8))
        p.addArc(center: CGPoint(x: end.x + 33, y: end.y - 28), radius: 11,
                 startAngle: .degrees(0), endAngle: .degrees(300), clockwise: true)
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
    @State private var shortcuts = false
    @State private var bumps = [0, 0, 0, 0]

    var body: some View {
        VStack(spacing: Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tone.body.opacity(0.55))
                Circle().fill(Tone.ember).frame(width: 6, height: 6).opacity(0.6)
                Trackpad(remote: remote)
            }

            if typing {
                KeyboardBar(shown: $typing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
            // Cuatro teclas grabadas, con aire entre ellas.
            HStack(spacing: Space.s + 2) {
                key("keyboard", "teclado", 0) { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { typing = true } }
                key("command", "atajos", 1) { shortcuts = true }
                Menu {
                    Button { remote.pushClipboard() } label: { Label("Enviar al Mac", systemImage: "arrow.up.doc.on.clipboard") }
                    Button { remote.send(.pullClipboard) } label: { Label("Traer del Mac", systemImage: "arrow.down.doc.on.clipboard") }
                } label: {
                    keyFace("doc.on.clipboard", "portapapeles", 2)
                }
                .simultaneousGesture(TapGesture().onEnded { Haptic.tap(); bumps[2] += 1 })
                key("cursorarrow.click.2", "clic der.", 3) { remote.send(.click(button: .right)) }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(Space.m)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: typing)
        .sheet(isPresented: $shortcuts) {
            ShortcutSheet().environmentObject(remote)
        }
    }

    private func key(_ symbol: String, _ title: String, _ i: Int, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            bumps[i] += 1
            action()
        } label: { keyFace(symbol, title, i) }
        .buttonStyle(PressScale())
    }

    /// Tecla grabada en la cerámica.
    private func keyFace(_ symbol: String, _ title: String, _ i: Int) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .symbolEffect(.bounce, value: bumps[i])
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Tone.ink.opacity(0.85))
        .frame(maxWidth: .infinity).frame(height: 62)
        .glass(18)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Tone.ink.opacity(0.14), .black.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Los atajos, en grande y con aire: una hoja que sube desde abajo.
struct ShortcutSheet: View {
    @EnvironmentObject private var remote: Remote
    @State private var editing = false
    @State private var taps: [UUID: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s + 2)], spacing: Space.s + 2) {
                    ForEach(remote.shortcuts) { s in
                        Button {
                            Detents.shared.press()
                            taps[s.id, default: 0] += 1
                            remote.send(.shortcut(s))
                        } label: {
                            VStack(spacing: 6) {
                                Text(s.glyphs).font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Tone.ember)
                                Text(s.title).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Tone.ink.opacity(0.7)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).frame(height: 88)
                            .glass(20)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                            .boing(taps[s.id, default: 0], amount: 0.08)
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(Space.m)
            }
            .navigationTitle("Atajos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Editar") { ShortcutEditorPage(hidesBar: false) }
                }
            }
            .background(Tone.body)
        }
        .tint(Tone.ember)
        .presentationDetents([.medium, .large])
        .presentationBackground(Tone.body)
        .presentationCornerRadius(32)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Más: un tallo vertical

struct MoreStage: View {
    /// El icono de la ficha vuela a la cabecera al abrir la función (y vuelve al cerrar).
    @Namespace private var hero
    @EnvironmentObject private var remote: Remote
    @EnvironmentObject private var deck: Deck

    var body: some View {
        Group {
            if let open = deck.moreOpen {
                // Cabecera fija: volver, el nombre en serif y qué hace. El contenido va debajo,
                // nunca tapado por un botón flotante.
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        backButton
                        VStack(alignment: .leading, spacing: 1) {
                            Text(open.title.prefix(1).uppercased() + open.title.dropFirst())
                                .font(Typo.title(20)).foregroundStyle(Tone.ink)
                            Text(open.detail).font(Typo.label(12)).foregroundStyle(Tone.ink.opacity(0.5)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: open.symbol).font(.system(size: 17)).foregroundStyle(open.group.hue.opacity(0.9))
                            .matchedGeometryEffect(id: open, in: hero)
                            .frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.s)
                    Rectangle().fill(LinearGradient(colors: [.clear, Tone.stroke, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1).padding(.horizontal, Space.m)
                    page(open).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                stem.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var backButton: some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(duration: 0.4)) { deck.moreOpen = nil }
        } label: {
            GlyphView(.back, size: 16)
                .foregroundStyle(Tone.ink.opacity(0.9))
                .frame(width: 42, height: 42)
                .glass(21)
                .overlay(Circle().stroke(Tone.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("volver a más")
    }

    private var stem: some View {
        let all = MoreItem.visible(touchBar: remote.hasTouchBar)
        let live = all.filter { remote.isActive($0) }
        return GeometryReader { geo in
            let wide = StageMetrics.wide(geo.size)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Space.m) {
                        // Lo que está en marcha ahora, arriba y a mano.
                        if !live.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: Space.s) {
                                    ForEach(live) { item in liveChip(item) }
                                }
                                .padding(.horizontal, 2)
                            }
                            .scrollIndicators(.hidden)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        // Soplar: siempre a mano, sin interruptor.
                        BlowHold()
                        ForEach(MoreItem.groups(touchBar: remote.hasTouchBar), id: \.group) { section in
                            branch(section.group, section.items, all: all)
                        }
                    }
                    .frame(maxWidth: wide ? 760 : 560)
                    .padding(.horizontal, wide ? Space.l : Space.m)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.m)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                // Al volver de una función, la lista queda donde estaba: en esa función.
                .onAppear {
                    guard all.indices.contains(deck.moreIndex) else { return }
                    proxy.scrollTo(all[deck.moreIndex], anchor: .center)
                }
                // Al girar la perilla, la opción elegida siempre queda a la vista.
                .onChange(of: deck.moreIndex) { _, i in
                    guard all.indices.contains(i) else { return }
                    withAnimation(.spring(duration: 0.35)) { proxy.scrollTo(all[i], anchor: .center) }
                }
            }
            .animation(.spring(duration: 0.45), value: live)
        }
    }

    /// Una rama: su hoja con el ícono, su nombre y sus funciones.
    private func branch(_ group: MoreGroup, _ items: [MoreItem], all: [MoreItem]) -> some View {
        let running = items.filter { remote.isActive($0) }.count
        return VStack(alignment: .leading, spacing: 12) {
            // Cabecera de herbario: nombre en serif, una hoja de su color y una línea fina.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LeafShape().fill(group.hue.opacity(0.85)).frame(width: 9, height: 14).rotationEffect(.degrees(-25))
                Text(group.title.prefix(1).uppercased() + group.title.dropFirst())
                    .font(Typo.title(19)).foregroundStyle(Tone.ink)
                Rectangle().fill(LinearGradient(colors: [Tone.stroke, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1).padding(.leading, 4)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 5 }
                if running > 0 {
                    Text(running == 1 ? "1 activa" : "\(running) activas")
                        .font(Typo.label(11, .bold)).foregroundStyle(Tone.onEmber)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(Tone.ember))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(items.count)").font(Typo.catalog(11)).foregroundStyle(Tone.ink.opacity(0.35))
                }
            }
            .padding(.horizontal, 2)
            CenteredGrid(minimum: 96, maxColumns: 4, spacing: Space.s) {
                ForEach(items) { item in
                    tile(item, group: group, index: all.firstIndex(of: item) ?? 0).id(item)
                        .modifier(Cascade(index: all.firstIndex(of: item) ?? 0))
                }
            }
        }
        .animation(.spring(duration: 0.35), value: running)
    }

    private func tile(_ item: MoreItem, group: MoreGroup, index: Int) -> some View {
        let selected = index == deck.moreIndex
        let on = remote.isActive(item)
        let number = String(format: "%02d", index + 1)
        return Button {
            Haptic.tap()
            deck.moreIndex = index
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.moreOpen = item }
        } label: {
            // Ficha de espécimen: el icono arriba, su número de catálogo, y el nombre abajo.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: item.symbol).font(.system(size: 19, weight: .regular))
                        .foregroundStyle(on ? Tone.ember : group.hue)
                        .symbolEffect(.pulse, isActive: on)
                        .matchedGeometryEffect(id: item, in: hero)
                    Spacer(minLength: 0)
                    Text(number).font(Typo.catalog(10)).foregroundStyle(Tone.ink.opacity(0.35))
                }
                Spacer(minLength: 6)
                Text(item.title).font(Typo.label(13, .semibold))
                    .foregroundStyle(Tone.ink.opacity(on || selected ? 1 : 0.88))
                    .lineLimit(1).minimumScaleFactor(0.75)
                // Una línea fina de su color: encendida, se llena.
                Capsule().fill(on ? Tone.ember : group.hue.opacity(0.35))
                    .frame(width: on ? 34 : 14, height: 2)
                    .padding(.top, 5)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 96)
            .glass(18, tint: on ? Tone.ember : group.hue.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Tone.ember.opacity(selected ? 0.9 : (on ? 0.5 : 0)), lineWidth: selected ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if remote.blocked(item) {
                    // Le falta un permiso en el Mac.
                    Circle().fill(Color(red: 1, green: 0.78, blue: 0.32)).frame(width: 7, height: 7).padding(10)
                        .offset(x: -16)
                }
            }
            .scaleEffect(selected ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(item.title + (on ? ", activa" : "") + (remote.blocked(item) ? ", falta un permiso en el Mac" : ""))
        .animation(.spring(duration: 0.3), value: selected)
        .animation(.spring(duration: 0.3), value: on)
    }

    private func liveChip(_ item: MoreItem) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.moreOpen = item }
        } label: {
            HStack(spacing: 8) {
                PulseDot(color: Tone.onEmber)
                Image(systemName: item.symbol).font(.system(size: 13, weight: .bold))
                Text(item.title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Tone.onEmber)
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(Tone.ember))
            .shadow(color: Tone.ember.opacity(0.45), radius: 10, y: 3)
        }
        .buttonStyle(PressScale())
    }

    private func tile(_ item: MoreItem, index: Int) -> some View {
        let selected = index == deck.moreIndex
        return Button {
            Haptic.tap()
            deck.moreIndex = index
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.moreOpen = item }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Tone.onEmber : Tone.ink.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(selected ? Tone.ember : Tone.recess))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Tone.ember : Tone.ink)
                        .lineLimit(1)
                    Text(item.detail).font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.5))
                        .lineLimit(2, reservesSpace: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(18)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? Tone.ember.opacity(0.7) : Tone.stroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .animation(.spring(duration: 0.3), value: selected)
    }

    @ViewBuilder private func page(_ item: MoreItem) -> some View {
        switch item {
        case .brightness:
            VStack(spacing: 12) {
                HeroMark(symbol: "sun.max.fill").foregroundStyle(Tone.ember)
                    .symbolEffect(.pulse)
                Text(remote.brightness == nil ? "este Mac no deja cambiar el brillo"
                                              : "gira la perilla para cambiar el brillo")
                    .font(.callout).foregroundStyle(Tone.ink.opacity(0.6))
            }
        case .classes: ClassesPage()
        case .brain: BrainPage()
        case .privacy: PrivacyPage()
        case .game: GamePage()
        case .orientation: OrientationPage()
        case .shots: ShotsPage()
        case .garden: GardenPage()
        case .herbarium: HerbariumPage()
        case .layers: LayersPage()
        case .permissions: PermissionsPage()
        case .detach: DetachPage()
        case .mixer: MixerPage()
        case .gaze: GazePage()
        case .guardian: GuardianPage()
        case .near: NearPage()
        case .guest: GuestPage()
        case .compass: CompassPage()
        case .callLight: CallLightPage()
        case .posture: PosturePage()
        case .photos: TossPage()
        case .send: SendPage()
        case .scan: ScanPage()
        case .lights: LightsPage()
        case .color: ColorPage()
        case .touchBar: TouchBarPage()
        case .gestures: GesturePage()
        case .laser: LaserPage()
        case .power: PowerPage()
        case .routines: NavigationStack { RoutineList() }.tint(Tone.ember)
        case .shortcuts: NavigationStack { ShortcutEditorPage() }.tint(Tone.ember)
        }
    }
}

// MARK: - Color

/// Elegir el acento: una corola de pétalos, uno por color, y el tuyo propio al centro.
struct ColorPage: View {
    @State private var custom = Theme.shared.accent
    @State private var picks = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - Space.l * 2
            let presets = Theme.presets
            ZStack {
                ForEach(Array(presets.enumerated()), id: \.element.id) { i, p in
                    let angle = Double(i) / Double(presets.count) * 2 * .pi - .pi / 2
                    let selected = Theme.shared.hex == p.hex
                    Button {
                        Detents.shared.press()
                        picks += 1
                        withAnimation(.smooth(duration: 0.45)) { Theme.shared.set(hex: p.hex) }
                        custom = Theme.color(p.hex)
                    } label: {
                        Ellipse()
                            .fill(Theme.color(p.hex))
                            .frame(width: side * 0.15, height: side * 0.30)
                            .overlay(Ellipse().stroke(Tone.ink, lineWidth: selected ? 3 : 0))
                            .scaleEffect(selected ? 1.12 : 1)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(p.name)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: cos(angle) * side * 0.33, y: sin(angle) * side * 0.33)
                    .animation(.spring(duration: 0.4, bounce: 0.4), value: selected)
                }
                // Centro de la flor: el selector libre.
                ZStack {
                    Circle().fill(Tone.ember).frame(width: side * 0.3, height: side * 0.3)
                        .boing(picks, amount: 0.1)
                    ColorPicker("color propio", selection: $custom, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(1.5)
                }
                .onChange(of: custom) { _, c in Theme.shared.set(c) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Botones (Stream Deck)

/// Botones grandes que cambian solos según la app que tengas al frente en el Mac.
struct DeckStage: View {
    @EnvironmentObject private var remote: Remote
    @State private var taps: [String: Int] = [:]
    @State private var menuID: String?
    @State private var query = ""

    /// Sin lectura de menús aún: tus atajos de siempre.
    private var fallback: [DeckAction] {
        remote.shortcuts.map { s in
            var mods = 0
            if s.command { mods |= DeckAction.cmd }
            if s.shift { mods |= DeckAction.shift }
            if s.option { mods |= DeckAction.option }
            if s.control { mods |= DeckAction.control }
            return DeckAction(id: "s:\(s.id)", title: s.title, symbol: "command", glyphs: s.glyphs, key: s.key, mods: mods)
        }
    }

    var body: some View {
        let a = remote.appActions
        VStack(spacing: Space.s) {
            header(a)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if !query.isEmpty { results(a) } else { content(a) }
                }
                .padding(.horizontal, Space.m).padding(.bottom, Space.m)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { remote.requestAppActions() }
    }

    // MARK: Encabezado y búsqueda

    private func header(_ a: AppActions?) -> some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                if let icon = remote.icons[remote.frontAppID] {
                    Image(uiImage: icon).resizable().frame(width: 26, height: 26)
                }
                Text(a?.appName ?? (remote.frontAppName.isEmpty ? "tus atajos" : remote.frontAppName))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Tone.ink.opacity(0.8))
                    .contentTransition(.opacity).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tone.ink.opacity(0.45))
                TextField("buscar en los menús de la app", text: $query)
                    .font(.system(size: 14)).foregroundStyle(Tone.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Tone.ink.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(Tone.key))
        }
        .padding(.horizontal, Space.m).padding(.top, Space.m)
    }

    // MARK: Contenido

    @ViewBuilder private func content(_ a: AppActions?) -> some View {
        let quick = (a?.quick.isEmpty == false) ? a!.quick : fallback
        if !quick.isEmpty {
            section(a?.quick.isEmpty == false ? "esenciales" : "tus atajos") { grid(quick) }
        }
        if let f = a?.frequent, !f.isEmpty {
            section("lo que más usas") { grid(f) }
        }
        if let a, !a.menus.isEmpty {
            let current = a.menus.first { $0.id == menuID } ?? a.menus[0]
            section("menús") {
                menuChips(a.menus, selected: current.id)
                grid(current.actions)
            }
        } else if let a, !a.scanned {
            HStack(spacing: 8) {
                WaitingDots()
                Text("leyendo los menús…").font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
            }
        } else if remote.permissions[.accessibility] == .denied {
            permissionCard
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1.2)
                .foregroundStyle(Tone.ink.opacity(0.45)).padding(.leading, 4)
            body()
        }
    }

    private func grid(_ actions: [DeckAction]) -> some View {
        CenteredGrid(minimum: 92, maxColumns: 5, spacing: 10) {
            ForEach(actions) { tile($0) }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: remote.frontAppID)
    }

    private func menuChips(_ menus: [MenuGroup], selected: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(menus) { m in
                    let on = m.id == selected
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(duration: 0.3)) { menuID = m.id }
                    } label: {
                        Text(m.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Tone.onEmber : Tone.ink.opacity(0.75))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(on ? Tone.ember : Tone.key))
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var permissionCard: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Tone.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text("Falta Accesibilidad en el Mac").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink)
                Text("Sin ella no se pueden leer los menús de la app.").font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            Button("pedir") { remote.requestPermission(.accessibility) }
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Tone.onEmber)
                .padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(Tone.ember))
        }
        .padding(Space.s)
        .glass(18)
    }

    // MARK: Búsqueda

    @ViewBuilder private func results(_ a: AppActions?) -> some View {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var seen = Set<String>()
        let pool = ((a?.quick ?? []) + (a?.frequent ?? []) + (a?.menus.flatMap(\.actions) ?? []))
            .filter { seen.insert($0.id).inserted }
        let found = pool.filter {
            ($0.title + " " + ($0.path ?? []).joined(separator: " "))
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
        }
        if found.isEmpty {
            Text("nada se llama así en esta app").font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5))
                .frame(maxWidth: .infinity).padding(.top, Space.xl)
        } else {
            CenteredGrid(minimum: 92, maxColumns: 5, spacing: 10) {
                ForEach(found.prefix(60)) { tile($0, subtitle: $0.glyphs.isEmpty ? $0.path?.first : $0.glyphs) }
            }
        }
    }

    // MARK: Ficha

    private func press(_ action: DeckAction) {
        guard action.enabled else { Haptic.tap(); return }
        Detents.shared.press()
        taps[action.id, default: 0] += 1
        remote.press(action)
    }

    private func tile(_ action: DeckAction, subtitle: String? = nil) -> some View {
        Button { press(action) } label: {
            VStack(spacing: 5) {
                Image(systemName: action.symbol).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(action.enabled ? Tone.ember : Tone.ink.opacity(0.3))
                    .symbolEffect(.bounce, value: taps[action.id, default: 0])
                Text(action.title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tone.ink.opacity(action.enabled ? 0.9 : 0.4))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                Text(subtitle ?? action.glyphs).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tone.ink.opacity(0.4)).lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(height: 92)
            .background(Keycap(on: action.marked))
            .overlay(alignment: .topTrailing) {
                if action.marked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Tone.ember).padding(8)
                }
            }
            .opacity(action.enabled ? 1 : 0.6)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(action.title + (action.glyphs.isEmpty ? "" : ", " + action.glyphs) + (action.enabled ? "" : ", no disponible"))
    }
}

/// Un punto que late suavemente: algo está encendido.
struct PulseDot: View {
    var color: Color = Tone.ember
    @State private var beat = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14).scaleEffect(beat ? 1.3 : 0.6).opacity(beat ? 0 : 1)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { beat = true }
        }
    }
}

extension Remote {
    /// Si una función de "más" está encendida ahora mismo.
    func isActive(_ item: MoreItem) -> Bool {
        switch item {
        case .guardian: guardianOn
        case .privacy: privacyOn
        case .near: nearOn
        case .guest: guestURL != nil
        case .posture: postureOn
        case .lights: lightsAmbient
        case .classes: transcribing
        case .detach: detachedTitle != nil
        case .mixer: mixerApps.contains { $0.gain < 0.99 }
        case .callLight: cameraInUse && UserDefaults.standard.object(forKey: "light.auto") as? Bool ?? true
        default: false
        }
    }
}

extension MoreItem {
    /// Permisos del Mac sin los cuales esta función no anda.
    var needs: [PermissionKind] {
        switch self {
        case .detach, .lights: [.screen]
        case .compass, .laser, .gestures, .gaze, .game: [.accessibility]
        case .posture, .guardian: [.camera]
        case .near: [.bluetooth]
        default: []
        }
    }
}

extension Remote {
    /// ¿A esta función le falta un permiso en el Mac?
    func blocked(_ item: MoreItem) -> Bool {
        item.needs.contains { kind in
            guard let s = permissions[kind] else { return false }
            return PermissionEntry(kind: kind, state: s).needsAttention
        }
    }
}


/// Entrada en cascada: cada ficha aparece un instante después de la anterior,
/// subiendo apenas. Da la sensación de que el invernadero "brota".
struct Cascade: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .scaleEffect(shown ? 1 : 0.96)
            .onAppear {
                guard !shown else { return }
                if reduce { shown = true; return }
                withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(min(0.6, Double(index) * 0.025))) { shown = true }
            }
    }
}
