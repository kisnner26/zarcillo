import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

typealias State = ZarcilloActivityAttributes.ContentState

@main
struct ZarcilloWidgets: WidgetBundle {
    var body: some Widget { ZarcilloIsland() }
}

private extension State {
    var color: Color { Color(red: Double(tint >> 16 & 255) / 255, green: Double(tint >> 8 & 255) / 255, blue: Double(tint & 255) / 255) }
    var idle: Bool { title.isEmpty }
    var span: ClosedRange<Date> {
        let start = stamp.addingTimeInterval(-position)
        return start...start.addingTimeInterval(max(duration, 1))
    }
    var sized: Bool { duration > 0 }
}

private struct Cover: View {
    let s: State
    let size: CGFloat
    var body: some View {
        Group {
            if let d = s.art, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [s.color, s.color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: s.idle ? "desktopcomputer" : "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

private struct Bars: View {
    let s: State
    var body: some View {
        if s.showWave {
            wave
        }
    }
    private var wave: some View {
        Image(systemName: s.playing ? "waveform" : "pause.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(s.color)
            .symbolEffect(.variableColor.iterative.reversing, isActive: s.playing)
    }
}

private struct Titles: View {
    let s: State
    let mac: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.idle ? mac : s.title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
            Text(s.idle ? "conectado" : s.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }
}

private struct Progress: View {
    let s: State
    var body: some View {
        if s.showProgress && s.playing && s.sized {
            VStack(spacing: 4) {
                ProgressView(timerInterval: s.span, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(s.color)
                HStack {
                    Text(timerInterval: s.span, countsDown: false).monospacedDigit()
                    Spacer()
                    Text(Duration.seconds(s.duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

private struct Controls: View {
    let s: State
    var body: some View {
        HStack(spacing: 34) {
            Button(intent: LiveMediaIntent("previous")) { Image(systemName: "backward.fill") }
            Button(intent: LiveMediaIntent("playPause")) {
                Image(systemName: s.playing ? "pause.fill" : "play.fill").font(.system(size: 22))
            }
            Button(intent: LiveMediaIntent("next")) { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(.white)
    }
}

struct ZarcilloIsland: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZarcilloActivityAttributes.self) { ctx in
            let s = ctx.state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if s.showCover { Cover(s: s, size: 58) }
                    Titles(s: s, mac: ctx.attributes.mac)
                    Spacer(minLength: 0)
                    Bars(s: s)
                }
                Progress(s: s)
                if s.showControls && !s.idle { Controls(s: s) }
            }
            .foregroundStyle(.white)
            .padding(16)
            .activityBackgroundTint(s.color.opacity(0.32))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { if s.showCover { Cover(s: s, size: 52).padding(.leading, 2) } }
                DynamicIslandExpandedRegion(.trailing) { Bars(s: s).padding(.trailing, 4) }
                DynamicIslandExpandedRegion(.center) { Titles(s: s, mac: ctx.attributes.mac) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Progress(s: s)
                        if s.showControls && !s.idle { Controls(s: s) }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Cover(s: s, size: 22)
            } compactTrailing: {
                if s.showWave { Image(systemName: s.playing ? "waveform" : s.idle ? "desktopcomputer" : "pause.fill")
                    .foregroundStyle(s.color)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: s.playing) }
            } minimal: {
                Cover(s: s, size: 22)
            }
            .keylineTint(s.color)
        }
    }
}
