import AppIntents
import Foundation
import Network

// Acciones para Siri, la app Atajos y el botón de Acción. Corren sin abrir la
// app: buscan el último Mac conectado, entran con el código guardado, mandan
// la orden y cierran.

enum QuickLink {
    struct Failure: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }

    static func send(_ commands: [Command]) async throws {
        guard let mac = UserDefaults.standard.string(forKey: "lastMac"), let code = Keychain.get(mac) else {
            throw Failure(message: "Abre Zarcillo y conéctate a tu Mac una vez.")
        }
        let endpoint = try await find(mac)
        let channel = Channel(NWConnection(to: endpoint, using: .zarcillo(passcode: code)))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            channel.onState = { state in
                switch state {
                case .ready:
                    for c in commands { channel.send(c) }
                    // Deja salir los paquetes antes de cerrar.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        channel.cancel()
                        once.run { cont.resume() }
                    }
                case .failed, .waiting:
                    channel.cancel()
                    once.run { cont.resume(throwing: Failure(message: "No pude conectar con \(mac).")) }
                default: break
                }
            }
            channel.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
                channel.cancel()
                once.run { cont.resume(throwing: Failure(message: "\(mac) no respondió.")) }
            }
        }
    }

    private static func find(_ mac: String) async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { cont in
            let once = Once()
            let browser = NWBrowser(for: .bonjour(type: ZarcilloService.type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    if case let .service(name, _, _, _) = r.endpoint, name == mac {
                        browser.cancel()
                        once.run { cont.resume(returning: r.endpoint) }
                    }
                }
            }
            browser.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                browser.cancel()
                once.run { cont.resume(throwing: Failure(message: "No encuentro \(mac) en esta red.")) }
            }
        }
    }

    /// Una continuación se reanuda una sola vez aunque lleguen varios eventos.
    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }
}

struct PlayPauseMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar o reanudar la música del Mac"
    func perform() async throws -> some IntentResult {
        try await QuickLink.send([.media(.playPause)])
        return .result()
    }
}

struct NextTrackMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Siguiente canción en el Mac"
    func perform() async throws -> some IntentResult {
        try await QuickLink.send([.media(.next)])
        return .result()
    }
}

struct LockMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Bloquear el Mac"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QuickLink.send([.power(.lock)])
        return .result(dialog: "Mac bloqueado.")
    }
}

struct SleepMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Suspender el Mac"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QuickLink.send([.power(.sleep)])
        return .result(dialog: "Mac suspendido.")
    }
}

struct SetMacVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Cambiar el volumen del Mac"

    @Parameter(title: "Volumen", inclusiveRange: (0, 100))
    var level: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Poner el volumen del Mac al \(\.$level) %")
    }

    func perform() async throws -> some IntentResult {
        try await QuickLink.send([.setLevel(kind: .volume, value: Double(level) / 100)])
        return .result()
    }
}

// MARK: - Escenas como parámetro

struct RoutineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Escena"
    static let defaultQuery = RoutineQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static func all() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: "routines"),
              let list = try? JSONDecoder().decode([Routine].self, from: data) else { return Routine.defaults }
        return list
    }
}

struct RoutineQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RoutineEntity] {
        RoutineEntity.all().filter { identifiers.contains($0.id) }.map { RoutineEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        RoutineEntity.all().map { RoutineEntity(id: $0.id, name: $0.name) }
    }
}

struct RunRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Ejecutar una escena en el Mac"

    @Parameter(title: "Escena")
    var routine: RoutineEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Ejecutar \(\.$routine) en el Mac")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let r = RoutineEntity.all().first(where: { $0.id == routine.id }) else {
            throw QuickLink.Failure(message: "Esa escena ya no existe.")
        }
        try await QuickLink.send([.runRoutine(r)])
        return .result(dialog: "Listo: \(r.name).")
    }
}

struct ZarcilloShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayPauseMacIntent(),
                    phrases: ["Pausa la música del Mac con \(.applicationName)",
                              "Pausar el Mac con \(.applicationName)"],
                    shortTitle: "Pausar música", systemImageName: "playpause.fill")
        AppShortcut(intent: NextTrackMacIntent(),
                    phrases: ["Siguiente canción con \(.applicationName)"],
                    shortTitle: "Siguiente canción", systemImageName: "forward.fill")
        AppShortcut(intent: LockMacIntent(),
                    phrases: ["Bloquea el Mac con \(.applicationName)",
                              "Bloquear mi Mac con \(.applicationName)"],
                    shortTitle: "Bloquear el Mac", systemImageName: "lock.fill")
        AppShortcut(intent: SleepMacIntent(),
                    phrases: ["Suspende el Mac con \(.applicationName)"],
                    shortTitle: "Suspender el Mac", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: RunRoutineIntent(),
                    phrases: ["Ejecuta una escena con \(.applicationName)",
                              "Activa \(\.$routine) con \(.applicationName)"],
                    shortTitle: "Ejecutar escena", systemImageName: "sparkles")
    }
}
