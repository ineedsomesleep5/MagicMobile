import SwiftUI

/// Persisted identifiers are shared with Android. Walnut Tavern is the only table players get
/// (2026-10-11). `arena` is the classic board layout on a plain dark gradient, kept for the UI tests
/// that pin it; the old moss, wood, ember, tide and stone textures were removed on 2026-10-14, and
/// their stored values fall back to the tavern.
enum BattlefieldBackdrop: String, CaseIterable, Identifiable {
    case arena, tavern

    var id: String { rawValue }
    /// A composed table rendered for each orientation (scripts/brand/tavern_table.py): its
    /// frame and play mat are placed for the board layout, so it cannot share one crop.
    var composedAssetNames: (portrait: String, landscape: String)? {
        self == .tavern ? ("battlefield-tavern-portrait", "battlefield-tavern-landscape") : nil
    }
    /// The iPad plate (tavern_layout.json "pad"), when this theme has one.
    var padImageName: String? {
        self == .tavern ? "battlefield-tavern-pad" : nil
    }
    /// Composed art carries its own lamp and vignette; the generic shading would muddy it.
    var hasBakedLighting: Bool { composedAssetNames != nil }
    static func resolved(_ value: String) -> Self { Self(rawValue: value) ?? .tavern }
}

/// Composed tables pick the render made for the orientation; the classic board draws a plain
/// gradient. The actual board owns card placement and readable overlays.
struct BattlefieldBackdropArt: View {
    let theme: BattlefieldBackdrop

