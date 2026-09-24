import ServiceManagement
import SwiftUI

@main
struct ZarcilloMacApp: App {
    @StateObject private var server = Server()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(server)
        } label: {
            Image(systemName: server.devices.isEmpty ? "leaf" : "leaf.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @EnvironmentObject private var server: Server
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zarcillo").font(.headline)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("CÓDIGO PARA TU IPHONE").font(.caption2).tracking(1.4).foregroundStyle(.secondary)
                Text(spaced(server.passcode))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .textSelection(.enabled)
                Button("Generar otro código") { server.regenerate() }
                    .buttonStyle(.link).font(.caption)
            }

            if !server.canControl {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Falta el permiso de Accesibilidad", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    Text("Sin él, el iPhone puede abrir apps y cambiar el volumen, pero no mover el cursor ni usar atajos.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Dar permiso…") { Input.requestAccess() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }

            if !server.canCapture {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Pantalla en vivo desactivada", systemImage: "rectangle.dashed")
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Para ver el Mac en el iPhone, Zarcillo necesita el permiso de Grabación de pantalla.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Dar permiso…") { ScreenGrabber.requestAccess() }
                }
            }

            if let problem = server.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }

            Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }

            HStack {
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var status: String {
        if !server.devices.isEmpty { return "Conectado: " + server.devices.joined(separator: ", ") }
        return server.listening ? "Esperando tu iPhone en la red" : "Iniciando…"
    }

    private func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }
}
