import SwiftUI

/// Las luces Govee que siguen la pantalla del Mac.
struct LightsPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var scanning = false

    var body: some View {
        StageScroll(spacing: Space.l) {
                orb

                if !remote.lights.isEmpty {
                    VStack(spacing: Space.s) {
                        SectionLabel(text: "intensidad")
                        HStack(spacing: Space.s) {
                            Image(systemName: "sun.min.fill").foregroundStyle(Tone.ink.opacity(0.5))
                            Slider(value: Binding(get: { remote.lightsBrightness },
                                                  set: { remote.lightsBrightness = $0 }),
                                   in: 0.05...1,
                                   onEditingChanged: { editing in
                                       if !editing { remote.send(.lightsBrightness(remote.lightsBrightness)) }
                                   })
                                .tint(Tone.ember)
                            Image(systemName: "sun.max.fill").foregroundStyle(Tone.ember)
                        }
                        .padding(.horizontal, Space.m).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
                    }
                }

                VStack(spacing: Space.s) {
                    SectionLabel(text: remote.lights.isEmpty ? "focos" : "cada foco sigue una zona de la pantalla")
                    if remote.lights.isEmpty {
                        empty
                    } else {
                        ForEach(remote.lights) { light in row(light) }
                    }
                    Button {
                        Haptic.tap()
                        scanning = true
                        remote.send(.lightsScan)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { scanning = false }
                    } label: {
                        Label(scanning ? "buscando…" : "buscar focos", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tone.ember)
                            .symbolEffect(.variableColor.iterative, isActive: scanning)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Capsule().strokeBorder(Tone.ember.opacity(0.5),
                                                               style: StrokeStyle(lineWidth: 1.5, dash: [5, 6])))
                    }
                    .buttonStyle(PressScale())
                }
        }
        .onAppear { remote.send(.lightsScan) }
    }

    /// Botón principal: una bombilla que se enciende en el color del tema.
    private var orb: some View {
        Button {
            Detents.shared.press()
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) { remote.lightsAmbient.toggle() }
            remote.send(.lightsAmbient(remote.lightsAmbient))
        } label: {
            ZStack {
                Circle().fill(remote.lightsAmbient ? Tone.ember.opacity(0.35) : .clear)
                    .frame(width: 190, height: 190).blur(radius: 30)
                Circle().fill(remote.lightsAmbient ? Tone.ember : Tone.key).frame(width: 130, height: 130)
                    .overlay(Circle().stroke(Tone.stroke, lineWidth: remote.lightsAmbient ? 0 : 1))
                    .shadow(color: remote.lightsAmbient ? Tone.ember.opacity(0.6) : .clear, radius: 24)
                VStack(spacing: 4) {
                    Image(systemName: remote.lightsAmbient ? "lightbulb.max.fill" : "lightbulb")
                        .font(.system(size: 34, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(remote.lightsAmbient ? "siguiendo" : "apagado").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(remote.lightsAmbient ? Tone.onEmber : Tone.ink.opacity(0.7))
            }
            .frame(height: 200)
        }
        .buttonStyle(PressScale())
        .disabled(remote.lights.isEmpty)
        .opacity(remote.lights.isEmpty ? 0.5 : 1)
        .accessibilityLabel(remote.lightsAmbient ? "apagar luces que siguen la pantalla" : "encender luces que siguen la pantalla")
    }

    private var empty: some View {
        CeramicCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("No encuentro focos todavía", systemImage: "lightbulb.slash")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink)
                Text("En la app Govee Home, abre cada foco › engranaje de ajustes › activa **LAN Control**. El Mac y los focos tienen que estar en la misma Wi-Fi.")
                    .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Los focos Lepro no tienen control local; si se pueden agregar a la app Smart Life, avísame y los sumamos.")
                    .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ light: LightInfo) -> some View {
        CeramicCard {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Tone.ember)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Govee \(light.sku)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink)
                        Text(light.ip).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tone.ink.opacity(0.45))
                    }
                    Spacer()
                    Button("identificar") {
                        Haptic.tap()
                        remote.send(.lightIdentify(id: light.id))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tone.ember)
                    .frame(height: 44)
                }
                HStack(spacing: 6) {
                    ForEach(LightZone.allCases, id: \.self) { zone in
                        let on = light.zone == zone
                        Button {
                            Haptic.tap()
                            remote.send(.lightZone(id: light.id, zone: zone))
                        } label: {
                            Text(zone.label).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(on ? Tone.onEmber : Tone.ink.opacity(0.7))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(Capsule().fill(on ? Tone.ember : Tone.recess))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
        }
    }
}
