import SwiftUI

@main
struct ZarcilloApp: App {
    @StateObject private var remote = Remote()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(remote)
                .preferredColorScheme(.dark)
                .buttonStyle(PressScale())
                .scrollDismissesKeyboard(.interactively)
                .persistentSystemOverlays(.hidden)
                .onAppear { WatchLink.shared.start(remote) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                remote.resume()
                WatchLink.shared.becameActive()
                // Por si quedó un pedido de orientación colgado: el giro es libre.
                Orientation.request(.allButUpsideDown)
            }
        }
    }
}
