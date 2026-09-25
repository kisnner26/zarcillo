import SwiftUI
import UIKit

// MARK: - Diario de intrusos

/// Cada vez que el guardián salta: cuándo, por qué y la foto de la cámara del Mac.
/// Se guarda en el iPhone (JSON + JPEG) y sobrevive a cerrar la app.
@MainActor
final class IntruderLog: ObservableObject {
    static let shared = IntruderLog()

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var reason: String
        var date: Date
        var hasPhoto = false
    }

    @Published private(set) var entries: [Entry] = []
    private let dir: URL

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Intrusos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("diario.json")),
           let e = try? JSONDecoder().decode([Entry].self, from: d) { entries = e }
    }

    /// La foto llega unos segundos después del aviso: si es del mismo aviso, se le suma.
    func record(_ reason: String, photo: UIImage?) {
        if let photo, let i = entries.firstIndex(where: { $0.reason == reason && Date().timeIntervalSince($0.date) < 30 }) {
            save(photo, entries[i].id)
            entries[i].hasPhoto = true
        } else {
            var e = Entry(reason: reason, date: Date())
            if let photo { save(photo, e.id); e.hasPhoto = true }
            entries.insert(e, at: 0)
            if entries.count > 60 { entries.removeLast(entries.count - 60) }
        }
        persist()
    }

    func photo(_ e: Entry) -> UIImage? {
        e.hasPhoto ? UIImage(contentsOfFile: dir.appendingPathComponent("\(e.id).jpg").path) : nil
    }

    func clear() {
        for e in entries { try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(e.id).jpg")) }
        entries = []
        persist()
    }

    private func save(_ img: UIImage, _ id: UUID) {
        try? img.jpegData(compressionQuality: 0.8)?.write(to: dir.appendingPathComponent("\(id).jpg"))
    }

    private func persist() {
        try? JSONEncoder().encode(entries).write(to: dir.appendingPathComponent("diario.json"))
    }
}

// MARK: - Escudo

/// Toda la seguridad del Mac de un vistazo: el escudo de enredadera, cada
/// protección con su interruptor, el botón de pánico y el diario de intrusos.
struct ShieldPage: View {
    @EnvironmentObject private var remote: Remote
    @ObservedObject private var log = IntruderLog.shared
    @State private var open: IntruderLog.Entry?

    private var active: Int { [remote.guardianOn, remote.nearOn, remote.privacyOn].filter { $0 }.count }

    var body: some View {
        StageScroll(spacing: Space.l) {
            VStack(spacing: Space.s) {
                VineShield(level: active)
                    .frame(width: 170, height: 196)
                Text(active == 0 ? "sin protección" : active == 3 ? "totalmente protegido" : "\(active) de 3 protecciones")
                    .font(Typo.title(20)).foregroundStyle(Tone.ink)
                    .contentTransition(.numericText())
                Text(remote.nearLocked ? "el Mac está bloqueado porque te alejaste" : "tu Mac, vigilado desde el iPhone")
                    .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.55))
            }
            .animation(.spring(duration: 0.6, bounce: 0.3), value: active)

            VStack(spacing: Space.s) {
                SectionLabel(text: "protecciones")
                row("guardián", "si alguien toca tu Mac, suena y le toma una foto", "lock.shield",
                    on: remote.guardianOn) { remote.setGuardian($0) }
                row("cercanía", "se bloquea cuando te alejas con el iPhone", "wave.3.right",
                    on: remote.nearOn) { remote.setNear($0, threshold: remote.nearThreshold) }
                row("privacidad", "filtro antiespía en la pantalla", "eye.slash",
                    on: remote.privacyOn) { remote.setPrivacy($0) }
            }

            VStack(spacing: Space.s) {
                SectionLabel(text: "emergencia")
                PanicHold {
                    remote.send(.setLevel(kind: .volume, value: 0))
                    remote.send(.power(.lock))
                    remote.flash("Mac silenciado y bloqueado")
                }
            }

