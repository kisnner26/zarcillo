import SwiftUI
import UIKit

// MARK: - Escena: el zarcillo que va del iPhone al Mac

/// Guarda el crecimiento suavizado entre fotogramas (no es estado de SwiftUI: solo se lee al dibujar).
private final class Growth {
    var value = 0.0
    var last = Date.timeIntervalSinceReferenceDate
    func step(toward target: Double, _ now: TimeInterval) -> Double {
        let dt = min(0.1, now - last)
        last = now
        value += (target - value) * min(1, dt * 2.2)
        return value
    }
}

enum ConnectStage {
    case searching, choosing, code, connecting

    /// Cuánto ha crecido el zarcillo hacia el Mac.
    var growth: Double {
        switch self {
        case .searching: 0.42
        case .choosing: 0.62
        case .code: 0.86
        case .connecting: 1.0
        }
    }
}

/// Un Mac arriba, un iPhone abajo y una enredadera que sube de uno al otro: es
/// lo que hace la app. Se dibuja siempre con la misma proporción (0.78) para que
/// nada se deforme, y todo es simétrico respecto al centro.
struct VineScene: View {
    let stage: ConnectStage
    static let aspect: CGFloat = 0.78
    private let growth = Growth()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let g = growth.step(toward: stage.growth, t)
                draw(&ctx, size, t, g)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var lit: Bool { stage == .connecting }

    // Geometría (fracciones del ancho w y el alto h).
    private func screenRect(_ w: Double, _ h: Double) -> CGRect { CGRect(x: w * 0.12, y: h * 0.03, width: w * 0.76, height: h * 0.34) }
    private func phoneRect(_ w: Double, _ h: Double) -> CGRect { CGRect(x: w * 0.395, y: h * 0.72, width: w * 0.21, height: h * 0.275) }

