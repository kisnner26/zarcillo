import AppKit
import SwiftUI

/// Aviso flotante bajo la barra de menús, compacto: un anillo de luz con el
/// número y un arco de marcas que se encienden con el valor. Mientras está a la
/// vista, las cuatro esquinas de la pantalla brillan con el color del tema.
@MainActor
final class HUD: ObservableObject {
    enum Content: Equatable {
        case level(LevelKind, Double)
        case message(String, symbol: String?, icon: NSImage?)
    }

    @Published private(set) var content: Content?
    @Published private(set) var visible = false
    private var panel: NSPanel?
    private var glow: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 230, height: 190)

    func showLevel(_ kind: LevelKind, _ value: Double) {
        show(.level(kind, value))
    }

    func showMessage(_ text: String, symbol: String?, icon: NSImage? = nil) {
        show(.message(text, symbol: symbol, icon: icon))
    }

    private func show(_ c: Content) {
        content = c
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let p = panel ?? makePanel(content: AnyView(HUDView(hud: self)))
        panel = p
        let g = glow ?? makePanel(content: AnyView(CornerGlow(hud: self)))
        glow = g
        if let s = screen {
            p.setFrame(NSRect(x: s.frame.minX + 18, y: s.visibleFrame.maxY - size.height - 4,
                              width: size.width, height: size.height), display: false)
            g.setFrame(s.frame, display: false)
        }
        g.orderFrontRegardless()
        p.orderFrontRegardless()
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { visible = true }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.45)) { self.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !self.visible else { return }
                self.panel?.orderOut(nil)
                self.glow?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    /// Paneles transparentes que no roban clics ni el foco.
    private func makePanel(content: AnyView) -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: content)
        return p
    }
}

// MARK: - Esquinas

/// Las cuatro esquinas de la pantalla se encienden con el acento. Con volumen o
/// brillo, más fuerte cuanto más alto el valor.
private struct CornerGlow: View {
    @ObservedObject var hud: HUD
    private let corners: [UnitPoint] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    var body: some View {
        let strength: Double = {
            if case .level(_, let v)? = hud.content { return 0.4 + 0.4 * v }
            return 0.4
        }()
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) * 0.42
            ZStack {
                ForEach(corners.indices, id: \.self) { i in
                    RadialGradient(colors: [MacTone.ember.opacity(strength), MacTone.ember.opacity(strength * 0.25), .clear],
                                   center: corners[i], startRadius: 0, endRadius: r)
                }
            }
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .opacity(hud.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: strength)
    }
}

// MARK: - Aviso

struct HUDView: View {
    @ObservedObject var hud: HUD

    var body: some View {
        Group {
            switch hud.content {
            case .level(let kind, let value)?:
                CompactDial(kind: kind, value: value)
            case .message(let text, let symbol, let icon)?:
                MessageChip(text: text, symbol: symbol, icon: icon)
            case nil:
                Color.clear
            }
        }
        .scaleEffect(hud.visible ? 1 : 0.7, anchor: .topLeading)
        .blur(radius: hud.visible ? 0 : 8)
        .opacity(hud.visible ? 1 : 0)
        .frame(width: 230, height: 190, alignment: .topLeading)
    }
}

/// Anillo con el número y un arco de marcas alrededor; la marca del valor lleva
/// un triángulo, como un dial.
private struct CompactDial: View {
    let kind: LevelKind
    let value: Double
    private let ticks = 12
    private let start = -60.0     // grados; 0 = derecha, crece en sentido horario
    private let sweep = 210.0
    private let radius: CGFloat = 62

    var body: some View {
        let lit = Int((value * Double(ticks - 1)).rounded())
        let va = (start + sweep * value) * .pi / 180
        ZStack {
            ForEach(0..<ticks, id: \.self) { i in
                let on = value > 0 && i <= lit
                let a = (start + sweep * Double(i) / Double(ticks - 1)) * .pi / 180
                Capsule()
                    .fill(on ? MacTone.ember : Color.white.opacity(0.22))
                    .frame(width: 4, height: 13)
                    .shadow(color: on ? MacTone.ember.opacity(0.9) : .clear, radius: 5)
                    .rotationEffect(.radians(a + .pi / 2))
                    .offset(x: cos(a) * radius, y: sin(a) * radius)
            }
            // Triángulo en el valor actual.
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(MacTone.ember)
                .rotationEffect(.radians(va - .pi / 2))
                .offset(x: cos(va) * (radius + 15), y: sin(va) * (radius + 15))
                .shadow(color: MacTone.ember, radius: 4)

            // El anillo central.
            ZStack {
                Circle().fill(Color.black.opacity(0.72))
                Circle().stroke(MacTone.ember, lineWidth: 2.5)
                    .shadow(color: MacTone.ember, radius: 8)
                    .shadow(color: MacTone.ember.opacity(0.6), radius: 18)
                VStack(spacing: -1) {
                    Image(systemName: kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value))
                }
                .foregroundStyle(MacTone.ember)
            }
            .frame(width: 50, height: 50)
        }
        .frame(width: 170, height: 170)
        .animation(.spring(duration: 0.28), value: value)
    }
}

private struct MessageChip: View {
    let text: String
    let symbol: String?
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(MacTone.ember, lineWidth: 2)
                    .shadow(color: MacTone.ember, radius: 6)
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(MacTone.ember)
                        .symbolEffect(.bounce, value: text)
                }
            }
            .frame(width: 30, height: 30)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().stroke(MacTone.ember.opacity(0.35), lineWidth: 1))
        .shadow(color: MacTone.ember.opacity(0.35), radius: 12)
        .padding(.top, 8)
    }
}
