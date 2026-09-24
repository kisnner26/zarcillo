import AppKit
import SwiftUI

/// Aviso flotante en la esquina superior izquierda, bajo la barra de menús:
/// el dial de volumen o brillo mientras se gira, o la app que se está abriendo.
@MainActor
final class HUD: ObservableObject {
    enum Content {
        case level(LevelKind, Double)
        case message(String, symbol: String?, icon: NSImage?)
    }

    @Published private(set) var content: Content?
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 320, height: 190)

    func showLevel(_ kind: LevelKind, _ value: Double) {
        show(.level(kind, value))
    }

    func showMessage(_ text: String, symbol: String?, icon: NSImage? = nil) {
        show(.message(text, symbol: symbol, icon: icon))
    }

    private func show(_ c: Content) {
        content = c
        let p = panel ?? makePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let s = screen {
            p.setFrameOrigin(NSPoint(x: s.frame.minX + 16, y: s.visibleFrame.maxY - size.height - 8))
        }
        if !p.isVisible || p.alphaValue < 1 {
            p.alphaValue = 1
            p.orderFrontRegardless()
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: HUDView(hud: self))
        panel = p
        return p
    }
}

private let glow = Color(red: 0.28, green: 0.62, blue: 1.0)

struct HUDView: View {
    @ObservedObject var hud: HUD

    var body: some View {
        Group {
            switch hud.content {
            case .level(let kind, let value)?:
                LevelDial(kind: kind, value: value)
            case .message(let text, let symbol, let icon)?:
                MessagePill(text: text, symbol: symbol, icon: icon)
            case nil:
                Color.clear
            }
        }
        .padding(12)
        .frame(width: 320, height: 190, alignment: .topLeading)
    }
}

private struct LevelDial: View {
    let kind: LevelKind
    let value: Double
    private let ticks = 36

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.82))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            ForEach(0..<ticks, id: \.self) { i in
                let t = Double(i) / Double(ticks - 1)
                let on = t <= value + 0.0001
                Capsule()
                    .fill(on ? glow : Color.white.opacity(0.18))
                    .frame(width: 3, height: i % 5 == 0 ? 13 : 8)
                    .shadow(color: on ? glow.opacity(0.9) : .clear, radius: 4)
                    .offset(y: -66)
                    .rotationEffect(.degrees(135 + 270 * t + 90))
            }
            VStack(spacing: 1) {
                Image(systemName: kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .frame(width: 68, height: 68)
            .background(Circle().stroke(glow, lineWidth: 2).shadow(color: glow, radius: 8))
        }
        .frame(width: 160, height: 160)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

private struct MessagePill: View {
    let text: String
    let symbol: String?
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 34, height: 34)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(glow)
                    .frame(width: 30)
            }
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().stroke(glow.opacity(0.35), lineWidth: 1))
        .shadow(color: glow.opacity(0.25), radius: 10)
    }
}
