import CoreImage
import SwiftUI
import UIKit

// The Arena board's table pieces (BoardMode.arena). Positions come from ArenaLayout through ArenaCanvas; behaviour stays
// with the views and helpers the Hearth board already uses (PlayerZoneMenu, BattlefieldRow, GameActionDockModel…).

struct ArenaBoardKey: EnvironmentKey { static let defaultValue = false }
struct CardFramesKey: EnvironmentKey { static let defaultValue = true }

/// The table's camera, so cards lying on it lean the way the rendered table does: the plate's pitch (landscape 22°,
/// portrait 16°, scripts/brand/arena_layout.json), the camera's distance in points (35 mm lens on a 36 mm sensor across
/// the screen's long side: half of it over tan 27°) and the screen's centre, toward which every card converges.
struct ArenaTableLean: Equatable {
    let pitch: Double
    let distance: CGFloat
    let centerX: CGFloat

    init(canvas: ArenaCanvas) {
        pitch = canvas.layout.landscape ? 22 : 16
        distance = max(canvas.screen.width, canvas.screen.height) / 2 / tan(27 * .pi / 180)
        centerX = canvas.screen.width / 2
    }

    /// The tilt for a card laid out at `frame` (global): its axis anchored under the screen's centre line, so its
    /// sides converge toward the table's vanishing point rather than its own.
    func anchor(for frame: CGRect) -> UnitPoint { UnitPoint(x: (centerX - frame.minX) / max(frame.width, 1), y: 0.5) }
    func perspective(for frame: CGRect) -> CGFloat { max(frame.width, frame.height) / distance }
}

struct ArenaTableLeanKey: EnvironmentKey { static let defaultValue: ArenaTableLean? = nil }

extension EnvironmentValues {
    /// True while the Arena board draws: battlefield tiles lean back with the table and tapped ones tilt instead of turning.
    var arenaBoard: Bool {
        get { self[ArenaBoardKey.self] }
        set { self[ArenaBoardKey.self] = newValue }
    }
    var arenaTableLean: ArenaTableLean? {
        get { self[ArenaTableLeanKey.self] }
        set { self[ArenaTableLeanKey.self] = newValue }
    }
    /// Tavern frames on battlefield cards (CardFramesPreference); off draws the reference game's cards.
    var cardFrames: Bool {
        get { self[CardFramesKey.self] }
        set { self[CardFramesKey.self] = newValue }
    }
    /// A mana payment is open on the Arena board: the permanents that can pay glow orange instead of cyan.
    var arenaPaying: Bool {
        get { self[ArenaPayingKey.self] }
        set { self[ArenaPayingKey.self] = newValue }
    }
}

struct ArenaPayingKey: EnvironmentKey { static let defaultValue = false }

enum ArenaPalette {
    static let cream = Color(red: 1, green: 0.965, blue: 0.88)
    static let viewerRim = Color(red: 0.91, green: 0.54, blue: 0.23)
    static let opponentRim = Color(red: 0.31, green: 0.55, blue: 1)
    static let attackGlow = Color(red: 1, green: 0.22, blue: 0.12)
    static let targetGlow = Color(red: 0.55, green: 0.9, blue: 1)
    static let iconFill = Color(red: 0.08, green: 0.045, blue: 0.025)
}

/// The Arena board's highlight: "the glow border" Caleb picked on the web guest board (memory frame-outline-glow,
/// `apps/web/src/board/tileArt.ts` `glowCanvas`): soft light that follows the card's own outline, never a box. With Card
/// Frames on it traces the tavern frame (crest and corners included); off, the reference's card or a token's arch; in
/// the hand, the printed card. Drawn behind the card and added to the light under it, so only the glow outside its edge
/// shows.
struct ArenaOutlineGlow: View {
    enum Outline: Hashable {
        case frame(TavernFrameKind)
        case tile(arched: Bool)
        /// A printed card (hand, drag, stack).
        case card
    }

    enum Tone {
        case playable, ability, payable, target, selected, attacking, blocking, source, shadow

        /// The web board's colours (playable #7ff0ff, target #c6f8ff, selected #ffe08f, attacking #ff5a2e, blocking
        /// #ffd38a), the duel prototype's orange for a source that can pay, its gold for a spell's source.
        var color: Color {
            switch self {
            case .playable: Color(red: 0.5, green: 0.94, blue: 1)
            // A permanent with an ability you can use now (Caleb, 2026-10-26: not the same white as a card to cast).
            case .ability: Color(red: 1, green: 0.88, blue: 0.23)
            case .target: Color(red: 0.78, green: 0.97, blue: 1)
            case .payable: Color(red: 1, green: 0.62, blue: 0.3)
            case .selected: Color(red: 1, green: 0.88, blue: 0.56)
            case .attacking: Color(red: 1, green: 0.35, blue: 0.18)
            case .blocking: Color(red: 1, green: 0.83, blue: 0.54)
            case .source: Color(red: 1, green: 0.84, blue: 0.5)
            case .shadow: .black
            }
        }
    }

    let outline: Outline
    let tone: Tone
    /// The web board shows a playable glow at 0.8 and the others at full strength.
    var strength: Double = 1
    /// The hand's playable glow breathes (full board effects only, never with Reduce Motion).
    var breathes = false
    @AppStorage(BoardFXLevel.key) private var level = BoardFXLevel.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if breathes && BoardFXLevel(rawValue: level) == .full && !reduceMotion {
                // The prototype's 2.2 s breath, on the shared clock so every playable card breathes together.
                BoardBreath(period: 1.1, low: 0.55, high: 1) { light in glow.opacity(light) }
            } else {
                glow
            }
        }
        .opacity(strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glow: some View {
        GeometryReader { proxy in
            if let image = ArenaGlowImages.image(outline) {
                let pad = ArenaGlowImages.pad
                Image(uiImage: image).resizable().renderingMode(.template)
                    .foregroundStyle(tone.color)
                    // Light adds to the table under it, as the web board's additive halo does; a shadow darkens.
                    .blendMode(tone == .shadow ? .normal : .plusLighter)
                    .frame(width: proxy.size.width * (1 + 2 * pad), height: proxy.size.height * (1 + 2 * pad))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

/// The outline glows' light, made once per outline and kept: a live blur on every tile was too slow with dozens of
/// tokens (TavernTileGlow's lesson). Built the way the web board's `glowCanvas` is: the outline's white silhouette on a
/// canvas 1.3x the card, drawn 16 px larger (on a 330 px tile) and blurred 14 px three times over, then the card's own
/// area (inset 4 px) cut back out.
@MainActor
enum ArenaGlowImages {
    /// The canvas reaches this share of the card past each edge (1.3x overall).
    static let pad: CGFloat = 0.15
    private static var cache: [ArenaOutlineGlow.Outline: UIImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(_ outline: ArenaOutlineGlow.Outline) -> UIImage? {
        if let image = cache[outline] { return image }
        guard let image = make(outline) else { return nil }
        cache[outline] = image
        return image
    }

    private static func make(_ outline: ArenaOutlineGlow.Outline) -> UIImage? {
        // Half the web's resolution is plenty for light this soft: the frames are 330 x 356, the reference's card 6:5,
        // a printed card 63:88.
        let shape: CGSize
        switch outline {
        case .frame: shape = CGSize(width: 165, height: 178)
        case .tile: shape = CGSize(width: 165, height: 137.5)
        case .card: shape = CGSize(width: 126, height: 176)
        }
        let unit = shape.width / 330
        let canvas = CGSize(width: (shape.width * (1 + 2 * pad)).rounded(), height: (shape.height * (1 + 2 * pad)).rounded())
        let box = CGRect(x: (canvas.width - shape.width) / 2, y: (canvas.height - shape.height) / 2, width: shape.width, height: shape.height)
        func silhouette(_ rect: CGRect) -> CIImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
                let cg = renderer.cgContext
                UIColor.white.setFill()
                switch outline {
                case .frame(let kind):
                    guard let frame = kind.image else { return }
                    frame.draw(in: rect)
                    // The frame's alpha in white (source-in), its arched window filled so the glow has the whole tile.
                    cg.setBlendMode(.sourceIn)
                    cg.fill(rect)
                    cg.setBlendMode(.normal)
                    let window = kind.window
                    cg.fill(CGRect(x: rect.minX + rect.width * window.minX, y: rect.minY + rect.height * window.minY,
                                   width: rect.width * window.width, height: rect.height * window.height))
                case .tile(let arched):
                    cg.addPath(ArenaTileShape(arched: arched, corner: rect.width * 0.07).path(in: rect).cgPath)
                    cg.fillPath()
                case .card:
                    cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.055).cgPath)
                    cg.fillPath()
                }
            }
            return image.cgImage.map(CIImage.init(cgImage:))
        }
        guard let spread = silhouette(box.insetBy(dx: -8 * unit, dy: -8 * unit)),
              let inner = silhouette(box.insetBy(dx: 4 * unit, dy: 4 * unit)) else { return nil }
        let extent = spread.extent
        let blurred = spread.clampedToExtent().applyingGaussianBlur(sigma: 14 * unit).cropped(to: extent)
        // Three passes over each other: 1 - (1 - a)^3, about three times the light where it is thin.
        let light = blurred
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 2.6)])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
        guard let output = context.createCGImage(light, from: extent) else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }
}

/// The leaning tavern table: the plate stretches to the screen the way the layout does, so the mat sits under the lanes.
struct ArenaTableBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            Image(landscape ? "tavern-arena-landscape" : "tavern-arena-portrait")
                .resizable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    // The lamp over the middle of the mat: warm light only, no texture.
                    RadialGradient(colors: [Color(red: 1, green: 0.77, blue: 0.47).opacity(0.13), .clear],
                                   center: .center, startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.42)
                        .blendMode(.screen)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A player's life medallion as Arena draws it (build_output/arena-game-reference/battlefield-next-1.jpg): their picture in
/// a thin gold ring, the life total on a dark plaque edged in gold over the ring's foot. It glows ember on its owner's
/// turn and red (attack) or blue (target) while it can be chosen. No brass coin.
struct ArenaHeroMedallion: View {
    let player: PlayerGameState
    let diameter: CGFloat
    var active = false
    var glow: Color? = nil
    var commanderReady = false
    var showsLife = true

    var body: some View {
        let portrait = diameter * 0.9
        ZStack {
            if commanderReady { TavernCommanderReadyGlow(diameter: portrait) }
            PlayerPortrait(player: player, size: portrait)
                .frame(width: portrait, height: portrait)
                .clipShape(Circle())
                .overlay(Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.3)], center: .center,
                                                      startRadius: portrait * 0.3, endRadius: portrait * 0.55)))
            Circle()
                .strokeBorder(LinearGradient(colors: [Color(red: 1, green: 0.90, blue: 0.62), ArenaMenuStyle.gold,
                                                      Color(red: 0.62, green: 0.44, blue: 0.18)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: max(1.5, diameter * 0.045))
                .frame(width: diameter * 0.96, height: diameter * 0.96)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottom) {
            if showsLife { lifePlaque.offset(y: diameter * 0.1) }
        }
        .background {
            if let glow {
                Circle().fill(glow).frame(width: diameter * 1.15, height: diameter * 1.15).blur(radius: diameter * 0.12)
            } else if active {
                Circle().fill(TavernPalette.ember.opacity(0.7)).frame(width: diameter * 1.05, height: diameter * 1.05)
                    .blur(radius: diameter * 0.1)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
        .opacity(player.isOut ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    private var lifePlaque: some View {
        Group {
            if player.isOut {
                Text("Out").font(.system(size: diameter * 0.17, weight: .bold)).foregroundStyle(Color.gray)
            } else {
                Text("\(player.life)")
                    .font(ArenaMenuStyle.title(diameter * 0.26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText(value: Double(player.life)))
                    .animation(.easeOut(duration: 0.3), value: player.life)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: diameter * 0.56, height: diameter * 0.34)
        .background(ArenaPlaqueShape().fill(LinearGradient(colors: [Color(red: 0.16, green: 0.16, blue: 0.19),
                                                                    Color(red: 0.05, green: 0.05, blue: 0.07)],
                                                           startPoint: .top, endPoint: .bottom)))
        .overlay(ArenaPlaqueShape().stroke(ArenaMenuStyle.gold.opacity(0.85), lineWidth: max(1, diameter * 0.02)))
    }
}

/// Arena's life plaque: a flat-topped, six-sided badge.
struct ArenaPlaqueShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// The real Magic card back (the image the app already shows for hidden cards), fetched once with the player's
/// artwork consent and kept in Caches; until then the tavern's leather back stands in.
@MainActor
final class ArenaCardBackArt: ObservableObject {
    static let shared = ArenaCardBackArt()
    @Published private(set) var image: UIImage?
    private var started = false
    private var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("magic-card-back.jpg")
    }

    func load() {
        guard !started else { return }
        started = true
        if let data = try? Data(contentsOf: cacheFile), let image = UIImage(data: data) {
            self.image = image
            return
        }
        guard MagicMobilePreferences.current.bool(forKey: NativeArtworkPreference.key),
              let url = CardImageURL.image("Hidden card", variant: .board), url.scheme == "https" else { return }
        let file = cacheFile
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return }
            try? data.write(to: file, options: .atomic)
            self.image = image
        }
    }
}

/// A face-down Magic card.
struct ArenaCardBack: View {
    @ObservedObject private var art = ArenaCardBackArt.shared

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Group {
                if let image = art.image {
                    Image(uiImage: image).resizable()
                } else {
                    leatherBack(width: width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.06))
        }
        .onAppear { art.load() }
        .accessibilityHidden(true)
    }

    private func leatherBack(width: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.16), Color(red: 0.07, green: 0.065, blue: 0.07)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
        }
        .overlay(RoundedRectangle(cornerRadius: width * 0.06).strokeBorder(Color.black.opacity(0.85), lineWidth: max(1, width * 0.06)))
    }
}

/// A library as a real stack of cards: one sliver per few cards (a little thicker than life so the count reads), the
/// back on top, lying back with the table.
struct ArenaDeckPile: View {
    let count: Int
    let size: CGSize
    let label: String

