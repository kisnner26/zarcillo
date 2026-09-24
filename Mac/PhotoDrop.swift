import AppKit
import SwiftUI

/// Las fotos que el iPhone "tira" al Mac.
///
/// Cada foto entra por arriba de la pantalla dentro de una hoja, cae meciéndose
/// como una hoja que se suelta de un árbol, y al tocar el suelo se abre en una
/// tarjeta que queda en la bandeja de la esquina. La foto ya está guardada en
/// Descargas › Zarcillo desde que llega; la animación es solo la bienvenida.
@MainActor
final class PhotoDrop: ObservableObject {
    struct Falling: Identifiable {
        let id = UUID()
        let image: NSImage
        let start: Date
        /// Desde qué punto del ancho cae (0…1) y hacia qué lado se mece primero.
        let from: CGFloat
        let sway: CGFloat
    }

    struct Landed: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let image: NSImage
    }

    static let fall: TimeInterval = 2.6

    @Published private(set) var falling: [Falling] = []
    @Published private(set) var landed: [Landed] = []
    @Published var trayHovered = false

    private var sky: NSPanel?
    private var tray: NSPanel?
    private var hideTray: DispatchWorkItem?
    private var screen: NSScreen?
    private var queued = 0

    private static var folder: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let dir = downloads.appendingPathComponent("Zarcillo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func receive(_ data: Data) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        var url = Self.folder.appendingPathComponent("foto \(f.string(from: Date())).\(ImageKind.fileExtension(of: data))")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = Self.folder.appendingPathComponent("foto \(f.string(from: Date())) \(n).\(ImageKind.fileExtension(of: data))")
            n += 1
        }
        try? data.write(to: url)
        guard let image = NSImage(data: data) else { return }

        screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        showSky()
        // Si llegan varias juntas, caen escalonadas y no todas a la vez.
        let delay = Double(queued) * 0.45
        queued += 1
        let leaf = Falling(image: image, start: Date().addingTimeInterval(delay),
                           from: CGFloat.random(in: 0.3...0.7), sway: Bool.random() ? 1 : -1)
        falling.append(leaf)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.fall) { [weak self] in
            guard let self else { return }
            self.queued = max(0, self.queued - 1)
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) {
                self.falling.removeAll { $0.id == leaf.id }
                self.landed.insert(Landed(url: url, image: image), at: 0)
                if self.landed.count > 5 { self.landed.removeLast(self.landed.count - 5) }
            }
            NSSound(named: "Pop")?.play()
            self.showTray()
            if self.falling.isEmpty { self.sky?.orderOut(nil) }
        }
    }

    func open(_ item: Landed) {
        NSWorkspace.shared.open(item.url)
    }

    func revealAll() {
        NSWorkspace.shared.activateFileViewerSelecting(landed.map(\.url))
    }

    func dismissTray() {
        withAnimation(.easeOut(duration: 0.3)) { landed.removeAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.tray?.orderOut(nil) }
    }

    // MARK: Paneles

    private func showSky() {
        guard let s = screen else { return }
        let p = sky ?? makePanel(frame: s.frame, clickable: false, content: AnyView(SkyView(drop: self)))
        if p.frame != s.frame { p.setFrame(s.frame, display: false) }
        p.orderFrontRegardless()
        sky = p
    }

    private func showTray() {
        guard let s = screen else { return }
        let size = NSSize(width: 460, height: 190)
        let frame = NSRect(x: s.visibleFrame.maxX - size.width - 12, y: s.visibleFrame.minY + 12,
                           width: size.width, height: size.height)
        let p = tray ?? makePanel(frame: frame, clickable: true, content: AnyView(TrayView(drop: self)))
        if p.frame != frame { p.setFrame(frame, display: false) }
        p.orderFrontRegardless()
        tray = p
        scheduleTrayHide()
    }

    /// La bandeja se va sola a los 8 s, salvo que el cursor esté encima.
    func scheduleTrayHide() {
        hideTray?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.trayHovered { self.scheduleTrayHide(); return }
            self.dismissTray()
        }
        hideTray = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func makePanel(frame: NSRect, clickable: Bool, content: AnyView) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = !clickable
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = fixedHost(content)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }
}

// MARK: - La caída

