import ServiceManagement
import SwiftUI

@main
struct ZarcilloMacApp: App {
    // `@State` y no `@StateObject`: la escena no debe redibujarse con cada
    // cambio del servidor. El icono de la barra de menús vive en una ventanita
    // de AppKit, y redibujarlo muchas veces seguidas mientras se acomoda hacía
    // que AppKit cerrara la app ("more Update Constraints … than there are views").
    @State private var server = Server()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(server)
        } label: {
            LeafLabel(presence: server.presence)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Lo único que el icono necesita saber: si hay un iPhone conectado.
@MainActor
final class Presence: ObservableObject {
    @Published private(set) var connected = false

    func set(_ value: Bool) {
        if value != connected { connected = value }
    }
}

struct LeafLabel: View {
    @ObservedObject var presence: Presence

    var body: some View {
        Image(systemName: presence.connected ? "leaf.fill" : "leaf")
    }
}

/// El menú de la hoja: la misma cerámica y el mismo acento que el iPhone.
struct MenuView: View {
    @EnvironmentObject private var server: Server
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var regenerations = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            code
            if !server.canControl { permission(
                title: "Falta Accesibilidad",
                detail: "Sin este permiso el iPhone abre apps y cambia el volumen, pero no mueve el cursor ni escribe.",
                symbol: "hand.raised.fill", action: Input.requestAccess) }
            if !server.canCapture { permission(
                title: "Pantalla en vivo apagada",
                detail: "Para ver el Mac en el iPhone hace falta el permiso de Grabación de pantalla.",
                symbol: "rectangle.dashed", action: ScreenGrabber.requestAccess) }
            optionalPermissions
            screenshotsToggle
            if let problem = server.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(
            ZStack {
                MacTone.body
                RadialGradient(colors: [MacTone.ember.opacity(0.18), .clear], center: .bottom, startRadius: 0, endRadius: 320)
                MacGrain(opacity: 0.06)
            }
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(MacTone.ember).frame(width: 38, height: 38)
                    .shadow(color: MacTone.ember.opacity(0.6), radius: 10)
                Image(systemName: "leaf.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(MacTone.onEmber)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Zarcillo").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(MacTone.ink)
                Text(status).font(.system(size: 12)).foregroundStyle(MacTone.ink.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            let color = server.devices.isEmpty ? MacTone.ember : MacTone.leaf
            // Brillo fijo, sin latir: una animación continua en esta ventana la
            // hacía recalcular su tamaño sin parar, y AppKit terminaba la app.
            Circle().fill(color).frame(width: 9, height: 9)
                .shadow(color: color, radius: 6)
        }
    }

    /// El código como seis teclas grabadas en la cerámica.
    private var code: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CÓDIGO PARA TU IPHONE").font(.system(size: 10, weight: .bold)).tracking(1.4)
                .foregroundStyle(MacTone.ink.opacity(0.45))
            HStack(spacing: 6) {
                ForEach(Array(server.passcode.enumerated()), id: \.offset) { i, ch in
                    Text(String(ch))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacTone.ember)
                        .contentTransition(.numericText())
                        .frame(width: 38, height: 48)
                        .background(Ceramic(shape: RoundedRectangle(cornerRadius: 11, style: .continuous), fill: MacTone.key))
                    if i == 2 { Spacer().frame(width: 6) }
                }
            }
            .animation(.spring(duration: 0.5, bounce: 0.3), value: server.passcode)
            Button {
                regenerations += 1
                server.regenerate()
            } label: {
                Label("Generar otro código", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, value: regenerations)
            }
            .buttonStyle(Pill(fill: MacTone.key, fg: MacTone.ink.opacity(0.8)))
        }
        .padding(14)
        .background(Ceramic(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), fill: MacTone.recess))
    }

    private var screenshotsToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTone.ember).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Capturas al iPhone").font(.system(size: 12, weight: .semibold)).foregroundStyle(MacTone.ink)
                Text("⇧⌘3, ⇧⌘4 y ⇧⌘5").font(.system(size: 10)).foregroundStyle(MacTone.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { server.sendScreenshots }, set: { server.setScreenshots($0) }))
                .labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .background(Ceramic(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fill: MacTone.key))
    }

    /// Cámara, Bluetooth y automatización: solo hacen falta para funciones concretas.
    @ViewBuilder private var optionalPermissions: some View {
        let missing = server.permissions.filter { $0.kind.isOptional && $0.needsAttention }
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PERMISOS OPCIONALES").font(.system(size: 10, weight: .bold)).tracking(1.4)
                    .foregroundStyle(MacTone.ink.opacity(0.45))
                ForEach(missing) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.kind.symbol).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacTone.ember).frame(width: 22)
                        Text(entry.kind.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MacTone.ink)
                        Spacer(minLength: 0)
                        Button(entry.state == .denied ? "Abrir Ajustes" : "Permitir") { Permissions.request(entry.kind) }
                            .buttonStyle(Pill(fill: MacTone.key, fg: MacTone.ink.opacity(0.85)))
                    }
                }
            }
            .padding(12)
            .background(Ceramic(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fill: MacTone.key))
        }
    }

    private func permission(title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(MacTone.ember)
                .frame(width: 30, height: 30).background(Circle().fill(MacTone.ember.opacity(0.15)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTone.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(MacTone.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dar permiso") { action() }
                    .buttonStyle(Pill(fill: MacTone.ember, fg: MacTone.onEmber))
            }
        }
        .padding(12)
        .background(Ceramic(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), fill: MacTone.key))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Zarcillo", isDirectory: true))
            } label: {
                Label("Fotos recibidas", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(Pill(fill: MacTone.key, fg: MacTone.ink.opacity(0.85)))

            HStack {
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(MacTone.ember)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTone.ink.opacity(0.75))
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
                    .buttonStyle(Pill(fill: .clear, fg: MacTone.ink.opacity(0.55)))
            }
        }
    }

    private var status: String {
        if !server.devices.isEmpty { return "Conectado: " + server.devices.joined(separator: ", ") }
        return server.listening ? "Esperando tu iPhone en la red" : "Iniciando…"
    }
}
