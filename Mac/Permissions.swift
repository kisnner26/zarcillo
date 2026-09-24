import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth

/// Mide y pide los permisos de macOS que usan las funciones de Zarcillo.
enum Permissions {
    nonisolated(unsafe) private static var bluetooth: CBCentralManager?
    nonisolated(unsafe) private static var automationCache: PermissionState = .undetermined
    nonisolated(unsafe) private static var automationAt = Date.distantPast

    private static let automationTargets = ["com.apple.finder", "com.apple.Music", "com.spotify.client",
                                            "com.apple.Safari", "com.google.Chrome"]

    static func all() -> [PermissionEntry] {
        PermissionKind.allCases.map { PermissionEntry(kind: $0, state: state($0)) }
    }

    static func state(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screen:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .granted
            case .notDetermined: return .undetermined
            default: return .denied
            }
        case .bluetooth:
            switch CBCentralManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .undetermined
            default: return .denied
            }
        case .automation:
            // Preguntar a cada app es algo lento: se repite cada 8 s como mucho.
            if Date().timeIntervalSince(automationAt) > 8 {
                automationAt = Date()
                automationCache = automation(ask: false)
            }
            return automationCache
        }
    }

    /// Estado de la automatización hacia las apps abiertas que Zarcillo lee.
    /// Con `ask` el sistema muestra su aviso si todavía no se ha decidido.
    static func automation(ask: Bool) -> PermissionState {
        var result: PermissionState = .granted
        var any = false
        for id in automationTargets where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            any = true
            let target = NSAppleEventDescriptor(bundleIdentifier: id)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            switch status {
            case noErr: continue
            case -1744: if result == .granted { result = .undetermined }   // haría falta preguntar
            default: result = .denied                                        // -1743: negado
            }
        }
        return any ? result : .undetermined
    }

    /// Provoca el aviso del sistema si aún no se decidió; si ya se negó, abre el
    /// panel de Ajustes correspondiente.
    @MainActor static func request(_ kind: PermissionKind) {
        let current = state(kind)
        guard current != .granted else { return }
        switch kind {
        case .accessibility:
            Input.requestAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { openSettings(kind) }
        case .screen:
            ScreenGrabber.requestAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { openSettings(kind) }
        case .camera:
            if current == .undetermined { AVCaptureDevice.requestAccess(for: .video) { _ in } } else { openSettings(kind) }
        case .bluetooth:
            if current == .undetermined { bluetooth = CBCentralManager(delegate: nil, queue: nil) } else { openSettings(kind) }
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async { _ = automation(ask: true) }
            if current == .denied { openSettings(kind) }
        }
    }

    @MainActor static func openSettings(_ kind: PermissionKind) {
        let pane: String
        switch kind {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screen: pane = "Privacy_ScreenCapture"
        case .camera: pane = "Privacy_Camera"
        case .bluetooth: pane = "Privacy_Bluetooth"
        case .automation: pane = "Privacy_Automation"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
