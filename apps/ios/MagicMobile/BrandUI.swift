import SwiftUI

/// MagicMobile's brand, shared with the app icon and the download site (apps/site/DESIGN.md):
/// charcoal canvas, ember coral, warm-white ink, heavy sans type and small-corner controls.
/// Everything is drawn in SwiftUI, so it scales to any screen without image assets.
enum BrandTheme {
    static let canvas = Color(red: 20 / 255, green: 21 / 255, blue: 24 / 255)          // #141518
    static let surface = Color(red: 37 / 255, green: 38 / 255, blue: 42 / 255)         // #25262a
    static let surfaceRaised = Color(red: 46 / 255, green: 47 / 255, blue: 52 / 255)
    static let border = Color(red: 69 / 255, green: 70 / 255, blue: 74 / 255)          // #45464a
    static let ink = Color(red: 243 / 255, green: 241 / 255, blue: 236 / 255)          // #f3f1ec
    static let inkSecondary = Color(red: 177 / 255, green: 178 / 255, blue: 182 / 255)
    static let ember = Color(red: 1, green: 128 / 255, blue: 88 / 255)                 // #ff8058
    static let emberLight = Color(red: 1, green: 157 / 255, blue: 126 / 255)           // #ff9d7e
    static let rust = Color(red: 167 / 255, green: 68 / 255, blue: 41 / 255)           // #a74429
    static let emberInk = Color(red: 34 / 255, green: 23 / 255, blue: 19 / 255)        // #221713, text on ember
    // The icon's own values, measured from design/brand/icon-master-2026-09-23.png.
    static let markCoral = Color(red: 253 / 255, green: 102 / 255, blue: 72 / 255)
    static let markCream = Color(red: 248 / 255, green: 246 / 255, blue: 241 / 255)
    static let markTile = Color(red: 26 / 255, green: 27 / 255, blue: 32 / 255)

    static let emberGradient = LinearGradient(colors: [emberLight, ember, Color(red: 0.93, green: 0.42, blue: 0.27)],
                                              startPoint: .top, endPoint: .bottom)
}

// MARK: - The mark

/// The app icon's mark: cream monogram under a coral card with a four-point sparkle.
/// `glint` makes the sparkle catch the light now and then.
struct BrandMark: View {
    var size: CGFloat = 72
    var glint = true
    var tile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !glint)) { timeline in
            let t = reduceMotion || !glint ? 0 : timeline.date.timeIntervalSince(start)
            // A glint every 4.5 s: a quick swell, then settle.
            let phase = t.truncatingRemainder(dividingBy: 4.5)
            let flash = phase < 0.6 ? sin(.pi * phase / 0.6) : 0
            Canvas { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize)
                if tile {
                    context.fill(Path(roundedRect: rect, cornerRadius: canvasSize.width * 0.22, style: .continuous),
                                 with: .color(BrandTheme.markTile))
                }
                let mark = tile ? rect.insetBy(dx: canvasSize.width * 0.04, dy: canvasSize.height * 0.04) : rect
                context.fill(BrandMarkPaths.cardFrame(in: mark), with: .color(BrandTheme.markCoral))
                let c = BrandMarkPaths.sparkleCenter
                let center = CGPoint(x: mark.minX + c.x * mark.width, y: mark.minY + c.y * mark.height)
                if flash > 0.01 {
                    var glow = context
                    glow.blendMode = .plusLighter
                    glow.opacity = flash * 0.9
                    let r = mark.width * 0.2
                    glow.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                              with: .radialGradient(Gradient(colors: [BrandTheme.emberLight, .clear]), center: center,
                                                    startRadius: 0, endRadius: r))
                }
                var spark = context
                let scale = 1 + 0.14 * flash
                spark.translateBy(x: center.x, y: center.y)
                spark.scaleBy(x: scale, y: scale)
                spark.rotate(by: .degrees(12 * flash))
                spark.translateBy(x: -center.x, y: -center.y)
                spark.fill(BrandMarkPaths.sparkle(in: mark), with: .color(flash > 0.5 ? BrandTheme.emberLight : BrandTheme.markCoral))
                context.fill(BrandMarkPaths.monogram(in: mark), with: .color(BrandTheme.markCream))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The sparkle from the mark on its own, for dividers and accents.
struct BrandSparkle: View {
    var size: CGFloat = 10
    var color: Color = BrandTheme.ember