    var body: some View {
        ArenaPileStack(count: count, size: size) { ArenaCardBack() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// A pile on the table, the library's look for every zone (Caleb, 2026-10-21: the graveyard and exile didn't lie like
/// the library): slivers whose thickness follows the count under the top card, a contact shadow, leaning with the table,
/// and the count on a lozenge.
struct ArenaPileStack<Top: View>: View {
    let count: Int
    let size: CGSize
    @ViewBuilder let top: Top

    static func thickness(count: Int, height: CGFloat) -> CGFloat {
        count > 0 ? max(1.5, CGFloat(count) * height * 0.0055) : 0
    }

    var body: some View {
        let thickness = Self.thickness(count: count, height: size.height)
        let layers = min(16, Int((thickness / 1.1).rounded()))
        ZStack {
            Ellipse().fill(.black.opacity(count > 0 ? 0.55 : 0)).blur(radius: 4)
                .frame(width: size.width * 1.1, height: size.height * 0.5).offset(y: size.height * 0.32)
            if count == 0 {
                RoundedRectangle(cornerRadius: 4).strokeBorder(TavernPalette.brass.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(0..<layers, id: \.self) { index in
                let fraction = layers > 1 ? Double(index) / Double(layers - 1) : 1
                RoundedRectangle(cornerRadius: size.width * 0.08)
                    .fill(Color(hue: 0.105, saturation: 0.32, brightness: 0.62 + 0.26 * fraction + (index % 2 == 0 ? 0 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: size.width * 0.08).strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                    .offset(x: -thickness * 0.22 * CGFloat(index) / CGFloat(max(layers, 1)),
                            y: -thickness * CGFloat(index) / CGFloat(max(layers, 1)))
            }
            if count > 0 {
                top.offset(x: -thickness * 0.22, y: -thickness)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(ArenaTableLeanEffect())
        .overlay(alignment: .bottomTrailing) {
            if count > 0 { ArenaCountBadge(count: count).offset(x: 8, y: -2) }
        }
    }
}

/// Lays a view on the table: tilted by the table camera's pitch, converging on its vanishing point.
struct ArenaTableLeanEffect: ViewModifier {
    @Environment(\.arenaTableLean) private var lean

    @ViewBuilder func body(content: Content) -> some View {
        // Off the Arena table (Hearth) the tile stays flat and pays for no geometry reads.
        if let lean {
            content.visualEffect { view, proxy in
                let frame = proxy.frame(in: .global)
                return view.rotation3DEffect(.degrees(lean.pitch), axis: (x: 1, y: 0, z: 0),
                                             anchor: lean.anchor(for: frame), perspective: lean.perspective(for: frame))
            }
        } else {
            content
        }
    }
}

/// A count on the Arena table (a pile, the stack, a browser card's order): a white number on a dark oval in a thin gold
/// line, as Arena marks counts. The Hearth board keeps its brass coin (TavernCoin).
struct ArenaCountBadge: View {
    let count: Int
    /// The badge's height: 17 on a pile, larger for the stack's size or a browser card's order.
    var size: CGFloat = 17

    var body: some View {
        Text("\(count)")
            .font(.system(size: max(11, size * 0.5), weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, max(5, size * 0.18))
            .frame(minWidth: size + 3, minHeight: size)
            .background(Capsule().fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.94)))
            .overlay(Capsule().strokeBorder(ArenaMenuStyle.gold.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .fixedSize()
    }
}

/// A graveyard: a pile like the library with its top card face up (the printed card only, no badges), or an empty
/// dashed slot; a tap opens the whole zone.
struct ArenaGraveyardPile: View {
    let cards: [ZoneCard]
    let size: CGSize
    let label: String
    /// An exile pile: the same top card under a cool, ghostly veil with the exile mark.
    var exile = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ArenaPileStack(count: cards.count, size: size) {
                if let top = cards.last {
                    CardTile(card: top, selected: false, zoneName: exile ? "Exile" : "Graveyard", width: size.width, height: size.height,
                             ignoreTappedRotation: true)
                        .allowsHitTesting(false)
                        .overlay {
                            if exile {
                                RoundedRectangle(cornerRadius: size.width * 0.07)
                                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.7, blue: 1).opacity(0.42),
                                                                  Color(red: 0.3, green: 0.25, blue: 0.6).opacity(0.5)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .overlay(alignment: .topLeading) {
                                        Image(systemName: "sparkles").font(.system(size: size.width * 0.24, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.9)).shadow(color: .black, radius: 2)
                                            .padding(size.width * 0.06)
                                    }
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cards.isEmpty)
        .accessibilityLabel(cards.isEmpty ? "\(label), empty" : "\(label), \(cards.count) cards")
    }
}

/// The opponent's hand as a fan of card backs along the top edge.
struct ArenaOpponentHandFan: View {
    let count: Int
    let card: CGSize
    let pitch: CGFloat

    var body: some View {
        let shown = min(count, 12)
        // A few cards still fan out past the medallion in front of them.
        let pitch = shown > 1 ? max(self.pitch, card.width * 1.8 / CGFloat(shown - 1)) : 0
        ZStack {
            ForEach(0..<shown, id: \.self) { index in
                let offset = CGFloat(index) - CGFloat(shown - 1) / 2
                ArenaCardBack()
                    .frame(width: card.width, height: card.height)
                    .rotationEffect(.degrees(180 - Double(offset) * 4))
                    .offset(x: offset * pitch, y: -offset * offset * 0.9)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }
        }
        .frame(width: card.width + CGFloat(max(shown - 1, 0)) * pitch, height: card.height)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 card in hand" : "\(count) cards in hand")
    }
}

// MARK: - Phase strip

/// The reference's phase strip: all eight steps of a turn as dark icons on a thin track, always shown, the current one
/// lit in the active player's colour; moving on sends a spark along the track to the next icon.
struct ArenaPhaseStrip: View {
    let step: String?
    let viewerTurn: Bool
    let width: CGFloat
    var iconSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkX: CGFloat?
    @State private var ignite = false
    /// The latest move: a spark still travelling for an older one does nothing when it lands.
    @State private var moves = 0

    enum Icon { case diamond, card, sword, shield, burst }

    /// Beginning, main 1, attackers, blockers, damage, end of combat, main 2, end: the reference's strip.
    static let icons: [Icon] = [.diamond, .card, .sword, .shield, .burst, .diamond, .card, .diamond]

    /// Which of the eight icons a step lights.
    static func current(for step: String?) -> Int? {
        switch (step ?? "").lowercased().replacingOccurrences(of: "_", with: "-") {
        case "beginning", "untap", "upkeep", "draw": return 0
        case "precombat-main", "main1": return 1
        case "combat", "begin-combat", "declare-attackers": return 2
        case "declare-blockers": return 3
        case "first-combat-damage", "first-strike-damage", "combat-damage": return 4
        case "end-combat": return 5
        case "postcombat-main", "main2": return 6
        case "ending", "end", "end-turn", "cleanup": return 7
        default: return nil
        }
    }

    var body: some View {
        let icons = Self.icons
        let current = Self.current(for: step)
        let rim = viewerTurn ? ArenaPalette.viewerRim : ArenaPalette.opponentRim
        let spacing = (width - 12) / CGFloat(icons.count)
        let positions = icons.indices.map { 6 + spacing * (CGFloat($0) + 0.5) }
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [.clear, TavernPalette.brass.opacity(0.75), TavernPalette.brass.opacity(0.75), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: 1.4)
                .shadow(color: .black.opacity(0.6), radius: 0.5, y: 0.8)
                .position(x: width / 2, y: iconSize / 2 + 2)
            if let current, current > 0 {
                // The part of the turn already played, lit in the turn's colour.
                Capsule().fill(LinearGradient(colors: [rim.opacity(0.2), rim], startPoint: .leading, endPoint: .trailing))
                    .frame(width: positions[current] - positions[0], height: 2)
                    .position(x: (positions[0] + positions[current]) / 2, y: iconSize / 2 + 2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: current)
            }
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                // The current step stays dark only while the spark is still on its way to it.
                let on = index == current && sparkX == nil
                ArenaPhaseIcon(icon: icon, rim: rim, on: on, size: iconSize * (icon == .diamond ? 0.7 : 0.9) * (on ? 1.2 : 1))
                    .scaleEffect(on && ignite ? 1.45 : 1)
                    .position(x: positions[index], y: iconSize / 2 + 2)
            }
            if let sparkX {
                Circle().fill(RadialGradient(colors: [.white, rim, .clear], center: .center, startRadius: 0, endRadius: 7))
                    .frame(width: 14, height: 14)
                    .position(x: sparkX, y: iconSize / 2 + 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: iconSize + 4)
        .onChange(of: current) { old, new in move(from: old, to: new, positions: positions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TavernPhaseTrack.describe(step).title)
        .accessibilityIdentifier("board.phase.plate")
    }

    private func move(from old: Int?, to new: Int?, positions: [CGFloat]) {
        moves += 1
        let move = moves
        guard !reduceMotion, let old, let new, old != new else { sparkX = nil; return }
        let distance = abs(positions[new] - positions[old])
        let duration = 0.22 + min(0.26, Double(distance) * 0.0022)
        sparkX = positions[old]
        withAnimation(.easeInOut(duration: duration)) { sparkX = positions[new] }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard moves == move else { return }
            sparkX = nil
            withAnimation(.easeOut(duration: 0.08)) { ignite = true }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.35)) { ignite = false }
        }
    }
}

/// One phase icon: a small enamel piece in a brass rim with an engraved detail, dark walnut while it waits, lit from
/// gold-white into the turn's colour, with a halo, while it is the current step.
struct ArenaPhaseIcon: View {
    let icon: ArenaPhaseStrip.Icon
    let rim: Color
    let on: Bool
    let size: CGFloat

    var body: some View {
        let silhouette = ArenaPhaseShape(icon: icon)
        let enamel = on ? [Color.white, Color(red: 1, green: 0.86, blue: 0.56), rim]
                        : [Color(red: 0.42, green: 0.33, blue: 0.24), Color(red: 0.2, green: 0.14, blue: 0.1), Color(red: 0.08, green: 0.05, blue: 0.04)]
        ZStack {
            silhouette.fill(LinearGradient(colors: enamel, startPoint: .top, endPoint: .bottom))
            // Facet shading: the lower right turns away from the lamp.
            silhouette.fill(LinearGradient(colors: [.clear, .black.opacity(on ? 0.16 : 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
            ArenaPhaseDetail(icon: icon)
                .stroke(on ? Color(red: 0.42, green: 0.2, blue: 0.04).opacity(0.8) : TavernPalette.brass.opacity(0.6),
                        style: StrokeStyle(lineWidth: max(0.7, size * 0.05), lineCap: .round, lineJoin: .round))
            silhouette.stroke(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), TavernPalette.brass, Color(red: 0.33, green: 0.2, blue: 0.07)],
                                             startPoint: .top, endPoint: .bottom),
                              style: StrokeStyle(lineWidth: max(1, size * 0.07), lineJoin: .round))
            // A thin lamp highlight along the top edge.
            silhouette.stroke(Color.white.opacity(on ? 0.7 : 0.25), lineWidth: max(0.5, size * 0.03))
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
        }
        .frame(width: size, height: size)
        // The halo sits behind without taking part in the layout (inside the stack it doubled the lit icon's size).
        .background {
            if on {
                Circle()
                    .fill(RadialGradient(colors: [rim.opacity(0.7), rim.opacity(0)], center: .center, startRadius: 0, endRadius: size))
                    .frame(width: size * 2, height: size * 2)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        .shadow(color: on ? rim : .clear, radius: on ? 5 : 0)
    }
}

/// A rounded rectangle drawn from lines and arcs. iOS fills a `Path(roundedRect:)` returned from a small Shape at the
/// shape's full size from the rectangle's corner (a block beside each card icon, 2026-10-20), so the phase icons
/// draw theirs by hand.
func arenaRoundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
    let r = min(radius, rect.width / 2, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
    path.closeSubpath()
    return path
}

/// The engraved line inside each phase icon, on the same 20 × 20 grid: a gem's table, a card's art box and text, a
/// blade's fuller, a shield's boss and bands, a burst's core.
struct ArenaPhaseDetail: Shape {
    let icon: ArenaPhaseStrip.Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        switch icon {
        case .diamond:
            path.addLines([p(10, 6.6), p(13.4, 10), p(10, 13.4), p(6.6, 10)])
            path.closeSubpath()
        case .card:
            path.addPath(arenaRoundedRectPath(CGRect(origin: p(6.7, 4.3), size: CGSize(width: 6.6 * scale, height: 6.2 * scale)),
                                              radius: scale))
            path.move(to: p(7, 12.9)); path.addLine(to: p(13, 12.9))
            path.move(to: p(7, 14.9)); path.addLine(to: p(11.4, 14.9))
        case .sword:
            path.move(to: p(16.2, 3.8)); path.addLine(to: p(8.8, 11.2))
            path.addEllipse(in: CGRect(origin: p(1.6, 16.4), size: CGSize(width: 2 * scale, height: 2 * scale)))
        case .shield:
            path.addEllipse(in: CGRect(origin: p(7.8, 6.8), size: CGSize(width: 4.4 * scale, height: 4.4 * scale)))
            path.move(to: p(10, 3.4)); path.addLine(to: p(10, 6.8))
            path.move(to: p(10, 11.2)); path.addLine(to: p(10, 16.4))
        case .burst:
            path.addEllipse(in: CGRect(origin: p(7.4, 7.8), size: CGSize(width: 5.2 * scale, height: 5.2 * scale)))
        }
        return path
    }
}

/// The strip's icons, drawn on a 20 × 20 grid like the prototype's SVGs.
struct ArenaPhaseShape: Shape {
    let icon: ArenaPhaseStrip.Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: rect.minX + $0.0 * scale, y: rect.minY + $0.1 * scale) })
            path.closeSubpath()
            return path
        }
        let blade = [(17.6, 2.4), (17.1, 5.4), (8.6, 13.9), (6.1, 11.4), (14.6, 2.9)] as [(CGFloat, CGFloat)]
        let guardBar = [(3.9, 10.6), (9.4, 16.1), (8.2, 17.3), (2.7, 11.8)] as [(CGFloat, CGFloat)]
        let grip = [(5.6, 15.2), (3.3, 17.5), (2.5, 16.7), (4.8, 14.4)] as [(CGFloat, CGFloat)]
        switch icon {
        case .diamond:
            return polygon([(10, 3.5), (16.5, 10), (10, 16.5), (3.5, 10)])
        case .card:
            return arenaRoundedRectPath(CGRect(x: rect.minX + 5 * scale, y: rect.minY + 2.5 * scale, width: 10 * scale, height: 15 * scale),
                                        radius: 2 * scale)
        case .sword:
            var path = polygon(blade)
            path.addPath(polygon(guardBar)); path.addPath(polygon(grip))
            return path
        case .shield:
            var path = Path()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
            path.move(to: p(10, 2.2))
            path.addLine(to: p(16.4, 4.4))
            path.addLine(to: p(16.4, 9.4))
            path.addCurve(to: p(10, 17.8), control1: p(16.4, 13.6), control2: p(13.5, 16.3))
            path.addCurve(to: p(3.6, 9.4), control1: p(6.5, 16.3), control2: p(3.6, 13.6))
            path.addLine(to: p(3.6, 4.4))
            path.closeSubpath()
            return path
        case .burst:
            return polygon([(10, 1.6), (11.9, 6.4), (16.8, 4.5), (14.6, 9.2), (18.9, 11.9), (13.9, 12.7), (14.1, 17.8),
                            (10, 14.7), (5.9, 17.8), (6.1, 12.7), (1.1, 11.9), (5.4, 9.2), (3.2, 4.5), (8.1, 6.4)])
        }
    }
}

// MARK: - Controls

/// The corner's plaque buttons on Arena's button face: the orange pill for the call to action, the dark glass pill for the
/// other choice, a quiet word when it's the opponent's turn. The pill is drawn a little inside a 44 pt target.
struct ArenaPlaqueButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, waiting }
    var kind: Kind = .primary
    var fontSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        ArenaButtonFace(label: configuration.label,
                        kind: kind == .primary ? .primary : kind == .secondary ? .secondary : .quiet,
                        font: ArenaMenuStyle.title(kind == .waiting ? fontSize * 0.8 : fontSize, .bold),
                        pressed: configuration.isPressed, inset: 3, glow: 0.8)
            .pressSound(.uiTap, isPressed: configuration.isPressed)
    }
}

/// A small pill: pass ahead (">>") and Undo. Dark glass, orange while lit.
struct ArenaPillStyle: ButtonStyle {
    var lit = false

    func makeBody(configuration: Configuration) -> some View {
        ArenaButtonFace(label: configuration.label, kind: lit ? .primary : .secondary, font: ArenaMenuStyle.font(13, .heavy),
                        pressed: configuration.isPressed, glow: 0.7)
            .contentShape(Rectangle().inset(by: -8))
    }
}

/// Pass ahead: the skip options while you play, Stop while the table skips for you.
struct ArenaPassAheadPill: View {
    /// Opens the skip choices on the table (ArenaMenuCard), not in a system pop-over.
    var openMenu: () -> Void = {}
    @Environment(\.nativeTurnControl) private var control

    /// The skip choices in a few words each (Caleb, 2026-10-21: the long labels wrapped and covered the hand).
    static func items(_ control: NativeTurnControl) -> [ArenaMenuItem] {
        [ArenaMenuItem(id: "skip-responses", title: "To end of turn", subtitle: "Skips responses", symbol: "forward.end.fill",
                       enabled: control.canSkipResponses, action: control.skipResponses),
         ArenaMenuItem(id: "skip-to-my-turn", title: "To my turn", subtitle: "Skips responses", symbol: "forward.end.alt.fill",
                       enabled: control.canSkipToMyTurn, action: control.skipToMyTurn),
         ArenaMenuItem(id: "end-turn", title: "To end of turn", subtitle: "Stops if they respond", symbol: "forward.fill",
                       enabled: control.canEndTurn, action: control.endTurn),
         ArenaMenuItem(id: "full-control", title: "Full control", subtitle: control.isFullControl ? "On for this turn" : "Stop at every priority this turn",
                       symbol: "hand.raised.fill", lit: control.isFullControl, action: control.toggleFullControl)]
    }

    var body: some View {
        if let control {
            if control.isAutoPassing {
                Button(action: control.stop) { skipGlyph }
                    .buttonStyle(ArenaPillStyle(lit: true))
                    .accessibilityLabel("Stop skipping")
                    .accessibilityHint(control.status ?? "Stops future automatic passes")
            } else {
                Button(action: openMenu) { skipGlyph }
                .buttonStyle(ArenaPillStyle())
                .disabled(!control.canEndTurn && !control.canSkipResponses && !control.canSkipToMyTurn)
                .accessibilityLabel("Skip options")
                .accessibilityHint("Choose how long to skip responses. Required choices always stop skipping.")
            }
        }
    }

    private var skipGlyph: some View {
        Image(systemName: "forward.fill").font(.system(size: 13, weight: .black))
    }
}

/// One row of an Arena menu card.
struct ArenaMenuItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    /// On right now (full control this turn).
    var lit = false
    var enabled = true
    let action: () -> Void
}

/// A menu on the Arena table (Caleb, 2026-10-21: the gear's and the skip pill's menus were system pop-overs with an
/// arrow): glass rows in a gold hairline on a glass card, an icon, a title and a line under it. A row closes the card,
/// then acts.
struct ArenaMenuCard: View {
    let items: [ArenaMenuItem]
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                Button {
                    close()
                    item.action()
                } label: {
                    HStack(spacing: 12) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                                .foregroundStyle(item.lit ? TavernPalette.ember : Color(red: 0.98, green: 0.84, blue: 0.52))
                                .frame(width: 22)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(ArenaMenuStyle.font(16, .semibold))
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(ArenaMenuStyle.font(11, .medium)).opacity(0.65)
                            }
                        }
                        .foregroundStyle(ArenaGlass.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                    .modifier(ArenaGlassRow(primary: item.lit))
                }
                .buttonStyle(.plain)
                .disabled(!item.enabled)
                .opacity(item.enabled ? 1 : 0.45)
                .accessibilityLabel(item.subtitle.map { "\(item.title), \($0)" } ?? item.title)
                .accessibilityIdentifier("arena.menu.\(item.id)")
            }
        }
        .padding(10)
        .frame(width: 280)
        .modifier(ArenaGlassPanel(cornerRadius: 16, opacity: 0.96))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arena.menuCard")
    }
}

