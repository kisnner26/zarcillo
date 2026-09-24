import CoreMotion
import SwiftUI
import UIKit

// MARK: - Pantalla en vivo

struct ScreenPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var tapPoint: CGPoint?
    @State private var taps = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = remote.frame {
                    let fit = fitted(img.size, in: geo.size)
                    Image(uiImage: img).resizable()
                        .frame(width: fit.width, height: fit.height)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Tone.ink.opacity(0.4), radius: 18, y: 10)
                        .overlay {
                            if let p = tapPoint {
                                Circle().stroke(.white, lineWidth: 3)
                                    .frame(width: 44, height: 44)
                                    .position(p)
                                    .keyframeAnimator(initialValue: RippleState(), trigger: taps) { v, s in
                                        v.scaleEffect(s.scale).opacity(s.opacity)
                                    } keyframes: { _ in
                                        KeyframeTrack(\.scale) { LinearKeyframe(0.4, duration: 0.001); CubicKeyframe(1.6, duration: 0.5) }
                                        KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.001); CubicKeyframe(0, duration: 0.5) }
                                    }
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        // Toque = clic; mantener y soltar = clic derecho, donde está el dedo.
                        .onTapGesture(coordinateSpace: .local) { p in tap(p, fit, .left) }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onEnded { value in
                                    if case .second(true, let drag?) = value { tap(drag.location, fit, .right) }
                                }
                        )
                        .transition(.opacity)
                } else {
                    VStack(spacing: 14) {
                        if remote.canCapture {
                            RadarRings().frame(width: 60, height: 60)
                            Text("Mirando la pantalla del Mac…")
                                .font(.callout.weight(.medium)).foregroundStyle(Tone.ink.opacity(0.75))
                        } else {
                            Image(systemName: "rectangle.dashed").font(.system(size: 44, weight: .light))
                                .foregroundStyle(Tone.ink.opacity(0.6))
                            Text("En el Mac, dale a Zarcillo el permiso de Grabación de pantalla (menú de la hoja › Dar permiso…).")
                                .font(.callout.weight(.medium)).multilineTextAlignment(.center)
                                .foregroundStyle(Tone.ink.opacity(0.75)).padding(.horizontal, 30)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(10)
        .onAppear { remote.send(.screen(on: true)) }
        .onDisappear { remote.send(.screen(on: false)) }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func tap(_ p: CGPoint, _ fit: CGSize, _ button: MouseButton) {
        tapPoint = p
        taps += 1
        Haptic.tap()
        remote.send(.tapScreen(x: p.x / fit.width, y: p.y / fit.height, button: button))
    }
}

// MARK: - Láser

/// El iPhone como puntero: mientras mantienes el botón, girar el teléfono mueve
/// un punto de luz en el Mac. Usa el giroscopio, no la cámara.
struct LaserPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var aiming = false
    @State private var slideTaps = 0
    private let motion = CMMotionManager()

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(Color(red: 1, green: 0.35, blue: 0.15).opacity(aiming ? 0.45 : 0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: aiming ? 30 : 10)
                    .scaleEffect(aiming ? 1.15 : 0.9)
                Circle().fill(Tone.key).frame(width: 170, height: 170)
                VStack(spacing: 6) {
                    Image(systemName: "light.beacon.max.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .symbolEffect(.pulse, isActive: aiming)
                    Text(aiming ? "apuntando" : "mantén para apuntar")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
            .animation(.spring(duration: 0.4, bounce: 0.3), value: aiming)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !aiming { start() } }
                .onEnded { _ in stop() })

            HStack(spacing: 18) {
                slideButton("chevron.left", "anterior", "left")
                slideButton("chevron.right", "siguiente", "right")
            }
            Text("Apunta el iPhone hacia la pantalla. Las flechas pasan diapositivas en Keynote, PowerPoint o el navegador.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(Tone.ink.opacity(0.6)).padding(.horizontal, 30)
            Spacer()
        }
        .onDisappear { stop() }
    }

    private func slideButton(_ symbol: String, _ title: String, _ key: String) -> some View {
        Button {
            Haptic.thump()
            slideTaps += 1
            remote.send(.key(name: key))
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 150, height: 58)
                .background(Capsule().fill(Tone.key))
        }
        .buttonStyle(PressScale())
    }

    private func start() {
        aiming = true
        Haptic.thump()
        remote.send(.laser(on: true))
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let r = data?.rotationRate else { return }
            // Girar a los lados es rotar sobre el eje z del teléfono; inclinarlo, sobre el x.
            let gain = 1500.0 / 60
            let dx = abs(r.z) > 0.02 ? -r.z * gain : 0
            let dy = abs(r.x) > 0.02 ? -r.x * gain : 0
            if dx != 0 || dy != 0 { remote.send(.laserMove(dx: dx, dy: dy)) }
        }
    }

    private func stop() {
        guard aiming else { return }
        aiming = false
        motion.stopDeviceMotionUpdates()
        remote.send(.laser(on: false))
    }
}

