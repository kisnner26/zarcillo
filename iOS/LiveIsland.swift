import ActivityKit
import SwiftUI
import UIKit

/// Mantiene la actividad en vivo: aparece al conectar con el Mac y se va al perderlo.
@MainActor
enum LiveIsland {
    private static var activity: Activity<ZarcilloActivityAttributes>?
    private static var thumbKey = ""
    private static var thumb: Data?
    private static var tint = 0xFA8C33
    private static var lastMac = ""
    private static var lastNP: NowPlaying?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "island.on") as? Bool ?? true }
    private static func flag(_ k: String) -> Bool { UserDefaults.standard.object(forKey: "island." + k) as? Bool ?? true }
    /// 0 = color de la carátula, 1 = acento de la app.
    private static var tintMode: Int { UserDefaults.standard.integer(forKey: "island.tint") }
    /// 0 = siempre que haya conexión, 1 = solo mientras suena algo.
    private static var showMode: Int { UserDefaults.standard.integer(forKey: "island.when") }

    /// Reaplica los ajustes a la actividad actual (al tocar la página "isla").
    static func refresh() {
        if lastMac.isEmpty { return }
        update(mac: lastMac, np: lastNP)
    }

    private static func state(_ np: NowPlaying?) -> ZarcilloActivityAttributes.ContentState {
        .init(title: np?.title ?? "", artist: np?.artist ?? "", playing: np?.playing ?? false,
              position: np?.position ?? 0, duration: np?.duration ?? 0, stamp: Date(),
              art: flag("cover") ? thumb : nil,
              tint: tintMode == 1 ? Int(Theme.shared.hex) : tint,
              showCover: flag("cover"), showProgress: flag("progress"),
              showControls: flag("controls"), showWave: flag("wave"))
    }

    /// Miniatura cuadrada que cabe en el límite de 4 KB del estado.
    private static func makeThumb(_ image: UIImage) -> Data? {
        let side: CGFloat = 60
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            let s = min(image.size.width, image.size.height)
            let crop = CGRect(x: (image.size.width - s) / 2, y: (image.size.height - s) / 2, width: s, height: s)
            if let cg = image.cgImage?.cropping(to: CGRect(x: crop.minX * image.scale, y: crop.minY * image.scale,
                                                           width: crop.width * image.scale, height: crop.height * image.scale)) {
                UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
        for q in stride(from: 0.6, through: 0.1, by: -0.1) {
            if let d = small.jpegData(compressionQuality: q), d.count <= 2400 { return d }
        }
        return nil
    }

    static func update(mac: String, np: NowPlaying?, art: UIImage? = nil, palette: ArtPalette? = nil) {
        lastMac = mac
        lastNP = np
        let wanted = enabled && (showMode == 0 || np?.playing == true)
        guard wanted, ActivityAuthorizationInfo().areActivitiesEnabled else { endActivity(); return }
        if np?.trackID != thumbKey {
            thumbKey = np?.trackID ?? ""
            thumb = nil
            tint = 0xFA8C33
        }
        if let art, thumb == nil { thumb = makeThumb(art) }
        if let palette {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            UIColor(palette.vivid).getRed(&r, green: &g, blue: &b, alpha: nil)
            tint = Int(r * 255) << 16 | Int(g * 255) << 8 | Int(b * 255)
        }
        let content = ActivityContent(state: state(np), staleDate: nil)
        if let activity, activity.attributes.mac == mac {
            Task { await activity.update(content) }
        } else {
            end()
            activity = try? Activity.request(attributes: .init(mac: mac), content: content)
        }
    }

    static func end() {
        lastMac = ""
        endActivity()
    }

    private static func endActivity() {
        guard let a = activity else { return }
        activity = nil
        thumbKey = ""
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