private struct SkyView: View {
    @ObservedObject var drop: PhotoDrop

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                ZStack {
                    ForEach(drop.falling) { leaf in
                        let t = min(1, max(0, tl.date.timeIntervalSince(leaf.start) / PhotoDrop.fall))
                        if tl.date >= leaf.start {
                            FallingLeaf(image: leaf.image, t: t)
                                .rotationEffect(.degrees(Double(leaf.sway) * sin(t * .pi * 4) * 28 * (1 - t) + Double(leaf.sway) * 8))
                                .position(position(leaf, t: t, in: geo.size))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Cae en zigzag, cada vez con menos vaivén, hasta la esquina de la bandeja.
    private func position(_ leaf: PhotoDrop.Falling, t: Double, in size: CGSize) -> CGPoint {
        let startX = size.width * leaf.from
        let endX = size.width - 190
        let endY = size.height - 110
        let ease = t * t * (3 - 2 * t)
        let x = startX + (endX - startX) * ease + leaf.sway * sin(t * .pi * 3.2) * 120 * (1 - t)
        // La caída acelera y frena, como una hoja que planea.
        let y = -140 + (endY + 140) * (1 - pow(1 - t, 1.6))
        return CGPoint(x: x, y: y)
    }
}

/// La foto recortada en forma de hoja, con su nervadura y un borde de luz.
private struct FallingLeaf: View {
    let image: NSImage
    let t: Double

    var body: some View {
        ZStack {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 150, height: 200)
                .clipShape(LeafShape())
            LeafVein().stroke(.white.opacity(0.5), lineWidth: 2).frame(width: 150, height: 200)
            LeafShape().stroke(Color(nsColor: Accent.nsColor), lineWidth: 3).frame(width: 150, height: 200)
        }
        .frame(width: 150, height: 200)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .shadow(color: Color(nsColor: Accent.nsColor).opacity(0.5), radius: 18)
        .scaleEffect(1 - 0.35 * t)
        // Aparece desde arriba y se desvanece justo al tocar el suelo.
        .opacity(t < 0.06 ? t / 0.06 : (t > 0.94 ? (1 - t) / 0.06 : 1))
    }
}

// MARK: - La bandeja

private struct TrayView: View {
    @ObservedObject var drop: PhotoDrop
    @State private var hovered: UUID?

    var body: some View {
        let accent = Color(nsColor: Accent.nsColor)
        HStack(spacing: 14) {
            ZStack {
                ForEach(Array(drop.landed.enumerated().reversed()), id: \.element.id) { i, item in
                    Button { drop.open(item) } label: {
                        Image(nsImage: item.image).resizable().scaledToFill()
                            .frame(width: 110, height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(i == 0 ? accent : .white.opacity(0.25), lineWidth: i == 0 ? 2.5 : 1))
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(Double(i) * -7))
                    .offset(x: CGFloat(i) * -14, y: CGFloat(i) * 4)
                    .scaleEffect(hovered == item.id ? 1.06 : 1)
                    .onHover { hovered = $0 ? item.id : nil }
                    .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity),
                                            removal: .opacity))
                }
            }
            .frame(width: 170, height: 160)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").foregroundStyle(accent)
                    Text(drop.landed.count == 1 ? "Llegó una foto" : "Llegaron \(drop.landed.count) fotos")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("en Descargas › Zarcillo")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 8) {
                    Button("Abrir") { if let first = drop.landed.first { drop.open(first) } }
                        .buttonStyle(Pill(fill: accent, fg: .black.opacity(0.85)))
                    Button("Mostrar") { drop.revealAll() }
                        .buttonStyle(Pill(fill: .white.opacity(0.12), fg: .white))
                    Button { drop.dismissTray() } label: { Image(systemName: "xmark") }
                        .buttonStyle(Pill(fill: .white.opacity(0.08), fg: .white.opacity(0.7)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MacTone.body.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(MacTone.stroke, lineWidth: 1))
                .shadow(color: accent.opacity(0.25), radius: 20)
        )
        .onHover { drop.trayHovered = $0 }
        .opacity(drop.landed.isEmpty ? 0 : 1)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: drop.landed)
    }
}

struct Pill: ButtonStyle {
    var fill: Color
    var fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
