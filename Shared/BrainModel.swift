import Foundation

/// Un paso de un plan del cerebro. Es deliberadamente simple: un `kind` y los
/// datos que ese tipo de paso necesita.
struct BrainStep: Codable, Hashable {
    var kind: String
    /// Nombre de app, dirección, texto, carpeta o código (AppleScript, terminal).
    var text: String?
    var number: Double?
    /// Si `number` es un hueco de la plantilla ({n}), aquí va su nombre.
    var numberSlot: String?
    /// Tecla de atajo, o nombre de la acción (playPause, lock…).
    var key: String?
    var mods: Int?
    var path: [String]?

    /// Pasos que pueden hacer daño o correr código: piden tu permiso.
    var risky: Bool { kind == "applescript" || kind == "shell" || kind == "quitAll" }

    var label: String {
        switch kind {
        case "openApp": "abrir \(text ?? "")"
        case "quitApp": "cerrar \(text ?? "")"
        case "hideApp": "ocultar \(text ?? "")"
        case "quitAll": "cerrar todas las apps"
        case "openURL": "abrir \(text ?? "")"
        case "openFolder": "abrir carpeta \(text ?? "")"
        case "volume": "volumen \(Int(number ?? 0)) %"
        case "volumeBy": (number ?? 0) >= 0 ? "subir el volumen" : "bajar el volumen"
        case "brightness": "brillo \(Int(number ?? 0)) %"
        case "brightnessBy": (number ?? 0) >= 0 ? "subir el brillo" : "bajar el brillo"
        case "media": "música: \(key ?? "")"
        case "shortcut": "atajo \(DeckAction.glyphs(key: key ?? "", mods: mods ?? 0))"
        case "menu": "menú: \((path ?? []).joined(separator: " › "))"
        case "typeText": "escribir “\((text ?? "").prefix(40))”"
        case "gesture": "gesto \(key ?? "")"
        case "power": "energía: \(key ?? "")"
        case "wait": "esperar \(number ?? 0) s"
        case "applescript": "AppleScript"
        case "shell": "comando de terminal"
        default: kind
        }
    }
}

/// Lo que el cerebro va a hacer, para mostrarlo (y pedir permiso si hace falta).
struct BrainPlan: Codable, Equatable, Identifiable {
    var id: String
    var utterance: String
    var reply: String
    var steps: [BrainStep]
    /// "grafo" (lo recordaba) o "claude".
    var source: String
    var needsConfirm: Bool
}

struct BrainStats: Codable, Equatable {
    var claudeCalls = 0
    var graphHits = 0
    var tokensIn = 0
    var tokensOut = 0

    /// Tokens que no se gastaron porque el grafo resolvió la orden.
    var tokensSaved: Int {
        guard claudeCalls > 0 else { return graphHits * 2200 }
        return graphHits * ((tokensIn + tokensOut) / claudeCalls)
    }
}

struct BrainIntentInfo: Codable, Equatable, Identifiable {
    var id: String
    var template: String
    var uses: Int
    var fixed: Bool
    var trusted: Bool
    var steps: [String]
}

struct BrainSuggestion: Codable, Equatable, Identifiable {
    var id: String        // id del intent
    var label: String
}

struct BrainInfo: Codable, Equatable {
    var stats: BrainStats
    var intents: [BrainIntentInfo]
    var claudeReady: Bool
    var claudeOn: Bool
    var claudePlan: String
}