/// The stack card's eye (ArenaStackTuck): at the card's lower left, under the tab that opens the whole stack, it tucks the
/// card aside; tucked, a slim tab at the table's edge with the stack's count brings it back.
struct ArenaStackTab: View {
    static let tuckedWidth: CGFloat = 30
    let tucked: Bool
    let count: Int
    let action: () -> Void
    @Environment(\.arenaSafeArea) private var safeArea

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tucked ? "eye.fill" : "eye.slash.fill").font(.system(size: 12, weight: .bold))
                if tucked {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .black))
                    if count > 1 {
                        Text("\(count)").font(.system(size: 12, weight: .black, design: .serif)).monospacedDigit()
                    }
                }
            }
            .foregroundStyle(ArenaMenuStyle.gold)
            .frame(width: tucked ? Self.tuckedWidth : 26, height: tucked ? 84 : 40)
            .background {
                let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: tucked ? 4 : 0,
                                                   topTrailingRadius: tucked ? 4 : 0)
                shape.fill(LinearGradient(colors: [ArenaGlass.top.opacity(0.96), ArenaGlass.bottom.opacity(0.96)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(ArenaMenuStyle.gold.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }
            // A 44 pt target around the slim tab, the tab at its right edge (against the card, or the table's edge).
            .frame(width: 44, height: tucked ? 92 : 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        // Tucked, it stays clear of a sideways phone's cutout.
        .offset(x: tucked ? -safeArea.insets.trailing : 0)
        .accessibilityLabel(tucked ? String(localized: "Show the stack, \(count) on it") : String(localized: "Tuck the stack away"))
        .accessibilityIdentifier(tucked ? "arena.stack.show" : "arena.stack.tuck")
    }
}

/// The top of the stack as a big card on the right (the reference's stack), with the count, and a tab that opens the
/// whole stack. A tap shows the card's full text.
struct ArenaStackCard: View {
    let object: XmageStackObject
    let count: Int
    let size: CGSize
    /// A commander cast from the command zone: the card wears a gold rim and a crown, and that is its whole fanfare.
    var commander = false
    /// The source's permanent on the table, for an ability whose card XMage didn't send (its art stays on the card).
    var fallbackSource: ZoneCard? = nil
    /// Plays the landing: only the first time this object shows, not again when the one above it resolves.
    var lands = true
    let inspect: (ZoneCard) -> Void
    let openStack: () -> Void

    private var sourceCard: ZoneCard? { object.displaySourceCard ?? fallbackSource }

    /// XMage marks spells; everything else on the stack is an activated or triggered ability.
    static func isAbility(_ object: XmageStackObject) -> Bool { (object.objectType ?? "").uppercased() != "SPELL" && object.objectType != nil }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BoardFXLevel.key) private var fxLevel = BoardFXLevel.defaultValue
    /// The card settles onto the stack with a little overshoot.
    @State private var settled = false
    /// While the landing plays: when it started.
    @State private var landedAt: Date?
    private static let landing: Double = 0.55

    /// The light a spell lands in: its colour, gold for several colours, a commander or an ability.
    private var arrivalColor: Color {
        if commander || Self.isAbility(object) { return Color(red: 1, green: 0.82, blue: 0.45) }
        let cost = (object.displaySourceCard?.card.manaCost ?? "").uppercased()
        let colors = ["W", "U", "B", "R", "G"].filter { cost.contains("{\($0)") || cost.contains("/\($0)") }
        guard colors.count == 1 else { return colors.isEmpty ? Color(red: 0.85, green: 0.88, blue: 0.95) : Color(red: 1, green: 0.82, blue: 0.45) }
        switch colors[0] {
        case "W": return Color(red: 1, green: 0.95, blue: 0.78)
        case "U": return Color(red: 0.4, green: 0.7, blue: 1)
        case "B": return Color(red: 0.72, green: 0.5, blue: 0.9)
        case "R": return Color(red: 1, green: 0.45, blue: 0.25)
        default: return Color(red: 0.45, green: 0.9, blue: 0.5)
        }
    }

    var body: some View {
        content
            .scaleEffect(settled || !lands ? 1 : 1.07)
            .background {
                if let landedAt {
                    TimelineView(.animation) { timeline in arrivalBloom(min(1, timeline.date.timeIntervalSince(landedAt) / Self.landing)) }
                }
            }
            .overlay {
                if let landedAt {
                    TimelineView(.animation) { timeline in arrivalShine(min(1, timeline.date.timeIntervalSince(landedAt) / Self.landing)) }
                }
            }
            .onAppear {
                // The reference's landing: the card settles with a little overshoot in a bloom of its colour, a shine
                // runs across it and a few motes drift off (Caleb, 2026-10-21: no rays). About half a second, light only.
                guard lands, !reduceMotion, BoardFXLevel(rawValue: fxLevel) != .off else { settled = true; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { settled = true }
                let start = Date()
                landedAt = start
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.landing + 0.05))
                    if landedAt == start { landedAt = nil }
                }
            }
    }

    /// Light of the spell's colour behind the card, flaring as it lands and fading as it settles, and motes drifting off.
    private func arrivalBloom(_ t: Double) -> some View {
        let flare = sin(.pi * t)
        return ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.12)
                .fill(arrivalColor)
                .padding(-size.width * (0.04 + 0.1 * flare))
                .blur(radius: size.width * 0.12)
                .opacity(0.85 * flare)
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * 2 * .pi + 0.4
                Circle().fill(.white)
                    .frame(width: 4, height: 4)
                    .shadow(color: arrivalColor, radius: 3)
                    .offset(x: cos(angle) * size.width * (0.42 + 0.3 * t), y: sin(angle) * size.height * (0.38 + 0.24 * t) - 14 * t)
                    .opacity(flare)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A band of light that sweeps once across the card as it lands.
    private func arrivalShine(_ t: Double) -> some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.5), location: 0.5),
                               .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            .frame(width: size.width * 0.45, height: size.height * 1.6)
            .rotationEffect(.degrees(18))
            .offset(x: size.width * (-1 + 2 * t))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: size.width * 0.05))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var content: some View {
        ZStack {
            if let card = sourceCard, Self.isAbility(object) {
                Button { inspect(card) } label: {
                    ArenaAbilityCard(source: card, text: object.rulesText ?? object.displayName, size: size)
                }
                .buttonStyle(.plain)
            } else if let card = object.displaySourceCard {
                Button { inspect(card) } label: {
                    // The printed card already shows its power and toughness: no badges over it.
                    CardTile(card: card, selected: false, zoneName: "Stack", width: size.width, height: size.height,
                             ignoreTappedRotation: true, imageVariant: .inspection)
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            } else {
                // A spell or ability whose card isn't known: its name and text on the Arena's ability card.
                ArenaAbilityCard(source: nil, name: object.displayName, text: object.rulesText ?? object.displaySourceName, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if commander {
                RoundedRectangle(cornerRadius: size.width * 0.05)
                    .strokeBorder(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), TavernPalette.brass,
                                                          Color(red: 0.6, green: 0.42, blue: 0.12)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 3)
                    .shadow(color: Color(red: 1, green: 0.8, blue: 0.35).opacity(0.8), radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if commander {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.3, green: 0.17, blue: 0.03))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.58), TavernPalette.brass],
                                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(y: -14)
                    .accessibilityLabel("Commander")
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
        .overlay(alignment: .leading) {
            // A tab on the card's left edge opens the whole stack, with how many objects are on it (Caleb, 2026-10-21:
            // the loose coin read as a scroll arrow).
            Button(action: openStack) {
                VStack(spacing: 3) {
                    if count > 1 {
                        Text("\(count)")
                            .font(ArenaMenuStyle.font(15, .heavy)).monospacedDigit()
                            .foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.52))
                    }
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .black))
                        .foregroundStyle(ArenaGlass.text)
                }
                .frame(width: 26, height: count > 1 ? 58 : 44)
                .background(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                    .fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                    .strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3, x: -1, y: 2)
                .frame(width: 44, height: max(44, count > 1 ? 58 : 44), alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -43)
            .accessibilityLabel(count > 1 ? "Open the stack, \(count) objects" : "Open the stack")
            .accessibilityIdentifier("board.stack.tray")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.isAbility(object) ? "Top of the stack: an ability of \(object.displaySourceName)"
                                                   : "Top of the stack: \(object.displayName)")
    }
}

/// The slim caption over the midline that says what the table wants ("Choose attackers.", "Pay {1}{R}").
// MARK: - Arena chrome

/// The Arena board's own surfaces, the reference game's dialogs and browsers rather than the Hearth board's tooled
/// leather and parchment: dark glass a little lighter at the top, edged in a fine gold hairline. The plaques and gold
/// titles stay; they are already the Arena corner's.
enum ArenaGlass {
    static let top = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let bottom = Color(red: 0.04, green: 0.045, blue: 0.06)
    static let hairline = LinearGradient(colors: [Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.85),
                                                  Color(red: 0.55, green: 0.38, blue: 0.14).opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom)
    static let text = Color(red: 0.95, green: 0.92, blue: 0.86)
}