// MARK: - Energía

struct PowerPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var confirm: PowerAction?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            row("bloquear", "el Mac pide contraseña al volver", "lock.fill") { confirm = .lock }
            row("apagar la pantalla", "el Mac sigue encendido", "display") { remote.send(.power(.displayOff)) }
            row("suspender", "se desconecta hasta que lo despiertes", "moon.zzz.fill") { confirm = .sleep }
            row("despertar", "si está en reposo en la misma red", "sunrise.fill") { remote.wake() }
            Text("Despertar funciona si el Mac tiene \"Activar con acceso a la red\" y en casa hay un HomePod o un Apple TV: ellos lo despiertan cuando el iPhone lo busca.")
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(Tone.ink.opacity(0.6)).padding(.horizontal, 26).padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 20)
        .confirmationDialog(confirm == .sleep ? "¿Suspender el Mac?" : "¿Bloquear el Mac?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button(confirm == .sleep ? "Suspender" : "Bloquear", role: .destructive) {
                if let c = confirm { remote.send(.power(c)) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.thump()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 46, height: 46)
                    .background(Circle().fill(Tone.key))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(detail).font(.system(size: 12, weight: .medium)).opacity(0.65)
                }
                .foregroundStyle(Tone.ink)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: 480)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - Escenas

/// Fila horizontal de escenas, arriba de las apps.
struct RoutineStrip: View {
    @EnvironmentObject private var remote: Remote
    @State private var taps: [UUID: Int] = [:]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(remote.routines) { r in
                    Button {
                        Haptic.thump()
                        taps[r.id, default: 0] += 1
                        remote.send(.runRoutine(r))
                    } label: {
                        Label(r.name, systemImage: r.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: taps[r.id, default: 0])
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Tone.key))
                            .overlay {
                                Capsule().stroke(.white, lineWidth: 2)
                                    .keyframeAnimator(initialValue: RippleState(), trigger: taps[r.id, default: 0]) { v, s in
                                        v.scaleEffect(x: 1 + (s.scale - 1) * 0.3, y: s.scale).opacity(s.opacity)
                                    } keyframes: { _ in
                                        KeyframeTrack(\.scale) { LinearKeyframe(1, duration: 0.001); CubicKeyframe(1.6, duration: 0.5) }
                                        KeyframeTrack(\.opacity) { LinearKeyframe(0.9, duration: 0.001); CubicKeyframe(0, duration: 0.5) }
                                    }
                                    .allowsHitTesting(false)
                            }
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

struct RoutineList: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        List {
            ForEach($remote.routines) { $r in
                NavigationLink { RoutineEditor(routine: $r) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.headline)
                            Text("\(r.steps.count) pasos").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: r.symbol) }
                }
            }
            .onDelete { remote.routines.remove(atOffsets: $0) }
            .onMove { remote.routines.move(fromOffsets: $0, toOffset: $1) }
            .listRowBackground(Tone.key)

            Button {
                remote.routines.append(Routine(name: "nueva escena", symbol: "sparkles", steps: []))
            } label: { Label("Nueva escena", systemImage: "plus") }
                .listRowBackground(Tone.key)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Escenas")
        .toolbar { EditButton() }
    }
}

struct RoutineEditor: View {
    @EnvironmentObject private var remote: Remote
    @Binding var routine: Routine
    @State private var adding = false

    private let symbols = ["sparkles", "graduationcap.fill", "film.fill", "figure.walk", "moon.fill",
                           "music.note", "briefcase.fill", "gamecontroller.fill", "book.fill", "cup.and.saucer.fill"]

