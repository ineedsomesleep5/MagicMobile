import SwiftUI
import PhotosUI
import UIKit

struct PortraitOpponentStatusBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: GameSnapshot
    let opponentName: String
    let opponent: PlayerGameState
    let humanId: String
    let combatTargetable: Bool
    let combatTargetAction: () -> Void
    let openLog: () -> Void
    var viewZone: ((String, [ZoneCard]) -> Void)? = nil
    var selectOpponent: ((String) -> Void)? = nil
    @Environment(\.boardHUDPulse) private var hudPulse
    @Environment(\.emoteCenter) private var emoteCenter
    @Environment(\.tavernBoard) private var tavern
    @Environment(\.tavernCanvas) private var tavernCanvas
    @State private var pulse = false

    var body: some View {
        if tavern { tavernBar } else { classicBar }
    }

    private var classicBar: some View {
        HStack(spacing: 6) {
            Button { if combatTargetable { combatTargetAction() } } label: {
                HStack(spacing: 6) {
                    PlayerPortrait(player: opponent, size: 40, active: snapshot.activePlayerId == opponent.playerId,
                                   thinking: snapshot.thinkingPlayerID == opponent.playerId)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponentName).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        if opponent.isOut {
                            Text("Out").font(.title3.bold()).foregroundStyle(.gray)
                        } else {
                            BoardLifeTotal(life: opponent.life, suffix: " life").id(opponent.playerId)
                                .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(MagicPalette.antiqueGold)
                        }
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 70, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(combatTargetable ? Color.red : .clear, lineWidth: 2))
            .accessibilityLabel(opponent.isOut ? "\(opponentName), out of the game" : "\(opponentName), \(opponent.life) life")
            turnColumn.frame(maxWidth: .infinity, alignment: .leading)
            trailingControls
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(.horizontal, 5)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(turn.color.opacity(0.75), lineWidth: 1.5))
        .shadow(color: turn.color.opacity(0.35), radius: 8)
        .shadow(color: .black.opacity(0.34), radius: 10, y: 5)
        .overlay(alignment: .bottomLeading) {
            if let emoteCenter {
                OpponentEmoteSlot(center: emoteCenter, snapshot: snapshot, focusedID: opponent.playerId)
                    .fixedSize()
                    .offset(x: 8, y: 44)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: turn.owner)
        .onChange(of: hudPulse) { _, _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.4)) { pulse = false }
            }
        }
    }

    private var turnColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(turn.color).frame(width: 7, height: 7).shadow(color: turn.color, radius: 3)
                // The phase drops first when a pod's extra controls leave less room.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        Text(turn.owner).font(.caption.weight(.black)).foregroundStyle(turn.color)
                        Text("· \((snapshot.step ?? snapshot.phase).arenaPhaseTitle)").font(.caption.bold())
                    }
                    Text(turn.owner).font(.caption.weight(.black)).foregroundStyle(turn.color)
                    Text(turn.owner).font(.caption2.weight(.black)).foregroundStyle(turn.color)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(turn.color.opacity(pulse ? 0.35 : 0), in: Capsule())
            .scaleEffect(pulse ? 1.06 : 1, anchor: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("board.turn.owner")
            Group {
                if BoardResponseCue.make(snapshot) == nil, let thinker = snapshot.thinkingPlayerID {
                    ThinkingLabel(name: snapshot.playerLabel(thinker))
                        .foregroundStyle(BoardTurnColors.opponent)
                } else if BoardResponseCue.make(snapshot) == nil, snapshot.isSpectating {
                    Text("You’re watching")
                } else {
                    Text(BoardResponseCue.make(snapshot)?.title ?? snapshot.priorityStatusText)
                        .foregroundStyle(BoardResponseCue.make(snapshot) == nil ? MagicPalette.parchment : MagicPalette.antiqueGold)
                }
            }
            .font(.caption2.bold()).lineLimit(2).minimumScaleFactor(0.75)
            .accessibilityIdentifier("board.response.status")
        }
    }

    @ViewBuilder private var trailingControls: some View {
        if let selectOpponent { OpponentFocusMenu(snapshot: snapshot, selectOpponent: selectOpponent) }
        BoardPlayerEffects(player: opponent, attachments: BattlefieldAttachments.enchanting(playerID: opponent.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: viewZone)
        if let viewZone { PlayerZoneMenu(player: opponent, viewZone: viewZone) }
        Button(action: openLog) { Image(systemName: "text.book.closed").frame(width: 44, height: 44) }
            .accessibilityLabel("Game log")
    }

    /// Walnut Tavern: the opponent's commander medallion sits in the table's top socket and
    /// opens their zones (and, in a pod, the other opponents); while they can be attacked a
    /// tap declares the attack. Turn and priority are engraved on the leather band to the
    /// left; their hand shows as card backs and the log is a brass ring to the right.
    private var tavernBar: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let canvas = tavernCanvas {
                let center = TavernDesign.opponentMedallion
                ZStack {
                    // Name, turn and priority on a leather nameplate in brass trim.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponentName)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(TavernPalette.parchment.opacity(0.9))
                        turnColumn
                    }
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(width: canvas.tavernLength(118), alignment: .leading)
                    .modifier(TavernPanelChrome(tavern: true, cornerRadius: 7))
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    .tavernPosition(CGPoint(x: center.x - 110, y: center.y + 8), canvas: canvas, origin: origin)
                    TavernCardBackFan(count: opponent.zones.visibleHandCount)
                        .tavernPosition(CGPoint(x: center.x, y: center.y - 40), canvas: canvas, origin: origin)
                    // The step of the turn mirrors the nameplate; the log is in the controls menu.
                    TavernPhasePlate(step: snapshot.step ?? snapshot.phase, turn: snapshot.turn,
                                     width: canvas.tavernLength(118))
                        .tavernPosition(CGPoint(x: center.x + 110, y: center.y + 8), canvas: canvas, origin: origin)
                    // Counters, commander damage and attached cards are in the medallion's
                    // pop-over; poison and the worst commander damage show here too.
                    TavernStatusGlance(summary: PlayerStatusSummary(player: opponent, snapshot: snapshot))
                        .tavernPosition(CGPoint(x: center.x + 110, y: center.y + 46), canvas: canvas, origin: origin)
                    opponentMedallion(diameter: canvas.tavernLength(TavernDesign.opponentHoleRadius * 2))
                        .tavernPosition(center, canvas: canvas, origin: origin)
                }
            }
        }
        .foregroundStyle(TavernPalette.parchment)
        .overlay(alignment: .bottomLeading) {
            if let emoteCenter {
                OpponentEmoteSlot(center: emoteCenter, snapshot: snapshot, focusedID: opponent.playerId)
                    .fixedSize()
                    .offset(x: 8, y: 44)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: turn.owner)
        .onChange(of: hudPulse) { _, _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.4)) { pulse = false }
            }
        }
    }

    @ViewBuilder
    private func opponentMedallion(diameter: CGFloat) -> some View {
        let medallion = TavernMedallion(diameter: diameter, life: opponent.isOut ? nil : opponent.life,
                                        active: snapshot.activePlayerId == opponent.playerId, targetable: combatTargetable) {
            PlayerPortrait(player: opponent, size: diameter, active: false,
                           thinking: snapshot.thinkingPlayerID == opponent.playerId)
        }
        .opacity(opponent.isOut ? 0.45 : 1)
        .frame(width: diameter + 8, height: diameter + 8)
        let label = opponent.isOut ? "\(opponentName), out of the game" : "\(opponentName), \(opponent.life) life"
        if combatTargetable || viewZone == nil {
            Button { if combatTargetable { combatTargetAction() } } label: { medallion }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(combatTargetable ? "Attacks this player" : "")
        } else if let viewZone {
            let opponents = BoardOpponentFocus.opponents(in: snapshot)
            PlayerZoneMenu(
                player: opponent, viewZone: viewZone,
                customLabel: AnyView(medallion),
                accessibilityOverride: (label, "board.zones.\(opponent.playerId)"),
                menuArrowEdge: .top,
                statusSnapshot: snapshot,
                swapOpponents: opponents,
                swap: selectOpponent
            )
        }
    }

    /// Whose turn it is, colored so a glance answers it: gold for you, blue for opponents.
    private var turn: (owner: String, color: Color) {
        guard let active = snapshot.activePlayerId else { return ("", MagicPalette.antiqueGold) }
        return snapshot.isViewer(active)
            ? ("YOUR TURN", MagicPalette.antiqueGold)
            : ("\(snapshot.playerLabel(active).uppercased())’S TURN", BoardTurnColors.opponent)
    }
}

