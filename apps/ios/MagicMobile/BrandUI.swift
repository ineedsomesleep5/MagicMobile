import SwiftUI
import UIKit

/// MagicMobile's brand, "Walnut & Ember" (chosen 2026-10-01): dark carved walnut, tooled
/// leather, parchment ink, brass edges and the ember coral of the app icon. Panels, buttons
/// and icon buttons draw with the tavern kit (Board/BoardChrome.swift) when its assets are
/// installed, and fall back to these colours alone.
enum BrandTheme {
    static let canvas = Color(red: 27 / 255, green: 18 / 255, blue: 11 / 255)          // #1b120b walnut
    static let surface = Color(red: 43 / 255, green: 27 / 255, blue: 17 / 255)         // #2b1b11 leather
    static let surfaceRaised = Color(red: 58 / 255, green: 36 / 255, blue: 22 / 255)   // #3a2416
    static let border = Color(red: 138 / 255, green: 106 / 255, blue: 60 / 255)        // #8a6a3c dim brass
    static let ink = Color(red: 243 / 255, green: 230 / 255, blue: 200 / 255)          // #f3e6c8 parchment
    static let inkSecondary = Color(red: 194 / 255, green: 171 / 255, blue: 134 / 255)
    static let brass = Color(red: 0.88, green: 0.68, blue: 0.36)
    static let brassGradient = LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), Color(red: 0.80, green: 0.56, blue: 0.22)],
                                              startPoint: .top, endPoint: .bottom)
    static let ember = Color(red: 1, green: 128 / 255, blue: 88 / 255)                 // #ff8058
    static let emberLight = Color(red: 1, green: 157 / 255, blue: 126 / 255)           // #ff9d7e
    static let rust = Color(red: 167 / 255, green: 68 / 255, blue: 41 / 255)           // #a74429
    static let emberInk = Color(red: 34 / 255, green: 23 / 255, blue: 19 / 255)        // #221713, text on ember
    static let danger = Color(red: 1, green: 112 / 255, blue: 100 / 255)               // #ff7064, destructive text on dark
    // The icon's own values, measured from design/brand/icon-master-2026-09-23.png.
    static let markCoral = Color(red: 253 / 255, green: 102 / 255, blue: 72 / 255)
    static let markCream = Color(red: 248 / 255, green: 246 / 255, blue: 241 / 255)
    static let markTile = Color(red: 26 / 255, green: 27 / 255, blue: 32 / 255)

    static let emberGradient = LinearGradient(colors: [emberLight, ember, Color(red: 0.93, green: 0.42, blue: 0.27)],
                                              startPoint: .top, endPoint: .bottom)
}

// MARK: - Ambient motion

private struct BrandAmbientMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while something covers the menu (Deck Studio, settings, a game), so the
    /// backdrop, hero card, glints and sparks stop drawing frames nobody can see.
    var brandAmbientMotion: Bool {
        get { self[BrandAmbientMotionKey.self] }
        set { self[BrandAmbientMotionKey.self] = newValue }
    }
}

// MARK: - The mark

/// The app icon's mark: cream monogram under a coral card with a four-point sparkle.
/// `glint` makes the sparkle catch the light now and then.
struct BrandMark: View {
    var size: CGFloat = 72
    var glint = true
    var tile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAmbientMotion) private var ambient
    @State private var start = Date()

    var body: some View {
        let still = reduceMotion || !glint || !ambient
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSince(start)
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
                // Walnut & Ember: the monogram is cast in brass.
                context.fill(BrandMarkPaths.monogram(in: mark),
                             with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.82, green: 0.58, blue: 0.24)]),
                                                   startPoint: CGPoint(x: mark.midX, y: mark.minY), endPoint: CGPoint(x: mark.midX, y: mark.maxY)))
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
    /// Looked up once, not on every frame of the sparks.
    private static let wall = UIImage(named: "menu-backdrop-tavern")
    var cards = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAmbientMotion) private var ambient
    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BrandTheme.canvas
                // Walnut & Ember: the rendered 3D tavern room (2026-10-04), else the flat tavern wall.
                if TavernRoomBackdrop.available {
                    TavernRoomBackdrop()
                } else if let wall = Self.wall {
                    Image(uiImage: wall)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                RadialGradient(colors: [BrandTheme.ember.opacity(0.22), BrandTheme.rust.opacity(0.08), .clear],
                               center: UnitPoint(x: 0.5, y: 1.08), startRadius: 0, endRadius: proxy.size.height * 0.62)
                RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: -0.05),
                               startRadius: 0, endRadius: proxy.size.height * 0.5)
                if reduceMotion || !ambient {
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
        // The tavern wall replaces the card fan; the sparks stay.
        if cards && Self.wall == nil && !TavernRoomBackdrop.available { drawFan(&context, size, t: t) }
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
        font(.system(size: size, weight: .heavy, design: .serif))
            .tracking(-0.3)
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
            BrandSparkle(size: 9, color: BrandTheme.brass)
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .serif)).tracking(2.4)
                    .foregroundStyle(BrandTheme.brassGradient)
                    .fixedSize()
                BrandSparkle(size: 9, color: BrandTheme.brass)
            }
            line(leading: false)
        }
        .accessibilityHidden(title == nil)
    }

    private func line(leading: Bool) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [BrandTheme.brass.opacity(0), BrandTheme.brass.opacity(0.8)],
                                 startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading))
            .frame(height: 1)
    }
}