    var body: some View {
        Form {
            Section("Nombre") {
                TextField("nombre", text: $routine.name)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(symbols, id: \.self) { s in
                            Image(systemName: s)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(routine.symbol == s ? Tone.key : .clear))
                                .foregroundStyle(routine.symbol == s ? .white : .primary)
                                .onTapGesture { withAnimation(.spring) { routine.symbol = s } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Section("Pasos, en orden") {
                ForEach(Array(routine.steps.enumerated()), id: \.offset) { _, step in
                    Label(step.label, systemImage: step.symbol)
                }
                .onDelete { routine.steps.remove(atOffsets: $0) }
                .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                Button { adding = true } label: { Label("Agregar paso", systemImage: "plus") }
            }
            Section {
                Button {
                    remote.send(.runRoutine(routine))
                    Haptic.thump()
                } label: { Label("Probar ahora", systemImage: "play.fill") }
            }
        }
        .navigationTitle(routine.name)
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            StepPicker { routine.steps.append($0) }.environmentObject(remote)
        }
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
            Form {
                Section("Abrir una app") {
                    ForEach(remote.apps) { app in
                        Button { pick(.openApp(id: app.id, name: app.name)) } label: {
                            HStack {
                                if let img = remote.icons[app.id] { Image(uiImage: img).resizable().frame(width: 26, height: 26) }
                                Text(app.name)
                            }
                        }
                    }
                }
                Section("Abrir una página") {
                    TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                    Button("Agregar") { pick(.openURL(url)) }.disabled(URL(string: url)?.host == nil)
                }
                Section("Volumen, brillo y espera") {
                    Slider(value: $level, in: 0...1) { Text("nivel") }
                    Button("Volumen al \(Int(level * 100)) %") { pick(.volume(level)) }
                    Button("Brillo al \(Int(level * 100)) %") { pick(.brightness(level)) }
                    Stepper("Esperar \(Int(seconds)) s", value: $seconds, in: 1...30)
                    Button("Agregar espera") { pick(.wait(seconds)) }
                }
                Section("Música") {
                    Button("Pausar o reanudar") { pick(.media(.playPause)) }
                    Button("Siguiente canción") { pick(.media(.next)) }
                }
                Section {
                    TextField("nombre exacto del atajo", text: $shortcutName)
                    Button("Agregar") { pick(.runShortcut(shortcutName)) }.disabled(shortcutName.isEmpty)
                } header: {
                    Text("Atajo de la app Atajos del Mac")
                } footer: {
                    Text("Sirve para lo que Zarcillo no hace solo: activar un Enfoque o No molestar, por ejemplo.")
                }
                Section("Teclas") {
                    ForEach(remote.shortcuts) { s in
                        Button("\(s.title)  \(s.glyphs)") { pick(.shortcut(s)) }
                    }
                }
                Section("Escritorio y energía") {
                    ForEach(DesktopGesture.allCases, id: \.self) { g in Button(g.label) { pick(.gesture(g)) } }
                    Button("Bloquear el Mac") { pick(.power(.lock)) }
                    Button("Apagar la pantalla") { pick(.power(.displayOff)) }
                    Button("Suspender el Mac") { pick(.power(.sleep)) }
                }
            }
            .navigationTitle("Agregar paso")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
    }

    private func pick(_ step: RoutineStep) {
        Haptic.tap()
        onPick(step)
        dismiss()
    }
}

/// El editor de atajos como página (desde "más").
struct ShortcutEditorPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        List {
            ForEach($remote.shortcuts) { $s in
                NavigationLink { ShortcutForm(shortcut: $s) } label: {
                    HStack {
                        Text(s.title)
                        Spacer()
                        Text(s.glyphs).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { remote.shortcuts.remove(atOffsets: $0) }
            .onMove { remote.shortcuts.move(fromOffsets: $0, toOffset: $1) }
            .listRowBackground(Tone.key)
            Button {
                remote.shortcuts.append(Shortcut(title: "nuevo atajo", key: "a", command: true))
            } label: { Label("Agregar atajo", systemImage: "plus") }
                .listRowBackground(Tone.key)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Atajos")
        .toolbar { EditButton() }
    }
}

// MARK: - Teclado remoto

/// Barra de escritura: lo que tecleas o dictas aparece en el Mac mientras escribes.
struct KeyboardBar: View {
    @EnvironmentObject private var remote: Remote
    @Binding var shown: Bool
    @State private var text = ""
    @State private var sent = ""
    @FocusState private var focused: Bool

    private let keys: [(String, String)] = [("esc", "escape"), ("⇥", "tab"), ("←", "left"), ("↑", "up"),
                                            ("↓", "down"), ("→", "right"), ("⌫", "delete"), ("↩", "return")]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.1) { label, name in
                        Button {
                            Haptic.tap()
                            remote.send(.key(name: name))
                        } label: {
                            Text(label).font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 36)
                                .padding(.horizontal, 4)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Tone.key))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(.white.opacity(0.7))
                TextField("escribe o dicta… aparece en el Mac", text: $text)
                    .focused($focused)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .autocorrectionDisabled(false)
                    .submitLabel(.return)
                    .onSubmit {
                        remote.send(.key(name: "return"))
                        text = ""
                        sent = ""
                        focused = true
                    }
                    .onChange(of: text) { _, new in sync(new) }
                Button {
                    withAnimation(.spring(duration: 0.35)) { shown = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Capsule().fill(Tone.key))
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onAppear { focused = true }
    }

    /// Manda solo la diferencia con lo ya enviado: letras nuevas se escriben,
    /// letras borradas se borran en el Mac con ⌫. Así el autocorrector y el
    /// dictado, que reescriben palabras enteras, también quedan bien.
    private func sync(_ new: String) {
        let old = Array(sent), now = Array(new)
        var common = 0
        while common < old.count, common < now.count, old[common] == now[common] { common += 1 }
        for _ in 0..<(old.count - common) { remote.send(.key(name: "delete")) }
        let added = String(now[common...])
        if !added.isEmpty { remote.send(.type(text: added)) }
        sent = new
        // El campo no crece sin límite: tras una frase larga se vacía sin tocar el Mac.
        if new.count > 160, new.hasSuffix(" ") {
            DispatchQueue.main.async { text = ""; sent = "" }
        }
    }
}
