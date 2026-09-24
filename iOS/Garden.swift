import SwiftUI

/// El jardín vivo: cada orden que el cerebro aprendió es una planta. Brota cuando
/// la aprende, echa hojas con el uso, florece cuando queda fija y se marchita si
/// pasan días sin que la pidas.
struct GardenPage: View {
    @EnvironmentObject private var remote: Remote
    @ObservedObject private var herbs = HerbStore.shared
    @State private var grow: Double = 0
    @State private var picked: String?
    @State private var pruning: Date?
    @AppStorage("garden.pruneSnooze") private var snooze: Double = 0

    var body: some View {
        StageScroll(spacing: Space.m) {
            let intents = remote.brainInfo?.intents ?? []
            let blooming = intents.filter(\.fixed).count
            let wilted = intents.filter { Self.wilt($0) > 0.5 }.count

            GardenCanvas(intents: intents, herbs: herbs.cards, grow: grow, cpu: remote.cpu,
                         auroraUntil: remote.auroraUntil, pruning: pruning, picked: $picked)
                .aspectRatio(0.95, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Tone.stroke, lineWidth: 1))

            let wiltedList = intents.filter { Self.wilt($0) > 0.5 }
            if !wiltedList.isEmpty, pruning == nil, Date().timeIntervalSince1970 > snooze {
                pruneCard(wiltedList)
            }

            if let h = herbs.cards.first(where: { $0.id == picked }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                    if !h.water.isEmpty { Text(h.water).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.6)) }
                    if !h.light.isEmpty { Text(h.light).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.6)) }
                    Text("del herbario").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.leaf)
                }
                .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
                chip("\(intents.count + herbs.cards.count)", "plantas")
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

    /// La propuesta mensual de podar lo que ya no usas.
    private func pruneCard(_ list: [BrainIntentInfo]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scissors").font(.system(size: 18, weight: .bold)).foregroundStyle(Tone.onEmber)
                .frame(width: 40, height: 40).background(Circle().fill(Tone.ember))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(list.count) planta\(list.count == 1 ? "" : "s") marchita\(list.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                Text("hace tiempo que no las usas").font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            Button("luego") {
                snooze = Date().addingTimeInterval(30 * 86_400).timeIntervalSince1970
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.55)).frame(minWidth: 44, minHeight: 44)
            Button {
                prune(list)
            } label: {
                Text("podar").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Tone.onEmber)
                    .padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(Tone.ember))
            }
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tone.key))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Tijeras que cruzan el jardín, hojas que caen y, al terminar, se olvidan de verdad.
    private func prune(_ list: [BrainIntentInfo]) {
        Detents.shared.press()
        withAnimation { pruning = Date() }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            for i in list { remote.send(.brainForget(intent: i.id)) }
            snooze = Date().addingTimeInterval(30 * 86_400).timeIntervalSince1970
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .seconds(0.4))
            remote.send(.brainInfo)
            withAnimation { pruning = nil }
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
    let herbs: [HerbCard]
    let grow: Double
    let cpu: Double
    let auroraUntil: Date
    let pruning: Date?
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
                sky(&ctx, size, t)
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
                    if i.graft != nil { graftPlant(&ctx, i, at: spot(i, idx, list.count, size), size: size, t: t) }
                    else { plant(&ctx, i, at: spot(i, idx, list.count, size), size: size, t: t) }
                }
                for (k, h) in herbs.enumerated() { pot(&ctx, h, at: herbSpot(k, herbs.count, size), t: t) }
                if let start = pruning { shears(&ctx, size, t - start.timeIntervalSinceReferenceDate) }
            }
            .overlay { taps }
        }
    }

    private func herbSpot(_ k: Int, _ n: Int, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (Double(k) + 1) / Double(n + 1), y: size.height * 0.965)
    }

    // MARK: Cielo

    /// El cielo es el estado del Mac: tormenta si el procesador va a tope, despejado
    /// con estrellas si descansa, y aurora cuando acaba de terminar algo largo.
    private func sky(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        let load = min(1, max(0, cpu))
        let dark = 0.10 + 0.05 * load
        let top = Color(red: dark * 0.9, green: dark, blue: dark + 0.05 - 0.04 * load)
        let horizon = Color(red: 0.20 - 0.06 * load, green: 0.13 + 0.02 * load, blue: 0.16 + 0.02 * load)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [top, horizon]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.6)))

        // Estrellas y luna cuando está tranquilo.
        if load < 0.5 {
            let clear = 1 - load * 2
            for k in 0..<36 {
                let x = unit("s\(k)", 1) * size.width, y = unit("s\(k)", 2) * size.height * 0.5
                let tw = 0.35 + 0.35 * sin(t * (0.8 + unit("s\(k)", 3)) + Double(k))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(tw * clear)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.8, y: size.height * 0.08, width: 26, height: 26)),
                     with: .color(Color(red: 0.98, green: 0.95, blue: 0.85).opacity(0.85 * clear)))
        }

        // Aurora: cintas verdes y violetas que ondulan arriba.
        let auroraLeft = auroraUntil.timeIntervalSinceNow
        if auroraLeft > 0 {
            let fade = min(1, auroraLeft / 3, (20 - auroraLeft) / 2 + 0.2)
            for (k, c) in [Color(red: 0.3, green: 1.0, blue: 0.6), Color(red: 0.4, green: 0.8, blue: 1.0), Color(red: 0.7, green: 0.4, blue: 1.0)].enumerated() {
                var band = Path()
                let base = size.height * (0.16 + 0.07 * Double(k))
                band.move(to: CGPoint(x: 0, y: base))
                for x in stride(from: 0.0, through: size.width, by: 8) {
                    let y = base + sin(x / 38 + t * (0.7 + 0.2 * Double(k)) + Double(k)) * 16 + sin(x / 90 - t * 0.4) * 10
                    band.addLine(to: CGPoint(x: x, y: y))
                }
                band.addLine(to: CGPoint(x: size.width, y: base + 70)); band.addLine(to: CGPoint(x: 0, y: base + 70)); band.closeSubpath()
                ctx.fill(band, with: .linearGradient(Gradient(colors: [c.opacity(0.55 * fade), .clear]),
                                                     startPoint: CGPoint(x: 0, y: base - 10), endPoint: CGPoint(x: 0, y: base + 70)))
            }
        }

        // Nubes: más y más oscuras cuanto más trabaja el procesador.
        let clouds = Int((load * 7).rounded())
        for k in 0..<clouds {
            let speed = 6 + unit("c\(k)", 1) * 10
            let x = (unit("c\(k)", 2) * size.width + t * speed).truncatingRemainder(dividingBy: size.width + 160) - 80
            let y = size.height * (0.06 + 0.32 * unit("c\(k)", 3))
            let shade = 0.22 + 0.10 * (1 - load)
            let col = Color(red: shade, green: shade, blue: shade + 0.03).opacity(0.85)
            for b in 0..<4 {
                let r = 22 + Double(b % 2) * 10 + unit("c\(k)", 4 + b) * 8
                ctx.fill(Path(ellipseIn: CGRect(x: x + Double(b) * 26 - r, y: y - r * 0.6, width: r * 2, height: r * 1.2)), with: .color(col))
            }
        }

        // Lluvia cuando va a tope.
        if load > 0.7 {
            let amount = Int((load - 0.7) / 0.3 * 46) + 10
            for k in 0..<amount {
                let x = unit("r\(k)", 1) * size.width
                let y = (unit("r\(k)", 2) * size.height + t * (260 + unit("r\(k)", 3) * 120)).truncatingRemainder(dividingBy: size.height * 0.8)
                var drop = Path()
                drop.move(to: CGPoint(x: x, y: y)); drop.addLine(to: CGPoint(x: x - 3, y: y + 11))
                ctx.stroke(drop, with: .color(Color(red: 0.6, green: 0.75, blue: 1.0).opacity(0.5)), lineWidth: 1.2)
            }
        }
    }

    // MARK: Injerto, maceta y poda

    /// Dos ramas de un mismo tronco: las dos órdenes que haces siempre seguidas.
    private func graftPlant(_ ctx: inout GraphicsContext, _ i: BrainIntentInfo, at base: CGPoint, size: CGSize, t: TimeInterval) {
        let g = min(1, max(0, grow * 1.25 - unit(i.id, 5) * 0.25))
        let wilt = GardenPage.wilt(i)
        let h = 96 * g * (size.height / 380)
        let fork = CGPoint(x: base.x, y: base.y - h * 0.45)
        let green = Color(hue: 0.33 - wilt * 0.2, saturation: 0.55 - wilt * 0.35, brightness: 0.78 - wilt * 0.3)
        let sway = sin(t * 0.9 + unit(i.id, 6) * 6.28) * 4
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - 18, y: base.y - 3, width: 36, height: 8)), with: .color(.black.opacity(0.3)))
        var trunk = Path(); trunk.move(to: base); trunk.addLine(to: fork)
        ctx.stroke(trunk, with: .color(green), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        for side in [-1.0, 1.0] {
            let tip = CGPoint(x: fork.x + side * 26 * g + sway, y: base.y - h)
            var branch = Path(); branch.move(to: fork)
            branch.addQuadCurve(to: tip, control: CGPoint(x: fork.x + side * 4, y: fork.y - h * 0.3))
            ctx.stroke(branch, with: .color(green), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let petal = Color(hue: 0.9 + unit(i.id, side > 0 ? 8 : 9) * 0.15, saturation: 0.5, brightness: 0.95 - wilt * 0.4)
            for k in 0..<6 {
                var c = ctx
                c.translateBy(x: tip.x, y: tip.y); c.rotate(by: .degrees(Double(k) * 60 + t * 6))
                c.fill(Path(ellipseIn: CGRect(x: -3.5, y: -13 * g - 1, width: 7, height: 12 * g)), with: .color(petal))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)), with: .color(Tone.ember))
        }
        // El nudo del injerto.
        ctx.stroke(Path(ellipseIn: CGRect(x: fork.x - 6, y: fork.y - 6, width: 12, height: 12)), with: .color(Tone.ember.opacity(0.8)), lineWidth: 2)
        if picked == i.id {
            ctx.stroke(Path(ellipseIn: CGRect(x: base.x - 40, y: base.y - h - 14, width: 80, height: h + 26)),
                       with: .color(Tone.ember.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
    }

    /// Una planta del herbario, en su maceta y con el tono de su foto.
    private func pot(_ ctx: inout GraphicsContext, _ h: HerbCard, at p: CGPoint, t: TimeInterval) {
        let sway = sin(t * 1.1 + h.hue * 9) * 3
        let color = Color(hue: h.hue, saturation: 0.5, brightness: 0.9)
        var stem = Path(); stem.move(to: CGPoint(x: p.x, y: p.y - 10)); stem.addQuadCurve(to: CGPoint(x: p.x + sway, y: p.y - 44), control: CGPoint(x: p.x - sway, y: p.y - 26))
        ctx.stroke(stem, with: .color(Color(hue: 0.33, saturation: 0.5, brightness: 0.7)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        for k in 0..<6 {
            var c = ctx
            c.translateBy(x: p.x + sway, y: p.y - 46); c.rotate(by: .degrees(Double(k) * 60 + t * 5))
            c.fill(Path(ellipseIn: CGRect(x: -3.5, y: -15, width: 7, height: 13)), with: .color(color))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x + sway - 4, y: p.y - 50, width: 8, height: 8)), with: .color(Tone.ember))
        var potShape = Path()
        potShape.move(to: CGPoint(x: p.x - 13, y: p.y - 10)); potShape.addLine(to: CGPoint(x: p.x + 13, y: p.y - 10))
        potShape.addLine(to: CGPoint(x: p.x + 9, y: p.y + 6)); potShape.addLine(to: CGPoint(x: p.x - 9, y: p.y + 6)); potShape.closeSubpath()
        ctx.fill(potShape, with: .color(Color(red: 0.62, green: 0.34, blue: 0.24)))
        if picked == h.id {
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 26, y: p.y - 66, width: 52, height: 82)), with: .color(Tone.leaf.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
    }

    /// Tijeras que cruzan el jardín mientras caen las hojas podadas.
    private func shears(_ ctx: inout GraphicsContext, _ size: CGSize, _ dt: TimeInterval) {
        let p = min(1, max(0, dt / 2.4))
        let x = -30 + (size.width + 60) * p
        let y = size.height * 0.62 + sin(p * 14) * 8
        for k in 0..<22 {
            let start = unit("p\(k)", 1) * 0.7
            let q = min(1, max(0, (p - start) / 0.3))
            guard q > 0 else { continue }
            let lx = size.width * (0.08 + 0.84 * unit("p\(k)", 2)) + sin(q * 9 + Double(k)) * 14
            let ly = size.height * 0.5 + q * size.height * 0.42
            var c = ctx
            c.translateBy(x: lx, y: ly); c.rotate(by: .degrees(q * 260 + Double(k) * 30))
            c.fill(LeafShape().path(in: CGRect(x: -6, y: -12, width: 12, height: 22)),
                   with: .color(Color(hue: 0.12, saturation: 0.5, brightness: 0.6).opacity(1 - q * 0.6)))
        }
        var s = ctx
        s.translateBy(x: x, y: y)
        let blade = Path(CGRect(x: -3, y: -22, width: 6, height: 24))
        let open = 0.3 + 0.25 * abs(sin(p * 22))
        for side in [-1.0, 1.0] {
            var b = s; b.rotate(by: .radians(side * open)); b.fill(blade, with: .color(Color(white: 0.9)))
        }
        s.fill(Path(ellipseIn: CGRect(x: -7, y: -3, width: 14, height: 14)), with: .color(Tone.ember))
    }

    /// Zonas táctiles invisibles sobre cada planta.
    private var taps: some View {
        GeometryReader { geo in
            let list = intents.sorted { $0.uses < $1.uses }
            ForEach(Array(herbs.enumerated()), id: \.element.id) { k, h in
                let p = herbSpot(k, herbs.count, geo.size)
                Color.clear.frame(width: 56, height: 80).contentShape(Rectangle())
                    .position(x: p.x, y: p.y - 26)
                    .onTapGesture {
                        Haptic.tap()
                        picked = picked == h.id ? nil : h.id
                    }
            }
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
