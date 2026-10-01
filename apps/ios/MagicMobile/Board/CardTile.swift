import SwiftUI
import PhotosUI
import UIKit

struct CardTile: View {
    let card: ZoneCard
    let selected: Bool
    var pending = false
    var legal = false
    // An engine offer permits starting a cast, not a promise of affordability.
    var castOffered = false
    var targetable = false
    var zoneName: String? = nil
    var width: CGFloat = 82
    var height: CGFloat = 112
    var ignoreTappedRotation: Bool = false
    var imageVariant: CardImageCacheVariant = .board
    /// Room a token copy's tag leaves at the trailing edge (TokenCopyFrameLayout.tagTrailingReserve).
    var tokenCopyTagTrailingReserve: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.nativeTurnControl) private var nativeTurnControl

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if !NativeCardArtworkPolicy.permitsLookup(card: card) {
                    CardArtPlaceholder(card: card, width: width, height: height)
                } else if let source = card.tokenCopySourceName {
                    TokenCopyCardFace(card: card, source: source, width: width, height: height, imageVariant: imageVariant,
                                      tagTrailingReserve: tokenCopyTagTrailingReserve)
                } else if nativeTurnControl != nil {
                    NativeCardArtworkView(card: card, variant: imageVariant) { loading, _ in
                        CardArtPlaceholder(card: card, width: width, height: height, loading: loading)
                    }
                } else {
                    AsyncImage(url: CardImageURL.image(card.card.name, variant: imageVariant)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .empty:
                            CardArtPlaceholder(card: card, width: width, height: height, loading: true)
                        case .failure, _:
                            CardArtPlaceholder(card: card, width: width, height: height)
                        }
                    }
                }
            }
            .saturation(card.tapped == true && !ignoreTappedRotation ? 0.3 : 1)
            .brightness(card.tapped == true && !ignoreTappedRotation ? -0.12 : 0)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            XmageCardIconStrip(icons: ignoreTappedRotation ? [] : card.visibleXmageIcons, cardWidth: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .allowsHitTesting(false)

            // A token copy's frame prints its live P/T itself.
            if !ignoreTappedRotation && card.showsPowerToughness && card.tokenCopySourceName == nil,
               let power = card.displayPower, let toughness = card.displayToughness {
                Text("\(power)/\(toughness)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.92), in: Capsule())
                    .padding(3)
            }

            if card.tapped == true && !ignoreTappedRotation {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: max(10, width * 0.15), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.72), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(3)
                    .allowsHitTesting(false)
            }

            if !ignoreTappedRotation && card.isCreature && card.summoningSickness == true {
                Image(systemName: "hourglass")
                    .font(.system(size: max(width * 0.105, 7), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: max(width * 0.22, 13), height: max(width * 0.22, 13))
                    .background(MagicPalette.warningAmber.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.32), lineWidth: 0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(3)
            }

            if !ignoreTappedRotation && !card.counterBadges.isEmpty {
                CardCounterBadgeStrip(badges: Array(card.counterBadges.prefix(3)), cardWidth: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: strokeWidth))
        .overlay(alignment: .topLeading) {
            if castOffered && !pending {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(4).background(.black.opacity(0.85), in: Circle()).padding(3)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay {
            Group {
            if castOffered && legal && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(LinearGradient(stops: [
                        .init(color: MagicPalette.legalEmerald, location: 0),
                        .init(color: MagicPalette.legalEmerald, location: 0.49),
                        .init(color: .white, location: 0.51),
                        .init(color: .white, location: 1)
                    ], startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                    .shadow(color: .white.opacity(0.5), radius: 8)
                    .padding(-3)
                    .allowsHitTesting(false)
            } else if castOffered && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.98), lineWidth: 2.8)
                    .shadow(color: .white.opacity(0.85), radius: 7)
                    .shadow(color: .white.opacity(0.45), radius: 14)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
            if legal && !castOffered && !selected && !pending && !targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MagicPalette.legalEmerald.opacity(0.92), lineWidth: max(width * 0.030, 2.1))
                    .shadow(
                        color: MagicPalette.legalEmerald.opacity(0.85),
                        radius: Self.playableGlowRadius(legal: legal, selected: selected, pending: pending, targetable: targetable, width: width)
                    )
                    .padding(-3)
            }
            if targetable {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.94), lineWidth: 2.8)
                    .shadow(color: Color.red.opacity(0.78), radius: 11)
                    .padding(-3)
            }
            }
            // The existing playable glow breathes in the hand; nothing new is drawn.
            .modifier(PlayableGlowPulse(active: zoneName == "Hand" && (legal || castOffered) && !selected && !pending && !targetable))
        }
        .shadow(color: shadowColor, radius: shadowRadius)
        .rotationEffect(.degrees(card.tapped == true && !ignoreTappedRotation ? 90 : 0))
        .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: card.tapped)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel(zoneName: zoneName, selected: selected, legal: legal, pending: pending))
        .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: zoneName))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(zoneName == "Hand" ? CardPlayAffordance(land: legal, spell: castOffered).accessibilityValue : "")
        .accessibilityHint(playHint)
    }

    private var playHint: String {
        switch CardPlayAffordance(land: legal, spell: castOffered) {
        case .landAndSpell: return "Land play and spell cast available. Select to choose a face. Hold to inspect."
        case .spell: return "Spell cast available. Drag upward to start casting. The engine will ask for payment and choices. Hold to inspect."
        case .land: return "Tap to select. Long press to inspect."
        case .none: return "Tap to select. Long press to inspect."
        }
    }

    private var strokeColor: Color {
        if pending {
            return MagicPalette.warningAmber
        }
        if selected {
            return MagicPalette.antiqueGold
        }
        if targetable {
            return Color.red
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.72)
        }
        if castOffered { return .white }
        return .black.opacity(0.55)
    }

    private var strokeWidth: CGFloat {
        if selected || pending || targetable { return 3 }
        if legal || castOffered { return 2.2 }
        return 1
    }

    private var shadowColor: Color {
        if pending {
            return MagicPalette.warningAmber.opacity(0.75)
        }
        if selected {
            return MagicPalette.antiqueGold.opacity(0.55)
        }
        if targetable {
            return Color.red.opacity(0.64)
        }
        if legal {
            return MagicPalette.legalEmerald.opacity(0.58)
        }
        return .clear
    }

    private var shadowRadius: CGFloat {
        if selected || pending {
            return 11
        }
        return Self.playableGlowRadius(legal: legal, selected: selected, pending: pending, targetable: targetable, width: width)
    }

    static func playableGlowRadius(legal: Bool, selected: Bool, pending: Bool, targetable: Bool, width: CGFloat) -> CGFloat {
        guard legal && !selected && !pending && !targetable else { return 0 }
        return max(width * 0.18, 10)
    }
}

