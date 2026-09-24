import SwiftUI
import WatchKit

/// La mano: agarra algo del Mac o del iPhone y lánzalo con la muñeca hacia el otro.
struct HandView: View {
    @EnvironmentObject private var link: PhoneLink
    @State private var fly = false
    @State private var sway = false

    var body: some View {
        ZStack {
            Ceramic(accent: link.accent)
            switch link.hand {
            case .empty, .failed:
                empty
            case .grabbing(let from):
                grabbing(from)
            case .holding(let h):
                holding(h)
            case .flying(let h):
                leaf(h).offset(y: fly ? -260 : 0).rotationEffect(.degrees(fly ? -35 : 0))
                    .scaleEffect(fly ? 0.4 : 1).opacity(fly ? 0 : 1)
                    .onAppear { withAnimation(.easeIn(duration: 0.45)) { fly = true } }
                    .onDisappear { fly = false }
            case .landed(let to):
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 38)).foregroundStyle(link.accent)
                        .symbolEffect(.bounce, value: to)
                    Text(to == "mac" ? "cayó en tu Mac" : "cayó en tu iPhone")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(WTone.ink)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: link.hand) { _, hand in
            if case .holding = hand {
                Wrist.shared.onThrow = { _ in
                    WKInterfaceDevice.current().play(.directionUp)
                    withAnimation { link.throwHeld() }
                }
                Wrist.shared.listen()
            } else {
                Wrist.shared.stop()
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Tendril(tightness: 0.55)
                .stroke(link.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(sway ? 8 : -8))
                .onAppear { withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { sway = true } }
            if case .failed(let why) = link.hand {
                Text(why).font(.system(size: 11)).foregroundStyle(link.accent).multilineTextAlignment(.center)
            } else {
                Text("agarra algo").font(.system(size: 12, weight: .semibold)).foregroundStyle(WTone.ink.opacity(0.6))
            }
            grabButton("del Mac", "laptopcomputer", "mac")
            grabButton("del iPhone", "iphone", "iphone")
        }
        .padding(.horizontal, 6)
    }

    private func grabButton(_ title: String, _ symbol: String, _ side: String) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            link.grab(from: side)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(side == "mac" ? link.accent : WTone.key)
    }

    private func grabbing(_ from: String) -> some View {
        VStack(spacing: 8) {
            LeafShape().stroke(link.accent, lineWidth: 2)
                .frame(width: 30, height: 42)
                .rotationEffect(.degrees(sway ? 20 : -20))
                .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { sway.toggle() } }
            Text(from == "mac" ? "agarrando del Mac…" : "agarrando del iPhone…")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(WTone.ink.opacity(0.8))
        }
    }

    /// Lo que tienes en la mano, dentro de una hoja.
    private func leaf(_ h: PhoneLink.Held) -> some View {
        ZStack {
            if let img = h.thumb {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 86, height: 114).clipShape(LeafShape())
                LeafVein().stroke(.white.opacity(0.45), lineWidth: 1.5).frame(width: 86, height: 114)
            } else {
                LeafShape().fill(link.accent.opacity(0.25)).frame(width: 86, height: 114)
                Image(systemName: h.kind == "url" ? "link" : h.kind == "text" ? "text.quote" : "doc.fill")
                    .font(.system(size: 28, weight: .semibold)).foregroundStyle(link.accent)
            }
            LeafShape().stroke(link.accent, lineWidth: 2.5).frame(width: 86, height: 114)
        }
        .shadow(color: link.accent.opacity(0.5), radius: 10)
    }

    private func holding(_ h: PhoneLink.Held) -> some View {
        VStack(spacing: 6) {
            leaf(h)
                .rotationEffect(.degrees(sway ? 4 : -4))
                .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { sway = true } }
            Text(h.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(WTone.ink).lineLimit(1)
            Button {
                WKInterfaceDevice.current().play(.directionUp)
                withAnimation { link.throwHeld() }
            } label: {
                Label(h.target == "mac" ? "lanza al Mac" : "lanza al iPhone", systemImage: "hand.wave.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(link.accent)
            // Doble toque (índice y pulgar) también lanza.
            .handGestureShortcut(.primaryAction)
        }
        .padding(.horizontal, 6)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { link.drop() } label: { Image(systemName: "xmark") }
            }
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}
