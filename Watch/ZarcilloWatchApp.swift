import SwiftUI

@main
struct ZarcilloWatchApp: App {
    @StateObject private var link = PhoneLink.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                HandView()
                MusicView()
                ScenesView()
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(link)
            .tint(link.accent)
            .onAppear { link.start() }
        }
    }
}

/// La cerámica oscura del iPhone, en pequeño.
enum WTone {
    static let ink = Color(red: 0.96, green: 0.91, blue: 0.86)
    static let body = Color(red: 0.106, green: 0.078, blue: 0.067)
    static let key = Color(red: 0.165, green: 0.125, blue: 0.11)
    static let stroke = Color(red: 0.23, green: 0.17, blue: 0.145)
}

struct Ceramic: View {
    let accent: Color

    var body: some View {
        ZStack {
            WTone.body
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .bottom, startRadius: 0, endRadius: 220)
        }
        .ignoresSafeArea()
    }
}
