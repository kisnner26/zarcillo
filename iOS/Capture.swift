import SwiftUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - Escanear

/// Dos formas de usar la cámara del iPhone para el Mac: leer texto en vivo y
/// escribirlo donde está el cursor, o fotografiar una pizarra, un proyector o
/// un cuaderno y mandarlo enderezado como PDF.
struct ScanPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var live = false
    @State private var document = false

    var body: some View {
        StageScroll(spacing: Space.m) {
                option("texto al cursor", "text.viewfinder",
                       "Apunta a una hoja, un libro o una pantalla. Toca un texto y se escribe donde está el cursor del Mac.") {
                    live = true
                }
                option("pizarra o apuntes", "doc.viewfinder",
                       "Fotografía la pizarra, el proyector o tu cuaderno, aunque estés de lado. Llega al Mac enderezado, como PDF con el texto buscable.") {
                    document = true
                }
        }
        .fullScreenCover(isPresented: $live) {
            LiveTextScanner { text in
                Detents.shared.press()
                remote.send(.type(text: text))
                remote.flash("escrito en el Mac")
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { closeButton { live = false } }
        }
        .fullScreenCover(isPresented: $document) {
            DocumentScanner { pages in
                document = false
                guard !pages.isEmpty else { return }
                remote.send(.scanPages(pages))
                remote.flash("enviando \(pages.count) página\(pages.count == 1 ? "" : "s") al Mac…")
            }
            .ignoresSafeArea()
        }
    }

    private func option(_ title: String, _ symbol: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            action()
        } label: {
            CeramicCard {
                HStack(spacing: Space.m) {
                    Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Tone.onEmber)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Tone.ember))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                        Text(detail).font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.55))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(PressScale())
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.55)))
        }
        .padding(Space.l)
    }
}

/// Texto en vivo de la cámara: el iPhone lo reconoce sin internet.
struct LiveTextScanner: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let t) = item { onText(t.transcript) }
        }
    }
}

/// El escáner de documentos del sistema: detecta los bordes y endereza la
/// perspectiva de cada página.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        init(onFinish: @escaping ([Data]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.8) }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}

// MARK: - Enviar al Mac

/// El bolsillo: archivos, links y texto hacia el Mac.
struct SendPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var importing = false
    @State private var link = ""
    @State private var text = ""

    var body: some View {
        StageScroll(spacing: Space.l) {
                Button {
                    Detents.shared.press()
                    importing = true
                } label: {
                    CeramicCard {
                        HStack(spacing: Space.m) {
                            Image(systemName: "doc.badge.arrow.up.fill").font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Tone.onEmber)
                                .frame(width: 60, height: 60).background(Circle().fill(Tone.ember))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("archivo al bolsillo").font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(Tone.ink)
                                Text("PDF, audio, video, lo que sea: cae en el Mac y lo arrastras a donde quieras.")
                                    .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.55))
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .buttonStyle(PressScale())

                WideButton(title: "traer la pestaña del Mac", symbol: "safari", filled: false) {
                    remote.send(.pullTab)
                }

                VStack(spacing: Space.s) {
                    SectionLabel(text: "abrir un link en el Mac")
                    HStack(spacing: Space.s) {
                        TextField("https://…", text: $link)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(size: 15)).foregroundStyle(Tone.ink)
                            .padding(.horizontal, 14).frame(height: 48)
                            .background(Capsule().fill(Tone.key))
                        pill("pegar") { link = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? link }
                        pill("abrir", filled: true) {
                            remote.send(.openURL(link.contains("://") ? link : "https://" + link))
                            link = ""
                        }
                        .disabled(link.isEmpty)
                    }
                }

                VStack(spacing: Space.s) {
                    SectionLabel(text: "escribir texto donde está el cursor")
                    TextField("un párrafo, un correo, una dirección…", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 15)).foregroundStyle(Tone.ink)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
                    WideButton(title: "escribir en el Mac", symbol: "keyboard") {
                        remote.send(.type(text: text))
                        text = ""
                    }
                    .disabled(text.isEmpty)
                    .opacity(text.isEmpty ? 0.5 : 1)
                }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), data.count < 25_000_000 else {
                    remote.flash("\(url.lastPathComponent) pesa demasiado (máx. 25 MB)")
                    continue
                }
                remote.send(.file(name: url.lastPathComponent, data: data))
            }
        }
    }

    private func pill(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Tone.onEmber : Tone.ink.opacity(0.85))
                .padding(.horizontal, 16).frame(height: 48)
                .background(Capsule().fill(filled ? Tone.ember : Tone.key))
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - La hoja cosechada

/// Lo cosechado cae desde arriba de la pantalla como una hoja y se guarda.
struct HarvestFall: View {
    @EnvironmentObject private var remote: Remote
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            GeometryReader { geo in
                if let start, let img = remote.harvestImage {
                    let t = min(1, tl.date.timeIntervalSince(start) / 1.6)
                    LeafCard(image: img, size: CGSize(width: 150, height: 200))
                        .rotationEffect(.degrees(sin(t * .pi * 3) * 22 * (1 - t)))
                        .scaleEffect(1 - 0.6 * t * t)
                        .position(x: geo.size.width / 2 + sin(t * .pi * 2.5) * 70 * (1 - t),
                                  y: -120 + (geo.size.height * 0.62 + 120) * (1 - pow(1 - t, 1.8)))
                        .opacity(t > 0.85 ? (1 - t) / 0.15 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: remote.harvests) { _, _ in
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { start = nil }
        }
    }
}
