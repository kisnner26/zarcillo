import Foundation

/// Una acción que el iPhone (o la Touch Bar) puede lanzar en la app que está
/// al frente en el Mac: casi siempre un elemento de su barra de menús, que se
/// pulsa por su ruta; si no, un atajo de teclado.
struct DeckAction: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    /// Cómo se ve el atajo: ⌘S, ⇧⌘Z…
    var glyphs = ""
    /// Ruta en la barra de menús: ["Archivo", "Guardar"].
    var path: [String]?
    /// Atajo de respaldo (tecla y modificadores).
    var key: String?
    var mods = 0
    var enabled = true
    var marked = false

    static let cmd = 1, shift = 2, option = 4, control = 8

    var shortcut: Shortcut? {
        guard let key else { return nil }
        return Shortcut(title: title, key: key, command: mods & Self.cmd != 0, shift: mods & Self.shift != 0,
                        option: mods & Self.option != 0, control: mods & Self.control != 0)
    }

    static func glyphs(key: String, mods: Int) -> String {
        Shortcut(title: "", key: key, command: mods & cmd != 0, shift: mods & shift != 0,
                 option: mods & option != 0, control: mods & control != 0).glyphs
    }
}

struct MenuGroup: Codable, Hashable, Identifiable {
    var title: String
    var actions: [DeckAction]
    var id: String { title }
}

/// Todo lo que el iPhone necesita para mostrar la app de turno.
struct AppActions: Codable, Equatable {
    var appID: String
    var appName: String
    /// Lo esencial de esta app: curado si lo conocemos; si no, lo que su propio menú ofrece.
    var quick: [DeckAction]
    /// Lo que más usas aquí.
    var frequent: [DeckAction]
    var menus: [MenuGroup]
    /// ¿Ya se leyó su barra de menús? (falso mientras se lee, o si falta Accesibilidad)
    var scanned: Bool
}

/// Un símbolo razonable para cada acción, por lo que dice su título (en español
/// o inglés) y, si no, por su atajo.
enum DeckSymbols {
    private static let words: [([String], String)] = [
        (["guardar como", "save as"], "square.and.arrow.down.on.square"),
        (["guardar", "save"], "square.and.arrow.down"),
        (["nueva ventana", "new window"], "macwindow.badge.plus"),
        (["nueva pestana", "new tab"], "plus.square.on.square"),
        (["nuevo", "nueva", "new "], "plus.square"),
        (["abrir", "open"], "folder"),
        (["cerrar pestana", "close tab"], "xmark.square"),
        (["cerrar", "close"], "xmark.circle"),
        (["imprimir", "print"], "printer"),
        (["exportar", "export", "compartir", "share"], "square.and.arrow.up"),
        (["deshacer", "undo"], "arrow.uturn.backward"),
        (["rehacer", "redo"], "arrow.uturn.forward"),
        (["copiar", "copy"], "doc.on.doc"),
        (["cortar", "cut"], "scissors"),
        (["pegar", "paste"], "doc.on.clipboard"),
        (["seleccionar todo", "select all"], "checkmark.rectangle"),
        (["reemplazar", "replace"], "arrow.left.arrow.right"),
        (["buscar", "find", "search"], "magnifyingglass"),
        (["acercar", "zoom in", "ampliar"], "plus.magnifyingglass"),
        (["alejar", "zoom out", "reducir"], "minus.magnifyingglass"),
        (["tamano real", "actual size", "ajustar", "fit "], "arrow.up.left.and.arrow.down.right"),
        (["pantalla completa", "full screen"], "arrow.up.left.and.arrow.down.right.circle"),
        (["recargar", "reload", "actualizar", "refresh"], "arrow.clockwise"),
        (["atras", "back"], "chevron.left"),
        (["adelante", "forward"], "chevron.right"),
        (["negrita", "bold"], "bold"),
        (["cursiva", "italic"], "italic"),
        (["subrayado", "underline"], "underline"),
        (["ejecutar", "run", "reproducir", "play"], "play.fill"),
        (["detener", "stop", "pausar", "pause"], "stop.fill"),
        (["compilar", "build"], "hammer.fill"),
        (["preferencias", "ajustes", "settings", "preferences"], "gearshape"),
        (["ocultar", "hide"], "eye.slash"),
        (["salir", "quit"], "power"),
        (["borrar", "eliminar", "delete", "trash", "papelera"], "trash"),
        (["enviar", "send"], "paperplane"),
        (["responder", "reply"], "arrowshape.turn.up.left"),
        (["marcador", "bookmark", "favorito"], "bookmark"),
        (["duplicar", "duplicate"], "plus.square.on.square"),
        (["renombrar", "rename"], "pencil"),
        (["informacion", "info"], "info.circle"),
        (["ayuda", "help"], "questionmark.circle"),
        (["silenciar", "mute"], "speaker.slash"),
        (["comentar", "comment"], "text.bubble"),
        (["minimizar", "minimize"], "minus.rectangle"),
        (["capturar", "screenshot"], "camera.viewfinder"),
    ]

    static func guess(title: String) -> String {
        let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for (keys, symbol) in words where keys.contains(where: { t.contains($0) }) { return symbol }
        return "command"
    }
}
