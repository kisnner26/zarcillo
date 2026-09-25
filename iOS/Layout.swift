import SwiftUI

/// Medidas que comparten todas las páginas del escenario.
enum StageMetrics {
    /// Aire arriba para el botón de volver; el mismo abajo, para que quede simétrico.
    static let edge: CGFloat = 22
    static let edgeWide: CGFloat = 20
    /// El escenario es "ancho" cuando el iPhone está de lado.
    static func wide(_ size: CGSize) -> Bool { size.width > size.height * 1.15 }
}

/// Una página con una pieza protagonista (un orbe, un radar, un QR…) y sus
/// controles. En vertical van uno sobre otro; con el iPhone de lado, uno junto
/// al otro. Siempre centrada, con el mismo aire arriba y abajo, y se desplaza
/// solo si no cabe.
struct StagePage<Hero: View, Controls: View>: View {
    /// Recibe el lado disponible para la pieza protagonista.
    @ViewBuilder var hero: (CGFloat) -> Hero
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        GeometryReader { geo in
            let wide = StageMetrics.wide(geo.size)
            let edge = wide ? StageMetrics.edgeWide : StageMetrics.edge
            let side = wide
                ? max(120, min(geo.size.height - edge * 2, geo.size.width * 0.42))
                : max(120, min(geo.size.width - Space.m * 2, geo.size.height * 0.42, 250))
            ScrollView {
                Group {
                    if wide {
                        HStack(spacing: Space.l) {
                            hero(side).frame(maxWidth: .infinity)
                            VStack(spacing: Space.m) { controls() }
                                .frame(maxWidth: 400)
                        }
                    } else {
                        VStack(spacing: Space.l) {
                            hero(side)
                            VStack(spacing: Space.m) { controls() }
                        }
                        .frame(maxWidth: 520)
                    }
                }
                .padding(.horizontal, wide ? Space.l : Space.m)
                .padding(.vertical, edge)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Una página de lista o formulario: centrada, con ancho cómodo en horizontal
/// y el mismo aire arriba y abajo.
struct StageScroll<Content: View>: View {
    var spacing: CGFloat = Space.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let wide = StageMetrics.wide(geo.size)
            let edge = wide ? StageMetrics.edgeWide : StageMetrics.edge
            ScrollView {
                VStack(spacing: spacing) { content() }
                    .frame(maxWidth: wide ? 620 : 520)
                    .padding(.horizontal, wide ? Space.l : Space.m)
                    .padding(.vertical, edge)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Texto de ayuda al pie de una página: siempre igual, centrado y discreto.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Tone.ink.opacity(0.45))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// Un interruptor en una tarjeta, con título y detalle.
struct ToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.label(15, .semibold)).foregroundStyle(Tone.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.5))
            }
        }
        .tint(Tone.ember)
        .padding(.horizontal, Space.m).frame(minHeight: 64)
        .glass(20)
    }
}

/// El emblema al inicio de una página: el símbolo dentro de un medallón de vidrio,
/// rodeado por una corona de hojas finas que gira muy despacio.
struct HeroMark: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduce)) { tl in
                let t = reduce ? 0 : tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<10, id: \.self) { k in
                        LeafShape().fill(Tone.moss.opacity(k % 2 == 0 ? 0.55 : 0.3))
                            .frame(width: 7, height: 13)
                            .offset(y: -60)
                            .rotationEffect(.degrees(Double(k) * 36 + t * 4))
                    }
                }
            }
            Circle().fill(.clear).glass(48).frame(width: 96, height: 96)
            Image(systemName: symbol).font(.system(size: 36, weight: .regular))
        }
        .frame(width: 132, height: 132)
    }
}
