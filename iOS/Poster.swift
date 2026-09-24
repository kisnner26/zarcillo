import SwiftUI
import UIKit

// La música como un póster: los colores salen de la carátula, un vinilo asoma
// detrás de ella y gira mientras suena, y el progreso es un zarcillo que crece.
// Pensado para que valga la pena capturarlo y compartirlo, y para eso hay un
// botón que lo exporta en formato historia (1080 × 1920).

// MARK: - Paleta de la carátula

struct ArtPalette: Equatable {
    /// El tono de fondo: el promedio de la carátula, oscurecido.
    var base: Color
    /// El color más vivo de la carátula: progreso, sombra y botón.
    var vivid: Color
    /// Si el color vivo es claro, lo que va encima se escribe oscuro.
    var vividIsLight: Bool

    static func from(_ image: UIImage) -> ArtPalette? {
        guard let cg = image.cgImage else { return nil }
        let side = 14
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var sum = (0.0, 0.0, 0.0)
        var best = (r: 0.0, g: 0.0, b: 0.0, score: -1.0)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            sum.0 += r; sum.1 += g; sum.2 += b
            let mx = max(r, g, b), mn = min(r, g, b)
            guard mx > 0.2 else { continue }
            // Saturado y con luz: el color que "salta" de la carátula.
            let score = (mx - mn) / mx * (0.4 + mx)
            if score > best.score { best = (r, g, b, score) }
        }
        let n = Double(side * side)
        let avg = Color(red: sum.0 / n, green: sum.1 / n, blue: sum.2 / n)
        let vivid = best.score > 0.15
            ? Color(red: best.r, green: best.g, blue: best.b)
            : Color(red: min(1, sum.0 / n + 0.3), green: min(1, sum.1 / n + 0.3), blue: min(1, sum.2 / n + 0.3))
        let lum = best.score > 0.15 ? 0.2126 * best.r + 0.7152 * best.g + 0.0722 * best.b : 0.6
        return ArtPalette(base: avg.mix(with: .black, by: 0.55), vivid: vivid, vividIsLight: lum > 0.55)
    }

    static var fallback: ArtPalette {
        ArtPalette(base: Tone.body, vivid: Tone.ember, vividIsLight: Theme.shared.isLight)
    }
}

// MARK: - Escenario de música

struct MusicStage: View {
    @EnvironmentObject private var remote: Remote
    @State private var scrub: Double?
    @State private var taps = [0, 0, 0]
    @State private var exporting = false

