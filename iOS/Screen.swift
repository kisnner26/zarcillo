import SwiftUI
import UIKit

// MARK: - Pantalla en vivo

/// El Mac en el escenario, con un botón para verlo en pantalla completa.
struct ScreenPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var full = false
    @State private var harvesting = false

    var body: some View {
        LiveScreen(zoomable: false, harvesting: $harvesting)
            .padding(10)
            .overlay(alignment: .bottomLeading) {
                if remote.frame != nil {
                    Button {
                        Detents.shared.press()
                        withAnimation(.spring(duration: 0.3)) { harvesting.toggle() }
                    } label: {
                        Label(harvesting ? "encierra una zona" : "cosechar", systemImage: "leaf.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(harvesting ? Tone.onEmber : Tone.ink)
                            .padding(.horizontal, 14).frame(height: Space.tap)
                            .background(Capsule().fill(harvesting ? Tone.ember : Tone.key.opacity(0.9)))
                    }
                    .buttonStyle(PressScale())
                    .padding(Space.l)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if remote.frame != nil {
                    Button {
                        Detents.shared.press()
                        full = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Tone.onEmber)
                            .frame(width: Space.tap, height: Space.tap)
                            .background(Circle().fill(Tone.ember))
                            .shadow(color: Tone.ember.opacity(0.5), radius: 10)
                    }
                    .buttonStyle(PressScale())
                    .padding(Space.l)
                    .accessibilityLabel("pantalla completa")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $full) {
                FullScreenMac().environmentObject(remote)
            }
    }
}

/// El Mac a pantalla completa: gira a horizontal, pide el doble de resolución,
/// se acerca con dos dedos y se mueve arrastrando. Tocar sigue siendo clic.
struct FullScreenMac: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var hint = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveScreen(zoomable: true, zoomOut: $zoom)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: Space.s) {
                Button {
                    Detents.shared.press()
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("cerrar")
                if zoom > 1.02 {
                    Button {
                        Haptic.tap()
                        zoom = 1
                    } label: {
                        Text("\(Int((zoom * 100).rounded())) %")
                            .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Tone.onEmber)
                            .padding(.horizontal, 14).frame(height: 44)
                            .background(Capsule().fill(Tone.ember))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(Space.m)
            .animation(.spring(duration: 0.3), value: zoom > 1.02)
        }
        .overlay(alignment: .bottom) {
            if hint {
                Text("pellizca para acercar · arrastra para moverte · toca para hacer clic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.bottom, Space.l)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            remote.send(.screen(on: true, width: 1800))
            Orientation.request(.landscape)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { hint = false } }
        }
        .onDisappear {
            remote.send(.screen(on: true, width: 960))
            // Devolverle el giro al sistema. Pedir "solo vertical" aquí quedaba
            // como un bloqueo y el iPhone ya no giraba a horizontal.
            Orientation.request(.allButUpsideDown)
        }
    }
}

/// La imagen en vivo, con toque = clic y mantener = clic derecho. Si es
/// `zoomable`, también se acerca con dos dedos y se arrastra.
struct LiveScreen: View {
    @EnvironmentObject private var remote: Remote
    var zoomable: Bool
    var zoomOut: Binding<CGFloat>? = nil
    /// Modo cosechar: el dedo encierra una zona en vez de hacer clic.
    var harvesting: Binding<Bool>? = nil
    /// Si está, los toques van aquí (0…1 sobre la imagen) en vez de a la pantalla del Mac.
    var onTap: ((Double, Double, MouseButton) -> Void)? = nil
    @State private var lasso: CGRect?

    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var tapPoint: CGPoint?
    @State private var taps = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = remote.frame {
                    let fit = fitted(img.size, in: geo.size)
                    Image(uiImage: img).resizable()
                        .interpolation(.medium)
                        .frame(width: fit.width, height: fit.height)
                        .clipShape(RoundedRectangle(cornerRadius: zoomable ? 0 : 14, style: .continuous))
                        .shadow(color: .black.opacity(zoomable ? 0 : 0.4), radius: 18, y: 10)
                        .scaleEffect(scale)
                        .offset(offset)
                        .transition(.opacity)
                    if let p = tapPoint {
                        Circle().stroke(Tone.ember, lineWidth: 3)
                            .frame(width: 44, height: 44)
                            .position(p)
                            .keyframeAnimator(initialValue: RippleState(), trigger: taps) { v, s in
                                v.scaleEffect(s.scale).opacity(s.opacity)
                            } keyframes: { _ in
                                KeyframeTrack(\.scale) { LinearKeyframe(0.4, duration: 0.001); CubicKeyframe(1.6, duration: 0.45) }
                                KeyframeTrack(\.opacity) { LinearKeyframe(1, duration: 0.001); CubicKeyframe(0, duration: 0.45) }
                            }
                            .allowsHitTesting(false)
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if let r = lasso {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Tone.ember.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Tone.ember, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(harvestGesture(geo.size), including: harvesting?.wrappedValue == true ? .all : .none)
            .onTapGesture(coordinateSpace: .local) { p in click(p, geo.size, .left) }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        if case .second(true, let drag?) = value { click(drag.location, geo.size, .right) }
                    }
            )
            .gesture(zoomGesture, including: zoomable ? .all : .none)
            .onChange(of: zoomOut?.wrappedValue) { _, z in
                // El botón de porcentaje vuelve al 100 %.
                if z == 1, scale != 1 { withAnimation(.spring(duration: 0.4)) { reset() } }
            }
        }
    }