enum BoardTurnColors {
    static let opponent = Color(red: 0.62, green: 0.74, blue: 1)
}

struct BoardHUDPulseKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// Increments when a phase pill lands in the top bar, which then flashes its turn label.
    var boardHUDPulse: Int {
        get { self[BoardHUDPulseKey.self] }
        set { self[BoardHUDPulseKey.self] = newValue }
    }
}

struct PortraitBattlefieldRowPlan: Equatable {
    let rows: [[ZoneCard]]
    let cardsPerRow: Int
    let overflowsHorizontally: Bool
}

enum PortraitBattlefieldRowPlanner {
    static func plan(cards: [ZoneCard], rowWidth: CGFloat, cardWidth: CGFloat, maxRows: Int = 3) -> PortraitBattlefieldRowPlan {
        guard !cards.isEmpty else {
            return PortraitBattlefieldRowPlan(rows: [[]], cardsPerRow: 1, overflowsHorizontally: false)
        }
        let visibleCards = Array(cards.prefix(10))
        let rowCount: Int
        if visibleCards.count <= 4 {
            rowCount = 1
        } else if visibleCards.count <= 7 {
            rowCount = min(maxRows, 2)
        } else {
            rowCount = min(maxRows, 3)
        }
        let baseRowCount = max(rowCount, 1)
        let baseSize = visibleCards.count / baseRowCount
        let remainder = visibleCards.count % baseRowCount
        var rows: [[ZoneCard]] = []
        var index = 0
        for rowIndex in 0..<baseRowCount {
            let size = baseSize + (rowIndex < remainder ? 1 : 0)
            guard size > 0 else { continue }
            rows.append(Array(visibleCards[index..<(index + size)]))
            index += size
        }
        if cards.count > 10, !rows.isEmpty {
            rows[rows.count - 1].append(contentsOf: cards.dropFirst(10))
        }
        return PortraitBattlefieldRowPlan(
            rows: rows,
            cardsPerRow: rows.map(\.count).max() ?? 1,
            overflowsHorizontally: cards.count > 10
        )
    }
}

