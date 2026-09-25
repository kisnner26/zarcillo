import SwiftUI
import UIKit

// Escenas, atajos y Touch Bar con el mismo lenguaje del resto: cerámica,
// teclas grabadas, tallos con nudos y el acento del tema.

/// Rótulo de sección: mayúsculas pequeñas y espaciadas.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Tone.ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tarjeta de cerámica.
struct CeramicCard<Content: View>: View {
    var radius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Tone.key))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Tone.ink.opacity(0.12), .black.opacity(0.45)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Botón a lo ancho: lleno con el acento, o grabado en la cerámica.
struct WideButton: View {
    let title: String
    let symbol: String
    var filled = true
    let action: () -> Void

    var body: some View {
        Button {
            Detents.shared.press()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(filled ? Tone.onEmber : Tone.ink.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Capsule().fill(filled ? Tone.ember : Tone.key))
                .overlay(Capsule().stroke(filled ? .clear : Tone.stroke, lineWidth: 1))
                .shadow(color: filled ? Tone.ember.opacity(0.4) : .clear, radius: 12)
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Escenas

struct RoutineList: View {
    @EnvironmentObject private var remote: Remote
    @State private var runs: [UUID: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s + 2) {
                ForEach(remote.routines) { r in
                    NavigationLink {
                        RoutineEditor(id: r.id)
                    } label: {
                        card(r)
                    }
                    .buttonStyle(PressScale())
                    .contextMenu {
                        Button { run(r) } label: { Label("Ejecutar", systemImage: "play.fill") }
                        Button {
                            var copy = r
                            copy.id = UUID()
                            copy.name += " (copia)"
                            remote.routines.append(copy)
                        } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) {
                            remote.routines.removeAll { $0.id == r.id }
                        } label: { Label("Eliminar", systemImage: "trash") }
                    }
                }
                Button {
                    Detents.shared.press()
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                        remote.routines.append(Routine(name: "nueva escena", symbol: "sparkles", steps: []))
                    }
                } label: {
                    Label("nueva escena", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tone.ember)
                        .frame(maxWidth: .infinity).frame(height: 64)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Tone.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6])))
                }
                .buttonStyle(PressScale())
            }
            .padding(Space.m)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(Tone.recess)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(_ r: Routine) -> some View {
        CeramicCard {
            HStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(Tone.ember)
                    Image(systemName: r.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Tone.onEmber)
                }
                .frame(width: 52, height: 52)
                .shadow(color: Tone.ember.opacity(0.4), radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Tone.ink)
                    HStack(spacing: 5) {
                        ForEach(Array(r.steps.prefix(6).enumerated()), id: \.offset) { _, step in
                            Image(systemName: step.symbol).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Tone.ink.opacity(0.7))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Tone.recess))
                        }
                        if r.steps.isEmpty {
                            Text("sin pasos todavía").font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.4))
                        } else if r.steps.count > 6 {
                            Text("+\(r.steps.count - 6)").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.ink.opacity(0.5))
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { run(r) } label: {
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tone.ember)
                        .symbolEffect(.bounce, value: runs[r.id, default: 0])
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Tone.recess))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("ejecutar \(r.name)")
            }
        }
    }

    private func run(_ r: Routine) {
        Detents.shared.press()
        runs[r.id, default: 0] += 1
        remote.send(.runRoutine(r))
    }
}