/// Slow breathing for the hand's playable-card glow. Full board effects only,
/// never with Reduce Motion, and only while the card is actually playable.
struct PlayableGlowPulse: ViewModifier {
    let active: Bool
    @AppStorage(BoardFXLevel.key) private var level = BoardFXLevel.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && BoardFXLevel(rawValue: level) == .full && !reduceMotion {
            content.phaseAnimator([0.5, 1.0]) { glow, value in
                glow.opacity(value)
            } animation: { _ in .easeInOut(duration: 1.2) }
        } else {
            content
        }
    }
}

struct CardCounterBadgeStrip: View {
    let badges: [CardCounterBadge]
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: max(cardWidth * 0.012, 1)) {
            ForEach(badges, id: \.self) { badge in
                // Shrinks rather than wraps when a caller caps the strip's width.
                HStack(spacing: 2) {
                    Text(badge.label)
                        .font(.system(size: max(cardWidth * 0.065, 5.5), weight: .black))
                    Text("\(badge.count)")
                        .font(.system(size: max(cardWidth * 0.083, 6.5), weight: .black))
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, max(cardWidth * 0.035, 2.5))
                .padding(.vertical, max(cardWidth * 0.015, 1))
                .background(counterColor(for: badge).opacity(0.90), in: Capsule())
                .overlay(Capsule().stroke(.black.opacity(0.38), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
        }
    }

    private func counterColor(for badge: CardCounterBadge) -> Color {
        let label = badge.label
        if label == "+1/+1" { return MagicPalette.legalEmerald }
        if label == "-1/-1" { return MagicPalette.oxblood }
        if label == "LOY" { return MagicPalette.arcaneBlue }
        if label == "SHD" { return MagicPalette.antiqueGold }
        return MagicPalette.leather
    }
}

struct XmageCardIconStrip: View {
    let icons: [XmageCardIcon]
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: max(cardWidth * 0.018, 1)) {
            ForEach(visibleIcons, id: \.self) { icon in
                if icon.textBadge == "Menace" {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: iconSize * 0.75, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment)
                        .frame(width: iconSize + 4, height: iconSize + 4)
                        .background(MagicPalette.iron.opacity(0.9), in: Circle())
                        .accessibilityLabel("Menace: requires two or more blockers")
                } else if let assetName = CardImageURL.xmageIconAssetName(for: icon.iconType),
                   let image = UIImage(named: assetName) {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(MagicPalette.parchment)
                        .frame(width: iconSize, height: iconSize)
                        .padding(max(cardWidth * 0.025, 1.5))
                        .background(MagicPalette.iron.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .accessibilityLabel(icon.displayText ?? icon.iconType)
                }
            }
            if icons.count > visibleIcons.count {
                Text("+\(icons.count - visibleIcons.count)")
                    .font(.system(size: max(cardWidth * 0.08, 6), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: iconSize, height: iconSize)
                    .background(MagicPalette.antiqueGold.opacity(0.9), in: Circle())
            }
        }
    }

    private var visibleIcons: [XmageCardIcon] {
        Array(icons.prefix(5))
    }

    private var iconSize: CGFloat {
        max(cardWidth * 0.18, 11)
    }
}

