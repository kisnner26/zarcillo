import SwiftUI

/// El borde de la pantalla brilla mientras el cerebro trabaja: acento al pensar,
/// ámbar si espera tu permiso, verde (o rojo) un instante al terminar.
struct AuraEdge: View {
    @EnvironmentObject private var remote: Remote
    @State private var color: Color = .clear
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let spin = Angle.degrees((t * 80).truncatingRemainder(dividingBy: 360))
            let gradient = AngularGradient(colors: [color, color.opacity(0.2), color, color.opacity(0.2), color], center: .center, angle: spin)
            let shape = RoundedRectangle(cornerRadius: 48, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 16).blur(radius: 14)
                shape.strokeBorder(gradient, lineWidth: 4).blur(radius: 3)
            }
            .opacity(visible ? 0.75 + 0.25 * sin(t * 3) : 0)
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: remote.brain) { _, state in update(state) }
    }

    private func update(_ state: BrainState) {
        hideTask?.cancel()
        switch state {
        case .idle:
            withAnimation(.easeOut(duration: 0.5)) { visible = false }
        case .thinking:
            show(Tone.ember)
        case .confirm:
            show(Color(red: 1.0, green: 0.72, blue: 0.2))
        case .done(let d):
            show(d.ok ? Color(red: 0.4, green: 0.9, blue: 0.5) : Color(red: 0.95, green: 0.3, blue: 0.3))
            hideTask = Task {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.6)) { visible = false }
            }
        }
    }

    private func show(_ c: Color) {
        withAnimation(.easeInOut(duration: 0.4)) {
            color = c
            visible = true
        }
    }
}