struct RoutineEditor: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var adding = false
    @State private var confirmDelete = false

    private let symbols = ["sparkles", "graduationcap.fill", "film.fill", "figure.walk", "moon.fill",
                           "music.note", "briefcase.fill", "gamecontroller.fill", "book.fill",
                           "cup.and.saucer.fill", "sun.max.fill", "bolt.fill", "leaf.fill", "headphones"]

    private var index: Int? { remote.routines.firstIndex { $0.id == id } }

    var body: some View {
        Group {
            if let i = index {
                content(i)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(Tone.recess)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            StepPicker { step in
                guard let i = index else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) { remote.routines[i].steps.append(step) }
            }
            .environmentObject(remote)
        }
    }

    private func content(_ i: Int) -> some View {
        let r = $remote.routines[i]
        return ScrollView {
            VStack(spacing: Space.l) {
                // Portada: el símbolo grande y el nombre editable.
                VStack(spacing: Space.m) {
                    ZStack {
                        Circle().fill(Tone.ember)
                        Image(systemName: r.wrappedValue.symbol).font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Tone.onEmber)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 84, height: 84)
                    .shadow(color: Tone.ember.opacity(0.45), radius: 16)
                    TextField("nombre", text: r.name)
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Tone.ink)
                }
                .padding(.top, Space.s)

                VStack(spacing: Space.s) {
                    SectionLabel(text: "icono")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                        ForEach(symbols, id: \.self) { s in
                            let on = r.wrappedValue.symbol == s
                            Button {
                                Haptic.tap()
                                withAnimation(.spring(duration: 0.35)) { r.wrappedValue.symbol = s }
                            } label: {
                                Image(systemName: s).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(on ? Tone.onEmber : Tone.ink.opacity(0.75))
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(on ? Tone.ember : Tone.key))
                                    .overlay(Circle().stroke(on ? .clear : Tone.stroke, lineWidth: 1))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                }

                VStack(spacing: Space.s) {
                    SectionLabel(text: "pasos, en orden")
                    stem(r)
                    Button { adding = true } label: {
                        Label("agregar paso", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tone.ember)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Capsule().strokeBorder(Tone.ember.opacity(0.5),
                                                               style: StrokeStyle(lineWidth: 1.5, dash: [5, 6])))
                    }
                    .buttonStyle(PressScale())
                }

                WideButton(title: "probar ahora", symbol: "play.fill") {
                    remote.send(.runRoutine(r.wrappedValue))
                }
                Button("eliminar escena", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.4, blue: 0.4))
                    .frame(height: 44)
            }
            .padding(Space.m)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("¿Eliminar \(r.wrappedValue.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    remote.routines.removeAll { $0.id == id }
                }
            }
        }
    }

    /// Los pasos como nudos de un tallo, de arriba abajo.
    private func stem(_ r: Binding<Routine>) -> some View {
        VStack(spacing: 0) {
            let steps = r.wrappedValue.steps
            if steps.isEmpty {
                Text("todavía no hay pasos").font(.system(size: 14)).foregroundStyle(Tone.ink.opacity(0.4))
                    .frame(maxWidth: .infinity).frame(height: 60)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: Space.m) {
                    ZStack {
                        Rectangle().fill(Tone.ink.opacity(0.15)).frame(width: 2)
                            .padding(.top, i == 0 ? 30 : 0)
                            .padding(.bottom, i == steps.count - 1 ? 30 : 0)
                        Circle().fill(Tone.key).frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Tone.stroke, lineWidth: 1))
                        Image(systemName: step.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ember)
                    }
                    .frame(width: 40, height: 60)
                    Text(step.label).font(.system(size: 15, weight: .medium)).foregroundStyle(Tone.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Menu {
                        if i > 0 {
                            Button { move(r, i, -1) } label: { Label("Subir", systemImage: "arrow.up") }
                        }
                        if i < steps.count - 1 {
                            Button { move(r, i, 1) } label: { Label("Bajar", systemImage: "arrow.down") }
                        }
                        Button(role: .destructive) {
                            withAnimation(.spring(duration: 0.35)) { _ = r.wrappedValue.steps.remove(at: i) }
                        } label: { Label("Quitar", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Tone.ink.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key.opacity(0.55)))
    }

    private func move(_ r: Binding<Routine>, _ i: Int, _ by: Int) {
        Haptic.tap()
        withAnimation(.spring(duration: 0.35)) { r.wrappedValue.steps.swapAt(i, i + by) }
    }
}

struct StepPicker: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let onPick: (RoutineStep) -> Void
    @State private var url = "https://"
    @State private var shortcutName = ""
    @State private var level = 0.3
    @State private var seconds = 2.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    group("abrir una app") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                            ForEach(remote.apps) { app in
                                Button { pick(.openApp(id: app.id, name: app.name)) } label: {
                                    VStack(spacing: 4) {
                                        if let img = remote.icons[app.id] {
                                            Image(uiImage: img).resizable().frame(width: 46, height: 46)
                                        }
                                        Text(app.name).font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Tone.ink.opacity(0.7)).lineLimit(1)
                                    }
                                }
                                .buttonStyle(PressScale())
                            }
                        }
                    }
                    group("abrir una página") {
                        HStack(spacing: Space.s) {
                            TextField("https://…", text: $url)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.system(size: 15)).foregroundStyle(Tone.ink)
                                .padding(.horizontal, 14).frame(height: 44)
                                .background(Capsule().fill(Tone.recess))
                            chip("agregar", filled: true) { pick(.openURL(url)) }
                                .disabled(URL(string: url)?.host == nil)
                        }
                    }
                    group("volumen, brillo y espera") {
                        VStack(spacing: Space.s) {
                            HStack {
                                Image(systemName: "speaker.fill").foregroundStyle(Tone.ink.opacity(0.5))
                                Slider(value: $level, in: 0...1).tint(Tone.ember)
                                Text("\(Int(level * 100)) %").font(.system(size: 13, weight: .bold))
                                    .monospacedDigit().foregroundStyle(Tone.ember).frame(width: 48)
                            }
                            HStack(spacing: Space.s) {
                                chip("volumen", filled: false) { pick(.volume(level)) }
                                chip("brillo", filled: false) { pick(.brightness(level)) }
                            }
                            Stepper(value: $seconds, in: 1...30) {
                                Text("esperar \(Int(seconds)) s").font(.system(size: 15)).foregroundStyle(Tone.ink)
                            }
                            chip("agregar espera", filled: false) { pick(.wait(seconds)) }
                        }
                    }
                    group("música") {
                        HStack(spacing: Space.s) {
                            chip("pausar / reanudar", filled: false) { pick(.media(.playPause)) }
                            chip("siguiente", filled: false) { pick(.media(.next)) }
                        }
                    }
                    group("atajo de la app Atajos del Mac") {
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack(spacing: Space.s) {
                                TextField("nombre exacto del atajo", text: $shortcutName)
                                    .font(.system(size: 15)).foregroundStyle(Tone.ink)
                                    .padding(.horizontal, 14).frame(height: 44)
                                    .background(Capsule().fill(Tone.recess))
                                chip("agregar", filled: true) { pick(.runShortcut(shortcutName)) }
                                    .disabled(shortcutName.isEmpty)
                            }
                            Text("Para lo que Zarcillo no hace solo, como activar un Enfoque o No molestar.")
                                .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.45))
                        }
                    }
                    group("teclas") {
                        FlowChips(items: remote.shortcuts.map { ($0.id.uuidString, "\($0.glyphs)  \($0.title)") }) { id in
                            if let s = remote.shortcuts.first(where: { $0.id.uuidString == id }) { pick(.shortcut(s)) }
                        }
                    }
                    group("escritorio y energía") {
                        FlowChips(items: DesktopGesture.allCases.map { ($0.rawValue, $0.label) }
                                  + [("lock", "bloquear"), ("display", "apagar pantalla"), ("sleep", "suspender")]) { id in
                            if let g = DesktopGesture(rawValue: id) { pick(.gesture(g)) }
                            else if id == "lock" { pick(.power(.lock)) }
                            else if id == "display" { pick(.power(.displayOff)) }
                            else { pick(.power(.sleep)) }
                        }
                    }
                }
                .padding(Space.m)
            }
            .scrollIndicators(.hidden)
            .background(Tone.body)
            .navigationTitle("agregar paso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
        .tint(Tone.ember)
        .presentationBackground(Tone.body)
        .presentationCornerRadius(32)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: Space.s) {
            SectionLabel(text: title)
            CeramicCard { content() }
        }
    }

    private func chip(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Tone.onEmber : Tone.ink.opacity(0.85))
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(filled ? Tone.ember : Tone.recess))
        }
        .buttonStyle(PressScale())
    }

    private func pick(_ step: RoutineStep) {
        Detents.shared.press()
        onPick(step)
        dismiss()
    }
}

