import CoreMotion
import SwiftUI

/// Las ventanas del Mac como capas flotantes. Inclinas el iPhone y se separan con
/// paralaje; tocas una y sube al frente en el Mac.
struct LayersPage: View {
    @EnvironmentObject private var remote: Remote
    @StateObject private var tilt = Tilt()
    @State private var order: [String] = []
    @State private var drag: CGSize = .zero

    private var windows: [WindowInfo] {
        let all = remote.windows.filter { !$0.title.isEmpty || !$0.minimized }
        let ids = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let known = order.compactMap { ids[$0] }
        let fresh = all.filter { !order.contains($0.id) }
        return Array((fresh + known).prefix(8))
    }

    var body: some View {
        GeometryReader { geo in
            let list = windows
            ZStack {
                if list.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.3.layers.3d").font(.system(size: 44, weight: .light))
                            .foregroundStyle(Tone.ink.opacity(0.5))
                        Text("no veo ventanas abiertas").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.7))
                        Text("Abre algo en el Mac o da el permiso de Accesibilidad.")
                            .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.45)).multilineTextAlignment(.center)
                    }
                    .padding(Space.l)
                }
                // La última de la lista es la del fondo; la primera, la del frente.
                ForEach(Array(list.enumerated().reversed()), id: \.element.id) { depth, w in
                    card(w, depth: depth, of: list.count, box: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag = CGSize(width: $0.translation.width / 6, height: $0.translation.height / 6) }
                .onEnded { _ in withAnimation(.spring(duration: 0.5, bounce: 0.35)) { drag = .zero } })
        }
        .padding(.horizontal, Space.m)
        .task {
            tilt.start()
            while !Task.isCancelled {
                remote.send(.listWindows)
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onDisappear { tilt.stop() }
        .overlay(alignment: .bottom) {
            Text("inclina el iPhone · toca una capa para traerla al frente")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.4))
                .padding(.bottom, Space.s)
        }
    }

    private func card(_ w: WindowInfo, depth: Int, of n: Int, box: CGSize) -> some View {
        let f = Double(depth)
        let cardW: CGFloat = min(box.width * 0.8, 340)
        // Las capas del fondo se mueven más con la inclinación: eso da la profundidad.
        let gain: Double = 1 + f * 0.35
        let px: Double = (tilt.roll * 60 + drag.width) * gain
        let py: Double = (tilt.pitch * 60 + drag.height) * gain
        let base: Double = (f - Double(n - 1) / 2) * 44
        let yaw: Double = tilt.roll * 14 + drag.width * 0.4
        let pit: Double = -tilt.pitch * 14 - drag.height * 0.4
        let front = depth == 0
        return face(w, width: cardW, front: front, depth: f)
            .opacity(1 - min(0.55, f * 0.09))
            .scaleEffect(1 - f * 0.03)
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(pit), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .offset(x: px, y: base + py)
            .zIndex(Double(n - depth))
            .onTapGesture { bringToFront(w) }
            .animation(.spring(duration: 0.5, bounce: 0.3), value: depth)
    }

    private func bringToFront(_ w: WindowInfo) {
        Detents.shared.press()
        remote.send(.focusWindow(id: w.id))
        let rest = windows.map(\.id).filter { $0 != w.id }
        withAnimation(.spring(duration: 0.55, bounce: 0.3)) { order = [w.id] + rest }
    }

    private func face(_ w: WindowInfo, width: CGFloat, front: Bool, depth: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let border: Color = front ? Tone.ember.opacity(0.8) : Tone.stroke
        let fill = LinearGradient(colors: [Tone.key, Tone.recess], startPoint: .topLeading, endPoint: .bottomTrailing)
        return faceContent(w)
            .padding(14)
            .frame(width: width, height: width * 0.62)
            .background(shape.fill(fill))
            .overlay(shape.stroke(border, lineWidth: front ? 1.5 : 1))
            .shadow(color: .black.opacity(0.45), radius: 14 + depth * 2, y: 8 + depth * 2)
    }

    private func faceContent(_ w: WindowInfo) -> some View {
        let app = remote.apps.first { $0.id == w.appID }
        let name: String = app?.name ?? w.appID
        let title: String = w.title.isEmpty ? "sin título" : w.title
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                appIcon(app)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.55))
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if w.minimized {
                Label("minimizada", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func appIcon(_ app: AppTile?) -> some View {
        if let data = app?.icon, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// La inclinación del iPhone, ya suavizada: roll (izquierda-derecha) y pitch (adelante-atrás).
@MainActor
final class Tilt: ObservableObject {
    @Published var roll = 0.0
    @Published var pitch = 0.0
    private let motion = CMMotionManager()
    private var zero: (r: Double, p: Double)?

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1 / 45
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            // Lo primero que se lee es el "reposo": todo se mide respecto a cómo lo sostienes.
            if zero == nil { zero = (a.roll, a.pitch) }
            let r = max(-1, min(1, (a.roll - zero!.r) / 0.6))
            let p = max(-1, min(1, (a.pitch - zero!.p) / 0.6))
            roll += (r - roll) * 0.18
            pitch += (p - pitch) * 0.18
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        zero = nil
    }
}
