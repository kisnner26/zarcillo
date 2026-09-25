import FoundationModels
import SwiftUI

/// Órdenes en lenguaje natural: "abre Figma, baja el volumen a 30 y pon el
/// modo clase". Se escucha y se entiende en el propio iPhone (el modelo de
/// Apple Intelligence si está disponible, si no un intérprete de reglas) y se
/// convierte en una escena de un solo uso.
@MainActor
final class VoiceCommander: ObservableObject {
    enum Phase: Equatable { case idle, listening, thinking, done([String]), failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var heard = ""
    let speech = LiveSpeech()
    private weak var remote: Remote?
    private var text = ""

    func attach(_ remote: Remote) { self.remote = remote }

    func begin() {
        text = ""
        heard = ""
        phase = .listening
        speech.onPartial = { [weak self] t in self?.heard = (self?.text ?? "") + t }
        speech.onFinal = { [weak self] t in
            guard let self else { return }
            self.text += (self.text.isEmpty ? "" : " ") + t
            self.heard = self.text
        }
        // Nombres de apps y escenas como pistas: el reconocedor acierta "Xcode" o "modo clase".
        speech.hints = (remote?.apps.map(\.name) ?? []) + (remote?.routines.map(\.name) ?? [])
            + ["cierra", "abre", "oculta", "volumen", "brillo", "pestaña", "Safari", "Chrome", "Spotify", "YouTube"]
        Task { await speech.start(locale: "es-MX") }
    }

    func end() {
        // Un respiro para que entre la última palabra antes de cortar.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            finish()
        }
    }

