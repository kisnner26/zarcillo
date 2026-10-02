#if os(iOS)
import ActivityKit
import Foundation

/// Lo que muestran la isla dinámica y la pantalla de bloqueo.
struct ZarcilloActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var playing: Bool
        var position: Double
        var duration: Double
        var stamp: Date
        /// Miniatura JPEG diminuta (el límite del estado es 4 KB).
        var art: Data?
        /// Color vivo de la carátula, 0xRRGGBB.
        var tint: Int
        /// Ajustes de la página "isla".
        var showCover = true
        var showProgress = true
        var showControls = true
        var showWave = true
    }
    var mac: String
}
#endif
