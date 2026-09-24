import Foundation

/// Los permisos de macOS que Zarcillo puede necesitar en el Mac. Los comparten
/// el Mac (que los mide y los pide) y el iPhone (que los muestra).
enum PermissionKind: String, Codable, CaseIterable, Identifiable {
    case accessibility, screen, camera, bluetooth, automation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accesibilidad"
        case .screen: "Grabación de pantalla"
        case .camera: "Cámara"
        case .bluetooth: "Bluetooth"
        case .automation: "Automatización"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: "Mover el cursor, escribir, atajos, ventanas y gestos."
        case .screen: "Ver el Mac en el iPhone, cosechar, luces que siguen la pantalla y sentir la música."
        case .camera: "Postura y la foto del guardián."
        case .bluetooth: "Bloquear el Mac cuando te alejas."
        case .automation: "Leer la música que suena, la pestaña del navegador y lo que eliges en el Finder."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "hand.raised.fill"
        case .screen: "rectangle.dashed"
        case .camera: "camera.fill"
        case .bluetooth: "wave.3.right"
        case .automation: "gearshape.2.fill"
        }
    }

    /// Los dos primeros son la base; el resto solo hace falta para funciones concretas.
    var isOptional: Bool { self != .accessibility && self != .screen }
}

enum PermissionState: String, Codable {
    case granted, denied, undetermined
}

struct PermissionEntry: Codable, Equatable, Identifiable {
    var kind: PermissionKind
    var state: PermissionState
    var id: String { kind.rawValue }

    /// ¿Hay que hacer algo? La automatización se pide sola al usarla, así que
    /// solo cuenta si ya se negó.
    var needsAttention: Bool {
        kind == .automation ? state == .denied : state != .granted
    }
}