    var body: some View {
        Canvas { context, canvasSize in
            // Scale the traced sparkle so its own bounds fill the canvas.
            let s = BrandMarkPaths.sparkleSize, c = BrandMarkPaths.sparkleCenter
            let unit = CGRect(x: canvasSize.width / 2 - c.x * canvasSize.width / s.width,
                              y: canvasSize.height / 2 - c.y * canvasSize.height / s.height,
                              width: canvasSize.width / s.width, height: canvasSize.height / s.height)
            context.fill(BrandMarkPaths.sparkle(in: unit), with: .color(color))
        }
        .frame(width: size, height: size * BrandMarkPaths.sparkleSize.height / BrandMarkPaths.sparkleSize.width)
        .accessibilityHidden(true)
    }
}

// MARK: - Backdrop

/// Animated menu background: a warm hearth glow below, a faint fan of cards carrying the
/// sparkle (the logo's own motif) and ember sparks rising through the room. Static under
/// Reduce Motion.
struct BrandBackdrop: View {
    var cards = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BrandTheme.canvas
                RadialGradient(colors: [BrandTheme.ember.opacity(0.22), BrandTheme.rust.opacity(0.08), .clear],
                               center: UnitPoint(x: 0.5, y: 1.08), startRadius: 0, endRadius: proxy.size.height * 0.62)
                RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: -0.05),
                               startRadius: 0, endRadius: proxy.size.height * 0.5)
                if reduceMotion {
                    Canvas { context, size in draw(&context, size, t: 0) }
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        let t = timeline.date.timeIntervalSince(start)
                        Canvas { context, size in draw(&context, size, t: t) }
                    }
                }
                RadialGradient(colors: [.clear, .black.opacity(0.6)], center: .center,
                               startRadius: min(proxy.size.width, proxy.size.height) * 0.4,
                               endRadius: max(proxy.size.width, proxy.size.height) * 0.78)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, t: Double) {
        if cards { drawFan(&context, size, t: t) }
        // Ember sparks rising from the hearth.
        for i in 0..<42 {
            let seed = Double(i) * 12.9898
            let r1 = frac(sin(seed) * 43758.5453), r2 = frac(sin(seed * 1.7) * 24634.6345), r3 = frac(sin(seed * 2.3) * 93245.1)
            let life = frac(t * (0.03 + 0.045 * r1) + r2)
            let x = size.width * r3 + sin(t * (0.35 + r1) + seed) * 20
            let y = size.height * (1.04 - life * 1.08)
            let radius = 0.7 + 1.7 * r1 * (1 - life * 0.5)
            var spark = context
            spark.blendMode = .plusLighter
            spark.opacity = sin(.pi * life) * (0.4 + 0.35 * sin(t * 2.6 + seed)) * (1 - life * 0.4)
            spark.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(i % 5 == 0 ? BrandTheme.emberLight : BrandTheme.ember))
        }
    }

    /// Three card outlines fanned like the logo, breathing slowly.
    private func drawFan(_ context: inout GraphicsContext, _ size: CGSize, t: Double) {
        let cardWidth = min(size.width, size.height) * 0.62
        let cardHeight = cardWidth / 0.716
        let pivot = CGPoint(x: size.width / 2, y: size.height * 0.42 + cardHeight * 0.5)
        let breathe = sin(t * 0.35) * 1.5
        for (index, angle) in [-16.0, 16.0, 0.0].enumerated() {
            var card = context
            card.translateBy(x: pivot.x, y: pivot.y)
            card.rotate(by: .degrees(angle + (angle == 0 ? 0 : (angle > 0 ? breathe : -breathe))))
            let rect = CGRect(x: -cardWidth / 2, y: -cardHeight, width: cardWidth, height: cardHeight)
            let shape = Path(roundedRect: rect, cornerRadius: cardWidth * 0.08, style: .continuous)
            card.fill(shape, with: .color(BrandTheme.canvas.opacity(index == 2 ? 0.85 : 0.6)))
            card.stroke(shape, with: .color(index == 2 ? BrandTheme.ember.opacity(0.16) : Color.white.opacity(0.05)),
                        lineWidth: 1.2)
        }
        // The sparkle glows faintly on the front card.
        let glow = 0.5 + 0.5 * sin(t * 0.7)
        let sparkleWidth = cardWidth * 0.34
        let center = CGPoint(x: pivot.x, y: pivot.y - cardHeight * 0.55)
        let s = BrandMarkPaths.sparkleSize, c = BrandMarkPaths.sparkleCenter
        let unit = CGRect(x: center.x - c.x * sparkleWidth / s.width, y: center.y - c.y * sparkleWidth / s.width,
                          width: sparkleWidth / s.width, height: sparkleWidth / s.width)
        var halo = context
        halo.blendMode = .plusLighter
        halo.opacity = 0.12 + 0.08 * glow
        halo.fill(Path(ellipseIn: CGRect(x: center.x - sparkleWidth, y: center.y - sparkleWidth,
                                         width: sparkleWidth * 2, height: sparkleWidth * 2)),
                  with: .radialGradient(Gradient(colors: [BrandTheme.ember, .clear]), center: center,
                                        startRadius: 0, endRadius: sparkleWidth))
        var spark = context
        spark.opacity = 0.1 + 0.06 * glow
        spark.fill(BrandMarkPaths.sparkle(in: unit), with: .color(BrandTheme.ember))
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }
}