struct PortraitOverlapLayoutPlan: Equatable {
    let count: Int
    let cardWidth: CGFloat
    let containerWidth: CGFloat
    let visibleLimit: Int
    let stride: CGFloat
    let contentWidth: CGFloat
    let needsScrolling: Bool

    func xOffset(for index: Int) -> CGFloat {
        let effectiveIndex = CGFloat(max(index, 0))
        let start = contentWidth > containerWidth ? 8 : max((containerWidth - visibleContentWidth) / 2, 0)
        return start + effectiveIndex * stride
    }

    private var visibleContentWidth: CGFloat {
        guard count > 0 else { return 0 }
        let visibleCount = CGFloat(min(count, visibleLimit))
        return cardWidth + max(visibleCount - 1, 0) * stride
    }
}

enum PortraitOverlapLayout {
    static func plan(
        count: Int,
        containerWidth: CGFloat,
        cardWidth: CGFloat,
        visibleLimit: Int = 10,
        minVisibleWidth: CGFloat = 30,
        spacing: CGFloat = 6
    ) -> PortraitOverlapLayoutPlan {
        guard count > 0 else {
            return PortraitOverlapLayoutPlan(
                count: 0,
                cardWidth: cardWidth,
                containerWidth: containerWidth,
                visibleLimit: visibleLimit,
                stride: cardWidth + spacing,
                contentWidth: max(containerWidth, 0),
                needsScrolling: false
            )
        }
        let visibleCount = min(count, max(visibleLimit, 1))
        let naturalStride = cardWidth + spacing
        let fittingStride = visibleCount > 1 ? max((containerWidth - cardWidth) / CGFloat(visibleCount - 1), 1) : naturalStride
        let stride = min(naturalStride, max(fittingStride, minVisibleWidth))
        let visibleContentWidth = cardWidth + CGFloat(max(visibleCount - 1, 0)) * stride
        let needsScrolling = count > visibleLimit || visibleContentWidth > containerWidth
        let contentWidth = needsScrolling && count > visibleLimit
            ? cardWidth + CGFloat(max(count - 1, 0)) * stride
            : min(max(visibleContentWidth, cardWidth), max(containerWidth, cardWidth))
        return PortraitOverlapLayoutPlan(
            count: count,
            cardWidth: cardWidth,
            containerWidth: containerWidth,
            visibleLimit: visibleLimit,
            stride: stride,
            contentWidth: contentWidth,
            needsScrolling: needsScrolling
        )
    }
}

