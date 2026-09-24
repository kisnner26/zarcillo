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
                PolaroidPile(shots: remote.shots, open: $open)
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


// MARK: - Polaroids

/// Estable por captura: la misma foto siempre cae con el mismo giro.
private func tilt(_ id: UUID, _ spread: Double) -> Double {
    let h = id.uuidString.utf8.reduce(UInt64(7)) { ($0 &* 31) &+ UInt64($1) }
    return (Double(h % 1000) / 1000 - 0.5) * 2 * spread
}

/// Un montón de fotos instantáneas. La más reciente arriba; un gesto hacia arriba
/// (o el botón) abre el montón en abanico, y hacia abajo lo recoge.
struct PolaroidPile: View {
    let shots: [Shot]
    @Binding var open: Shot?
    @State private var fanned = false

    var body: some View {
        VStack(spacing: Space.m) {
            if fanned {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                    ForEach(shots) { shot in
                        PolaroidView(shot: shot, width: nil)
                            .rotationEffect(.degrees(tilt(shot.id, 4)))
                            .onTapGesture { Detents.shared.press(); open = shot }
                            .draggable(Image(uiImage: shot.image))
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.vertical, Space.s)
            } else {
                let top = Array(shots.prefix(5))
                ZStack {
                    ForEach(Array(top.enumerated().reversed()), id: \.element.id) { depth, shot in
                        PolaroidView(shot: shot, width: 250)
                            .rotationEffect(.degrees(depth == 0 ? tilt(shot.id, 2) : tilt(shot.id, 9)))
                            .offset(x: depth == 0 ? 0 : tilt(shot.id, 14), y: Double(depth) * -6)
                            .zIndex(Double(top.count - depth))
                            .transition(.move(edge: .top).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
                            .onTapGesture { Detents.shared.press(); if depth == 0 { open = shot } else { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { fanned = true } } }
                    }
                }
                .frame(height: 330)
                .frame(maxWidth: .infinity)
            }

            if shots.count > 1 {
                Button {
                    Haptic.tap()
                    withAnimation(.spring(duration: 0.55, bounce: 0.3)) { fanned.toggle() }
                } label: {
                    Label(fanned ? "recoger el montón" : "abrir el montón · \(shots.count)",
                          systemImage: fanned ? "square.stack" : "rectangle.stack.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Tone.ink.opacity(0.85))
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Capsule().fill(Tone.key))
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard shots.count > 1, abs(v.translation.height) > abs(v.translation.width) else { return }
            let up = v.translation.height < 0
            if up != fanned {
                Haptic.thump()
                withAnimation(.spring(duration: 0.55, bounce: 0.3)) { fanned = up }
            }
        })
        .animation(.spring(duration: 0.55, bounce: 0.3), value: shots.map(\.id))
    }
}

/// Foto instantánea: marco crema con más borde abajo, sombra y fecha. Las recién
/// llegadas se "revelan": empiezan lechosas y sin color y se aclaran en unos segundos.
struct PolaroidView: View {
    let shot: Shot
    var width: CGFloat?
    @State private var developed = false

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()

    private var fresh: Bool { Date().timeIntervalSince(shot.at) < 10 }

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: shot.image).resizable().scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1.18, contentMode: .fit)
                .clipped()
                .saturation(developed ? 1 : 0.05)
                .brightness(developed ? 0 : 0.45)
                .contrast(developed ? 1 : 0.6)
                .blur(radius: developed ? 0 : 10)
                .overlay(Color(red: 0.86, green: 0.83, blue: 0.72).opacity(developed ? 0 : 0.55))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.horizontal, 10).padding(.top, 10)
            Text(Self.date.string(from: shot.at))
                .font(.system(size: 13, weight: .regular, design: .serif)).italic()
                .foregroundStyle(Color(red: 0.32, green: 0.27, blue: 0.24).opacity(0.85))
                .frame(height: 38)
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 0.97, green: 0.95, blue: 0.9)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .onAppear {
            guard !developed else { return }
            if fresh { withAnimation(.easeOut(duration: 4.5).delay(0.4)) { developed = true } } else { developed = true }
        }
    }
}