struct TargetingStatusPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .black))
            VStack(alignment: .leading, spacing: 1) {
                Text("Choose a glowing target")
                    .font(.system(size: 11, weight: .black))
                Text("\(count) eligible target\(count == 1 ? "" : "s")")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.75)
            }
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(MagicPalette.iron.opacity(0.90), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.legalEmerald.opacity(0.56), lineWidth: 1.3))
        .shadow(color: MagicPalette.legalEmerald.opacity(0.24), radius: 14, y: 5)
    }
}

struct CardArtPlaceholder: View {
    let card: ZoneCard
    let width: CGFloat
    let height: CGFloat
    var loading = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MagicPalette.parchment,
                    Color(red: 0.72, green: 0.59, blue: 0.38),
                    MagicPalette.parchmentShadow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: max(height * 0.025, 2)) {
                HStack(alignment: .top, spacing: 3) {
                    Text(card.card.name)
                        .font(.system(size: max(width * 0.115, 6), weight: .black, design: .serif))
                        .foregroundStyle(MagicPalette.iron)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, max(width * 0.03, 2))
                .padding(.vertical, max(height * 0.018, 1.5))
                .background(MagicPalette.parchment.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MagicPalette.leather.opacity(0.78),
                                    MagicPalette.moss.opacity(0.62),
                                    MagicPalette.iron.opacity(0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: loading ? "hourglass" : "sparkles")
                        .font(.system(size: max(width * 0.18, 10), weight: .semibold))
                        .foregroundStyle(MagicPalette.antiqueGold.opacity(loading ? 0.34 : 0.42))
                }
                .frame(height: max(height * 0.38, 22))

                Text(card.card.typeLine.isEmpty ? "Card" : card.card.typeLine)
                    .font(.system(size: max(width * 0.075, 5), weight: .bold, design: .serif))
                    .foregroundStyle(MagicPalette.iron.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, max(width * 0.035, 2))
                    .padding(.vertical, max(height * 0.012, 1))
                    .background(MagicPalette.parchmentShadow.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))

                Spacer(minLength: 0)
            }
            .padding(max(width * 0.07, 3.5))

            if loading {
                ProgressView()
                    .tint(MagicPalette.antiqueGold)
                    .scaleEffect(0.58)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(max(width * 0.07, 4))
            }
        }
        .frame(width: width, height: height)
        .preference(key: CardArtPlaceholderShownKey.self, value: true)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    LinearGradient(
                        colors: [MagicPalette.borderBronze.opacity(0.70), MagicPalette.borderIron.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(width * 0.035, 1)
                )
        )
    }
}

/// A token copy drawn as its own card: the token's live name, type line, rules and P/T
/// around the copied card's illustration, with a tag naming the source. The printed
/// source card is never shown, because its name or stats can differ from the token's.
struct TokenCopyCardFace: View {
    let card: ZoneCard
    let source: String
    let width: CGFloat
    let height: CGFloat
    var imageVariant: CardImageCacheVariant = .board
    var tagTrailingReserve: CGFloat = 0
    @Environment(\.nativeTurnControl) private var nativeTurnControl

