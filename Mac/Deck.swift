import AppKit
import ApplicationServices

/// Lee y pulsa la barra de menús de cualquier app con la API de Accesibilidad.
/// Así los botones se adaptan solos a la app que estés usando, en su propio
/// idioma y con sus propios atajos, sin tener una lista escrita a mano.
enum MenuScanner {
    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func title(_ el: AXUIElement) -> String {
        ((attr(el, kAXTitleAttribute) as? String) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func menuBar(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = attr(app, kAXMenuBarAttribute) else { return nil }
        return (bar as! AXUIElement)
    }

    /// Los menús que no aportan botones útiles.
    private static let skipMenus: Set<String> = ["window", "ventana", "help", "ayuda", "ver ventana"]
    private static let skipItems: [String] = ["services", "servicios", "open recent", "abrir reciente", "recent", "recientes"]

    static func scan(pid: pid_t) -> [MenuGroup] {
        guard let bar = menuBar(pid) else { return [] }
        var groups: [MenuGroup] = []
        var budget = 450
        let deadline = Date().addingTimeInterval(1.8)
        for (i, top) in children(bar).enumerated() {
            let name = title(top)
            // El primero es el menú de Apple, igual en todas las apps.
            if i == 0 || name.isEmpty || skipMenus.contains(name.lowercased()) { continue }
            guard let menu = children(top).first else { continue }
            var actions: [DeckAction] = []
            collect(menu, path: [name], into: &actions, depth: 0, budget: &budget, deadline: deadline)
            if !actions.isEmpty { groups.append(MenuGroup(title: name, actions: actions)) }
            if budget <= 0 || Date() > deadline { break }
        }
        return groups
    }

    private static func collect(_ menu: AXUIElement, path: [String], into out: inout [DeckAction],
                                depth: Int, budget: inout Int, deadline: Date) {
        var count = 0
        for item in children(menu) {
            if budget <= 0 || Date() > deadline { return }
            let name = title(item)
            if name.isEmpty { continue }                       // separadores
            let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if skipItems.contains(where: { folded.hasPrefix($0) }) { continue }

            if let sub = children(item).first {                // un submenú: se aplana
                if depth < 2 { collect(sub, path: path + [name], into: &out, depth: depth + 1, budget: &budget, deadline: deadline) }
                continue
            }
            count += 1
            if count > 40 { return }                           // una lista larga no sirve de botones
            budget -= 1

            let enabled = (attr(item, kAXEnabledAttribute) as? Bool) ?? true
            let mark = (attr(item, "AXMenuItemMarkChar") as? String) ?? ""
            var key: String?
            var mods = 0
            var glyphs = ""
            if let raw = attr(item, "AXMenuItemCmdChar") as? String, let k = keyName(raw) {
                let m = (attr(item, "AXMenuItemCmdModifiers") as? Int) ?? 0
                // Bits del menú: 1 mayúsculas, 2 opción, 4 control, 8 = sin ⌘.
                mods = (m & 8 == 0 ? DeckAction.cmd : 0) | (m & 1 != 0 ? DeckAction.shift : 0)
                    | (m & 2 != 0 ? DeckAction.option : 0) | (m & 4 != 0 ? DeckAction.control : 0)
                key = k
                glyphs = DeckAction.glyphs(key: k, mods: mods)
            }
            let full = path + [name]
            out.append(DeckAction(id: "menu:" + full.joined(separator: ">"),
                                  title: full.dropFirst().joined(separator: " › "),
                                  symbol: DeckSymbols.guess(title: name), glyphs: glyphs,
                                  path: full, key: key, mods: mods, enabled: enabled, marked: !mark.isEmpty))
        }
    }

    /// El carácter de atajo de un menú, como nombre de tecla que entiende `Input`.
    private static func keyName(_ raw: String) -> String? {
        guard let scalar = raw.unicodeScalars.first, raw.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x20: return "space"
        case 0x0D, 0x03: return "return"
        case 0x09: return "tab"
        case 0x1B: return "escape"
        case 0x7F, 0x08: return "delete"
        case 0xF700: return "up"
        case 0xF701: return "down"
        case 0xF702: return "left"
        case 0xF703: return "right"
        case 0xF704...0xF71F: return "f\(Int(scalar.value) - 0xF703)"
        case 0xF720...0xF8FF, 0..<0x20: return nil
        default: return raw.lowercased()
        }
    }

    /// Pulsa un elemento del menú por su ruta, sin abrir el menú.
    static func press(pid: pid_t, path: [String]) -> Bool {
        guard var container = menuBar(pid), !path.isEmpty else { return false }
        for (i, name) in path.enumerated() {
            guard let item = children(container).first(where: { title($0) == name }) else { return false }
            if i == path.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            guard let next = children(item).first else { return false }
            container = next
        }
        return false
    }
}

/// Decide qué botones mostrar para la app que está al frente: lo esencial (el
/// perfil curado si lo hay; si no, lo que su propio menú ofrece), lo que más
/// usas y todos sus menús. Lo comparten el iPhone y la Touch Bar.
@MainActor
final class DeckEngine {
    private struct Use: Codable {
        var action: DeckAction
        var count: Int
    }

    private(set) var current: AppActions?
    private(set) var pid: pid_t = 0
    var onChange: ((AppActions) -> Void)?
    /// Cuando una acción no se pudo ejecutar (la app no expone su menú y no tiene atajo).
    var onFail: ((DeckAction) -> Void)?

