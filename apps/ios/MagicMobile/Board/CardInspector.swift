import SwiftUI
import PhotosUI
import UIKit

/// True while a card view shows the drawn placeholder instead of the real card image.
struct CardArtPlaceholderShownKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Held-card inspection. Inspection lasts only while the finger is down, so nothing
/// here can scroll: the printed card carries its own rules, and the panel adds only
/// live state. The rules text appears only when the real image is not showing
/// (placeholder, hidden or token art), and it shrinks to fit instead of clipping.
/// Every permanent visible on the battlefield, so an inspector can show what is attached.
struct InspectorBattlefieldKey: EnvironmentKey { static let defaultValue: [ZoneCard] = [] }

extension EnvironmentValues {
    var inspectorBattlefield: [ZoneCard] {
        get { self[InspectorBattlefieldKey.self] }
        set { self[InspectorBattlefieldKey.self] = newValue }
    }
}

extension GameSnapshot {
    var visibleBattlefield: [ZoneCard] { players.flatMap(\.zones.battlefield) }
}

struct CardInspector: View {
    let card: ZoneCard
    @Environment(\.inspectorBattlefield) private var battlefield
    @State private var artMissing = false

    /// Inspection is held with a finger, so the attachment list reads, never scrolls or taps.
    private var shown: ZoneCard { card }

    /// Auras, Equipment and anything else attached to the shown card, in table order.
    private var attachments: [ZoneCard] {
        battlefield.filter { $0.attachedToInstanceId == shown.instanceId && $0.instanceId != shown.instanceId }
    }

    private var attachedTo: ZoneCard? {
        guard let parent = shown.attachedToInstanceId else { return nil }
        return battlefield.first { $0.instanceId == parent }
    }

