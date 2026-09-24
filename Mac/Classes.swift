import AppKit
import SwiftUI

/// Clases transcritas en vivo: el iPhone escucha, el Mac muestra subtítulos
/// grandes abajo de la pantalla y guarda la clase completa al terminar.
@MainActor
final class LiveClass: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let at: Date
        let text: String
        let translation: String?
        var marked = false
    }

    @Published private(set) var active = false
    @Published private(set) var partial = ""
    @Published private(set) var partialTranslation: String?
    @Published private(set) var lines: [Line] = []
    @Published private(set) var marks = 0

    private var title = "clase"
    private var started = Date()
    private var panel: NSPanel?

    func start(title: String) {
        self.title = title.isEmpty ? "clase" : title
        started = Date()
        lines = []
        partial = ""
        partialTranslation = nil
        active = true
        show()
    }

    func update(text: String, translation: String?, final: Bool) {
        if !active { start(title: title) }
        if final {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(Line(at: Date(), text: text, translation: translation))
            }
            partial = ""
            partialTranslation = nil
        } else {
            partial = text
            partialTranslation = translation
        }
    }

    /// Marca el momento: la última frase queda destacada en el documento.
    func mark() {
        if lines.isEmpty, !partial.isEmpty {
            lines.append(Line(at: Date(), text: partial, translation: partialTranslation, marked: true))
        } else if !lines.isEmpty {
            lines[lines.count - 1].marked = true
        }
        marks += 1
    }

    /// Termina y guarda la clase en Documentos › Zarcillo › Clases como texto
    /// con horas y los momentos marcados.
    func end() -> URL? {
        guard active else { return nil }
        if !partial.isEmpty { update(text: partial, translation: partialTranslation, final: true) }
        active = false
        panel?.orderOut(nil)

        let day = DateFormatter(), hour = DateFormatter(), stamp = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        hour.dateFormat = "HH.mm"
        stamp.dateFormat = "HH:mm:ss"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Zarcillo/Clases/\(day.string(from: started))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(title) \(hour.string(from: started)).md")

        var md = "# \(title)\n\n\(day.string(from: started)) · \(hour.string(from: started).replacingOccurrences(of: ".", with: ":"))\n\n"
        let marked = lines.filter(\.marked)
        if !marked.isEmpty {
            md += "## Momentos marcados\n\n" + marked.map { "- **\(stamp.string(from: $0.at))** \($0.text)" }.joined(separator: "\n") + "\n\n"
        }
        md += "## Transcripción\n\n"
        for l in lines {
            md += "**\(stamp.string(from: l.at))**\(l.marked ? " ⭐" : "") \(l.text)\n"
            if let t = l.translation, !t.isEmpty { md += "> \(t)\n" }
            md += "\n"
        }
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func show() {
        guard let s = NSScreen.main else { return }
        let size = NSSize(width: min(960, s.frame.width - 80), height: 190)
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.visibleFrame.minY + 30,
                           width: size.width, height: size.height)
        if panel == nil {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let host = fixedHost(CaptionsView(live: self))
            host.frame = NSRect(origin: .zero, size: size)
            host.autoresizingMask = [.width, .height]
            p.contentView = host
            panel = p
        }
        if panel?.frame != frame { panel?.setFrame(frame, display: false) }
        panel?.orderFrontRegardless()
    }
}

/// Subtítulos: lo último dicho en grande, la traducción debajo en el acento.
private struct CaptionsView: View {
    @ObservedObject var live: LiveClass

    var body: some View {
        let current = live.partial.isEmpty ? (live.lines.last?.text ?? "escuchando…") : live.partial
        let translation = live.partial.isEmpty ? live.lines.last?.translation : live.partialTranslation
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("clase en vivo").font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                if live.marks > 0 {
                    Label("\(live.marks)", systemImage: "star.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MacTone.ember)
                        .symbolEffect(.bounce, value: live.marks)
                }
            }
            Text(current)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.opacity)
            if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(MacTone.ember)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(MacTone.ember.opacity(0.3), lineWidth: 1))
        .shadow(color: MacTone.ember.opacity(0.25), radius: 18)
        .animation(.easeOut(duration: 0.2), value: current)
    }
}
