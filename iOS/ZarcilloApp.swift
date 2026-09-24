import SwiftUI

@main
struct ZarcilloApp: App {
    @StateObject private var remote = Remote()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(remote)
                .preferredColorScheme(.light)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { remote.resume() }
        }
    }
}
