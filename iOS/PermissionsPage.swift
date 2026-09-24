import SwiftUI

/// Lo que el Mac le deja hacer a Zarcillo. Cada permiso que falta se puede
/// pedir desde aquí: el aviso sale en la pantalla del Mac.
struct PermissionsPage: View {
    @EnvironmentObject private var remote: Remote

    var body: some View {
        StageScroll(spacing: Space.m) {
            summary
            ForEach(PermissionKind.allCases) { kind in row(kind) }
            Hint("El aviso aparece en la pantalla del Mac: toca Permitir. Si ya lo habías negado, se abre Ajustes allí; activa Zarcillo en esa lista.")
        }
    }

    private var summary: some View {
        let missing = remote.missingPermissions.count
        return VStack(spacing: 6) {
            Image(systemName: missing == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(missing == 0 ? Tone.leaf : Tone.ember)
                .contentTransition(.symbolEffect(.replace))
            Text(remote.permissions.isEmpty ? "consultando al Mac…"
                 : missing == 0 ? "todo en orden" : missing == 1 ? "falta 1 permiso" : "faltan \(missing) permisos")
                .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
        }
        .padding(.bottom, Space.s)
    }

    private func row(_ kind: PermissionKind) -> some View {
        let state = remote.permissions[kind]
        let entry = state.map { PermissionEntry(kind: kind, state: $0) }
        let ok = state == .granted
        let attention = entry?.needsAttention ?? false
        return HStack(spacing: Space.s) {
            Image(systemName: kind.symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ok ? Tone.leaf : (attention ? Tone.ember : Tone.ink.opacity(0.6)))
                .frame(width: 40, height: 40).background(Circle().fill(Tone.recess))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Tone.ink)
                    if kind.isOptional {
                        Text("opcional").font(.system(size: 10, weight: .bold)).foregroundStyle(Tone.ink.opacity(0.4))
                    }
                }
                Text(kind.detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if ok {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Tone.leaf)
            } else if state != nil {
                Button {
                    Detents.shared.press()
                    remote.requestPermission(kind)
                } label: {
                    Text(state == .denied ? "abrir" : "pedir").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tone.onEmber).padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Tone.ember))
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(attention ? Tone.ember.opacity(0.5) : Tone.stroke, lineWidth: 1))
    }
}
