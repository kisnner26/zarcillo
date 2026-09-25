import AppKit
import SwiftUI

/// "Un solo aparato": una capa transparente sobre la pantalla del Mac que hace
/// visible lo que llega del iPhone. El iPhone "está" en el borde de abajo: de ahí
/// crece la enredadera al conectarse, salen los zarcillos de luz hacia cada clic y
/// suben hojas al escribir. No roba clics, no sale en capturas ni en la pantalla
/// que ve el iPhone.
@MainActor
final class Bridge {
    enum Kind { case grow, wither, click(CGPoint), leaf(CGFloat), thorns }

    struct Effect: Identifiable {
        let id = UUID()
        let kind: Kind
        let start = Date()
        var life: Double {
            switch kind {
            case .grow: 3.4
            case .wither: 1.6
            case .click: 0.9
            case .leaf: 1.4
            case .thorns: 5.0
            }
        }
    }

    fileprivate final class Model: ObservableObject {
        @Published var effects: [Effect] = []
        var size: CGSize = .zero
        /// La hoja de la barra de menús, en coordenadas de la vista.
        var icon: CGPoint = .zero
    }

    fileprivate let model = Model()
    private var panel: NSPanel?
    private var lastClick = Date.distantPast
    private var lastLeaf = Date.distantPast
    private var sweeper: Timer?

    // MARK: Lo que dispara efectos

    func connected() { add(.grow) }
    func disconnected() { add(.wither) }
    /// El guardián saltó: enredaderas con espinas cubren la pantalla desde los bordes.
    func thorns() { add(.thorns) }

    /// Un clic que vino del iPhone, donde está el cursor.
    func click() {
        let now = Date()
        guard now.timeIntervalSince(lastClick) > 0.08, let screen = screen else { return }
        lastClick = now
        let m = NSEvent.mouseLocation
        add(.click(CGPoint(x: m.x - screen.frame.minX, y: screen.frame.maxY - m.y)))
    }

    /// Una tecla o texto que vino del iPhone.
    func typed() {
        let now = Date()
        guard now.timeIntervalSince(lastLeaf) > 0.07 else { return }
        lastLeaf = now
        add(.leaf(CGFloat.random(in: 0.38...0.62)))
    }

    // MARK: Panel

    private var screen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    private func add(_ kind: Kind) {
        guard let screen else { return }
        let p = panel ?? makePanel()
        panel = p
        if p.frame != screen.frame { p.setFrame(screen.frame, display: false) }
        model.size = screen.frame.size
        model.icon = iconPoint(in: screen) ?? CGPoint(x: screen.frame.width * 0.82, y: 12)
        p.orderFrontRegardless()
        model.effects.append(Effect(kind: kind))
        if model.effects.count > 40 { model.effects.removeFirst(model.effects.count - 40) }
        if sweeper == nil {
            sweeper = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sweep() }
            }
        }
    }

    /// Se quitan los efectos terminados; sin ninguno, el panel se oculta y no dibuja nada.
    private func sweep() {
        let now = Date()
        model.effects.removeAll { now.timeIntervalSince($0.start) > $0.life }
        if model.effects.isEmpty {
            sweeper?.invalidate(); sweeper = nil
            panel?.orderOut(nil)
        }
    }

    /// Dónde está la hoja de Zarcillo en la barra de menús.
    private func iconPoint(in screen: NSScreen) -> CGPoint? {
        guard let w = NSApp.windows.first(where: { $0.className.contains("StatusBar") && $0.isVisible }) else { return nil }
        let f = w.frame
        return CGPoint(x: f.midX - screen.frame.minX, y: screen.frame.maxY - f.midY)
    }

    private func makePanel() -> NSPanel {
        let frame = screen?.frame ?? .zero
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = .none
        let host = fixedHost(BridgeView(model: model))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }
}

private struct BridgeView: View {
    @ObservedObject var model: Bridge.Model