            VStack(spacing: Space.s) {
                SectionLabel(text: "diario de intrusos")
                if log.entries.isEmpty {
                    Text("Nadie ha tocado tu Mac mientras el guardián vigilaba.")
                        .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, Space.m).glass(20)
                } else {
                    ForEach(log.entries.prefix(20)) { e in entry(e) }
                    Button("borrar el diario") { withAnimation { log.clear() } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.5))
                        .frame(height: 44)
                }
            }
        }
        .sheet(item: $open) { e in IntruderSheet(entry: e) }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, on: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17))
                .foregroundStyle(on ? Tone.ember : Tone.ink.opacity(0.6))
                .frame(width: 40, height: 40).glass(14, tint: on ? Tone.ember : .clear)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.prefix(1).uppercased() + title.dropFirst()).font(Typo.title(16)).foregroundStyle(Tone.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            LeafSwitch(isOn: Binding(get: { on }, set: { v in
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                set(v)
            }))
            .onTapGesture { withAnimation(.spring(duration: 0.35, bounce: 0.35)) { set(!on) } }
        }
        .padding(12)
        .glass(20)
    }

    private func entry(_ e: IntruderLog.Entry) -> some View {
        Button {
            Haptic.tap()
            open = e
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let img = log.photo(e) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Image(systemName: "exclamationmark.shield").font(.system(size: 18)).foregroundStyle(Tone.ember)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .glass(14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.reason.prefix(1).uppercased() + e.reason.dropFirst()).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tone.ink).lineLimit(1)
                    Text(e.date.formatted(.relative(presentation: .named))).font(.system(size: 12))
                        .foregroundStyle(Tone.ink.opacity(0.5))
                }
                Spacer(minLength: 0)
                Text(e.date.formatted(date: .omitted, time: .shortened)).font(Typo.catalog(11)).foregroundStyle(Tone.ink.opacity(0.4))
            }
            .padding(10)
            .glass(20)
        }
        .buttonStyle(PressScale())
    }
}

/// Un escudo dibujado con enredaderas: una rama por cada protección encendida,
/// con sus hojas. Late suave cuando hay al menos una.
struct VineShield: View {
    let level: Int
    @State private var beat = false

    var body: some View {
        ZStack {
            ShieldOutline().fill(Tone.ember.opacity(level > 0 ? 0.10 : 0.03))
            ShieldOutline().stroke(level > 0 ? Tone.ember.opacity(0.8) : Tone.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // Tres ramas: izquierda, derecha y el centro.
            ForEach(0..<3, id: \.self) { i in
                ShieldVine(side: i)
                    .trim(from: 0, to: i < level ? 1 : 0)
                    .stroke(Tone.leaf, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .animation(.easeInOut(duration: 0.9).delay(Double(i) * 0.12), value: level)
                ForEach(0..<4, id: \.self) { k in
                    let p = ShieldVine.leafSpot(side: i, k: k)
                    LeafShape().fill(Tone.leaf)
                        .frame(width: 10, height: 17)
                        .rotationEffect(.degrees(p.angle))
                        .position(x: p.point.x, y: p.point.y)
                        .scaleEffect(i < level ? 1 : 0.01)
                        .opacity(i < level ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.5).delay(0.5 + Double(k) * 0.08 + Double(i) * 0.12), value: level)
                }
            }
            Image(systemName: level == 3 ? "checkmark" : "leaf.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(level > 0 ? Tone.ember : Tone.ink.opacity(0.35))
                .contentTransition(.symbolEffect(.replace))
                .offset(y: -6)
        }
        .frame(width: 170, height: 196)
        .scaleEffect(beat && level > 0 ? 1.03 : 1)
        .shadow(color: Tone.ember.opacity(level > 0 ? 0.35 : 0), radius: 18)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { beat = true } }
    }
}

private struct ShieldOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY + 4))
        p.addCurve(to: CGPoint(x: r.maxX - 6, y: r.minY + r.height * 0.18),
                   control1: CGPoint(x: r.midX + r.width * 0.2, y: r.minY + r.height * 0.1),
                   control2: CGPoint(x: r.maxX - 20, y: r.minY + r.height * 0.14))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY - 4),
                   control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6),
                   control2: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY - r.height * 0.12))
        p.addCurve(to: CGPoint(x: r.minX + 6, y: r.minY + r.height * 0.18),
                   control1: CGPoint(x: r.midX - r.width * 0.2, y: r.maxY - r.height * 0.12),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.6))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + 4),
                   control1: CGPoint(x: r.minX + 20, y: r.minY + r.height * 0.14),
                   control2: CGPoint(x: r.midX - r.width * 0.2, y: r.minY + r.height * 0.1))
        return p
    }
}