/// A filled glass surface (sheets, pop-overs, full-width backings).
struct ArenaGlassBackground: View {
    var body: some View {
        LinearGradient(colors: [ArenaGlass.top.opacity(0.97), ArenaGlass.bottom.opacity(0.98)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1) }
            .ignoresSafeArea()
    }
}

/// A floating glass panel with rounded corners in the gold hairline.
struct ArenaGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14
    var opacity: Double = 0.92

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: [ArenaGlass.top.opacity(opacity), ArenaGlass.bottom.opacity(opacity)],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)))
            }
            .overlay { shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
    }
}

/// ArenaGlassPanel only on the Arena board.
struct ArenaGlassIf: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 14

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.modifier(ArenaGlassPanel(cornerRadius: cornerRadius)) } else { content }
    }
}

/// Closes a board panel that the Arena board shows on the table instead of in a sheet (`boardSheet`). Panels that close
/// themselves call it in place of `dismiss`, which would reach past the board.
private struct BoardPanelCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

extension EnvironmentValues {
    var boardPanelClose: (() -> Void)? {
        get { self[BoardPanelCloseKey.self] }
        set { self[BoardPanelCloseKey.self] = newValue }
    }
}

extension View {
    /// A board panel: a sheet on the Hearth board; on the Arena board a glass panel over the dimmed table, no system sheet.
    @ViewBuilder
    func boardSheet<Content: View>(isPresented: Binding<Bool>, arena: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        if arena {
            overlay { ArenaPanelOverlay(isPresented: isPresented, content: content) }
        } else {
            sheet(isPresented: isPresented, content: content)
        }
    }
}

/// The Arena board's panel: centred on the table over a dimmed board; a tap on the board closes it.
struct ArenaPanelOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                if isPresented {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented = false }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    content()
                        .environment(\.boardPanelClose, { isPresented = false })
                        .environment(\.arenaBoard, true)
                        .frame(maxWidth: min(proxy.size.width - 32, landscape ? 640 : 560),
                               maxHeight: proxy.size.height * (landscape ? 0.92 : 0.84))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .modifier(ArenaGlassPanel(cornerRadius: 22, opacity: 0.96))
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                        .accessibilityAddTraits(.isModal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: isPresented)
        }
    }
}

/// A row or option on glass: a lighter pane in the hairline; primary rows a touch brighter.
struct ArenaGlassRow: ViewModifier {
    var primary = false
    var danger = false
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(danger ? Color(red: 0.42, green: 0.08, blue: 0.07).opacity(0.85)
                                  : Color.white.opacity(primary ? 0.11 : 0.06))
            }
            .overlay { shape.strokeBorder(danger ? AnyShapeStyle(Color(red: 0.9, green: 0.4, blue: 0.3).opacity(0.7)) : AnyShapeStyle(ArenaGlass.hairline),
                                          lineWidth: primary ? 1.2 : 0.8) }
    }
}

/// ArenaGlassRow only on the Arena board.
struct ArenaGlassRowIf: ViewModifier {
    let active: Bool
    var primary = false

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.modifier(ArenaGlassRow(primary: primary)) } else { content }
    }
}

/// The glass close button that stands in for the Hearth board's wax seal.
struct ArenaCloseLabel: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(ArenaGlass.text)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
    }
}

/// A card's colour for its frame, the reference's way: its one colour, gold for several, grey for none (lands without a
/// cost take their basic land types).
enum ArenaCardColor {
    static func frame(for card: ZoneCard) -> Color {
        var colors = Set<String>()
        let cost = card.card.manaCost?.uppercased() ?? ""
        for symbol in ["W", "U", "B", "R", "G"] where cost.contains(symbol) { colors.insert(symbol) }
        for color in card.card.tokenColors ?? [] {
            switch color.lowercased() {
            case "w", "white": colors.insert("W")
            case "u", "blue": colors.insert("U")
            case "b", "black": colors.insert("B")
            case "r", "red": colors.insert("R")
            case "g", "green": colors.insert("G")
            default: break
            }
        }
        if colors.isEmpty {
            for (land, symbol) in [("Plains", "W"), ("Island", "U"), ("Swamp", "B"), ("Mountain", "R"), ("Forest", "G")]
            where card.card.typeLine.localizedCaseInsensitiveContains(land) { colors.insert(symbol) }
        }
        if colors.count > 1 { return Color(red: 0.93, green: 0.74, blue: 0.32) }
        switch colors.first {
        case "W": return Color(red: 0.93, green: 0.88, blue: 0.72)
        case "U": return Color(red: 0.25, green: 0.52, blue: 0.95)
        case "B": return Color(red: 0.42, green: 0.30, blue: 0.48)
        case "R": return Color(red: 0.86, green: 0.22, blue: 0.14)
        case "G": return Color(red: 0.22, green: 0.66, blue: 0.30)
        default: return Color(red: 0.62, green: 0.62, blue: 0.66)
        }
    }
}

/// An ability on the stack the reference game's way: its source's frame colour and art, a type line that says
/// "Ability", only the ability's own text, a rounded foot, and the keyword's icon in the corner when it has one.
struct ArenaAbilityCard: View {
    let source: ZoneCard?
    var name: String? = nil
    /// The type line: "Ability", or "Mode 2" for a modal spell's mode.
    var kind = "Ability"
    let text: String
    let size: CGSize
    /// A planeswalker ability's loyalty cost ("+1", "−4"), on a shield at the card's foot as in the reference.
    var loyalty: String? = nil