    var body: some View {
        TimelineView(.animation(paused: model.effects.isEmpty)) { tl in
            Canvas { ctx, size in
                let now = tl.date
                // Donde "está" el iPhone: un resplandor cálido en el borde de abajo.
                let live = model.effects.map { max(0, 1 - now.timeIntervalSince($0.start) / $0.life) }.max() ?? 0
                if live > 0 {
                    let o = origin(size), r = size.width * 0.16
                    ctx.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r * 0.55, width: r * 2, height: r * 1.1)),
                             with: .radialGradient(Gradient(colors: [MacTone.ember.opacity(0.35 * live), .clear]),
                                                   center: o, startRadius: 0, endRadius: r))
                }
                for e in model.effects {
                    let t = now.timeIntervalSince(e.start)
                    guard t >= 0, t <= e.life else { continue }
                    switch e.kind {
                    case .grow: vine(&ctx, size, t, withering: false)
                    case .wither: vine(&ctx, size, t, withering: true)
                    case .click(let p): tendril(&ctx, size, to: p, t)
                    case .leaf(let fx): floatingLeaf(&ctx, size, fx, t, seed: e.id.hashValue)
                    case .thorns: thorns(&ctx, size, t)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// El iPhone vive abajo, al centro.
    private func origin(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height + 6) }

    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

    private func bezier(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        let v = 1 - u
        return CGPoint(x: v * v * v * a.x + 3 * v * v * u * c1.x + 3 * v * u * u * c2.x + u * u * u * b.x,
                       y: v * v * v * a.y + 3 * v * v * u * c1.y + 3 * v * u * u * c2.y + u * u * u * b.y)
    }

    private func leaf(_ ctx: inout GraphicsContext, at p: CGPoint, angle: Double, size s: CGFloat, color: Color) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        c.fill(LeafShape().path(in: CGRect(x: -s * 0.3, y: -s, width: s * 0.6, height: s)), with: .color(color))
    }

    // MARK: Conectar / desconectar: la enredadera trepa hasta la hoja de la barra de menús.

