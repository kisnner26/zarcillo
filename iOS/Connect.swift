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

/// Un iPhone abajo, un Mac arriba y una enredadera que crece de uno al otro: es
/// lo que hace la app. Busca (se mece), elige, pide el código (casi llega) y se
/// agarra al conectar (se enrosca en el Mac y la pantalla se enciende).
struct VineScene: View {
    let stage: ConnectStage
    private let growth = Growth()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let g = growth.step(toward: stage.growth, t)
                draw(&ctx, size, t, g)
            }
        }
        .accessibilityHidden(true)
    }

    // Puntos de la escena en coordenadas 0…1.
    private let p0 = CGPoint(x: 0.27, y: 0.66)
    private let p1 = CGPoint(x: 0.22, y: 0.40)
    private let p2 = CGPoint(x: 0.62, y: 0.58)
    private let p3 = CGPoint(x: 0.71, y: 0.37)

    private func bezier(_ u: Double, _ size: CGSize) -> CGPoint {
        let a = pow(1 - u, 3), b = 3 * u * pow(1 - u, 2), c = 3 * u * u * (1 - u), d = u * u * u
        return CGPoint(x: (a * p0.x + b * p1.x + c * p2.x + d * p3.x) * size.width,
                       y: (a * p0.y + b * p1.y + c * p2.y + d * p3.y) * size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: TimeInterval, _ g: Double) {
        let w = size.width, h = size.height
        let ember = Tone.ember
        let lit = g > 0.95 || stage == .connecting

        // Resplandor detrás del Mac.
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.30, y: -h * 0.1, width: w * 0.85, height: h * 0.8)),
                 with: .radialGradient(Gradient(colors: [ember.opacity(lit ? 0.34 : 0.14), .clear]),
                                       center: CGPoint(x: w * 0.71, y: h * 0.22), startRadius: 0, endRadius: w * 0.5))

        // Luciérnagas.
        for k in 0..<16 {
            let a = frac(Double(k) * 0.618), b = frac(Double(k) * 0.382 + 0.3)
            let x = (a + 0.03 * sin(t * 0.5 + Double(k))) * w
            let y = (b + 0.03 * cos(t * 0.6 + Double(k) * 2)) * h
            let glow = 0.15 + 0.25 * (0.5 + 0.5 * sin(t * 1.3 + Double(k) * 1.7))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)), with: .color(ember.opacity(glow)))
        }

        mac(&ctx, size, t, lit)
        phone(&ctx, size, t)

        // El tallo, de la base del iPhone hacia el Mac, meciéndose.
        let steps = max(2, Int(70 * g))
        var pts: [CGPoint] = []
        for i in 0...steps {
            let u = g * Double(i) / Double(steps)
            var p = bezier(u, size)
            let sway = sin(t * 1.1 + u * 7) * 6 * u * (lit ? 0.3 : 1)
            p.x += sway
            pts.append(p)
        }
        let green = Color(hue: 0.33, saturation: 0.5, brightness: 0.78)
        for i in 1..<pts.count {
            var seg = Path(); seg.move(to: pts[i - 1]); seg.addLine(to: pts[i])
            let wdt = 4.6 - 2.4 * Double(i) / Double(pts.count)
            ctx.stroke(seg, with: .color(green), style: StrokeStyle(lineWidth: wdt, lineCap: .round))
        }

        // Hojas a lo largo del tallo.
        var k = 0
        for i in stride(from: 6, to: pts.count, by: 7) {
            let p = pts[i], q = pts[i - 1]
            let angle = atan2(p.y - q.y, p.x - q.x)
            let side: Double = k % 2 == 0 ? 1 : -1
            let grown = min(1, (Double(pts.count - i) / 14)) * min(1, g * 1.4)
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(angle + side * (1.05 + 0.08 * sin(t * 1.4 + Double(k)))))
            let len = (15 + 6 * frac(Double(k) * 0.7)) * min(1, grown + 0.25)
            c.fill(LeafShape().path(in: CGRect(x: -len * 0.3, y: -len, width: len * 0.6, height: len)),
                   with: .color(green.opacity(0.95)))
            k += 1
        }

        // El zarcillo: la punta se enrosca en espiral (más cerrada cuanto más cerca del Mac).
        if let tip = pts.last, g > 0.15 {
            let tight = 0.55 + 0.45 * g
            var curl = Path()
            let base = t * 1.4
            for j in 0...44 {
                let f = Double(j) / 44
                let r = (16 * (1 - f) + 2.5) * (1.2 - 0.35 * tight)
                let a = base * 0.15 + f * 7.2 * tight
                let pt = CGPoint(x: tip.x + cos(a) * r - r * 0.9, y: tip.y + sin(a) * r)
                if j == 0 { curl.move(to: pt) } else { curl.addLine(to: pt) }
            }
            ctx.stroke(curl, with: .color(green), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            if lit {
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)), with: .color(ember))
                ctx.stroke(Path(ellipseIn: CGRect(x: tip.x - 11 - 3 * sin(t * 3), y: tip.y - 11 - 3 * sin(t * 3),
                                                  width: 22 + 6 * sin(t * 3), height: 22 + 6 * sin(t * 3))),
                           with: .color(ember.opacity(0.5)), lineWidth: 1.5)
            }
        }
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }

    /// Un portátil de perfil: tapa, pantalla y base.
    private func mac(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: TimeInterval, _ lit: Bool) {
        let w = size.width, h = size.height
        let screen = CGRect(x: w * 0.50, y: h * 0.07, width: w * 0.44, height: h * 0.27)
        let shell = RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: screen)
        ctx.fill(shell, with: .color(Tone.recess))
        ctx.stroke(shell, with: .color(lit ? Tone.ember.opacity(0.9) : Tone.ink.opacity(0.35)), lineWidth: lit ? 2.5 : 1.8)
        let inner = screen.insetBy(dx: 8, dy: 8)
        let glass = RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: inner)
        ctx.fill(glass, with: .linearGradient(
            Gradient(colors: [lit ? Tone.ember.opacity(0.32) : Tone.key, Tone.recess]),
            startPoint: CGPoint(x: inner.midX, y: inner.minY), endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
        // Contenido de la pantalla según el momento.
        switch stage {
        case .searching:
            let y = inner.minY + (inner.height - 2) * (0.5 + 0.5 * sin(t * 1.6))
            ctx.fill(Path(CGRect(x: inner.minX + 6, y: y, width: inner.width - 12, height: 2)), with: .color(Tone.ember.opacity(0.35)))
        case .choosing, .code:
            for i in 0..<6 {
                let x = inner.midX + (Double(i) - 2.5) * 13
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: inner.midY - 3, width: 6, height: 6)),
                         with: .color(Tone.ink.opacity(stage == .code ? 0.35 + 0.35 * sin(t * 2 + Double(i)) : 0.2)))
            }
        case .connecting:
            var c = ctx
            c.translateBy(x: inner.midX, y: inner.midY)
            c.rotate(by: .degrees(35))
            let s = min(inner.width, inner.height) * 0.62
            c.fill(LeafShape().path(in: CGRect(x: -s * 0.3, y: -s / 2, width: s * 0.6, height: s)), with: .color(Tone.ember))
        }
        // Base.
        var base = Path()
        base.move(to: CGPoint(x: w * 0.44, y: h * 0.355)); base.addLine(to: CGPoint(x: w * 0.995, y: h * 0.355))
        base.addLine(to: CGPoint(x: w * 0.96, y: h * 0.385)); base.addLine(to: CGPoint(x: w * 0.475, y: h * 0.385)); base.closeSubpath()
        ctx.fill(base, with: .color(Tone.key))
        ctx.stroke(base, with: .color(Tone.ink.opacity(0.3)), lineWidth: 1.2)
    }

    /// El iPhone, de donde nace la enredadera.
    private func phone(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: TimeInterval) {
        let w = size.width, h = size.height
        let body = CGRect(x: w * 0.13, y: h * 0.66, width: w * 0.28, height: h * 0.36)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: body)
        ctx.fill(shape, with: .color(Tone.recess))
        ctx.stroke(shape, with: .color(Tone.ink.opacity(0.45)), lineWidth: 1.8)
        let notch = Path(roundedRect: CGRect(x: body.midX - 12, y: body.minY + 6, width: 24, height: 5), cornerRadius: 2.5)
        ctx.fill(notch, with: .color(Tone.ink.opacity(0.3)))
        // Maceta: la hoja sale del teléfono.
        var c = ctx
        c.translateBy(x: body.midX, y: body.minY + body.height * 0.5)
        c.rotate(by: .degrees(-15 + 6 * sin(t * 1.1)))
        let s = body.width * 0.55
        c.fill(LeafShape().path(in: CGRect(x: -s * 0.3, y: -s / 2, width: s * 0.6, height: s)), with: .color(Tone.ember.opacity(0.9)))
    }
}

