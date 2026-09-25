import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Las fichas de plantas reales. Se guardan en el iPhone (ficha en JSON, foto en JPEG).
@MainActor
final class HerbStore: ObservableObject {
    static let shared = HerbStore()
    @Published private(set) var cards: [HerbCard] = []
    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Herbario", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("fichas.json")),
           let saved = try? JSONDecoder().decode([HerbCard].self, from: data) { cards = saved }
    }

    func photo(_ id: String) -> UIImage? { UIImage(contentsOfFile: dir.appendingPathComponent("\(id).jpg").path) }

    func add(_ card: HerbCard, photo: UIImage) {
        try? photo.jpegData(compressionQuality: 0.8)?.write(to: dir.appendingPathComponent("\(card.id).jpg"))
        cards.insert(card, at: 0)
        save()
    }

    /// Llegó la ficha completa del Mac: conserva el tono y la fecha de la provisional.
    func complete(_ card: HerbCard) {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var c = card
        c.hue = cards[i].hue
        c.date = cards[i].date
        cards[i] = c
        save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func remove(_ card: HerbCard) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(card.id).jpg"))
        cards.removeAll { $0.id == card.id }
        save()
    }

    private func save() {
        try? JSONEncoder().encode(cards).write(to: dir.appendingPathComponent("fichas.json"))
    }
}

enum PlantVision {
    /// Lo que Vision ve en la foto, de más a menos seguro. Es una clasificación general, no un experto en plantas:
    /// por eso el Mac la pasa después por Claude para armar la ficha.
    static func labels(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached {
            let request = VNClassifyImageRequest()
            try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            let found = (request.results ?? []).filter { $0.confidence > 0.08 }.prefix(8)
            return found.map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
    }

    /// El tono medio del centro de la foto (0…1): así la planta del jardín tiene su color.
    static func hue(_ image: UIImage) -> Double {
        guard let ci = CIImage(image: image) else { return 0.3 }
        let e = ci.extent
        let center = ci.cropped(to: e.insetBy(dx: e.width * 0.25, dy: e.height * 0.25))
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: center, kCIInputExtentKey: CIVector(cgRect: center.extent)]),
              let out = f.outputImage else { return 0.3 }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: nil, brightness: nil, alpha: nil)
        return Double(h)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct HerbariumPage: View {
    @EnvironmentObject private var remote: Remote
    @ObservedObject private var store = HerbStore.shared
    @State private var camera = false
    @State private var working = false

    var body: some View {
        StageScroll(spacing: Space.m) {
            HeroMark(symbol: "leaf.circle").foregroundStyle(Tone.leaf)
                .symbolEffect(.pulse, isActive: working)

            Button {
                Detents.shared.press()
                camera = true
            } label: {
                Label(working ? "leyendo la planta…" : "fotografiar una planta", systemImage: "camera.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Tone.onEmber)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(Tone.ember))
            }
            .buttonStyle(PressScale())
            .disabled(working)

            ForEach(store.cards) { card in
                herbCard(card)
            }

            Hint(store.cards.isEmpty
                 ? "Apunta la cámara a una planta. El iPhone reconoce lo que ve y el Mac, con Claude, arma la ficha (riego, luz, cuidado). La planta aparece dibujada en tu jardín."
                 : "El reconocimiento es aproximado: es una clasificación general de imágenes, no un botánico. Ante la duda, la ficha lo dice.")
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in capture(image) }.ignoresSafeArea()
        }
    }

    private func capture(_ image: UIImage) {
        working = true
        Task {
            let labels = await PlantVision.labels(image)
            let id = UUID().uuidString
            let provisional = HerbCard(id: id, name: labels.first?.capitalized ?? "Sin identificar", scientific: "",
                                       water: "", light: "", tip: "identificando…", labels: labels, hue: PlantVision.hue(image))
            store.add(provisional, photo: image)
            remote.send(.herbarium(id: id, labels: labels))
            working = false
        }
    }

    private func herbCard(_ card: HerbCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let p = store.photo(card.id) {
                    Image(uiImage: p).resizable().scaledToFill().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Tone.ink)
                    if !card.scientific.isEmpty {
                        Text(card.scientific).font(.system(size: 12)).italic().foregroundStyle(Tone.ink.opacity(0.55))
                    }
                    Text(Date(timeIntervalSince1970: card.date).formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11)).foregroundStyle(Tone.ink.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            if !card.water.isEmpty { line("drop.fill", card.water) }
            if !card.light.isEmpty { line("sun.max.fill", card.light) }
            if !card.tip.isEmpty { line("lightbulb.fill", card.tip) }
            HStack(spacing: Space.s) {
                pill("enviar al Mac", "laptopcomputer") { sendToMac(card) }
                pill("borrar", "trash") { store.remove(card) }
            }
        }
        .padding(Space.m)
        .glass(22)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.8))
            .labelStyle(.titleAndIcon).fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button {
            Detents.shared.press()
            run()
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(Tone.recess))
        }
        .buttonStyle(PressScale())
    }

    /// La ficha como texto y la foto, a la carpeta de recibidos del Mac.
    private func sendToMac(_ card: HerbCard) {
        var md = "# \(card.name)\n"
        if !card.scientific.isEmpty { md += "*\(card.scientific)*\n" }
        md += "\n- Riego: \(card.water)\n- Luz: \(card.light)\n- Consejo: \(card.tip)\n"
        remote.send(.file(name: "Herbario - \(card.name).md", data: Data(md.utf8)))
        if let jpg = store.photo(card.id)?.jpegData(compressionQuality: 0.85) {
            remote.send(.file(name: "Herbario - \(card.name).jpg", data: jpg))
        }
        remote.flash("ficha enviada al Mac")
    }
}
