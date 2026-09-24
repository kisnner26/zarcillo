import Foundation

// Lo que viaja entre el iPhone y el Mac. Todo es JSON con un prefijo de largo
// (ver `Channel`), así que agregar un caso nuevo no rompe el formato.

enum ZarcilloService {
    /// Tipo Bonjour con el que el Mac se anuncia en la red local.
    static let type = "_zarcillo._tcp"
}

enum LevelKind: String, Codable {
    case volume, brightness
}

enum MouseButton: String, Codable {
    case left, right
}

enum MediaKey: String, Codable {
    case playPause, next, previous
}

enum DesktopGesture: String, Codable, CaseIterable {
    case spaceLeft, spaceRight, missionControl, appWindows, spotlight

    var label: String {
        switch self {
        case .spaceLeft: "escritorio izquierdo"
        case .spaceRight: "escritorio derecho"
        case .missionControl: "Mission Control"
        case .appWindows: "ventanas de la app"
        case .spotlight: "Spotlight"
        }
    }

    var symbol: String {
        switch self {
        case .spaceLeft: "arrow.left"
        case .spaceRight: "arrow.right"
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .spotlight: "magnifyingglass"
        }
    }
}

/// Un atajo de teclado que el usuario arma en el iPhone y el Mac ejecuta.
struct Shortcut: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    /// Una letra o número, o un nombre de tecla especial (`space`, `tab`, `left`…).
    var key: String
    var command = false
    var shift = false
    var option = false
    var control = false

    var glyphs: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + keyGlyph
    }

    var keyGlyph: String {
        switch key {
        case "space": "espacio"
        case "tab": "⇥"
        case "return": "↩"
        case "escape": "esc"
        case "delete": "⌫"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        default: key.uppercased()
        }
    }

    static let defaults: [Shortcut] = [
        Shortcut(title: "cambiar app", key: "tab", command: true),
        Shortcut(title: "copiar", key: "c", command: true),
        Shortcut(title: "pegar", key: "v", command: true),
        Shortcut(title: "deshacer", key: "z", command: true),
        Shortcut(title: "cerrar pestaña", key: "w", command: true),
        Shortcut(title: "captura", key: "4", command: true, shift: true),
        Shortcut(title: "bloquear", key: "q", command: true, control: true),
    ]
}

/// Una app del Dock del Mac, con su icono real ya rasterizado.
struct AppTile: Codable, Hashable, Identifiable {
    var id: String          // bundle id
    var name: String
    var icon: Data          // PNG
    var running: Bool
}

/// Lo que suena en el Mac (Música o Spotify).
struct NowPlaying: Codable, Equatable {
    var source: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    /// Cambia con cada canción: sirve para saber cuándo pedir otra carátula.
    var trackID: String
}

/// Una ventana abierta en el Mac.
struct WindowInfo: Codable, Hashable, Identifiable {
    var id: String          // pid:índice
    var appID: String       // bundle id
    var title: String
    var minimized: Bool
}

enum PowerAction: String, Codable {
    case lock, sleep, displayOff
}

/// Un paso de una escena.
enum RoutineStep: Codable, Hashable {
    case openApp(id: String, name: String)
    case openURL(String)
    case volume(Double)
    case brightness(Double)
    case media(MediaKey)
    case shortcut(Shortcut)
    /// Un atajo de la app Atajos del Mac, por nombre (sirve para Enfoque/No molestar).
    case runShortcut(String)
    case gesture(DesktopGesture)
    case power(PowerAction)
    case wait(Double)

    var label: String {
        switch self {
        case .openApp(_, let name): "abrir \(name)"
        case .openURL(let url): "abrir \(url.replacingOccurrences(of: "https://", with: ""))"
        case .volume(let v): "volumen \(Int(v * 100)) %"
        case .brightness(let v): "brillo \(Int(v * 100)) %"
        case .media(let m):
            switch m {
            case .playPause: "pausar / reanudar música"
            case .next: "siguiente canción"
            case .previous: "canción anterior"
            }
        case .shortcut(let s): "atajo \(s.glyphs)"
        case .runShortcut(let name): "Atajos: \(name)"
        case .gesture(let g): g.label
        case .power(let p):
            switch p {
            case .lock: "bloquear el Mac"
            case .sleep: "suspender el Mac"
            case .displayOff: "apagar la pantalla"
            }
        case .wait(let s): "esperar \(s.formatted()) s"
        }
    }

    var symbol: String {
        switch self {
        case .openApp: "app.badge"
        case .openURL: "link"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .media: "playpause.fill"
        case .shortcut: "command"
        case .runShortcut: "square.stack.3d.up.fill"
        case .gesture(let g): g.symbol
        case .power: "power"
        case .wait: "hourglass"
        }
    }
}

/// Varias acciones con un toque: "modo clase", "cine"…
struct Routine: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var symbol: String
    var steps: [RoutineStep]

    static let defaults: [Routine] = [
        Routine(name: "modo clase", symbol: "graduationcap.fill", steps: [
            .media(.playPause),
            .volume(0.1),
            .openURL("https://uamvirtual.uam.edu.ni/grado/my/"),
        ]),
        Routine(name: "cine", symbol: "film.fill", steps: [
            .brightness(0.35),
            .volume(0.7),
        ]),
        Routine(name: "me voy", symbol: "figure.walk", steps: [
            .media(.playPause),
            .power(.lock),
        ]),
    ]
}

/// iPhone → Mac.
enum Command: Codable {
    case hello(device: String)
    case listApps
    case launch(id: String)
    case setLevel(kind: LevelKind, value: Double)   // 0...1
    case gesture(DesktopGesture)
    case move(dx: Double, dy: Double)
    case click(button: MouseButton)
    case press(down: Bool)
    case scroll(dx: Double, dy: Double)
    case media(MediaKey)
    case shortcut(Shortcut)
    // Teclado remoto
    case type(text: String)
    case key(name: String)
    // Portapapeles
    case pushClipboard(text: String?, image: Data?)
    case pullClipboard
    // Música
    case seek(seconds: Double)
    // Láser
    case laser(on: Bool)
    case laserMove(dx: Double, dy: Double)
    // Pantalla en vivo: coordenadas normalizadas 0…1 sobre la pantalla principal.
    case screen(on: Bool)
    case tapScreen(x: Double, y: Double, button: MouseButton)
    // Ventanas
    case listWindows
    case focusWindow(id: String)
    // Escenas y energía
    case runRoutine(Routine)
    case power(PowerAction)
    // Lo que el Mac muestra por su cuenta (Touch Bar, HUD): tus escenas y tu color.
    case syncRoutines([Routine])
    case accent(hex: Int)
}

/// Mac → iPhone.
enum Event: Codable {
    case welcome(mac: String, volume: Double?, brightness: Double?, canControl: Bool)
    case apps([AppTile])
    case levels(volume: Double?, brightness: Double?)
    case status(String)
    case machine(hardwareAddress: String?, ip: String?)
    case permissions(accessibility: Bool, screen: Bool)
    case clipboard(text: String?, image: Data?)
    case nowPlaying(NowPlaying?)
    case artwork(trackID: String, data: Data)
    case frame(Data)
    case windows([WindowInfo])
}
