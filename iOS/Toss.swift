import PhotosUI
import SwiftUI
import UIKit

/// Tirar fotos al Mac: se apilan como hojas y cada una se lanza hacia arriba
/// con el dedo. Sale volando meciéndose y en el Mac cae desde lo alto de la
/// pantalla, como una hoja que se suelta de un árbol.
struct TossPage: View {
    @EnvironmentObject private var remote: Remote
    @State private var picks: [PhotosPickerItem] = []
    @State private var stack: [Leaf] = []
    @State private var flights: [Flight] = []
    @State private var drag: CGSize = .zero
    @State private var loading = false
    @State private var sent = 0

    struct Leaf: Identifiable {
        let id = UUID()
        let preview: UIImage
        let data: Data
    }

    struct Flight: Identifiable {
        let id = UUID()
        let preview: UIImage
        let start: Date
        let spin: Double
        let from: CGSize
    }

    private let card = CGSize(width: 170, height: 226)
    private static let flightTime = 0.95

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if stack.isEmpty && flights.isEmpty {
                    empty
                } else {
                    pile
                    VStack {
                        Spacer()
                        controls
                    }
                    .padding(Space.m)
                }
                // Las hojas que ya van volando hacia el Mac.
                TimelineView(.animation(paused: flights.isEmpty)) { tl in
                    ZStack {
                        ForEach(flights) { f in
                            let t = min(1, tl.date.timeIntervalSince(f.start) / Self.flightTime)
                            LeafCard(image: f.preview, size: card)
                                .scaleEffect(1 - 0.45 * t)
                                .rotationEffect(.degrees(f.spin * t * 140 + sin(t * .pi * 3) * 18))
                                .offset(x: f.from.width + sin(t * .pi * 2.5) * 60 * (1 - t),
                                        y: f.from.height - (geo.size.height + card.height) * t * t)
                                .opacity(t > 0.8 ? (1 - t) / 0.2 : 1)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: picks) { _, items in load(items) }
    }

    private var empty: some View {
        VStack(spacing: Space.m) {
            PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                ZStack {
                    LeafShape().fill(Tone.ember.opacity(0.18))
                    LeafShape().stroke(Tone.ember, lineWidth: 2.5)
                    LeafVein().stroke(Tone.ember.opacity(0.6), lineWidth: 2)
                    Image(systemName: "photo.badge.plus").font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Tone.ember)
                }
                .frame(width: 110, height: 146)
                .floating()
            }
            .buttonStyle(PressScale())
            Text("elige fotos y tíralas al Mac")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Tone.ink)
            Text("desliza cada una hacia arriba: caerá en tu Mac como una hoja")
                .font(.system(size: 13)).foregroundStyle(Tone.ink.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
            if loading { ProgressView().tint(Tone.ember) }
        }
    }

    /// La pila: la de arriba se arrastra; las de abajo se asoman giradas.
    private var pile: some View {
        ZStack {
            ForEach(Array(stack.prefix(4).enumerated().reversed()), id: \.element.id) { i, leaf in
                let top = i == 0
                LeafCard(image: leaf.preview, size: card)
                    .rotationEffect(.degrees(top ? Double(drag.width) / 14 : Double(i) * (i % 2 == 0 ? 5 : -5)))
                    .offset(x: top ? drag.width : 0, y: top ? drag.height : CGFloat(i) * 8)
                    .scaleEffect(top ? 1 + min(0.06, abs(drag.height) / 3000) : 1 - CGFloat(i) * 0.05)
                    .gesture(top ? DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            if v.predictedEndTranslation.height < -220 || v.translation.height < -150 {
                                toss(from: v.translation)
                            } else {
                                withAnimation(.spring(duration: 0.45, bounce: 0.45)) { drag = .zero }
                            }
                        } : nil)
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: stack.count)
            }
        }
        .offset(y: -30)
    }

    private var controls: some View {
        HStack(spacing: Space.s + 2) {
            PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                Label("más", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tone.ink.opacity(0.85))
                    .padding(.horizontal, Space.m).frame(height: Space.tap)
                    .background(Capsule().fill(Tone.key))
                    .overlay(Capsule().stroke(Tone.stroke, lineWidth: 1))
            }
            Spacer()
            Text(stack.count == 1 ? "1 foto" : "\(stack.count) fotos")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tone.ink.opacity(0.5))
                .contentTransition(.numericText())
            Spacer()
            Button { tossAll() } label: {
                Label("tirar todas", systemImage: "leaf.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Tone.onEmber)
                    .padding(.horizontal, Space.m).frame(height: Space.tap)
                    .background(Capsule().fill(Tone.ember))
                    .shadow(color: Tone.ember.opacity(0.5), radius: 10)
            }
            .buttonStyle(PressScale())
            .disabled(stack.isEmpty)
        }
    }

    // MARK: Acciones

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loading = true
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                let preview = await image.byPreparingThumbnail(ofSize: CGSize(width: 520, height: 700)) ?? image
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
                    stack.append(Leaf(preview: preview, data: Self.sendable(data, image)))
                }
            }
            picks = []
            loading = false
        }
    }

    /// Las fotos viajan con sus bytes originales. Solo las enormes (ProRAW,
    /// panorámicas) se pasan a JPEG para no pasarse del tamaño de un mensaje.
    private static func sendable(_ data: Data, _ image: UIImage) -> Data {
        guard data.count > 18_000_000 else { return data }
        return image.jpegData(compressionQuality: 0.9) ?? data
    }

    private func toss(from offset: CGSize) {
        guard let leaf = stack.first else { return }
        Detents.shared.press()
        remote.send(.photo(leaf.data))
        sent += 1
        flights.append(Flight(preview: leaf.preview, start: Date(), spin: offset.width >= 0 ? 1 : -1, from: offset))
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            stack.removeFirst()
            drag = .zero
        }
        let id = flights.last?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flightTime + 0.05) {
            flights.removeAll { $0.id == id }
        }
    }

    private func tossAll() {
        let n = stack.count
        for i in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.32) {
                toss(from: CGSize(width: CGFloat.random(in: -30...30), height: -20))
            }
        }
    }
}

/// Una foto recortada como hoja, con su nervadura y un borde en el acento.
struct LeafCard: View {
    let image: UIImage
    let size: CGSize

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(LeafShape())
            LeafVein().stroke(.white.opacity(0.45), lineWidth: 2)
            LeafShape().stroke(Tone.ember, lineWidth: 3)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        .shadow(color: Tone.ember.opacity(0.35), radius: 16)
    }
}