    var body: some View {
        let frame = source.map(ArenaCardColor.frame(for:)) ?? Color(red: 0.62, green: 0.62, blue: 0.66)
        let edge = max(3, size.width * 0.035)
        let shape = ArenaAbilityShape(corner: size.width * 0.05)
        let icon = XmageCardIcon.keywordIcons(rules: text).first.flatMap { XmageCardIcon.assetName(for: $0.iconType) }
        ZStack {
            shape.fill(LinearGradient(colors: [frame, frame.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                Text(source?.card.name ?? name ?? "Ability")
                    .font(.system(size: max(10, size.width * 0.075), weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.06))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, size.width * 0.05)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: size.height * 0.085)
                    .background(ZStack { Color(white: 0.94); frame.opacity(0.28) })
                Group {
                    if let source {
                        TavernArtCrop(card: source, zoneName: "Stack", tagReserve: 0)
                    } else {
                        LinearGradient(colors: [frame.opacity(0.6), Color(red: 0.1, green: 0.1, blue: 0.12)], startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: "sparkles").font(.system(size: size.width * 0.2, weight: .bold)).foregroundStyle(.white.opacity(0.5)))
                    }
                }
                .frame(height: size.height * 0.4)
                .clipped()
                Text(kind)
                    .font(.system(size: max(9, size.width * 0.062), weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.06))
                    .padding(.horizontal, size.width * 0.05)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: size.height * 0.07)
                    .background(ZStack { Color(white: 0.9); frame.opacity(0.22) })
                ZStack(alignment: .topLeading) {
                    Color(red: 0.97, green: 0.95, blue: 0.9)
                    GameRulesText(source: PromptDisplayText.clean(text), symbolSize: max(9, size.width * 0.06))
                        .font(.system(size: max(9, size.width * 0.062), weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.1, green: 0.08, blue: 0.06))
                        .minimumScaleFactor(0.55)
                        .padding(size.width * 0.06)
                }
            }
            .padding(edge)
            .clipShape(shape.inset(by: edge * 0.5))
            shape.strokeBorder(.black.opacity(0.85), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottom) {
            if let loyalty {
                Text(loyalty)
                    .font(.system(size: max(12, size.width * 0.1), weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: size.width * 0.32, height: size.width * 0.24)
                    .background(ArenaShieldShape().fill(Color(red: 0.08, green: 0.08, blue: 0.1)))
                    .overlay(ArenaShieldShape().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                    .offset(y: size.width * 0.1)
                    .accessibilityLabel("Loyalty \(loyalty)")
            }
        }
        .overlay(alignment: .topLeading) {
            if let icon, let image = UIImage(named: icon) {
                Image(uiImage: image).resizable().scaledToFit()
                    .padding(4)
                    .frame(width: size.width * 0.16, height: size.width * 0.16)
                    .background(Circle().fill(Color(red: 0.12, green: 0.1, blue: 0.08)))
                    .overlay(Circle().stroke(TavernPalette.brass, lineWidth: 1))
                    .offset(x: -size.width * 0.06, y: size.height * 0.1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ability of \(source?.card.name ?? name ?? "a permanent"): \(PromptDisplayText.clean(text))")
    }
}

/// The Arena board's ability browser, after the reference game's browsers (Caleb, 2026-10-20): a dark veil, the
/// abilities as Arena ability cards in a row, one line of instructions and the corner's plaques. Ordering triggers,
/// you tap them in the order they should resolve (1 resolves first) and press Done; choosing an ability, a tap picks
/// it. A hold shows the source card.
struct ArenaAbilityBrowser: View {
    let prompt: PromptEnvelopeV2
    let abilities: [XmagePromptAbility]
    /// Ordering triggers (XMage's PICK_ABILITY) rather than choosing one ability.
    let ordering: Bool
    let pending: Bool
    let screen: CGSize
    var canRemember = false
    /// The prompt's own way out (XMage's Cancel), when it has one.
    var cancel: (title: String, action: () -> Void)?
    let choose: (XmagePromptAbility) -> Void
    /// The order to resolve in, first to last, and whether XMage should keep putting the first pick first.
    let order: ([XmagePromptAbility], Bool) -> Void
    let inspect: (ZoneCard) -> Void
    @State private var picked: [String] = []
    @State private var remember = false

    private var cardSize: CGSize {
        let landscape = screen.width > screen.height
        let height = min(landscape ? screen.height * 0.5 : 230, 250)
        return CGSize(width: height * 0.72, height: height)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(ordering ? "Order your triggers" : "Choose an ability")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                Text(ordering ? "Tap them in the order they resolve: 1 resolves first." : PromptDisplayText.clean(prompt.message))
                    .font(ArenaMenuStyle.font(14, .medium))
                    .foregroundStyle(ArenaGlass.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(abilities) { ability in card(ability) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(minWidth: screen.width)
                }
                if ordering && canRemember {
                    RememberChoiceToggle(title: "Always put my last-resolving pick first", isOn: $remember)
                }
                if !ordering, let cancel {
                    Button(cancel.title, action: cancel.action)
                        .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                        .frame(width: 150, height: 40)
                        .accessibilityIdentifier("arena.abilities.cancel")
                }
                if ordering {
                    HStack(spacing: 12) {
                        Button("Auto Order") { order(abilities, false) }
                            .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                            .frame(width: 150, height: 40)
                            .accessibilityIdentifier("arena.triggers.auto")
                        Button(picked.count >= abilities.count - 1 ? "Done" : "\(picked.count) of \(abilities.count)") {
                            let chosen = picked.compactMap { id in abilities.first { $0.id == id } }
                            order(chosen + abilities.filter { !picked.contains($0.id) }, remember)
                        }
                        .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                        .frame(width: 150, height: 40)
                        .disabled(picked.count < abilities.count - 1)
                        .accessibilityIdentifier("arena.triggers.done")
                    }
                }
            }
            .disabled(pending)
            .opacity(pending ? 0.7 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.abilityBrowser")
    }

    private func card(_ ability: XmagePromptAbility) -> some View {
        let number = picked.firstIndex(of: ability.id).map { $0 + 1 }
        let loyalty = ArenaLoyalty.split(ability.rulesText ?? ability.label)
        return ArenaAbilityCard(source: ability.sourceCard, name: ability.sourceName, text: loyalty?.text ?? ability.rulesText ?? ability.label,
                                size: cardSize, loyalty: loyalty?.cost)
            .overlay {
                if number != nil {
                    ArenaAbilityShape(corner: cardSize.width * 0.05).strokeBorder(Color(red: 1, green: 0.82, blue: 0.4), lineWidth: 3)
                        .shadow(color: Color(red: 1, green: 0.75, blue: 0.3), radius: 8)
                }
            }
            .overlay(alignment: .top) {
                if let number { ArenaCountBadge(count: number, size: 34).offset(y: -17).transition(.scale) }
            }
            .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
            .scaleEffect(number != nil ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: number)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !pending else { return }
                if !ordering { choose(ability); return }
                if let index = picked.firstIndex(of: ability.id) { picked.remove(at: index) } else { picked.append(ability.id) }
                GameHaptics.selection()
            }
            .onLongPressGesture(minimumDuration: 0.35) { if let source = ability.sourceCard { inspect(source) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ability.sourceName ?? ability.sourceCard?.card.name ?? "Ability"): \(PromptDisplayText.clean(ability.rulesText ?? ability.label))")
            .accessibilityValue(number.map { "Resolves \($0)" } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("arena.ability.\(ability.id)")
    }
}

/// The whole stack the Arena way (Caleb, 2026-10-20): its cards side by side over the dimmed table, like the ability
/// browser, the one that resolves next first. Spells show as their card, abilities as ability cards; whose each is and
/// what it targets sits underneath. A tap reads a card; Resolve All and Done below. Landscape lays them in one row,
/// portrait in two columns, so many show at once.
/// A target question whose choices are on the stack (ArenaTargetReach; Gogo copying Zur's trigger) opens it to choose:
/// its message is the title, the choices glow, the rest dim, and a tap chooses. Done steps aside to the table.
struct ArenaStackBrowser: View {
    @Environment(\.arenaSafeArea) private var safeArea
    let snapshot: GameSnapshot
    let screen: CGSize
    var resolveAll: (() -> Void)?
    var stopSkipping: (() -> Void)?
    var choosable: Set<String> = []
    /// XMage's own answers beside the choices (Cancel for an optional target).
    var answers: [(id: String, title: String, action: () -> Void)] = []
    var choose: ((String) -> Void)?
    let inspect: (ZoneCard) -> Void
    let close: () -> Void

    private var choosing: Bool { choose != nil && !choosable.isEmpty }

    private var objects: [XmageStackObject] { snapshot.stackTopFirst }
    private var landscape: Bool { screen.width > screen.height }

    private var cardSize: CGSize {
        if landscape {
            let height = min(screen.height * 0.5, 230)
            return CGSize(width: height * 0.72, height: height)
        }
        let width = min((screen.width - 24 * 2 - 18) / 2, 180)
        return CGSize(width: width, height: width / 0.72)
    }

    private var responding: Bool {
        (snapshot.legalActions ?? []).contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(spacing: landscape ? 8 : 12) {
                header
                if landscape {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in entry(object, position: index) }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .frame(minWidth: screen.width)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.fixed(cardSize.width), spacing: 18, alignment: .top),
                                            GridItem(.fixed(cardSize.width), spacing: 18, alignment: .top)],
                                  alignment: .center, spacing: 26) {
                            ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in entry(object, position: index) }
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
                buttons
            }
            .padding(.top, safeArea.top(landscape ? 50 : 56))
            .padding(.horizontal, landscape ? safeArea.side : 0)
            .padding(.bottom, landscape ? 10 : 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.stackBrowser")
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(choosing ? PromptDisplayText.clean(snapshot.promptEnvelopeV2?.message ?? "Choose one") : "The Stack")
                    .font(.system(size: choosing ? 19 : 22, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                // Choosing, the question is the title and each card wears its place.
                if !choosing {
                    ArenaCountBadge(count: snapshot.xmage?.stack.count ?? objects.count, size: 28)
                        .accessibilityLabel("\(snapshot.xmage?.stack.count ?? objects.count) on the stack")
                }
            }
            .padding(.horizontal, 24)
            HStack(spacing: 8) {
                Text(objects.count > 1 ? "Resolves left to right" : "Resolves next")
                    .font(ArenaMenuStyle.font(13, .medium))
                    .foregroundStyle(ArenaGlass.text.opacity(0.75))
                TavernTag(text: choosing ? "CHOOSE ONE" : responding ? "YOUR RESPONSE" : "WAITING", leather: true,
                          accent: choosing || responding ? TavernPalette.ember : nil)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if let stopSkipping {
                Button("Stop skipping", action: stopSkipping)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 15))
                    .frame(width: 150, height: 40)
            }
            if let resolveAll, !choosing {
                Button("Resolve All", action: resolveAll)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                    .frame(width: 150, height: 40)
                    .accessibilityIdentifier("board.stack.sheet.resolveAll")
            }
            if choosing {
                ForEach(answers, id: \.id) { answer in
                    Button(answer.title, action: answer.action)
                        .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 16))
                        .frame(width: 150, height: 40)
                }
            }
            Button(choosing ? "View Battlefield" : "Done", action: close)
                .buttonStyle(ArenaPlaqueButtonStyle(kind: choosing ? .secondary : .primary, fontSize: choosing ? 15 : 16))
                .frame(width: 150, height: 40)
                .accessibilityIdentifier("board.stack.done")
        }
    }

    private func entry(_ object: XmageStackObject, position: Int) -> some View {
        let next = position == 0
        let ability = ArenaStackCard.isAbility(object) || object.displaySourceCard == nil
        let choice = choosing && choosable.contains(object.id)
        return VStack(spacing: 7) {
            Group {
                if ability {
                    ArenaAbilityCard(source: object.displaySourceCard, name: object.displaySourceCard == nil ? object.displayName : nil,
                                     text: object.rulesText ?? object.displayName, size: cardSize)
                } else if let card = object.displaySourceCard {
                    CardTile(card: card, selected: false, zoneName: "Stack", width: cardSize.width, height: cardSize.height,
                             imageVariant: .inspection)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if choice {
                    RoundedRectangle(cornerRadius: cardSize.width * 0.05)
                        .strokeBorder(ArenaPalette.targetGlow, lineWidth: 3)
                        .shadow(color: ArenaPalette.targetGlow, radius: 9)
                        .allowsHitTesting(false)
                } else if next && !choosing {
                    RoundedRectangle(cornerRadius: cardSize.width * 0.05)
                        .strokeBorder(Color(red: 1, green: 0.82, blue: 0.4), lineWidth: 3)
                        .shadow(color: Color(red: 1, green: 0.75, blue: 0.3), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) { ArenaCountBadge(count: position + 1, size: 30).offset(y: -15) }
            .saturation(choosing && !choice ? 0.35 : 1)
            .opacity(choosing && !choice ? 0.55 : 1)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if choice, let choose { GameHaptics.selection(); choose(object.id) } else if let card = object.displaySourceCard { inspect(card) }
            }
            .onLongPressGesture(minimumDuration: 0.35) { if let card = object.displaySourceCard { inspect(card) } }
            VStack(spacing: 2) {
                Text(next ? "RESOLVES NEXT" : owner(object).uppercased())
                    .font(ArenaMenuStyle.font(10, .heavy)).tracking(0.8)
                    .foregroundStyle(next ? Color(red: 0.98, green: 0.72, blue: 0.4) : ArenaGlass.text.opacity(0.65))
                if next {
                    Text(owner(object)).font(ArenaMenuStyle.font(11, .regular).italic()).foregroundStyle(ArenaGlass.text.opacity(0.75))
                }
                if let targets = object.targetIds, !targets.isEmpty {
                    Label(StackTargetPresentation.labels(for: targets, in: snapshot).joined(separator: ", "), systemImage: "scope")
                        .font(ArenaMenuStyle.font(11, .semibold))
                        .foregroundStyle(ArenaGlass.text)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: cardSize.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position + 1). \(object.displayName), \(owner(object))")
        .accessibilityValue(PromptDisplayText.clean(object.rulesText ?? ""))
        .accessibilityHint(choice ? "Chooses it" : object.displaySourceCard == nil ? "" : "Tap to read the card")
        .accessibilityAddTraits(choice ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("arena.stack.\(object.id)")
    }

    /// "Yours" or "Aurelia's".
    private func owner(_ object: XmageStackObject) -> String {
        guard let controller = object.controllerId else { return object.displaySourceName }
        return snapshot.isViewer(controller) ? "Yours" : "\(snapshot.playerLabel(controller))’s"
    }
}

/// A question the Arena way (Caleb, 2026-10-20; the reference's "Pay 2 life?"): the table dims, the question is the
/// title, the card it's about stands in the middle (an ability as its ability card), and the answers sit under it as
/// plaques. "View Battlefield" steps it aside.
struct ArenaQuestionStage<Answers: View>: View {
    @Environment(\.arenaSafeArea) private var safeArea
    let title: String
    let object: XmageStackObject?
    let card: ZoneCard?
    let screen: CGSize
    let inspect: (ZoneCard) -> Void
    @ViewBuilder let answers: Answers
    @State private var peeking = false

    /// The question in a few words, the reference's way ("Use Esper Sentinel's ability?"); the whole of XMage's message
    /// goes under it when it says more (Caleb, 2026-10-21: long questions filled the screen).
    static func headline(_ message: String, object: XmageStackObject?, card: ZoneCard?) -> (title: String, detail: String?) {
        let clean = PromptDisplayText.clean(message)
        guard clean.count > 64, object != nil || card != nil else { return (clean, nil) }
        if let mark = clean.firstIndex(of: "?"), clean.distance(from: clean.startIndex, to: mark) < 64 {
            let head = String(clean[...mark])
            let rest = clean[clean.index(after: mark)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (head, rest.isEmpty ? nil : rest)
        }
        // "Use X's ability?" only when the message is about X; otherwise its first sentence.
        let name = object?.displaySourceName ?? card?.card.name ?? ""
        if !name.isEmpty, clean.localizedCaseInsensitiveContains(name), object.map(ArenaStackCard.isAbility) ?? false {
            return ("Use \(name)'s ability?", clean)
        }
        // Otherwise its first sentence over the rest, or the whole question when it is one long sentence: never cut off, and
        // never said twice (the judge, 2026-10-22).
        if let stop = clean.range(of: ". "), clean.distance(from: clean.startIndex, to: stop.lowerBound) < 70 {
            let rest = clean[stop.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(clean[..<stop.lowerBound]) + ".", rest.isEmpty ? nil : rest)
        }
        return (clean, nil)
    }

    var body: some View {
        let landscape = screen.width > screen.height
        let height = landscape ? min(screen.height * 0.48, 220) : min(screen.height * 0.36, 330)
        let size = CGSize(width: height * 0.72, height: height)
        let headline = Self.headline(title, object: object, card: card)
        let art = object?.displaySourceCard ?? card
        ZStack {
            Color.black.opacity(peeking ? 0 : 0.8).ignoresSafeArea()
                .allowsHitTesting(!peeking)
                .accessibilityHidden(true)
            VStack(spacing: landscape ? 10 : 18) {
                VStack(spacing: 4) {
                GameRulesText(source: headline.title, cardName: object?.displaySourceName ?? card?.card.name, symbolSize: 18)
                    .font(.system(size: landscape ? 20 : 22, weight: .bold, design: .serif))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("arena.question.title")
                if let detail = headline.detail {
                    GameRulesText(source: detail, cardName: object?.displaySourceName ?? card?.card.name, symbolSize: 13)
                        .font(ArenaMenuStyle.font(13, .medium))
                        .foregroundStyle(ArenaGlass.text.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("arena.question.detail")
                }
                }
                Group {
                    if let object, ArenaStackCard.isAbility(object) || object.displaySourceCard == nil {
                        // Its permanent's art from the table when XMage sent no card.
                        ArenaAbilityCard(source: art, name: art == nil ? object.displayName : nil,
                                         text: object.rulesText ?? object.displayName, size: size)
                    } else if let shown = art {
                        CardTile(card: shown, selected: false, zoneName: "Question", width: size.width, height: size.height,
                                 ignoreTappedRotation: true, imageVariant: .inspection)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                .contentShape(Rectangle())
                .onTapGesture { if let art { inspect(art) } }
                answers
            }
            .padding(.top, safeArea.top(landscape ? 50 : 40))
            .padding(.horizontal, landscape ? safeArea.side : 0)
            .opacity(peeking ? 0 : 1)
            .allowsHitTesting(!peeking)
            Button(peeking ? "Back to the question" : "View Battlefield") { peeking.toggle() }
                .font(ArenaMenuStyle.font(12, .bold))
                .foregroundStyle(ArenaGlass.text)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .frame(minHeight: 44)
                .accessibilityIdentifier("arena.question.viewBattlefield")
                // Clear of the gear (top right in landscape): padded before it is placed, so it never widens the layer.
                .padding(.top, landscape ? 4 : 50)
                .padding(.trailing, landscape ? 120 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.question")
    }
}

/// A modal spell's modes the Arena way: each mode is a card with the spell's art over its text, side by side over the
/// dimmed table; a tap chooses it (XMage asks again for each further mode). The prompt's own answers (Done) sit below.
struct ArenaModeBrowser: View {
    @Environment(\.arenaSafeArea) private var safeArea
    let title: String
    let detail: String
    let source: ZoneCard?
    let modes: [ChoicePromptOption]
    let pending: Bool
    let screen: CGSize
    var answers: [(id: String, title: String, action: () -> Void)] = []
    let choose: (ChoicePromptOption) -> Void
    let inspect: (ZoneCard) -> Void

    private var landscape: Bool { screen.width > screen.height }

    /// Upright, more than two modes sit two to a row so none runs off the edge (the judge, 2026-10-22).
    private var columns: Int { landscape || modes.count <= 2 ? max(1, modes.count) : 2 }

    private var cardSize: CGSize {
        if landscape {
            let height = min(screen.height * 0.52, 250)
            return CGSize(width: height * 0.72, height: height)
        }
        let width = min(180, (screen.width - 48 - 16 * CGFloat(columns - 1)) / CGFloat(columns))
        return CGSize(width: width, height: width / 0.72)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(title)
                    .font(ArenaMenuStyle.title(22, .bold))
                    .foregroundStyle(ArenaGlass.text)
                    .shadow(color: .black, radius: 2)
                if detail.lowercased() != title.lowercased() {
                    Text(detail)
                        .font(ArenaMenuStyle.font(14, .medium))
                        .foregroundStyle(ArenaGlass.text.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                }
                ScrollView(landscape ? .horizontal : .vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardSize.width), spacing: 16), count: columns), spacing: 16) {
                        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                            // The card names its mode once: in the type line under the source's art, or as its name
                            // when there is no source card.
                            ArenaAbilityCard(source: source, name: source == nil ? "Mode \(index + 1)" : nil,
                                             kind: source == nil ? "Mode" : "Mode \(index + 1)",
                                             text: Self.text(of: mode), size: cardSize)
                                .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
                                .contentShape(Rectangle())
                                .onTapGesture { guard !pending else { return }; GameHaptics.selection(); choose(mode) }
                                .onLongPressGesture(minimumDuration: 0.35) { if let source { inspect(source) } }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(PromptDisplayText.clean(mode.label))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("arena.mode.\(mode.id)")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(minWidth: screen.width)
                }
                .mask(ArenaScrollFade(depth: landscape ? 0 : 20))
                // Upright the cards scroll in the room left, so the title stays on screen.
                .frame(maxHeight: landscape ? nil : .infinity)
                if !answers.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(answers, id: \.id) { answer in
                            Button(answer.title, action: answer.action)
                                .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                                .frame(width: 150, height: 40)
                        }
                    }
                }
            }
            .padding(.top, safeArea.top(landscape ? 50 : 96))
            .padding(.horizontal, landscape ? safeArea.side : 0)
            .padding(.bottom, landscape ? 10 : 28)
            .disabled(pending)
            .opacity(pending ? 0.7 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("arena.modeBrowser")
    }

    /// "1. Create a Treasure token." without its number: the card's place shows the order.
    static func text(of mode: ChoicePromptOption) -> String {
        let label = PromptDisplayText.clean(mode.label)
        guard let range = label.range(of: #"^\d+\.\s*"#, options: .regularExpression) else { return label }
        return String(label[range.upperBound...])
    }
}

/// The frame every Arena browser shares (docs/ARENA_STYLE.md): the table dims, a title and one line of instructions sit
/// at the top, the content in the middle, answers at the bottom, the source card on the right in landscape and "View
/// Battlefield" top right, which steps the browser aside.
struct ArenaBrowserFrame<Content: View, Footer: View>: View {
    @Environment(\.arenaSafeArea) private var safeArea
    let title: String
    var detail: String? = nil
    var source: XmageStackObject? = nil
    var sourceCard: ZoneCard? = nil
    let screen: CGSize
    var identifier = "arena.browser"
    var inspect: (ZoneCard) -> Void = { _ in }
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var peeking = false

    var body: some View {
        let landscape = screen.width > screen.height
        let showsSource = landscape && (source != nil || sourceCard != nil)
        ZStack {
            Color.black.opacity(peeking ? 0 : 0.8).ignoresSafeArea()
                .allowsHitTesting(!peeking)
                .accessibilityHidden(true)
            VStack(spacing: landscape ? 8 : 12) {
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: landscape ? 22 : 24, weight: .bold, design: .serif))
                        .foregroundStyle(ArenaGlass.text)
                        .shadow(color: .black, radius: 2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("\(identifier).title")
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(ArenaMenuStyle.font(13, .medium))
                            .foregroundStyle(ArenaGlass.text.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)
                content.frame(maxHeight: .infinity)
                footer
            }
            .padding(.top, safeArea.top(landscape ? 50 : 96))
            .padding(.horizontal, landscape ? safeArea.side : 0)
            .padding(.bottom, landscape ? 10 : 28)
            .padding(.trailing, showsSource ? 150 : 0)
            .opacity(peeking ? 0 : 1)
            .allowsHitTesting(!peeking)
            if showsSource && !peeking {
                sourceView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            Button(peeking ? "Back to the choice" : "View Battlefield") { peeking.toggle() }
                .font(ArenaMenuStyle.font(12, .bold))
                .foregroundStyle(ArenaGlass.text)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .frame(minHeight: 44)
                .accessibilityIdentifier("\(identifier).viewBattlefield")
                // Clear of the gear (top right in landscape): padded before it is placed, so it never widens the layer.
                .padding(.top, landscape ? 4 : 50)
                .padding(.trailing, landscape ? 120 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var sourceView: some View {
        let size = CGSize(width: 124, height: 172)
        Group {
            if let source, ArenaStackCard.isAbility(source) || source.displaySourceCard == nil {
                ArenaAbilityCard(source: source.displaySourceCard, name: source.displaySourceCard == nil ? source.displayName : nil,
                                 text: source.rulesText ?? source.displayName, size: size)
            } else if let card = source?.displaySourceCard ?? sourceCard {
                CardTile(card: card, selected: false, zoneName: "Stack", width: size.width, height: size.height, imageVariant: .inspection)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { if let card = source?.displaySourceCard ?? sourceCard { inspect(card) } }
    }
}

/// Plaques under a browser: XMage's own answers (Cancel, Done) beside the browser's main one.
struct ArenaAnswerRow: View {
    var answers: [(id: String, title: String, action: () -> Void)] = []
    var primary: (title: String, subtitle: String?, enabled: Bool, action: () -> Void)? = nil
    var pending = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(answers, id: \.id) { answer in
                Button(answer.title, action: answer.action)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 15))
                    .frame(width: 140, height: 40)
                    .disabled(pending)
            }
            if let primary {
                Button(action: primary.action) {
                    VStack(spacing: 0) {
                        Text(primary.title)
                        if let subtitle = primary.subtitle {
                            Text(subtitle.uppercased()).font(ArenaMenuStyle.font(8, .heavy)).opacity(0.85)
                        }
                    }
                }
                .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 16))
                .frame(width: 170, height: 42)
                .disabled(!primary.enabled || pending)
                .accessibilityIdentifier("arena.browser.primary")
            }
            if pending { ProgressView().tint(ArenaGlass.text) }
        }
    }
}

/// A zone opened from the table, the Arena way (Caleb, 2026-10-21: the command zone and Revealed panels were the Hearth
/// board's): graveyard, exile, the command zone, revealed or looked-at cards side by side on the dimmed table, an ember
/// plaque under each card you can use (Cast, or the action's own name), Done to close. Hold a card to read it. Sends the
/// same actions as the Hearth board's zone panel (CompactZoneInspectorOverlay).
struct ArenaZoneBrowser: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let pendingActionId: String?
    let screen: CGSize
    var targetableIDs: Set<String> = []
    var runTargetAction: ((ZoneCard) -> Void)? = nil
    @Binding var inspectedCard: ZoneCard?
    let runAction: (LegalAction) -> Void
    let close: () -> Void

    private var landscape: Bool { screen.width > screen.height }
    private var cardSize: CGSize {
        let height = landscape ? min(220, screen.height * 0.5) : min(200, (screen.width - 56) / 3 * 1.4)
        return CGSize(width: height / 1.4, height: height)
    }

    private func actions(_ card: ZoneCard) -> [LegalAction] { GameBoardInteractionState.cardActions(for: card, actions: legalActions) }
    private func targetable(_ card: ZoneCard) -> Bool {
        runTargetAction != nil && (targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id))
    }

    /// Only what the table can't show: an empty zone, or that a card is wanted. No how-to lines (Caleb, 2026-10-22).
    private var detail: String? {
        if cards.isEmpty { return title.contains("Library") ? "Face down" : "No cards" }
        return cards.contains(where: targetable) ? "Choose a card" : nil
    }

    private func perform(_ action: LegalAction) {
        guard pendingActionId == nil, legalActions.contains(where: { $0.id == action.id }) else { return }
        if GameplayAffordances.dismissesZone(action: action) {
            inspectedCard = nil
            close()
        }
        runAction(action)
    }

    var body: some View {
        ArenaBrowserFrame(title: title, detail: detail, screen: screen, identifier: "arena.zone", inspect: { inspectedCard = $0 }) {
            if cards.isEmpty {
                Spacer(minLength: 0)
            } else if landscape {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) { ForEach(cards) { tile($0) } }
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .frame(minWidth: screen.width - 48)
                }
            } else {
                // As many columns as cards, up to three, centred on the table; it scrolls only when they don't fit, so one
                // card sits in the middle with its plaque under it, as in Arena's browsers (Caleb, 2026-10-22).
                let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardSize.width), spacing: 12, alignment: .top),
                                                    count: min(3, cards.count)), spacing: 14) {
                    ForEach(cards) { tile($0) }
                }
                .padding(.vertical, 12)
                ViewThatFits(in: .vertical) {
                    grid.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ScrollView(showsIndicators: false) { grid.frame(maxWidth: .infinity) }
                }
            }
        } footer: {
            // Done always closes, even while an answer is on its way (the Hearth panel's close never waited either).
            ArenaAnswerRow(primary: (title: "Done", subtitle: nil, enabled: true, action: close))
        }
    }