    /// El tallo: de la parte de arriba del iPhone a la base del Mac, en S.
    private func stem(_ u: Double, _ w: Double, _ h: Double) -> CGPoint {
        let p0 = CGPoint(x: 0.5, y: 0.72), p1 = CGPoint(x: 0.24, y: 0.63)
        let p2 = CGPoint(x: 0.76, y: 0.50), p3 = CGPoint(x: 0.5, y: 0.405)
        let a = pow(1 - u, 3), b = 3 * u * pow(1 - u, 2), c = 3 * u * u * (1 - u), d = u * u * u
        return CGPoint(x: (a * p0.x + b * p1.x + c * p2.x + d * p3.x) * w, y: (a * p0.y + b * p1.y + c * p2.y + d * p3.y) * h)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: TimeInterval, _ g: Double) {
        let w = size.width, h = size.height
        let screen = screenRect(w, h)

        // Halo detrás del Mac: más fuerte al conectar.
        let halo = w * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: screen.midX - halo, y: screen.midY - halo, width: halo * 2, height: halo * 2)),
                 with: .radialGradient(Gradient(colors: [Tone.ember.opacity(lit ? 0.30 : 0.12), .clear]),
                                       center: CGPoint(x: screen.midX, y: screen.midY), startRadius: 0, endRadius: halo))

        // Polen flotando.
        for k in 0..<18 {
            let a = frac(Double(k) * 0.618 + 0.1), b = frac(Double(k) * 0.414 + 0.2)
            let x = (a + 0.025 * sin(t * 0.5 + Double(k))) * w
            let y = (b + 0.02 * cos(t * 0.6 + Double(k) * 2)) * h
            let glow = 0.12 + 0.22 * (0.5 + 0.5 * sin(t * 1.3 + Double(k) * 1.7))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(Tone.ember.opacity(glow)))
        }

        mac(&ctx, w, h, t)
        phone(&ctx, w, h, t)
        vine(&ctx, w, h, t, g)
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }

    // MARK: Mac (de frente)

    private func mac(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: TimeInterval) {
        let screen = screenRect(w, h)
        let lid = RoundedRectangle(cornerRadius: w * 0.035, style: .continuous).path(in: screen)
        ctx.fill(lid, with: .color(Color(red: 0.09, green: 0.075, blue: 0.07)))
        ctx.stroke(lid, with: .color(lit ? Tone.ember.opacity(0.85) : Tone.ink.opacity(0.28)), lineWidth: 1.5)

        let glass = screen.insetBy(dx: w * 0.025, dy: w * 0.025)
        let glassPath = RoundedRectangle(cornerRadius: w * 0.012, style: .continuous).path(in: glass)
        ctx.fill(glassPath, with: .linearGradient(
            Gradient(colors: lit ? [Tone.ember.opacity(0.55), Tone.emberDeep.opacity(0.35)] : [Tone.key, Tone.recess]),
            startPoint: CGPoint(x: glass.minX, y: glass.minY), endPoint: CGPoint(x: glass.maxX, y: glass.maxY)))
        // Cámara.
        ctx.fill(Path(ellipseIn: CGRect(x: screen.midX - 2, y: screen.minY + w * 0.011, width: 4, height: 4)), with: .color(Tone.ink.opacity(0.25)))

        var inner = ctx
        inner.clip(to: glassPath)
        switch stage {
        case .searching:
            // Ondas que salen del centro: el Mac se está anunciando.
            for k in 0..<3 {
                let p = frac(t * 0.45 + Double(k) / 3)
                let r = glass.width * 0.08 + p * glass.width * 0.5
                inner.stroke(Path(ellipseIn: CGRect(x: glass.midX - r, y: glass.midY - r, width: r * 2, height: r * 2)),
                             with: .color(Tone.ember.opacity(0.45 * (1 - p))), lineWidth: 1.5)
            }
            leafIcon(&inner, CGPoint(x: glass.midX, y: glass.midY), glass.height * 0.22, Tone.ink.opacity(0.5), tilt: 0)
        case .choosing:
            leafIcon(&inner, CGPoint(x: glass.midX, y: glass.midY), glass.height * 0.28, Tone.ink.opacity(0.6), tilt: 0)
        case .code:
            // Seis puntos, como el código que muestra el Mac.
            let d = glass.width * 0.055
            for i in 0..<6 {
                let x = glass.midX + (Double(i) - 2.5) * d * 2.1 + (i >= 3 ? d * 0.6 : -d * 0.6)
                let o = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 2.4 - Double(i) * 0.6))
                inner.fill(RoundedRectangle(cornerRadius: d * 0.35).path(in: CGRect(x: x - d * 0.8, y: glass.midY - d, width: d * 1.6, height: d * 2)),
                           with: .color(Tone.ink.opacity(o)))
            }
        case .connecting:
            leafIcon(&inner, CGPoint(x: glass.midX, y: glass.midY), glass.height * 0.36 * (1 + 0.04 * sin(t * 3)), Tone.onEmber, tilt: 0)
        }

        // Base: una lámina con la muesca para abrir la tapa.
        let bw = w * 0.92, by = screen.maxY + h * 0.002
        var base = Path()
        base.move(to: CGPoint(x: w / 2 - bw / 2 + w * 0.02, y: by))
        base.addLine(to: CGPoint(x: w / 2 + bw / 2 - w * 0.02, y: by))
        base.addQuadCurve(to: CGPoint(x: w / 2 + bw / 2, y: by + h * 0.028), control: CGPoint(x: w / 2 + bw / 2, y: by))
        base.addLine(to: CGPoint(x: w / 2 - bw / 2, y: by + h * 0.028))
        base.addQuadCurve(to: CGPoint(x: w / 2 - bw / 2 + w * 0.02, y: by), control: CGPoint(x: w / 2 - bw / 2, y: by))
        base.closeSubpath()
        ctx.fill(base, with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.37, blue: 0.35), Color(red: 0.22, green: 0.19, blue: 0.18)]),
                                             startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + h * 0.028)))
        ctx.fill(RoundedRectangle(cornerRadius: 3).path(in: CGRect(x: w / 2 - w * 0.08, y: by, width: w * 0.16, height: h * 0.008)),
                 with: .color(.black.opacity(0.35)))
        ctx.stroke(base, with: .color(Tone.ink.opacity(0.25)), lineWidth: 1)
    }

    // MARK: iPhone (de frente)

    private func phone(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: TimeInterval) {
        let body = phoneRect(w, h)
        let shape = RoundedRectangle(cornerRadius: body.width * 0.2, style: .continuous).path(in: body)
        ctx.fill(shape, with: .color(Color(red: 0.09, green: 0.075, blue: 0.07)))
        ctx.stroke(shape, with: .color(Tone.ink.opacity(0.35)), lineWidth: 1.5)
        let glass = body.insetBy(dx: body.width * 0.07, dy: body.width * 0.07)
        let gp = RoundedRectangle(cornerRadius: body.width * 0.14, style: .continuous).path(in: glass)
        ctx.fill(gp, with: .linearGradient(Gradient(colors: [Tone.ember.opacity(0.35), Tone.recess]),
                                           startPoint: CGPoint(x: glass.midX, y: glass.minY), endPoint: CGPoint(x: glass.midX, y: glass.maxY)))
        // Isla dinámica.
        ctx.fill(Capsule().path(in: CGRect(x: glass.midX - glass.width * 0.2, y: glass.minY + glass.width * 0.08,
                                           width: glass.width * 0.4, height: glass.width * 0.12)), with: .color(.black))
        leafIcon(&ctx, CGPoint(x: glass.midX, y: glass.midY + glass.height * 0.06), glass.width * 0.42, Tone.ember, tilt: 8 * sin(t * 1.1))
    }

    /// El icono de la hoja (el mismo de la app), centrado en `c`, de alto `s`.
    private func leafIcon(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: Double, _ color: Color, tilt: Double) {
        var l = ctx
        l.translateBy(x: c.x, y: c.y)
        l.rotate(by: .degrees(tilt))
        var img = l.resolve(Image(systemName: "leaf.fill").resizable())
        img.shading = .color(color)
        l.draw(img, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
    }

    // MARK: Enredadera

    private func vine(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: TimeInterval, _ g: Double) {
        let n = max(2, Int(80 * g))
        var pts: [CGPoint] = []
        for i in 0...n {
            let u = g * Double(i) / Double(n)
            var p = stem(u, w, h)
            p.x += sin(t * 1.2 + u * 6) * w * 0.012 * u * (lit ? 0.3 : 1)
            pts.append(p)
        }
        let green = Color(red: 0.55, green: 0.82, blue: 0.52)
        let deep = Color(red: 0.36, green: 0.62, blue: 0.36)

        // Tallo con grosor que se afina hacia la punta.
        for i in 1..<pts.count {
            var seg = Path(); seg.move(to: pts[i - 1]); seg.addLine(to: pts[i])
            let f = Double(i) / Double(pts.count)
            ctx.stroke(seg, with: .color(deep), style: StrokeStyle(lineWidth: w * (0.018 - 0.010 * f), lineCap: .round))
        }

        // Hojas alternas, cada una del mismo tamaño salvo las que están brotando cerca de la punta.
        var k = 0
        for i in stride(from: 8, to: pts.count - 3, by: 9) {
            let p = pts[i], q = pts[i - 2]
            let angle = atan2(p.y - q.y, p.x - q.x) + .pi / 2
            let side: Double = k % 2 == 0 ? 1 : -1
            let fresh = min(1, Double(pts.count - i) / 12)
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(angle + side * (0.95 + 0.07 * sin(t * 1.4 + Double(k)))))
            let len = w * 0.075 * fresh
            c.fill(LeafShape().path(in: CGRect(x: -len * 0.32, y: -len, width: len * 0.64, height: len)), with: .color(green))
            var vein = Path(); vein.move(to: .zero); vein.addLine(to: CGPoint(x: 0, y: -len * 0.8))
            c.stroke(vein, with: .color(deep.opacity(0.8)), lineWidth: 1)
            k += 1
        }

        // La punta: un zarcillo en espiral. Al conectar se enrosca en el borde del Mac.
        guard let tip = pts.last, g > 0.1 else { return }
        let dir = atan2(tip.y - pts[max(0, pts.count - 4)].y, tip.x - pts[max(0, pts.count - 4)].x)
        var curl = Path()
        curl.move(to: tip)
        let turns = lit ? 1.6 : 1.1 + 0.2 * sin(t * 1.5)
        for j in 1...40 {
            let f = Double(j) / 40
            let r = w * 0.045 * (1 - f * 0.85)
            let a = dir + f * turns * 2 * .pi
            let center = CGPoint(x: tip.x + cos(dir) * w * 0.02, y: tip.y + sin(dir) * w * 0.02)
            curl.addLine(to: CGPoint(x: center.x + cos(a - .pi) * r * (1 - f) + cos(dir) * r * f,
                                     y: center.y + sin(a - .pi) * r * (1 - f) + sin(dir) * r * f))
        }
        ctx.stroke(curl, with: .color(deep), style: StrokeStyle(lineWidth: w * 0.007, lineCap: .round, lineJoin: .round))

        if lit {
            // El punto donde se agarra: late.
            let r = w * 0.02 * (1 + 0.25 * sin(t * 3))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(Tone.ember))
            let ring = r * 2.2
            ctx.stroke(Path(ellipseIn: CGRect(x: tip.x - ring, y: tip.y - ring, width: ring * 2, height: ring * 2)),
                       with: .color(Tone.ember.opacity(0.4)), lineWidth: 1.2)
        } else {
            // Yema en la punta mientras crece.
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - w * 0.011, y: tip.y - w * 0.011, width: w * 0.022, height: w * 0.022)), with: .color(green))
        }
    }
}

