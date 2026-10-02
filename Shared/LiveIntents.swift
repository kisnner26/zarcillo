#if os(iOS)
import AppIntents

/// Botones de la isla dinámica. Corren en la app, no en la extensión.
struct LiveMediaIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control de música"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Acción") var action: String

    init() { action = "playPause" }
    init(_ action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        let key: MediaKey = action == "next" ? .next : action == "previous" ? .previous : .playPause
        try? await QuickLink.send([.media(key)])
        #endif
        return .result()
    }
}
#endif
