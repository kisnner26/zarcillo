import SwiftUI

@main
struct ZarcilloApp: App {
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate
    @StateObject private var remote = Remote()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(remote)
                .preferredColorScheme(.dark)
                .buttonStyle(PressScale())
                .scrollDismissesKeyboard(.interactively)
                // En cualquier campo de texto, un "Listo" sobre el teclado lo cierra.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .fontWeight(.semibold)
                        .tint(Tone.ember)
                    }
                }
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    WatchLink.shared.start(remote)
                    Orientation.request(.allButUpsideDown)
                }
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