    /// Encerrar una zona: se dibuja el rectángulo y al soltar se pide al Mac.
    private func harvestGesture(_ box: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                lasso = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                               width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
            }
            .onEnded { _ in
                defer {
                    withAnimation(.easeOut(duration: 0.3)) { lasso = nil }
                    harvesting?.wrappedValue = false
                }
                guard let r = lasso, r.width > 12, r.height > 12, let a = normalized(r.origin, box),
                      let b = normalized(CGPoint(x: r.maxX, y: r.maxY), box, clamp: true) else { return }
                Detents.shared.press()
                remote.send(.harvest(x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y))
            }
    }

    /// Punto de la vista → punto 0…1 de la pantalla del Mac.
    private func normalized(_ p: CGPoint, _ box: CGSize, clamp: Bool = true) -> CGPoint? {
        guard let img = remote.frame else { return nil }
        let fit = fitted(img.size, in: box)
        let x = ((p.x - box.width / 2 - offset.width) / scale) / fit.width + 0.5
        let y = ((p.y - box.height / 2 - offset.height) / scale) / fit.height + 0.5
        return CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                scale = min(5, max(1, base * v.magnification))
                zoomOut?.wrappedValue = scale
            }
            .onEnded { _ in
                base = scale
                if scale < 1.05 { withAnimation(.spring(duration: 0.35)) { reset() } }
            }
            .simultaneously(with: DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard scale > 1 else { return }
                    offset = CGSize(width: baseOffset.width + v.translation.width,
                                    height: baseOffset.height + v.translation.height)
                }
                .onEnded { _ in baseOffset = offset })
    }

    private func reset() {
        scale = 1
        base = 1
        offset = .zero
        baseOffset = .zero
        zoomOut?.wrappedValue = 1
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            if remote.canCapture {
                RadarRings(color: Tone.ember).frame(width: 60, height: 60)
                Text("Mirando la pantalla del Mac…")
                    .font(.callout.weight(.medium)).foregroundStyle(Tone.ink.opacity(0.75))
            } else {
                Image(systemName: "rectangle.dashed").font(.system(size: 44, weight: .light))
                    .foregroundStyle(Tone.ink.opacity(0.6))
                Text("En el Mac, dale a Zarcillo el permiso de Grabación de pantalla (menú de la hoja › Dar permiso…).")
                    .font(.callout.weight(.medium)).multilineTextAlignment(.center)
                    .foregroundStyle(Tone.ink.opacity(0.75)).padding(.horizontal, 30)
            }
        }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        let s = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * s, height: size.height * s)
    }

    /// Punto tocado → punto de la pantalla del Mac, deshaciendo zoom y desplazamiento.
    private func click(_ p: CGPoint, _ box: CGSize, _ button: MouseButton) {
        guard let img = remote.frame else { return }
        let fit = fitted(img.size, in: box)
        let qx = (p.x - box.width / 2 - offset.width) / scale
        let qy = (p.y - box.height / 2 - offset.height) / scale
        let x = qx / fit.width + 0.5, y = qy / fit.height + 0.5
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        tapPoint = p
        taps += 1
        Haptic.tap()
        if let onTap { onTap(x, y, button) } else { remote.send(.tapScreen(x: x, y: y, button: button)) }
    }
}

enum Orientation {
    /// Pide al sistema estas orientaciones. Lo pedido persiste, así que siempre
    /// hay que devolver `.allButUpsideDown` al terminar.
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}