    var body: some View {
        if let composed = theme.composedAssetNames {
            GeometryReader { proxy in
                if proxy.size.isTavernPad, let pad = theme.padImageName, UIImage(named: pad) != nil {
                    // The iPad plate stretches to the screen the way its sockets do, so the painted
                    // rings sit exactly under the live controls on every iPad.
                    Image(pad).resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Image(proxy.size.height >= proxy.size.width ? composed.portrait : composed.landscape)
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        } else {
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.085, blue: 0.10), Color(red: 0.10, green: 0.16, blue: 0.16)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// The table a game is played on. Every game draws one from its match ID, so a resumed game keeps its table and two phones
/// in one match agree. Only Quick Match's Advanced and a Custom Table can choose instead: that pick is pinned to the match.
enum ArenaTableDraw {
    static let random = "random"
    /// What those two screens show, remembered between games.
    static let pickKey = "magicmobile.arenaTablePick"
    /// The match the pinned table belongs to. Left empty, the pin holds for every game, which fixtures and screenshots use.
    static let pinnedMatchKey = "magicmobile.arenaTableMatch"

    static func table(match: String?, pinned: String, pinnedMatch: String) -> ArenaTableTheme {
        if pinnedMatch.isEmpty || pinnedMatch == match, let table = ArenaTableTheme(rawValue: pinned) { return table }
        guard let match else { return .walnut }
        // FNV-1a, because Swift's own hash changes with every launch.
        let hash = match.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        return ArenaTableTheme.allCases[Int(hash % UInt64(ArenaTableTheme.allCases.count))]
    }
}

/// The Arena board's table themes (docs/ARENA_STYLE.md "Table worlds"): a theme holds the plate, its light and how cards
/// sit in that light; the Arena UI stays the same on every table. Stored values will be shared with Android and the web.
enum ArenaTableTheme: String, CaseIterable, Identifiable {
    case walnut
    case radioNight = "radio-night"
    case utopia
    case halloween
    case volcano

    struct CardShadow: Equatable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .walnut: "Walnut"
        case .radioNight: "Radio Night"
        case .utopia: "Utopia"
        case .halloween: "Halloween"
        case .volcano: "Volcano"
        }
    }

    /// The table pinned to a match (ArenaTableDraw.pinnedMatchKey).
    static let key = "magicmobile.arenaTable"
    static let defaultValue = ArenaTableDraw.random

    func plate(landscape: Bool) -> String {
        let name = self == .walnut ? "tavern-arena" : "arena-world-\(rawValue)"
        return "\(name)-\(landscape ? "landscape" : "portrait")"
    }

    /// The table's own air (scripts/audio/build_world_ambience.py). The tavern has its music.
    var ambience: String? { self == .walnut ? nil : "world-\(rawValue)" }

    /// The warm lamp drawn over the walnut mat. A world's lamps are in its plate.
    var hasTableLamp: Bool { self == .walnut }
    /// A pale table: thin light controls drawn straight on it need dark glass behind them.
    var isBright: Bool { self == .utopia }

    /// The table's light on a card lying on it, and on a tapped one.
    var cardLight: Color {
        switch self {
        case .walnut: .white
        case .radioNight: Color(red: 0.95, green: 0.93, blue: 1)
        case .utopia: Color(red: 1, green: 0.985, blue: 0.95)
        case .halloween: Color(red: 0.97, green: 0.93, blue: 0.95)
        case .volcano: Color(red: 1, green: 0.96, blue: 0.92)
        }
    }
    var tappedLight: Color {
        switch self {
        case .walnut: Color(white: 0.64)
        case .radioNight: Color(red: 0.6, green: 0.58, blue: 0.68)
        case .utopia: Color(red: 0.7, green: 0.67, blue: 0.62)
        case .halloween: Color(red: 0.6, green: 0.56, blue: 0.62)
        case .volcano: Color(red: 0.66, green: 0.58, blue: 0.54)
        }
    }

    /// Each world's sun or moon is behind the player (arena_worlds/*.json), so shadows fall away up the table.
    var cardShadow: CardShadow? {
        switch self {
        case .walnut: nil
        case .radioNight: CardShadow(color: Color(red: 0.03, green: 0.02, blue: 0.07).opacity(0.85), radius: 5, x: 1.5, y: -3)
        case .utopia: CardShadow(color: Color(red: 0.36, green: 0.22, blue: 0.1).opacity(0.42), radius: 4, x: 0.5, y: -2.5)
        case .halloween: CardShadow(color: Color(red: 0.04, green: 0.02, blue: 0.05).opacity(0.85), radius: 5, x: 1, y: -3)
        case .volcano: CardShadow(color: Color(red: 0.05, green: 0.015, blue: 0.01).opacity(0.85), radius: 5, x: 0, y: -2.5)
        }
    }
    var pileShadow: Color {
        switch self {
        case .walnut: .black.opacity(0.55)
        case .radioNight: Color(red: 0.03, green: 0.02, blue: 0.07).opacity(0.72)
        case .utopia: Color(red: 0.36, green: 0.22, blue: 0.1).opacity(0.42)
        case .halloween: Color(red: 0.04, green: 0.02, blue: 0.05).opacity(0.72)
        case .volcano: Color(red: 0.05, green: 0.015, blue: 0.01).opacity(0.72)
        }
    }
}

struct GameBoardTheme {
    // Foundations
    let backgroundShadow = Color(red: 0.04, green: 0.03, blue: 0.02)
    let charredOak = Color(red: 0.08, green: 0.045, blue: 0.025)
    let oak = Color(red: 0.18, green: 0.10, blue: 0.05)
    let oakHighlight = Color(red: 0.28, green: 0.16, blue: 0.08)
    let leatherDark = Color(red: 0.045, green: 0.055, blue: 0.075)
    let leatherMid = Color(red: 0.13, green: 0.15, blue: 0.18)
    let carvedWood = Color(red: 0.29, green: 0.17, blue: 0.09)
    let agedParchment = Color(red: 0.72, green: 0.58, blue: 0.37)
    let parchmentLight = Color(red: 0.91, green: 0.84, blue: 0.68)
    let parchmentInk = Color(red: 0.14, green: 0.09, blue: 0.055)
    let antiqueGold = Color(red: 0.84, green: 0.65, blue: 0.25)
    let brass = Color(red: 0.66, green: 0.47, blue: 0.17)
    let brassShadow = Color(red: 0.31, green: 0.20, blue: 0.07)
    let iron = Color(red: 0.055, green: 0.065, blue: 0.085)
    let ironRaised = Color(red: 0.14, green: 0.16, blue: 0.19)
    // Tones that previously existed only in the duplicate ContentView palette.
    let mossMid = Color(red: 0.16, green: 0.25, blue: 0.14)
    let parchmentShadow = Color(red: 0.46, green: 0.34, blue: 0.20)
    let borderIron = Color(red: 0.20, green: 0.18, blue: 0.15)

    // State colors. Mana colors remain owned by the mana system.
    let emeraldPriority = Color(red: 0.18, green: 0.78, blue: 0.47)
    let arcaneBlue = Color(red: 0.27, green: 0.65, blue: 0.85)
    let warningAmber = Color(red: 0.85, green: 0.54, blue: 0.17)
    let dangerOxblood = Color(red: 0.54, green: 0.17, blue: 0.15)

    // Readable content colors.
    let whiteReadable = Color(red: 0.97, green: 0.95, blue: 0.90)
    let mutedText = Color(red: 0.79, green: 0.74, blue: 0.65)
    let subduedText = Color(red: 0.61, green: 0.56, blue: 0.48)

    static let current = GameBoardTheme()
}

struct GameBoardShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension GameBoardTheme {
    var appBackground: Color { backgroundShadow }
    var panelBackground: Color { leatherDark }
    var raisedPanelBackground: Color { ironRaised }
    var panelBorder: Color { brass.opacity(0.42) }
    var quietBorder: Color { agedParchment.opacity(0.18) }
    var primaryText: Color { whiteReadable }
    var secondaryText: Color { mutedText }
    var tertiaryText: Color { subduedText }
    var primaryAction: Color { antiqueGold }
    var primaryActionPressed: Color { brass }

    var panelShadow: GameBoardShadow {
        GameBoardShadow(color: .black.opacity(0.34), radius: 10, x: 0, y: 5)
    }

    var floatingShadow: GameBoardShadow {
        GameBoardShadow(color: .black.opacity(0.48), radius: 18, x: 0, y: 9)
    }

    var priorityGlow: GameBoardShadow {
        GameBoardShadow(color: emeraldPriority.opacity(0.34), radius: 10, x: 0, y: 0)
    }

    var stackGlow: GameBoardShadow {
        GameBoardShadow(color: arcaneBlue.opacity(0.28), radius: 10, x: 0, y: 0)
    }
}

enum MagicTypography {
    static let hero = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let screenTitle = Font.system(.title, design: .serif).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .serif).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasis = Font.system(.body, design: .default).weight(.semibold)
    static let button = Font.system(.headline, design: .default).weight(.bold)
    static let label = Font.system(.caption, design: .default).weight(.bold)
    static let caption = Font.system(.caption, design: .default)
    static let gameLabel = Font.system(.caption2, design: .default).weight(.bold)
    static let gameValue = Font.system(.footnote, design: .default).weight(.semibold)
}

enum MagicPanelMaterial: Equatable {
    case oak
    case leather
    case iron
    case parchment
}

enum MagicPanelProminence: Equatable {
    case quiet
    case standard
    case elevated
}

enum MagicStatusTone: Equatable {
    case neutral
    case positive
    case warning
    case danger
    case arcane
}

private extension MagicPanelMaterial {
    var fill: LinearGradient {
        let theme = GameBoardTheme.current
        let colors: [Color]

        switch self {
        case .oak:
            colors = [theme.oakHighlight, theme.oak, theme.charredOak]
        case .leather:
            colors = [theme.leatherMid, theme.leatherDark]
        case .iron:
            colors = [theme.ironRaised, theme.iron]
        case .parchment:
            colors = [theme.parchmentLight, theme.agedParchment]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var foreground: Color {
        self == .parchment ? GameBoardTheme.current.parchmentInk : GameBoardTheme.current.primaryText
    }
}

private extension MagicStatusTone {
    var color: Color {
        let theme = GameBoardTheme.current
        switch self {
        case .neutral: return theme.mutedText
        case .positive: return theme.emeraldPriority
        case .warning: return theme.warningAmber
        case .danger: return theme.dangerOxblood
        case .arcane: return theme.arcaneBlue
        }
    }
}

struct MagicPanelModifier: ViewModifier {
    let material: MagicPanelMaterial
    let prominence: MagicPanelProminence
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    private var shadow: GameBoardShadow {
        let theme = GameBoardTheme.current
        switch prominence {
        case .quiet:
            return GameBoardShadow(color: .clear, radius: 0, x: 0, y: 0)
        case .standard:
            return theme.panelShadow
        case .elevated:
            return theme.floatingShadow
        }
    }

    private var borderOpacity: Double {
        switch prominence {
        case .quiet: return 0.34
        case .standard: return 0.58
        case .elevated: return 0.82
        }
    }

    func body(content: Content) -> some View {
        let theme = GameBoardTheme.current

        content
            .padding(contentPadding)
            .foregroundStyle(material.foreground)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material.fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(theme.panelBorder.opacity(borderOpacity), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(theme.agedParchment.opacity(prominence == .quiet ? 0.04 : 0.09))
                            .frame(height: 1)
                            .padding(.horizontal, cornerRadius)
                    }
            }
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

struct MagicPrimaryButtonStyle: ButtonStyle {
    var fillsWidth = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = GameBoardTheme.current

        configuration.label
            .font(compact ? MagicTypography.bodyEmphasis : MagicTypography.button)
            .foregroundStyle(theme.parchmentInk)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: compact ? 44 : 48)
            .background {
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [theme.brass, theme.brassShadow]
                                : [theme.antiqueGold, theme.brass],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                            .strokeBorder(theme.parchmentLight.opacity(0.34), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.18 : 0.3), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct MagicSecondaryButtonStyle: ButtonStyle {
    var fillsWidth = false
    var compact = false
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = GameBoardTheme.current
        let accent = isDestructive ? theme.dangerOxblood : theme.brass

        configuration.label
            .font(compact ? MagicTypography.bodyEmphasis : MagicTypography.button)
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, compact ? 13 : 17)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: compact ? 44 : 48)
            .background {
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .fill(configuration.isPressed ? theme.iron : theme.ironRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                            .strokeBorder(accent.opacity(isDestructive ? 0.72 : 0.48), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct MagicIconButtonStyle: ButtonStyle {
    var tone: MagicStatusTone = .neutral
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = GameBoardTheme.current
        let accent = tone.color
        let size: CGFloat = 44

        configuration.label
            .font(compact ? MagicTypography.bodyEmphasis : MagicTypography.button)
            .foregroundStyle(tone == .neutral ? theme.primaryText : accent)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? theme.iron : theme.ironRaised, in: Circle())
            .overlay {
                Circle().strokeBorder(accent.opacity(tone == .neutral ? 0.3 : 0.6), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func magicPanel(
        _ material: MagicPanelMaterial = .leather,
        prominence: MagicPanelProminence = .standard,
        cornerRadius: CGFloat = GameBoardDesignTokens.current.radius.largePanel,
        padding: CGFloat = GameBoardDesignTokens.current.spacing.panelPadding
    ) -> some View {
        modifier(
            MagicPanelModifier(
                material: material,
                prominence: prominence,
                cornerRadius: cornerRadius,
                contentPadding: padding
            )
        )
    }
}
