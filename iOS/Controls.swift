import SwiftUI
import UIKit

// MARK: - Interruptor

/// Interruptor de invernadero: una cápsula de vidrio y una perilla con una hoja que
/// gira media vuelta al encenderse. Sustituye al interruptor del sistema en toda la app.
struct LeafToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.label
            Spacer(minLength: 0)
            LeafSwitch(isOn: configuration.$isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { flip(configuration) }
    }

    private func flip(_ c: Configuration) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        withAnimation(.spring(duration: 0.35, bounce: 0.35)) { c.isOn.toggle() }
    }
}

struct LeafSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Tone.ember, Tone.emberDeep], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.25 : 0.14), lineWidth: 0.8))
                .shadow(color: isOn ? Tone.ember.opacity(0.45) : .clear, radius: 8)
            Circle()
                .fill(isOn ? Color.white : Color.white.opacity(0.85))
                .overlay(
                    LeafShape().fill(isOn ? Tone.ember : Tone.moss)
                        .frame(width: 8, height: 13)
                        .rotationEffect(.degrees(isOn ? 30 : -150))
                )
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .padding(3)
        }
        .frame(width: 54, height: 32)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "activado" : "desactivado")
    }
}

// MARK: - Deslizador

/// Deslizador enredadera: la parte llena es un tallo del acento con hojas, y el mango
/// es una yema de vidrio. Vibra suave en cada décimo del recorrido.
struct VineSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @State private var lastTick = -1

    init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1, step: Double? = nil,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    private var fraction: Double {
        let f = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
        return min(1, max(0, f))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, knob: CGFloat = dragging ? 30 : 26
            let x = CGFloat(fraction) * (w - knob) + knob / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                // El tallo con sus hojas, hasta el mango.
                Canvas { ctx, size in
                    let y = size.height / 2
                    var stem = Path()
                    stem.move(to: CGPoint(x: 2, y: y))
                    stem.addLine(to: CGPoint(x: x, y: y))
                    ctx.stroke(stem, with: .color(Tone.ember), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    var k = 0
                    var lx: CGFloat = 16
                    while lx < x - 12 {
                        var c = ctx
                        c.translateBy(x: lx, y: y)
                        c.rotate(by: .degrees(k % 2 == 0 ? -55 : 235))
                        c.fill(LeafShape().path(in: CGRect(x: -3, y: -10, width: 6, height: 10)), with: .color(Tone.ember.opacity(0.85)))
                        lx += 22; k += 1
                    }
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().fill(Tone.ember).frame(width: knob * 0.34))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .shadow(color: Tone.ember.opacity(dragging ? 0.6 : 0), radius: 10)
                    .position(x: x, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging {
                        withAnimation(.spring(duration: 0.2)) { dragging = true }
                        onEditingChanged(true)
                    }
                    set(Double((g.location.x - knob / 2) / (w - knob)))
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.25)) { dragging = false }
                    onEditingChanged(false)
                })
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) %")
        .accessibilityAdjustableAction { dir in
            let d = (range.upperBound - range.lowerBound) / 10
            value = min(range.upperBound, max(range.lowerBound, value + (dir == .increment ? d : -d)))
        }
    }

    private func set(_ f: Double) {
        var v = range.lowerBound + min(1, max(0, f)) * (range.upperBound - range.lowerBound)
        if let step { v = (v / step).rounded() * step }
        value = min(range.upperBound, max(range.lowerBound, v))
        let tick = Int(fraction * 10)
        if tick != lastTick {
            lastTick = tick
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Más / menos

/// Selector de más y menos: dos botones de vidrio y el valor en medio.
struct LeafStepper<Label: View>: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: Space.s) {
            label()
            Spacer(minLength: 0)
            button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
    }

    private func button(_ symbol: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(duration: 0.25)) { run() }
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Tone.ink : Tone.ink.opacity(0.3))
                .frame(width: 40, height: 40).glass(20)
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
    }
}
