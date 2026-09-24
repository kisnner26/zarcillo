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
            let wide = geo.size.width > geo.size.height * 1.15
            ZStack {
                Backdrop(art: remote.artwork, palette: palette)
                if let np = remote.nowPlaying {
                    if wide {
                        HStack(spacing: Space.l) {
                            Record(art: remote.artwork, palette: palette, playing: np.playing,
                                   size: min(geo.size.height - 56, geo.size.width * 0.36))
                            VStack(alignment: .leading, spacing: Space.m) {
                                meta(np, align: .leading)
                                progress(np, palette)
                                controls(np, palette)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    } else {
                        VStack(spacing: Space.m) {
                            Spacer(minLength: 0)
                            Record(art: remote.artwork, palette: palette, playing: np.playing,
                                   size: min(geo.size.width * 0.56, geo.size.height * 0.4))
                            meta(np, align: .center)
                            progress(np, palette)
                            controls(np, palette)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.l)
                    }
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
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(align == .center ? .center : .leading)
            Text(np.artist)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
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
                    VineProgress(progress: frac, color: palette.vivid,
                                 phase: np.playing ? tl.date.timeIntervalSinceReferenceDate : 0)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in scrub = max(0, min(1, v.location.x / g.size.width)) * np.duration }
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
            }
        }
    }

    private func controls(_ np: NowPlaying, _ palette: ArtPalette) -> some View {
        HStack(spacing: Space.xl) {
            button(0, "backward.fill", 20, .previous, fill: .white.opacity(0.12), fg: .white, side: 52)
            button(1, np.playing ? "pause.fill" : "play.fill", 26, .playPause,
                   fill: palette.vivid, fg: palette.vividIsLight ? .black.opacity(0.85) : .white, side: 68)
            button(2, "forward.fill", 20, .next, fill: .white.opacity(0.12), fg: .white, side: 52)
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
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            Grain(opacity: 0.09)
        }
        .clipped()
    }
}

/// La carátula con un vinilo que asoma por detrás y gira mientras suena.
struct Record: View {
    let art: UIImage?
    let palette: ArtPalette
    let playing: Bool
    let size: CGFloat
    var animated = true

    var body: some View {
        ZStack(alignment: .leading) {
            Vinyl(art: art, size: size * 0.94)
                .modifier(SpinWhile(on: playing && animated))
                .offset(x: playing ? size * 0.3 : size * 0.06)
                .animation(.spring(duration: 0.8, bounce: 0.25), value: playing)
            cover
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
                .shadow(color: palette.vivid.opacity(0.55), radius: size * 0.16, y: size * 0.08)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        }
        .frame(width: size * 1.3, height: size, alignment: .leading)
    }

    @ViewBuilder private var cover: some View {
        if let art {
            Image(uiImage: art).resizable().scaledToFill()
        } else {
            ZStack {
                palette.base
                Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundStyle(palette.vivid)
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

/// El progreso como un zarcillo: una onda que ondula mientras suena, con un
/// brote de luz en la punta.
struct VineProgress: View {
    let progress: Double
    let color: Color
    var phase: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let amp: CGFloat = 5
            let wave: CGFloat = 34
            func path(to limit: CGFloat) -> Path {
                var p = Path()
                var x: CGFloat = 0
                p.move(to: CGPoint(x: 0, y: mid + sin(CGFloat(phase) * 1.4) * amp))
                while x <= limit {
                    p.addLine(to: CGPoint(x: x, y: mid + sin(x / wave * 2 * .pi + CGFloat(phase) * 1.4) * amp))
                    x += 2
                }
                return p
            }
            let head = size.width * CGFloat(min(1, max(0, progress)))
            ctx.stroke(path(to: size.width), with: .color(.white.opacity(0.18)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var glow = ctx
            glow.addFilter(.blur(radius: 5))
            glow.stroke(path(to: head), with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.stroke(path(to: head), with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            let y = mid + sin(head / wave * 2 * .pi + CGFloat(phase) * 1.4) * amp
            let bud = CGRect(x: head - 7, y: y - 7, width: 14, height: 14)
            glow.fill(Path(ellipseIn: bud.insetBy(dx: -4, dy: -4)), with: .color(color))
            ctx.fill(Path(ellipseIn: bud), with: .color(.white))
        }
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
            VStack(spacing: 26) {
                Spacer()
                Record(art: art, palette: palette, playing: true, size: 210, animated: false)
                    .padding(.leading, 30)
                VStack(spacing: 8) {
                    Text(np.title)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(np.artist)
                        .font(.system(size: 18, weight: .medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                VStack(spacing: 6) {
                    VineProgress(progress: np.duration > 0 ? position / np.duration : 0, color: palette.vivid)
                        .frame(height: 30)
                    HStack {
                        Text(clock(position))
                        Spacer()
                        Text(clock(np.duration))
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 250)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text("sonando en mi Mac · zarcillo")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 30)
            }
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
