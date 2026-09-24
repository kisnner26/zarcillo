import SwiftUI

/// Las capturas de pantalla que tomas en el Mac (⇧⌘3, ⇧⌘4, ⇧⌘5) llegan aquí solas:
/// copiadas, listas para pegar o compartir.
struct ShotsPage: View {
    @EnvironmentObject private var remote: Remote
    @AppStorage("shots.copy") private var autoCopy = true
    @AppStorage("shots.save") private var autoSave = false
    @State private var open: Shot?

    var body: some View {
        StageScroll(spacing: Space.m) {
            Image(systemName: "camera.viewfinder").font(.system(size: 44, weight: .semibold))
                .foregroundStyle(remote.screenshotsOn ? Tone.ember : Tone.ink.opacity(0.4))
                .symbolEffect(.bounce, value: remote.shots.count)
            ToggleCard(title: "capturas del Mac al iPhone", detail: "cada vez que tomas una con ⇧⌘3, ⇧⌘4 o ⇧⌘5",
                       isOn: Binding(get: { remote.screenshotsOn }, set: { remote.setScreenshots($0) }))
            ToggleCard(title: "copiar al llegar", detail: "para pegarla directo en cualquier app", isOn: $autoCopy)
            ToggleCard(title: "guardar en Fotos", detail: "además de tenerla aquí", isOn: $autoSave)

            if remote.shots.isEmpty {
                Hint("Toma una captura en el Mac y aparecerá aquí. Zarcillo tiene que estar abierto en el iPhone; la primera vez, el Mac pide permiso para ver el Escritorio.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(remote.shots) { shot in
                        Button {
                            Detents.shared.press()
                            open = shot
                        } label: {
                            Image(uiImage: shot.image).resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 92).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                        }
                        .buttonStyle(PressScale())
                        // Se puede arrastrar a otra app en pantalla dividida.
                        .draggable(Image(uiImage: shot.image))
                    }
                }
            }
        }
        .sheet(item: $open) { ShotSheet(shot: $0) }
    }
}

struct ShotSheet: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    let shot: Shot
    @State private var copied = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: Space.m) {
            Image(uiImage: shot.image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            Text(shot.name).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5)).lineLimit(1)
            HStack(spacing: Space.s) {
                action(copied ? "copiada" : "copiar", copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.image = shot.image
                    copied = true
                }
                action(saved ? "guardada" : "Fotos", saved ? "checkmark" : "photo.badge.plus") {
                    UIImageWriteToSavedPhotosAlbum(shot.image, nil, nil, nil)
                    saved = true
                }
                ShareLink(item: Image(uiImage: shot.image), preview: SharePreview(shot.name, image: Image(uiImage: shot.image))) {
                    label("compartir", "square.and.arrow.up")
                }
                action("borrar", "trash") {
                    remote.removeShot(shot)
                    dismiss()
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tone.body.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            run()
        } label: { label(title, symbol) }
        .buttonStyle(PressScale())
    }

    private func label(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Tone.ink.opacity(0.85))
        .frame(maxWidth: .infinity).frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
    }
}
