import SwiftUI
import WatchKit

/// Lo que suena en el Mac, con la corona como perilla de volumen.
struct MusicView: View {
    @EnvironmentObject private var link: PhoneLink
    @State private var crown = 0.5
    @State private var lastSend = Date.distantPast

    var body: some View {
        ZStack {
            Ceramic(accent: link.accent)
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(WTone.stroke, lineWidth: 5)
                    Circle().trim(from: 0, to: crown)
                        .stroke(link.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Tendril(tightness: crown)
                        .stroke(link.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .padding(16)
                    Text("\(Int(crown * 100))").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(WTone.ink.opacity(0.7)).offset(y: 30)
                }
                .frame(width: 76, height: 76)
                .focusable()
                .digitalCrownRotation($crown, from: 0, through: 1, by: 0.02, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                Text(link.title ?? "nada sonando").font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(WTone.ink).lineLimit(1).minimumScaleFactor(0.7)
                if !link.artist.isEmpty {
                    Text(link.artist).font(.system(size: 11)).foregroundStyle(WTone.ink.opacity(0.6)).lineLimit(1)
                }
                HStack(spacing: 8) {
                    control("backward.fill", "previous", filled: false)
                    control(link.playing ? "pause.fill" : "play.fill", "playPause", filled: true)
                    control("forward.fill", "next", filled: false)
                }
            }
        }
        .onAppear { crown = link.volume }
        .onChange(of: link.volume) { _, v in if Date().timeIntervalSince(lastSend) > 1 { crown = v } }
        .onChange(of: crown) { _, v in
            guard Date().timeIntervalSince(lastSend) > 0.08 else { return }
            lastSend = Date()
            link.setVolume(v)
        }
    }

    private func control(_ symbol: String, _ key: String, filled: Bool) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            link.media(key)
        } label: {
            Image(systemName: symbol).font(.system(size: filled ? 16 : 13, weight: .bold))
                .foregroundStyle(filled ? WTone.body : WTone.ink)
                .frame(width: filled ? 44 : 36, height: filled ? 44 : 36)
                .background(Circle().fill(filled ? link.accent : WTone.key))
        }
        .buttonStyle(.plain)
    }
}

/// Tus escenas del iPhone, a un toque, y bloquear el Mac.
struct ScenesView: View {
    @EnvironmentObject private var link: PhoneLink

    var body: some View {
        List {
            Section {
                ForEach(link.routines, id: \.self) { name in
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        link.run(name)
                    } label: {
                        Label(name, systemImage: "sparkles").font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                }
            } header: {
                Text(link.connected ? link.mac : "sin Mac").foregroundStyle(link.accent)
            }
            Button(role: .destructive) {
                WKInterfaceDevice.current().play(.click)
                link.lock()
            } label: {
                Label("bloquear el Mac", systemImage: "lock.fill")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Ceramic(accent: link.accent))
    }
}