    var body: some View {
        let palette = remote.palette ?? .fallback
        GeometryReader { geo in
            // Siempre la misma composición, centrada, con medidas fijas: un
            // título largo se encoge en su renglón en vez de empujar lo demás.
            let cover = min(geo.size.width * 0.5, geo.size.height * 0.3)
            ZStack {
                Backdrop(art: remote.artwork, palette: palette)
                if let np = remote.nowPlaying {
                    VStack(spacing: Space.s + 2) {
                        Record(art: remote.artwork, palette: palette, playing: np.playing, size: cover)
                        meta(np, align: .center)
                        progress(np, palette)
                        controls(np, palette)
                    }
                    .padding(.horizontal, Space.l)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    VStack(spacing: Space.s) {
                        Image(systemName: "music.note").font(.system(size: 44, weight: .light))
                            .foregroundStyle(Tone.ember).floating()
                        Text("nada sonando en Música ni en Spotify")
                            .font(.callout.weight(.medium)).foregroundStyle(Tone.ink.opacity(0.6))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topLeading) {
                if remote.nowPlaying != nil {
                    // Sentir la música: cada golpe vibra en la mano.
                    Button {
                        Detents.shared.press()
                        remote.feelingBeats.toggle()
                        remote.send(.beats(remote.feelingBeats))
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(remote.feelingBeats ? Tone.onEmber : .white)
                            .symbolEffect(.bounce, value: remote.beatCount)
                            .frame(width: Space.tap, height: Space.tap)
                            .background(Circle().fill(remote.feelingBeats ? Tone.ember : .black.opacity(0.35)))
                    }
                    .buttonStyle(PressScale())
                    .padding(Space.m)
                    .accessibilityLabel(remote.feelingBeats ? "dejar de sentir la música" : "sentir la música")
                }
            }
            .overlay(alignment: .topTrailing) {
                if remote.nowPlaying != nil {
                    Button { share(palette) } label: {
                        Image(systemName: exporting ? "hourglass" : "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Space.tap, height: Space.tap)
                            .background(Circle().fill(.black.opacity(0.35)))
                            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    .padding(Space.m)
                    .accessibilityLabel("compartir como imagen")
                }
            }
        }
        .animation(.smooth(duration: 0.6), value: remote.nowPlaying?.trackID)
    }

    private func meta(_ np: NowPlaying, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 6) {
            Label(np.source, systemImage: np.source == "Spotify" ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))
            Text(np.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(height: 36)
            Text(np.artist)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: align == .center ? .center : .leading)
        .contentTransition(.opacity)
    }

    private func progress(_ np: NowPlaying, _ palette: ArtPalette) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !np.playing)) { tl in
            let pos = scrub ?? remote.position(at: tl.date)
            let frac = np.duration > 0 ? pos / np.duration : 0
            VStack(spacing: 6) {
                GeometryReader { g in
                    let usable = g.size.width - VineProgress.inset * 2
                    VineProgress(progress: frac, color: Tone.ember,
                                 phase: np.playing ? tl.date.timeIntervalSinceReferenceDate : 0,
                                 active: scrub != nil)
                        .overlay(alignment: .topLeading) {
                            // Al arrastrar, una burbuja con el tiempo sobre la punta.
                            if let s = scrub {
                                Text(clock(s))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Tone.onEmber)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Tone.ember))
                                    .fixedSize()
                                    .position(x: VineProgress.inset + usable * CGFloat(frac), y: -14)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let f = (v.location.x - VineProgress.inset) / max(usable, 1)
                                scrub = max(0, min(1, f)) * np.duration
                            }
                            .onEnded { _ in
                                if let s = scrub { remote.send(.seek(seconds: s)) }
                                Detents.shared.press()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { scrub = nil }
                            })
                }
                .frame(height: 30)
                HStack {
                    Text(clock(pos))
                    Spacer()
                    Text("-" + clock(max(0, np.duration - pos)))
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, VineProgress.inset)
            }
        }
    }

    private func controls(_ np: NowPlaying, _ palette: ArtPalette) -> some View {
        HStack(spacing: Space.xl) {
            button(0, "backward.fill", 18, .previous, fill: .white.opacity(0.12), fg: .white, side: 48)
            button(1, np.playing ? "pause.fill" : "play.fill", 24, .playPause,
                   fill: Tone.ember, fg: Tone.onEmber, side: 60)
            button(2, "forward.fill", 18, .next, fill: .white.opacity(0.12), fg: .white, side: 48)
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ i: Int, _ symbol: String, _ size: CGFloat, _ key: MediaKey,
                        fill: Color, fg: Color, side: CGFloat) -> some View {
        Button {
            Detents.shared.press()
            taps[i] += 1
            remote.send(.media(key))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(fg)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps[i])
                .frame(width: side, height: side)
                .background(Circle().fill(fill))
                .shadow(color: i == 1 ? fill.opacity(0.6) : .clear, radius: 16, y: 6)
        }
        .buttonStyle(PressScale())
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Dibuja el póster en 1080 × 1920 y abre la hoja de compartir.
    private func share(_ palette: ArtPalette) {
        guard let np = remote.nowPlaying, !exporting else { return }
        exporting = true
        Detents.shared.press()
        let poster = StoryPoster(np: np, art: remote.artwork, palette: palette,
                                 position: remote.position(at: Date()))
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        if let image = renderer.uiImage { ShareSheet.present(image) }
        exporting = false
    }
}

// MARK: - Piezas

/// Fondo: la carátula muy desenfocada, teñida y con grano.
struct Backdrop: View {
    let art: UIImage?
    let palette: ArtPalette

    var body: some View {
        ZStack {
            palette.base
            if let art {
                Image(uiImage: art).resizable().scaledToFill()
                    .blur(radius: 50)
                    .saturation(1.35)
                    .opacity(0.8)
                    .transition(.opacity)
            }
            // El tema manda: el acento tiñe la carátula para que todo combine.
            Tone.ember.opacity(0.28).blendMode(.color)
            Tone.ember.opacity(0.12)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            Grain(opacity: 0.09)
        }
        .clipped()
    }
}

/// La carátula, centrada, con un vinilo que asoma por arriba mientras suena.
/// Asoma hacia arriba y no a un lado para que la composición quede simétrica.
struct Record: View {
    let art: UIImage?
    let palette: ArtPalette
    let playing: Bool
    let size: CGFloat
    var animated = true

    /// Cuánto sobresale el vinilo por encima de la carátula.
    static func peek(_ size: CGFloat) -> CGFloat { size * 0.24 }

    var body: some View {
        ZStack {
            Vinyl(art: art, size: size * 0.92)
                .modifier(SpinWhile(on: playing && animated))
                .offset(y: playing ? -Record.peek(size) : -size * 0.04)
                .animation(.spring(duration: 0.8, bounce: 0.25), value: playing)
            cover
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.07, style: .continuous))
                .shadow(color: Tone.ember.opacity(0.45), radius: size * 0.14, y: size * 0.07)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        }
        .frame(width: size, height: size)
        .padding(.top, Record.peek(size))
    }

    @ViewBuilder private var cover: some View {
        if let art {
            Image(uiImage: art).resizable().scaledToFill()
        } else {
            ZStack {
                palette.base
                Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundStyle(Tone.ember)
            }
        }
    }
}

