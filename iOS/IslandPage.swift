import SwiftUI

/// Ajustes de la isla dinámica y de la tarjeta del bloqueo.
struct IslandPage: View {
    @AppStorage("island.on") private var on = true
    @AppStorage("island.when") private var when = 0
    @AppStorage("island.tint") private var tint = 0
    @AppStorage("island.cover") private var cover = true
    @AppStorage("island.progress") private var progress = true
    @AppStorage("island.controls") private var controls = true
    @AppStorage("island.wave") private var wave = true

    var body: some View {
        StageScroll(spacing: Space.m) {
            HeroMark(symbol: "capsule.fill").foregroundStyle(Tone.ember)
                .padding(.top, Space.s)

            ToggleCard(title: "mostrar la isla", detail: "aparece al conectar con tu Mac", isOn: $on)

            if on {
                choice("cuándo", [("siempre conectado", 0), ("solo si suena algo", 1)], $when)
                choice("color", [("de la carátula", 0), ("acento de la app", 1)], $tint)

                VStack(spacing: Space.s) {
                    SectionLabel(text: "qué muestra")
                    ToggleCard(title: "carátula", detail: "la portada de la canción", isOn: $cover)
                    ToggleCard(title: "progreso", detail: "barra y tiempos", isOn: $progress)
                    ToggleCard(title: "botones", detail: "anterior, pausa y siguiente", isOn: $controls)
                    ToggleCard(title: "onda animada", detail: "mientras suena", isOn: $wave)
                }
            }
        }
        .onChange(of: on) { _, _ in LiveIsland.refresh() }
        .onChange(of: when) { _, _ in LiveIsland.refresh() }
        .onChange(of: tint) { _, _ in LiveIsland.refresh() }
        .onChange(of: cover) { _, _ in LiveIsland.refresh() }
        .onChange(of: progress) { _, _ in LiveIsland.refresh() }
        .onChange(of: controls) { _, _ in LiveIsland.refresh() }
        .onChange(of: wave) { _, _ in LiveIsland.refresh() }
    }

    private func choice(_ label: String, _ options: [(String, Int)], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: label)
            HStack(spacing: 8) {
                ForEach(options, id: \.1) { name, tag in
                    let selected = value.wrappedValue == tag
                    Button {
                        Haptic.tap()
                        value.wrappedValue = tag
                    } label: {
                        Text(name).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? Tone.onEmber : Tone.ink)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Capsule().fill(selected ? Tone.ember : Tone.key))
                            .overlay(Capsule().stroke(Tone.stroke, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(PressScale())
                }
            }
        }
    }
}
