import AppKit
import SwiftUI

/// La misma cerámica del iPhone, para que el Mac se vea como el mismo aparato.
enum MacTone {
    static let ink = Color(red: 0.96, green: 0.91, blue: 0.86)
    static let body = Color(red: 0.106, green: 0.078, blue: 0.067)
    static let recess = Color(red: 0.07, green: 0.051, blue: 0.043)
    static let key = Color(red: 0.165, green: 0.125, blue: 0.11)
    static let stroke = Color(red: 0.23, green: 0.17, blue: 0.145)
    static let leaf = Color(red: 0.62, green: 0.85, blue: 0.62)
    /// El acento que eligió el usuario en el iPhone.
    static var ember: Color { Color(nsColor: Accent.nsColor) }
    static var emberDeep: Color { Color(nsColor: Accent.nsColor).mix(with: .black, by: 0.28) }
    /// Texto sobre el acento: oscuro si es claro.
    static var onEmber: Color {
        let h = Accent.hex
        let lum = 0.2126 * Double((h >> 16) & 0xFF) / 255 + 0.7152 * Double((h >> 8) & 0xFF) / 255 + 0.0722 * Double(h & 0xFF) / 255
        return lum > 0.45 ? body : ink
    }
}

/// Grano de cerámica: una baldosa de ruido que se genera una vez y se repite.
struct MacGrain: View {
    var opacity: Double

    private static let tile: NSImage = {
        let side = 96
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: side, bitsPerPixel: 8)!
        if let data = rep.bitmapData {
            for i in 0..<(side * side) { data[i] = UInt8.random(in: 0...255) }
        }
        let img = NSImage(size: NSSize(width: side, height: side))
        img.addRepresentation(rep)
        return img
    }()

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// Superficie de cerámica con borde de luz arriba y sombra abajo.
struct Ceramic<S: InsettableShape>: View {
    let shape: S
    var fill: Color = MacTone.body

    var body: some View {
        ZStack {
            shape.fill(fill)
            MacGrain(opacity: 0.06).clipShape(shape)
            shape.strokeBorder(LinearGradient(colors: [MacTone.ink.opacity(0.14), .black.opacity(0.5)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}
