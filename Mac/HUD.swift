import AppKit
import SwiftUI

/// Aviso flotante bajo la barra de menús, en la cerámica y el color del iPhone:
/// la perilla con su zarcillo mientras cambias volumen o brillo, o una pastilla
/// con lo que acaba de pasar. Entra con un resorte y se va desvaneciéndose.
@MainActor
final class HUD: ObservableObject {
    enum Content: Equatable {
        case level(LevelKind, Double)
        case message(String, symbol: String?, icon: NSImage?)
    }

    @Published private(set) var content: Content?
    @Published private(set) var visible = false
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 360, height: 220)

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
            p.setFrameOrigin(NSPoint(x: s.frame.minX + 14, y: s.visibleFrame.maxY - size.height - 6))
        }
        p.orderFrontRegardless()
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) { visible = true }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.35)) { self.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !self.visible { self.panel?.orderOut(nil) }
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

struct HUDView: View {
    @ObservedObject var hud: HUD

    var body: some View {
        Group {
            switch hud.content {
            case .level(let kind, let value)?:
                LevelKnob(kind: kind, value: value)
            case .message(let text, let symbol, let icon)?:
                MessagePill(text: text, symbol: symbol, icon: icon)
            case nil:
                Color.clear
            }
        }
        .scaleEffect(hud.visible ? 1 : 0.82, anchor: .topLeading)
        .blur(radius: hud.visible ? 0 : 10)
        .opacity(hud.visible ? 1 : 0)
        .padding(16)
        .frame(width: 360, height: 220, alignment: .topLeading)
    }
}

/// La perilla del iPhone, en chico: arco de luz, marcas y el zarcillo que se
/// enrosca con el valor.
private struct LevelKnob: View {
    let kind: LevelKind
    let value: Double

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Ceramic(shape: Circle(), fill: MacTone.recess)
                Circle()
                    .trim(from: 0, to: value * 0.75)
                    .stroke(MacTone.ember, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(8)
                    .shadow(color: MacTone.ember.opacity(0.8), radius: 8)
                ZStack {
                    Circle().fill(MacTone.ember)
                    ForEach(0..<20, id: \.self) { i in
                        Capsule().fill(MacTone.emberDeep)
                            .frame(width: 2, height: i % 5 == 0 ? 8 : 5)
                            .offset(y: -34)
                            .rotationEffect(.degrees(Double(i) * 18))
                    }
                    Tendril(tightness: value)
                        .stroke(MacTone.body, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 44, height: 44)
                }
                .frame(width: 76, height: 76)
                .overlay(RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.32, y: 0.26),
                                        startRadius: 0, endRadius: 34).blendMode(.softLight).clipShape(Circle()))
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 2) {
                Label(kind == .volume ? "volumen" : "brillo",
                      systemImage: kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1.2)
                    .foregroundStyle(MacTone.ink.opacity(0.55))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MacTone.ember)
                    .contentTransition(.numericText(value: value))
            }
            .padding(.trailing, 20)
        }
        .padding(10)
        .background(Ceramic(shape: Capsule()).shadow(color: .black.opacity(0.4), radius: 16, y: 8))
        .animation(.spring(duration: 0.3), value: value)
    }
}

private struct MessagePill: View {
    let text: String
    let symbol: String?
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(MacTone.key)
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(MacTone.ember)
                        .symbolEffect(.bounce, value: text)
                }
            }
            .frame(width: 42, height: 42)
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTone.ink)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.leading, 8).padding(.trailing, 20).padding(.vertical, 8)
        .background(Ceramic(shape: Capsule()).shadow(color: .black.opacity(0.4), radius: 16, y: 8))
        .overlay(Capsule().stroke(MacTone.ember.opacity(0.35), lineWidth: 1))
    }
}
