import SwiftUI

/// El jardín vivo: cada orden que el cerebro aprendió es una planta. Brota cuando
/// la aprende, echa hojas con el uso, florece cuando queda fija y se marchita si
/// pasan días sin que la pidas.
struct GardenPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var grow: Double = 0
    @State private var picked: String?

    var body: some View {
        StageScroll(spacing: Space.m) {
            let intents = remote.brainInfo?.intents ?? []
            let blooming = intents.filter(\.fixed).count
            let wilted = intents.filter { Self.wilt($0) > 0.5 }.count

            GardenCanvas(intents: intents, grow: grow, picked: $picked)
                .aspectRatio(0.95, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Tone.stroke, lineWidth: 1))

            if let p = intents.first(where: { $0.id == picked }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.template).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                    Text(p.steps.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55))
                    Text("\(p.uses) uso\(p.uses == 1 ? "" : "s") · " + Self.state(p))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ember)
                }
                .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: Space.s) {
                chip("\(intents.count)", "plantas")
                chip("\(blooming)", "en flor")
                chip("\(wilted)", "marchitas")
            }
            Hint(intents.isEmpty
                 ? "Todavía no hay nada sembrado. Pídele algo nuevo al cerebro por voz o escrito y, cuando lo resuelva, brotará aquí."
                 : "Toca una planta para ver qué orden es. Se ponen fijas (flor) a la segunda vez que salen bien; si pasa una semana sin usarlas, se marchitan.")
        }
        .animation(.spring(duration: 0.4), value: picked)
        .task {
            remote.send(.brainInfo)
            withAnimation(.easeOut(duration: 2.4)) { grow = 1 }
        }
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Tone.ember)
            Text(label).font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
    }

    /// 0 = fresca, 1 = seca del todo (a los 14 días sin usar).
    static func wilt(_ i: BrainIntentInfo) -> Double {
        guard let t = i.lastUsed else { return 0 }
        let days = Date().timeIntervalSince(Date(timeIntervalSince1970: t)) / 86_400
        return min(1, max(0, (days - 3) / 11))
    }

    static func state(_ i: BrainIntentInfo) -> String {
        if wilt(i) > 0.5 { return "marchita" }
        if i.fixed { return "en flor" }
        return i.uses > 1 ? "con hojas" : "brote"
    }
}

/// Hash estable: la misma orden siempre nace en el mismo lugar.
private func unit(_ s: String, _ salt: Int) -> Double {
    var h: UInt64 = 1469598103934665603 &+ UInt64(salt)
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Double(h % 10_000) / 10_000
}

private struct GardenCanvas: View {
    let intents: [BrainIntentInfo]
    let grow: Double
    @Binding var picked: String?

