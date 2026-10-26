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
    /// Already chosen in a multi-card target prompt (GameBoardInteractionState.boardChosenTargetIds).
    var chosenIds: Set<String> = []
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
    /// Where the tiles sit in the lane while they fit: centred, or (the Arena board's lands) from its leading edge.
    var alignment: Alignment = .center
    /// The Arena board sizes its rows itself (ArenaRowFit): this many rows, whatever the tile count.
    var preferredRows: Int? = nil
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool
    @State private var expandedGroupIds: Set<String> = []
    /// Piles opened with a hold while choosing from them: they stack again once the choice or combat ends. A pile opened
    /// just to look stays open until its Stack chip (Caleb, 2026-10-16).
    @State private var choiceOpenedGroupIds: Set<String> = []
    @State private var scrollOffsets = BattlefieldRowScrollOffsets()
    @State private var layoutCache = BattlefieldRowLayoutCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tavernBoard) private var tavern
    /// The Arena board piles identical lands the reference's way: each copy peeks out from under the one on top.
    @Environment(\.arenaBoard) private var arena
    @Environment(\.cardFrames) private var cardFrames

    /// The row's groups, sizes and arrangement, recomputed only when an input changes.
    private var layout: BattlefieldRowLayout {
        layoutCache.layout(BattlefieldRowLayout.Input(
            flipped: flipped, adaptsToDensity: adaptsToDensity, arrangement: arrangement, preferredRows: preferredRows,
            rowWidth: rowWidth, cardWidth: cardWidth, cardHeight: cardHeight, availableHeight: availableHeight,
            expandedGroupIds: expandedGroupIds, chosenIds: chosenIds, targetableIds: targetableIds,
            combatHighlightIds: combatHighlightIds, cards: cards), make: makeLayout)
    }

    private func makeLayout() -> BattlefieldRowLayout {
        let groups = BattlefieldAttachments.groups(cards)
        let rendered = groups.flatMap(displayGroups)
        let permanent = availableHeight.map { height in
            let proposed = arrangement.rows(rendered, flipped: flipped,
                twoRows: preferredRows.map { $0 == 2 } ?? (arrangement == .landscapeResources || rendered.count > 5))
            return ArenaPermanentLayout(rowCounts: proposed.map(\.count), width: rowWidth,
                height: height, maxCardWidth: cardWidth, ratio: cardHeight / max(cardWidth, 1))
        }
        let width: CGFloat
        if let permanent {
            width = permanent.cardWidth
        } else if adaptsToDensity {
            width = BattlefieldAdaptiveSizing.cardWidth(
                availableRowWidth: rowWidth, maxCardWidth: cardWidth,
                heightRatio: 1,
                tappedSlots: Array(repeating: false, count: min(5, rendered.count)))
        } else {
            width = cardWidth
        }
        return BattlefieldRowLayout(
            groups: groups, rendered: rendered, permanent: permanent, cardWidth: width,
            cardHeight: cardHeight * width / max(cardWidth, 1),
            arranged: arrangement.rows(rendered, flipped: flipped, twoRows: (permanent?.rows ?? 1) == 2),
            stackChips: expandedGroupIds.isEmpty ? [:] : Self.stackChipPiles(groups, expanded: expandedGroupIds))
    }

    /// The tiles a group shows: every card when it is open; otherwise one pile, with the cards already chosen from it
    /// pulled out beside it as their own tiles (Caleb, 2026-10-15), so the pile's next tap chooses another one and a
    /// tap on a pulled-out card takes it back.
    private func displayGroups(_ group: BattlefieldCardGroup) -> [BattlefieldCardGroup] {
        Self.displayGroups(group, expanded: isExpanded(group), chosenIds: chosenIds)
    }

    static func displayGroups(_ group: BattlefieldCardGroup, expanded: Bool, chosenIds: Set<String>) -> [BattlefieldCardGroup] {
        func single(_ card: ZoneCard) -> BattlefieldCardGroup { BattlefieldCardGroup(id: "card:" + card.instanceId, cards: [card]) }
        if expanded { return group.cards.map(single) }
        guard group.count > 1, !group.id.hasPrefix("attachment:") else { return [group] }
        let chosen = group.cards.filter { isChosen($0, chosenIds) }
        guard !chosen.isEmpty else { return [group] }
        let rest = group.cards.filter { !isChosen($0, chosenIds) }
        return (rest.isEmpty ? [] : [BattlefieldCardGroup(id: group.id, cards: rest)]) + chosen.map(single)
    }

    /// The card a tap on a pile chooses next: the first that can be targeted and isn't chosen yet.
    static func nextTargetable(in group: BattlefieldCardGroup, targetableIds: Set<String>, chosenIds: Set<String>) -> ZoneCard? {
        group.cards.first { !$0.isPhasedOut && !isChosen($0, chosenIds) &&
                            (targetableIds.contains($0.instanceId) || targetableIds.contains($0.id)) }
    }

    static func isChosen(_ card: ZoneCard, _ chosenIds: Set<String>) -> Bool {
        chosenIds.contains(card.instanceId) || chosenIds.contains(card.id)
    }

    private func isChosen(_ card: ZoneCard) -> Bool { Self.isChosen(card, chosenIds) }

    private func isExpanded(_ group: BattlefieldCardGroup) -> Bool {
        guard !group.id.hasPrefix("attachment:") else { return false }
        if expandedGroupIds.contains(group.id) { return true }
        // Eight or more identical tokens stay one pile even in combat or targeting (Caleb,
        // 2026-10-02): a tap acts on the next one, a hold opens the pile.
        if group.count >= Self.stackThreshold { return false }
        return group.cards.contains { targetableIds.contains($0.instanceId) || targetableIds.contains($0.id) } ||
            Self.requiresIndividualCombatCards(group, highlightedIDs: combatHighlightIds)
    }

    /// From this many identical cards a group stays stacked while it can be chosen.
    static let stackThreshold = 8

    /// Each tile's width in cards as the Arena board draws these cards, for ArenaRowFit: an attached Aura or Equipment
    /// peeks out 0.3 of a card per layer, a pile of lands 0.12 per copy underneath, and piles open into single cards
    /// while they are chosen from, as `isExpanded` opens them. A pile the player opened by hand scrolls like any overflow.
    static func arenaTileUnits(_ cards: [ZoneCard], targetableIds: Set<String>, chosenIds: Set<String>,
                               combatHighlightIds: Set<String>) -> [CGFloat] {
        BattlefieldAttachments.groups(cards).flatMap { group -> [BattlefieldCardGroup] in
            let choosing = group.cards.contains { targetableIds.contains($0.instanceId) || targetableIds.contains($0.id) } ||
                requiresIndividualCombatCards(group, highlightedIDs: combatHighlightIds)
            let expanded = !group.id.hasPrefix("attachment:") && group.count < stackThreshold && choosing
            return displayGroups(group, expanded: expanded, chosenIds: chosenIds)
        }.map { group in
            if group.id.hasPrefix("attachment:") { return 1 + 0.3 * CGFloat(min(group.count - 1, 3)) }
            if group.count > 1, group.representative.card.isLand { return 1 + 0.12 * CGFloat(min(group.count - 1, 5)) }
            return 1
        }
    }

    /// The piles still open once a choice or combat has ended: the ones opened only to look.
    static func openAfterChoice(expanded: Set<String>, openedForChoice: Set<String>) -> Set<String> {
        expanded.subtracting(openedForChoice)
    }

    /// The last card of each pile the player opened, keyed to that pile: it carries the Stack chip.
    static func stackChipPiles(_ groups: [BattlefieldCardGroup], expanded: Set<String>) -> [String: String] {
        var piles: [String: String] = [:]
        for group in groups where group.count > 1 && expanded.contains(group.id) && !group.id.hasPrefix("attachment:") {
            if let last = group.cards.last { piles[last.instanceId] = group.id }
        }
        return piles
    }

    private func restack(_ groupId: String) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
            expandedGroupIds.remove(groupId)
            choiceOpenedGroupIds.remove(groupId)
        }
        GameHaptics.selection()
    }

    /// The card a tap on a stack acts on: the first that can be targeted, then the first that
    /// combat highlights; nil when the stack simply opens.
    private func nextChoosable(in group: BattlefieldCardGroup) -> (card: ZoneCard, targetable: Bool)? {
        if let card = Self.nextTargetable(in: group, targetableIds: targetableIds, chosenIds: chosenIds) {
            return (card, true)
        }
        if let card = group.cards.first(where: { combatHighlightIds.contains($0.instanceId) || combatHighlightIds.contains($0.id) }) {
            return (card, false)
        }
        return nil
    }

    static func requiresIndividualCombatCards(_ group: BattlefieldCardGroup, highlightedIDs: Set<String>) -> Bool {
        group.cards.contains {
            $0.isAttacking == true || $0.blocking?.isEmpty == false ||
            highlightedIDs.contains($0.instanceId) || highlightedIDs.contains($0.id)
        }
    }

    private var renderedCardWidth: CGFloat { layout.cardWidth }
    private var renderedCardHeight: CGFloat { layout.cardHeight }
    private var permanentLayout: ArenaPermanentLayout? { layout.permanent }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let rows = permanentLayout?.rows ?? 1
            let arranged = layout.arranged
            if arrangement == .landscapeResources && rows == 2 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<2, id: \.self) { row in
                        ScrollView(.horizontal, showsIndicators: rowContentWidth(arranged[row]) > rowWidth) {
                            rowTiles(arranged[row], tucked: row > 0)
                                .padding(.horizontal, 8)
                                .frame(minWidth: rowWidth, minHeight: ((availableHeight ?? 0) - 4) / 2, alignment: alignment)
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
                        ForEach(0..<rows, id: \.self) { row in rowTiles(arranged[row], tucked: row > 0) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, availableHeight == nil ? 0 : 8)
                    .frame(minWidth: rowWidth, minHeight: availableHeight ?? max(cardHeight + 6, 44), alignment: alignment)
                    .reportsBattlefieldRowOffset(0)
                }
                .scrollClipDisabled()
                .battlefieldRowOverflow(overflowLane(scroller: 0, rows: Array(arranged.prefix(rows))), offsets: scrollOffsets)
                .accessibilityIdentifier("board.battlefield.\(title)")
            }
        }
        .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2), value: renderedCardWidth)
        .onChange(of: targetableIds.isEmpty && combatHighlightIds.isEmpty) { _, settled in
            guard settled, !choiceOpenedGroupIds.isEmpty else { return }
            withAnimation(GameBoardMotion.reduced(reduceMotion) ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
                expandedGroupIds = Self.openAfterChoice(expanded: expandedGroupIds, openedForChoice: choiceOpenedGroupIds)
                choiceOpenedGroupIds = []
            }
        }
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
    /// `tucked`: a row sits above this one in the lane, so attachment tabs stay inside their creature.
    private func rowTiles(_ groups: [BattlefieldCardGroup], tucked: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(groups) { group in
                if group.id.hasPrefix("attachment:") { attachmentGroupTile(group, tucked: tucked) }
                else if group.count > 1 { collapsedGroupTile(group) }
                else { battlefieldCardTile(group.representative) }
            }
        }
    }

    private var cardGroups: [BattlefieldCardGroup] { layout.groups }

    /// Arena-style: Auras and Equipment tuck behind their creature, each showing a named tab
    /// above it. The creature keeps its full size (Caleb, 2026-10-02): the tabs rise above it,
    /// over the gap. In a lower row (`tucked`) they would cover the power and toughness of the card
    /// above (Caleb, 2026-10-15), so there they sit inside the creature's top edge instead.
    @ViewBuilder
    private func attachmentGroupTile(_ group: BattlefieldCardGroup, tucked: Bool = false) -> some View {
        if arena {
            arenaAttachmentTile(group, tucked: tucked)
        } else {
            tabbedAttachmentTile(group, tucked: tucked)
        }
    }

    /// The Arena board (the reference's): each Aura and Equipment is its own card tucked behind the creature, shifted
    /// left and a little up so its name and left edge show, one step further per card; the row makes room for them on
    /// the left. A tap on the visible edge acts on it, a hold reads it. Four or more show the rest as a count.
    private func arenaAttachmentTile(_ group: BattlefieldCardGroup, tucked: Bool) -> some View {
        let attachments = Array(group.cards.dropFirst())
        let shown = Array(attachments.prefix(3))
        let step = renderedCardHeight * (tucked ? 0.0 : 0.1)
        let side = -renderedCardWidth * 0.3
        return ZStack(alignment: .bottom) {
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, card in
                battlefieldCardTile(card)
                    .offset(x: side * CGFloat(index + 1), y: -step * CGFloat(index + 1))
                    .accessibilityHint("Attached to \(group.representative.card.name). Tap to select; hold to inspect.")
            }
            battlefieldCardTile(group.representative)
                .overlay(alignment: .topTrailing) {
                    if attachments.count > shown.count {
                        Text("+\(attachments.count - shown.count)")
                            .font(.system(size: max(9, renderedCardWidth * 0.13), weight: .heavy, design: .serif))
                            .foregroundStyle(TavernPalette.label)
                            .padding(.horizontal, 4)
                            .background(TavernPalette.leather, in: Capsule())
                            .overlay(Capsule().strokeBorder(TavernPalette.brass, lineWidth: 1))
                            .offset(x: 4, y: -step * CGFloat(shown.count) - 6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(width: renderedCardWidth, height: renderedCardHeight, alignment: .bottom)
        .padding(.leading, renderedCardWidth * 0.3 * CGFloat(shown.count))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func tabbedAttachmentTile(_ group: BattlefieldCardGroup, tucked: Bool) -> some View {
        let attachments = Array(group.cards.dropFirst())
        // Two tabs at most; the rest count on the top tab.
        let shown = Array(attachments.prefix(2))
        let peek = max(11, min(14, renderedCardHeight * 0.13))
        if tucked {
            battlefieldCardTile(group.representative)
                .overlay(alignment: .top) {
                    VStack(spacing: 1) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
                            AttachmentNameTab(card: card, height: peek,
                                              more: index == shown.count - 1 ? attachments.count - shown.count : 0)
                                .contentShape(Rectangle())
                                .onCardInteraction(tap: {
                                    let targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
                                    handleCardTap(card, action: legalAction(for: card), targetable: targetable, combatHighlighted: false)
                                }, inspect: {
                                    inspectedCard = card
                                    GameHaptics.impact()
                                }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(card.card.name)
                                .accessibilityHint("Attached to \(group.representative.card.name). Tap to select; hold to inspect.")
                        }
                    }
                    .padding(.top, peek * 0.35)
                }
                .frame(width: renderedCardWidth, height: renderedCardHeight)
                .accessibilityElement(children: .contain)
        } else {
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
    }

    @ViewBuilder
    private func collapsedGroupTile(_ group: BattlefieldCardGroup) -> some View {
        let card = group.representative
        let groupIds = Set(group.cards.flatMap { [$0.instanceId, $0.id] })
        let targetable = !targetableIds.isDisjoint(with: groupIds)
        let combatHighlighted = !combatHighlightIds.isDisjoint(with: groupIds)
        let legal = group.cards.contains { legalAction(for: $0) != nil }
        let ability = group.cards.contains(where: hasAbility)
        let peeks = arena && card.card.isLand ? min(group.count - 1, 5) : 0

        ArenaBattlefieldCard(
            card: card,
            selected: false,
            legal: legal,
            ability: ability,
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .background(alignment: .topLeading) {
            if peeks > 0 {
                ForEach(1...peeks, id: \.self) { layer in
                    ArenaBattlefieldCard(card: group.cards[layer], zoneName: title, width: renderedCardWidth, height: renderedCardHeight)
                        .frame(width: renderedCardWidth, height: renderedCardHeight)
                        .offset(x: -CGFloat(layer) * renderedCardWidth * 0.12, y: CGFloat(layer) * 2)
                        .zIndex(-Double(layer))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.leading, CGFloat(peeks) * renderedCardWidth * 0.12)
        .background {
            // A big stack reads as a pile: two more frames peek out behind it (frame art only).
            if tavern, cardFrames, group.count >= Self.stackThreshold, let frame = TavernFrameKind(card).image {
                ForEach(0..<2, id: \.self) { layer in
                    Image(uiImage: frame).resizable()
                        .frame(width: renderedCardWidth, height: renderedCardHeight)
                        .brightness(-0.18 - 0.1 * Double(layer))
                        .offset(x: CGFloat(layer + 1) * 3.5, y: -CGFloat(layer + 1) * 3.5)
                        .zIndex(-Double(layer))
                }
                .allowsHitTesting(false)
            }
        }
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .boardFXCardMotion(card.instanceId)
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .overlay(alignment: .bottomLeading) {
            if group.count > peeks + 1 {
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
        }
        .onCardInteraction(tap: {
            if let next = nextChoosable(in: group) {
                // A stack being chosen from: the tap targets or declares its next card.
                handleCardTap(next.card, action: legalAction(for: next.card), targetable: next.targetable,
                              combatHighlighted: !next.targetable)
            } else {
                expandedGroupIds.insert(group.id)
                selectedCard = nil
                inspectedCard = nil
                GameHaptics.selection()
            }
        }, inspect: {
            if nextChoosable(in: group) != nil {
                // Hold to open the pile and pick a particular card; it stacks again when the choice ends.
                expandedGroupIds.insert(group.id)
                choiceOpenedGroupIds.insert(group.id)
                GameHaptics.impact()
            } else {
                inspectedCard = card
                GameHaptics.impact()
            }
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .offset(y: card.tapped == true && (permanentLayout?.rows ?? 1) == 1 ? 5 : 0)
        .accessibilityLabel("\(group.count) grouped \(card.card.name) cards in \(title)")
        .accessibilityHint(nextChoosable(in: group) != nil ? "Tap to choose the next one. Long press to open the group."
                                                           : "Tap to expand the group. Long press to inspect a card.")
        .accessibilityAction(named: Text("Expand group")) {
            expandedGroupIds.insert(group.id)
        }
        .accessibilityAction(named: Text("Inspect")) {
            inspectedCard = card
        }
    }

    @ViewBuilder
    private func battlefieldCardTile(_ card: ZoneCard) -> some View {
        let pile = layout.stackChips[card.instanceId]
        let action = legalAction(for: card)
        let targetable = !card.isPhasedOut && (targetableIds.contains(card.instanceId) || targetableIds.contains(card.id))
        let combatHighlighted = combatHighlightIds.contains(card.instanceId) || combatHighlightIds.contains(card.id)

        ArenaBattlefieldCard(
            card: card,
            selected: selectedCard?.id == card.id || isChosen(card),
            legal: action != nil,
            ability: hasAbility(card),
            targetable: targetable || combatHighlighted,
            zoneName: title,
            width: renderedCardWidth,
            height: renderedCardHeight
        )
        .frame(width: renderedCardWidth, height: renderedCardHeight)
        .overlay(alignment: .topTrailing) {
            // Chosen in a multi-card prompt: an ember seal, so it reads apart from the cards still to choose from.
            if isChosen(card) {
                Image(systemName: "checkmark")
                    .font(.system(size: max(9, renderedCardWidth * 0.11), weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: max(18, renderedCardWidth * 0.22), height: max(18, renderedCardWidth * 0.22))
                    .background(TavernPalette.ember, in: Circle())
                    .overlay(Circle().stroke(MagicPalette.antiqueGold, lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [card.instanceId: $0] }
        .boardFXCardMotion(card.instanceId)
        .opacity(!targetableIds.isEmpty && !targetable ? 0.54 : 1)
        .accessibilityAddTraits(isChosen(card) ? .isSelected : [])
        .onCardInteraction(tap: {
            handleCardTap(card, action: action, targetable: targetable, combatHighlighted: combatHighlighted)
        }, inspect: {
            inspectedCard = card
            GameHaptics.impact()
        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
        .overlay(alignment: .bottomTrailing) {
            if let pile { BattlefieldStackChip(cardWidth: renderedCardWidth) { restack(pile) } }
        }
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
        let visible = layout.rendered.count
        let contentWidth = 16 + CGFloat(visible) * renderedCardWidth + CGFloat(max(visible - 1, 0)) * 4
        return contentWidth > rowWidth
    }

    /// An activated ability other than mana that the engine offers for this permanent now.
    private func hasAbility(_ card: ZoneCard) -> Bool {
        !card.isPhasedOut && legalActions.contains {
            $0.type == "activate_ability" && ($0.sourceInstanceId == card.instanceId || $0.cardInstanceId == card.instanceId)
        }
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

/// Everything BattlefieldRow derives from its cards, sizes and selection. The tile builders read the card width about a
/// dozen times per tile, and every read used to group the whole row again; Instruments on Caleb's iPhone (2026-10-18)
/// put that grouping at about a tenth of the main thread, during scrolls and animations as well as new snapshots.
struct BattlefieldRowLayout {
    /// Cheap fields first: the synthesized == stops at the first difference, and the sets and the card array compare by
    /// storage before contents.
    struct Input: Equatable {
        let flipped: Bool
        let adaptsToDensity: Bool
        let arrangement: BattlefieldRowArrangement
        let preferredRows: Int?
        let rowWidth: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let availableHeight: CGFloat?
        let expandedGroupIds: Set<String>
        let chosenIds: Set<String>
        let targetableIds: Set<String>
        let combatHighlightIds: Set<String>
        let cards: [ZoneCard]
    }

    let groups: [BattlefieldCardGroup]
    /// The tiles in order: open piles spread out, chosen cards pulled out of theirs.
    let rendered: [BattlefieldCardGroup]
    let permanent: ArenaPermanentLayout?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    /// `rendered` split into the rows the row shows.
    let arranged: [[BattlefieldCardGroup]]
    /// The last card of each opened pile, keyed to that pile (it carries the Stack chip).
    let stackChips: [String: String]
}

/// Holds the last BattlefieldRowLayout. A reference type on purpose: it is written while the body is evaluated and must
/// not invalidate the view.
final class BattlefieldRowLayoutCache {
    private var input: BattlefieldRowLayout.Input?
    private var cached: BattlefieldRowLayout?

    func layout(_ input: BattlefieldRowLayout.Input, make: () -> BattlefieldRowLayout) -> BattlefieldRowLayout {
        if let cached, self.input == input {
            // Keep the newest storage, so the next comparison is by identity.
            self.input = input
            return cached
        }
        let made = make()
        self.input = input
        cached = made
        return made
    }
}

/// The brass chip on the last card of a pile the player spread out: tap to stack it back together.
struct BattlefieldStackChip: View {
    let cardWidth: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "square.stack.3d.down.right.fill").font(.system(size: 9, weight: .black))
                if cardWidth >= 44 { Text("Stack").font(.system(size: 10, weight: .heavy, design: .serif)) }
            }
            .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04))
            .padding(.horizontal, 6)
            .frame(minHeight: 20)
            .background(Capsule().fill(BrandTheme.brassGradient))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 10, y: 10)
        .accessibilityLabel("Stack the group")
        .accessibilityIdentifier("battlefield.restack")
    }
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