    private func finish() {
        speech.stop()
        let order = heard.trimmingCharacters(in: .whitespaces)
        guard !order.isEmpty, let remote else {
            phase = .idle
            return
        }
        // Enseñar por demostración, sin pasar por Claude.
        let low = order.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        if remote.teaching {
            if ["listo", "termine", "ya termine", "eso es todo", "ya", "guardalo", "guarda"].contains(low) {
                remote.teachStop(); phase = .idle; return
            }
            if low.hasPrefix("cancela") { remote.teachCancel(); phase = .idle; return }
        }
        for prefix in ["aprende esto ", "aprende a ", "ensenate ", "aprende "] where low.hasPrefix(prefix) {
            let name = String(low.dropFirst(prefix.count))
            if !name.isEmpty { remote.teach(name); phase = .idle; return }
        }
        phase = .thinking
        Task {
            // Lo básico lo resuelve la gramática al instante. Lo demás va al cerebro del Mac:
            // primero lo que ya aprendió y, si no, Claude.
            let grammar = VoiceGrammar(apps: remote.apps, routines: remote.routines).parse(order)
            if !(grammar.understood && !grammar.steps.isEmpty), case .connected = remote.phase {
                remote.ask(order)
                phase = .idle
                return
            }
            let steps = await plan(order, remote: remote)
            if steps.isEmpty {
                phase = .failed("no entendí “\(order)”. Prueba: “cierra Fotos”, “sube el volumen a 60”, “busca … en YouTube”")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                remote.send(.runRoutine(Routine(name: "voz", symbol: "waveform", steps: steps)))
                phase = .done(steps.map(\.label))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            try? await Task.sleep(for: .seconds(2.5))
            if case .listening = phase { return }
            phase = .idle
        }
    }

    // MARK: Entender

    private func plan(_ order: String, remote: Remote) async -> [RoutineStep] {
        // Primero la gramática: rápida, exacta y sin sorpresas ("cierra" nunca es "abre").
        let grammar = VoiceGrammar(apps: remote.apps, routines: remote.routines).parse(order)
        if grammar.understood, !grammar.steps.isEmpty { return grammar.steps }
        // Lo que no entendió, al modelo del iPhone si lo hay.
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable,
           let steps = try? await planWithModel(order, remote: remote), !steps.isEmpty {
            return steps
        }
        return grammar.steps
    }

    @available(iOS 26.0, *)
    private func planWithModel(_ order: String, remote: Remote) async throws -> [RoutineStep] {
        let apps = remote.apps.map(\.name).joined(separator: ", ")
        let scenes = remote.routines.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
        Conviertes órdenes habladas en español para controlar un Mac en una lista de pasos, en el orden dicho.
        Reglas:
        - "cierra", "cerrar", "sal de", "quita" una app = quitApp. Nunca uses openApp para cerrar.
        - "abre", "pon", "ve a", "cambia a" una app = openApp. Una página web (youtube, gmail, algo.com) = openURL.
        - "oculta", "esconde" = hideApp. "cierra todo" = quitAllApps.
        - "sube"/"baja" el volumen o el brillo sin número = volumeUp/volumeDown/brightnessUp/brightnessDown.
          Con número ("a 40", "al 40") = volume o brightness con level.
        - "busca X" = search con target X. "escribe X" = typeText con target X exacto.
        - pestañas y ventanas: newTab, closeTab, newWindow, closeWindow, minimize, fullScreen.
        - copy, paste, undo, save, screenshot, lock, sleep, displayOff, missionControl, spotlight.
        - si el usuario nombra una escena, scene con su nombre.
        Apps del Dock: \(apps). Escenas: \(scenes).
        El target de una app es su nombre tal como lo dijo el usuario.
        """)
        let response = try await session.respond(to: order, generating: VoicePlan.self)
        return response.content.steps.flatMap { steps(from: $0, remote: remote) }
    }

    @available(iOS 26.0, *)
    private func steps(from s: VoicePlan.Step, remote: Remote) -> [RoutineStep] {
        if s.action == .scene {
            // Una escena se expande en sus propios pasos.
            guard let name = s.target,
                  let r = remote.routines.first(where: { fold($0.name).contains(fold(name)) || fold(name).contains(fold($0.name)) })
            else { return [] }
            return r.steps
        }
        return step(from: s, remote: remote).map { [$0] } ?? []
    }

    @available(iOS 26.0, *)
    private func step(from s: VoicePlan.Step, remote: Remote) -> RoutineStep? {
        func key(_ k: String, shift: Bool = false, ctrl: Bool = false, _ title: String) -> RoutineStep {
            .shortcut(Shortcut(title: title, key: k, command: true, shift: shift, control: ctrl))
        }
        let target = s.target?.trimmingCharacters(in: .whitespaces) ?? ""
        switch s.action {
        case .openApp:
            guard !target.isEmpty else { return nil }
            if let app = match(target, in: remote.apps) { return .openApp(id: app.id, name: app.name) }
            return .openAppNamed(target)
        case .quitApp: return target.isEmpty ? nil : .quitApp(match(target, in: remote.apps)?.name ?? target)
        case .hideApp: return target.isEmpty ? nil : .hideApp(match(target, in: remote.apps)?.name ?? target)
        case .quitAllApps: return .quitAllApps
        case .volume: return .volume(Double(min(100, max(0, s.level ?? 50))) / 100)
        case .volumeUp: return .volumeBy(Double(s.level ?? 15) / 100)
        case .volumeDown: return .volumeBy(-Double(s.level ?? 15) / 100)
        case .mute: return .volume(0)
        case .brightness: return .brightness(Double(min(100, max(0, s.level ?? 50))) / 100)
        case .brightnessUp: return .brightnessBy(Double(s.level ?? 15) / 100)
        case .brightnessDown: return .brightnessBy(-Double(s.level ?? 15) / 100)
        case .playPause: return .media(.playPause)
        case .nextTrack: return .media(.next)
        case .previousTrack: return .media(.previous)
        case .lock: return .power(.lock)
        case .sleep: return .power(.sleep)
        case .displayOff: return .power(.displayOff)
        case .missionControl: return .gesture(.missionControl)
        case .spotlight: return .gesture(.spotlight)
        case .openURL:
            guard !target.isEmpty else { return nil }
            return .openURL(target.contains("://") ? target : "https://" + target.replacingOccurrences(of: " ", with: ""))
        case .search:
            guard !target.isEmpty else { return nil }
            return .openURL("https://www.google.com/search?q=" + (target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target))
        case .typeText: return target.isEmpty ? nil : .typeText(target)
        case .newTab: return key("t", "nueva pestaña")
        case .closeTab: return key("w", "cerrar pestaña")
        case .newWindow: return key("n", "nueva ventana")
        case .closeWindow: return key("w", "cerrar ventana")
        case .minimize: return key("m", "minimizar")
        case .fullScreen: return key("f", ctrl: true, "pantalla completa")
        case .copy: return key("c", "copiar")
        case .paste: return key("v", "pegar")
        case .undo: return key("z", "deshacer")
        case .save: return key("s", "guardar")
        case .screenshot: return key("3", shift: true, "captura de pantalla")
        case .openFolder: return target.isEmpty ? nil : .openFolder(target)
        case .scene: return nil
        }
    }

    private func match(_ name: String, in apps: [AppTile]) -> AppTile? {
        let n = fold(name)
        return apps.first { fold($0.name) == n } ?? apps.first { fold($0.name).contains(n) || n.contains(fold($0.name)) }
    }

    private func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

@available(iOS 26.0, *)
@Generable
struct VoicePlan {
    @Generable
    enum Action {
        case openApp, quitApp, hideApp, quitAllApps
        case volume, volumeUp, volumeDown, mute, brightness, brightnessUp, brightnessDown
        case playPause, nextTrack, previousTrack
        case lock, sleep, displayOff, missionControl, spotlight
        case openURL, search, typeText, openFolder
        case newTab, closeTab, newWindow, closeWindow, minimize, fullScreen
        case copy, paste, undo, save, screenshot
        case scene
    }

    @Generable
    struct Step {
        @Guide(description: "Qué hacer en el Mac")
        var action: Action
        @Guide(description: "Nombre de la app, escena, dirección web, texto a buscar o a escribir, o carpeta, si aplica")
        var target: String?
        @Guide(description: "Nivel de 0 a 100 para volumen o brillo; para subir o bajar, cuánto")
        var level: Int?
    }

    @Guide(description: "Los pasos en el orden en que se dijeron")
    var steps: [Step]
}

/// Lo que se ve mientras hablas: lo escuchado y, al soltar, los pasos.
struct VoiceOverlay: View {
    @ObservedObject var voice: VoiceCommander

    var body: some View {
        Group {
            switch voice.phase {
            case .idle:
                EmptyView()
            case .listening:
                card(symbol: "waveform", title: voice.heard.isEmpty ? "te escucho…" : voice.heard, lines: [])
            case .thinking:
                card(symbol: "sparkles", title: "entendiendo…", lines: [])
            case .done(let steps):
                card(symbol: "checkmark", title: "listo", lines: steps)
            case .failed(let why):
                card(symbol: "questionmark", title: why, lines: [])
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: voice.phase)
    }

    private func card(symbol: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Tone.onEmber)
                    .symbolEffect(.variableColor.iterative, isActive: voice.phase == .listening)
                    .frame(width: 40, height: 40).background(Circle().fill(Tone.ember))
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tone.ink).lineLimit(3)
            }
            ForEach(lines, id: \.self) { l in
                Label(l, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Tone.ink.opacity(0.75))
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial).environment(\.colorScheme, .dark))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tone.body.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Tone.ember.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.horizontal, Space.m)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