/// Una rama del escudo, del pie hacia arriba. Tamaño fijo 170×196.
private struct ShieldVine: Shape {
    let side: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        let (a, c1, c2, b) = Self.curve(side)
        p.move(to: a); p.addCurve(to: b, control1: c1, control2: c2)
        return p
    }

    static func curve(_ side: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        switch side {
        case 0: (CGPoint(x: 85, y: 180), CGPoint(x: 40, y: 150), CGPoint(x: 22, y: 90), CGPoint(x: 40, y: 38))
        case 1: (CGPoint(x: 85, y: 180), CGPoint(x: 130, y: 150), CGPoint(x: 148, y: 90), CGPoint(x: 130, y: 38))
        default: (CGPoint(x: 85, y: 180), CGPoint(x: 70, y: 140), CGPoint(x: 100, y: 110), CGPoint(x: 85, y: 128))
        }
    }

    static func leafSpot(side: Int, k: Int) -> (point: CGPoint, angle: Double) {
        let (a, c1, c2, b) = curve(side)
        let u = 0.25 + 0.2 * Double(k)
        let v = 1 - u
        let x = v * v * v * a.x + 3 * v * v * u * c1.x + 3 * v * u * u * c2.x + u * u * u * b.x
        let y = v * v * v * a.y + 3 * v * v * u * c1.y + 3 * v * u * u * c2.y + u * u * u * b.y
        let out: Double = side == 0 ? -1 : 1
        return (CGPoint(x: x, y: y), (k % 2 == 0 ? 55 : -35) * out)
    }
}

/// Botón de pánico: se mantiene pulsado un segundo (un anillo se llena) para que
/// no se dispare sin querer. Al completarse, vibra fuerte y actúa.
struct PanicHold: View {
    let action: () -> Void
    @State private var progress = 0.0
    @State private var holding = false
    @State private var done = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color(red: 1, green: 0.35, blue: 0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: done ? "lock.fill" : "hand.raised.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(done ? "Mac cerrado" : "Cerrar el invernadero").font(Typo.title(17)).foregroundStyle(Tone.ink)
                Text(holding ? "sigue pulsando…" : "mantén pulsado: silencia y bloquea el Mac al instante")
                    .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(22, tint: Color(red: 1, green: 0.3, blue: 0.3))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color(red: 1, green: 0.4, blue: 0.4).opacity(holding ? 0.8 : 0.25), lineWidth: 1))
        .scaleEffect(holding ? 0.98 : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !holding else { return }
                holding = true
                done = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.linear(duration: 1.0)) { progress = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard holding else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    done = true
                    action()
                }
            }
            .onEnded { _ in
                holding = false
                withAnimation(.spring(duration: 0.4)) { progress = 0 }
            })
        .animation(.spring(duration: 0.3), value: holding)
        .accessibilityLabel("Cerrar el invernadero: mantén pulsado para silenciar y bloquear el Mac")
    }
}

/// La foto de un intruso, grande, con la hora y el motivo.
struct IntruderSheet: View {
    let entry: IntruderLog.Entry
    @ObservedObject private var log = IntruderLog.shared

    var body: some View {
        VStack(spacing: Space.m) {
            if let img = log.photo(entry) {
                Image(uiImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            } else {
                Image(systemName: "camera.metering.unknown").font(.system(size: 40)).foregroundStyle(Tone.ink.opacity(0.4))
                    .frame(height: 200)
            }
            Text(entry.reason.prefix(1).uppercased() + entry.reason.dropFirst()).font(Typo.title(22)).foregroundStyle(Tone.ink)
            Text(entry.date.formatted(date: .complete, time: .standard)).font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.55))
            if let img = log.photo(entry) {
                ShareLink(item: Image(uiImage: img), preview: SharePreview("Intruso", image: Image(uiImage: img))) {
                    Label("compartir", systemImage: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tone.ink).frame(maxWidth: .infinity).frame(height: 50).glass(25)
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tone.body.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
