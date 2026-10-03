import SwiftUI
import PhotosUI
import UIKit

extension GameSnapshot {
    var combatSelectionResetKey: String {
        "\(id)|\(bridgeRevision ?? -1)|\(turn)|\(phase)|\(step ?? "")"
    }
}

/// Scrolled-away permanents stay clipped at the row's sides, while glows, attack stances,
/// selection lift and tapped rotation may draw above and below the row.
struct BattlefieldRowMask: View {
    var body: some View { Rectangle().padding(.horizontal, -4).padding(.vertical, -28) }
}

/// Scroll offsets live outside BattlefieldRow's body, so scrolling redraws only the edge fade and markers.
@Observable
final class BattlefieldRowScrollOffsets {
    var byScroller: [Int: CGFloat] = [:]
}

struct BattlefieldRowOffsetKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One BattlefieldRow scroller and the rows it moves together.
struct BattlefieldRowOverflowLane: Equatable {
    let scroller: Int
    let cardWidth: CGFloat
    let viewportWidth: CGFloat
    let cardsPerSlotByRow: [[Int]]

    func overflow(_ offsets: BattlefieldRowScrollOffsets) -> BattlefieldRowOverflow {
        BattlefieldRowOverflow.lane(contentOffset: offsets.byScroller[scroller] ?? 0, viewportWidth: viewportWidth,
                                    cardWidth: cardWidth, cardsPerSlotByRow: cardsPerSlotByRow)
    }
}

/// BattlefieldRowMask, with a soft fade at an edge where the lane clips cards.
struct BattlefieldRowFadeMask: View {
    let lane: BattlefieldRowOverflowLane
    let offsets: BattlefieldRowScrollOffsets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let overflow = lane.overflow(offsets)
        HStack(spacing: 0) {
            edge(fades: overflow.clipsLeading, from: .leading, to: .trailing)
            Rectangle()
            edge(fades: overflow.clipsTrailing, from: .trailing, to: .leading)
        }
        .padding(.horizontal, -4).padding(.vertical, -28)
        .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.18),
                   value: [overflow.clipsLeading, overflow.clipsTrailing])
    }

    private func edge(fades: Bool, from start: UnitPoint, to end: UnitPoint) -> some View {
        ZStack {
            Rectangle().opacity(fades ? 0 : 1)
            LinearGradient(colors: [.clear, .black], startPoint: start, endPoint: end).opacity(fades ? 1 : 0)
        }
        .frame(width: 28)
    }
}

/// "+N" counts of cards entirely scrolled out of view. Drawing only: touches reach the lane beneath.
struct BattlefieldRowOverflowMarkers: View {
    let lane: BattlefieldRowOverflowLane
    let offsets: BattlefieldRowScrollOffsets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let overflow = lane.overflow(offsets)
        HStack(spacing: 0) {
            if overflow.hiddenLeading > 0 { marker(overflow.hiddenLeading, side: "left") }
            Spacer(minLength: 0)
            if overflow.hiddenTrailing > 0 { marker(overflow.hiddenTrailing, side: "right") }
        }
        .padding(.horizontal, 3)
        .allowsHitTesting(false)
        .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.18),
                   value: [overflow.hiddenLeading > 0, overflow.hiddenTrailing > 0])
    }

    private func marker(_ count: Int, side: String) -> some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .black))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(MagicPalette.iron.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.58), lineWidth: 1))
            .transition(.opacity)
            // The row's own identifier (on its scroll view) takes precedence here; find markers by label.
            .accessibilityLabel("\(count) more \(count == 1 ? "card" : "cards") off-screen to the \(side)")
    }
}

extension View {
    /// Reports how far the scroller holding this content has moved, for the edge fade and markers.
    func reportsBattlefieldRowOffset(_ scroller: Int) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: BattlefieldRowOffsetKey.self,
                                   value: [scroller: -geometry.frame(in: .named(BattlefieldRow.scrollSpace)).minX])
        })
    }

    /// The lane's clipping mask with its edge fade, the "+N" markers and the offset they read.
    func battlefieldRowOverflow(_ lane: BattlefieldRowOverflowLane, offsets: BattlefieldRowScrollOffsets) -> some View {
        coordinateSpace(.named(BattlefieldRow.scrollSpace))
            .mask { BattlefieldRowFadeMask(lane: lane, offsets: offsets) }
            .overlay { BattlefieldRowOverflowMarkers(lane: lane, offsets: offsets) }
            .onPreferenceChange(BattlefieldRowOffsetKey.self) { values in
                for (scroller, offset) in values where offsets.byScroller[scroller] != offset {
                    offsets.byScroller[scroller] = offset
                }
            }
    }
}