    private func tile(_ card: ZoneCard) -> some View {
        let cardActions = actions(card)
        let target = targetable(card)
        return VStack(spacing: 8) {
            CardTile(card: card, selected: false, zoneName: "Zone", width: cardSize.width, height: cardSize.height,
                     ignoreTappedRotation: true, imageVariant: .inspection)
                .background {
                    if target || !cardActions.isEmpty {
                        ArenaOutlineGlow(outline: .card, tone: target ? .target : .playable, breathes: !target)
                    }
                }
                .onCardInteraction(tap: { inspectedCard = card }, inspect: { inspectedCard = card },
                                   release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                .accessibilityLabel(card.card.name)
            if target {
                Button("Choose") { if pendingActionId == nil { runTargetAction?(card) } }
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 14))
                    .frame(width: cardSize.width, height: 36)
                    .disabled(pendingActionId != nil)
                    .accessibilityLabel("Choose \(card.card.name)")
            }
            ForEach(cardActions.prefix(3)) { action in
                Button(cardActions.count == 1 && action.type == "cast_spell" ? "Cast" : action.displayLabel) { perform(action) }
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .primary, fontSize: 14))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: cardSize.width, height: 36)
                    .disabled(pendingActionId != nil)
                    .accessibilityLabel("\(action.displayLabel), \(card.card.name)")
                    .accessibilityIdentifier("arena.zone.action.\(action.id)")
            }
        }
        .frame(width: cardSize.width)
    }
}

/// A player's card on the Arena table, opened from their medallion (Caleb, 2026-10-21: the medallion's menu was a
/// list of Hearth plaques and ran off the screen): their name, life and counters and the commander damage they took,
/// then one icon per zone that holds cards (the command zone while they have a commander, lit when you can cast from
/// it), exile zones by their full names, and in a pod the other opponents to swap to. A tap opens that zone's browser.
struct ArenaPlayerCard: View {
    let player: PlayerGameState
    let snapshot: GameSnapshot
    let pendingActionID: String?
    var opponents: [PlayerGameState] = []
    var swap: ((String) -> Void)? = nil
    let open: (BoardZoneReference) -> Void
    let close: () -> Void
    @Environment(\.voiceRoom) private var voiceRoom

    private struct ZoneIcon: Identifiable {
        let zone: BoardZoneReference.PlayerZone
        let name: String
        let symbol: String
        let count: Int
        let lit: Bool
        var id: String { zone.rawValue }
    }

    private var zones: [ZoneIcon] {
        let viewer = snapshot.isViewer(player.playerId)
        let castable = viewer ? GameplayAffordances.castableZones(player: player, snapshot: snapshot, pendingActionID: pendingActionID) : []
        let commanderReady = viewer && GameplayAffordances.commanderCastAvailable(player: player, snapshot: snapshot, pendingActionID: pendingActionID)
        let zones = player.zones
        var icons: [ZoneIcon] = []
        if !zones.command.isEmpty || !(player.commanders ?? []).isEmpty {
            icons.append(ZoneIcon(zone: .command, name: "Command", symbol: "crown.fill", count: zones.command.count, lit: commanderReady))
        }
        icons.append(ZoneIcon(zone: .graveyard, name: "Graveyard", symbol: "leaf.fill", count: zones.graveyard.count, lit: castable.contains(.graveyard)))
        icons.append(ZoneIcon(zone: .exile, name: "Exile", symbol: "sparkles", count: zones.exile.count, lit: castable.contains(.exile)))
        icons.append(ZoneIcon(zone: .library, name: "Library", symbol: "books.vertical.fill", count: zones.visibleLibraryCount, lit: castable.contains(.library)))
        if !viewer { icons.append(ZoneIcon(zone: .hand, name: "Hand", symbol: "hand.raised.fill", count: zones.visibleHandCount, lit: false)) }
        // Only zones with something in them, and the library (always worth its count).
        return icons.filter { $0.count > 0 || $0.zone == .command || $0.zone == .library }
    }

    var body: some View {
        // A long list of exile zones scrolls inside the card instead of pushing it off the screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) { content }
        }
        .frame(width: 300)
        .modifier(ArenaGlassPanel(cornerRadius: 18, opacity: 0.96))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arena.playerCard")
    }

    private var content: some View {
        let name = snapshot.playerLabel(player.playerId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlayerPortrait(player: player, size: 44)
                    .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(ArenaGlass.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(player.isOut ? "Out of the game" : "\(player.life) life")
                        .font(ArenaMenuStyle.font(13, .heavy))
                        .foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.52))
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .black)).foregroundStyle(ArenaGlass.text.opacity(0.8))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(name)'s card")
            }
            if let voiceRoom, !snapshot.isViewer(player.playerId), let seat = voiceRoom.seat(named: player.displayName) {
                ArenaVoiceSilenceButton(room: voiceRoom, seat: seat)
            }
            let summary = PlayerStatusSummary(player: player, snapshot: snapshot)
            if !summary.orbit.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.orbit) { badge in
                        HStack(spacing: 10) {
                            TavernStatusBadge(badge: badge, size: 26).frame(width: 30, height: 30).accessibilityHidden(true)
                            Text(badge.label)
                                .font(ArenaMenuStyle.font(13, .semibold))
                                .foregroundStyle(badge.nearLethal ? Color(red: 1, green: 0.62, blue: 0.52) : ArenaGlass.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(badge.label)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(zones) { icon in
                    Button { open(.player(playerID: player.playerId, zone: icon.zone)) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: icon.symbol).font(.system(size: 17, weight: .bold))
                            Text("\(icon.count)").font(ArenaMenuStyle.font(13, .heavy)).monospacedDigit()
                            Text(icon.name.uppercased()).font(ArenaMenuStyle.font(8, .heavy)).tracking(0.8)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(icon.lit ? Color(red: 1, green: 0.9, blue: 0.7) : ArenaGlass.text)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .modifier(ArenaGlassRow(primary: icon.lit))
                        .background { if icon.lit { ArenaOutlineGlow(outline: .card, tone: .playable, breathes: true) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon.lit ? "\(icon.name), \(icon.count), you can play from it" : "\(icon.name), \(icon.count)")
                    .accessibilityIdentifier("arena.player.zone.\(icon.zone.rawValue)")
                }
            }
            let named = BoardZoneReference.namedReferences(in: snapshot)
            if !named.isEmpty {
                VStack(spacing: 6) {
                    ForEach(named, id: \.self) { reference in
                        Button { open(reference) } label: {
                            HStack {
                                Text(reference.title(in: snapshot))
                                    .font(ArenaMenuStyle.font(13, .semibold))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 6)
                                Text("\(reference.cards(in: snapshot).count)")
                                    .font(ArenaMenuStyle.font(13, .heavy)).monospacedDigit()
                            }
                            .foregroundStyle(ArenaGlass.text)
                            .padding(.horizontal, 12).frame(minHeight: 40)
                            .modifier(ArenaGlassRow())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if opponents.count > 1, let swap {
                TavernOpponentSwap(opponents: opponents, current: player.playerId,
                                   label: { snapshot.playerLabel($0) }, select: swap,
                                   withChoices: Set(ArenaTargetReach.of(snapshot, targetable: GameBoardInteractionState.boardTargetableIds(for: snapshot)).hiddenOpponents))
            }
        }
        .padding(14)
    }
}

/// A list of named choices the Arena way (Caleb, 2026-10-20): replacement effects and other choices that name a card
/// show that card with the choice's text; colours show their mana symbol; anything else is a glass tile, with a search
/// field for long lists. XMage's "Remember answer" twins become one "Remember my choice" toggle.
struct ArenaChoiceBrowser: View {
    struct Option: Identifiable {
        let id: String
        let rememberID: String?
        let label: String
        let text: String
        let card: ZoneCard?
        let symbol: String?
    }

    let title: String
    var detail: String? = nil
    let options: [Option]
    var source: XmageStackObject? = nil
    let pending: Bool
    let screen: CGSize
    var answers: [(id: String, title: String, action: () -> Void)] = []
    let choose: (Option, Bool) -> Void
    let inspect: (ZoneCard) -> Void
    @State private var remember = false
    @State private var search = ""

    private var asCards: Bool { options.contains { $0.card != nil } && options.count <= 8 }
    private var asSymbols: Bool { !asCards && options.allSatisfy { $0.symbol != nil } }
    private var shown: [Option] {
        guard !search.isEmpty else { return options }
        return options.filter { $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let landscape = screen.width > screen.height
        ArenaBrowserFrame(title: title, detail: detail, source: source, screen: screen, identifier: "arena.choiceBrowser", inspect: inspect) {
            VStack(spacing: 10) {
                if options.count > 12 && !asCards {
                    TextField("Search choices", text: $search)
                        .modifier(TavernFieldChrome(tavern: true))
                        .frame(maxWidth: 360)
                        .accessibilityIdentifier("arena.choice.search")
                }
                if asCards {
                    let height = min(landscape ? screen.height * 0.5 : 250, 250)
                    let size = CGSize(width: height * 0.72, height: height)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(shown) { option in
                                ArenaAbilityCard(source: option.card, name: option.card == nil ? (option.label.count < 30 ? option.label : "Choice") : nil,
                                                 kind: option.card == nil ? "Choice" : "Effect", text: option.text, size: size)
                                    .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
                                    .contentShape(Rectangle())
                                    .onTapGesture { pick(option) }
                                    .onLongPressGesture(minimumDuration: 0.35) { if let card = option.card { inspect(card) } }
                                    .modifier(ArenaChoiceAccessibility(option: option))
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 16)
                        .frame(minWidth: screen.width - (landscape && source != nil ? 150 : 0))
                    }
                } else if asSymbols {
                    HStack(spacing: 18) {
                        ForEach(shown) { option in
                            Button { pick(option) } label: {
                                VStack(spacing: 6) {
                                    ManaSymbolView(symbol: option.symbol ?? "C", size: 54)
                                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                                    Text(option.label).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaGlass.text)
                                }
                                .frame(minWidth: 64, minHeight: 88)
                            }
                            .buttonStyle(.plain)
                            .modifier(ArenaChoiceAccessibility(option: option))
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: landscape ? 170 : 150), spacing: 10)], spacing: 10) {
                            ForEach(shown) { option in
                                Button { pick(option) } label: {
                                    GameRulesText(source: PromptDisplayText.clean(option.label), symbolSize: 14)
                                        .font(ArenaMenuStyle.font(14, .semibold))
                                        .foregroundStyle(ArenaGlass.text)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .padding(.horizontal, 10)
                                        .modifier(ArenaGlassRow())
                                }
                                .buttonStyle(.plain)
                                .modifier(ArenaChoiceAccessibility(option: option))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                if options.contains(where: { $0.rememberID != nil }) {
                    RememberChoiceToggle(title: "Remember my choice for this game", isOn: $remember)
                        .frame(maxWidth: 420)
                }
            }
        } footer: {
            ArenaAnswerRow(answers: answers, pending: pending)
        }
        .disabled(pending)
    }

    private func pick(_ option: Option) {
        guard !pending else { return }
        GameHaptics.selection()
        choose(option, remember && option.rememberID != nil)
    }
}

private struct ArenaChoiceAccessibility: ViewModifier {
    let option: ArenaChoiceBrowser.Option
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PromptDisplayText.clean(option.label))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("arena.choice.\(option.id)")
    }
}

/// Choosing a player the Arena way (who goes first, which player): each player's medallion, their name and life under
/// it, side by side over the dimmed table; a tap chooses.
struct ArenaPlayerChoice: View {
    struct Seat: Identifiable {
        /// The id the answer sends.
        let id: String
        let player: PlayerGameState?
        let name: String
    }

    let title: String
    var detail: String? = nil
    let seats: [Seat]
    let pending: Bool
    let screen: CGSize
    var answers: [(id: String, title: String, action: () -> Void)] = []
    let choose: (Seat) -> Void

    var body: some View {
        let diameter: CGFloat = min(screen.width, screen.height) * (seats.count > 2 ? 0.24 : 0.3)
        // Upright, three or four players sit two to a row so none is cut off at the edge (the judge, 2026-10-22).
        let columns = screen.width > screen.height || seats.count <= 2 ? seats.count : 2
        ArenaBrowserFrame(title: title, detail: detail, screen: screen, identifier: "arena.playerChoice") {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(diameter * 1.25), spacing: diameter * 0.3), count: max(1, columns)),
                      spacing: diameter * 0.3) {
                ForEach(seats) { seat in
                    Button {
                        guard !pending else { return }
                        GameHaptics.selection()
                        choose(seat)
                    } label: {
                        VStack(spacing: 10) {
                            if let player = seat.player {
                                ArenaHeroMedallion(player: player, diameter: diameter)
                            } else {
                                Circle().fill(Color.white.opacity(0.08)).frame(width: diameter, height: diameter)
                                    .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 2))
                            }
                            Text(seat.name)
                                .font(ArenaMenuStyle.title(18, .bold))
                                .foregroundStyle(ArenaGlass.text)
                                .shadow(color: .black, radius: 2)
                                .padding(.top, diameter * 0.1)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(seat.name)
                    .accessibilityIdentifier("arena.player.\(seat.id)")
                }
            }
            .frame(maxHeight: .infinity)
        } footer: {
            ArenaAnswerRow(answers: answers, pending: pending)
        }
    }
}