// MARK: - Typography and surfaces

extension View {
    /// Heavy display type, as on the download site.
    func brandTitle(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .black))
            .tracking(-0.6)
            .foregroundStyle(BrandTheme.ink)
            .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
    }

    func brandPanel(padding: CGFloat = 18) -> some View { modifier(BrandPanel(padding: padding)) }
}

/// A thin rule with the brand sparkle at its center and an optional small label.
struct BrandDivider: View {
    var title: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            line(leading: true)
            BrandSparkle(size: 9)
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(2.4)
                    .foregroundStyle(BrandTheme.ember)
                    .fixedSize()
                BrandSparkle(size: 9)
            }
            line(leading: false)
        }
        .accessibilityHidden(title == nil)
    }

    private func line(leading: Bool) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [BrandTheme.ember.opacity(0), BrandTheme.ember.opacity(0.7)],
                                 startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading))
            .frame(height: 1)
    }
}

/// Dark gameplay surface with a hairline border and a warm edge of light along the top.
struct BrandPanel: ViewModifier {
    var padding: CGFloat = 18
    private let radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [BrandTheme.surface.opacity(0.96), Color(red: 0.11, green: 0.115, blue: 0.13).opacity(0.97)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(BrandTheme.border, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.clear, BrandTheme.ember.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.horizontal, radius)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

// MARK: - Buttons

/// Ember call to action (dark ink on coral) or a dark secondary button with a hairline
/// border. Presses sink a pixel, darken and click, like the site's download buttons.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        BrandButtonFace(label: configuration.label, pressed: configuration.isPressed, kind: kind)
    }
}

/// A real view (not inline style code) so enabled state and Reduce Motion always arrive
/// through the environment, even when another style forwards to this one.
private struct BrandButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let kind: BrandButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let primary = kind == .primary
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return label
            .pressSound(primary ? .uiConfirm : .uiTap, isPressed: pressed)
            .font(.system(size: primary ? 19 : 17, weight: primary ? .heavy : .bold))
            .foregroundStyle(primary ? BrandTheme.emberInk : BrandTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, primary ? 16 : 13)
            .frame(maxWidth: .infinity, minHeight: primary ? 58 : 50)
            .contentShape(shape)
            .background {
                if primary {
                    shape.fill(BrandTheme.emberGradient)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                                    .padding(1.5).mask(shape))
                } else {
                    shape.fill(LinearGradient(colors: [BrandTheme.surfaceRaised, BrandTheme.surface], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                if primary && isEnabled && !reduceMotion { ShineSweep().clipShape(shape).allowsHitTesting(false) }
            }
            .overlay {
                shape.strokeBorder(primary ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(BrandTheme.border),
                                   lineWidth: 1)
            }
            .shadow(color: primary ? BrandTheme.ember.opacity(isEnabled ? 0.45 : 0) : .black.opacity(0.35),
                    radius: primary ? 16 : 8, y: primary ? 2 : 4)
            .saturation(isEnabled ? 1 : 0.1)
            .opacity(isEnabled ? 1 : 0.5)
            .brightness(pressed ? -0.08 : 0)
            .offset(y: pressed ? 1 : 0)
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }
}

/// A glint that crosses the button every few seconds.
struct ShineSweep: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let cycle = 3.6
            let p = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle) / 0.9
            GeometryReader { proxy in
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.3)
                    .rotationEffect(.degrees(20))
                    .offset(x: -proxy.size.width * 0.4 + CGFloat(min(p, 1.2)) * proxy.size.width * 1.5)
                    .opacity(p < 1.2 ? 1 : 0)
                    .blendMode(.plusLighter)
            }
        }
    }
}

/// Small-corner tile with an icon over a caption (menu utilities).
struct BrandIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandTheme.ember)
                    .frame(width: 52, height: 46)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [BrandTheme.surfaceRaised, BrandTheme.surface], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(BrandTheme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandTheme.inkSecondary)
            }
            .frame(minWidth: 72, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
    }
}

