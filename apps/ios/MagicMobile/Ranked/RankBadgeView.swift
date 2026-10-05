import SwiftUI

extension RankTier {
    /// The tier's metal, for glows, pips and the drawn stand-in badge.
    var tint: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.27)
        case .silver: return Color(red: 0.80, green: 0.83, blue: 0.88)
        case .gold: return Color(red: 1.0, green: 0.80, blue: 0.36)
        case .platinum: return Color(red: 0.55, green: 0.90, blue: 0.86)
        case .diamond: return Color(red: 0.50, green: 0.75, blue: 1.0)
        case .mythic: return Color(red: 1.0, green: 0.45, blue: 0.22)
        }
    }

    var shade: Color {
        switch self {
        case .bronze: return Color(red: 0.36, green: 0.18, blue: 0.07)
        case .silver: return Color(red: 0.32, green: 0.34, blue: 0.40)
        case .gold: return Color(red: 0.48, green: 0.30, blue: 0.06)
        case .platinum: return Color(red: 0.10, green: 0.34, blue: 0.36)
        case .diamond: return Color(red: 0.08, green: 0.20, blue: 0.48)
        case .mythic: return Color(red: 0.45, green: 0.07, blue: 0.03)
        }
    }
}

/// A tier's emblem: the rendered badge art, or a drawn brass medallion until it ships.
struct RankEmblem: View {
    let tier: RankTier
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let image = UIImage(named: tier.assetName) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors: [tier.tint, tier.shade], center: .init(x: 0.35, y: 0.3),
                                                 startRadius: 0, endRadius: size * 0.55))
                    Circle().strokeBorder(TavernPalette.brassLine, lineWidth: size * 0.06)
                    Image(systemName: tier == .mythic ? "flame.fill" : "crown.fill")
                        .font(.system(size: size * 0.36, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [.white.opacity(0.95), tier.tint], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pips toward the next division: little cut gems in a brass row.
struct RankPips: View {
    let filled: Int
    var total = RankPosition.pipsPerDivision
    var tier: RankTier = .gold
    var size: CGFloat = 14
    /// The pip that just changed glows (filled) or shows its empty socket (lost).
    var highlight: Int?

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(0..<total, id: \.self) { index in
                let on = index < filled
                Diamond()
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [.white, tier.tint, tier.shade], startPoint: .top, endPoint: .bottom))
                             : AnyShapeStyle(Color.black.opacity(0.55)))
                    .overlay(Diamond().strokeBorder(TavernPalette.brassLine, lineWidth: max(1, size * 0.1)))
                    .frame(width: size, height: size * 1.25)
                    .shadow(color: on ? tier.tint.opacity(index == highlight ? 1 : 0.55) : .clear, radius: index == highlight ? size * 0.6 : size * 0.2)
                    .scaleEffect(index == highlight ? 1.25 : 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "\(filled) of \(total) pips"))
    }

    private struct Diamond: InsettableShape {
        var inset: CGFloat = 0
        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: inset, dy: inset)
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            path.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.midY))
            path.closeSubpath()
            return path
        }
        func inset(by amount: CGFloat) -> Diamond { Diamond(inset: inset + amount) }
    }
}

/// The emblem with its division on a brass plate and the pips under it.
struct RankBadge: View {
    struct Spin: Equatable {
        var start: Date
        var turns: Double
        var duration: Double
        var reverse = false
    }

    let position: RankPosition
    var size: CGFloat = 96
    var showsPips = true
    var showsTitle = false
    /// Turns the emblem in 3D first (the division plate shows once it has landed).
    var spin: Spin? = nil

    var body: some View {
        VStack(spacing: size * 0.06) {
            Group {
                if let spin {
                    RankSpinEmblem(tier: position.tier, size: size, start: spin.start, turns: spin.turns,
                                   duration: spin.duration, reverse: spin.reverse)
                } else {
                    RankEmblem(tier: position.tier, size: size)
                }
            }
                .overlay(alignment: .bottom) {
                    if position.tier != .mythic {
                        Text(position.divisionNumeral)
                            .font(.system(size: max(10, size * 0.15), weight: .black, design: .serif))
                            .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04))
                            .padding(.horizontal, size * 0.08)
                            .frame(minWidth: size * 0.3, minHeight: size * 0.2)
                            .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), TavernPalette.brass, Color(red: 0.55, green: 0.36, blue: 0.12)],
                                                                      startPoint: .top, endPoint: .bottom)))
                            .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                            .offset(y: size * 0.06)
                    }
                }
            if showsTitle {
                Text(position.title)
                    .font(.system(size: max(13, size * 0.17), weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), position.tier.tint], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            }
            if showsPips {
                if position.tier == .mythic {
                    Label("\(position.pips)", systemImage: "flame.fill")
                        .font(.system(size: max(11, size * 0.13), weight: .heavy, design: .serif))
                        .foregroundStyle(position.tier.tint)
                } else {
                    RankPips(filled: position.pips, tier: position.tier, size: max(8, size * 0.12))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.tier == .mythic
                            ? String(localized: "Rank \(position.title), \(position.pips) points")
                            : String(localized: "Rank \(position.title), \(position.pips) of 4 pips"))
    }
}

