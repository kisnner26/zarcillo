import SwiftUI

/// Iconos propios de Zarcillo, dibujados con hojas, tallos y semillas en vez
/// de los símbolos genéricos del sistema. Se usan como cualquier icono: toman
/// el color de `foregroundStyle` y el tamaño del marco.
enum Glyph: String, CaseIterable {
    case close, expand, harvest, pad, deck, apps, music, screen, more, back

    func draw(_ ctx: inout GraphicsContext, _ s: CGFloat, _ color: GraphicsContext.Shading) {
        let line = StrokeStyle(lineWidth: max(1.4, s * 0.085), lineCap: .round, lineJoin: .round)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        /// Hoja centrada en (x, y), de largo `l` (fracción de s), girada `deg` grados (0 = punta arriba).
        func leaf(_ x: CGFloat, _ y: CGFloat, _ l: CGFloat, _ deg: Double, width: CGFloat = 0.5) {
            var c = ctx
            c.translateBy(x: x * s, y: y * s)
            c.rotate(by: .degrees(deg))
            let h = l * s
            c.fill(LeafShape().path(in: CGRect(x: -h * width / 2, y: -h / 2, width: h * width, height: h)), with: color)
        }
        func stroke(_ build: (inout Path) -> Void) {
            var path = Path()
            build(&path)
            ctx.stroke(path, with: color, style: line)
        }

        switch self {
        case .close:
            // Dos hojas cruzadas.
            leaf(0.5, 0.5, 0.92, 45, width: 0.3)
            leaf(0.5, 0.5, 0.92, -45, width: 0.3)
        case .expand:
            // Cuatro hojas que salen hacia las esquinas.
            for (x, y, d) in [(0.25, 0.25, -45.0), (0.75, 0.25, 45.0), (0.25, 0.75, -135.0), (0.75, 0.75, 135.0)] {
                leaf(CGFloat(x), CGFloat(y), 0.42, d, width: 0.46)
            }
        case .back:
            // Una hoja que apunta a la izquierda sobre su tallo.
            // Dos hojas en ángulo: una flecha hacia atrás.
            leaf(0.56, 0.33, 0.46, 45, width: 0.34)
            leaf(0.56, 0.67, 0.46, 135, width: 0.34)
        case .harvest:
            // Una hoja dentro de un marco de selección punteado.
            var frame = Path(roundedRect: CGRect(x: 0.08 * s, y: 0.08 * s, width: 0.84 * s, height: 0.84 * s), cornerRadius: 0.18 * s)
            frame = frame.strokedPath(StrokeStyle(lineWidth: max(1.2, s * 0.07), lineCap: .round, dash: [s * 0.12, s * 0.1]))
            ctx.fill(frame, with: color)
            leaf(0.5, 0.52, 0.5, 30, width: 0.56)
        case .pad:
            // Superficie del trackpad con una hoja donde se toca y su onda.
            stroke { $0.addRoundedRect(in: CGRect(x: 0.1 * s, y: 0.16 * s, width: 0.8 * s, height: 0.68 * s), cornerSize: CGSize(width: 0.16 * s, height: 0.16 * s)) }
            leaf(0.5, 0.5, 0.36, 20, width: 0.56)
        case .deck:
            // Cuatro hojas en rejilla: botones.
            for (x, y) in [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)] {
                ctx.fill(Path(roundedRect: CGRect(x: (CGFloat(x) - 0.19) * s, y: (CGFloat(y) - 0.19) * s, width: 0.38 * s, height: 0.38 * s),
                              cornerRadius: 0.1 * s), with: color)
            }
            // Una hoja calada en el botón de arriba a la derecha: el que "está vivo".
            var c = ctx
            c.blendMode = .destinationOut
            c.translateBy(x: 0.72 * s, y: 0.28 * s)
            c.rotate(by: .degrees(25))
            c.fill(LeafShape().path(in: CGRect(x: -0.07 * s, y: -0.13 * s, width: 0.14 * s, height: 0.26 * s)), with: .color(.black))
        case .apps:
            // Brote en su maceta.
            var pot = Path()
            pot.move(to: p(0.24, 0.62)); pot.addLine(to: p(0.76, 0.62)); pot.addLine(to: p(0.67, 0.92)); pot.addLine(to: p(0.33, 0.92)); pot.closeSubpath()
            ctx.fill(pot, with: color)
            stroke { $0.move(to: p(0.5, 0.62)); $0.addQuadCurve(to: p(0.5, 0.2), control: p(0.44, 0.4)) }
            leaf(0.34, 0.34, 0.34, -55, width: 0.55)
            leaf(0.66, 0.26, 0.34, 55, width: 0.55)
        case .music:
            // Una corchea cuya bandera es una hoja.
            ctx.fill(Path(ellipseIn: CGRect(x: 0.16 * s, y: 0.64 * s, width: 0.34 * s, height: 0.26 * s)), with: color)
            stroke { $0.move(to: p(0.47, 0.76)); $0.addLine(to: p(0.47, 0.14)) }
            leaf(0.66, 0.3, 0.42, 130, width: 0.52)
        case .screen:
            // Pantalla con un brote adentro.
            stroke { $0.addRoundedRect(in: CGRect(x: 0.08 * s, y: 0.14 * s, width: 0.84 * s, height: 0.56 * s), cornerSize: CGSize(width: 0.1 * s, height: 0.1 * s)) }
            stroke { $0.move(to: p(0.34, 0.88)); $0.addLine(to: p(0.66, 0.88)) }
            stroke { $0.move(to: p(0.5, 0.7)); $0.addLine(to: p(0.5, 0.86)) }
            leaf(0.5, 0.42, 0.3, 25, width: 0.56)
        case .more:
            // Tres semillas.
            for (i, d) in [-20.0, 0, 20].enumerated() {
                var c = ctx
                c.translateBy(x: (0.2 + 0.3 * CGFloat(i)) * s, y: 0.5 * s)
                c.rotate(by: .degrees(d))
                c.fill(Path(ellipseIn: CGRect(x: -0.09 * s, y: -0.13 * s, width: 0.18 * s, height: 0.26 * s)), with: color)
            }
        }
    }
}

/// Un icono propio, del tamaño que se le dé y con el color del estilo actual.
struct GlyphView: View {
    let glyph: Glyph
    var size: CGFloat = 20

    init(_ glyph: Glyph, size: CGFloat = 20) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Canvas { ctx, box in
            glyph.draw(&ctx, min(box.width, box.height), .style(.foreground))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