/// The reference's number picker (MTG Arena's "Pay X = 10"): one capsule in the button corner, [−5] [−] [answer] [+]
/// [+5], Cancel under it. Holding − or + keeps stepping. The board stays in view, the spell on the stack.
struct ArenaAmountPill: View {
    let label: String
    let range: ArenaAmountRange
    let initial: Int
    let pending: Bool
    let submit: (Int) -> Void
    /// XMage's way back (Cancel), under the pill.
    var cancel: (title: String, action: () -> Void)? = nil
    @State private var value: Int?

    var body: some View {
        let current = value ?? range.clamp(initial)
        VStack(spacing: 10) {
            HStack(spacing: -6) {
                if range.values.count > 6 { lens("−5", places: -5, current: current, wide: false) }
                lens("−", places: -1, current: current, wide: false)
                Button { submit(current) } label: {
                    VStack(spacing: -1) {
                        Text(label).font(ArenaMenuStyle.font(12, .bold))
                        Text(label.hasSuffix("X") ? "X = \(current)" : "\(current)")
                            .font(.system(size: 18, weight: .heavy, design: .serif)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(current)))
                    }
                    .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.75))
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .frame(width: 112, height: 50)
                    .background { Capsule().fill(ArenaMenuStyle.orange) }
                    .overlay(Capsule().strokeBorder(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.9), lineWidth: 1.2))
                    .shadow(color: TavernPalette.ember.opacity(0.7), radius: 8)
                }
                .buttonStyle(.plain)
                .zIndex(1)
                .disabled(pending)
                .accessibilityLabel("\(label) \(current)")
                .accessibilityHint("Locks in the value")
                .accessibilityIdentifier("arena.amount.submit")
                lens("+", places: 1, current: current, wide: false)
                if range.values.count > 6 { lens("+5", places: 5, current: current, wide: false) }
            }
            if let cancel {
                Button(cancel.title, action: cancel.action)
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 15))
                    .frame(width: 150, height: 38)
                    .disabled(pending)
                    .accessibilityIdentifier("arena.amount.cancel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arena.amount")
    }

    private func lens(_ title: String, places: Int, current: Int, wide: Bool) -> some View {
        let blocked = places < 0 ? current <= range.minimum : current >= range.maximum
        return ArenaRepeatButton(repeats: abs(places) == 1) {
            let now = value ?? range.clamp(initial)
            let next = range.step(now, by: places)
            guard next != now else { return false }
            value = next
            GameHaptics.selection()
            return true
        } label: {
            Text(title)
                .font(.system(size: abs(places) == 1 ? 22 : 15, weight: .heavy, design: .serif))
                .foregroundStyle(ArenaGlass.text.opacity(blocked ? 0.35 : 1))
                .frame(width: abs(places) == 1 ? 48 : 42, height: 42)
                .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        }
        .disabled(blocked || pending)
        .accessibilityLabel(places < 0 ? "Lower by \(abs(places))" : "Raise by \(places)")
        .accessibilityIdentifier("arena.amount.\(places)")
    }
}

/// A button that keeps acting while it is held (after a short wait), like the reference's − and +.
struct ArenaRepeatButton<Label: View>: View {
    var repeats = true
    /// Takes one step; false when it can't go further, which also stops a held repeat.
    let action: () -> Bool
    @ViewBuilder let label: Label
    /// Resets by itself when the touch ends or is taken away (a scroll view, the view going), so a repeat always stops.
    @GestureState private var pressed = false
    @State private var task: Task<Void, Never>?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.94 : 1)
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
            .onChange(of: pressed) { _, down in
                task?.cancel()
                task = nil
                guard down, isEnabled, action(), repeats else { return }
                task = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    while !Task.isCancelled, action() {
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                }
            }
            .onDisappear { task?.cancel(); task = nil }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { _ = action() } }
    }
}

/// Splitting damage, counters or mana the Arena way: each blocker or target as its card (a player as their medallion,
/// a colour as its symbol) with a big number on it and − / + under it, lethal marked; what's left to give at the
/// bottom, Done only when the split is legal. XMage's own split comes in filled (lethal damage first).
struct ArenaSplitBrowser: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        let card: ZoneCard?
        let player: PlayerGameState?
        let symbol: String?
        let minimum: Int
        let maximum: Int
        let initial: Int
        let lethal: Int?
    }

    let title: String
    let rows: [Row]
    let slots: [XmagePromptMultiAmount]
    let totalMin: Int?
    let totalMax: Int?
    var source: XmageStackObject? = nil
    var sourceCard: ZoneCard? = nil
    let pending: Bool
    let screen: CGSize
    var answers: [(id: String, title: String, action: () -> Void)] = []
    let submit: ([Int]) -> Void
    let inspect: (ZoneCard) -> Void
    @State private var values: [Int]?

    private var current: [Int] { values ?? rows.map(\.initial) }
    private var total: Int { current.reduce(0, +) }
    private var valid: Bool { PromptCommandBuilder.isValidMultiAmountValues(current, slots: slots, totalMin: totalMin, totalMax: totalMax) }

    private var detail: String {
        if let totalMax, totalMax == totalMin ?? totalMax {
            let left = totalMax - total
            return left == 0 ? "All \(totalMax) given out" : left > 0 ? "\(left) of \(totalMax) left to give" : "\(-left) too many"
        }
        return "\(total) given"
    }

    var body: some View {
        let landscape = screen.width > screen.height
        // Portrait: up to three across, wrapping; landscape: one row.
        let columns = landscape ? rows.count : min(3, max(rows.count, 1))
        let fitted = landscape ? 210 : ((screen.width - 48 - CGFloat(columns - 1) * 14) / CGFloat(columns)) / 0.72
        let height = min(landscape ? screen.height * 0.42 : fitted, 210)
        let size = CGSize(width: height * 0.72, height: height)
        ArenaBrowserFrame(title: title, detail: detail, source: source, sourceCard: sourceCard, screen: screen,
                          identifier: "arena.split", inspect: inspect) {
            if landscape {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            column(row, index: index, size: size)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .frame(minWidth: screen.width - ((source != nil || sourceCard != nil) ? 150 : 0))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(size.width), spacing: 14), count: columns), spacing: 18) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            column(row, index: index, size: size)
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Button("Reset") { values = nil }
                    .buttonStyle(ArenaPlaqueButtonStyle(kind: .secondary, fontSize: 15))
                    .frame(width: 110, height: 40)
                    .disabled(values == nil || pending)
                ArenaAnswerRow(answers: answers, primary: ("Done", nil, valid, { submit(current) }), pending: pending)
            }
        }
    }

    private func column(_ row: Row, index: Int, size: CGSize) -> some View {
        let value = current[index]
        let lethal = row.lethal.map { value >= $0 } ?? false
        let name = row.card?.card.name ?? ArenaSplit.name(of: row.label)
        return VStack(spacing: 8) {
            face(row, size: size)
                .overlay(alignment: .center) { badge(value, lethal: lethal) }
                .overlay(alignment: .topTrailing) { if lethal { skull } }
                .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.3) { if let card = row.card { inspect(card) } }
            Text(name)
                .font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(ArenaGlass.text)
                .lineLimit(1).frame(width: size.width)
            HStack(spacing: 10) {
                stepper("−", by: -1, index: index, row: row)
                stepper("+", by: 1, index: index, row: row)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name): \(value)\(lethal ? ", lethal" : "")")
        .accessibilityIdentifier("arena.split.\(row.id)")
    }

    @ViewBuilder
    private func face(_ row: Row, size: CGSize) -> some View {
        if let card = row.card {
            CardTile(card: card, selected: false, zoneName: "Split", width: size.width, height: size.height, imageVariant: .inspection)
                .allowsHitTesting(false)
        } else if let player = row.player {
            ArenaHeroMedallion(player: player, diameter: size.width * 0.9)
                .frame(width: size.width, height: size.height)
        } else if let symbol = row.symbol {
            ManaSymbolView(symbol: symbol, size: size.width * 0.6)
                .frame(width: size.width, height: size.height * 0.7)
        } else {
            ArenaAbilityCard(source: nil, name: ArenaSplit.name(of: row.label), kind: "Target", text: row.label, size: size)
        }
    }

    private static let blood = Color(red: 0.55, green: 0.06, blue: 0.05)

    private func badge(_ value: Int, lethal: Bool) -> some View {
        let fill: Color = lethal ? Self.blood.opacity(0.92) : Color.black.opacity(0.6)
        let rim: AnyShapeStyle = lethal ? AnyShapeStyle(Color(red: 1, green: 0.45, blue: 0.3)) : AnyShapeStyle(ArenaGlass.hairline)
        return Text("\(value)")
            .font(.system(size: 34, weight: .heavy, design: .serif))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 3)
            .frame(width: 62, height: 62)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(rim, lineWidth: 2))
            .opacity(value == 0 && !lethal ? 0.75 : 1)
    }

    private var skull: some View {
        Image(systemName: "skull.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(Self.blood))
            .offset(x: 6, y: -6)
            .accessibilityHidden(true)
    }

    private func stepper(_ title: String, by delta: Int, index: Int, row: Row) -> some View {
        let value = current[index]
        let blocked = delta < 0 ? value <= row.minimum : value >= row.maximum || (totalMax.map { total >= $0 } ?? false)
        return ArenaRepeatButton {
            var next = current
            // Never past the row's limits, nor more than the total to give.
            if delta > 0, let totalMax, next.reduce(0, +) >= totalMax { return false }
            let proposed = min(max(next[index] + delta, row.minimum), row.maximum)
            guard proposed != next[index] else { return false }
            next[index] = proposed
            values = next
            GameHaptics.selection()
            return true
        } label: {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .serif))
                .foregroundStyle(ArenaGlass.text.opacity(blocked ? 0.35 : 1))
                .frame(width: 50, height: 40)
                .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        }
        .disabled(blocked || pending)
        .accessibilityLabel(delta < 0 ? "One less to \(ArenaSplit.name(of: row.label))" : "One more to \(ArenaSplit.name(of: row.label))")
        .accessibilityIdentifier("arena.split.\(row.id).\(delta < 0 ? "minus" : "plus")")
    }
}