/// Fichas que se acomodan en varias filas.
struct FlowChips: View {
    let items: [(String, String)]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { id, title in
                Button { onTap(id) } label: {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tone.ink.opacity(0.85))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Capsule().fill(Tone.recess))
                }
                .buttonStyle(PressScale())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Atajos

struct ShortcutEditorPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var editing: UUID?
    /// En "más" la barra sobra (hay botón de volver); dentro de una hoja, no.
    var hidesBar = true

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(remote.shortcuts) { s in
                    Button {
                        Haptic.tap()
                        editing = s.id
                    } label: {
                        VStack(spacing: 6) {
                            Text(s.glyphs).font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Tone.ember).lineLimit(1).minimumScaleFactor(0.6)
                            Text(s.title).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Tone.ink.opacity(0.65)).lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity).frame(height: 92)
                        .background(Keycap(on: false))
                    }
                    .buttonStyle(PressScale())
                    .contextMenu {
                        Button(role: .destructive) {
                            remote.shortcuts.removeAll { $0.id == s.id }
                        } label: { Label("Eliminar", systemImage: "trash") }
                    }
                }
                Button {
                    Detents.shared.press()
                    let new = Shortcut(title: "nuevo atajo", key: "a", command: true)
                    remote.shortcuts.append(new)
                    editing = new.id
                } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Tone.ember)
                        .frame(maxWidth: .infinity).frame(height: 92)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Tone.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6])))
                }
                .buttonStyle(PressScale())
            }
            .padding(Space.m)
        }
        .scrollIndicators(.hidden)
        .background(Tone.recess)
        .toolbar(hidesBar ? .hidden : .visible, for: .navigationBar)
        .sheet(item: Binding(get: { editing.map(IDBox.init) }, set: { editing = $0?.id })) { box in
            ShortcutForm(id: box.id).environmentObject(remote)
        }
    }
}