// MARK: - Pantalla de vincular

struct ConnectView: View {
    @EnvironmentObject private var remote: Remote
    @Environment(\.isLandscape) private var landscape
    @State private var code = ""
    @State private var shakes = 0
    @FocusState private var focused: Bool

    private var stage: ConnectStage {
        switch remote.phase {
        case .searching: .searching
        case .choosing: .choosing
        case .needsCode: .code
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
                VStack(spacing: Space.s) {
                    // La escena cede sitio cuando sale el teclado, en vez de empujar el código fuera de pantalla.
                    VineScene(stage: stage)
                        .frame(minHeight: 110, maxHeight: focused ? 190 : 340)
                        .frame(maxWidth: 420)
                        .animation(.spring(duration: 0.4), value: focused)
                    title
                    ScrollView {
                        VStack(spacing: Space.m) { content }
                            .frame(maxWidth: 400)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Space.xs).padding(.bottom, Space.s)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .layoutPriority(1)
                    footer
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
            }
        }
        .onChange(of: remote.phase) { _, p in
            if case .needsCode = p { code = ""; focused = true }
        }
        .onAppear { if case .needsCode = remote.phase { focused = true } }
        .onChange(of: remote.codeError) { _, e in
            if e != nil {
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
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tone.key))
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
        case .connecting(let mac), .connected(let mac):
            status("Conectando con \(mac)", detail: "Un momento…", spinning: true)
        }
    }

    private func status(_ title: String, detail: String?, spinning: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if spinning { ProgressView().tint(Tone.ember).scaleEffect(0.8) }
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Tone.ink)
            }
            if let detail {
                Text(detail).font(.system(size: 14)).foregroundStyle(Tone.ink.opacity(0.65)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
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
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tone.key))
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
                    if digits.count == 6 { remote.submit(code: digits) }
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