/// Choosing a pile the Arena way (Fact or Fiction, Liliana): the two piles fanned side by side in gold-rimmed wells, a
/// tap picks one, the main plaque takes it. Hold a card to read it.
struct ArenaPileBrowser: View {
    let title: String
    var detail: String? = nil
    let piles: [XmagePromptPile]
    var source: XmageStackObject? = nil
    let pending: Bool
    let screen: CGSize
    let choose: (XmagePromptPile) -> Void
    let inspect: (ZoneCard) -> Void
    @State private var picked: String?

    var body: some View {
        let landscape = screen.width > screen.height
        let width: CGFloat = landscape ? 96 : 84
        ArenaBrowserFrame(title: title, detail: detail, source: source, screen: screen, identifier: "arena.pileBrowser", inspect: inspect) {
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 14))
            layout {
                ForEach(piles) { pile in
                    let chosen = picked == pile.id
                    VStack(spacing: 8) {
                        Text("\(pile.label.uppercased()) · \(pile.cards.count == 1 ? "1 CARD" : "\(pile.cards.count) CARDS")")
                            .font(ArenaMenuStyle.font(13, .heavy)).tracking(1.2)
                            .foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.52))
                        HStack(spacing: -width * 0.45) {
                            ForEach(Array(pile.cards.enumerated()), id: \.element.id) { index, card in
                                CardTile(card: card, selected: false, zoneName: pile.label, width: width, height: width * 1.4,
                                         imageVariant: .inspection)
                                    .allowsHitTesting(false)
                                    .rotationEffect(.degrees(Double(index - pile.cards.count / 2) * 4), anchor: .bottom)
                                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                                    .onLongPressGesture(minimumDuration: 0.3) { inspect(card) }
                            }
                            if pile.cards.isEmpty {
                                Text("Empty").font(ArenaMenuStyle.font(14, .regular).italic()).foregroundStyle(ArenaGlass.text.opacity(0.6))
                                    .frame(width: width, height: width * 1.4)
                            }
                        }
                        .padding(14)
                        .frame(minWidth: width * 1.6)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(chosen ? 0.5 : 0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(chosen ? AnyShapeStyle(Color(red: 1, green: 0.82, blue: 0.4))
                                                                             : AnyShapeStyle(ArenaGlass.hairline), lineWidth: chosen ? 3 : 1))
                    .shadow(color: chosen ? Color(red: 1, green: 0.75, blue: 0.3).opacity(0.7) : .clear, radius: 10)
                    .contentShape(Rectangle())
                    .onTapGesture { guard !pending else { return }; picked = pile.id; GameHaptics.selection() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(pile.label): \(pile.cards.map(\.card.name).joined(separator: ", "))")
                    .accessibilityAddTraits(chosen ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
                    .accessibilityIdentifier("arena.pile.\(pile.id)")
                }
            }
        } footer: {
            let pile = piles.first { $0.id == picked }
            ArenaAnswerRow(primary: (pile.map { "Choose \($0.label)" } ?? "Pick a pile", nil, pile != nil, { if let pile { choose(pile) } }),
                           pending: pending)
        }
    }
}

/// The ability card's outline: square shoulders and a gently rounded foot.
struct ArenaAbilityShape: InsettableShape {
    var corner: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = max(0, corner - insetAmount)
        let foot = r.height * 0.1
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX - c, y: r.minY + c), radius: c, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - foot))
        path.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - foot), control: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addArc(center: CGPoint(x: r.minX + c, y: r.minY + c), radius: c, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ArenaAbilityShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// The light arc from the ability on the stack to what it points at (its targets, or its source when it has none).
struct ArenaStackArc: View {
    let from: CGRect
    let to: [CGRect]
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    /// One arc, from the stack card's left edge up and over to the target's middle.
    struct Arc: Shape {
        let start: CGPoint
        let end: CGPoint

        func path(in rect: CGRect) -> Path {
            let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - abs(start.x - end.x) * 0.25 - 30)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            return path
        }
    }

    var body: some View {
        // Shapes, not a Canvas, so the arc draws itself in (a trim animates; a Canvas only jumps to the end).
        ZStack {
            ForEach(Array(to.enumerated()), id: \.offset) { _, target in
                // From the upper part of the card's left edge, clear of the stack tab at its middle.
                let arc = Arc(start: CGPoint(x: from.minX, y: from.minY + from.height * 0.24),
                              end: CGPoint(x: target.midX, y: target.midY)).trim(from: 0, to: drawn)
                arc.stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                arc.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                arc.stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(.easeOut(duration: 0.45)) { drawn = 1 } }
        }
    }
}

/// A spell or ability waiting on the stack marks what it targets, as the reference does: a ring with four ticks over
/// the target that breathes until the spell resolves (Caleb, 2026-10-21: Murder's target couldn't be seen).
struct ArenaTargetReticle: View {
    let rect: CGRect
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let diameter = max(34, min(rect.width, rect.height) * 0.62)
        ZStack {
            Circle().stroke(color.opacity(0.35), lineWidth: 7).blur(radius: 3)
            Circle().stroke(color, lineWidth: 2.2)
            Circle().stroke(.white.opacity(0.8), lineWidth: 0.8).padding(diameter * 0.18)
            ForEach(0..<4, id: \.self) { quarter in
                Capsule().fill(color)
                    .frame(width: 2.6, height: diameter * 0.2)
                    .offset(y: -diameter * 0.5)
                    .rotationEffect(.degrees(Double(quarter) * 90))
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .scaleEffect(shown ? 1 : 1.6)
        .opacity(shown ? 1 : 0)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.35)) { shown = true } }
        }
    }
}

struct ArenaPromptCaption: View {
    let text: String

    var body: some View {
        GameRulesText(source: text, symbolSize: 15)
            .font(ArenaMenuStyle.font(15, .semibold))
            .foregroundStyle(TavernPalette.parchment)
            .shadow(color: .black, radius: 2)
            .shadow(color: .black.opacity(0.8), radius: 6)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .allowsHitTesting(false)
            .accessibilityIdentifier("board.arena.caption")
    }
}

/// Floating mana the reference's way: plain mana symbols by your portrait, one per mana; a symbol takes a tap while
/// you pay (XMage asks for floating mana then).
struct ArenaFloatingMana: View {
    let pool: ManaPool?
    let payable: Set<String>
    let spend: (String) -> Void

    var body: some View {
        let values: [(String, Int)] = [("W", pool?.W ?? 0), ("U", pool?.U ?? 0), ("B", pool?.B ?? 0),
                                       ("R", pool?.R ?? 0), ("G", pool?.G ?? 0), ("C", pool?.C ?? 0)].filter { $0.1 > 0 }
        HStack(spacing: 2) {
            ForEach(values, id: \.0) { symbol, count in
                let symbols = ManaSymbolView(symbol: symbol, size: 20)
                    .shadow(color: .black.opacity(0.75), radius: 1.5, y: 1)
                    .overlay(alignment: .bottomTrailing) {
                        if count > 1 {
                            Text("\(count)").font(ArenaMenuStyle.font(10, .black)).monospacedDigit()
                                .foregroundStyle(.white).padding(.horizontal, 3)
                                .background(Capsule().fill(Color.black.opacity(0.85)))
                                .offset(x: 5, y: 4)
                        }
                    }
                if payable.contains(symbol) {
                    Button { spend(symbol) } label: {
                        symbols.padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(Capsule().strokeBorder(TavernPalette.ember.opacity(0.8), lineWidth: 1.2).frame(height: 24))
                    .accessibilityLabel("Spend floating \(symbol) mana, \(count) available")
                    .accessibilityIdentifier("board.mana.spend.\(symbol)")
                } else {
                    symbols.padding(.horizontal, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(count) floating \(symbol) mana")
                }
            }
        }
        .padding(.horizontal, 5)
        .background(Capsule().fill(Color.black.opacity(0.45)).frame(height: 28))
        .overlay(Capsule().strokeBorder(TavernPalette.brass.opacity(0.55), lineWidth: 1).frame(height: 28))
    }
}


/// The end of a game on the Arena board, as Arena shows it (build_output/arena-game-reference/victory-*.jpg): the board
/// dims and one word lands on a flare of light behind the MagicMobile mark, orange for Victory, cold steel for Defeat,
/// violet for a draw. A tap, or a moment, lifts the word to the top over your medallion, your rank, the game's numbers
/// and the two ways on. View Battlefield lifts it all to look at the final board. No trophy, flag or tavern panel.
struct ArenaGameResultView: View {
    @Environment(\.arenaSafeArea) private var safeArea
    let snapshot: GameSnapshot
    var stats: GameStats?
    var rankChange: RankChange?
    /// Why a ranked win left the ladder alone, once the server says so.
    var rankNote: String?
    var rematchTitle: String?
    let newGame: () -> Void
    let quitGame: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var settled = false
    @State private var peeking = false

    private enum Outcome { case victory, defeat, draw }

    private var outcome: Outcome {
        guard let winners = snapshot.winnerPlayerIds, !winners.isEmpty else { return .draw }
        return winners.contains(snapshot.viewerID) ? .victory : .defeat
    }

    private var word: String {
        switch outcome {
        case .victory: String(localized: "Victory")
        case .defeat: String(localized: "Defeat")
        case .draw: String(localized: "Draw")
        }
    }

    private var flare: Color {
        switch outcome {
        case .victory: Color(red: 1, green: 0.52, blue: 0.14)
        case .defeat: Color(red: 0.46, green: 0.58, blue: 0.74)
        case .draw: Color(red: 0.62, green: 0.40, blue: 0.96)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.opacity(peeking ? 0 : 0.86).ignoresSafeArea()
                    .allowsHitTesting(!peeking)
                if !peeking {
                    VStack(spacing: landscape ? 10 : 18) {
                        banner(landscape: landscape)
                            .padding(.top, settled ? safeArea.top(landscape ? 50 : 104) : max(0, proxy.size.height / 2 - (landscape ? 70 : 90)))
                        if settled {
                            details(landscape: landscape)
                                .transition(.opacity.combined(with: .offset(y: 24)))
                        }
                        Spacer(minLength: 0)
                    }
                    // Held to the screen: the flare is wider and spills off both sides, but it must not widen the layer,
                    // or View Battlefield is laid out past the screen's edge.
                    .frame(width: proxy.size.width)
                    .padding(.horizontal, landscape ? safeArea.side : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { settle() }
                }
                Button(peeking ? String(localized: "Back") : String(localized: "View Battlefield")) {
                    withAnimation(.easeOut(duration: 0.2)) { peeking.toggle() }
                }
                .buttonStyle(ArenaButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("board.result.viewBattlefield")
                .padding(.top, landscape ? 6 : 50)
                .padding(.trailing, landscape ? 120 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { landed = true }
            UINotificationFeedbackGenerator().notificationOccurred(outcome == .victory ? .success : .error)
        }
        .task {
            do { try await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 1.8)) } catch { return }
            settle()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game completed. \(word)")
    }

    private func settle() {
        guard !settled else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85)) { settled = true }
    }

    /// The word on its flare, the mark glowing behind it.
    private func banner(landscape: Bool) -> some View {
        let size: CGFloat = landscape ? (settled ? 40 : 54) : (settled ? 44 : 60)
        return ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [flare.opacity(0.85), flare.opacity(0.25), .clear], center: .center,
                                     startRadius: 0, endRadius: 220))
                .frame(width: 520, height: size * 1.9)
                .blur(radius: 14)
            Capsule()
                .fill(LinearGradient(colors: [.clear, flare, Color.white.opacity(0.9), flare, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 440, height: 2.5)
                .blur(radius: 1.2)
                .offset(y: size * 0.12)
            if let mark = UIImage(named: "LaunchMark") {
                Image(uiImage: mark)
                    .resizable().scaledToFit()
                    .frame(height: size * 1.7)
                    .opacity(0.32)
                    .shadow(color: flare, radius: 18)
                    .blendMode(.plusLighter)
            }
            Text(word.uppercased())
                .font(ArenaMenuStyle.title(size, .bold))
                .tracking(size * 0.06)
                .foregroundStyle(outcome == .defeat ? Color(white: 0.86) : Color.white)
                .shadow(color: flare.opacity(0.9), radius: 14)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
        }
        .scaleEffect(landed || reduceMotion ? 1 : 1.5)
        .opacity(landed || reduceMotion ? 1 : 0)
        .frame(height: size * 2)
    }

    /// Your medallion, the rank you hold after the game, the game's numbers, then Main Menu and the rematch.
    private func details(landscape: Bool) -> some View {
        VStack(spacing: landscape ? 8 : 14) {
            if let viewer = snapshot.human {
                ArenaHeroMedallion(player: viewer, diameter: landscape ? 84 : 120, active: outcome == .victory, showsLife: false)
                    .saturation(outcome == .defeat ? 0.15 : 1)
                    .accessibilityHidden(true)
            }
            if let rankChange {
                HStack(spacing: 10) {
                    RankEmblem(tier: rankChange.after.tier, size: landscape ? 40 : 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rankChange.after.title).font(ArenaMenuStyle.title(20, .bold)).foregroundStyle(ArenaGlass.text)
                        Text(rankLine(rankChange)).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.gold)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let rankNote {
                Text(rankNote).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaGlass.text.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("board.result.rankNote")
            }
            if let stats, stats.turns > 0 {
                HStack(spacing: landscape ? 22 : 28) {
                    figure("\(stats.turns)", String(localized: "Turns"))
                    figure("\(stats.combatDamage)", String(localized: "Damage"))
                    figure("\(stats.creaturesDestroyed)", String(localized: "Destroyed"))
                }
            }
            HStack(spacing: 12) {
                Button(String(localized: "Main Menu"), action: quitGame)
                    .buttonStyle(ArenaButtonStyle(kind: .secondary))
                Button(rematchTitle ?? String(localized: "New Game"), action: newGame)
                    .buttonStyle(ArenaButtonStyle(kind: .primary))
                    .accessibilityIdentifier("board.result.rematch")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(ArenaMenuStyle.title(24, .bold)).monospacedDigit().foregroundStyle(ArenaGlass.text)
            Text(label.uppercased()).font(ArenaMenuStyle.font(10, .heavy)).tracking(1.2).foregroundStyle(ArenaGlass.text.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
    }

    private func rankLine(_ change: RankChange) -> String {
        switch change.kind {
        case .tierUp: String(localized: "Promoted")
        case .tierDown: String(localized: "Demoted")
        case .divisionUp: String(localized: "Division up")
        case .divisionDown: String(localized: "Division down")
        case .pipUp: String(localized: "+\(change.pipDelta) pip")
        case .pipDown: String(localized: "\(change.pipDelta) pip")
        case .none: String(localized: "Ranked")
        }
    }
}
