import SwiftUI

/// Qué hace la perilla y qué botones muestra el Stream Deck según la app que
/// está al frente en el Mac.
struct AppContext {
    enum Knob {
        /// Flechas izquierda/derecha: un cuadro por marca en editores de video.
        case frames
        /// ⌘+ / ⌘−
        case zoom
        /// Flechas: una diapositiva por marca.
        case slides
        /// Desplazamiento vertical.
        case scroll
        /// Volumen del Mac.
        case volume

        var caption: String {
            switch self {
            case .frames: "cuadro"
            case .zoom: "zoom"
            case .slides: "diapo"
            case .scroll: "scroll"
            case .volume: ""
            }
        }
    }

    struct Button: Identifiable {
        let title: String
        let symbol: String
        let shortcut: Shortcut
        var id: String { title }
    }

    let name: String
    let knob: Knob
    let buttons: [Button]

    private static func b(_ title: String, _ symbol: String, _ key: String,
                          cmd: Bool = false, shift: Bool = false, opt: Bool = false, ctrl: Bool = false) -> Button {
        Button(title: title, symbol: symbol,
               shortcut: Shortcut(title: title, key: key, command: cmd, shift: shift, option: opt, control: ctrl))
    }

    /// Perfil por identificador de app. Lo que no está aquí usa volumen y tus atajos.
    static func `for`(_ bundle: String) -> AppContext? {
        switch bundle {
        case "com.apple.FinalCut":
            return AppContext(name: "Final Cut", knob: .frames, buttons: [
                b("cortar", "scissors", "b", cmd: true), b("entrada", "arrow.right.to.line", "i"),
                b("salida", "arrow.left.to.line", "o"), b("reproducir", "playpause.fill", "space"),
                b("marcador", "bookmark.fill", "m"), b("deshacer", "arrow.uturn.backward", "z", cmd: true),
                b("acercar", "plus.magnifyingglass", "=", cmd: true), b("exportar", "square.and.arrow.up", "e", cmd: true),
            ])
        case let id where id.hasPrefix("com.adobe.PremierePro"):
            return AppContext(name: "Premiere", knob: .frames, buttons: [
                b("cortar", "scissors", "k", cmd: true), b("entrada", "arrow.right.to.line", "i"),
                b("salida", "arrow.left.to.line", "o"), b("reproducir", "playpause.fill", "space"),
                b("marcador", "bookmark.fill", "m"), b("deshacer", "arrow.uturn.backward", "z", cmd: true),
                b("acercar", "plus.magnifyingglass", "="), b("exportar", "square.and.arrow.up", "m", cmd: true),
            ])
        case "com.blackmagic-design.DaVinciResolve", "com.blackmagic-design.DaVinciResolveLite":
            return AppContext(name: "DaVinci", knob: .frames, buttons: [
                b("cortar", "scissors", "b", cmd: true), b("entrada", "arrow.right.to.line", "i"),
                b("salida", "arrow.left.to.line", "o"), b("reproducir", "playpause.fill", "space"),
                b("marcador", "bookmark.fill", "m"), b("deshacer", "arrow.uturn.backward", "z", cmd: true),
            ])
        case "com.apple.dt.Xcode":
            return AppContext(name: "Xcode", knob: .scroll, buttons: [
                b("compilar", "hammer.fill", "b", cmd: true), b("ejecutar", "play.fill", "r", cmd: true),
                b("detener", "stop.fill", ".", cmd: true), b("probar", "checkmark.diamond.fill", "u", cmd: true),
                b("limpiar", "trash", "k", cmd: true, shift: true), b("abrir rápido", "magnifyingglass", "o", cmd: true, shift: true),
                b("comentar", "text.bubble", "/", cmd: true), b("deshacer", "arrow.uturn.backward", "z", cmd: true),
            ])
        case "com.microsoft.VSCode":
            return AppContext(name: "VS Code", knob: .scroll, buttons: [
                b("comandos", "command", "p", cmd: true, shift: true), b("archivo", "doc.text.magnifyingglass", "p", cmd: true),
                b("terminal", "terminal", "`", ctrl: true), b("comentar", "text.bubble", "/", cmd: true),
                b("guardar", "square.and.arrow.down", "s", cmd: true), b("formatear", "text.alignleft", "f", shift: true, opt: true),
            ])
        case "com.figma.Desktop":
            return AppContext(name: "Figma", knob: .zoom, buttons: [
                b("mover", "cursorarrow", "v"), b("marco", "number", "f"), b("rectángulo", "rectangle", "r"),
                b("texto", "textformat", "t"), b("pluma", "pencil.tip", "p"), b("comentar", "text.bubble", "c"),
                b("agrupar", "rectangle.3.group", "g", cmd: true), b("deshacer", "arrow.uturn.backward", "z", cmd: true),
            ])
        case "com.apple.Photos", "com.apple.Preview", "com.adobe.Photoshop", "com.pixelmatorteam.pixelmator.x":
            return AppContext(name: "Imágenes", knob: .zoom, buttons: [
                b("ajustar", "arrow.up.left.and.arrow.down.right", "0", cmd: true), b("anterior", "chevron.left", "left"),
                b("siguiente", "chevron.right", "right"), b("girar", "rotate.right", "r", cmd: true),
                b("deshacer", "arrow.uturn.backward", "z", cmd: true),
            ])
        case "com.apple.iWork.Keynote", "com.microsoft.Powerpoint":
            return AppContext(name: "Presentación", knob: .slides, buttons: [
                b("anterior", "chevron.left", "left"), b("siguiente", "chevron.right", "right"),
                b("pantalla negra", "rectangle.fill", "b"), b("salir", "xmark", "escape"),
            ])
        case "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac":
            return AppContext(name: "Navegador", knob: .scroll, buttons: [
                b("nueva pestaña", "plus.square", "t", cmd: true), b("cerrar", "xmark.square", "w", cmd: true),
                b("reabrir", "arrow.uturn.backward.square", "t", cmd: true, shift: true), b("atrás", "chevron.left", "[", cmd: true),
                b("adelante", "chevron.right", "]", cmd: true), b("recargar", "arrow.clockwise", "r", cmd: true),
                b("buscar", "magnifyingglass", "f", cmd: true), b("dirección", "link", "l", cmd: true),
            ])
        case "us.zoom.xos":
            return AppContext(name: "Zoom", knob: .volume, buttons: [
                b("silencio", "mic.slash.fill", "a", cmd: true, shift: true), b("cámara", "video.slash.fill", "v", cmd: true, shift: true),
                b("compartir", "rectangle.on.rectangle", "s", cmd: true, shift: true), b("mano", "hand.raised.fill", "y", opt: true),
                b("chat", "bubble.left.fill", "h", cmd: true, shift: true), b("salir", "phone.down.fill", "w", cmd: true),
            ])
        case "com.microsoft.teams2", "com.microsoft.teams":
            return AppContext(name: "Teams", knob: .volume, buttons: [
                b("silencio", "mic.slash.fill", "m", cmd: true, shift: true), b("cámara", "video.slash.fill", "o", cmd: true, shift: true),
                b("mano", "hand.raised.fill", "k", cmd: true, shift: true), b("salir", "phone.down.fill", "h", cmd: true, shift: true),
            ])
        case "com.apple.Music", "com.spotify.client":
            return AppContext(name: "Música", knob: .volume, buttons: [])
        default:
            return nil
        }
    }
}