struct PortraitBattlefieldPermanentGroup: View {
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
    let availableHeight: CGFloat
    var allowsManaUndo = false
    var manaPaymentActive = false
    let runAction: (LegalAction) -> Void
    let runTargetAction: (ZoneCard) -> Void
    let runCombatCardAction: (ZoneCard) -> Bool

    var body: some View {
        BattlefieldRow(
            title: title, cards: cards, legalActions: legalActions,
            targetableIds: targetableIds, combatHighlightIds: combatHighlightIds,
            selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: flipped,
            cardWidth: cardWidth, cardHeight: cardHeight, rowWidth: rowWidth, adaptsToDensity: true,
            availableHeight: availableHeight, arrangement: .portraitPermanents,
            allowsManaUndo: allowsManaUndo, manaPaymentActive: manaPaymentActive,
            runAction: runAction, runTargetAction: runTargetAction, runCombatCardAction: runCombatCardAction
        )
    }
}

struct PortraitScrollScrubber: View {
    let progress: CGFloat
    let visible: Bool
    let drag: (CGFloat) -> Void
    @GestureState private var dragStartProgress: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 1)
            let thumbWidth = HandScrubberGeometry.thumbWidth(trackWidth: trackWidth)
            let travel = max(trackWidth - thumbWidth, 1)
            Capsule()
                .fill(.white.opacity(visible ? 0.14 : 0.0))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(MagicPalette.antiqueGold.opacity(visible ? 0.78 : 0.0))
                        .frame(width: thumbWidth)
                        .offset(x: travel * min(max(progress, 0), 1))
                }
                .frame(height: 8)
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragStartProgress) { _, start, _ in
                            if start == nil { start = progress }
                        }
                        .onChanged { value in
                            guard visible else { return }
                            let thumbStart = travel * min(max(dragStartProgress ?? progress, 0), 1)
                            let withinThumb = value.startLocation.x - thumbStart
                            let grabOffset = (0...thumbWidth).contains(withinThumb) ? withinThumb : thumbWidth / 2
                            drag(HandScrubberGeometry.progress(location: value.location.x, trackWidth: trackWidth,
                                                               grabOffset: grabOffset))
                        }
                )
        }
        .frame(height: 44)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scroll hand")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
        .accessibilityIdentifier("board.hand.scrubber")
        .accessibilityHidden(!visible)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: drag(min(1, progress + 0.1))
            case .decrement: drag(max(0, progress - 0.1))
            @unknown default: break
            }
        }
    }
}

struct HandViewportKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct PortraitHandRow: View {
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let pendingCardInstanceId: String?
    @Binding var interactionState: GameBoardInteractionState
    let playerDropZone: CGRect
    @Binding var isOverPlayerDropZone: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let rowWidth: CGFloat
    let onDropFeedback: (String) -> Void
    let onActionChoice: ([LegalAction], String) -> Void
    let runAction: (LegalAction) -> Void
    /// A spectator's stand-in: their hand stays hidden and only its size shows.
    var hiddenCount: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// On the tavern table the hand rests as a full, curved fan: no tuck, no expand button.
    @Environment(\.tavernBoard) private var tavern
    @State private var draggingCardId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartCenter: CGPoint = .zero
    @State private var handCardBounds: [String: CGRect] = [:]
    @State private var handViewport = CGRect.zero
    @State private var handExpanded = false
    @AppStorage(BoardFXLevel.key) private var boardFXLevel = BoardFXLevel.defaultValue
    @StateObject private var handScroll = HandScrollController()

    /// Arena-style fan: cards tilt and dip away from the visible center of the hand.
    private var fansHand: Bool { !handExpanded && BoardFXLevel(rawValue: boardFXLevel) != .off && !GameBoardMotion.reduced(reduceMotion) }

    private var handSpacing: CGFloat { ArenaHandLayout.spacing(count: cards.count, width: rowWidth, cardWidth: cardWidth, expanded: handExpanded) }
    private var contentWidth: CGFloat { CGFloat(cards.count) * cardWidth + CGFloat(max(cards.count - 1, 0)) * handSpacing }

    /// Height of the hand when it is not expanded: tucked classically, whole on the tavern table.
    private var restingHeight: CGFloat {
        tavern ? ArenaHandLayout.tavernHeight(cardHeight: cardHeight) : ArenaHandLayout.restingHeight(cardHeight: cardHeight)
    }

