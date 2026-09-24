import AppKit
import Foundation

// MARK: - Claude (por el CLI de tu suscripción)

/// Habla con Claude a través del programa oficial `claude` que ya tienes en el
/// Mac, con tu propia sesión y tu plan. Zarcillo no ve ni guarda ninguna
/// credencial: solo lanza el programa y lee su respuesta.
enum ClaudeCLI {
    struct Answer {
        var json: [String: Any]
        var tokensIn: Int
        var tokensOut: Int
    }

    enum Failure: Error, LocalizedError {
        case missing, notLoggedIn, failed(String), timeout
        var errorDescription: String? {
            switch self {
            case .missing: "no encontré el programa claude en este Mac"
            case .notLoggedIn: "Claude no tiene la sesión iniciada (ejecuta: claude auth login)"
            case .failed(let m): m
            case .timeout: "Claude tardó demasiado"
            }
        }
    }

    static var path: String? {
        [ "/opt/homebrew/bin/claude", "/usr/local/bin/claude", NSHomeDirectory() + "/.local/bin/claude",
          NSHomeDirectory() + "/.claude/local/claude" ]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Solo la suscripción: si hubiera una clave de API suelta, el CLI cobraría por token.
        env["ANTHROPIC_API_KEY"] = nil
        env["ANTHROPIC_AUTH_TOKEN"] = nil
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["HOME"] = NSHomeDirectory()
        return env
    }

    /// Ejecuta el CLI fuera del hilo principal, con límite de tiempo.
    private static func run(_ args: [String], timeout: TimeInterval) async throws -> Data {
        guard let exe = path else { throw Failure.missing }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.environment = environment()
                p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                p.standardInput = FileHandle.nullDevice
                var timedOut = false
                do { try p.run() } catch { cont.resume(throwing: Failure.failed(error.localizedDescription)); return }
                let killer = DispatchWorkItem { timedOut = true; p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                if timedOut { cont.resume(throwing: Failure.timeout) } else { cont.resume(returning: data) }
            }
        }
    }

    /// ¿Hay una sesión iniciada? Y de qué plan.
    static func status() async -> (ready: Bool, plan: String) {
        guard let data = try? await run(["auth", "status"], timeout: 15),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (false, "") }
        return ((j["loggedIn"] as? Bool) ?? false, (j["subscriptionType"] as? String) ?? "")
    }

    /// Una consulta que devuelve JSON con la forma del esquema.
    static func ask(system: String, prompt: String, schema: String, model: String = "haiku") async throws -> Answer {
        let data = try await run([
            "-p", "--model", model, "--output-format", "json", "--no-session-persistence",
            "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            "--system-prompt", system, "--json-schema", schema, prompt,
        ], timeout: 60)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.failed("respuesta ilegible")
        }
        if (j["is_error"] as? Bool) == true {
            if (j["api_error_status"] as? Int) == 401 { throw Failure.notLoggedIn }
            throw Failure.failed((j["result"] as? String) ?? "error de Claude")
        }
        guard let structured = j["structured_output"] as? [String: Any] else { throw Failure.failed("sin respuesta estructurada") }
        let usage = j["usage"] as? [String: Any]
        return Answer(json: structured, tokensIn: (usage?["input_tokens"] as? Int) ?? 0,
                      tokensOut: (usage?["output_tokens"] as? Int) ?? 0)
    }
}

// MARK: - El cerebro

/// Convierte una orden hablada en acciones. Tres capas, de la más barata a la
/// más cara: el grafo que ya aprendió (gratis y al instante), Claude (varios
/// segundos y tokens de tu plan) y, cuando Claude resuelve algo que se puede
/// repetir, lo guarda como plantilla para no volver a preguntarle.
@MainActor
final class Brain {
    struct Intent: Codable, Identifiable, Equatable {
        var id: String
        /// La orden con huecos: ["abre", "{app}", "y", "luego", "ciérrala"] (normalizada).
        var template: [String]
        var reply: String
        var steps: [BrainStep]
        var uses = 0
        var ok = 0
        var riskyConfirms = 0
        var lastUsed = Date()
        var contexts: [String: Int] = [:]
        var next: [String: Int] = [:]
        /// Un injerto une dos órdenes que haces siempre seguidas.
        var graftOf: [String]? = nil
        var title: String? = nil