/// Dark gameplay surface with a hairline border and a warm edge of light along the top.
struct BrandPanel: ViewModifier {
    var padding: CGFloat = 18
    private let radius: CGFloat = 16

    @ViewBuilder
    func body(content: Content) -> some View {
        if TavernUIKit.available {
            content
                .padding(padding)
                .modifier(TavernPanelChrome(tavern: true, cornerRadius: 12))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        } else {
            plain(content)
        }
    }

    private func plain(_ content: Content) -> some View {
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
/// border (red text for a destructive choice). Presses sink a pixel, darken and click, like
/// the site's download buttons.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
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
    @Environment(\.brandAmbientMotion) private var ambient

    var body: some View {
        if TavernUIKit.available { tavernFace } else { plainFace }
    }

    /// Walnut & Ember: a riveted brass plaque, ember glass for the call to action, leather for
    /// the rest, oxblood leather for a destructive choice.
    private var tavernFace: some View {
        let primary = kind == .primary
        let shape = RoundedRectangle(cornerRadius: 21, style: .continuous)
        return label
            .pressSound(primary ? .uiConfirm : nil, isPressed: pressed)
            .font(.system(size: primary ? 19 : 17, weight: .heavy, design: .serif))
            .foregroundStyle(primary ? Color(red: 1, green: 0.91, blue: 0.66)
                             : kind == .destructive ? Color(red: 1, green: 0.8, blue: 0.72) : TavernPalette.parchment)
            .shadow(color: .black.opacity(0.75), radius: 1, y: 1)
            .padding(.horizontal, 22)
            .padding(.vertical, primary ? 14 : 11)
            .frame(maxWidth: .infinity, minHeight: primary ? 58 : 50)
            .contentShape(shape)
            .background {
                Group {
                    switch kind {
                    case .primary: TavernFill(material: .ember)
                    case .secondary: TavernFill(material: .leather)
                    case .destructive: TavernFill(material: .leather).overlay(MagicPalette.oxblood.opacity(0.7))
                    }
                }
                .clipShape(shape)
                .padding(3)
            }
            .overlay {
                if primary && isEnabled && !reduceMotion && ambient { ShineSweep().clipShape(shape).padding(3).allowsHitTesting(false) }
            }
            .overlay { TavernCapsuleRim() }
            .shadow(color: primary ? BrandTheme.ember.opacity(isEnabled ? 0.4 : 0) : .black.opacity(0.4),
                    radius: primary ? 14 : 6, y: primary ? 2 : 3)
            .saturation(isEnabled ? 1 : 0.15)
            .opacity(isEnabled ? 1 : 0.55)
            .brightness(pressed ? -0.08 : 0)
            .offset(y: pressed ? 1 : 0)
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }

    private var plainFace: some View {
        let primary = kind == .primary
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return label
            .pressSound(primary ? .uiConfirm : nil, isPressed: pressed)
            .font(.system(size: primary ? 19 : 17, weight: primary ? .heavy : .bold))
            .foregroundStyle(primary ? BrandTheme.emberInk : kind == .destructive ? BrandTheme.danger : BrandTheme.ink)
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
                if primary && isEnabled && !reduceMotion && ambient { ShineSweep().clipShape(shape).allowsHitTesting(false) }
            }
            .overlay {
                shape.strokeBorder(primary ? AnyShapeStyle(Color.white.opacity(0.22))
                                   : kind == .destructive ? AnyShapeStyle(BrandTheme.rust) : AnyShapeStyle(BrandTheme.border),
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

/// A glint that crosses the button every few seconds. It is one full-size gradient whose
/// bright band moves, so nothing is ever drawn outside the button: an offset stripe would
/// widen the button's frame for VoiceOver and for UI-test tap points.
struct ShineSweep: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let cycle = 3.6
            // The band travels from just before the leading edge to just past the trailing one.
            let p = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle) / 0.9 * 1.4 - 0.2
            let band = 0.14
            LinearGradient(stops: [
                .init(color: .clear, location: min(1, max(0, p - band))),
                .init(color: .white.opacity(p > -band && p < 1 + band ? 0.5 : 0), location: min(1, max(0, p))),
                .init(color: .clear, location: min(1, max(0, p + band)))
            ], startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8))
            .blendMode(.plusLighter)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
                // A round brass medallion with a leather face.
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandTheme.brassGradient)
                    .frame(width: 50, height: 50)
                    .background { TavernFill(material: .leather).clipShape(Circle()) }
                    .overlay(Circle().strokeBorder(BrandTheme.brassGradient, lineWidth: 3))
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1).padding(3))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .serif))
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
    @Environment(\.brandAmbientMotion) private var ambient
    @State private var start = Date()

    var body: some View {
        let height = width / 0.716
        let still = reduceMotion || !ambient
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSince(start)
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

// MARK: - System controls

/// The system controls the app keeps (they carry the accessibility and UI-test contracts),
/// dressed in Walnut & Ember: leather segmented controls with an ember selection and serif
/// labels, ember switches, brass-ringed stepper buttons and serif navigation titles.
enum TavernAppearance {
    @MainActor static func apply() {
        let parchment = UIColor(red: 0.95, green: 0.90, blue: 0.78, alpha: 1)
        let ember = UIColor(red: 1, green: 0.5, blue: 0.35, alpha: 1)
        let leather = UIColor(red: 0.20, green: 0.12, blue: 0.075, alpha: 1)
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = ember
        segmented.backgroundColor = leather
        segmented.setTitleTextAttributes([.font: serif(13, .semibold), .foregroundColor: parchment], for: .normal)
        segmented.setTitleTextAttributes([.font: serif(13, .bold),
                                          .foregroundColor: UIColor(red: 0.16, green: 0.08, blue: 0.04, alpha: 1)], for: .selected)
        UISwitch.appearance().onTintColor = ember
        let stepper = UIStepper.appearance()
        let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        stepper.setBackgroundImage(clear, for: .normal)
        stepper.setDividerImage(clear, forLeftSegmentState: .normal, rightSegmentState: .normal)
        stepper.setIncrementImage(ring("plus"), for: .normal)
        stepper.setDecrementImage(ring("minus"), for: .normal)
        UINavigationBar.appearance().titleTextAttributes = [.font: serif(17, .semibold)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(32, .bold)]
    }

    private static func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// A 30 pt brass ring with a leather face and a gold symbol, for stepper buttons.
    private static func ring(_ symbol: String) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            UIColor(red: 0.24, green: 0.14, blue: 0.08, alpha: 1).setFill()
            UIBezierPath(ovalIn: rect).fill()
            let colors = [UIColor(red: 1, green: 0.88, blue: 0.56, alpha: 1).cgColor, UIColor(red: 0.62, green: 0.42, blue: 0.15, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.saveGState()
                let ring = UIBezierPath(ovalIn: rect)
                ring.append(UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).reversing())
                ring.addClip()
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
                context.cgContext.restoreGState()
            }
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(UIColor(red: 1, green: 0.86, blue: 0.52, alpha: 1), renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2))
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - Walnut & Ember controls

/// A brass-rimmed switch: dark leather when off, glowing ember glass with the brass knob to
/// the right when on. Drawn under the real Toggle, which stays on top nearly invisible so
/// taps, VoiceOver and UI tests keep the system contract.
struct TavernToggle: View {
    let title: String
    @Binding var isOn: Bool
    var identifier: String? = nil
    /// A line of explanation under the title, in faded parchment.
    var subtitle: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .opacity(0.65)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            TavernSwitchFace(isOn: isOn)
                .frame(width: 51, height: 31)
                .overlay {
                    Toggle(title, isOn: $isOn)
                        .labelsHidden()
                        .opacity(0.02)
                        .accessibilityIdentifier(identifier ?? title)
                }
        }
        .frame(minHeight: 44)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A level in the tavern style: an ember-filled groove in a brass rim with a brass knob.
/// The real Slider sits on top, nearly invisible, so touch, VoiceOver and UI tests use it.
struct TavernSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let label: String
    var identifier: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let knob: CGFloat = 22
            let travel = max(proxy.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.12, green: 0.07, blue: 0.04))
                    .frame(height: 8)
                    .overlay(Capsule().strokeBorder(BrandTheme.brassGradient, lineWidth: 1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.32), Color(red: 0.74, green: 0.26, blue: 0.1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: knob / 2 + travel * fraction, height: 6)
                    .padding(.leading, 1)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.70, green: 0.48, blue: 0.17),
                                                  Color(red: 0.40, green: 0.25, blue: 0.08)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 13))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 34)
        .overlay {
            Slider(value: $value, in: range) { Text(label) }
                .opacity(0.02)
                .accessibilityIdentifier(identifier ?? label)
        }
    }
}

