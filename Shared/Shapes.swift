import SwiftUI

// Formas compartidas por el iPhone y el Mac, para que los dos se vean como el
// mismo aparato.

/// Espiral de zarcillo: más vueltas cuanto mayor el valor.
struct Tendril: Shape {
    var tightness: Double
    var animatableData: Double {
        get { tightness }
        set { tightness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let turns = 0.6 + tightness * 2.4
        let steps = 160
        var p = Path()
        let startAngle = Double.pi * 0.75
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = startAngle - t * turns * 2 * .pi
            let rr = r * (1 - t * 0.88)
            let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Una hoja: dos curvas que se juntan en punta arriba y en el tallo abajo.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + w * 1.05, y: rect.minY + h * 0.18),
                   control2: CGPoint(x: rect.minX + w * 0.92, y: rect.minY + h * 0.86))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.86),
                   control2: CGPoint(x: rect.minX - w * 0.05, y: rect.minY + h * 0.18))
        p.closeSubpath()
        return p
    }
}

/// La nervadura central de la hoja.
struct LeafVein: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.08),
                       control: CGPoint(x: rect.midX + rect.width * 0.06, y: rect.midY))
        return p
    }
}

/// Tipo de imagen por sus primeros bytes, para guardarla con la extensión correcta.
enum ImageKind {
    static func fileExtension(of data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.count >= 12, String(bytes: b[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            return brand.hasPrefix("hei") || brand.hasPrefix("mif") ? "heic" : "mov"
        }
        if b.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }
}
