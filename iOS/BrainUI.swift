import SwiftUI

/// La tarjeta que muestra lo que el cerebro hace con tu orden: pensando, el plan
/// (con el código exacto si lo hay, para que lo apruebes), y el resultado.
struct BrainOverlay: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        Group {
            switch remote.brain {
            case .idle:
                EmptyView()
            case .thinking:
                card {
                    HStack(spacing: 12) {
                        icon("sparkles", spinning: true)
                        Text("pensando…").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Tone.ink)
                    }
                }
            case .confirm(let plan):
                card { confirm(plan) }
            case .done(let d):
                card { done(d) }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: remote.brain)
    }

    // MARK: Piezas

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial).environment(\.colorScheme, .dark))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tone.body.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Tone.ember.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .padding(.horizontal, Space.m)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func icon(_ name: String, spinning: Bool = false) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .bold)).foregroundStyle(Tone.onEmber)
            .symbolEffect(.variableColor.iterative, isActive: spinning)
            .frame(width: 40, height: 40).background(Circle().fill(Tone.ember))
    }

    private func confirm(_ plan: BrainPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                icon("exclamationmark.shield.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿lo hago?").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                    Text("“\(plan.utterance)”").font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55)).lineLimit(2)
                }
            }
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 4) {
                    Label(step.label, systemImage: step.risky ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(step.risky ? Tone.ember : Tone.ink.opacity(0.75))
                    if step.risky, let code = step.text {
                        Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tone.ink.opacity(0.85))
                            .lineLimit(8).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tone.recess))
                    }
                }
            }
            HStack(spacing: Space.s) {
                button("cancelar", filled: false) { remote.brainConfirm(plan, ok: false) }
                button("ejecutar", filled: true) { remote.brainConfirm(plan, ok: true) }
            }
        }
    }

    private func done(_ d: BrainDone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                icon(d.ok ? "checkmark" : "xmark")
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.reply).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Tone.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(d.source == "grafo" ? "lo recordaba · sin gastar Claude" : "Claude")
                        .font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1)
                        .foregroundStyle(d.source == "grafo" ? Tone.leaf : Tone.ink.opacity(0.45))
                }
                Spacer(minLength: 0)
                Button { remote.dismissBrain() } label: {
                    GlyphView(.close, size: 15).foregroundStyle(Tone.ink.opacity(0.4))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("cerrar")
            }
            if let out = d.output, !out.isEmpty, !d.reply.contains(out.prefix(20)) {
                Text(out).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tone.ink.opacity(0.8))
                    .lineLimit(8).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tone.recess))
            }
            if let intent = d.intent, d.ok {
                Button("no era eso") { remote.brainWrong(intent) }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.55))
            }
            if !remote.suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(remote.suggestions) { s in
                            Button {
                                Detents.shared.press()
                                remote.send(.brainRun(intent: s.id))
                            } label: {
                                Label(s.label, systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Tone.onEmber).padding(.horizontal, 12).frame(height: 32)
                                    .background(Capsule().fill(Tone.ember))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func button(_ title: String, filled: Bool, _ run: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            run()
        } label: {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? Tone.onEmber : Tone.ink.opacity(0.8))
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Capsule().fill(filled ? Tone.ember : Tone.recess))
        }
        .buttonStyle(PressScale())
    }
}