struct BattlefieldRow: View {
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let targetableIds: Set<String>
    let combatHighlightIds: Set<String>
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    var flipped = false
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    var adaptsToDensity = false
    var availableHeight: CGFloat? = nil
    var arrangement: BattlefieldRowArrangement = .automatic
    var allowsManaUndo = false
    var manaPaymentActive = false
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool
    @State private var expandedGroupIds: Set<String> = []
    @State private var scrollOffsets = BattlefieldRowScrollOffsets()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleCards: [ZoneCard] {
        cardGroups.flatMap { group in
            isExpanded(group) ? group.cards : [group.representative]
        }
    }

    private func isExpanded(_ group: BattlefieldCardGroup) -> Bool {
        !group.id.hasPrefix("attachment:") && (expandedGroupIds.contains(group.id) ||
        group.cards.contains { targetableIds.contains($0.instanceId) || targetableIds.contains($0.id) } ||
        Self.requiresIndividualCombatCards(group, highlightedIDs: combatHighlightIds))
    }

    static func requiresIndividualCombatCards(_ group: BattlefieldCardGroup, highlightedIDs: Set<String>) -> Bool {
        group.cards.contains {
            $0.isAttacking == true || $0.blocking?.isEmpty == false ||
            highlightedIDs.contains($0.instanceId) || highlightedIDs.contains($0.id)
        }
    }

    private var renderedCardWidth: CGFloat {
        if let permanentLayout { return permanentLayout.cardWidth }
        guard adaptsToDensity else { return cardWidth }
        return BattlefieldAdaptiveSizing.cardWidth(
            availableRowWidth: rowWidth, maxCardWidth: cardWidth,
            heightRatio: 1,
            tappedSlots: Array(repeating: false, count: min(5, visibleCards.count)))
    }

    private var renderedCardHeight: CGFloat {
        cardHeight * renderedCardWidth / max(cardWidth, 1)
    }

    private var permanentLayout: ArenaPermanentLayout? {
        availableHeight.map { height in
            let proposed = arrangement.rows(renderedGroups, flipped: flipped,
                twoRows: arrangement == .landscapeResources || visibleCardCount > 5)
            return ArenaPermanentLayout(rowCounts: proposed.map(\.count), width: rowWidth,
                height: height, maxCardWidth: cardWidth, ratio: cardHeight / max(cardWidth, 1))
        }
    }