    var body: some View {
        let frame = TokenCopyFrameLayout(size: CGSize(width: width, height: height), tagTrailingReserve: tagTrailingReserve)
        let rules = card.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [MagicPalette.parchment, Color(red: 0.72, green: 0.59, blue: 0.38), MagicPalette.parchmentShadow],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            Text(card.card.name)
                .font(.system(size: frame.nameFontSize, weight: .black, design: .serif))
                .foregroundStyle(MagicPalette.iron)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, max(width * 0.03, 2))
                .frame(width: frame.nameBar.width, height: frame.nameBar.height, alignment: .leading)
                .background(MagicPalette.parchment.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                .offset(x: frame.nameBar.minX, y: frame.nameBar.minY)

            illustration
                .frame(width: frame.art.width, height: frame.art.height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(MagicPalette.iron.opacity(0.55), lineWidth: max(width * 0.006, 0.5)))
                .offset(x: frame.art.minX, y: frame.art.minY)

            Text(card.card.typeLine.isEmpty ? "Token" : card.card.typeLine)
                .font(.system(size: frame.typeFontSize, weight: .bold, design: .serif))
                .foregroundStyle(MagicPalette.iron.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, max(width * 0.03, 2))
                .frame(width: frame.typeBar.width, height: frame.typeBar.height, alignment: .leading)
                .background(MagicPalette.parchment.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                .offset(x: frame.typeBar.minX, y: frame.typeBar.minY)

            RoundedRectangle(cornerRadius: 3)
                .fill(MagicPalette.parchment.opacity(0.42))
                .frame(width: frame.textBox.width, height: frame.textBox.height)
                .offset(x: frame.textBox.minX, y: frame.textBox.minY)

            if frame.showsRules && !rules.isEmpty {
                let area = frame.rulesArea(showsPowerToughness: card.showsPowerToughness)
                GameRulesText(source: rules, cardName: card.card.name, symbolSize: frame.rulesFontSize)
                    .font(.system(size: frame.rulesFontSize, weight: .medium, design: .serif))
                    .foregroundStyle(MagicPalette.iron)
                    .lineLimit(frame.rulesLineLimit(showsPowerToughness: card.showsPowerToughness))
                    .frame(width: area.width, height: area.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: area.minX, y: area.minY)
            }

            if card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
                let box = frame.powerToughnessBox
                Text("\(power)/\(toughness)")
                    .font(.system(size: frame.powerToughnessFontSize, weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: box.width, height: box.height)
                    .background(MagicPalette.parchment, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(MagicPalette.borderBronze, lineWidth: max(width * 0.01, 0.8)))
                    .offset(x: box.minX, y: box.minY)
            }

            let slot = frame.tagSlot
            Text(TokenCopyPresentation.tag(source: source, cardWidth: width))
                .font(.system(size: frame.tagFontSize, weight: .black))
                .tracking(0.3)
                .foregroundStyle(MagicPalette.antiqueGold)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, slot.height * 0.45)
                .frame(height: slot.height)
                .background(MagicPalette.iron.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.6), lineWidth: 0.7))
                .frame(width: slot.width, height: slot.height, alignment: .leading)
                .offset(x: slot.minX, y: slot.minY)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LinearGradient(colors: [MagicPalette.borderBronze.opacity(0.70), MagicPalette.borderIron.opacity(0.62)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(width * 0.035, 1))
        )
    }

    /// The source's illustration only: NativeCardArtworkView crops copy art itself, and a
    /// whole printed image (previews, hosted games) is framed down to its art window.
    @ViewBuilder private var illustration: some View {
        if nativeTurnControl != nil {
            NativeCardArtworkView(name: card.card.name, variant: imageVariant, contentMode: .fill, artOnly: true,
                                  tokenTypeLine: card.card.tokenArtwork?.typeLine ?? card.card.typeLine,
                                  tokenOracleText: card.card.tokenArtwork?.oracleText ?? card.card.oracleText,
                                  tokenPower: card.card.tokenArtwork?.power ?? card.displayPower,
                                  tokenToughness: card.card.tokenArtwork?.toughness ?? card.displayToughness,
                                  tokenColors: card.card.tokenArtwork?.colors ?? card.card.tokenColors,
                                  tokenSourceName: source) { loading, _ in
                artPlaceholder(loading: loading)
            }
        } else {
            // Like CardTile: previews with forced placeholders pass no URL and stay loading.
            AsyncImage(url: CardImageURL.image(source, variant: imageVariant)) { phase in
                switch phase {
                case .success(let image):
                    GeometryReader { proxy in
                        let placement = CardIllustrationCrop.imageFrame(filling: proxy.size)
                        image.resizable()
                            .frame(width: placement.width, height: placement.height)
                            .offset(x: placement.minX, y: placement.minY)
                    }
                case .empty:
                    artPlaceholder(loading: true)
                case .failure, _:
                    artPlaceholder(loading: false)
                }
            }
        }
    }

    private func artPlaceholder(loading: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [MagicPalette.leather.opacity(0.78), MagicPalette.moss.opacity(0.62), MagicPalette.iron.opacity(0.86)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: loading ? "hourglass" : "sparkles")
                .font(.system(size: max(width * 0.18, 10), weight: .semibold))
                .foregroundStyle(MagicPalette.antiqueGold.opacity(loading ? 0.34 : 0.42))
        }
    }
}
