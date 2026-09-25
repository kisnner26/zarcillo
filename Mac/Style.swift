import AppKit
import SwiftUI

/// El mismo invernadero de noche que el iPhone: verde casi negro, vidrio con filo
/// de luz y texto blanco frío, para que el Mac y el iPhone se vean como un solo aparato.
enum MacTone {
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.92)
    static let body = Color(red: 0.035, green: 0.062, blue: 0.052)
    static let recess = Color(red: 0.05, green: 0.085, blue: 0.072)
    static let key = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.11)
    static let leaf = Color(red: 0.55, green: 0.86, blue: 0.62)
    static let moss = Color(red: 0.36, green: 0.62, blue: 0.48)
    /// El acento que eligió el usuario en el iPhone.
    static var ember: Color { Color(nsColor: Accent.nsColor) }
    static var emberDeep: Color { Color(nsColor: Accent.nsColor).mix(with: .black, by: 0.28) }
    /// Texto sobre el acento: oscuro si es claro.
    static var onEmber: Color {
        let h = Accent.hex
        let lum = 0.2126 * Double((h >> 16) & 0xFF) / 255 + 0.7152 * Double((h >> 8) & 0xFF) / 255 + 0.0722 * Double(h & 0xFF) / 255
        return lum > 0.45 ? Color(red: 0.04, green: 0.06, blue: 0.05) : .white
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

/// Superficie de vidrio con filo de luz arriba (antes cerámica; mismo nombre para no
/// tocar a quien la usa).
struct Ceramic<S: InsettableShape>: View {
    let shape: S
    var fill: Color = MacTone.body

    var body: some View {
        ZStack {
            shape.fill(fill)
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.07), .clear, Color.white.opacity(0.02)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06), .white.opacity(0.1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
    }
}

/// Interruptor de hoja, igual al del iPhone.
struct MacLeafToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(LinearGradient(colors: [MacTone.ember, MacTone.emberDeep], startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(.white.opacity(configuration.isOn ? 0.25 : 0.14), lineWidth: 0.8))
                Circle().fill(Color.white)
                    .overlay(LeafShape().fill(configuration.isOn ? MacTone.ember : MacTone.moss)
                        .frame(width: 6, height: 10).rotationEffect(.degrees(configuration.isOn ? 30 : -150)))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(2.5)
            }
            .frame(width: 40, height: 24)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.spring(duration: 0.3, bounce: 0.35)) { configuration.isOn.toggle() } }
        }
    }
}

/// Vista de SwiftUI para paneles flotantes con tamaño fijo.
///
/// Por defecto `NSHostingView` intenta ajustar la ventana a su contenido; en un
/// panel que el código ya dimensiona eso entra en un bucle de restricciones y
/// AppKit termina la app ("more Update Constraints in Window passes than there
/// are views"). Aquí SwiftUI dibuja y nada más.
func fixedHost<V: View>(_ view: V) -> NSView {
    let host = NSHostingView(rootView: view)
    host.sizingOptions = []
    return host
}
