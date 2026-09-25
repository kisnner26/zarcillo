import SwiftUI

/// Modo privacidad: una vista previa que se ve como la pantalla del Mac mirada
/// de frente o de lado (inclina el iPhone o arrastra), y los ajustes del filtro.
struct PrivacyPage: View {
    @EnvironmentObject private var remote: Remote
    @StateObject private var tilt = Tilt()
    @AppStorage("privacy.strength") private var strength = 0.6
    @AppStorage("privacy.focus") private var focus = false
    @AppStorage("privacy.onlookers") private var onlookers = false
    @State private var drag = 0.0

    var body: some View {
        StageScroll(spacing: Space.m) {
            preview
                .padding(.top, Space.s)

            Button {
                Detents.shared.press()
                remote.setPrivacy(!remote.privacyOn)
            } label: {
                Label(remote.privacyOn ? "privacidad activada" : "activar privacidad",
                      systemImage: remote.privacyOn ? "eye.slash.fill" : "eye")
                    .font(.system(size: 16, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(remote.privacyOn ? Tone.onEmber : Tone.ink)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(remote.privacyOn ? Tone.ember : Tone.key))
                    .overlay(Capsule().stroke(Tone.stroke, lineWidth: remote.privacyOn ? 0 : 1))
            }
            .buttonStyle(PressScale())

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("intensidad").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink)
                    Spacer()
                    Text(strength < 0.4 ? "suave" : strength < 0.75 ? "media" : "fuerte")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ember)
                }
                Slider(value: $strength, in: 0.2...1) { editing in if !editing { resend() } }
                    .tint(Tone.ember)
            }
            .padding(Space.m)
            .glass(22)

            ToggleCard(title: "foco en el cursor", detail: "solo queda clara la zona donde trabajas", isOn: $focus)
                .onChange(of: focus) { _, _ in resend() }
            ToggleCard(title: "tapar si alguien más mira", detail: "la cámara del Mac cuenta las caras, sin guardar nada", isOn: $onlookers)
                .onChange(of: onlookers) { _, _ in resend() }

            if remote.onlooker {
                Label("hay alguien más mirando tu Mac", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.72, blue: 0.2))
                    .transition(.opacity)
            }

            Hint("Es un filtro hecho por software: oscurece los costados de la pantalla y lo que no estás mirando, y no aparece en capturas. No cambia el ángulo físico del panel como un filtro de lámina real.")
        }
        .animation(.spring(duration: 0.4), value: remote.onlooker)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }

    private func resend() {
        if remote.privacyOn { remote.setPrivacy(true) }
    }

    /// Ángulo de mirada: −1 de lado izquierdo, 0 de frente, 1 de lado derecho.
    private var angle: Double { max(-1, min(1, tilt.roll * 1.6 + drag)) }

    /// Cuánto se oscurece la pantalla al verla desde ese ángulo.
    private var shade: Double {
        guard remote.privacyOn else { return abs(angle) * 0.12 }
        return min(0.96, pow(abs(angle), 0.8) * (0.55 + 0.45 * strength) * 1.2)
    }

    private var preview: some View {
        VStack(spacing: Space.s) {
            ZStack {
                // Pantalla con contenido de ejemplo.
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.09, green: 0.075, blue: 0.07))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.7)).frame(width: 7, height: 7) }
                    }
                    Text("Cuenta · saldo").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.6))
                    Text("C$ 24 580,00").font(.system(size: 22, weight: .bold)).foregroundStyle(Tone.ink)
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(Tone.ink.opacity(0.18)).frame(width: [150, 190, 120][i], height: 6)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Lo que hace el filtro: trama de láminas y oscuridad según el ángulo.
                if remote.privacyOn {
                    Canvas { ctx, size in
                        var x = 0.0
                        var lines = Path()
                        while x < size.width { lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 3 }
                        ctx.fill(lines, with: .color(.black.opacity(0.18 + 0.4 * abs(angle))))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(shade))
                // Reflejo que se desliza con el ángulo.
                LinearGradient(colors: [.clear, .white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60).offset(x: angle * 140).blur(radius: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(remote.privacyOn ? Tone.ember.opacity(0.7) : Tone.stroke, lineWidth: 1.5))
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxWidth: 360)
            .rotation3DEffect(.degrees(angle * 38), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .animation(.spring(duration: 0.35), value: remote.privacyOn)

            // Base del portátil.
            Capsule().fill(Tone.key).frame(maxWidth: 400).frame(height: 10)
                .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
                .rotation3DEffect(.degrees(angle * 38), axis: (x: 0, y: 1, z: 0), perspective: 0.55)

            Text(abs(angle) < 0.2 ? "de frente: tú lo ves todo" : "de lado: así lo ve quien está al lado")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.5))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: abs(angle) < 0.2)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { drag = max(-1, min(1, $0.translation.width / 150)) }
            .onEnded { _ in withAnimation(.spring(duration: 0.5, bounce: 0.3)) { drag = 0 } })
        .accessibilityLabel("vista previa del filtro de privacidad; inclina el iPhone o arrastra para mirar de lado")
    }
}