/// Press feedback without chrome, for custom-drawn controls.
struct BrandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressSound(isPressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Hero card

/// The selected commander presented like a prize: floating, catching the light, with a
/// warm halo and a pedestal shadow.
struct HeroCommanderCard: View {
    let name: String?
    var namespace: Namespace.ID? = nil
    var width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let height = width / 0.716
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [BrandTheme.ember.opacity(0.42), .clear], center: .center,
                                         startRadius: 0, endRadius: width * 0.9))
                    .frame(width: width * 1.9, height: height * 1.2)
                    .opacity(0.55 + 0.15 * sin(t * 1.1))
                    .blur(radius: 10)
                Ellipse()
                    .fill(.black.opacity(0.6))
                    .frame(width: width * (0.8 - 0.05 * sin(t * 0.9)), height: 16)
                    .blur(radius: 8)
                    .offset(y: height * 0.56)
                CommanderDeckPortrait(name: name, namespace: namespace)
                    .frame(width: width, height: height)
                    .overlay {
                        // Light sliding across the card face as it turns.
                        LinearGradient(colors: [.clear, .white.opacity(0.2), .clear],
                                       startPoint: UnitPoint(x: -0.2 + 1.4 * frac(t / 5), y: 0),
                                       endPoint: UnitPoint(x: 0.3 + 1.4 * frac(t / 5), y: 1))
                            .blendMode(.plusLighter)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .allowsHitTesting(false)
                    }
                    .rotation3DEffect(.degrees(6 * sin(t * 0.55)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(3 * sin(t * 0.4 + 1)), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotationEffect(.degrees(-3 + 1.2 * sin(t * 0.6)))
                    .offset(y: -5 * sin(t * 0.9))
                    .shadow(color: BrandTheme.ember.opacity(0.3), radius: 22)
            }
        }
        .frame(width: width * 1.3, height: height * 1.12)
        .accessibilityHidden(true)
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }
}

/// "VS" medallion between two decks.
struct VersusMedallion: View {
    var size: CGFloat = 54

    var body: some View {
        Text("VS")
            .font(.system(size: size * 0.36, weight: .black))
            .tracking(-0.5)
            .foregroundStyle(BrandTheme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(RadialGradient(colors: [BrandTheme.surfaceRaised, BrandTheme.canvas],
                                                     center: .center, startRadius: 0, endRadius: size * 0.5)))
            .overlay(Circle().strokeBorder(BrandTheme.emberGradient, lineWidth: 2.5))
            .shadow(color: BrandTheme.ember.opacity(0.6), radius: 12)
            .accessibilityHidden(true)
    }
}

// MARK: - Versus intro

/// The two sides meet before the first draw: commanders slide in, the medallion slams
/// down with a shockwave, then the table is revealed. Purely visual; touches pass through.
struct VersusIntroOverlay: View {
    struct Seat: Identifiable, Equatable {
        let id: String
        let name: String
        let commander: String?
    }

    let you: Seat
    let opponents: [Seat]
    let finished: () -> Void
    @State private var phase = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = min(150, width * 0.34)
            let opponentWidth = opponents.count > 1 ? cardWidth * 0.62 : cardWidth
            ZStack {
                BrandBackdrop(cards: false)
                    .ignoresSafeArea()
                HStack(alignment: .center, spacing: 0) {
                    seat(you, width: cardWidth, tilt: -5)
                        .offset(x: phase >= 1 ? 0 : -width)
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        ForEach(opponents) { seat($0, width: opponentWidth, tilt: 5) }
                    }
                    .offset(x: phase >= 1 ? 0 : width)
                }
                .padding(.horizontal, 18)
                Circle()
                    .strokeBorder(BrandTheme.ember, lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .scaleEffect(phase >= 2 ? 4.5 : 0.6)
                    .opacity(phase == 1 ? 0.9 : 0)
                    .animation(.easeOut(duration: 0.7), value: phase)
                VersusMedallion(size: 86)
                    .scaleEffect(phase >= 2 ? 1 : 3.2)
                    .opacity(phase >= 2 ? 1 : 0)
            }
            .opacity(phase >= 3 ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(you.name) versus \(opponents.map(\.name).joined(separator: ", "))")
        .task {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { phase = 1 }
            try? await Task.sleep(for: .milliseconds(480))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { phase = 2 }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeIn(duration: 0.45)) { phase = 3 }
            try? await Task.sleep(for: .milliseconds(480))
            finished()
        }
    }

    private func seat(_ seat: Seat, width: CGFloat, tilt: Double) -> some View {
        VStack(spacing: 8) {
            CommanderDeckPortrait(name: seat.commander)
                .frame(width: width, height: width / 0.716)
                .rotationEffect(.degrees(tilt))
                .shadow(color: BrandTheme.ember.opacity(0.35), radius: 18)
            Text(seat.name)
                .font(.system(size: max(12, width * 0.11), weight: .heavy))
                .foregroundStyle(BrandTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: width + 20)
        }
    }
}