    var body: some View {
        let layout = handExpanded
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(ZStackLayout(alignment: .bottom))
        Group {
            layout {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: handSpacing) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            let playableActions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
                            let selected = selectedCard?.id == card.id
                            let isDragging = draggingCardId == card.id
                            CardTile(
                                card: card,
                                selected: selected,
                                pending: pendingCardInstanceId == card.instanceId,
                                legal: playableActions.contains { $0.type == "play_land" },
                                castOffered: playableActions.contains { $0.type == "cast_spell" },
                                zoneName: "Hand",
                                width: cardWidth,
                                height: cardHeight
                            )
                            .overlay(alignment: .topTrailing) {
                                HandManaCost(cost: card.card.manaCost ?? playableActions.first?.manaCost)
                                    .offset(y: -15).allowsHitTesting(false).accessibilityHidden(true)
                            }
                            .id(card.id)
                            .background { GeometryReader { geometry in
                                Color.clear.preference(key: HandCardBoundsKey.self,
                                    value: [card.id: geometry.frame(in: .named("portrait-board"))])
                            } }
                            .visualEffect { [fansHand, tavern] content, proxy in
                                let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                                let viewport = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? frame.width
                                let spread = fansHand ? min(max((frame.midX - viewport / 2) / max(viewport / 2, 1), -1), 1) : 0
                                return content
                                    .rotationEffect(.degrees(spread * (tavern ? 11 : 7)), anchor: .bottom)
                                    .offset(y: spread * spread * (tavern ? 18 : 9))
                            }
                            .scaleEffect(selected ? 1.05 : 1.0)
                            .offset(y: selected ? -10 : 0)
                            .opacity(isDragging ? 0 : 1)
                            .zIndex(isDragging ? 1000 : selected ? 900 : Double(index))
                            .animation(GameBoardMotion.reduced(reduceMotion) ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isDragging)
                            .accessibilityHint("Tap to expand your hand. Hold to inspect. Drag upward to your battlefield to play.")
                            .accessibilityAction { selectedCard = nil; inspectedCard = card }
                            .accessibilityAction(named: "Inspect card") { selectedCard = nil; inspectedCard = card }
                            .accessibilityAction(named: "Play card") {
                                switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: true) {
                                case let .submit(action): runAction(action)
                                case let .requiresChoice(actions, message): onActionChoice(actions, message)
                                case let .rejected(message): onDropFeedback(message)
                                case .ignored: break
                                }
                            }
                            .overlay {
                                HandCardPan(changed: { translation, start in
                                        if draggingCardId == nil {
                                            guard let bounds = handCardBounds[card.id] else { return }
                                            dragStartCenter = CGPoint(x: bounds.midX, y: bounds.midY)
                                            GameAudio.shared.play(.cardPickup)
                                        }
                                        selectedCard = nil
                                        inspectedCard = nil
                                        draggingCardId = card.id
                                        dragOffset = translation
                                        let point = CGPoint(x: dragStartCenter.x - cardWidth / 2 + start.x + translation.width,
                                                            y: dragStartCenter.y - cardHeight / 2 + start.y + translation.height)
                                        isOverPlayerDropZone = playerDropZone.contains(point)
                                        interactionState.mode = .draggingCard(
                                            cardId: card.instanceId,
                                            legalActionIds: playableActions.map(\.id)
                                        )
                                    }, ended: { translation, start, cancelled in
                                        guard draggingCardId == card.id else { return }
                                        selectedCard = nil
                                        let point = CGPoint(x: dragStartCenter.x - cardWidth / 2 + start.x + translation.width,
                                                            y: dragStartCenter.y - cardHeight / 2 + start.y + translation.height)
                                        let shouldPlay = !cancelled && playerDropZone.contains(point)
                                        draggingCardId = nil
                                        dragOffset = .zero
                                        isOverPlayerDropZone = false
                                        guard shouldPlay else {
                                            interactionState.mode = .selectedCard(cardId: card.instanceId)
                                            return
                                        }
                                        switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: shouldPlay) {
                                        case .ignored:
                                            interactionState.mode = .selectedCard(cardId: card.instanceId)
                                        case let .rejected(message):
                                            onDropFeedback(message)
                                            interactionState.mode = .selectedCard(cardId: card.instanceId)
                                        case let .requiresChoice(actions, message):
                                            onDropFeedback(message)
                                            onActionChoice(actions, message)
                                            interactionState.mode = .selectedCard(cardId: card.instanceId)
                                        case let .submit(action):
                                            interactionState.mode = .awaitingCastSnapshot(actionId: action.id)
                                            if action.type == "cast_spell" { GameAudio.shared.play(.cardPlay) }
                                            runAction(action)
                                        }
                                    }, inspect: { selectedCard = nil; inspectedCard = card }, tap: {
                                        if handExpanded || tavern { selectedCard = nil; inspectedCard = card }
                                        else { withAnimation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2)) { handExpanded = true } }
                                    }, releaseInspection: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                            }
                        }
                    }
                    .padding(.top, 18)
                    .frame(height: cardHeight + 20, alignment: .topLeading)
                    .padding(.horizontal, 4)
                    .background(HandScrollConnection(controller: handScroll))
                }
                .frame(height: handExpanded ? cardHeight + 20 : restingHeight, alignment: .top)
                // Tuck the resting hand at the bottom only; the playable glow, cost badges
                // and fan tilt may draw above the row.
                .scrollClipDisabled()
                .mask { Rectangle().padding(.top, -48).padding(.horizontal, -12).padding(.bottom, tavern ? -40 : 0) }
                .accessibilityIdentifier("board.hand.scroll")
                .background { GeometryReader { geometry in
                    Color.clear.preference(key: HandViewportKey.self, value: geometry.frame(in: .named("portrait-board")))
                } }

                if !tavern {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(GameBoardMotion.reduced(reduceMotion) ? nil : .easeInOut(duration: 0.2)) { handExpanded.toggle() }
                    } label: {
                        Label("Hand · \(hiddenCount ?? cards.count)", systemImage: handExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2.bold()).padding(.horizontal, 12)
                            .foregroundStyle(MagicPalette.parchment)
                            .frame(minHeight: 44).background(.black.opacity(0.78), in: Capsule())
                            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.55), lineWidth: 1))
                    }
                    .accessibilityLabel(handExpanded ? "Tuck hand" : "Expand hand")
                    .accessibilityIdentifier("board.hand.expand")
                    PortraitScrollScrubber(progress: handScroll.progress, visible: contentWidth + 8 > rowWidth + 1,
                                           drag: handScroll.scroll)
                }
                }
            }
            .frame(height: restingHeight, alignment: .bottom)
            .onPreferenceChange(HandCardBoundsKey.self) { handCardBounds = $0; handScroll.refreshProgress() }
            .onPreferenceChange(HandViewportKey.self) { handViewport = $0; handScroll.refreshProgress() }
            .overlay {
                GeometryReader { geometry in
                    if let draggingCardId, let card = cards.first(where: { $0.id == draggingCardId }) {
                        let origin = geometry.frame(in: .named("portrait-board")).origin
                        let actions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
                        CardTile(card: card, selected: false, pending: pendingCardInstanceId == card.instanceId,
                                 legal: actions.contains { $0.type == "play_land" }, castOffered: actions.contains { $0.type == "cast_spell" },
                                 zoneName: "Hand", width: cardWidth, height: cardHeight)
                            .position(x: dragStartCenter.x + dragOffset.width - origin.x,
                                      y: dragStartCenter.y + dragOffset.height - origin.y)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: cards.map(\.id)) { _, ids in
                if let draggingCardId, !ids.contains(draggingCardId) {
                    self.draggingCardId = nil
                    dragOffset = .zero
                    isOverPlayerDropZone = false
                }
            }
            .onDisappear {
                draggingCardId = nil
                dragOffset = .zero
                isOverPlayerDropZone = false
            }
        }
    }
}

struct NativeTurnControl {
    let canEndTurn: Bool
    let canSkipResponses: Bool
    let canSkipToMyTurn: Bool
    let isAutoPassing: Bool
    let status: String?
    let endTurn: () -> Void
    let skipResponses: () -> Void
    let skipToMyTurn: () -> Void
    let stop: () -> Void
}

struct BoardZoneInspectionActionKey: EnvironmentKey {
    static let defaultValue: ((BoardZoneReference) -> Void)? = nil
}

struct NativeTurnControlKey: EnvironmentKey {
    static let defaultValue: NativeTurnControl? = nil
}

extension EnvironmentValues {
    var boardZoneInspectionAction: ((BoardZoneReference) -> Void)? {
        get { self[BoardZoneInspectionActionKey.self] }
        set { self[BoardZoneInspectionActionKey.self] = newValue }
    }
    var nativeTurnControl: NativeTurnControl? {
        get { self[NativeTurnControlKey.self] }
        set { self[NativeTurnControlKey.self] = newValue }
    }
}