extension CommanderBracket {
    var tint: Color {
        switch self {
        case .exhibition: return Color(red: 0.55, green: 0.80, blue: 0.55)
        case .core: return Color(red: 0.45, green: 0.70, blue: 0.95)
        case .upgraded: return Color(red: 0.95, green: 0.75, blue: 0.30)
        case .optimized: return Color(red: 0.95, green: 0.42, blue: 0.25)
        case .cedh: return Color(red: 0.75, green: 0.35, blue: 0.95)
        }
    }
}

/// A deck's bracket as a small tavern tag with the bracket's jewel: "Bracket 3 · Upgraded".
struct BracketTag: View {
    let bracket: CommanderBracket
    var short = false
    var leather = true

    var body: some View {
        TavernTag(text: short ? String(localized: "B\(bracket.rawValue)") : bracket.title, leather: leather, accent: bracket.tint)
            .accessibilityLabel(bracket.title)
    }
}

/// A badge turning in 3D: frames of the Meshy model's full turn (scripts/brand/rank_badges.py).
/// `turns` whole turns over `duration` seconds from `start`, slowing to a stop front on; with
/// `forever` it keeps turning at one turn per `duration`. Without the frames it turns flat.
/// Frames are decoded once (RankSpinFrames) and neighbours crossfade, so the slow end of the
/// turn glides instead of stepping.
struct RankSpinEmblem: View {
    static let frameCount = 32
    let tier: RankTier
    var size: CGFloat = 96
    var start = Date()
    var turns: Double = 2
    var duration: Double = 1.4
    var forever = false
    var reverse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [UIImage] = []

    static func hasFrames(_ tier: RankTier) -> Bool { UIImage(named: "\(tier.assetName)-spin-00") != nil }

    var body: some View {
        if reduceMotion {
            RankEmblem(tier: tier, size: size)
        } else {
            TimelineView(.animation) { context in
                let elapsed = max(0, context.date.timeIntervalSince(start))
                let progress: Double = forever ? elapsed / duration : min(1, elapsed / duration)
                // Ease out: fast at first, settling on the front.
                let turned = forever ? progress : turns * (1 - pow(1 - progress, 3))
                if !forever, progress >= 1 {
                    RankEmblem(tier: tier, size: size)
                } else if frames.count == Self.frameCount {
                    let position = turned * Double(Self.frameCount)
                    let raw = Int(position.rounded(.down))
                    let blend = position - Double(raw)
                    ZStack {
                        Image(uiImage: frames[frameIndex(raw)]).resizable().scaledToFit()
                        Image(uiImage: frames[frameIndex(raw + 1)]).resizable().scaledToFit().opacity(blend)
                    }
                    .frame(width: size, height: size)
                } else if Self.hasFrames(tier) {
                    // Decoding (first appearance only): hold the still front.
                    RankEmblem(tier: tier, size: size)
                } else {
                    RankEmblem(tier: tier, size: size)
                        .rotation3DEffect(.degrees((reverse ? -1 : 1) * turned * 360), axis: (0, 1, 0))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: tier) { frames = await RankSpinFrames.frames(tier) }
        }
    }

    private func frameIndex(_ raw: Int) -> Int {
        let wrapped = ((raw % Self.frameCount) + Self.frameCount) % Self.frameCount
        return reverse ? (Self.frameCount - wrapped) % Self.frameCount : wrapped
    }
}

/// Each tier's spin frames, decoded off the main thread once and kept: decoding a frame the first
/// time it was drawn is what made the turn stutter.
actor RankSpinFrames {
    static let shared = RankSpinFrames()
    private var cache: [RankTier: [UIImage]] = [:]

    static func frames(_ tier: RankTier) async -> [UIImage] { await shared.frames(tier) }

    private func frames(_ tier: RankTier) -> [UIImage] {
        if let cached = cache[tier] { return cached }
        let decoded = (0..<RankSpinEmblem.frameCount).compactMap {
            UIImage(named: String(format: "%@-spin-%02d", tier.assetName, $0))?.preparingForDisplay()
        }
        let complete = decoded.count == RankSpinEmblem.frameCount ? decoded : []
        cache[tier] = complete
        return complete
    }
}