        var fixed: Bool { ok >= 2 }
        var trusted: Bool { riskyConfirms >= 2 }
        var slots: [String] { template.compactMap { $0.hasPrefix("{") ? String($0.dropFirst().dropLast()) : nil } }
        var display: String { title ?? template.joined(separator: " ") }
    }

    private struct Saved: Codable {
        var intents: [Intent]
        var stats: BrainStats
        var claudeOn: Bool
    }

    private struct Pending {
        var plan: BrainPlan
        var intent: String?
        var template: [String]?
        var slots: [String: String]
        var reply: String
        var context: String
        var emit: (Event) -> Void
    }

    weak var server: Server?
    private(set) var intents: [Intent] = []
    private(set) var stats = BrainStats()
    private(set) var claudeOn = true
    private(set) var claudeReady = false
    private(set) var claudePlan = ""
    private var pending: [String: Pending] = [:]
    private var last: (id: String, at: Date)?

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zarcillo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("brain.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            intents = s.intents
            stats = s.stats
            claudeOn = s.claudeOn
        }
        Task { await refreshClaude() }
    }

    private func save() {
        try? JSONEncoder().encode(Saved(intents: intents, stats: stats, claudeOn: claudeOn)).write(to: Self.file, options: .atomic)
    }

    func refreshClaude() async {
        let s = await ClaudeCLI.status()
        claudeReady = s.ready
        claudePlan = s.plan
    }

    func info() -> BrainInfo {
        BrainInfo(stats: stats,
                  intents: intents.sorted { $0.uses > $1.uses }.map {
                      BrainIntentInfo(id: $0.id, template: $0.display, uses: $0.uses, fixed: $0.fixed,
                                      trusted: $0.trusted, steps: $0.steps.map(\.label),
                                      lastUsed: $0.lastUsed.timeIntervalSince1970, graft: $0.graftOf)
                  },
                  claudeReady: claudeReady, claudeOn: claudeOn, claudePlan: claudePlan)
    }

    func setClaude(_ on: Bool) { claudeOn = on; save() }

    func forget(_ id: String?) {
        if let id { intents.removeAll { $0.id == id } } else { intents = []; stats = BrainStats() }
        save()
    }

    // MARK: Entrada

    func ask(_ text: String, emit: @escaping (Event) -> Void) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let id = UUID().uuidString
        let context = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        // 1. Lo que ya aprendió.
        let toks = Self.tokens(clean)
        if let (intent, caps) = bestMatch(toks, context: context) {
            let steps = fill(intent.steps, caps)
            let risky = steps.contains(where: \.risky)
            let plan = BrainPlan(id: id, utterance: clean, reply: fillText(intent.reply, caps), steps: steps,
                                 source: "grafo", needsConfirm: risky && !intent.trusted)
            stats.graphHits += 1
            pending[id] = Pending(plan: plan, intent: intent.id, template: nil, slots: caps, reply: plan.reply,
                                  context: context, emit: emit)
            proceed(id)
            return
        }

        // 2. Claude.
        guard claudeOn else {
            emit(.brainResult(id: id, ok: false, reply: "no sé hacer eso todavía, y Claude está apagado", source: "grafo",
                              output: nil, intent: nil))
            return
        }
        emit(.brainThinking(id: id))
        server?.aura.show(.thinking)
        Task {
            do {
                let (plan, template) = try await askClaude(clean, id: id, context: context)
                var caps: [String: String] = [:]
                var tmpl: [String]?
                if let t = template {
                    let pattern = Self.tokens(t, keepSlots: true).map(\.norm)
                    if Self.validPattern(pattern), let c = Self.match(pattern, toks) { tmpl = pattern; caps = c }
                }
                pending[id] = Pending(plan: plan, intent: nil, template: tmpl, slots: caps, reply: plan.reply,
                                      context: context, emit: emit)
                proceed(id)
            } catch {
                await refreshClaude()
                server?.aura.show(.done(false))
                emit(.brainResult(id: id, ok: false, reply: error.localizedDescription, source: "claude", output: nil, intent: nil))
            }
        }
    }

    /// Ejecuta ya, o espera el permiso del usuario si hay pasos con riesgo.
    private func proceed(_ id: String) {
        guard let p = pending[id] else { return }
        if p.plan.needsConfirm {
            server?.aura.show(.confirm)
            p.emit(.brainPlan(p.plan))
        } else { run(id) }
    }

    func confirm(_ id: String, ok: Bool) {
        guard let p = pending[id] else { return }
        if ok {
            run(id, confirmed: true)
        } else {
            pending[id] = nil
            server?.aura.hide()
            p.emit(.brainResult(id: id, ok: false, reply: "cancelado", source: p.plan.source, output: nil, intent: p.intent))
        }
    }

    func feedback(_ intentID: String, good: Bool) {
        guard let i = intents.firstIndex(where: { $0.id == intentID }) else { return }
        // "No era eso": se olvida esa plantilla para que la próxima vez decida Claude.
        if !good { intents.remove(at: i) } else { intents[i].ok += 1 }
        save()
    }

    /// Una sugerencia de un toque: repite lo aprendido tal cual.
    func runIntent(_ intentID: String, emit: @escaping (Event) -> Void) {
        guard let intent = intents.first(where: { $0.id == intentID }), intent.slots.isEmpty else { return }
        let id = UUID().uuidString
        let plan = BrainPlan(id: id, utterance: intent.display, reply: intent.reply, steps: intent.steps, source: "grafo",
                             needsConfirm: intent.steps.contains(where: \.risky) && !intent.trusted)
        stats.graphHits += 1
        pending[id] = Pending(plan: plan, intent: intent.id, template: nil, slots: [:], reply: intent.reply,
                              context: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "", emit: emit)
        proceed(id)
    }

    // MARK: Ejecutar y aprender

    private func run(_ id: String, confirmed: Bool = false) {
        guard let p = pending.removeValue(forKey: id) else { return }
        server?.aura.show(.thinking)
        Task {
            let output = await execute(p.plan.steps)
            let failed = output.failures > 0
            var intentID = p.intent

            if !failed {
                if let existing = p.intent, let i = intents.firstIndex(where: { $0.id == existing }) {
                    intents[i].uses += 1
                    intents[i].ok += 1
                    intents[i].lastUsed = Date()
                    intents[i].contexts[p.context, default: 0] += 1
                    if confirmed && p.plan.steps.contains(where: \.risky) { intents[i].riskyConfirms += 1 }
                    for part in intents[i].graftOf ?? [] {
                        if let k = intents.firstIndex(where: { $0.id == part }) { intents[k].uses += 1; intents[k].lastUsed = Date() }
                    }
                } else if p.plan.source == "claude" {
                    intentID = learn(p)
                }
                if let prev = last, let now = intentID, prev.id != now, Date().timeIntervalSince(prev.at) < 600,
                   let pi = intents.firstIndex(where: { $0.id == prev.id }) {
                    intents[pi].next[now, default: 0] += 1
                    graft(prev.id, now)
                }
                if let now = intentID { last = (now, Date()) }
            }
            save()

            server?.aura.show(.done(!failed))
            var reply = p.reply
            if let text = output.text, !text.isEmpty { reply = reply.replacingOccurrences(of: "{salida}", with: text) }
            reply = reply.replacingOccurrences(of: "{salida}", with: "")
            if failed { reply = output.notes.first ?? "no pude completarlo" }
            p.emit(.brainResult(id: id, ok: !failed, reply: reply, source: p.plan.source,
                                output: output.text, intent: intentID))
            p.emit(.brainSuggest(suggestions(after: intentID, context: p.context)))
            server?.hud.showMessage(String(reply.prefix(48)), symbol: failed ? "exclamationmark.circle" : "sparkles")
        }
    }

    /// Guarda lo que Claude resolvió como plantilla (con huecos si se pudo
    /// generalizar) para no volver a preguntarle.
    private func learn(_ p: Pending) -> String? {
        var pattern = p.template ?? Self.tokens(p.plan.utterance).map(\.norm)
        var steps = p.plan.steps
        var reply = p.plan.reply

        if p.template != nil {
            // Cada hueco tiene que aparecer en algún paso: si no, la plantilla no sirve.
            var used = Set<String>()
            steps = steps.map { step in
                var s = step
                for (slot, value) in p.slots {
                    if let t = s.text, t.range(of: value, options: .caseInsensitive) != nil {
                        s.text = t.replacingOccurrences(of: value, with: "{\(slot)}", options: .caseInsensitive)
                        used.insert(slot)
                    }
                    if let n = s.number, let v = Double(value), n == v, s.numberSlot == nil {
                        s.numberSlot = slot
                        used.insert(slot)
                    }
                }
                return s
            }
            for (slot, value) in p.slots {
                // "la calculadora" → "{app}": el artículo no viaja al hueco.
                let escaped = NSRegularExpression.escapedPattern(for: value)
                reply = reply.replacingOccurrences(of: "(?:\\b(?:el|la|los|las|un|una|mi|tu)\\s+)?" + escaped, with: "{\(slot)}",
                                                   options: [.regularExpression, .caseInsensitive])
            }
            if used != Set(p.slots.keys) {
                pattern = Self.tokens(p.plan.utterance).map(\.norm)   // no generaliza: solo esta orden exacta
                steps = p.plan.steps
                reply = p.plan.reply
            }
        }
        guard Self.validPattern(pattern) else { return nil }
        if let dup = intents.firstIndex(where: { $0.template == pattern }) {
            intents[dup].steps = steps
            intents[dup].ok += 1
            intents[dup].uses += 1
            return intents[dup].id
        }
        let intent = Intent(id: UUID().uuidString, template: pattern, reply: reply, steps: steps, uses: 1, ok: 1,
                            contexts: [p.context: 1])
        intents.append(intent)
        return intent.id
    }

    /// Dos órdenes sin huecos que haces seguidas tres veces se unen en una planta con dos ramas.
    private func graft(_ a: String, _ b: String) {
        let id = "graft:\(a)+\(b)"
        guard !intents.contains(where: { $0.id == id }),
              let x = intents.first(where: { $0.id == a }), let y = intents.first(where: { $0.id == b }),
              x.slots.isEmpty, y.slots.isEmpty, x.graftOf == nil, y.graftOf == nil,
              (x.next[b] ?? 0) >= 3 else { return }
        var g = Intent(id: id, template: [], reply: "Listo: \(x.display) y \(y.display)", steps: x.steps + y.steps)
        g.ok = 1
        g.graftOf = [a, b]
        g.title = "\(x.display) → \(y.display)"
        intents.append(g)
        server?.hud.showMessage("injerto nuevo", symbol: "leaf.arrow.triangle.circlepath")
    }

    /// Una orden que el usuario enseñó haciéndola: queda fija desde el primer momento.
    func addTaught(name: String, steps: [BrainStep]) {
        var pattern = Self.tokens(name).map(\.norm)
        if !Self.validPattern(pattern) { pattern = name.lowercased().split(separator: " ").map(String.init) }
        var i = Intent(id: "taught-\(UUID().uuidString.prefix(8))", template: pattern, reply: "Listo: \(name)", steps: steps)
        i.ok = 2
        intents.append(i)
        save()
    }

    /// Ficha de planta a partir de las etiquetas de Vision. Si Claude no responde, queda una ficha mínima.
    func herbCard(id: String, labels: [String]) async -> HerbCard {
        var card = HerbCard(id: id, name: labels.first?.capitalized ?? "Planta", scientific: "", water: "", light: "", tip: "", labels: labels)
        guard claudeOn, !labels.isEmpty else { return card }
        let schema = """
        {"type":"object","properties":{"name":{"type":"string"},"scientific":{"type":"string"},"water":{"type":"string"},\
        "light":{"type":"string"},"tip":{"type":"string"}},"required":["name","scientific","water","light","tip"]}
        """
        let system = "Eres un botánico. Recibes etiquetas que un modelo de visión puso a la foto de una planta y devuelves una ficha breve en español: nombre común más probable, nombre científico (vacío si no estás seguro), riego, luz y un consejo de cuidado (cada uno una frase corta). Si las etiquetas no parecen una planta, pon en name 'No parece una planta'. No inventes certeza: si es ambiguo, dilo en el consejo."
        if let a = try? await ClaudeCLI.ask(system: system, prompt: labels.joined(separator: ", "), schema: schema) {
            stats.claudeCalls += 1; stats.tokensIn += a.tokensIn; stats.tokensOut += a.tokensOut
            card.name = (a.json["name"] as? String) ?? card.name
            card.scientific = (a.json["scientific"] as? String) ?? ""
            card.water = (a.json["water"] as? String) ?? ""
            card.light = (a.json["light"] as? String) ?? ""
            card.tip = (a.json["tip"] as? String) ?? ""
            save()
        }
        return card
    }

    /// Lo que sueles pedir después de esto (y lo que sueles pedir con esta app al frente).
    private func suggestions(after intentID: String?, context: String) -> [BrainSuggestion] {
        var scored: [String: Int] = [:]
        if let id = intentID, let i = intents.first(where: { $0.id == id }) {
            for (next, n) in i.next where n >= 2 { scored[next, default: 0] += n * 2 }
        }
        for i in intents where i.slots.isEmpty && (i.contexts[context] ?? 0) >= 3 { scored[i.id, default: 0] += i.contexts[context] ?? 0 }
        if let id = intentID { scored[id] = nil }
        return scored.sorted { $0.value > $1.value }.prefix(3).compactMap { entry in
            guard let i = intents.first(where: { $0.id == entry.key }), i.slots.isEmpty else { return nil }
            return BrainSuggestion(id: i.id, label: i.display)
        }
    }

    // MARK: Coincidencia

    private func bestMatch(_ toks: [(orig: String, norm: String)], context: String) -> (Intent, [String: String])? {
        var best: (Intent, [String: String], Int)?
        for i in intents where i.ok >= 1 && i.graftOf == nil {
            guard let caps = Self.match(i.template, toks) else { continue }
            let score = i.ok * 2 + (i.contexts[context] ?? 0) - i.slots.count
            if best == nil || score > best!.2 { best = (i, caps, score) }
        }
        return best.map { ($0.0, $0.1) }
    }

    private func fillText(_ s: String, _ caps: [String: String]) -> String {
        caps.reduce(s) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    private func fill(_ steps: [BrainStep], _ caps: [String: String]) -> [BrainStep] {
        steps.map { step in
            var s = step
            if let t = s.text { s.text = fillText(t, caps) }
            if let slot = s.numberSlot, let v = caps[slot], let n = Double(v) { s.number = n }
            return s
        }
    }

    // MARK: Texto

    private static let fillers: Set<String> = ["oye", "hey", "zarcillo", "porfa", "porfavor", "pues", "ok", "okay"]

    static func tokens(_ s: String, keepSlots: Bool = false) -> [(orig: String, norm: String)] {
        let cleaned = s.replacingOccurrences(of: "[¿?¡!\",;:()]", with: " ", options: .regularExpression)
        var out: [(String, String)] = []
        for w in cleaned.split(whereSeparator: \.isWhitespace) {
            let orig = String(w).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !orig.isEmpty else { continue }
            if keepSlots, orig.hasPrefix("{"), orig.hasSuffix("}") { out.append((orig, orig.lowercased())); continue }
            let norm = orig.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
            if fillers.contains(norm) { continue }
            if norm == "favor", out.last?.1 == "por" { out.removeLast(); continue }
            out.append((orig, norm))
        }
        return out
    }

    /// Una plantilla útil tiene palabras propias y pocos huecos; si no, coincidiría con cualquier cosa.
    static func validPattern(_ p: [String]) -> Bool {
        let slots = p.filter { $0.hasPrefix("{") }.count
        let words = p.count - slots
        return words >= 1 && slots <= 3 && (slots == 0 || words >= 2)
    }

    private static let numberWords: [String: Int] = [
        "cero": 0, "uno": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
        "nueve": 9, "diez": 10, "once": 11, "doce": 12, "quince": 15, "veinte": 20, "treinta": 30, "cuarenta": 40,
        "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
    ]

    private static let articles: Set<String> = ["el", "la", "los", "las", "un", "una", "mi", "mis", "tu"]

    private static func number(_ norm: String) -> Int? {
        let digits = norm.trimmingCharacters(in: CharacterSet(charactersIn: "%"))
        return Int(digits) ?? numberWords[norm]
    }

    /// ¿La orden encaja en la plantilla? Devuelve lo que cayó en cada hueco.
    static func match(_ pattern: [String], _ toks: [(orig: String, norm: String)]) -> [String: String]? {
        func go(_ pi: Int, _ ti: Int, _ caps: [String: String]) -> [String: String]? {
            if pi == pattern.count { return ti == toks.count ? caps : nil }
            let p = pattern[pi]
            guard p.hasPrefix("{"), p.hasSuffix("}") else {
                guard ti < toks.count, toks[ti].norm == p else { return nil }
                return go(pi + 1, ti + 1, caps)
            }
            let name = String(p.dropFirst().dropLast())
            let numeric = name.hasPrefix("n")
            for len in 1...3 where ti + len <= toks.count {
                let slice = toks[ti..<(ti + len)]
                var value = slice.map(\.orig).joined(separator: " ")
                // "la calculadora" → "calculadora": el artículo no es parte del nombre.
                if !numeric, len > 1, articles.contains(slice.first!.norm) {
                    value = slice.dropFirst().map(\.orig).joined(separator: " ")
                }
                if numeric {
                    guard len == 1, let n = number(slice.first!.norm) else { continue }
                    value = String(n)
                }
                var next = caps
                next[name] = value
                if let r = go(pi + 1, ti + len, next) { return r }
            }
            return nil
        }
        return go(0, 0, [:])
    }

    // MARK: Claude

    private static let schema = """
    {"type":"object","properties":{"understood":{"type":"boolean"},"reply":{"type":"string"},\
    "template":{"type":["string","null"]},"steps":{"type":"array","items":{"type":"object","properties":{\
    "kind":{"type":"string","enum":["openApp","quitApp","hideApp","quitAll","openURL","openFolder","volume","volumeBy",\
    "brightness","brightnessBy","media","shortcut","menu","typeText","gesture","power","wait","applescript","shell"]},\
    "text":{"type":"string"},"number":{"type":"number"},"key":{"type":"string"},"mods":{"type":"integer"},\
    "path":{"type":"array","items":{"type":"string"}}},"required":["kind"]}}},"required":["understood","reply","steps","template"]}
    """

    private static let system = """
    Eres el cerebro de Zarcillo, un control remoto del Mac de su dueño. Conviertes una orden hablada en español en un plan de \
    pasos que se ejecutan en el Mac. Responde SOLO con el JSON del esquema.

    Pasos disponibles (kind y datos):
    - openApp / quitApp / hideApp: text = nombre de la app; si el usuario dijo el nombre, úsalo tal cual (el Mac lo resuelve).
    - quitAll: cierra todas las apps.
    - openURL: text = dirección o dominio. openFolder: text = descargas, documentos, escritorio, aplicaciones, imágenes, música, películas o inicio.
    - volume / brightness: number 0-100. volumeBy / brightnessBy: number entre -100 y 100 (relativo).
    - media: key = playPause, next o previous.
    - shortcut: atajo en la app al frente. key = una letra o space, return, escape, tab, delete, left, right, up, down; mods = suma de ⌘=1, ⇧=2, ⌥=4, ⌃=8.
    - menu: pulsa un elemento del menú de la app al frente. path = ["Archivo","Guardar"], como se ve en su barra de menús; text = nombre de otra app si no es la del frente.
    - typeText: escribe text donde está el cursor.
    - gesture: key = spaceLeft, spaceRight, missionControl, appWindows, spotlight.
    - power: key = lock, sleep, displayOff.
    - wait: number = segundos.
    - applescript: text = código AppleScript. shell: text = comando de zsh. Úsalos SOLO si ningún paso simple sirve; el usuario verá el código y tendrá que aprobarlo.

    Reglas:
    - Prefiere pasos específicos antes que shell o applescript. Código corto y seguro; nunca borres archivos, envíes mensajes ni gastes dinero salvo que la orden lo pida de forma explícita.
    - Si la orden es una pregunta sobre el Mac (batería, espacio en disco, red, hora…), usa shell e incluye {salida} en reply donde debe ir el resultado del comando.
    - reply: una frase corta en español que diga qué se hizo (o por qué no se pudo). Si no la entiendes o no se puede hacer en un Mac, understood = false y steps vacío.
    - template (siempre, aunque sea null): la orden generalizada, para reutilizarla sin volver a consultarte. Cópiala tal cual pero cambia por huecos {nombre} los datos que podrían ser otros (una app, un número, un sitio, un texto); los huecos numéricos empiezan con n ({n}). Esos datos deben aparecer en los pasos exactamente como los dijo el usuario (en openApp, text = la palabra que dijo). Ejemplos:
      orden "abre notas y luego ciérrala" → template "abre {app} y luego ciérrala"
      orden "pon el volumen al 30" → template "pon el volumen al {n}"
      orden "abre spotify y pon el volumen a 20" → template "abre {app} y pon el volumen a {n}"
      orden "busca recetas de gallo pinto en youtube" → template "busca {consulta} en youtube"
      Si la orden no cambia con otros datos (por ejemplo "cuánta batería me queda"), o es demasiado particular, template = null.
    """

    private func askClaude(_ text: String, id: String, context: String) async throws -> (BrainPlan, String?) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
        let scenes = server?.routines.map(\.name) ?? []
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let ctx: [String: Any] = ["orden": text, "app_al_frente": front, "apps_abiertas": apps, "escenas": scenes,
                                  "hora": DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)]
        let prompt = String(data: (try? JSONSerialization.data(withJSONObject: ctx)) ?? Data(), encoding: .utf8) ?? text
        let answer = try await ClaudeCLI.ask(system: Self.system, prompt: prompt, schema: Self.schema)
        stats.claudeCalls += 1
        stats.tokensIn += answer.tokensIn
        stats.tokensOut += answer.tokensOut

        let j = answer.json
        Self.log(["orden": text, "respuesta": j])
        let understood = (j["understood"] as? Bool) ?? false
        let reply = (j["reply"] as? String) ?? ""
        let raw = (j["steps"] as? [[String: Any]]) ?? []
        let steps: [BrainStep] = raw.compactMap { d in
            guard let kind = d["kind"] as? String else { return nil }
            return BrainStep(kind: kind, text: d["text"] as? String, number: (d["number"] as? NSNumber)?.doubleValue,
                             key: d["key"] as? String, mods: (d["mods"] as? NSNumber)?.intValue, path: d["path"] as? [String])
        }
        guard understood, !steps.isEmpty else { throw ClaudeCLI.Failure.failed(reply.isEmpty ? "no lo entendí" : reply) }
        // El riesgo lo decide el código, no el modelo.
        let plan = BrainPlan(id: id, utterance: text, reply: reply, steps: steps, source: "claude",
                             needsConfirm: steps.contains(where: \.risky))
        return (plan, j["template"] as? String)
    }

    /// Las últimas respuestas de Claude, para ver qué está aprendiendo el cerebro. Solo local.
    private static func log(_ entry: [String: Any]) {
        let url = file.deletingLastPathComponent().appendingPathComponent("claude-log.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: entry), let line = String(data: data, encoding: .utf8) else { return }
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append(line)
        try? lines.suffix(30).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Ejecutor

    struct Outcome {
        var failures = 0
        var notes: [String] = []
        var text: String?
    }

    private func execute(_ steps: [BrainStep]) async -> Outcome {
        var out = Outcome()
        let hud = server?.hud
        for step in steps {
            switch step.kind {
            case "openApp":
                if AppFinder.open(step.text ?? "") == nil { out.failures += 1; out.notes.append("no encontré la app “\(step.text ?? "")”") }
            case "quitApp":
                if AppFinder.quit(step.text ?? "") == nil { out.failures += 1; out.notes.append("“\(step.text ?? "")” no está abierta") }
            case "hideApp":
                if AppFinder.hide(step.text ?? "") == nil { out.failures += 1; out.notes.append("“\(step.text ?? "")” no está abierta") }
            case "quitAll":
                AppFinder.quitAll()
            case "openURL":
                var s = (step.text ?? "").trimmingCharacters(in: .whitespaces)
                if !s.contains("://") { s = "https://" + s }
                if let url = URL(string: s) { NSWorkspace.shared.open(url) } else { out.failures += 1 }
            case "openFolder":
                if AppFinder.openFolder(step.text ?? "") == nil { out.failures += 1; out.notes.append("no sé qué carpeta es “\(step.text ?? "")”") }
            case "volume":
                let v = min(1, max(0, (step.number ?? 0) / 100)); Volume.set(v); hud?.showLevel(.volume, v)
            case "volumeBy":
                let v = min(1, max(0, (Volume.get() ?? 0.5) + (step.number ?? 0) / 100)); Volume.set(v); hud?.showLevel(.volume, v)
            case "brightness":
                let v = min(1, max(0, (step.number ?? 0) / 100)); Brightness.set(v); hud?.showLevel(.brightness, v)
            case "brightnessBy":
                let v = min(1, max(0, (Brightness.get() ?? 0.5) + (step.number ?? 0) / 100)); Brightness.set(v); hud?.showLevel(.brightness, v)
            case "media":
                if let k = MediaKey(rawValue: step.key ?? "") { Input.media(k) } else { out.failures += 1 }
            case "shortcut":
                let m = step.mods ?? 0
                let s = Shortcut(title: "", key: (step.key ?? "").lowercased(), command: m & DeckAction.cmd != 0,
                                 shift: m & DeckAction.shift != 0, option: m & DeckAction.option != 0, control: m & DeckAction.control != 0)
                if !Input.shortcut(s) { out.failures += 1; out.notes.append("no pude enviar el atajo") }
            case "menu":
                var pid = server?.deck.pid ?? 0
                if let name = step.text, !name.isEmpty, let app = AppFinder.running(name) { pid = app.processIdentifier }
                let path = step.path ?? []
                let ok = await Task.detached { MenuScanner.press(pid: pid, path: path) }.value
                if !ok { out.failures += 1; out.notes.append("no encontré “\(path.joined(separator: " › "))” en el menú") }
            case "typeText":
                Typing.type(step.text ?? "")
            case "gesture":
                if let g = DesktopGesture(rawValue: step.key ?? "") { Input.gesture(g) } else { out.failures += 1 }
            case "power":
                if let p = PowerAction(rawValue: step.key ?? "") { Power.perform(p) } else { out.failures += 1 }
            case "wait":
                try? await Task.sleep(for: .seconds(min(30, max(0, step.number ?? 0))))
            case "applescript":
                var error: NSDictionary?
                let result = NSAppleScript(source: step.text ?? "")?.executeAndReturnError(&error)
                if let error { out.failures += 1; out.notes.append((error["NSAppleScriptErrorMessage"] as? String) ?? "el AppleScript falló") }
                else if let s = result?.stringValue, !s.isEmpty { out.text = s }
            case "shell":
                let r = await Self.shell(step.text ?? "")
                if r.status != 0 { out.failures += 1; out.notes.append(r.text.isEmpty ? "el comando falló" : String(r.text.prefix(120))) }
                if !r.text.isEmpty { out.text = r.text }
            default:
                out.failures += 1
                out.notes.append("no sé hacer “\(step.kind)”")
            }
            try? await Task.sleep(for: .milliseconds(300))
            if out.failures > 0 { break }
        }
        return out
    }

    /// Un comando de terminal, con 20 s de límite y la salida recortada.
    private static func shell(_ command: String) async -> (status: Int32, text: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-c", command]
                p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: (1, error.localizedDescription)); return }
                let killer = DispatchWorkItem { p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                let text = String(decoding: data.prefix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (p.terminationStatus, text))
            }
        }
    }
}
