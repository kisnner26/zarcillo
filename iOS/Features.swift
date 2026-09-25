import CoreMotion
import SwiftUI
import UIKit

// MARK: - Láser

/// El iPhone como puntero: mientras mantienes el botón, girar el teléfono mueve
/// un punto de luz en el Mac. Usa el giroscopio, no la cámara.
struct LaserPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var aiming = false
    @State private var slideTaps = 0
    private let motion = CMMotionManager()

    var body: some View {
        StagePage { side in
            ZStack {
                Circle().fill(Color(red: 1, green: 0.35, blue: 0.15).opacity(aiming ? 0.45 : 0.12))
                    .frame(width: side * 0.85, height: side * 0.85)
                    .blur(radius: aiming ? 30 : 10)
                    .scaleEffect(aiming ? 1.15 : 0.9)
                Circle().fill(Tone.key).frame(width: side * 0.66, height: side * 0.66)
                VStack(spacing: 6) {
                    Image(systemName: "light.beacon.max.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .symbolEffect(.pulse, isActive: aiming)
                    Text(aiming ? "apuntando" : "mantén para apuntar")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .animation(.spring(duration: 0.4, bounce: 0.3), value: aiming)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !aiming { start() } }
                .onEnded { _ in stop() })
        } controls: {
            HStack(spacing: Space.s) {
                slideButton("chevron.left", "anterior", "left")
                slideButton("chevron.right", "siguiente", "right")
            }
            Hint("Apunta el iPhone hacia la pantalla. Las flechas pasan diapositivas en Keynote, PowerPoint o el navegador.")
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
                .frame(maxWidth: .infinity).frame(height: 58)
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
        StageScroll(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                row("bloquear", "el Mac pide contraseña al volver", "lock.fill") { confirm = .lock }
                row("apagar la pantalla", "el Mac sigue encendido", "display") { remote.send(.power(.displayOff)) }
                row("suspender", "se desconecta hasta que lo despiertes", "moon.zzz.fill") { confirm = .sleep }
                row("despertar", "si está en reposo en la misma red", "sunrise.fill") { remote.wake() }
            }
            Hint("Despertar funciona si el Mac tiene \"Activar con acceso a la red\" y en casa hay un HomePod o un Apple TV: ellos lo despiertan cuando el iPhone lo busca.")
        }
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
                    Text(title).font(.system(size: 17, weight: .bold))
                    Text(detail).font(.system(size: 12, weight: .medium)).opacity(0.65)
                }
                .foregroundStyle(Tone.ink)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .glass(20)
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
            HStack(spacing: 12) {
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
                            .padding(.horizontal, 18)
                            .frame(minHeight: 46)
                            .background(Capsule().fill(Tone.key))
                            .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
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
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
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
            // Las teclas especiales, en una fila pareja que llena el ancho.
            HStack(spacing: 5) {
                ForEach(keys, id: \.1) { label, name in
                    Button {
                        Haptic.tap()
                        remote.send(.key(name: name))
                    } label: {
                        Text(label).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tone.ink.opacity(0.9))
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .glass(10)
                    }
                    .buttonStyle(PressScale())
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.system(size: 14)).foregroundStyle(Tone.ember)
                TextField("escribe o dicta… aparece en el Mac", text: $text)
                    .focused($focused)
                    .font(.system(size: 15))
                    .foregroundStyle(Tone.ink)
                    .tint(Tone.ember)
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
                    focused = false
                    withAnimation(.spring(duration: 0.35)) { shown = false }
                } label: {
                    Text("listo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.onEmber)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(Tone.ember))
                }
                .buttonStyle(PressScale())
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 46)
            .glass(23)
        }
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