struct Vinyl: View {
    let art: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            // Surcos
            ForEach(0..<9, id: \.self) { k in
                Circle().stroke(.white.opacity(k % 3 == 0 ? 0.08 : 0.04), lineWidth: 1)
                    .padding(size * 0.05 + CGFloat(k) * size * 0.035)
            }
            // Reflejo en diagonal
            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear, .clear, .white.opacity(0.06), .clear],
                                          center: .center))
            // Etiqueta central con la carátula
            Group {
                if let art { Image(uiImage: art).resizable().scaledToFill() } else { Color.gray }
            }
            .frame(width: size * 0.34, height: size * 0.34)
            .clipShape(Circle())
            Circle().fill(Color(white: 0.06)).frame(width: size * 0.035, height: size * 0.035)
        }
        .frame(width: size, height: size)
    }
}

/// Un vinilo a 33 ⅓: una vuelta cada 1,8 s.
private struct SpinWhile: ViewModifier {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !on || reduce)) { tl in
            content.rotationEffect(.degrees(on && !reduce
                ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360 : 0))
        }
    }
}

/// El progreso como un tallo que crece: lo que falta es una línea fina y
/// quieta; lo escuchado es un tallo en el color del tema que ondula apenas y
/// echa hojas a medida que avanza, con la punta enroscada en un zarcillo.
struct VineProgress: View {
    let progress: Double
    let color: Color
    var phase: Double = 0
    /// Mientras se arrastra, la punta crece.
    var active = false

    /// Margen a cada lado: la punta nunca se corta contra el borde.
    static let inset: CGFloat = 12

    var body: some View {
        Canvas { ctx, size in
            let inset = Self.inset
            let mid = size.height / 2
            let usable = size.width - inset * 2
            let head = inset + usable * CGFloat(min(1, max(0, progress)))
            let amp: CGFloat = 2.2
            let t = CGFloat(phase)
            func y(_ x: CGFloat) -> CGFloat { mid + sin(x / 22 + t * 1.2) * amp }

            // Lo que falta: línea recta y quieta.
            var rest = Path()
            rest.move(to: CGPoint(x: head, y: mid))
            rest.addLine(to: CGPoint(x: size.width - inset, y: mid))
            ctx.stroke(rest, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Lo escuchado: el tallo.
            var stem = Path()
            stem.move(to: CGPoint(x: inset, y: y(inset)))
            var x = inset
            while x < head { x = min(head, x + 2); stem.addLine(to: CGPoint(x: x, y: y(x))) }
            var glow = ctx
            glow.addFilter(.blur(radius: 4))
            glow.stroke(stem, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Hojas: una cada 30 pt, alternando arriba y abajo; cada una crece
            // en los 18 pt que siguen a su nacimiento.
            var i = 0
            var lx = inset + 22
            while lx < head - 4 {
                let grow = min(1, (head - lx) / 18)
                let up = i % 2 == 0
                let w = 6 * grow, h = 11 * grow
                let leaf = LeafShape().path(in: CGRect(x: -w / 2, y: -h, width: w, height: h))
                    .applying(CGAffineTransform(rotationAngle: up ? -0.75 : 0.75 + .pi))
                    .applying(CGAffineTransform(translationX: lx, y: y(lx)))
                ctx.fill(leaf, with: .color(color.opacity(0.9)))
                lx += 30
                i += 1
            }

            // La punta: un zarcillo que se enrosca, con luz.
            let r: CGFloat = active ? 9 : 7
            let tip = CGPoint(x: head, y: y(head))
            let curl = Tendril(tightness: 0.35)
                .path(in: CGRect(x: tip.x - r, y: tip.y - r * 2, width: r * 2, height: r * 2))
            ctx.stroke(curl, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            glow.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r * 0.55, y: tip.y - r * 0.55, width: r * 1.1, height: r * 1.1)),
                     with: .color(.white))
        }
        .animation(.spring(duration: 0.25), value: active)
    }
}

// MARK: - Póster para compartir

struct StoryPoster: View {
    let np: NowPlaying
    let art: UIImage?
    let palette: ArtPalette
    let position: Double

    var body: some View {
        ZStack {
            Backdrop(art: art, palette: palette)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 30) {
                    Record(art: art, palette: palette, playing: true, size: 230, animated: false)
                    VStack(spacing: 8) {
                        Text(np.title)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        Text(np.artist)
                            .font(.system(size: 18, weight: .medium))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    VStack(spacing: 6) {
                        VineProgress(progress: np.duration > 0 ? position / np.duration : 0, color: Tone.ember)
                            .frame(height: 30)
                        HStack {
                            Text(clock(position))
                            Spacer()
                            Text(clock(np.duration))
                        }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, VineProgress.inset)
                    }
                    .frame(width: 250)
                }
                Spacer(minLength: 0)
                // Solo la marca.
                HStack(spacing: 7) {
                    Image(systemName: "leaf.fill").foregroundStyle(Tone.ember)
                    Text("zarcillo")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, 34)
            }
            .padding(.top, 40)
        }
        .frame(width: 360, height: 640)
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

enum ShareSheet {
    /// La hoja de compartir del sistema: historias, mensajes, guardar en Fotos.
    @MainActor
    static func present(_ image: UIImage) {
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        vc.popoverPresentationController?.sourceView = top?.view
        top?.present(vc, animated: true)
    }
}