struct IDBox: Identifiable { let id: UUID }

/// Tecla grabada: se enciende con el acento cuando está activa.
struct Keycap: View {
    let on: Bool
    var radius: CGFloat = 20

    var body: some View {
        // Tecla de vidrio: filo de luz arriba; encendida, se tiñe del acento.
        Color.clear
            .glass(radius, tint: on ? Tone.ember : .clear)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Tone.ember.opacity(on ? 0.9 : 0), lineWidth: 1.2))
            .shadow(color: on ? Tone.ember.opacity(0.3) : .clear, radius: 10)
    }
}

/// Editar un atajo con un teclado de verdad: modificadores arriba, teclas abajo.
struct ShortcutForm: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    private static let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
    ]
    private static let specials = ["escape", "tab", "space", "return", "delete", "left", "up", "down", "right", "-", "="]

    var body: some View {
        if let i = remote.shortcuts.firstIndex(where: { $0.id == id }) {
            let s = $remote.shortcuts[i]
            ScrollView {
                VStack(spacing: Space.l) {
                    // Vista previa: la combinación como una tecla grande.
                    VStack(spacing: 6) {
                        Text(s.wrappedValue.glyphs)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Tone.ember)
                            .contentTransition(.interpolate)
                        TextField("nombre", text: s.title)
                            .font(.system(size: 17, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Tone.ink)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.l)
                    .background(Keycap(on: true, radius: 28))
                    .animation(.spring(duration: 0.3), value: s.wrappedValue.glyphs)

                    VStack(spacing: Space.s) {
                        SectionLabel(text: "modificadores")
                        HStack(spacing: Space.s) {
                            modifier("⌃", "control", s.control)
                            modifier("⌥", "opción", s.option)
                            modifier("⇧", "mayús", s.shift)
                            modifier("⌘", "comando", s.command)
                        }
                    }

                    VStack(spacing: 6) {
                        SectionLabel(text: "tecla")
                        ForEach(Self.rows, id: \.self) { row in
                            HStack(spacing: 5) {
                                ForEach(row, id: \.self) { k in key(k, s.key) }
                            }
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(Self.specials, id: \.self) { k in key(k, s.key, wide: true) }
                        }
                        .padding(.top, 4)
                    }

                    WideButton(title: "probar en el Mac", symbol: "play.fill") {
                        remote.send(.shortcut(s.wrappedValue))
                    }
                    Button("eliminar atajo", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            remote.shortcuts.removeAll { $0.id == id }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.4, blue: 0.4))
                }
                .padding(Space.m)
            }
            .scrollIndicators(.hidden)
            .background(Tone.body)
            .presentationBackground(Tone.body)
            .presentationCornerRadius(32)
            .presentationDetents([.large])
        }
    }

    private func modifier(_ glyph: String, _ name: String, _ value: Binding<Bool>) -> some View {
        Button {
            Detents.shared.detent(speed: 0.2)
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { value.wrappedValue.toggle() }
        } label: {
            VStack(spacing: 2) {
                Text(glyph).font(.system(size: 22, weight: .semibold))
                Text(name).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(value.wrappedValue ? Tone.ember : Tone.ink.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 62)
            .background(Keycap(on: value.wrappedValue, radius: 16))
        }
        .buttonStyle(PressScale())
    }

    private func key(_ k: String, _ selection: Binding<String>, wide: Bool = false) -> some View {
        let on = selection.wrappedValue == k
        return Button {
            Detents.shared.detent(speed: 0.1)
            withAnimation(.spring(duration: 0.25)) { selection.wrappedValue = k }
        } label: {
            Text(Shortcut(title: "", key: k).keyGlyph)
                .font(.system(size: wide ? 13 : 16, weight: .semibold))
                .foregroundStyle(on ? Tone.ember : Tone.ink.opacity(0.8))
                .frame(maxWidth: wide ? nil : .infinity)
                .padding(.horizontal, wide ? 14 : 0)
                .frame(height: 44)
                .background(Keycap(on: on, radius: 10))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Touch Bar

/// Elegir qué muestra la Touch Bar del Mac y en qué orden, con una vista previa
/// en vivo, y mostrarla u ocultarla desde aquí.
struct TouchBarPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        StageScroll(spacing: Space.l) {
                preview
                HStack(spacing: Space.s) {
                    WideButton(title: "mostrar", symbol: "rectangle.split.3x1.fill") { remote.send(.touchBarShow(true)) }
                    WideButton(title: "ocultar", symbol: "xmark", filled: false) { remote.send(.touchBarShow(false)) }
                }
                VStack(spacing: Space.s) {
                    SectionLabel(text: "piezas, en orden")
                    ForEach(Array(remote.touchBar.slots.enumerated()), id: \.element.id) { i, slot in
                        row(slot, at: i)
                    }
                }
                Button("restablecer") {
                    Haptic.tap()
                    withAnimation(.spring(duration: 0.4)) { remote.setTouchBar(.standard) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tone.ink.opacity(0.55))
                .frame(height: 44)
        }
    }

    /// La Touch Bar en miniatura, tal como se verá.
    private var preview: some View {
        HStack(spacing: 5) {
            ForEach(remote.touchBar.slots.filter(\.on)) { slot in
                HStack(spacing: 4) {
                    Image(systemName: slot.kind.symbol).font(.system(size: 11, weight: .bold))
                    if slot.kind == .volume || slot.kind == .brightness {
                        Capsule().fill(Tone.ember).frame(width: 26, height: 3)
                    }
                }
                .foregroundStyle(slot.kind == .media ? Tone.onEmber : .white.opacity(0.85))
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(slot.kind == .media ? Tone.ember : Color(white: 0.2)))
                .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
            Image(systemName: "leaf.fill").font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tone.onEmber)
                .frame(width: 32, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tone.ember))
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
        .animation(.spring(duration: 0.4, bounce: 0.3), value: remote.touchBar)
    }

    private func row(_ slot: TouchBarConfig.Slot, at i: Int) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: slot.kind.symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(slot.on ? Tone.ember : Tone.ink.opacity(0.4))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Tone.recess))
            Text(slot.kind.label).font(.system(size: 15, weight: .medium))
                .foregroundStyle(slot.on ? Tone.ink : Tone.ink.opacity(0.45))
            Spacer(minLength: 0)
            arrow("chevron.up", enabled: i > 0) { move(i, -1) }
            arrow("chevron.down", enabled: i < remote.touchBar.slots.count - 1) { move(i, 1) }
            Toggle("", isOn: Binding(get: { slot.on }, set: { on in
                var c = remote.touchBar
                c.slots[i].on = on
                Haptic.tap()
                withAnimation(.spring(duration: 0.35)) { remote.setTouchBar(c) }
            }))
            .labelsHidden()
            .tint(Tone.ember)
        }
        .padding(.horizontal, Space.m).frame(height: 64)
        .glass(20)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tone.ink.opacity(enabled ? 0.7 : 0.15))
                .frame(width: 36, height: 44)
        }
        .disabled(!enabled)
    }

    private func move(_ i: Int, _ by: Int) {
        var c = remote.touchBar
        c.slots.swapAt(i, i + by)
        Haptic.tap()
        withAnimation(.spring(duration: 0.35)) { remote.setTouchBar(c) }
    }
}
