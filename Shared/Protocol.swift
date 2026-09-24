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
}

/// Mac → iPhone.
enum Event: Codable {
    case welcome(mac: String, volume: Double?, brightness: Double?, canControl: Bool)
    case apps([AppTile])
    case levels(volume: Double?, brightness: Double?)
    case status(String)
}
