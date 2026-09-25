import SwiftUI

/// Cuadrícula de fichas iguales cuya última fila, si queda incompleta, se centra.
/// Así nunca queda una ficha sola pegada a la izquierda.
struct CenteredGrid: Layout {
    var minimum: CGFloat = 92
    var maxColumns = 4
    var spacing: CGFloat = 10

    private func columns(_ width: CGFloat) -> Int {
        max(1, min(maxColumns, Int((width + spacing) / (minimum + spacing))))
    }

    private func cell(_ width: CGFloat, _ cols: Int) -> CGFloat {
        (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
    }

    private func rowHeights(_ subviews: Subviews, cols: Int, cellW: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: cols).map { start in
            subviews[start..<min(start + cols, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (minimum * CGFloat(maxColumns) + spacing * CGFloat(maxColumns - 1))
        let cols = columns(width)
        let rows = rowHeights(subviews, cols: cols, cellW: cell(width, cols))
        let height = rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(bounds.width)
        let w = cell(bounds.width, cols)
        let rows = rowHeights(subviews, cols: cols, cellW: w)
        var y = bounds.minY
        for (r, h) in rows.enumerated() {
            let start = r * cols
            let count = min(cols, subviews.count - start)
            let rowWidth = w * CGFloat(count) + spacing * CGFloat(count - 1)
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for i in start..<start + count {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
                x += w + spacing
            }
            y += h + spacing
        }
    }
}