    private var cache: [pid_t: (at: Date, menus: [MenuGroup])] = [:]
    private var scanning: Set<pid_t> = []
    private var usage: [String: [String: Use]] = {
        guard let d = UserDefaults.standard.data(forKey: "deckUsage"),
              let u = try? JSONDecoder().decode([String: [String: Use]].self, from: d) else { return [:] }
        return u
    }()

    /// Los atajos que casi toda app tiene, en orden de importancia.
    private static let universal: [(String, Int)] = [
        ("n", DeckAction.cmd), ("o", DeckAction.cmd), ("s", DeckAction.cmd), ("w", DeckAction.cmd),
        ("z", DeckAction.cmd), ("z", DeckAction.cmd | DeckAction.shift), ("f", DeckAction.cmd),
        ("c", DeckAction.cmd), ("v", DeckAction.cmd), ("p", DeckAction.cmd), ("t", DeckAction.cmd),
        ("r", DeckAction.cmd),
    ]

    /// Se llama al cambiar de app y cuando el iPhone lo pide. `force` vuelve a
    /// leer los menús aunque la lectura sea reciente (para ver qué está activo).
    func refresh(force: Bool = false) {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        pid = app.processIdentifier
        let name = app.localizedName ?? id
        let cached = cache[pid]
        publish(appID: id, name: name, menus: cached?.menus ?? [], scanned: cached != nil)

        let age = cached.map { Date().timeIntervalSince($0.at) } ?? .infinity
        guard Input.isTrusted, !scanning.contains(pid), force ? age > 1.5 : age > 20 else { return }
        scanning.insert(pid)
        let p = pid
        DispatchQueue.global(qos: .userInitiated).async {
            let menus = MenuScanner.scan(pid: p)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanning.remove(p)
                    self.cache[p] = (Date(), menus)
                    if self.pid == p { self.publish(appID: id, name: name, menus: menus, scanned: true) }
                }
            }
        }
    }

    private func publish(appID: String, name: String, menus: [MenuGroup], scanned: Bool) {
        let all = menus.flatMap(\.actions)
        let curated = AppContext.for(appID)
        var quick: [DeckAction]

        if let buttons = curated?.buttons, !buttons.isEmpty {
            // El perfil curado manda; de la lectura de los menús toma la ruta (para
            // pulsarlo sin teclas) y si ahora mismo está activo.
            quick = buttons.map { b in
                let s = b.shortcut
                var mods = 0
                if s.command { mods |= DeckAction.cmd }
                if s.shift { mods |= DeckAction.shift }
                if s.option { mods |= DeckAction.option }
                if s.control { mods |= DeckAction.control }
                var a = DeckAction(id: "key:\(b.title)", title: b.title, symbol: b.symbol,
                                   glyphs: DeckAction.glyphs(key: s.key, mods: mods), key: s.key, mods: mods)
                if let hit = all.first(where: { $0.key == s.key && $0.mods == mods }) {
                    a.path = hit.path
                    a.enabled = hit.enabled
                    a.marked = hit.marked
                }
                return a
            }
        } else {
            // Sin perfil: lo esencial que esta app realmente tenga en su menú.
            quick = []
            for (key, mods) in Self.universal {
                guard quick.count < 8,
                      let hit = all.first(where: { $0.key == key && $0.mods == mods && $0.enabled }),
                      !quick.contains(where: { $0.id == hit.id }) else { continue }
                var a = hit
                a.title = hit.path?.last ?? hit.title
                quick.append(a)
            }
        }

        let quickIDs = Set(quick.map(\.id))
        let frequent = (usage[appID] ?? [:]).values
            .filter { $0.count >= 2 && !quickIDs.contains($0.action.id) }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { use -> DeckAction in
                // Con el estado de ahora, si el menú ya se leyó.
                all.first(where: { $0.id == use.action.id }) ?? use.action
            }

        let next = AppActions(appID: appID, appName: curated?.name ?? name, quick: quick,
                              frequent: Array(frequent), menus: menus, scanned: scanned)
        if next != current {
            current = next
            onChange?(next)
        }
    }

    /// Pulsa una acción: por su ruta de menú y, si esa app no la deja, con su atajo.
    func press(_ action: DeckAction) {
        if let appID = current?.appID { record(action, appID) }
        let p = pid
        DispatchQueue.global(qos: .userInitiated).async {
            var done = false
            if let path = action.path { done = MenuScanner.press(pid: p, path: path) }
            if !done, let shortcut = action.shortcut {
                DispatchQueue.main.async { _ = Input.shortcut(shortcut) }
            } else if !done {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.onFail?(action) } }
            }
        }
        // Tras la acción cambia lo que está activo (deshacer, pegar…) y lo más usado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh(force: true) }
    }

    private func record(_ action: DeckAction, _ appID: String) {
        var bucket = usage[appID] ?? [:]
        var use = bucket[action.id] ?? Use(action: action, count: 0)
        use.count += 1
        use.action = action
        bucket[action.id] = use
        // Solo se recuerdan las 40 más usadas por app.
        if bucket.count > 40 {
            for k in bucket.sorted(by: { $0.value.count < $1.value.count }).prefix(bucket.count - 40).map(\.key) { bucket[k] = nil }
        }
        usage[appID] = bucket
        UserDefaults.standard.set(try? JSONEncoder().encode(usage), forKey: "deckUsage")
    }
}
