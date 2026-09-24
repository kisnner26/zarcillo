import Foundation

/// Entiende órdenes habladas en español para el Mac. Es determinista: cada
/// frase se parte en cláusulas ("cierra Fotos y abre Safari"), cada cláusula
/// busca su verbo y su objeto, y si una cláusula no trae verbo hereda el de la
/// anterior ("cierra Fotos, Música y Notas"). Si alguna cláusula no se
/// entiende, `understood` es falso y quien llama puede pedir ayuda al modelo.
struct VoiceGrammar {
    let apps: [AppTile]
    let routines: [Routine]

    struct Result {
        var steps: [RoutineStep] = []
        var understood = true
        var unknown: [String] = []
    }

    private enum Verb { case open, quit, hide, search, up, down, set, type }
    private enum Object { case volume, brightness }

    // MARK: Entrada

    func parse(_ text: String) -> Result {
        var result = Result()
        var lastVerb: Verb?
        var lastObject: Object?
        // "escribe …": todo lo que sigue es el texto tal cual, con sus "y" y comas.
        var commands = text
        var typed: String?
        if let r = text.range(of: "(^|[,.;]\\s*|\\by\\s+|\\bluego\\s+|\\bdespu[eé]s\\s+)(escr[ií]beme|escribe|escribir|dicta|teclea|tipea)\\b[:,]?\\s*",
                              options: [.regularExpression, .caseInsensitive]) {
            commands = String(text[..<r.lowerBound])
            typed = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for original in Self.split(commands) {
            let c = Self.clean(original)
            guard !c.isEmpty else { continue }
            if let steps = understand(c, lastVerb: &lastVerb, lastObject: &lastObject) {
                result.steps += steps
            } else {
                result.understood = false
                result.unknown.append(original.trimmingCharacters(in: .whitespaces))
            }
        }
        if let typed, !typed.isEmpty { result.steps.append(.typeText(typed)) }
        return result
    }

    // MARK: Una cláusula

    private func understand(_ c: String, lastVerb: inout Verb?, lastObject: inout Object?) -> [RoutineStep]? {
        // 1. Frases fijas: teclado, música, sistema. Van primero porque
        //    "cierra la pestaña" no es cerrar una app llamada "pestaña".
        if let fixed = fixed(c) {
            lastVerb = nil
            return fixed
        }

        // 2. Escenas por nombre ("modo clase", "activa cine").
        if let r = routines.first(where: { c.contains(Self.fold($0.name)) }) {
            lastVerb = nil
            return r.steps
        }

        // 3. Volumen y brillo.
        let object: Object? = Self.has(c, ["volumen", "sonido", "audio"]) ? .volume
            : Self.has(c, ["brillo", "luminosidad"]) ? .brightness : nil
        var verb = Self.verb(c)
        if let object {
            lastObject = object
            if verb == .up || verb == .down { lastVerb = verb }
            return level(c, object, verb: verb ?? lastVerb)
        }
        if verb == .up || verb == .down {
            lastVerb = verb
            return level(c, lastObject ?? .volume, verb: verb)
        }

        // 4. Verbo + objeto: abrir, cerrar, ocultar, buscar.
        var target = c
        if let v = verb {
            target = Self.after(Self.verbWords(v), in: c)
        } else if let v = lastVerb, v != .up && v != .down {
            verb = v     // "cierra Fotos, Música y Notas"
        }
        target = Self.strip(["la app", "la aplicacion", "el programa", "la", "el", "los", "las", "un", "una", "mi", "de", "del"],
                            from: target, onlyLeading: true)
        guard let v = verb, !target.isEmpty else { return nil }
        lastVerb = v

        switch v {
        case .quit:
            if Self.has(target, ["todo", "todas", "todos"]) { return [.quitAllApps] }
            return [.quitApp(appName(target))]
        case .hide:
            return [.hideApp(appName(target))]
        case .search:
            return [.openURL(Self.searchURL(target))]
        case .open:
            if Self.has(c, ["carpeta"]) || Self.folders.contains(where: { target.hasPrefix($0) }) {
                return [.openFolder(target)]
            }
            if let app = dockApp(target) { return [.openApp(id: app.id, name: app.name)] }
            if let site = Self.site(target) { return [.openURL(site)] }
            return [.openAppNamed(appName(target))]
        case .set:
            if let app = dockApp(target) { return [.openApp(id: app.id, name: app.name)] }
            return nil
        default:
            return nil
        }
    }

    private func level(_ c: String, _ object: Object, verb: Verb?) -> [RoutineStep]? {
        let n = Self.number(in: c)
        let absolute = n != nil && (c.range(of: "\\b(al|a|en|hasta)\\s+\\d", options: .regularExpression) != nil
            || verb == .set || verb == nil || verb == .open || c.contains("%"))
        func set(_ v: Double) -> RoutineStep { object == .volume ? .volume(v) : .brightness(v) }
        func by(_ d: Double) -> RoutineStep { object == .volume ? .volumeBy(d) : .brightnessBy(d) }

        if Self.has(c, ["maximo", "tope", "todo lo que da"]) { return [set(1)] }
        if Self.has(c, ["minimo"]) { return [set(object == .volume ? 0 : 0.05)] }
        if Self.has(c, ["mitad"]) { return [set(0.5)] }
        if let n, absolute { return [set(min(100, max(0, n)) / 100)] }
        let amount = n.map { $0 / 100 } ?? (Self.has(c, ["un poco", "poquito", "tantito"]) ? 0.08
            : Self.has(c, ["mucho", "bastante"]) ? 0.3 : 0.15)
        var verb = verb
        if verb != .up && verb != .down {
            // "pon más volumen", "el brillo más bajo"
            if Self.has(c, ["mas", "sube", "alto", "fuerte", "arriba"]) { verb = .up }
            else if Self.has(c, ["menos", "baja", "bajo", "abajo", "suave"]) { verb = .down }
        }
        switch verb {
        case .up: return [by(amount)]
        case .down: return [by(-amount)]
        default: return nil
        }
    }

    // MARK: Frases fijas

    private func fixed(_ c: String) -> [RoutineStep]? {
        func key(_ k: String, cmd: Bool = true, shift: Bool = false, opt: Bool = false, ctrl: Bool = false, _ title: String) -> [RoutineStep] {
            [.shortcut(Shortcut(title: title, key: k, command: cmd, shift: shift, option: opt, control: ctrl))]
        }
        let h = { (words: [String]) in Self.has(c, words) }

        // Pestañas y ventanas.
        if h(["pestana"]) {
            if h(["cierra", "cerrar", "quita"]) { return key("w", "cerrar pestaña") }
            if h(["abre", "nueva", "otra", "crea"]) { return key("t", "nueva pestaña") }
            if h(["reabre", "recupera", "vuelve a abrir", "restaura"]) { return key("t", shift: true, "reabrir pestaña") }
            if h(["siguiente", "derecha"]) { return key("]", shift: true, "pestaña siguiente") }
            if h(["anterior", "izquierda"]) { return key("[", shift: true, "pestaña anterior") }
        }
        if h(["ventana"]) && !h(["ventanas"]) {
            if h(["cierra", "cerrar"]) { return key("w", "cerrar ventana") }
            if h(["nueva", "abre", "otra"]) { return key("n", "nueva ventana") }
            if h(["minimiza"]) { return key("m", "minimizar") }
            if h(["pantalla completa", "maximiza", "agranda"]) { return key("f", ctrl: true, "pantalla completa") }
        }
        if h(["pantalla completa"]) { return key("f", ctrl: true, "pantalla completa") }
        if c == "minimiza" || c == "minimizar" || h(["minimiza esto", "minimiza la"]) { return key("m", "minimizar") }

        // Edición.
        if Self.starts(c, ["copia", "copiar", "copialo"]) && c.count < 16 { return key("c", "copiar") }
        if Self.starts(c, ["pega", "pegar", "pegalo"]) && c.count < 16 { return key("v", "pegar") }
        if Self.starts(c, ["corta", "cortar"]) && c.count < 14 { return key("x", "cortar") }
        if h(["deshaz", "deshacer", "deshazlo"]) { return key("z", "deshacer") }
        if h(["rehaz", "rehacer"]) { return key("z", shift: true, "rehacer") }
        if h(["selecciona todo", "seleccionar todo", "selecciona todo el"]) { return key("a", "seleccionar todo") }
        if Self.starts(c, ["guarda", "guardar", "guardalo"]) && c.count < 20 { return key("s", "guardar") }
        if Self.starts(c, ["imprime", "imprimir"]) { return key("p", "imprimir") }
        if h(["recarga", "refresca", "actualiza la pagina", "recargar"]) { return key("r", "recargar") }
        if h(["busca en la pagina", "buscar en la pagina", "busca en esta pagina"]) { return key("f", "buscar en la página") }
        if c == "atras" || h(["pagina anterior", "regresa a la pagina", "ve atras", "vuelve atras"]) { return key("[", "atrás") }
        if c == "adelante" || h(["pagina siguiente", "ve adelante"]) { return key("]", "adelante") }
        if Self.starts(c, ["acerca", "acercate", "agranda", "zoom in", "haz zoom"]) || c == "mas grande" { return key("=", "acercar") }
        if Self.starts(c, ["aleja", "alejate", "achica", "zoom out"]) || c == "mas pequeno" { return key("-", "alejar") }
        if Self.starts(c, ["enter", "intro", "envia", "enviar", "dale enter"]) && c.count < 14 {
            return [.shortcut(Shortcut(title: "enter", key: "return"))]
        }
        if Self.starts(c, ["escape", "esc"]) && c.count < 10 { return [.shortcut(Shortcut(title: "esc", key: "escape"))] }
        if h(["cambia de app", "siguiente app", "cambiar de app", "otra app"]) { return key("tab", "cambiar app") }

        // Capturas.
        if h(["captura", "screenshot", "pantallazo", "foto de la pantalla"]) {
            return h(["zona", "parte", "region", "area", "recorte", "trozo"])
                ? key("4", shift: true, "captura de una zona")
                : key("3", shift: true, "captura de pantalla")
        }

        // Música.
        if h(["siguiente cancion", "pasa la cancion", "cambia la cancion", "otra cancion", "salta", "skip"])
            || c == "siguiente" { return [.media(.next)] }
        if h(["cancion anterior", "la de antes", "la anterior", "regresa la cancion"]) || c == "anterior" { return [.media(.previous)] }
        if h(["pausa", "pausar", "deten", "detener", "para la musica", "para la cancion", "stop",
              "reproduce", "reanuda", "continua", "dale play", "play", "pon musica", "pon la musica"])
            && !h(["volumen"]) { return [.media(.playPause)] }

        // Sonido.
        if h(["silencia", "silencio", "mutea", "mute", "quita el sonido", "sin sonido", "callate"]) { return [.volume(0)] }
        if h(["activa el sonido", "quita el silencio", "desmutea", "unmute"]) { return [.volume(0.4)] }

        // Sistema.
        if h(["bloquea", "bloquear"]) { return [.power(.lock)] }
        if h(["apaga la pantalla", "apagar la pantalla"]) { return [.power(.displayOff)] }
        if h(["suspende", "suspender", "duerme", "a dormir", "reposo", "mandalo a dormir"]) { return [.power(.sleep)] }
        if h(["mission control", "todas las ventanas", "ver ventanas"]) { return [.gesture(.missionControl)] }
        if h(["ventanas de la app", "ventanas de esta app"]) { return [.gesture(.appWindows)] }
        if h(["spotlight"]) { return [.gesture(.spotlight)] }
        if h(["escritorio"]) && h(["derecha", "siguiente", "proximo"]) { return [.gesture(.spaceRight)] }
        if h(["escritorio"]) && h(["izquierda", "anterior"]) { return [.gesture(.spaceLeft)] }
        if h(["cierra todo", "cierra todas", "cerrar todo", "cierra las apps"]) { return [.quitAllApps] }
        return nil
    }

    // MARK: Apps

    private func dockApp(_ spoken: String) -> AppTile? {
        let n = Self.fold(spoken)
        let wanted = [n] + (Self.aliases[n] ?? [])
        return apps.first { a in wanted.contains(Self.fold(a.name)) }
            ?? apps.first { a in wanted.contains { w in Self.fold(a.name).hasPrefix(w) || (w.count > 3 && w.hasPrefix(Self.fold(a.name))) } }
    }

    /// El nombre como lo diría el Mac: si está en el Dock, el suyo; si no, lo dicho.
    private func appName(_ spoken: String) -> String { dockApp(spoken)?.name ?? spoken }

    // MARK: Vocabulario

    private static let aliases: [String: [String]] = [
        "fotos": ["photos"], "musica": ["music"], "notas": ["notes"], "calendario": ["calendar"],
        "mensajes": ["messages"], "correo": ["mail"], "ajustes": ["system settings", "configuracion del sistema"],
        "chrome": ["google chrome"], "code": ["visual studio code"], "vscode": ["visual studio code"],
        "word": ["microsoft word"], "excel": ["microsoft excel"], "powerpoint": ["microsoft powerpoint"],
    ]

    private static let folders = ["descargas", "documentos", "mis documentos", "carpeta", "imagenes", "peliculas",
                                  "carpeta personal", "aplicaciones"]

    private static let sites: [String: String] = [
        "youtube": "https://youtube.com", "gmail": "https://mail.google.com", "google": "https://google.com",
        "netflix": "https://netflix.com", "instagram": "https://instagram.com", "facebook": "https://facebook.com",
        "twitter": "https://x.com", "tiktok": "https://tiktok.com", "github": "https://github.com",
        "chatgpt": "https://chatgpt.com", "chat gpt": "https://chatgpt.com", "claude": "https://claude.ai",
        "amazon": "https://amazon.com", "wikipedia": "https://es.wikipedia.org", "uam virtual": "https://uamvirtual.uam.edu.ni",
        "whatsapp web": "https://web.whatsapp.com", "drive": "https://drive.google.com", "google drive": "https://drive.google.com",
    ]

    private static func site(_ target: String) -> String? {
        if let s = sites[target] { return s }
        // "ve a apple.com", "abre uam.edu.ni"
        let compact = target.replacingOccurrences(of: " punto ", with: ".").replacingOccurrences(of: " ", with: "")
        if compact.contains("."), !compact.hasSuffix("."), compact.count > 3 {
            return compact.hasPrefix("http") ? compact : "https://" + compact
        }
        return nil
    }

    private static func searchURL(_ q: String) -> String {
        var query = q
        var base = "https://www.google.com/search?q="
        for (site, url) in [("youtube", "https://www.youtube.com/results?search_query="),
                            ("wikipedia", "https://es.wikipedia.org/w/index.php?search="),
                            ("amazon", "https://www.amazon.com/s?k="),
                            ("imagenes", "https://www.google.com/search?tbm=isch&q=")] {
            for pattern in [" en \(site)", "en \(site) "] where query.contains(pattern) {
                query = query.replacingOccurrences(of: pattern, with: " ")
                base = url
            }
        }
        query = strip(["sobre", "acerca de", "que es", "informacion de"], from: query.trimmingCharacters(in: .whitespaces), onlyLeading: true)
        let encoded = query.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return base + encoded
    }

    private static func verbWords(_ v: Verb) -> [String] {
        switch v {
        case .open: ["abreme", "abrime", "abre", "abrir", "inicia", "iniciar", "lanza", "ejecuta", "arranca",
                     "llevame a", "vete a", "ve a", "entra a", "entra en", "cambia a", "muestrame", "muestra",
                     "pasame a", "trae", "ponme", "abras", "abre", "pon"]
        case .quit: ["cierrame", "cierra", "cerrar", "cierre", "salte de", "sal de", "salir de", "mata", "termina",
                     "finaliza", "quitame", "quita", "fuerza el cierre de", "cierres", "cierra"]
        case .hide: ["ocultame", "oculta", "ocultar", "ocultes", "escondeme", "esconde", "esconder", "minimiza"]
        case .search: ["buscame", "busca", "buscar", "busques", "googlea", "investiga"]
        case .up: ["subele", "sube", "subir", "aumenta", "aumentar", "incrementa", "mas"]
        case .down: ["bajale", "baja", "bajar", "disminuye", "reduce", "reducir", "menos"]
        case .set: ["ponle", "cambia", "ajusta", "deja"]
        case .type: ["escribe", "escribir", "escribeme", "dicta", "teclea", "tipea"]
        }
    }

    private static func verb(_ c: String) -> Verb? {
        let order: [Verb] = [.quit, .hide, .search, .up, .down, .open, .set]
        for v in order where starts(c, verbWords(v)) { return v }
        // El verbo puede no ir al inicio: "puedes cerrar Fotos", "quiero abrir Notas".
        for v in order {
            for w in verbWords(v) where w.count > 3 && c.range(of: "\\b\(w)\\b", options: .regularExpression) != nil { return v }
        }
        return nil
    }

    // MARK: Texto

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quita muletillas y signos; deja palabras en minúsculas sin tildes.
    static func clean(_ s: String) -> String {
        var t = fold(s)
        t = t.replacingOccurrences(of: "[¿?¡!\"“”]|\\.(?=\\s|$)", with: "", options: .regularExpression)
        let fillers = ["por favor", "porfa", "porfavor", "oye", "hey", "zarcillo", "puedes", "podrias", "quiero que",
                       "quiero", "necesito que", "necesito", "me puedes", "ahora", "rapido", "ya", "tambien", "a ver"]
        for f in fillers {
            t = t.replacingOccurrences(of: "\\b\(f)\\b", with: " ", options: .regularExpression)
        }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// Parte en cláusulas por comas, puntos, "y", "luego", "después"…
    static func split(_ s: String) -> [String] {
        let pattern = "\\s*(?:[,;]|\\.(?=\\s|$)|\\by luego\\b|\\by despu[eé]s\\b|\\bluego\\b|\\bdespu[eé]s\\b|\\by tambi[eé]n\\b|\\be\\b|\\by\\b)\\s*"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [s] }
        var out: [String] = []
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            out.append(String(s[last..<r.lowerBound]))
            last = r.upperBound
        }
        out.append(String(s[last...]))
        return out.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func has(_ c: String, _ words: [String]) -> Bool {
        words.contains { w in
            w.hasSuffix(" ") || w.hasPrefix(" ") ? c.contains(w)
                : c.range(of: "\\b\(NSRegularExpression.escapedPattern(for: w))", options: .regularExpression) != nil
        }
    }

    static func starts(_ c: String, _ words: [String]) -> Bool {
        words.contains { c == $0 || c.hasPrefix($0 + " ") }
    }

    /// Quita del inicio las palabras dadas (artículos, "la app"…), las veces que haga falta.
    static func strip(_ words: [String], from c: String, onlyLeading: Bool = true) -> String {
        var t = c
        var changed = true
        while changed {
            changed = false
            for w in words.sorted(by: { $0.count > $1.count }) {
                if t == w { return "" }
                if t.hasPrefix(w + " ") {
                    t = String(t.dropFirst(w.count + 1)).trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        return t
    }

    /// Lo que viene después del verbo, esté donde esté ("puedes cerrar fotos" → "fotos").
    static func after(_ verbs: [String], in c: String) -> String {
        var best: Range<String.Index>?
        for v in verbs {
            if let r = c.range(of: "\\b\(v)\\b", options: .regularExpression),
               best == nil || r.lowerBound < best!.lowerBound || (r.lowerBound == best!.lowerBound && r.upperBound > best!.upperBound) {
                best = r
            }
        }
        guard let best else { return c }
        return String(c[best.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private static let numberWords: [String: Double] = [
        "cero": 0, "cinco": 5, "diez": 10, "quince": 15, "veinte": 20, "veinticinco": 25, "treinta": 30,
        "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
    ]

    static func number(in c: String) -> Double? {
        if let r = c.range(of: "\\d+", options: .regularExpression) { return Double(c[r]) }
        for (w, n) in numberWords where c.range(of: "\\b\(w)\\b", options: .regularExpression) != nil { return n }
        return nil
    }
}
