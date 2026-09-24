import CryptoKit
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
    /// `width`: ancho en píxeles que pide el iPhone (más en pantalla completa).
    case screen(on: Bool, width: Int)
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
    /// Una foto "tirada" desde el iPhone. Viaja con sus bytes originales (HEIC, JPEG…).
    case photo(Data)
    // Touch Bar del Mac, manejada desde el iPhone.
    case touchBar(TouchBarConfig)
    case touchBarShow(Bool)
    // Luces que siguen a la pantalla del Mac.
    case lightsScan
    case lightsAmbient(Bool)
    case lightsBrightness(Double)
    case lightZone(id: String, zone: LightZone)
    case lightIdentify(id: String)
    /// Cosechar: recortar una zona de la pantalla (coordenadas 0…1) y traerla al iPhone.
    case harvest(x: Double, y: Double, w: Double, h: Double)
    /// Páginas escaneadas (pizarra, proyector, apuntes), ya enderezadas.
    case scanPages([Data])
    /// Cualquier archivo, para el bolsillo del Mac.
    case file(name: String, data: Data)
    /// Un link que se abre en el Mac.
    case openURL(String)
    /// Una foto tirada con dirección: el ángulo del lanzamiento (radianes, 0 =
    /// hacia arriba) y de qué lado del iPhone está el Mac.
    case photoToss(data: Data, angle: Double, side: String)
    // Clases transcritas: el iPhone escucha y el Mac muestra y guarda.
    case transcriptStart(title: String, language: String)
    case transcript(text: String, translation: String?, final: Bool)
    case transcriptMark
    case transcriptEnd
    /// Soplar: las ventanas se dispersan (o vuelven, si ya se habían ido).
    case blow
    /// Sentir la música: el Mac escucha su propio audio y avisa cada golpe.
    case beats(Bool)
    /// Postura: la cámara del Mac vigila si te encorvas.
    case posture(Bool)
    /// Guardián de biblioteca: el Mac avisa si alguien lo toca, lo desenchufa o lo cierra.
    case guardian(on: Bool, siren: Bool)
    case guardianSilence
    /// Bloqueo por cercanía: el Mac mide la señal Bluetooth del iPhone.
    case proximity(on: Bool, threshold: Int)
    /// Brote invitado: un código QR para que un amigo lance fotos desde su navegador.
    case guest(Bool)
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
    case capabilities(touchBar: Bool)
    case touchBarConfig(TouchBarConfig)
    case lights(devices: [LightInfo], ambient: Bool, brightness: Double)
    /// La app que está al frente en el Mac: la perilla y el Stream Deck se adaptan a ella.
    case frontApp(id: String, name: String)
    /// Lo cosechado, en PNG.
    case harvested(Data)
    /// Un golpe de la música, con su fuerza 0…1.
    case beat(Double)
    /// La cámara del Mac se está usando (una videollamada).
    case cameraInUse(Bool)
    case postureState(on: Bool, slouching: Bool)
    case guardianState(on: Bool, siren: Bool)
    case guardianAlert(reason: String, photo: Data?)
    case nearState(on: Bool, rssi: Int?, threshold: Int, locked: Bool)
    case guestPass(url: String?, expires: Double?)
}

/// Qué parte de la pantalla sigue cada foco.
enum LightZone: String, Codable, CaseIterable {
    case all, left, center, right

    var label: String {
        switch self {
        case .all: "toda"
        case .left: "izquierda"
        case .center: "centro"
        case .right: "derecha"
        }
    }
}

/// Un foco encontrado en la red local.
struct LightInfo: Codable, Hashable, Identifiable {
    var id: String       // identificador del fabricante
    var sku: String      // modelo, p. ej. H6008
    var ip: String
    var zone: LightZone
}

/// Qué muestra la Touch Bar de Zarcillo en el Mac y en qué orden.
struct TouchBarConfig: Codable, Equatable {
    struct Slot: Codable, Equatable, Identifiable {
        var kind: Kind
        var on: Bool
        var id: Kind { kind }
    }

    enum Kind: String, Codable, CaseIterable {
        case playing, media, volume, brightness, routines, status

        var label: String {
            switch self {
            case .playing: "lo que suena"
            case .media: "controles de música"
            case .volume: "volumen"
            case .brightness: "brillo"
            case .routines: "escenas"
            case .status: "estado del iPhone"
            }
        }

        var symbol: String {
            switch self {
            case .playing: "music.note"
            case .media: "playpause.fill"
            case .volume: "speaker.wave.2.fill"
            case .brightness: "sun.max.fill"
            case .routines: "sparkles"
            case .status: "iphone"
            }
        }
    }

    var slots: [Slot]

    static let standard = TouchBarConfig(slots: [
        Slot(kind: .playing, on: true),
        Slot(kind: .media, on: true),
        Slot(kind: .volume, on: true),
        Slot(kind: .brightness, on: false),
        Slot(kind: .routines, on: false),
        Slot(kind: .status, on: false),
    ])
}

/// Mensajes que se mandan muchas veces por segundo (puntero, desplazamiento,
/// pantalla en vivo) van en binario: un byte de tipo y los datos crudos, sin
/// pasar por JSON. Un mensaje JSON siempre empieza con `{`, así que no se
/// confunden.
enum Fast {
    static let move: UInt8 = 1
    static let scroll: UInt8 = 2
    static let frame: UInt8 = 3

    static func vector(_ tag: UInt8, _ dx: Double, _ dy: Double) -> Data {
        var d = Data([tag])
        var x = Float32(dx).bitPattern.bigEndian, y = Float32(dy).bitPattern.bigEndian
        d.append(Data(bytes: &x, count: 4))
        d.append(Data(bytes: &y, count: 4))
        return d
    }

    static func readVector(_ d: Data) -> (Double, Double)? {
        guard d.count == 9 else { return nil }
        func f(_ at: Int) -> Double {
            let bits = d[d.startIndex + at ..< d.startIndex + at + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return Double(Float32(bitPattern: bits))
        }
        return (f(1), f(5))
    }
}

/// El iPhone se anuncia por Bluetooth con este servicio; el Mac lo reconoce
/// por una huella del código de enlace, sin que viaje el código.
enum NearBeacon {
    static let service = "7A3E9C51-2B84-4F0D-9E6A-5C1D8B2F4A63"
    static let token = "7A3E9C52-2B84-4F0D-9E6A-5C1D8B2F4A63"

    static func token(passcode: String) -> Data {
        Data(SHA256.hash(data: Data("zarcillo-cerca-\(passcode)".utf8)).prefix(12))
    }
}