    private func vine(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, withering: Bool) {
        let a = origin(size), b = model.icon
        let c1 = CGPoint(x: a.x - size.width * 0.18, y: size.height * 0.55)
        let c2 = CGPoint(x: b.x + size.width * 0.12, y: size.height * 0.28)
        let green = Color(red: 0.55, green: 0.86, blue: 0.62)
        let dry = Color(red: 0.55, green: 0.42, blue: 0.3)
        let grow: Double, alpha: Double, drop: CGFloat
        if withering {
            grow = 1; alpha = max(0, 1 - t / 1.6); drop = CGFloat(ease(t / 1.6)) * 60
        } else {
            grow = ease(t / 1.6); alpha = t < 2.6 ? 1 : max(0, 1 - (t - 2.6) / 0.8); drop = 0
        }
        let color = withering ? dry : green
        let n = 90
        var path = Path()
        var pts: [CGPoint] = []
        for i in 0...Int(Double(n) * grow) {
            let u = Double(i) / Double(n)
            var p = bezier(a, c1, c2, b, u)
            p.x += sin(u * 14 + t * 1.5) * 6 * (1 - u)
            p.y += drop * CGFloat(u)
            pts.append(p)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 10))
        glow.stroke(path, with: .color(color.opacity(0.4 * alpha)), style: StrokeStyle(lineWidth: 22, lineCap: .round))
        ctx.stroke(path, with: .color(color.opacity(0.95 * alpha)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        for (k, i) in stride(from: 6, to: pts.count - 2, by: 7).enumerated() {
            let p = pts[i], q = pts[i - 1]
            let ang = atan2(p.y - q.y, p.x - q.x) + .pi / 2 + (k % 2 == 0 ? 1.0 : -1.0)
            leaf(&ctx, at: p, angle: ang + (withering ? t * 0.8 : 0), size: 30, color: color.opacity(0.92 * alpha))
        }
        // Al llegar, la hoja de la barra de menús destella.
        if !withering, t > 1.5, t < 2.6 {
            let f = (t - 1.5) / 1.1
            let r = 14 + 70 * f
            ctx.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)),
                       with: .color(MacTone.ember.opacity(0.8 * (1 - f))), lineWidth: 2.5)
        }
    }

    // MARK: Clic: un zarcillo de luz del borde de abajo al cursor, y florece.

    private func tendril(_ ctx: inout GraphicsContext, _ size: CGSize, to p: CGPoint, _ t: Double) {
        let a = origin(size)
        let reach = ease(t / 0.28)
        let fade = t < 0.45 ? 1 : max(0, 1 - (t - 0.45) / 0.45)
        let side: CGFloat = p.x > a.x ? -1 : 1
        let c1 = CGPoint(x: a.x + side * 140, y: a.y - (a.y - p.y) * 0.35)
        let c2 = CGPoint(x: p.x - side * 60, y: p.y + 90)
        var path = Path()
        let n = 40
        for i in 0...Int(Double(n) * reach) {
            let q = bezier(a, c1, c2, p, Double(i) / Double(n))
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 8))
        glow.stroke(path, with: .color(MacTone.ember.opacity(0.5 * fade)), style: StrokeStyle(lineWidth: 18, lineCap: .round))
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [MacTone.ember.opacity(0), MacTone.ember.opacity(0.95 * fade)]),
                                               startPoint: a, endPoint: p),
                   style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        // Florece donde cae el clic: una onda y seis pétalos que se abren.
        if t > 0.24 {
            let f = min(1, (t - 0.24) / 0.6)
            let r = 8 + 56 * f
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(MacTone.ember.opacity(0.9 * (1 - f))), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                     with: .color(MacTone.ember.opacity(0.9 * (1 - f))))
            for k in 0..<7 {
                let ang = Double(k) / 7 * 2 * .pi + f * 0.7
                let d = 12 + 34 * f
                leaf(&ctx, at: CGPoint(x: p.x + cos(ang) * d, y: p.y + sin(ang) * d), angle: ang + .pi / 2, size: 18,
                     color: MacTone.ember.opacity(0.9 * (1 - f)))
            }
        }
    }

    // MARK: Escribir: sube una hoja desde el iPhone.

    private func floatingLeaf(_ ctx: inout GraphicsContext, _ size: CGSize, _ fx: CGFloat, _ t: Double, seed: Int) {
        let f = t / 1.4
        let x = size.width * fx + CGFloat(sin(t * 5 + Double(seed % 7))) * 14
        let y = size.height - CGFloat(ease(f)) * size.height * 0.22
        let alpha = f < 0.2 ? f / 0.2 : max(0, 1 - (f - 0.2) / 0.8)
        leaf(&ctx, at: CGPoint(x: x, y: y), angle: sin(t * 4) * 0.6, size: 26,
             color: Color(red: 0.55, green: 0.86, blue: 0.62).opacity(0.85 * alpha))
    }

    // MARK: Guardián: la pantalla se cierra con enredaderas.

    private func thorns(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let grow = ease(t / 1.8)
        let alpha = t < 4.2 ? 1 : max(0, 1 - (t - 4.2) / 0.8)
        // Oscurece hacia los bordes, como si el invernadero se cerrara.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [.clear, Color.black.opacity(0.55 * grow * alpha)]),
                                       center: CGPoint(x: size.width / 2, y: size.height / 2),
                                       startRadius: size.width * 0.18, endRadius: size.width * 0.7))
        let vine = Color(red: 0.28, green: 0.52, blue: 0.34)
        let n = 16
        for k in 0..<n {
            // Salen de puntos repartidos por el borde y se enroscan hacia el centro.
            let f = Double(k) / Double(n)
            let per = 2 * (size.width + size.height)
            var d = f * per
            let start: CGPoint
            if d < size.width { start = CGPoint(x: d, y: 0) }
            else if (d - size.width) < size.height { d -= size.width; start = CGPoint(x: size.width, y: d) }
            else if (d - size.width - size.height) < size.width { d -= size.width + size.height; start = CGPoint(x: size.width - d, y: size.height) }
            else { d -= 2 * size.width + size.height; start = CGPoint(x: 0, y: size.height - d) }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = 0.42 + 0.12 * sin(Double(k) * 1.7)
            let end = CGPoint(x: start.x + (center.x - start.x) * reach, y: start.y + (center.y - start.y) * reach)
            let bend: CGFloat = k % 2 == 0 ? 1 : -1
            let mid = CGPoint(x: (start.x + end.x) / 2 + bend * (end.y - start.y) * 0.3, y: (start.y + end.y) / 2 - bend * (end.x - start.x) * 0.3)
            var path = Path()
            let steps = Int(60 * grow)
            guard steps > 1 else { continue }
            var pts: [CGPoint] = []
            for i in 0...steps {
                let u = Double(i) / 60
                let v = 1 - u
                let p = CGPoint(x: v * v * start.x + 2 * v * u * mid.x + u * u * end.x,
                                y: v * v * start.y + 2 * v * u * mid.y + u * u * end.y)
                pts.append(p)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(vine.opacity(0.95 * alpha)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            for i in stride(from: 5, to: pts.count - 1, by: 6) {
                let p = pts[i], q = pts[i - 1]
                let ang = atan2(p.y - q.y, p.x - q.x)
                // Espinas: triángulos pequeños a los lados; y alguna hoja.
                for s in [-1.0, 1.0] {
                    var th = Path()
                    let base = CGPoint(x: p.x + cos(ang + s * .pi / 2) * 3, y: p.y + sin(ang + s * .pi / 2) * 3)
                    th.move(to: CGPoint(x: base.x + cos(ang) * 4, y: base.y + sin(ang) * 4))
                    th.addLine(to: CGPoint(x: base.x - cos(ang) * 4, y: base.y - sin(ang) * 4))
                    th.addLine(to: CGPoint(x: p.x + cos(ang + s * .pi / 2) * 12, y: p.y + sin(ang + s * .pi / 2) * 12))
                    th.closeSubpath()
                    ctx.fill(th, with: .color(Color(red: 0.62, green: 0.2, blue: 0.2).opacity(0.9 * alpha)))
                }
                if i % 12 == 5 {
                    leaf(&ctx, at: p, angle: ang + .pi / 2 + (i % 24 == 5 ? 0.8 : -0.8), size: 26, color: vine.opacity(0.95 * alpha))
                }
            }
        }
    }
}
