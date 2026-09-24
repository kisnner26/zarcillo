import Observation
import SwiftUI
import UIKit

/// El color de acento de toda la app, elegido por el usuario.
///
/// Es `@Observable`: cualquier vista que lea `Tone.ember` mientras se dibuja
/// queda suscrita sola, así cambiar el color repinta todo al instante sin
/// reiniciar pantallas ni perder dónde estabas.
@Observable
final class Theme {
    static let shared = Theme()

    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let hex: UInt32
    }

    static let presets: [Preset] = [
        Preset(id: "brasa", name: "brasa", hex: 0xF08A4B),
        Preset(id: "ambar", name: "ámbar", hex: 0xF2B544),
        Preset(id: "hoja", name: "hoja", hex: 0x7FCB7A),
        Preset(id: "musgo", name: "musgo", hex: 0x4FB3A0),
        Preset(id: "celeste", name: "celeste", hex: 0x35BEDC),
        Preset(id: "lirio", name: "lirio", hex: 0x8C8CF2),
        Preset(id: "orquidea", name: "orquídea", hex: 0xD57FE0),
        Preset(id: "rosa", name: "rosa", hex: 0xF27A9E),
        Preset(id: "amapola", name: "amapola", hex: 0xEE5A4F),
        Preset(id: "hueso", name: "hueso", hex: 0xE9DCCB),
    ]

    private(set) var accent: Color
    private(set) var hex: UInt32

    private init() {
        let saved = UserDefaults.standard.object(forKey: "accent") as? Int
        let start = UInt32(saved ?? 0xF08A4B)
        hex = start
        accent = Self.color(start)
    }

    func set(_ color: Color) {
        let c = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        set(hex: byte(r) << 16 | byte(g) << 8 | byte(b))
    }

    func set(hex: UInt32) {
        self.hex = hex
        accent = Self.color(hex)
        UserDefaults.standard.set(Int(hex), forKey: "accent")
    }

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Luminancia relativa: decide si el texto encima va oscuro o claro.
    var isLight: Bool {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.45
    }
}