    private var renderedGroups: [BattlefieldCardGroup] {
        cardGroups.flatMap { group in
            isExpanded(group) ? group.cards.map { BattlefieldCardGroup(id: "card:" + $0.instanceId, cards: [$0]) } : [group]
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let rows = permanentLayout?.rows ?? 1
            let arranged = arrangement.rows(renderedGroups, flipped: flipped, twoRows: rows == 2)
            if arrangement == .landscapeResources && rows == 2 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<2, id: \.self) { row in
                        ScrollView(.horizontal, showsIndicators: rowContentWidth(arranged[row]) > rowWidth) {
                            rowTiles(arranged[row])
                                .padding(.horizontal, 8)
                                .frame(minWidth: rowWidth, minHeight: ((availableHeight ?? 0) - 4) / 2)
                                .reportsBattlefieldRowOffset(row)
                        }
                        .scrollClipDisabled()
                        .battlefieldRowOverflow(overflowLane(scroller: row, rows: [arranged[row]]), offsets: scrollOffsets)
                        // Each resource row scrolls on its own, so each needs its own identifier:
                        // the first keeps the lane's, the second adds ".row2".
                        .accessibilityIdentifier("board.battlefield.\(title)" + (row == 0 ? "" : ".row\(row + 1)"))
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: showsOverflowIndicator) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<rows, id: \.self) { row in rowTiles(arranged[row]) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, availableHeight == nil ? 0 : 8)
                    .frame(minWidth: rowWidth, minHeight: availableHeight ?? max(cardHeight + 6, 44), alignment: .center)
                    .reportsBattlefieldRowOffset(0)
                }
                .scrollClipDisabled()
                .battlefieldRowOverflow(overflowLane(scroller: 0, rows: Array(arranged.prefix(rows))), offsets: scrollOffsets)
                .accessibilityIdentifier("board.battlefield.\(title)")
            }
        }
        .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2), value: renderedCardWidth)
    }

    private func rowContentWidth(_ groups: [BattlefieldCardGroup]) -> CGFloat {
        16 + groups.reduce(CGFloat.zero) { width, group in
            width + renderedCardWidth
        } + CGFloat(max(groups.count - 1, 0)) * 4
    }

    static let scrollSpace = "battlefield-row-scroll"

    /// Every tile is one card wide; a collapsed group or attachment stack counts all of its cards.
    private func overflowLane(scroller: Int, rows: [[BattlefieldCardGroup]]) -> BattlefieldRowOverflowLane {
        BattlefieldRowOverflowLane(scroller: scroller, cardWidth: renderedCardWidth, viewportWidth: rowWidth,
                                   cardsPerSlotByRow: rows.map { $0.map(\.count) })
    }

    @ViewBuilder
    private func rowTiles(_ groups: [BattlefieldCardGroup]) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(groups) { group in
                if group.id.hasPrefix("attachment:") { attachmentGroupTile(group) }
                else if group.count > 1 { collapsedGroupTile(group) }
                else { battlefieldCardTile(group.representative) }
            }
        }
    }

    private var cardGroups: [BattlefieldCardGroup] {
        BattlefieldAttachments.groups(cards)
    }

    private var visibleCardCount: Int {
        cardGroups.reduce(0) { count, group in
            count + (isExpanded(group) ? group.count : 1)
        }
    }

    /// Arena-style: Auras and Equipment tuck behind their creature, each showing a named tab
    /// above it. The creature keeps its full size (Caleb, 2026-10-02): the tabs rise above it,
    /// over the gap or the row above, since the lanes do not clip.
    @ViewBuilder
    private func attachmentGroupTile(_ group: BattlefieldCardGroup) -> some View {
        let attachments = Array(group.cards.dropFirst())
        // Two tabs at most; the rest count on the top tab.
        let shown = Array(attachments.prefix(2))
        let peek = max(11, min(14, renderedCardHeight * 0.13))
        ZStack(alignment: .bottom) {
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, card in
                battlefieldCardTile(card)
                    .overlay(alignment: .top) {
                        AttachmentNameTab(card: card, height: peek,
                                          more: index == shown.count - 1 ? attachments.count - shown.count : 0)
                    }
                    .offset(y: -peek * CGFloat(index + 1))
                    .accessibilityHint("Attached to \(group.representative.card.name). Tap to select; hold to inspect.")
            }
            battlefieldCardTile(group.representative)
        }
        .frame(width: renderedCardWidth, height: renderedCardHeight, alignment: .bottom)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func collapsedGroupTile(_ group: BattlefieldCardGroup) -> some View {
        let card = group.representative
        let groupIds = Set(group.cards.flatMap { [$0.instanceId, $0.id] })
        let targetable = !targetableIds.isDisjoint(with: groupIds)
        let combatHighlighted = !combatHighlightIds.isDisjoint(with: groupIds)
        let legal = group.cards.contains { legalAction(for: $0) != nil }

        ArenaBattlefieldCard(
            card: card,
            selected: false,
            legal: legal,
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .boardFXCardMotion(card.instanceId)
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .overlay(alignment: .bottomLeading) {
            Text("×\(group.count)")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(MagicPalette.iron.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.58), lineWidth: 1))
                .padding(3)
                .allowsHitTesting(false)
        }
        .onCardInteraction(tap: {
            expandedGroupIds.insert(group.id)
            selectedCard = nil
            inspectedCard = nil
            GameHaptics.selection()
        }, inspect: {
            inspectedCard = card
            GameHaptics.impact()
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .offset(y: card.tapped == true && (permanentLayout?.rows ?? 1) == 1 ? 5 : 0)
        .accessibilityLabel("\(group.count) grouped \(card.card.name) cards in \(title)")
        .accessibilityHint("Tap to expand the group. Long press to inspect a card.")
        .accessibilityAction(named: Text("Expand group")) {
            expandedGroupIds.insert(group.id)
        }
        .accessibilityAction(named: Text("Inspect")) {
            inspectedCard = card
        }
    }

    @ViewBuilder
    private func battlefieldCardTile(_ card: ZoneCard) -> some View {
        let action = legalAction(for: card)
        let targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
        let combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)

        ArenaBattlefieldCard(
            card: card,
            selected: selectedCard?.id == card.id,
            legal: action != nil,
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .boardFXCardMotion(card.instanceId)
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .onCardInteraction(tap: {
            handleCardTap(card, action: action, targetable: targetable, combatHighlighted: combatHighlighted)
        }, inspect: {
            inspectedCard = card
            GameHaptics.impact()
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .offset(y: card.tapped == true && (permanentLayout?.rows ?? 1) == 1 ? 5 : 0)
        .accessibilityAction(named: Text(targetable ? "Choose target" : "Select")) {
            handleCardTap(card, action: action, targetable: targetable, combatHighlighted: combatHighlighted)
        }
        .accessibilityAction(named: Text("Inspect")) {
            inspectedCard = card
        }
    }

    private func handleCardTap(_ card: ZoneCard, action: LegalAction?, targetable: Bool, combatHighlighted: Bool) {
        guard !card.isPhasedOut else { return }
        if targetable {
            runTargetAction(card)
        } else if !targetableIds.isEmpty {
            GameHaptics.warning()
        } else if combatHighlighted, runCombatCardAction(card) {
            GameHaptics.selection()
        } else if let immediate = PortraitInteractionPolicy.automaticCardAction(GameBoardInteractionState.cardActions(for: card, actions: legalActions)), Self.tapRunnableActionTypes.contains(immediate.type) {
            runAction(immediate)
        } else {
            selectedCard = selectedCard?.instanceId == card.instanceId ? nil : card
            inspectedCard = nil
            GameHaptics.selection()
        }
    }

    private var showsOverflowIndicator: Bool {
        if cardGroups.contains(where: { $0.id.hasPrefix("attachment:") }) { return true }
        if let permanentLayout { return permanentLayout.contentWidth > rowWidth }
        let contentWidth = 16 + CGFloat(visibleCards.count) * renderedCardWidth + CGFloat(max(visibleCardCount - 1, 0)) * 4
        return contentWidth > rowWidth
    }

    private func legalAction(for card: ZoneCard) -> LegalAction? {
        guard !card.isPhasedOut else { return nil }
        if allowsManaUndo, manaPaymentActive, card.tapped == true, let undo = manaUndoAction,
           undo.sourceInstanceId == card.instanceId || undo.cardInstanceId == card.instanceId {
            return undo
        }
        return legalActions.first {
            $0.cardInstanceId == card.instanceId || $0.sourceInstanceId == card.instanceId
        }
    }

    private var manaUndoAction: LegalAction? {
        legalActions.first { Self.manaUndoActionTypes.contains($0.type) }
    }

    private static let tapRunnableActionTypes = Set(["make_mana", "undo_mana"])
    private static let manaUndoActionTypes = Set(["undo_mana"])
}

enum HandFanLayout {
    static func card(
        at point: CGPoint,
        cards: [ZoneCard],
        metrics: BattlefieldLayoutMetrics,
        selectedCardId: String?,
        draggingCardId: String?,
        dragOffset: CGSize
    ) -> ZoneCard? {
        guard !cards.isEmpty else { return nil }
        for (index, card) in cards.enumerated().reversed() {
            let frame = cardFrame(
                index: index,
                card: card,
                cards: cards,
                metrics: metrics,
                selectedCardId: selectedCardId,
                draggingCardId: draggingCardId,
                dragOffset: dragOffset
            )
            if frame.insetBy(dx: -8, dy: -8).contains(point) {
                return card
            }
        }
        return cards.last
    }

    static func cardFrame(
        index: Int,
        card: ZoneCard,
        cards: [ZoneCard],
        metrics: BattlefieldLayoutMetrics,
        selectedCardId: String?,
        draggingCardId: String?,
        dragOffset: CGSize
    ) -> CGRect {
        let center = CGFloat(cards.count - 1) / 2
        let distance = CGFloat(index) - center
        let maxSpread = max((metrics.playWidth - metrics.handCardWidth) / CGFloat(max(cards.count - 1, 1)), 0)
        let spread = min(metrics.handCardWidth * 0.56, maxSpread)
        let isSelected = selectedCardId == card.id
        let isDragging = draggingCardId == card.id
        let midX = metrics.playWidth / 2 + distance * spread + (isDragging ? dragOffset.width : 0)
        let midY = metrics.handFrameHeight / 2 + (isSelected ? -30 : 10) + (isDragging ? dragOffset.height : 0)
        return CGRect(
            x: midX - metrics.handCardWidth / 2,
            y: midY - metrics.handCardHeight / 2,
            width: metrics.handCardWidth,
            height: metrics.handCardHeight
        )
    }
}