    /// Always at least the card's type; then live state on the table.
    private var liveState: [String] {
        let card = shown
        var details: [String] = []
        if card.card.isToken == true {
            details.append(card.card.copySourceArtworkName == nil ? "Token" : "Token copy")
        }
        if !card.card.typeLine.isEmpty { details.append(card.card.typeLine) }
        if card.visibleXmageIcons.contains(where: { $0.iconType == "COMMANDER" }) { details.append("Commander") }
        if card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
            details.append("\(power)/\(toughness)")
        }
        if let tapped = card.tapped { details.append(tapped ? "Tapped" : "Untapped") }
        if card.isCreature && card.summoningSickness == true { details.append("Summoning sick") }
        if card.isAttacking == true { details.append("Attacking") }
        if let blocking = card.blocking, !blocking.isEmpty { details.append(blocking.count == 1 ? "Blocking" : "Blocking \(blocking.count)") }
        if let damage = card.damage, damage > 0 { details.append("\(damage) damage") }
        if card.attachedToInstanceId != nil { details.append(attachedTo.map { "Attached to \($0.card.name)" } ?? "Attached") }
        if card.isPhasedOut { details.append("Phased out") }
        details += card.counterBadges.map { "\($0.label) ×\($0.count)" }
        details += card.visibleXmageIcons.compactMap { icon in
            icon.displayText ?? XmageCardIcon.keywordName(for: icon.iconType)
        }
        var seen = Set<String>()
        return details.filter { seen.insert($0.lowercased()).inserted }
    }

    private var showsRules: Bool {
        artMissing || shown.card.isToken == true || !NativeCardArtworkPolicy.permitsLookup(card: shown)
    }

    /// Solid, so the board never shows through the text while you read.
    static let backdrop = Color(red: 0.07, green: 0.08, blue: 0.10)

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 13

    var body: some View {
        let card = shown
        let rules = card.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rulesVisible = showsRules && !rules.isEmpty
        let state = liveState
        let attached = attachments
        let reminder = CardRulesReminder.text(for: card)
        // Rules get their room first; CardInspectorFit shrinks the card, then the text.
        CardInspectorLayout {
            InspectorCardFace(card: card)
            if rulesVisible || !state.isEmpty || !attached.isEmpty || reminder != nil {
                ViewThatFits(in: .vertical) {
                    ForEach(CardInspectorFit.textScales, id: \.self) { scale in
                        footer(scale: scale, card: card, rules: rulesVisible ? rules : nil, state: state,
                               reminder: reminder, attached: attached)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(9)
        .onPreferenceChange(CardArtPlaceholderShownKey.self) { artMissing = $0 }
        .background(Self.backdrop, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.35)))
    }

    private func footer(scale: CGFloat, card: ZoneCard, rules: String?, state: [String], reminder: String?,
                        attached: [ZoneCard]) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            if !state.isEmpty {
                InspectorStateChips(items: state, scale: scale)
            }
            if let rules {
                GameRulesText(source: rules, cardName: card.card.name,
                              isHidden: !NativeCardArtworkPolicy.permitsLookup(card: card), symbolSize: 16 * scale)
                    .font(.system(size: bodySize * scale)).lineSpacing(3 * scale)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reminder {
                Label(reminder, systemImage: "info.circle")
                    .font(.system(size: footnoteSize * scale, weight: .semibold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.rulesReminder")
            }
            if !attached.isEmpty {
                InspectorAttachmentList(cards: attached, scale: scale)
                    // A thumbnail's missing art must not read as the main card's.
                    .transformPreference(CardArtPlaceholderShownKey.self) { $0 = false }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .foregroundStyle(MagicPalette.parchment)
    }
}

/// The inspected card, as large as its slot allows.
struct InspectorCardFace: View {
    let card: ZoneCard

    var body: some View {
        GeometryReader { proxy in
            let height = max(1, min(proxy.size.height, proxy.size.width * BattlefieldLayoutMetrics.magicCardHeightToWidth))
            let width = height / BattlefieldLayoutMetrics.magicCardHeightToWidth
            CardTile(card: card, selected: false, zoneName: "Inspector", width: width, height: height,
                     ignoreTappedRotation: true, imageVariant: .inspection)
                .modifier(InspectionFoil(size: CGSize(width: width, height: height)))
                .id(card.instanceId)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

/// Card above (portrait) or beside (landscape) the footer, sized by CardInspectorFit from the
/// footer's natural height. The footer is then offered all the room left under the card.
struct CardInspectorLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 480))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let face = subviews.first else { return }
        let footer = subviews.count > 1 ? subviews[1] : nil
        let fit = CardInspectorFit.plan(available: bounds.size, cardAspect: BattlefieldLayoutMetrics.magicCardHeightToWidth,
                                        hasFooter: footer != nil) { width in
            footer?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        }
        if fit.horizontal {
            face.place(at: bounds.origin, proposal: ProposedViewSize(fit.cardSize))
            footer?.place(at: CGPoint(x: bounds.minX + fit.cardSize.width + CardInspectorFit.columnSpacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: fit.footerSize.width, height: bounds.height))
        } else {
            face.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(fit.cardSize))
            let top = fit.cardSize.height + CardInspectorFit.spacing
            footer?.place(at: CGPoint(x: bounds.minX, y: bounds.minY + top),
                          proposal: ProposedViewSize(width: bounds.width, height: max(bounds.height - top, 0)))
        }
    }
}

/// What is attached to the inspected card: each Aura or Equipment with its rules text.
struct InspectorAttachmentList: View {
    let cards: [ZoneCard]
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var rulesSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(cards.count == 1 ? "ATTACHED" : "ATTACHED · \(cards.count)")
                .font(.system(size: captionSize * scale, weight: .black)).tracking(1.2)
                .foregroundStyle(MagicPalette.antiqueGold)
            ForEach(cards.prefix(4)) { attachment in
                HStack(alignment: .top, spacing: 10 * scale) {
                    CardTile(card: attachment, selected: false, zoneName: "Inspector attachment",
                             width: 40 * scale, height: 40 * scale * BattlefieldLayoutMetrics.magicCardHeightToWidth,
                             ignoreTappedRotation: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.card.name)
                            .font(.system(size: nameSize * scale, weight: .heavy))
                            .foregroundStyle(.white)
                        if !attachment.card.typeLine.isEmpty {
                            Text(attachment.card.typeLine)
                                .font(.system(size: captionSize * scale, weight: .semibold))
                                .foregroundStyle(MagicPalette.parchment.opacity(0.7))
                        }
                        if let text = attachment.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            GameRulesText(source: text, cardName: attachment.card.name,
                                          isHidden: !NativeCardArtworkPolicy.permitsLookup(card: attachment), symbolSize: 16 * scale)
                                .font(.system(size: rulesSize * scale)).lineSpacing(1)
                                .foregroundStyle(MagicPalette.parchment)
                                .lineLimit(4)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)
                .background(MagicPalette.iron.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(MagicPalette.antiqueGold.opacity(0.35), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inspector.attachment.\(attachment.instanceId)")
            }
            if cards.count > 4 {
                Text("+\(cards.count - 4) more attached")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.75))
            }
        }
    }
}

/// Short notes for rules players often read differently than the engine applies them.
enum CardRulesReminder {
    static func text(for card: ZoneCard) -> String? {
        let rules = (card.card.oracleText ?? "").lowercased()
        if rules.contains("triggers an additional time") {
            return String(localized: "Only triggered abilities (“when”, “whenever”, “at”) happen again. Effects that say “instead”, like Chatterfang’s extra Squirrels, are not triggers and are not doubled.")
        }
        return nil
    }
}

/// Live card state as compact chips that wrap onto as many lines as they need
/// (Android's FlowRow), so the inspector's fit measures their real height.
struct InspectorStateChips: View {
    let items: [String]
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 15

    var body: some View {
        InspectorChipFlow(spacing: 6 * scale) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: chipSize * scale, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8 * scale).padding(.vertical, 3 * scale)
                    .background(MagicPalette.iron.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.55), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Left-to-right rows that wrap at the proposed width.
struct InspectorChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !rows[rows.count - 1].isEmpty && x + spacing + size.width > width {
                rows.append([])
                x = 0
            }
            x += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        // Explicit CGFloat types keep these closures cheap to type-check on older Xcode.
        let heights: [CGFloat] = rows.map { row in row.map { $0.size.height }.max() ?? 0 }
        let widths: [CGFloat] = rows.map { row in
            let cards: CGFloat = row.reduce(CGFloat(0)) { $0 + $1.size.width }
            return cards + spacing * CGFloat(max(row.count - 1, 0))
        }
        let height: CGFloat = heights.reduce(CGFloat(0), +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used: CGFloat = widths.max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += height + spacing
        }
    }
}
