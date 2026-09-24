import SwiftUI
import Translation

/// Clases transcritas: el iPhone escucha, el Mac muestra subtítulos y guarda
/// la clase con los momentos marcados. Si la clase es en inglés, también la
/// traduce al español, todo en el propio iPhone.
struct ClassesPage: View {
    @EnvironmentObject private var remote: Remote
    @StateObject private var speech = LiveSpeech()
    @AppStorage("class.title") private var title = ""
    @AppStorage("class.english") private var english = false
    @State private var lines: [String] = []
    @State private var marks = 0
    @State private var translation: TranslationSession.Configuration?
    @State private var queue = SegmentQueue()

    /// Frases cerradas que esperan su traducción.
    final class SegmentQueue {
        var continuation: AsyncStream<String>.Continuation?
        lazy var stream: AsyncStream<String> = AsyncStream { self.continuation = $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                TextField("materia (Ingeniería de Software II…)", text: $title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tone.ink)
                    .padding(.horizontal, 16).frame(height: 52)
                    .background(Capsule().fill(Tone.key))
                    .disabled(speech.running)
                    .padding(.top, 48)

                HStack(spacing: Space.s) {
                    chip("en español", on: !english) { english = false }
                    chip("en inglés → español", on: english) { english = true }
                }
                .disabled(speech.running)

                orb

                if speech.running {
                    Button {
                        Detents.shared.press()
                        mark()
                    } label: {
                        Label(marks == 0 ? "marcar este momento" : "marcado \(marks) \(marks == 1 ? "vez" : "veces")",
                              systemImage: "star.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Tone.ember)
                            .symbolEffect(.bounce, value: marks)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Capsule().fill(Tone.key))
                    }
                    .buttonStyle(PressScale())
                    Text("también puedes tocar la perilla para marcar")
                        .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.4))
                }

                if speech.denied {
                    Text("Dale a Zarcillo permiso de micrófono y de reconocimiento de voz en Ajustes.")
                        .font(.system(size: 13)).foregroundStyle(Tone.ember).multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !speech.partial.isEmpty {
                        Text(speech.partial).font(.system(size: 16, weight: .medium)).foregroundStyle(Tone.ink)
                    }
                    ForEach(Array(lines.suffix(8).reversed().enumerated()), id: \.offset) { _, l in
                        Text(l).font(.system(size: 14)).foregroundStyle(Tone.ink.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.m)
        }
        .scrollIndicators(.hidden)
        .translationTask(translation) { session in
            for await text in queue.stream {
                let translated = (try? await session.translate(text))?.targetText
                remote.send(.transcript(text: text, translation: translated, final: true))
            }
        }
        .onChange(of: remote.knobMarks) { _, _ in if speech.running { mark() } }
        .onDisappear { if speech.running { stopClass() } }
    }

    /// El botón grande: grabar o terminar, con el nivel de la voz latiendo.
    private var orb: some View {
        Button {
            Detents.shared.press()
            speech.running ? stopClass() : startClass()
        } label: {
            ZStack {
                Circle().fill(Tone.ember.opacity(speech.running ? 0.3 : 0))
                    .frame(width: 180 + speech.level * 60, height: 180 + speech.level * 60)
                    .blur(radius: 24)
                Circle().fill(speech.running ? Tone.ember : Tone.key)
                    .frame(width: 130, height: 130)
                    .overlay(Circle().stroke(Tone.stroke, lineWidth: speech.running ? 0 : 1))
                VStack(spacing: 4) {
                    Image(systemName: speech.running ? "stop.fill" : "waveform")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: speech.running)
                    Text(speech.running ? "terminar" : "empezar").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(speech.running ? Tone.onEmber : Tone.ink.opacity(0.8))
            }
            .frame(height: 200)
            .animation(.easeOut(duration: 0.12), value: speech.level)
        }
        .buttonStyle(PressScale())
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(text).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Tone.onEmber : Tone.ink.opacity(0.7))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Capsule().fill(on ? Tone.ember : Tone.key))
        }
        .buttonStyle(PressScale())
    }

    private func startClass() {
        lines = []
        marks = 0
        remote.transcribing = true
        remote.send(.transcriptStart(title: title.isEmpty ? "clase" : title, language: english ? "en" : "es"))
        if english {
            queue = SegmentQueue()
            translation = TranslationSession.Configuration(source: Locale.Language(identifier: "en"),
                                                           target: Locale.Language(identifier: "es"))
        } else {
            translation = nil
        }
        speech.onPartial = { text in remote.send(.transcript(text: text, translation: nil, final: false)) }
        speech.onFinal = { text in
            lines.append(text)
            if english {
                queue.continuation?.yield(text)
            } else {
                remote.send(.transcript(text: text, translation: nil, final: true))
            }
        }
        Task { await speech.start(locale: english ? "en-US" : "es-MX") }
    }

    private func stopClass() {
        speech.stop()
        remote.transcribing = false
        // Un respiro para que la última traducción alcance a salir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            queue.continuation?.finish()
            remote.send(.transcriptEnd)
        }
    }

    private func mark() {
        marks += 1
        remote.send(.transcriptMark)
    }
}