/// Cerebro: si Claude está listo, cuánto ha ahorrado el grafo y todo lo que
/// aprendió (para borrarlo si algo quedó mal).
struct BrainPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var text = ""
    @State private var lesson = ""

    var body: some View {
        StageScroll(spacing: Space.m) {
            let info = remote.brainInfo
            VStack(spacing: 6) {
                Image(systemName: "brain.head.profile").font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(info?.claudeReady == true ? Tone.ember : Tone.ink.opacity(0.4))
                Text(status(info)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                TextField("escribe una orden…", text: $text, axis: .vertical)
                    .font(.system(size: 15)).foregroundStyle(Tone.ink).lineLimit(1...3)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Tone.onEmber)
                        .frame(width: 46, height: 46).background(Circle().fill(Tone.ember))
                }
                .buttonStyle(PressScale())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            teachCard

            ToggleCard(title: "usar Claude", detail: "para lo que el grafo todavía no sabe",
                       isOn: Binding(get: { info?.claudeOn ?? true }, set: { remote.send(.brainSettings(claudeOn: $0)) }))

            if let s = info?.stats {
                HStack(spacing: Space.s) {
                    stat("\(s.claudeCalls)", "consultas a Claude")
                    stat("\(s.graphHits)", "resueltas sin Claude")
                    stat(s.tokensSaved >= 1000 ? "\(s.tokensSaved / 1000)k" : "\(s.tokensSaved)", "tokens ahorrados")
                }
            }

            if let intents = info?.intents, !intents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("lo que aprendió").font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1.2)
                        .foregroundStyle(Tone.ink.opacity(0.45)).padding(.leading, 4)
                    ForEach(intents) { i in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(i.template).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ink)
                                Text(i.steps.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.5)).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 4) {
                                if i.fixed {
                                    Text("fijo").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.onEmber)
                                        .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(Tone.leaf))
                                }
                                Text("\(i.uses) uso\(i.uses == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.45))
                            }
                            Button { remote.send(.brainForget(intent: i.id)) } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.4))
                            }
                        }
                        .padding(Space.s)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
                    }
                    Button("olvidar todo") { remote.send(.brainForget(intent: nil)) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.5)).frame(height: 44)
                        .frame(maxWidth: .infinity)
                }
            }

            Hint("Las órdenes que Claude resuelve y se pueden repetir se guardan aquí, solo en tu Mac, y la próxima vez se resuelven sin gastar tu plan. Lo que lleva AppleScript o comandos de terminal siempre te pide permiso.")
        }
        .task { remote.send(.brainInfo) }
    }

    /// Enseñar por demostración: el Mac mira lo que haces y lo guarda como orden.
    @ViewBuilder
    private var teachCard: some View {
        if remote.teaching {
            VStack(spacing: Space.s) {
                HStack(spacing: 10) {
                    Circle().fill(Color(red: 0.95, green: 0.3, blue: 0.3)).frame(width: 12, height: 12)
                        .symbolEffect(.pulse)
                        .opacity(0.9)
                    Text("mirando el Mac · \(remote.teachSteps) paso\(remote.teachSteps == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                    Spacer(minLength: 0)
                }
                Text("Abre las apps y usa los atajos (⌘ o ⌃) que quieras enseñar. No anoto lo que escribes.")
                    .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s) {
                    teachButton("cancelar", filled: false) { remote.teachCancel() }
                    teachButton("terminé", filled: true) { remote.teachStop() }
                }
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(red: 0.95, green: 0.3, blue: 0.3).opacity(0.5), lineWidth: 1))
        } else {
            HStack(spacing: 8) {
                TextField("enseñar una orden nueva…", text: $lesson)
                    .font(.system(size: 15)).foregroundStyle(Tone.ink)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key))
                    .submitLabel(.go)
                    .onSubmit(startLesson)
                Button(action: startLesson) {
                    Image(systemName: "record.circle").font(.system(size: 18, weight: .bold)).foregroundStyle(Tone.onEmber)
                        .frame(width: 46, height: 46).background(Circle().fill(Tone.ember))
                }
                .buttonStyle(PressScale())
                .disabled(lesson.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("empezar a enseñar")
            }
        }
    }

    private func startLesson() {
        remote.teach(lesson)
        lesson = ""
    }

    private func teachButton(_ title: String, filled: Bool, _ run: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            run()
        } label: {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? Tone.onEmber : Tone.ink.opacity(0.8))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Capsule().fill(filled ? Tone.ember : Tone.recess))
        }
        .buttonStyle(PressScale())
    }

    private func status(_ info: BrainInfo?) -> String {
        guard let info else { return "consultando al Mac…" }
        if !info.claudeReady { return "Claude sin sesión\nen el Mac: claude auth login" }
        return "Claude listo" + (info.claudePlan.isEmpty ? "" : " · plan \(info.claudePlan)")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Tone.ember)
            Text(label).font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.5)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""
        remote.ask(t)
    }
}