struct TavernSwitchFace: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.3), Color(red: 0.72, green: 0.22, blue: 0.08)],
                                                          startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color(red: 0.16, green: 0.10, blue: 0.06)))
                .overlay(Capsule().strokeBorder(BrandTheme.brassGradient, lineWidth: 1.5))
                .shadow(color: isOn ? BrandTheme.ember.opacity(0.55) : .clear, radius: 5)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.70, green: 0.48, blue: 0.17),
                                              Color(red: 0.40, green: 0.25, blue: 0.08)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 15))
                .frame(width: 25, height: 25)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(3)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: isOn)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A stepper as two brass rings (−, +) at the spots the real Stepper's halves occupy; the
/// real Stepper sits on top nearly invisible, so taps, VoiceOver and UI tests use it.
struct TavernStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var identifier: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
            Spacer(minLength: 8)
            HStack(spacing: 15) {
                ring("minus", enabled: value > range.lowerBound)
                ring("plus", enabled: value < range.upperBound)
            }
            .frame(width: 94, height: 32)
            .overlay {
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
                    .opacity(0.02)
                    .accessibilityIdentifier(identifier ?? title)
            }
        }
        .frame(minHeight: 44)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func ring(_ symbol: String, enabled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(BrandTheme.brassGradient)
            .frame(width: 32, height: 32)
            .background { TavernFill(material: .leather).clipShape(Circle()) }
            .overlay(Circle().strokeBorder(BrandTheme.brassGradient, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            .opacity(enabled ? 1 : 0.4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A choice as a recessed parchment slot (its title in brass, the current choice in ink)
/// that opens the tavern's leather pop-over instead of the system menu.
struct TavernPicker<Value: Hashable>: View {
    struct Section {
        var title: String?
        var options: [(label: String, value: Value)]
    }

    let title: String
    @Binding var selection: Value
    let sections: [Section]
    var identifier: String? = nil
    /// Off when a caption above already names the choice.
    var showsTitle = true

    private var current: String {
        sections.flatMap(\.options).first { $0.value == selection }?.label ?? "Choose"
    }

    var body: some View {
        let count = sections.reduce(0) { $0 + $1.options.count + ($1.title == nil ? 0 : 1) }
        TavernMenu(arrowEdge: .top, scrollHeight: count > 7 ? 420 : nil, scrollAnchor: AnyHashable(selection)) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                if let heading = section.title {
                    Text(heading.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(1.6)
                        .foregroundStyle(BrandTheme.brassGradient)
                        .padding(.top, 4)
                }
                ForEach(Array(section.options.enumerated()), id: \.offset) { _, option in
                    TavernMenuItem(title: option.label, systemImage: option.value == selection ? "checkmark" : nil) {
                        selection = option.value
                    }
                    .id(AnyHashable(option.value))
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    if showsTitle {
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(1.4)
                            .foregroundStyle(DeckStudioPalette.accent)
                    }
                    Text(current)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(TavernPalette.ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DeckStudioPalette.accent)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                TavernFill(material: .parchment)
                    .overlay(LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: .top, endPoint: .center))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TavernPalette.brassLine, lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityLabel("\(title), \(current)")
        .accessibilityIdentifier(identifier ?? title)
    }
}