    /// Dónde cae cada planta: filas de fondo a frente, las más nuevas al frente.
    private func spot(_ i: BrainIntentInfo, _ index: Int, _ n: Int, _ size: CGSize) -> CGPoint {
        let cols = max(2, min(4, Int(ceil(sqrt(Double(max(n, 1)) * 1.4)))))
        let row = index / cols, col = index % cols
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let fx = (Double(col) + 0.5 + (unit(i.id, 1) - 0.5) * 0.5) / Double(cols)
        let fy = 0.58 + 0.34 * (rows == 1 ? 0.5 : Double(row) / Double(rows - 1))
        return CGPoint(x: fx * size.width, y: fy * size.height)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // Cielo y tierra.
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.13), Color(red: 0.20, green: 0.13, blue: 0.16)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.6)))
                let soil = Path(ellipseIn: CGRect(x: -size.width * 0.2, y: size.height * 0.66, width: size.width * 1.4, height: size.height * 0.7))
                ctx.fill(soil, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.24, green: 0.17, blue: 0.14), Color(red: 0.12, green: 0.09, blue: 0.09)]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.66), endPoint: CGPoint(x: 0, y: size.height)))
                // Luciérnagas.
                for k in 0..<14 {
                    let a = unit("f\(k)", 3), b = unit("f\(k)", 4)
                    let x = (a + 0.04 * sin(t * 0.5 + Double(k))) * size.width
                    let y = (b * 0.6 + 0.03 * cos(t * 0.6 + Double(k) * 2)) * size.height
                    let glow = 0.25 + 0.25 * sin(t * 1.3 + Double(k) * 1.7)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(Tone.ember.opacity(glow)))
                }
                let list = intents.sorted { $0.uses < $1.uses }
                for (idx, i) in list.enumerated() {
                    plant(&ctx, i, at: spot(i, idx, list.count, size), size: size, t: t)
                }
            }
            .overlay { taps }
        }
    }

    /// Zonas táctiles invisibles sobre cada planta.
    private var taps: some View {
        GeometryReader { geo in
            let list = intents.sorted { $0.uses < $1.uses }
            ForEach(Array(list.enumerated()), id: \.element.id) { idx, i in
                let p = spot(i, idx, list.count, geo.size)
                Color.clear.frame(width: 64, height: 110).contentShape(Rectangle())
                    .position(x: p.x, y: p.y - 40)
                    .onTapGesture {
                        Haptic.tap()
                        picked = picked == i.id ? nil : i.id
                    }
            }
        }
    }

    private func plant(_ ctx: inout GraphicsContext, _ i: BrainIntentInfo, at base: CGPoint, size: CGSize, t: TimeInterval) {
        let wilt = GardenPage.wilt(i)
        let stage = i.fixed ? 2 : (i.uses > 1 ? 1 : 0)
        let g = min(1, max(0, grow * 1.25 - unit(i.id, 5) * 0.25))         // cada planta brota a su hora
        let height = (stage == 0 ? 46 : stage == 1 ? 74 : 98) * g * (1 - wilt * 0.35) * (size.height / 380)
        let sway = sin(t * 0.9 + unit(i.id, 6) * 6.28) * 5 * (1 - wilt)
        let droop = wilt * 26
        let tip = CGPoint(x: base.x + sway + (unit(i.id, 7) - 0.5) * 12 + droop, y: base.y - height + droop * 0.6)
        let green = Color(hue: 0.33 - wilt * 0.2, saturation: 0.55 - wilt * 0.35, brightness: 0.78 - wilt * 0.3)
        let selected = picked == i.id

        // Sombra en el suelo.
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - 16, y: base.y - 3, width: 32, height: 8)), with: .color(.black.opacity(0.3)))

        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: tip, control: CGPoint(x: base.x + sway * 0.2 - droop * 0.4, y: base.y - height * 0.55))
        ctx.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        // Hojas a lo largo del tallo.
        let leaves = stage == 0 ? 1 : stage == 1 ? 3 : 4
        for k in 0..<leaves {
            let f = 0.35 + 0.55 * Double(k) / Double(max(leaves, 1))
            let p = CGPoint(x: base.x + (tip.x - base.x) * f, y: base.y + (tip.y - base.y) * f)
            let side: Double = k % 2 == 0 ? 1 : -1
            let len = (12 + 8 * Double(stage)) * g * (1 - wilt * 0.4)
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .degrees(side * (58 + sin(t * 1.1 + Double(k)) * 6) + wilt * side * 30))
            c.fill(LeafShape().path(in: CGRect(x: -len * 0.32, y: -len, width: len * 0.64, height: len)),
                   with: .color(green.opacity(0.95)))
        }

        // Flor: solo las fijas, y se cierra al marchitar.
        if stage == 2 {
            let open = g * (1 - wilt)
            let petals = 7
            let hue = unit(i.id, 8)
            let petal = Color(hue: 0.9 + hue * 0.15, saturation: 0.45 + 0.2 * (1 - wilt), brightness: 0.95 - wilt * 0.4)
            for k in 0..<petals {
                var c = ctx
                c.translateBy(x: tip.x, y: tip.y)
                c.rotate(by: .degrees(Double(k) / Double(petals) * 360 + t * 6))
                let l = 15 * open + 3
                c.fill(Path(ellipseIn: CGRect(x: -4.5, y: -l - 2, width: 9, height: l)), with: .color(petal))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4.5, y: tip.y - 4.5, width: 9, height: 9)), with: .color(Tone.ember))
        } else {
            // Brote: una yema.
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 5, width: 8, height: 10)), with: .color(green))
        }

        if selected {
            ctx.stroke(Path(ellipseIn: CGRect(x: base.x - 28, y: tip.y - 26, width: 56, height: base.y - tip.y + 40)),
                       with: .color(Tone.ember.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
    }
}
