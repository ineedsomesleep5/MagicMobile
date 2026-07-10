import SwiftUI

struct GameBoardTheme {
    // Foundations
    let backgroundDeepMoss = Color(red: 0.02, green: 0.10, blue: 0.07)
    let backgroundShadow = Color(red: 0.04, green: 0.03, blue: 0.02)
    let charredOak = Color(red: 0.08, green: 0.045, blue: 0.025)
    let oak = Color(red: 0.18, green: 0.10, blue: 0.05)
    let oakHighlight = Color(red: 0.28, green: 0.16, blue: 0.08)
    let leatherDark = Color(red: 0.11, green: 0.07, blue: 0.05)
    let leatherMid = Color(red: 0.20, green: 0.13, blue: 0.09)
    let carvedWood = Color(red: 0.29, green: 0.17, blue: 0.09)
    let agedParchment = Color(red: 0.72, green: 0.58, blue: 0.37)
    let parchmentLight = Color(red: 0.91, green: 0.84, blue: 0.68)
    let parchmentInk = Color(red: 0.14, green: 0.09, blue: 0.055)
    let antiqueGold = Color(red: 0.84, green: 0.65, blue: 0.25)
    let brass = Color(red: 0.66, green: 0.47, blue: 0.17)
    let brassShadow = Color(red: 0.31, green: 0.20, blue: 0.07)
    let iron = Color(red: 0.09, green: 0.08, blue: 0.08)
    let ironRaised = Color(red: 0.16, green: 0.14, blue: 0.13)

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

struct MagicBadgeModifier: ViewModifier {
    let tone: MagicStatusTone

    func body(content: Content) -> some View {
        let color = tone.color

        content
            .font(MagicTypography.label)
            .foregroundStyle(tone == .neutral ? GameBoardTheme.current.primaryText : color)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(color.opacity(tone == .neutral ? 0.12 : 0.15), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1)
            }
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

    func magicBadge(_ tone: MagicStatusTone = .neutral) -> some View {
        modifier(MagicBadgeModifier(tone: tone))
    }
}