// MARK: - Pantalla de vincular

struct ConnectView: View {
    @EnvironmentObject private var remote: Remote
    var onCode: () -> Void = {}
    @State private var sending = false
    @Environment(\.isLandscape) private var landscape
    @State private var code = ""
    @State private var shakes = 0
    @FocusState private var focused: Bool

    private var stage: ConnectStage {
        switch remote.phase {
        case .searching: .searching
        case .choosing: .choosing
        case .needsCode: sending ? .connecting : .code
        case .connecting, .connected: .connecting
        }
    }

    var body: some View {
        Group {
            if landscape {
                HStack(spacing: Space.l) {
                    VStack(spacing: Space.s) {
                        VineScene(stage: stage).frame(maxHeight: .infinity)
                        title
                    }
                    .frame(maxWidth: .infinity)
                    ScrollView {
                        VStack(spacing: Space.m) { content }
                            .frame(maxWidth: 400)
                            .frame(maxWidth: .infinity, minHeight: 0)
                            .padding(.vertical, Space.m)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, Space.l)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: Space.s)
                    // Con el teclado la escena se encoge; sin él ocupa lo que haya, siempre en proporción.
                    VineScene(stage: stage)
                        .frame(maxWidth: 300, maxHeight: focused ? 170 : 360)
                        .animation(.spring(duration: 0.45), value: focused)
                    title.padding(.top, Space.m)
                    VStack(spacing: Space.m) { content }
                        .frame(maxWidth: 400)
                        .padding(.top, Space.l)
                        .animation(.spring(duration: 0.45), value: remote.phase)
                    Spacer(minLength: Space.s)
                    footer
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.l)
            }
        }
        .onChange(of: remote.phase) { _, p in
            if case .needsCode = p { code = ""; focused = true }
        }
        .onAppear { if case .needsCode = remote.phase { focused = true } }
        .onChange(of: remote.codeError) { _, e in
            if e != nil {
                code = ""
                focused = true
                shakes += 1
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: Piezas

    private var title: some View {
        VStack(spacing: 4) {
            Text("Zarcillo").font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
            Text("se estira desde tu iPhone y se agarra a tu Mac")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Tone.ink.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Label("Todo viaja cifrado por tu Wi-Fi. Sin cuentas ni servidores.", systemImage: "lock.fill")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Tone.ink.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.bottom, Space.xs)
            .opacity(focused ? 0 : 1)
            .frame(height: focused ? 0 : nil)
            .animation(.easeOut(duration: 0.2), value: focused)
    }

    @ViewBuilder private var content: some View {
        switch remote.phase {
        case .searching:
            status("Buscando tu Mac", detail: nil, spinning: true)
            if remote.networkDenied { denied } else { steps }
        case .choosing:
            status("Encontré más de un Mac", detail: "¿Cuál quieres controlar?", spinning: false)
            VStack(spacing: 8) {
                ForEach(Array(remote.macs.enumerated()), id: \.element) { i, mac in
                    Button { Haptic.tap(); remote.choose(mac) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "laptopcomputer").font(.system(size: 18, weight: .semibold)).foregroundStyle(Tone.ember)
                            Text(remote.name(mac)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Tone.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Tone.ink.opacity(0.35))
                        }
                        .padding(.horizontal, Space.m).frame(height: 56)
                        .glass(18)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(Double(i) * 0.06), value: remote.macs.count)
                }
            }
        case .needsCode(let mac):
            status("Escribe el código", detail: "Es el de 6 dígitos que muestra \(mac) en la barra de menús, en el icono de la hoja.", spinning: false)
            codeBoxes
            if let e = remote.codeError {
                Label(e, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 0.98, green: 0.55, blue: 0.45))
                    .multilineTextAlignment(.center)
            }
        case .connecting(let mac):
            status("Conectando", detail: mac, spinning: true)
        case .connected(let mac):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Tone.ember)
                    .symbolEffect(.bounce, value: mac)
                    .transition(.scale.combined(with: .opacity))
                Text("Conectado").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                Text(mac).font(.system(size: 14)).foregroundStyle(Tone.ink.opacity(0.62)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func status(_ title: String, detail: String?, spinning: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 14)).foregroundStyle(Tone.ink.opacity(0.62)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if spinning { WaitingDots().padding(.top, 4) }
        }
        .frame(maxWidth: .infinity)
    }

    /// Los tres pasos para que aparezca el Mac.
    private var steps: some View {
        VStack(spacing: 0) {
            step("laptopcomputer", "Abre Zarcillo en tu Mac", "Se queda en la barra de menús, arriba.")
            Divider().overlay(Tone.stroke)
            step("wifi", "Usa la misma Wi-Fi", "El iPhone y el Mac en la misma red.")
            Divider().overlay(Tone.stroke)
            step("leaf.fill", "Espera un momento", "El Mac aparece aquí solo, sin configurar nada.")
        }
        .glass(20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tone.stroke, lineWidth: 1))
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tone.onEmber)
                .frame(width: 34, height: 34).background(Circle().fill(Tone.ember))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m).padding(.vertical, 12)
    }

    private var denied: some View {
        VStack(spacing: Space.s) {
            Label("Zarcillo no tiene permiso para ver tu red local.", systemImage: "wifi.exclamationmark")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tone.ink).multilineTextAlignment(.center)
            Text("Sin él no puede encontrar tu Mac. Actívalo en Ajustes › Zarcillo › Red local.")
                .font(.system(size: 12)).foregroundStyle(Tone.ink.opacity(0.6)).multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text("Abrir Ajustes").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Tone.onEmber)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(Tone.ember))
            }
            .buttonStyle(PressScale())
        }
        .padding(Space.m)
        .glass(20)
    }

    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.01)
                .accessibilityLabel("código de 6 dígitos")
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    if digits.count == 6, !sending {
                        // Primero se va el teclado; cuando ya bajó, se envía el código.
                        sending = true
                        focused = false
                        onCode()
                        Haptic.tap()
                        Task {
                            try? await Task.sleep(for: .seconds(0.38))
                            remote.submit(code: digits)
                            sending = false
                        }
                    }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    let filled = i < chars.count
                    let next = i == chars.count && focused
                    Text(filled ? String(chars[i]) : "")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(filled ? Tone.onEmber : Tone.ink)
                        .contentTransition(.numericText())
                        .frame(minWidth: 0, maxWidth: 48).frame(height: 58)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(filled ? Tone.ember : Tone.key))
                        .overlay {
                            // La casilla que espera el siguiente dígito late.
                            if next {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 2)
                                    .phaseAnimator([0.25, 1.0]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.7) }
                            }
                        }
                        .scaleEffect(filled ? 1 : 0.94)
                        .animation(.spring(duration: 0.3, bounce: 0.5), value: filled)
                    if i == 2 { Spacer().frame(width: 4) }
                }
            }
            .shake(shakes)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}


/// Tres puntos que laten en fila: esperando.
struct WaitingDots: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    let v = 0.5 + 0.5 * sin(t * 4 - Double(i) * 0.9)
                    Circle().fill(Tone.ember).frame(width: 7, height: 7)
                        .scaleEffect(0.7 + 0.3 * v).opacity(0.35 + 0.65 * v)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
