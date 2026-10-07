import SwiftUI
import PhotosUI
import UIKit

struct ImmersivePlayShell: View {
    let snapshot: GameSnapshot?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let playerDisplayName: String
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let lastActionRejection: ActionRejectionNotice?
    let commandFailure: CardChoiceCommandFailure?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let checkBridgeHealth: () async -> EngineHealth?
    let newGame: () -> Void
    let quitGame: () -> Void
    let loadProtocolDebug: (String) async throws -> XmageProtocolDebug
    @Binding var portraitModeEnabled: Bool
    let viewZone: (String, [ZoneCard]) -> Void

    var body: some View {
        NativeGameView(
            snapshot: snapshot,
            selectedCard: $selectedCard,
            inspectedCard: $inspectedCard,
            playerDisplayName: playerDisplayName,
            avatarData: avatarData,
            pendingActionId: pendingActionId,
            pendingCardInstanceId: pendingCardInstanceId,
            lastActionRejection: lastActionRejection,
            commandFailure: commandFailure,
            liveUpdateStatus: liveUpdateStatus,
            onInteractionFeedback: onInteractionFeedback,
            runAction: runAction,
            runCommand: runCommand,
            refreshGame: refreshGame,
            reconnectGame: reconnectGame,
            checkBridgeHealth: checkBridgeHealth,
            newGame: newGame,
            quitGame: quitGame,
            loadProtocolDebug: loadProtocolDebug,
            portraitModeEnabled: $portraitModeEnabled,
            viewZone: viewZone
        )
    }
}

@MainActor
enum GameHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

struct OpponentFocusMenu: View {
    let snapshot: GameSnapshot
    let selectOpponent: (String) -> Void

    var body: some View {
        if BoardOpponentFocus.opponents(in: snapshot).count > 1 {
            Menu {
                ForEach(BoardOpponentFocus.opponents(in: snapshot)) { player in
                    Button {
                        selectOpponent(player.playerId)
                    } label: {
                        Label(snapshot.playerLabel(player.playerId), systemImage: snapshot.opponent?.playerId == player.playerId ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .frame(width: 44, height: 44)
                    .background(MagicPalette.iron.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Choose opponent to view")
            .accessibilityValue(snapshot.playerLabel(snapshot.opponent?.playerId))
            .accessibilityHint("Changes the displayed opponent battlefield")
            .accessibilityIdentifier("board.opponentFocus")
        }
    }
}

struct NativeGameView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: GameSnapshot?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let playerDisplayName: String
    let avatarData: Data?
    let pendingActionId: String?
    let pendingCardInstanceId: String?
    let lastActionRejection: ActionRejectionNotice?
    let commandFailure: CardChoiceCommandFailure?
    let liveUpdateStatus: String
    let onInteractionFeedback: (String) -> Void
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let refreshGame: () -> Void
    let reconnectGame: () -> Void
    let checkBridgeHealth: () async -> EngineHealth?
    let newGame: () -> Void
    let quitGame: () -> Void
    let loadProtocolDebug: (String) async throws -> XmageProtocolDebug
    @Binding var portraitModeEnabled: Bool
    let viewZone: (String, [ZoneCard]) -> Void
    @State private var isLogOpen = false
    @State private var isGameMenuOpen = false
    @State private var isTavernStackOpen = false
    @AppStorage(BoardAppearancePreference.key) private var boardAppearance = BoardAppearancePreference.defaultValue
    @State private var isPromptInspectorOpen = false
    @State private var protocolDebug: XmageProtocolDebug?
    @State private var protocolDebugError: String?
    @State private var isProtocolDebugLoading = false
    @State private var gameMenuConfirmation: GameMenuConfirmation?
    @State private var isOverPlayerDropZone = false
    @State private var interactionState = GameBoardInteractionState.idle
    @State private var inspectingZoneTitle: String? = nil
    @State private var inspectingZoneCards: [ZoneCard] = []
    @State private var isPromptDetailOpen = false
    @State private var isCardChoiceOpen = false
    @State private var committedCardChoice: CardChoicePlan?
    @State private var cardChoiceCompletionTask: Task<Void, Never>?
    @State private var reviewCardChoiceAfterPending = false
    @State private var isLandscapeStackOpen = false
    @State private var inspectingZoneReference: BoardZoneReference?
    @State private var dragActionChoice: DragActionChoice?
    @State private var combatSelection = CombatSelectionState()
    @State private var combatPreviewArrows: [CombatArrow] = []
    /// Creatures you declared as attackers or blockers this step, oldest first: Back takes
    /// back the latest.
    @State private var combatDeclarationOrder: [String] = []
    /// Which opponent the top of the board shows; it follows the turn (BoardFocusTracker).
    @State private var focusTracker = BoardFocusTracker()
    @AppStorage(BoardFocusTracker.followTurnsKey) private var followTurns = true
    @State private var lastTurnCueKey: String?
    @State private var showsTurnCue = false
    /// Game, turn and active player of the last turn-start banner.
    @State private var lastTurnBannerKey: String?
    @State private var lastTurnSoundKey: String?
    @State private var showsTurnBanner = false
    /// While the turn banner holds the centre of the board, showcases wait (BoardFXDirector.ingest).
    @State private var turnBannerEndsAt: Date?
    /// The phase pill is flying up into the top bar.
    @State private var phaseCueMerging = false
    @State private var hudPulse = 0
    @State private var aiWaitBeganAt = Date()
    @State private var aiWaitKey = ""
    @State private var didAutoRefreshAIWaitKey: String?
    @State private var didAutoReconnectAIWaitKey: String?
    @State private var didAutoDiagnoseAIWaitKey: String?
    @State private var boardFX = BoardFXDirector()
    @State private var boardFXClock = BoardFXClock()
    @State private var boardShake: CGFloat = 0
    @State private var boardShakeAmplitude: CGFloat = 6
    @State private var hitVignette = 0.0
    @State private var gameStats = GameStats()
    @State private var combatLogReasons = CombatLogReasons()
    @AppStorage(BoardFXLevel.key) private var boardFXLevel = BoardFXLevel.defaultValue
    @AppStorage(BoardFXSound.key) private var boardSoundsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The starting roll covers the board and answers its starting-player prompt itself.
    @Environment(\.startingRollVisible) private var startingRollVisible
    @Environment(\.emoteCenter) private var emoteCenter

    private func openPromptDetails() {
        if let snapshot, PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil {
            isCardChoiceOpen = true
        } else {
            isPromptDetailOpen = true
        }
    }

    private func advanceCommittedCardChoice() {
        guard var plan = committedCardChoice, let snapshot else { return }
        if snapshot.promptEnvelopeV2 == nil && pendingActionId == nil && plan.lastPrompt != nil {
            if cardChoiceCompletionTask == nil {
                let lastPrompt = plan.lastPrompt
                cardChoiceCompletionTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    if committedCardChoice?.lastPrompt == lastPrompt,
                       self.snapshot?.promptEnvelopeV2 == nil, pendingActionId == nil {
                        committedCardChoice = nil
                    }
                    cardChoiceCompletionTask = nil
                }
            }
            return
        }
        cardChoiceCompletionTask?.cancel()
        cardChoiceCompletionTask = nil
        let command = plan.next(in: snapshot, pending: pendingActionId != nil)
        committedCardChoice = plan.stopped ? nil : plan
        if plan.stopped {
            isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil
            isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
        }
        if let command {
            runCommand(command, "Apply card choice", "card-plan-\(command.promptId ?? "")-\(command.messageId ?? 0)")
        }
    }

    private func cancelCommittedCardChoice() {
        cardChoiceCompletionTask?.cancel()
        cardChoiceCompletionTask = nil
        committedCardChoice = nil
        if let snapshot {
            if pendingActionId != nil {
                reviewCardChoiceAfterPending = true
                isCardChoiceOpen = false
                isPromptDetailOpen = false
            } else {
                isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
            }
        }
    }

    private func handleCardChoicePendingChange(from oldValue: String?, to newValue: String?, snapshot: GameSnapshot) {
        guard newValue == nil else { return }
        if reviewCardChoiceAfterPending {
            reviewCardChoiceAfterPending = false
            isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil
            isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
        } else if oldValue != nil, committedCardChoice?.submittedPromptIsUnchanged(in: snapshot) == true {
            cancelCommittedCardChoice()
        } else {
            advanceCommittedCardChoice()
        }
    }

    private func handleCardChoiceFailureChange(from oldValue: CardChoiceCommandFailure?,
                                               to newValue: CardChoiceCommandFailure?) {
        if committedCardChoice != nil,
           CardChoiceCommandFailure.isNewFailure(from: oldValue, to: newValue) {
            cancelCommittedCardChoice()
        }
    }

    private func commitCardChoicePlan(_ plan: CardChoicePlan) {
        cardChoiceCompletionTask?.cancel()
        cardChoiceCompletionTask = nil
        reviewCardChoiceAfterPending = false
        committedCardChoice = plan
        isCardChoiceOpen = false
        advanceCommittedCardChoice()
    }

    private func localViewZone(title: String, cards: [ZoneCard]) {
        if title.hasPrefix("Enchanting "), let snapshot,
           let playerID = snapshot.players.first(where: { player in
               Set(ZoneCard.enchanting(playerID: player.playerId, cards: snapshot.players.flatMap { $0.zones.battlefield }).map(\.id)) == Set(cards.map(\.id))
           })?.playerId, !cards.isEmpty {
            inspectBoardZone(.playerEnchantments(playerID: playerID))
            return
        }
        inspectingZoneReference = nil
        inspectingZoneTitle = title
        inspectingZoneCards = cards
    }

    private func inspectBoardZone(_ reference: BoardZoneReference) {
        guard let snapshot else { return }
        inspectingZoneReference = reference
        inspectingZoneTitle = reference.title(in: snapshot)
        inspectingZoneCards = reference.cards(in: snapshot)
        inspectedCard = nil
    }

    private var boardOverlayTransition: AnyTransition {
        GameBoardMotion.reduced(accessibilityReduceMotion) ? .opacity : .scale.combined(with: .opacity)
    }

    private func clearBoardSelection() {
        guard selectedCard != nil || inspectedCard != nil else { return }
        selectedCard = nil
        inspectedCard = nil
        GameHaptics.selection()
        onInteractionFeedback("Selection cleared")
    }

    /// The landscape battlefield: both players' lanes, the centre strip, the hand and their
    /// overlays. The classic board frames it between its side columns; the tavern board lays
    /// it on the mat of the landscape plate.
    @ViewBuilder
    private func landscapeCenterColumn(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState) -> some View {
        GeometryReader { proxy in
            let metrics = BattlefieldLayoutMetrics(proxy: proxy,
                centerControlsVisible: BoardDecisionPresentation.needsCenterSpace(snapshot, hasRejection: lastActionRejection != nil))
            let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
            let combatHighlights = CombatHighlightSet(
                selection: combatSelection,
                actions: snapshot.legalActions ?? [],
                combatGroups: snapshot.xmage?.combat ?? []
            )
            let shouldShowCompactPrompt = !startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId)
            let derivedInteractionMode = GameBoardInteractionState.mode(
                for: snapshot,
                pendingActionId: pendingActionId,
                selectedCard: selectedCard
            )

            ZStack {
                BattlefieldRow(title: "Opponent board", cards: landscapePermanents(opponent.zones.battlefield, resources: false), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.opponentBattlefieldRect.width, adaptsToDensity: true, availableHeight: metrics.opponentBattlefieldRect.height, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentBattlefieldRect.width, height: metrics.opponentBattlefieldRect.height)
                    .position(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)

                BattlefieldRow(title: "Opponent lands", cards: landscapePermanents(opponent.zones.battlefield, resources: true), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.opponentLandsRect.width, adaptsToDensity: true, availableHeight: metrics.opponentLandsRect.height, arrangement: .landscapeResources, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentLandsRect.width, height: metrics.opponentLandsRect.height)
                    .position(x: metrics.opponentLandsRect.midX, y: metrics.opponentLandsRect.midY)

                if !isTavernBoard {
                    Rectangle()
                        .fill(.white.opacity(0.13))
                        .frame(width: max(metrics.centerStripRect.width - 28, 80), height: 1.5)
                        .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)
                }

                BattlefieldRow(title: "Your board", cards: landscapePermanents(human.zones.battlefield, resources: false), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.playerBattlefieldRect.width, adaptsToDensity: true, availableHeight: metrics.playerBattlefieldRect.height, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerBattlefieldRect.width, height: metrics.playerBattlefieldRect.height)
                    .position(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)

                BattlefieldRow(title: "Your lands", cards: landscapePermanents(human.zones.battlefield, resources: true), legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.playerLandsRect.width, adaptsToDensity: true, availableHeight: metrics.playerLandsRect.height, arrangement: .landscapeResources, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerLandsRect.width, height: metrics.playerLandsRect.height)
                    .position(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        if InlinePaymentPromptState.isActive(in: snapshot) {
                            InlinePaymentPromptBar(
                                snapshot: snapshot,
                                pendingActionId: pendingActionId,
                                runAction: runAction,
                                runCommand: runCommand,
                                openDetails: openPromptDetails
                            )
                            .frame(maxWidth: .infinity)
                        } else if BoardDecisionPresentation.showsGuidance(snapshot) {
                            PromptPill(snapshot: snapshot, combatSelection: combatSelection,
                                       back: combatBackAction(in: snapshot))
                                .frame(maxWidth: .infinity)
                        }

                        let revealedCards = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                        let lookedAtCards = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                        if !revealedCards.isEmpty {
                            FloatingZoneChip(title: "Revealed", count: revealedCards.count, icon: "eye") {
                                inspectBoardZone(.collection(.revealed))
                            }
                        }
                        if !lookedAtCards.isEmpty {
                            FloatingZoneChip(title: "Looked", count: lookedAtCards.count, icon: "eye.trianglebadge.exclamationmark") {
                                inspectBoardZone(.collection(.lookedAt))
                            }
                        }
                    }
                    if let lastActionRejection {
                        ActionRejectionInlineView(notice: lastActionRejection) {
                            recover(from: lastActionRejection)
                        }
                    }
                }
                .frame(width: metrics.centerStripRect.width, height: max(InlinePaymentPromptState.isActive(in: snapshot) ? 52 : metrics.centerStripRect.height, lastActionRejection == nil ? metrics.centerStripRect.height : 66))
                .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                if isOverPlayerDropZone {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(MagicPalette.antiqueGold.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.72), lineWidth: 2))
                        .frame(width: metrics.playerDropZone.width, height: metrics.playerDropZone.height)
                        .position(x: metrics.playerDropZone.midX, y: metrics.playerDropZone.midY)
                        .allowsHitTesting(false)
                }

                PortraitHandRow(
                    cards: BoardOpponentFocus.seatHand(in: snapshot),
                    legalActions: snapshot.legalActions ?? [],
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    pendingCardInstanceId: pendingCardInstanceId,
                    interactionState: $interactionState,
                    playerDropZone: metrics.playerDropZone,
                    isOverPlayerDropZone: $isOverPlayerDropZone,
                    cardWidth: metrics.handCardWidth,
                    cardHeight: metrics.handCardHeight,
                    rowWidth: metrics.handRect.width,
                    onDropFeedback: onInteractionFeedback,
                    onActionChoice: { actions, message in
                        dragActionChoice = DragActionChoice(message: message, actions: actions)
                    },
                    runAction: runAction,
                    hiddenCount: snapshot.isViewer(human.playerId) ? nil : human.zones.visibleHandCount
                )
                    .frame(width: metrics.handRect.width, height: metrics.handRect.height)
                    .position(x: metrics.handRect.midX, y: metrics.handRect.midY)
                    .onChange(of: derivedInteractionMode) { _, mode in
                        interactionState.mode = mode
                    }



                if TargetingHelperVisibility.shouldShow(snapshot: snapshot, pendingActionId: pendingActionId, mode: derivedInteractionMode, targetableIds: targetableIds) {
                    TargetingStatusPill(count: targetableIds.count)
                        .position(x: metrics.bottomActionRect.midX, y: metrics.bottomActionRect.midY)
                        .allowsHitTesting(false)
                }

                if CombatSelectionState.isDeclareAttackers(snapshot) {
                    let declaredAttackCount = snapshot.xmage?.combat.flatMap(\.attackers).count ?? 0
                    let hasPendingAttacker = !combatSelection.selectedAttackerIds.isEmpty
                    CombatSubmitPill(
                        title: hasPendingAttacker ? "Cancel Selection" : (declaredAttackCount == 0 ? "No Attacks" : "Done Attacking"),
                        count: max(declaredAttackCount, combatSelection.selectedAttackerIds.count)
                    ) {
                        if hasPendingAttacker {
                            combatSelection.clearAttackers()
                        } else {
                            finishAttackers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.bottomActionRect.midX, y: metrics.centerStripRect.maxY + 18)
                    .zIndex(19)
                } else if CombatSelectionState.isDeclareBlockers(snapshot) {
                    let declaredBlockCount = snapshot.xmage?.combat.flatMap(\.blockers).count ?? 0
                    let hasPendingBlocker = combatSelection.selectedBlockerId != nil
                    CombatSubmitPill(
                        title: hasPendingBlocker ? "Cancel Selection" : (declaredBlockCount == 0 ? "No Blocks" : "Done Blocking"),
                        count: max(declaredBlockCount, combatSelection.blockerPairCount)
                    ) {
                        if hasPendingBlocker {
                            combatSelection.clearBlockers()
                        } else if combatSelection.hasPendingBlockers {
                            submitBlockers(snapshot: snapshot)
                        } else {
                            finishBlockers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.bottomActionRect.midX, y: metrics.centerStripRect.maxY + 18)
                    .zIndex(19)
                }

                // Floating Zone Inspector overlay
                if let inspectingZoneTitle {
                    CompactZoneInspectorOverlay(
                        title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                        cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                        legalActions: snapshot.legalActions ?? [],
                        pendingActionId: pendingActionId,
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        runAction: runAction,
                        closeAction: {
                            self.inspectingZoneTitle = nil
                            self.inspectingZoneCards = []
                            self.inspectingZoneReference = nil
                        },
                        targetableIDs: targetableIds,
                        runTargetAction: { submitTarget($0, snapshot: snapshot) },
                        availableHeight: metrics.safeFrame.height
                    )
                    .position(x: metrics.safeFrame.midX, y: metrics.safeFrame.midY)
                    .transition(boardOverlayTransition)
                }
                if let inspectedCard {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { self.inspectedCard = nil }
                        .inspectionTouchPassthrough()
                        .zIndex(99)

                    CardInspector(card: inspectedCard)
                        .inspectionTouchPassthrough()
                        .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                        .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                        .zIndex(100)
                }

                if shouldShowCompactPrompt && !isPromptDetailOpen && CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
                    CompactPromptPopup(
                        snapshot: snapshot,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        openDetails: {
                            isPromptDetailOpen = true
                        }
                    )
                    .frame(
                        width: min(max(metrics.size.width * 0.30, 260), 340),
                        height: min(max(metrics.size.height * 0.20, 98), 178)
                    )
                    .position(x: metrics.boardColumnRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(20)
                }

                if let dragActionChoice {
                    DragActionChoicePopup(
                        choice: dragActionChoice,
                        pendingActionId: pendingActionId,
                    runAction: { action in
                        self.dragActionChoice = nil
                        selectedCard = nil
                        runAction(action)
                        },
                    cancel: {
                        self.dragActionChoice = nil
                        selectedCard = nil
                        }
                    )
                    .frame(width: min(max(metrics.size.width * 0.30, 260), 340))
                    .position(x: metrics.boardColumnRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(21)
                }
            }
            .coordinateSpace(name: "portrait-board")
            // Drawn layers only (arrows and effects): one hidden layer, so it never covers the cards for
            // VoiceOver or touch tests. The offscreen-combat markers are real buttons in their own overlay.
            .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                GeometryReader { geometry in
                    let bounds = anchors.mapValues { geometry[$0] }
                    if inspectingZoneTitle == nil && inspectedCard == nil {
                        CombatArrowOverlay(snapshot: snapshot, groups: snapshot.xmage?.combat ?? [],
                            previewArrows: combatPreviewArrows, metrics: metrics,
                            humanBattlefield: human.zones.battlefield,
                            opponentBattlefield: opponent.zones.battlefield, renderedBounds: bounds)
                            .allowsHitTesting(false)
                    }
                    boardFXOverlay(bounds: bounds, snapshot: snapshot, opponentRect: metrics.opponentBattlefieldRect,
                        playerRect: metrics.playerBattlefieldRect, stackRect: metrics.centerStripRect, handRect: metrics.handRect)
                }
                .allowsHitTesting(false)
                // Hidden alone does not take inside a preference overlay: an empty representation does.
                .accessibilityRepresentation { EmptyView() }
            }
            .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                if inspectingZoneTitle == nil && inspectedCard == nil {
                    GeometryReader { geometry in
                        CombatEdgeIndicators(cards: human.zones.battlefield + opponent.zones.battlefield,
                            combatIDs: Set(CombatArrowModel.arrows(from: snapshot.xmage?.combat ?? [], previewArrows: combatPreviewArrows).flatMap { [$0.fromId, $0.toId] }),
                            bounds: anchors.mapValues { geometry[$0] },
                            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
                            laneIndices: CombatViewportAnchors.laneIndices(human: human.zones.battlefield, opponent: opponent.zones.battlefield),
                            inspect: { inspectedCard = $0 })
                    }
                }
            }
            .onAppear {
                interactionState.mode = derivedInteractionMode
            }
            .onChange(of: snapshot.combatSelectionResetKey) { _, _ in
                combatSelection.resetIfInactive(snapshot)
                combatPreviewArrows = []
            }
            .onChange(of: pendingActionId) { _, newValue in
                if newValue == nil {
                    combatPreviewArrows = []
                }
            }
        }
    }

    /// Walnut Tavern held sideways (TavernSockets.landscape): the battlefield column lies on the
    /// landscape plate's mat, the opponent's medallion and nameplate go up the left walnut
    /// column above yours, and the phase plate, stack tray and pass button down the right. The
    /// tavern top bar and command bar place their pieces on those sockets themselves.
    @ViewBuilder
    private func tavernLandscapeContent(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState,
                                        humanName: String, opponentName: String, rootProxy: GeometryProxy) -> some View {
        let canvas = CGSize(width: rootProxy.size.width + rootProxy.safeAreaInsets.leading + rootProxy.safeAreaInsets.trailing,
                            height: rootProxy.size.height + rootProxy.safeAreaInsets.top + rootProxy.safeAreaInsets.bottom)
        let sockets = TavernSockets.current(canvas)
        let origin = rootProxy.frame(in: .global).origin
        let board = canvas.tavernRect(CGRect(x: sockets.mat.minX, y: sockets.mat.minY, width: sockets.mat.width,
                                             height: sockets.handBottom - sockets.mat.minY))
        let opponentColumn = canvas.tavernRect(CGRect(x: 64, y: 0, width: 128, height: 176))
        let defenders = CombatHighlightSet(selection: combatSelection, actions: snapshot.legalActions ?? [],
                                           combatGroups: snapshot.xmage?.combat ?? []).defenderIds
        let actions = snapshot.legalActions ?? []
        ZStack {
            landscapeCenterColumn(snapshot: snapshot, human: human, opponent: opponent)
                .frame(width: board.width, height: board.height)
                .position(x: board.midX - origin.x, y: board.midY - origin.y)
            PortraitOpponentStatusBar(
                snapshot: snapshot,
                opponentName: opponentName,
                opponent: opponent,
                humanId: human.playerId,
                combatTargetable: CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: defenders) != nil,
                combatTargetAction: {
                    if let defenderId = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: defenders) {
                        submitAttackers(defenderId: defenderId, snapshot: snapshot)
                    }
                },
                openLog: { isLogOpen = true },
                viewZone: { localViewZone(title: $0, cards: $1) },
                selectOpponent: { focusTracker.select($0) }
            )
            .frame(width: opponentColumn.width, height: opponentColumn.height)
            .position(x: opponentColumn.midX - origin.x, y: opponentColumn.midY - origin.y)
            if !snapshot.isSpectating {
                PortraitBottomCommandBar(
                    humanName: humanName,
                    human: human,
                    opponentId: opponent.playerId,
                    manaPool: human.manaPool,
                    passAction: passAction(in: actions),
                    yieldActions: GameplayActionPresentation.yieldActions(in: actions),
                    pendingActionId: pendingActionId,
                    snapshot: snapshot,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    openLog: { isLogOpen = true },
                    openSettings: { isGameMenuOpen = true },
                    openPromptDetails: openPromptDetails,
                    viewZone: { localViewZone(title: $0, cards: $1) },
                    runAction: runAction,
                    runCommand: runCommand,
                    openStack: { isTavernStackOpen = true }
                )
                .frame(width: rootProxy.size.width, height: rootProxy.size.height)
                .sheet(isPresented: $isTavernStackOpen) {
                    BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                        .tavernSheet(true)
                }
                .onChange(of: isTavernStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
            }
            if snapshot.isWaitingOnAIOrStalled {
                AIWaitFallbackControls(
                    snapshot: snapshot,
                    pendingActionId: pendingActionId,
                    liveUpdateStatus: liveUpdateStatus,
                    beganAt: aiWaitBeganAt,
                    didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                    didReconnect: didAutoReconnectAIWaitKey == aiWaitKey,
                    didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                    refreshAction: refreshGame,
                    reconnectAction: reconnectGame
                )
                .frame(width: min(board.width - 28, 360))
                .position(x: board.midX - origin.x, y: board.midY - origin.y)
                .zIndex(80)
            }
        }
        .frame(width: rootProxy.size.width, height: rootProxy.size.height)
        .environment(\.tavernBoard, true)
        .environment(\.tavernCanvas, canvas)
    }

    private func recover(from rejection: ActionRejectionNotice) {
        GameHaptics.impact()
        if rejection.category == .bridgeDisconnected {
            reconnectGame()
        } else {
            refreshGame()
        }
    }

    private func refreshProtocolDebug() async {
        guard let gameId = snapshot?.id else { return }
        isProtocolDebugLoading = true
        protocolDebugError = nil
        do {
            protocolDebug = try await loadProtocolDebug(gameId)
        } catch {
            protocolDebugError = error.localizedDescription
        }
        isProtocolDebugLoading = false
    }

    @ViewBuilder
    var body: some View {
        // `human` is the bottom seat: the viewer, or their stand-in while they watch. Actions,
        // stats, haptics and "You" stay on the viewer (snapshot.human / viewerID).
        if let snapshot = snapshot.map({ BoardOpponentFocus.snapshot($0, selecting: focusTracker.focusedID) }),
           let human = snapshot.seat, let opponent = snapshot.opponent {
            let humanName = snapshot.playerLabel(human.playerId)
            let opponentName = snapshot.playerLabel(opponent.playerId)
            let sideCombatHighlights = CombatHighlightSet(
                selection: combatSelection,
                actions: snapshot.legalActions ?? [],
                combatGroups: snapshot.xmage?.combat ?? []
            )
            let boardSurface = GeometryReader { rootProxy in
                ZStack {
                    BattlefieldSurface(portraitModeEnabled: portraitModeEnabled)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: clearBoardSelection)

                    if GameOrientationMode.isPortraitLayout(size: rootProxy.size, portraitEnabled: portraitModeEnabled) {
                        portraitGameContent(
                            snapshot: snapshot,
                            human: human,
                            opponent: opponent,
                            humanName: humanName,
                            opponentName: opponentName,
                            sideCombatHighlights: sideCombatHighlights
                        )
                        .environment(\.tavernBoard, isTavernBoard)
                        .environment(\.tavernCanvas, isTavernBoard ? CGSize(
                            width: rootProxy.size.width + rootProxy.safeAreaInsets.leading + rootProxy.safeAreaInsets.trailing,
                            height: rootProxy.size.height + rootProxy.safeAreaInsets.top + rootProxy.safeAreaInsets.bottom) : nil)
                    } else if isTavernBoard {
                        tavernLandscapeContent(snapshot: snapshot, human: human, opponent: opponent,
                                               humanName: humanName, opponentName: opponentName, rootProxy: rootProxy)
                    } else {
                    HStack(spacing: 0) {
                    // LEFT COLUMN
                    VStack(alignment: .leading, spacing: 0) {
                        LandscapePlayerSummary(
                            name: opponentName,
                            player: opponent,
                            active: snapshot.activePlayerId == opponent.playerId,
                            opponentId: human.playerId,
                            combatTargetable: CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: sideCombatHighlights.defenderIds) != nil,
                            combatTargetAction: {
                                if let defenderId = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: sideCombatHighlights.defenderIds) {
                                    submitAttackers(defenderId: defenderId, snapshot: snapshot)
                                }
                            },
                            thinking: snapshot.thinkingPlayerID == opponent.playerId
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)

                        HStack(spacing: 4) {
                            PlayerZoneMenu(player: opponent, viewZone: localViewZone)
                            BoardPlayerEffects(player: opponent, attachments: BattlefieldAttachments.enchanting(playerID: opponent.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: localViewZone,
                                opponents: BoardOpponentFocus.opponents(in: snapshot), selectOpponent: { focusTracker.select($0) })
                        }

                        Spacer()

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            ManaPoolHUD(manaPool: human.manaPool, compact: true, grid: true,
                                payableSymbols: GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId),
                                payMana: { symbol in
                                    if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                                        runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                                    }
                                })
                            LandscapePlayerSummary(name: humanName, player: human, active: snapshot.activePlayerId == human.playerId,
                                                   opponentId: opponent.playerId, chatSnapshot: snapshot.isViewer(human.playerId) ? snapshot : nil)
                            HStack(spacing: 4) {
                                PlayerZoneMenu(player: human, viewZone: localViewZone, snapshot: snapshot, pendingActionID: pendingActionId)
                                BoardPlayerEffects(player: human, attachments: BattlefieldAttachments.enchanting(playerID: human.playerId, allCards: snapshot.players.flatMap { $0.zones.battlefield }), viewZone: localViewZone)
                            }
                            // The revealed top of your library, under your zones.
                            if let top = human.zones.library.first {
                                TopOfLibraryCard(card: top, playable: GameplayAffordances.castableZones(player: human, snapshot: snapshot, pendingActionID: pendingActionId).contains(.library),
                                                 owner: "your", height: 40) { localViewZone(title: "Top of your library", cards: [top]) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 88)
                    .background(
                        LinearGradient(
                            colors: [MagicPalette.iron.opacity(0.96), MagicPalette.leather.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(MagicPalette.antiqueGold.opacity(0.28))
                            .frame(width: 1)
                    }

                    // CENTER COLUMN
                    landscapeCenterColumn(snapshot: snapshot, human: human, opponent: opponent)

                    // RIGHT COLUMN
                    VStack(alignment: .trailing, spacing: 8) {
                        ScrollView(.vertical) {
                        VStack(spacing: 8) {
                        MagicPathPhaseRail(
                            snapshot: snapshot,
                            passAction: passAction(in: snapshot.legalActions ?? []),
                            yieldActions: GameplayActionPresentation.yieldActions(in: snapshot.legalActions ?? []),
                            logAction: { isLogOpen.toggle() },
                            settingsAction: { isGameMenuOpen = true },
                            runAction: runAction,
                            onlyPhases: true
                        )
                        .padding(.top, 12)

                        if pendingActionId == nil, let cue = BoardResponseCue.make(snapshot) {
                            BoardResponseBanner(cue: cue)
                        }

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        GameLogAccessButton(entryCount: snapshot.log.count, openLog: { isLogOpen = true })
                            .padding(.horizontal, 8)

                        Button {
                            isLandscapeStackOpen = true
                        } label: {
                            Label("Stack · \(snapshot.stackTopFirst.count)", systemImage: "square.stack.3d.up")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Inspect stack")

                        if let emoteCenter { TableChatButton(center: emoteCenter) }

                        if let xmageStack = snapshot.xmage?.stack, !xmageStack.isEmpty {
                            XmageStackPeek(
                                objects: snapshot.source == "xmage-ondevice" ? Array(xmageStack.reversed()) : xmageStack,
                                legalActions: snapshot.legalActions ?? [],
                                promptText: snapshot.promptEnvelopeV2?.message ?? snapshot.promptText,
                                selectedCard: $selectedCard,
                                inspectedCard: $inspectedCard
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        } else if !human.zones.stack.isEmpty {
                            StackPeek(cards: human.zones.stack, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        }
                        }
                        }

                        Divider()
                            .background(MagicPalette.antiqueGold.opacity(0.18))
                            .padding(.horizontal, 8)

                        GameplayActionDock(
                            snapshot: snapshot,
                            passAction: passAction(in: snapshot.legalActions ?? []),
                            yieldActions: GameplayActionPresentation.yieldActions(in: snapshot.legalActions ?? []),
                            pendingActionId: pendingActionId,
                            compact: true,
                            landscapeSidebar: true,
                            openPromptDetails: openPromptDetails,
                            openLog: { isLogOpen = true },
                            openSettings: { isGameMenuOpen = true },
                            runAction: runAction
                        )
                        .padding(.horizontal, LandscapeActionDockLayout.horizontalPadding)
                        .padding(.bottom, LandscapeActionDockLayout.bottomPadding)
                    }
                    .overlay(alignment: .center) {
                        if snapshot.isWaitingOnAIOrStalled {
                            AIWaitFallbackControls(
                                snapshot: snapshot,
                                pendingActionId: pendingActionId,
                                liveUpdateStatus: liveUpdateStatus,
                                beganAt: aiWaitBeganAt,
                                didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                                didReconnect: didAutoReconnectAIWaitKey == aiWaitKey,
                                didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                                refreshAction: refreshGame,
                                reconnectAction: reconnectGame
                            )
                            .padding(.horizontal, 10)
                        }
                    }
                    .frame(width: LandscapeActionDockLayout.sidebarWidth(hasStack: !snapshot.stackTopFirst.isEmpty))
                    .background(
                        LinearGradient(
                            colors: [MagicPalette.iron.opacity(0.96), MagicPalette.leather.opacity(0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(MagicPalette.antiqueGold.opacity(0.28))
                            .frame(width: 1)
                    }
                }
                }
                }
            }
                .background(Color(red: 0.055, green: 0.085, blue: 0.10).ignoresSafeArea())
                .preferredColorScheme(.dark)
                .overlay(alignment: .top) {
                    #if DEBUG
                    if snapshot.source == "design-preview" {
                        Text("DEVELOPMENT FIXTURE · NO ENGINE")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.yellow, in: Capsule()).allowsHitTesting(false)
                    }
                    #endif
                }
                .sheet(isPresented: $isLogOpen) {
                    GameLogDrawer(
                        log: snapshot.log,
                        reasons: combatLogReasons.reasons,
                        close: { isLogOpen = false }
                    )
                    .padding(14)
                    .tavernSheet(isTavernBoard)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isLandscapeStackOpen) {
                    BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                }
                .sheet(isPresented: $isPromptDetailOpen) {
                    UniversalPromptActionPanel(
                        snapshot: snapshot,
                        selectedCardActions: selectedCard.map { GameBoardInteractionState.cardActions(for: $0, actions: snapshot.legalActions ?? []) } ?? [],
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        viewZone: { title, cards in
                            isPromptDetailOpen = false
                            localViewZone(title: title, cards: cards)
                        },
                        showsGameSurfaceSections: snapshot.promptEnvelopeV2 == nil
                    )
                    .id("\(snapshot.promptEnvelopeV2?.id ?? ""):\(snapshot.promptEnvelopeV2?.messageId ?? 0)")
                    .padding(14)
                    .tavernSheet(isTavernBoard)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isGameMenuOpen) {
                    GameManagementMenu(
                        snapshot: snapshot,
                        concedeAction: concedeAction(in: snapshot.legalActions ?? []),
                        runAction: runAction,
                        portraitModeEnabled: $portraitModeEnabled,
                        openPromptInspector: {
                            isGameMenuOpen = false
                            isPromptInspectorOpen = true
                        },
                        confirmStartNew: {
                            if isTavernBoard { isGameMenuOpen = false }
                            gameMenuConfirmation = .startNew
                        },
                        confirmQuit: {
                            if isTavernBoard { isGameMenuOpen = false }
                            gameMenuConfirmation = .quit
                        }
                    )
                    .tavernSheet(isTavernBoard)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isPromptInspectorOpen) {
                    PromptDebugInspector(
                        snapshot: snapshot,
                        liveUpdateStatus: liveUpdateStatus,
                        lastActionRejection: lastActionRejection,
                        protocolDebug: protocolDebug,
                        protocolDebugError: protocolDebugError,
                        isProtocolDebugLoading: isProtocolDebugLoading,
                        refreshProtocolDebug: { Task { await refreshProtocolDebug() } }
                    )
                        .task(id: snapshot.id) {
                            await refreshProtocolDebug()
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .tavernConfirmation(
                    active: isTavernBoard,
                    title: gameMenuConfirmation?.title ?? "Leave game?",
                    message: gameMenuConfirmation?.message,
                    isPresented: Binding(
                        get: { gameMenuConfirmation != nil },
                        set: { if !$0 { gameMenuConfirmation = nil } }
                    ),
                    actions: gameMenuConfirmation == .startNew
                        ? [TavernDialogAction(title: "Start New Game", destructive: true) {
                            gameMenuConfirmation = nil
                            isGameMenuOpen = false
                            newGame()
                        }]
                        : gameMenuConfirmation == .quit
                            ? [TavernDialogAction(title: "Quit to Menu", destructive: true) {
                                gameMenuConfirmation = nil
                                isGameMenuOpen = false
                                quitGame()
                            }]
                            : [],
                    onCancel: { gameMenuConfirmation = nil }
                )
            // Above the HUD, dock, choice and phase layers, edge to edge.
            boardPresentation(boardSurface, snapshot: snapshot)
                // The tavern's candle sits under the clock: the status bar leaves during a game. On a
                // hidden background, so the board itself never becomes one big accessibility element.
                .background { Color.clear.statusBarHidden(isTavernBoard).accessibilityHidden(true).allowsHitTesting(false) }
                .environment(\.inspectorBattlefield, snapshot.visibleBattlefield)
                .overlay {
                    if let choice = OpeningHandChoice(snapshot), let hand = snapshot.human?.zones.hand, !hand.isEmpty {
                        OpeningHandOverlay(choice: choice, cards: hand, pending: pendingActionId != nil, answer: runCommand)
                            .environment(\.tavernBoard, isTavernBoard)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if snapshot.isSpectating {
                        SpectatorBar(snapshot: snapshot, leave: quitGame)
                            .frame(maxWidth: 460)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? nil : .easeOut(duration: 0.3),
                           value: snapshot.isSpectating)
                .overlay {
                    if snapshot.isCompleted {
                        GameCompletionOverlay(snapshot: snapshot, stats: gameStats, newGame: newGame, quitGame: quitGame)
                            .environment(\.tavernBoard, isTavernBoard)
                            .transition(boardOverlayTransition)
                    }
                }
                .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? nil : .easeOut(duration: 0.35),
                           value: snapshot.isCompleted)
                .onChange(of: snapshot.isCompleted) { _, completed in
                    guard completed else { return }
                    isLogOpen = false; isLandscapeStackOpen = false; isPromptDetailOpen = false
                    isCardChoiceOpen = false; dragActionChoice = nil; inspectedCard = nil
                    let won = snapshot.winnerPlayerIds?.contains(snapshot.viewerID) == true
                    GameAudio.shared.duckMusic(for: 6)
                    GameAudio.shared.play(won ? .victory : .defeat, after: 0.25)
                }
                .onChange(of: GameSoundSignature(snapshot)) { old, new in
                    for (index, sound) in GameSoundSignature.cues(from: old, to: new).enumerated() {
                        GameAudio.shared.play(sound, after: Double(index) * 0.11)
                    }
                }
        } else {
            LoadingGameView()
        }
    }

    private func boardPresentation<Content: View>(_ content: Content, snapshot: GameSnapshot) -> some View {
        let observed = boardObservation(content, snapshot: snapshot)
        let choices = boardChoicePresentation(observed, snapshot: snapshot)
        return boardPhasePresentation(choices, snapshot: snapshot)
    }

    private func ingestBoardFX(_ snapshot: GameSnapshot) {
        let level = BoardFXLevel.resolved(stored: boardFXLevel, reduceMotion: GameBoardMotion.reduced(accessibilityReduceMotion))
        let scheduled = boardFX.ingest(snapshot, level: level, now: Date(), holdUntil: turnBannerEndsAt)
        guard !scheduled.isEmpty else { return }
        BoardFXHaptics.play(scheduled, viewerID: snapshot.viewerID)
        if boardSoundsEnabled {
            var arrivals: [String: BoardFXSound.Arrival] = [:]
            let arrived = Set(scheduled.compactMap { fx -> String? in
                if case let .enteredBattlefield(id, _, _, _, _) = fx.event { return id }; return nil
            })
            if !arrived.isEmpty {
                for card in snapshot.players.flatMap(\.zones.battlefield) where arrived.contains(card.instanceId) {
                    arrivals[card.instanceId] = BoardFXSound.Arrival(isLand: card.card.typeLine.localizedCaseInsensitiveContains("land"),
                                                                    isToken: card.card.isToken == true)
                }
            }
            BoardFXSound.play(scheduled, viewerID: snapshot.viewerID, arrivals: arrivals)
        }
        guard level == .full else { return }
        // Shake when the hit lands, scaled to it: the viewer losing life, a big hit on an
        // opponent, or a commander touching down. Five or more to you also flares red.
        var shakes: [(at: TimeInterval, amplitude: CGFloat, flare: Bool)] = []
        for fx in scheduled {
            switch fx.event {
            case let .lifeChanged(id, delta) where delta < 0:
                if id == snapshot.viewerID {
                    shakes.append((fx.delay, delta <= -5 ? 12 : 6, delta <= -5))
                } else if delta <= -5 {
                    shakes.append((fx.delay, 5, false))
                }
            case .enteredBattlefield(_, _, _, _, .commander):
                shakes.append((fx.landing, 6, false))
            default: break
            }
        }
        for shake in shakes.prefix(3) {
            DispatchQueue.main.asyncAfter(deadline: .now() + shake.at) {
                boardShakeAmplitude = shake.amplitude
                withAnimation(.linear(duration: shake.amplitude > 8 ? 0.5 : 0.36)) { boardShake += 1 }
                if shake.flare {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
                    withAnimation(.easeOut(duration: 0.12)) { hitVignette = 1 }
                    withAnimation(.easeIn(duration: 0.7).delay(0.15)) { hitVignette = 0 }
                }
            }
        }
    }

    /// Life points default to the battlefield edges; the portrait board passes its life HUD positions.
    private func boardFXOverlay(bounds: [String: CGRect], snapshot: GameSnapshot, opponentRect: CGRect,
                                playerRect: CGRect, stackRect: CGRect, handRect: CGRect,
                                viewerLife: CGPoint? = nil, opponentLife: CGPoint? = nil) -> some View {
        let anchors = BoardFXAnchors(
            viewerID: snapshot.viewerID,
            viewerPoint: viewerLife ?? CGPoint(x: playerRect.minX + 50, y: playerRect.maxY - 20),
            opponentPoint: opponentLife ?? CGPoint(x: opponentRect.minX + 50, y: opponentRect.minY + 20),
            // On the tavern table the showcase sits higher, clear of the cost and target ribbons.
            stackPoint: CGPoint(x: stackRect.midX, y: isTavernBoard ? min(stackRect.midY, (opponentRect.midY + stackRect.midY) / 2) : stackRect.midY),
            viewerHandPoint: CGPoint(x: handRect.midX, y: handRect.midY),
            opponentHandPoint: CGPoint(x: opponentRect.midX, y: opponentRect.minY - 40),
            playerLabels: Dictionary(snapshot.players.map { ($0.playerId, snapshot.playerLabel($0.playerId)) }, uniquingKeysWith: { first, _ in first }))
        return BoardFXOverlay(effects: boardFX.active, subjects: boardFX.subjects, cardBounds: bounds, anchors: anchors,
                              clock: boardFXClock, prune: { boardFX.prune(now: Date()) }, tavern: isTavernBoard)
    }

    private func boardObservation<Content: View>(_ content: Content, snapshot: GameSnapshot) -> some View {
        content
            .modifier(BoardImpactShake(animatableData: boardShake, amplitude: boardShakeAmplitude))
            .overlay { if hitVignette > 0 { BoardHitVignette(strength: hitVignette) } }
            .environment(\.boardFXCardMotion, boardFX.cardMotion(viewerID: snapshot.viewerID))
            .environment(\.boardFXClock, boardFXClock)
            .environment(\.boardHUDPulse, hudPulse)
            .environment(\.boardZoneInspectionAction, inspectBoardZone)
            .onChange(of: BoardFXRevisionKey(snapshot: snapshot), initial: true) { _, _ in
                ingestBoardFX(snapshot)
                gameStats.record(snapshot)
                combatLogReasons.observe(snapshot)
            }
            .modifier(CombatDeclarationObserver(ids: declaredCombatCards(in: snapshot).map(\.id), order: $combatDeclarationOrder))
            .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: inspectingZoneTitle)
            .animation(GameBoardMotion.reduced(accessibilityReduceMotion) ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: inspectedCard?.id)
            .onAppear {
                updateAIWaitStart(for: snapshot)
                isCardChoiceOpen = PortraitInteractionPolicy.cardChoiceKey(snapshot) != nil
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
            }
            // The tracker starts over by itself when the game changes.
            .onChange(of: BoardFocusTracker.observationKey(snapshot, followTurns: followTurns), initial: true) { _, _ in
                focusTracker.observe(snapshot, followTurns: followTurns)
            }
            .onChange(of: snapshot.id) { _, _ in
                cardChoiceCompletionTask?.cancel()
                cardChoiceCompletionTask = nil
                committedCardChoice = nil
                reviewCardChoiceAfterPending = false
                lastTurnCueKey = nil
                lastTurnBannerKey = nil
                inspectingZoneTitle = nil
                inspectingZoneCards = []
                inspectingZoneReference = nil
                selectedCard = nil
                inspectedCard = nil
            }
            .onChange(of: snapshot.bridgeRevision) { _, _ in
                advanceCommittedCardChoice()
                let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
                if let card = inspectedCard { inspectedCard = cards.first { $0.id == card.id } }
                if let card = selectedCard { selectedCard = cards.first { $0.id == card.id } }
                if let reference = inspectingZoneReference, inspectingZoneTitle != nil {
                    inspectingZoneCards = reference.cards(in: snapshot)
                    inspectingZoneTitle = reference.title(in: snapshot)
                } else if inspectingZoneTitle != nil {
                    // Unscoped legacy inspections cannot safely infer zone membership.
                    inspectingZoneCards = []
                    inspectingZoneTitle = nil
                }
                if let choice = dragActionChoice, !choice.actions.allSatisfy({ old in
                    snapshot.legalActions?.contains(where: { $0.id == old.id && $0.messageId == old.messageId }) == true
                }) { dragActionChoice = nil }
            }
            .onChange(of: snapshot.promptEnvelopeV2?.id) { _, _ in
                advanceCommittedCardChoice()
                isPromptDetailOpen = PortraitInteractionPolicy.detailChoiceKey(snapshot) != nil
            }
            .onChange(of: snapshot.promptEnvelopeV2?.messageId) { _, _ in
                advanceCommittedCardChoice()
            }
            .onChange(of: pendingActionId) { oldValue, newValue in
                handleCardChoicePendingChange(from: oldValue, to: newValue, snapshot: snapshot)
            }
            .onChange(of: isLogOpen) { _, open in GameAudio.shared.play(open ? .pageFlip : .uiClose) }
            #if DEBUG
            // Visual QA: MAGICMOBILE_PREVIEW_OPEN_LOG=<seconds> opens a design preview's log after that delay.
            .task(id: snapshot.source) {
                guard snapshot.source == "design-preview",
                      let delay = ProcessInfo.processInfo.environment["MAGICMOBILE_PREVIEW_OPEN_LOG"].flatMap(Double.init) else { return }
                try? await Task.sleep(for: .seconds(delay))
                isLogOpen = true
            }
            #endif
            .onChange(of: isGameMenuOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
            .onChange(of: isLandscapeStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
            .onChange(of: lastActionRejection?.message) { _, newValue in
                if newValue != nil { GameAudio.shared.play(.uiError) }
                if newValue != nil && committedCardChoice != nil { cancelCommittedCardChoice() }
            }
            .onChange(of: commandFailure) { oldValue, newValue in
                handleCardChoiceFailureChange(from: oldValue, to: newValue)
            }
            .onChange(of: PortraitInteractionPolicy.detailChoiceKey(snapshot)) { _, key in
                isPromptDetailOpen = key != nil
                // A decision that needs you, not a routine priority pass (the starting roll answers its own).
                if key != nil && !startingRollVisible { GameAudio.shared.play(.responseAlert) }
            }
            .onChange(of: PortraitInteractionPolicy.cardChoiceKey(snapshot)) { _, key in
                if key != nil && committedCardChoice == nil && !startingRollVisible { GameAudio.shared.play(.responseAlert) }
                isCardChoiceOpen = key != nil && committedCardChoice == nil && !reviewCardChoiceAfterPending
                inspectedCard = nil
                selectedCard = nil
                if key != nil { isPromptDetailOpen = false; isLandscapeStackOpen = false }
            }
    }

    private func boardChoicePresentation<Content: View>(_ content: Content, snapshot: GameSnapshot) -> some View {
        content
            // The starting roll covers the board too (the root also applies startingRollCovered).
            .accessibilityHidden(isCardChoiceOpen || committedCardChoice != nil || startingRollVisible)
            .overlay {
                if isCardChoiceOpen, let key = PortraitInteractionPolicy.cardChoiceKey(snapshot), let prompt = snapshot.promptEnvelopeV2 {
                    BoardCardChoiceView(snapshot: snapshot, prompt: prompt, pendingActionId: pendingActionId,
                                        runCommand: runCommand, runAction: runAction,
                                        commitPlan: commitCardChoicePlan, close: { isCardChoiceOpen = false })
                        .environment(\.tavernBoard, isTavernBoard)
                        .id(key)
                }
            }
            .overlay {
                if committedCardChoice != nil {
                    // Block manual board/answer taps until Stop returns control to the current prompt.
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if committedCardChoice != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Applying card choices…").font(.caption)
                        Button("Stop") { cancelCommittedCardChoice() }
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHint("Stops remaining automatic replies. Choices already sent to XMage stay applied.")
                    }
                    .padding(8)
                    .background(MagicPalette.iron, in: Capsule())
                    .accessibilityIdentifier("board.choice.progress")
                }
            }
            .onChange(of: selectedCard?.id) { _, _ in
                guard let card = selectedCard, pendingActionId == nil,
                      GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty else { return }
                let actions = GameBoardInteractionState.cardActions(for: card, actions: snapshot.legalActions ?? [])
                if !actions.isEmpty {
                    dragActionChoice = DragActionChoice(message: card.card.name, actions: actions)
                }
            }
    }

    private func boardPhasePresentation<Content: View>(_ content: Content, snapshot: GameSnapshot) -> some View {
        content
            // The classic board: day or night and the storm count under the top bar (the tavern table hangs them
            // under its phase plate).
            .overlay(alignment: .top) {
                if !isTavernBoard {
                    TavernTableHints(dayNight: snapshot.dayNight, stormCount: snapshot.stormCount)
                        .padding(.top, 64)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if showsTurnBanner, let active = snapshot.activePlayerId, !isCardChoiceOpen, !isPromptDetailOpen {
                    BoardTurnBanner(title: snapshot.isViewer(active) ? "Your turn" : "\(snapshot.playerLabel(active))’s turn",
                                    turn: snapshot.turn, isViewer: snapshot.isViewer(active))
                        .environment(\.tavernBoard, isTavernBoard)
                        // Leaves by shrinking up toward the top bar's turn label.
                        .transition(.asymmetric(insertion: .opacity,
                                                removal: .scale(scale: 0.2, anchor: .top).combined(with: .offset(y: -220)).combined(with: .opacity)))
                        .accessibilityIdentifier("board.turn.banner")
                }
            }
            .overlay {
                if showsTurnCue, let cue = BoardPhaseAnnouncement.make(snapshot), !isCardChoiceOpen, !isPromptDetailOpen {
                    // A compact pill under the top HUD keeps the middle of the board clear for combat.
                    HStack(spacing: 8) {
                        if isTavernBoard && TavernUIKit.available {
                            TavernTag(text: cue.owner.uppercased(), leather: true)
                        } else {
                            Text(cue.owner.uppercased()).font(.caption2.weight(.heavy)).tracking(1)
                                .foregroundStyle(MagicPalette.antiqueGold)
                        }
                        Text(cue.title).font(.system(size: 17, weight: .bold, design: .serif))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                        .foregroundStyle(MagicPalette.parchment)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .modifier(PhaseCueChrome(tavern: isTavernBoard))
                        .shadow(color: .black.opacity(0.4), radius: 10)
                        .scaleEffect(phaseCueMerging ? 0.5 : 1)
                        .offset(y: phaseCueMerging ? -46 : 0)
                        .opacity(phaseCueMerging ? 0 : 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                        // On the tavern table it sits under the nameplate and phase plate.
                        .padding(.top, verticalSizeClass == .compact ? 8 : (isTavernBoard ? 96 : 64))
                        .transition(GameBoardMotion.reduced(accessibilityReduceMotion) ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("board.phase.announcement")
                }
            }
            .task(id: BoardPhaseAnnouncement.make(snapshot)?.key) {
                guard let key = BoardPhaseAnnouncement.make(snapshot)?.key, key != lastTurnCueKey else {
                    showsTurnCue = false
                    return
                }
                lastTurnCueKey = key
                // The first phase of a new turn gets the turn-start banner instead of a phase card.
                let turnKey = "\(snapshot.id):\(snapshot.turn):\(snapshot.activePlayerId ?? "")"
                if turnKey != lastTurnSoundKey {
                    // A chime when your turn begins (the versus reveal covers the first one).
                    let firstTurn = lastTurnSoundKey == nil
                    lastTurnSoundKey = turnKey
                    if !firstTurn || snapshot.turn > 1 {
                        if snapshot.isViewer(snapshot.activePlayerId) { GameAudio.shared.play(.turnYou) }
                    }
                }
                if turnKey != lastTurnBannerKey && BoardFXLevel(rawValue: boardFXLevel) != .off {
                    let firstBanner = lastTurnBannerKey == nil
                    lastTurnBannerKey = turnKey
                    if !firstBanner || snapshot.turn > 1 {
                        // A showcase at the centre finishes first, so the banner and a cast never stack.
                        if let busy = boardFX.centreBusyUntil, busy > Date() {
                            do { try await Task.sleep(for: .seconds(min(busy.timeIntervalSinceNow, BoardFXScheduler.maximumHold))) } catch { return }
                        }
                        // The ribbon plays with the phase pill; it is center stage only briefly.
                        if snapshot.isViewer(snapshot.activePlayerId) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        turnBannerEndsAt = Date().addingTimeInterval(1.95)
                        withAnimation(.easeOut(duration: 0.2)) { showsTurnBanner = true; showsTurnCue = !isTavernBoard }
                        do { try await Task.sleep(for: .seconds(1.6)) } catch { showsTurnBanner = false; return }
                        withAnimation(.easeIn(duration: 0.35)) { showsTurnBanner = false }
                        await mergePhaseCueIntoBar()
                        return
                    }
                }
                phaseCueMerging = false
                // The tavern's phase plate already names the phase; it flashes instead of a pill.
                if isTavernBoard { hudPulse += 1; return }
                withAnimation(.easeOut(duration: 0.2)) { showsTurnCue = true }
                do { try await Task.sleep(for: .seconds(1.1)) } catch { return }
                await mergePhaseCueIntoBar()
            }
            .onChange(of: snapshot.aiWaitSignature) { _, _ in
                updateAIWaitStart(for: snapshot)
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now in
                handleAIWaitRecovery(for: snapshot, now: now)
            }
    }

    /// The pill shrinks up into the top bar, which flashes its turn label as it lands.
    private func mergePhaseCueIntoBar() async {
        withAnimation(.easeIn(duration: 0.3)) { phaseCueMerging = true }
        try? await Task.sleep(for: .milliseconds(300))
        showsTurnCue = false
        phaseCueMerging = false
        hudPulse += 1
    }

    private func updateAIWaitStart(for snapshot: GameSnapshot) {
        let key = snapshot.aiWaitSignature
        if key != aiWaitKey {
            aiWaitKey = key
            aiWaitBeganAt = Date()
            didAutoRefreshAIWaitKey = nil
            didAutoReconnectAIWaitKey = nil
            didAutoDiagnoseAIWaitKey = nil
        }
    }

    private func handleAIWaitRecovery(for snapshot: GameSnapshot, now: Date) {
        let key = snapshot.aiWaitSignature
        guard key == aiWaitKey else { return }
        let action = AIWaitRecoveryPolicy.action(
            for: snapshot,
            elapsedSeconds: now.timeIntervalSince(aiWaitBeganAt),
            didRefresh: didAutoRefreshAIWaitKey == key,
            didReconnect: didAutoReconnectAIWaitKey == key,
            didDiagnose: didAutoDiagnoseAIWaitKey == key
        )
        switch action {
        case .none:
            return
        case .refresh:
            didAutoRefreshAIWaitKey = key
            onInteractionFeedback("Refreshing player wait")
            refreshGame()
        case .reconnect:
            didAutoReconnectAIWaitKey = key
            onInteractionFeedback("Reconnecting player wait")
            reconnectGame()
        case .diagnose:
            didAutoDiagnoseAIWaitKey = key
            onInteractionFeedback("Checking bridge health")
            Task {
                _ = await checkBridgeHealth()
                await refreshProtocolDebug()
            }
        }
    }

    @ViewBuilder
    /// The Walnut Tavern table is portrait-only for now; landscape keeps the classic controls.
    private var isTavernBoard: Bool { BattlefieldBackdrop.resolved(boardAppearance) == .tavern }

    private func portraitGameContent(
        snapshot: GameSnapshot,
        human: PlayerGameState,
        opponent: PlayerGameState,
        humanName: String,
        opponentName: String,
        sideCombatHighlights: CombatHighlightSet
    ) -> some View {
        GeometryReader { proxy in
            let metrics = PortraitBattlefieldLayoutMetrics(proxy: proxy, paymentActive: InlinePaymentPromptState.isActive(in: snapshot), largeText: GameBoardMotion.largeText(dynamicTypeSize),
                centerControlsVisible: BoardDecisionPresentation.needsCenterSpace(snapshot, hasRejection: lastActionRejection != nil),
                tavernDock: isTavernBoard)
            let actions = snapshot.legalActions ?? []
            let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
            let combatHighlights = CombatHighlightSet(
                selection: combatSelection,
                actions: actions,
                combatGroups: snapshot.xmage?.combat ?? []
            )
            let shouldShowCompactPrompt = !startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId)
            let derivedInteractionMode = GameBoardInteractionState.mode(
                for: snapshot,
                pendingActionId: pendingActionId,
                selectedCard: selectedCard
            )

            ZStack {
                PortraitOpponentStatusBar(
                    snapshot: snapshot,
                    opponentName: opponentName,
                    opponent: opponent,
                    humanId: human.playerId,
                    combatTargetable: CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: combatHighlights.defenderIds) != nil,
                    combatTargetAction: {
                        if let defenderId = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: combatHighlights.defenderIds) {
                            submitAttackers(defenderId: defenderId, snapshot: snapshot)
                        }
                    },
                    openLog: { isLogOpen = true },
                    viewZone: { localViewZone(title: $0, cards: $1) },
                    selectOpponent: { focusTracker.select($0) }
                )
                .frame(width: metrics.topHUDRect.width, height: metrics.topHUDRect.height)
                .position(x: metrics.topHUDRect.midX, y: metrics.topHUDRect.midY)

                PortraitBattlefieldPermanentGroup(title: "Opponent board", cards: nonLandPermanents(opponent.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.opponentBattlefieldRect.width, availableHeight: metrics.opponentBattlefieldRect.height, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentBattlefieldRect.width, height: metrics.opponentBattlefieldRect.height)
                    .position(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)

                BattlefieldRow(title: "Opponent lands", cards: landPermanents(opponent.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, flipped: true, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.opponentLandsRect.width, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.opponentLandsRect.width, height: metrics.opponentLandsRect.height)
                    .position(x: metrics.opponentLandsRect.midX, y: metrics.opponentLandsRect.midY)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        if InlinePaymentPromptState.isActive(in: snapshot) {
                            InlinePaymentPromptBar(
                                snapshot: snapshot,
                                pendingActionId: pendingActionId,
                                runAction: runAction,
                                runCommand: runCommand,
                                openDetails: openPromptDetails
                            )
                            .frame(maxWidth: .infinity)
                        } else if BoardDecisionPresentation.showsGuidance(snapshot) {
                            PromptPill(snapshot: snapshot, combatSelection: combatSelection,
                                       back: combatBackAction(in: snapshot))
                                .frame(maxWidth: .infinity)
                        }

                        let revealedCards = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                        let lookedAtCards = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                        if !revealedCards.isEmpty {
                            FloatingZoneChip(title: "Revealed", count: revealedCards.count, icon: "eye") {
                                inspectBoardZone(.collection(.revealed))
                            }
                        }
                        if !lookedAtCards.isEmpty {
                            FloatingZoneChip(title: "Looked", count: lookedAtCards.count, icon: "eye.trianglebadge.exclamationmark") {
                                inspectBoardZone(.collection(.lookedAt))
                            }
                        }
                    }
                    if let lastActionRejection {
                        ActionRejectionInlineView(notice: lastActionRejection) {
                            recover(from: lastActionRejection)
                        }
                    }
                }
                .frame(width: metrics.centerStripRect.width, height: metrics.centerStripRect.height)
                .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.midY)

                PortraitBattlefieldPermanentGroup(title: "Your board", cards: nonLandPermanents(human.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.permanentCardWidth, cardHeight: metrics.permanentCardHeight, rowWidth: metrics.playerBattlefieldRect.width, availableHeight: metrics.playerBattlefieldRect.height, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerBattlefieldRect.width, height: metrics.playerBattlefieldRect.height)
                    .position(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)

                BattlefieldRow(title: "Your lands", cards: landPermanents(human.zones.battlefield), legalActions: actions, targetableIds: targetableIds, combatHighlightIds: combatHighlights.cardIds, selectedCard: $selectedCard, inspectedCard: $inspectedCard, cardWidth: metrics.landCardWidth, cardHeight: metrics.landCardHeight, rowWidth: metrics.playerLandsRect.width, allowsManaUndo: true, manaPaymentActive: snapshot.manaPayment?.active == true, runAction: runAction, runTargetAction: { submitTarget($0, snapshot: snapshot) }, runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
                    .frame(width: metrics.playerLandsRect.width, height: metrics.playerLandsRect.height)
                    .position(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)

                PortraitHandRow(
                    cards: BoardOpponentFocus.seatHand(in: snapshot),
                    legalActions: actions,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    pendingCardInstanceId: pendingCardInstanceId,
                    interactionState: $interactionState,
                    playerDropZone: metrics.playerDropZone,
                    isOverPlayerDropZone: $isOverPlayerDropZone,
                    cardWidth: metrics.handCardWidth,
                    cardHeight: metrics.handCardHeight,
                    rowWidth: metrics.handRect.width,
                    onDropFeedback: onInteractionFeedback,
                    onActionChoice: { choiceActions, message in
                        dragActionChoice = DragActionChoice(message: message, actions: choiceActions)
                    },
                    runAction: runAction,
                    hiddenCount: snapshot.isViewer(human.playerId) ? nil : human.zones.visibleHandCount
                )
                .frame(width: metrics.handRect.width, height: metrics.handRect.height)
                .position(x: metrics.handRect.midX, y: metrics.handRect.midY)
                .onChange(of: derivedInteractionMode) { _, mode in
                    interactionState.mode = mode
                }

                if isOverPlayerDropZone {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(MagicPalette.antiqueGold.opacity(0.13))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MagicPalette.antiqueGold.opacity(0.70), lineWidth: 2))
                        .frame(width: metrics.playerDropZone.width, height: metrics.playerDropZone.height)
                        .position(x: metrics.playerDropZone.midX, y: metrics.playerDropZone.midY)
                        .allowsHitTesting(false)
                }

                if !snapshot.isSpectating {
                PortraitBottomCommandBar(
                    humanName: humanName,
                    human: human,
                    opponentId: opponent.playerId,
                    manaPool: human.manaPool,
                    passAction: passAction(in: actions),
                    yieldActions: GameplayActionPresentation.yieldActions(in: actions),
                    pendingActionId: pendingActionId,
                    snapshot: snapshot,
                    selectedCard: $selectedCard,
                    inspectedCard: $inspectedCard,
                    openLog: { isLogOpen = true },
                    openSettings: { isGameMenuOpen = true },
                    openPromptDetails: openPromptDetails,
                    viewZone: { localViewZone(title: $0, cards: $1) },
                    runAction: runAction,
                    runCommand: runCommand,
                    openStack: isTavernBoard ? { isTavernStackOpen = true } : nil
                )
                .frame(width: metrics.bottomControlsRect.width, height: metrics.bottomControlsRect.height)
                .position(x: metrics.bottomControlsRect.midX, y: metrics.bottomControlsRect.midY)
                .sheet(isPresented: $isTavernStackOpen) {
                    BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard)
                        .tavernSheet(true)
                }
                .onChange(of: isTavernStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
                }

                if CombatSelectionState.isDeclareAttackers(snapshot) {
                    let declaredAttackCount = snapshot.xmage?.combat.flatMap(\.attackers).count ?? 0
                    let hasPendingAttacker = !combatSelection.selectedAttackerIds.isEmpty
                    CombatSubmitPill(
                        title: hasPendingAttacker ? "Cancel Selection" : (declaredAttackCount == 0 ? "No Attacks" : "Done Attacking"),
                        count: max(declaredAttackCount, combatSelection.selectedAttackerIds.count)
                    ) {
                        if hasPendingAttacker {
                            combatSelection.clearAttackers()
                        } else {
                            finishAttackers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.maxY + 20)
                    .zIndex(19)
                } else if CombatSelectionState.isDeclareBlockers(snapshot) {
                    let declaredBlockCount = snapshot.xmage?.combat.flatMap(\.blockers).count ?? 0
                    let hasPendingBlocker = combatSelection.selectedBlockerId != nil
                    CombatSubmitPill(
                        title: hasPendingBlocker ? "Cancel Selection" : (declaredBlockCount == 0 ? "No Blocks" : "Done Blocking"),
                        count: max(declaredBlockCount, combatSelection.blockerPairCount)
                    ) {
                        if hasPendingBlocker {
                            combatSelection.clearBlockers()
                        } else if combatSelection.hasPendingBlockers {
                            submitBlockers(snapshot: snapshot)
                        } else {
                            finishBlockers(snapshot: snapshot)
                        }
                    }
                    .position(x: metrics.centerStripRect.midX, y: metrics.centerStripRect.maxY + 20)
                    .zIndex(19)
                }

                if let inspectingZoneTitle {
                    CompactZoneInspectorOverlay(
                        title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                        cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                        legalActions: actions,
                        pendingActionId: pendingActionId,
                        selectedCard: $selectedCard,
                        inspectedCard: $inspectedCard,
                        runAction: runAction,
                        closeAction: {
                            self.inspectingZoneTitle = nil
                            self.inspectingZoneCards = []
                            self.inspectingZoneReference = nil
                        },
                        targetableIDs: targetableIds,
                        runTargetAction: { submitTarget($0, snapshot: snapshot) }
                    )
                    .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                    .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(70)
                }

                if let inspectedCard {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { self.inspectedCard = nil }
                        .inspectionTouchPassthrough()
                        .zIndex(99)

                    CardInspector(card: inspectedCard)
                        .inspectionTouchPassthrough()
                        .frame(width: metrics.detailSheetRect.width, height: metrics.detailSheetRect.height)
                        .position(x: metrics.detailSheetRect.midX, y: metrics.detailSheetRect.midY)
                        .zIndex(100)
                }

                if shouldShowCompactPrompt && !isPromptDetailOpen && (targetableIds.isEmpty || targetableIds.contains(where: { id in snapshot.players.contains { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot).contains(id) } })) {
                    CompactPromptPopup(
                        snapshot: snapshot,
                        pendingActionId: pendingActionId,
                        runAction: runAction,
                        runCommand: runCommand,
                        openDetails: {
                            isPromptDetailOpen = true
                        }
                    )
                    .frame(width: metrics.compactPromptRect.width, height: metrics.compactPromptRect.height)
                    .position(x: metrics.compactPromptRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(20)
                }

                if let dragActionChoice {
                    DragActionChoicePopup(
                        choice: dragActionChoice,
                        pendingActionId: pendingActionId,
                        runAction: { action in
                            self.dragActionChoice = nil
                            selectedCard = nil
                            runAction(action)
                        },
                        cancel: {
                            self.dragActionChoice = nil
                            selectedCard = nil
                        }
                    )
                    .frame(width: metrics.compactPromptRect.width)
                    .position(x: metrics.compactPromptRect.midX, y: metrics.compactPromptRect.midY)
                    .transition(boardOverlayTransition)
                    .zIndex(21)
                }

                if snapshot.isWaitingOnAIOrStalled {
                    AIWaitFallbackControls(
                        snapshot: snapshot,
                        pendingActionId: pendingActionId,
                        liveUpdateStatus: liveUpdateStatus,
                        beganAt: aiWaitBeganAt,
                        didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                        didReconnect: didAutoReconnectAIWaitKey == aiWaitKey,
                        didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                        refreshAction: refreshGame,
                        reconnectAction: reconnectGame
                    )
                    .frame(width: min(metrics.safeFrame.width - 28, 360))
                    .position(x: metrics.safeFrame.midX, y: metrics.safeFrame.midY)
                    .zIndex(80)
                }
            }
            #if DEBUG
            .dynamicTypeSize(snapshot.id == "design-preview-large-text" ? .accessibility2 : dynamicTypeSize)
            #endif
            .preferredColorScheme(.dark)
            .coordinateSpace(name: "portrait-board")
            // Drawn layers only (arrows and effects): one hidden layer, so it never covers the cards for
            // VoiceOver or touch tests. The offscreen-combat markers are real buttons in their own overlay.
            .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                GeometryReader { geometry in
                    let bounds = anchors.mapValues { geometry[$0] }
                    if inspectingZoneTitle == nil && inspectedCard == nil {
                        PortraitCombatArrowOverlay(snapshot: snapshot, groups: snapshot.xmage?.combat ?? [],
                            previewArrows: combatPreviewArrows, metrics: metrics,
                            humanBattlefield: human.zones.battlefield,
                            opponentBattlefield: opponent.zones.battlefield, renderedBounds: bounds,
                            focusedOpponentID: opponent.playerId)
                    }
                    boardFXOverlay(bounds: bounds, snapshot: snapshot, opponentRect: metrics.opponentBattlefieldRect,
                        playerRect: metrics.playerBattlefieldRect, stackRect: metrics.centerStripRect, handRect: metrics.handRect,
                        viewerLife: bounds[TavernSeatAnchor.bottom].map { CGPoint(x: $0.midX, y: $0.minY - 8) }
                            ?? CGPoint(x: metrics.bottomHUDRect.minX + 34, y: metrics.bottomHUDRect.maxY - 78),
                        opponentLife: bounds[TavernSeatAnchor.top].map { CGPoint(x: $0.midX, y: $0.maxY + 10) }
                            ?? CGPoint(x: metrics.topHUDRect.minX + 44, y: metrics.topHUDRect.maxY + 26))
                }
                .allowsHitTesting(false)
                // Hidden alone does not take inside a preference overlay: an empty representation does.
                .accessibilityRepresentation { EmptyView() }
            }
            .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
                if inspectingZoneTitle == nil && inspectedCard == nil {
                    GeometryReader { geometry in
                        CombatEdgeIndicators(cards: human.zones.battlefield + opponent.zones.battlefield,
                            combatIDs: Set(CombatArrowModel.arrows(from: snapshot.xmage?.combat ?? [], previewArrows: combatPreviewArrows).flatMap { [$0.fromId, $0.toId] }),
                            bounds: anchors.mapValues { geometry[$0] },
                            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
                            laneIndices: CombatViewportAnchors.laneIndices(human: human.zones.battlefield, opponent: opponent.zones.battlefield),
                            inspect: { inspectedCard = $0 })
                    }
                }
            }
            .onAppear {
                interactionState.mode = derivedInteractionMode
                #if DEBUG
                if snapshot.id == "design-preview-zone-inspection" { inspectBoardZone(.player(playerID: snapshot.viewerID, zone: .graveyard)) }
                #endif
            }
            .onChange(of: snapshot.combatSelectionResetKey) { _, _ in
                combatSelection.resetIfInactive(snapshot)
                combatPreviewArrows = []
            }
            .onChange(of: pendingActionId) { _, newValue in
                if newValue == nil {
                    combatPreviewArrows = []
                }
            }
        }
    }

    private func passAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "pass_priority" }
            ?? actions.first { $0.type == "pass_until_response" }
    }

    private func concedeAction(in actions: [LegalAction]) -> LegalAction? {
        actions.first { $0.type == "concede" }
    }

    private func selectedActions(in snapshot: GameSnapshot) -> [LegalAction] {
        guard let selectedCard else { return [] }
        return GameBoardInteractionState.cardActions(for: selectedCard, actions: snapshot.legalActions ?? [])
    }

    /// Your creatures already declared in this combat step: attacking while you declare
    /// attackers, blocking while you declare blockers.
    private func declaredCombatCards(in snapshot: GameSnapshot) -> [ZoneCard] {
        guard let human = snapshot.human else { return [] }
        let step = (snapshot.step ?? snapshot.phase).lowercased().replacingOccurrences(of: "_", with: "-")
        let attackers = step.contains("declare-attack")
        let blockers = step.contains("declare-block")
        return human.zones.battlefield.filter { card in
            (attackers && card.isAttacking == true) || (blockers && !(card.blocking ?? []).isEmpty)
        }
    }

    /// Back while declaring attackers or blockers: select the latest declared creature again,
    /// which XMage takes as taking it back (the creature stays an exposed target).
    private func combatBackAction(in snapshot: GameSnapshot) -> (() -> Void)? {
        guard pendingActionId == nil else { return nil }
        let targetable = targetableCardIds(in: snapshot)
        let candidates = declaredCombatCards(in: snapshot).filter { targetable.contains($0.id) || targetable.contains($0.instanceId) }
        guard let fallback = candidates.last else { return nil }
        let latest = combatDeclarationOrder.last { id in candidates.contains { $0.id == id } }
        let card = candidates.first { $0.id == latest } ?? fallback
        return {
            GameHaptics.selection()
            submitTarget(card, snapshot: snapshot)
            onInteractionFeedback("Took back \(card.card.name)")
        }
    }

    private func targetableCardIds(in snapshot: GameSnapshot) -> Set<String> {
        GameBoardInteractionState.boardTargetableIds(for: snapshot)
    }

    private func submitTarget(_ card: ZoneCard, snapshot: GameSnapshot) {
        guard targetableCardIds(in: snapshot).contains(card.instanceId) || targetableCardIds(in: snapshot).contains(card.id) else {
            GameHaptics.warning()
            onInteractionFeedback("\(card.card.name) is not an exposed XMage target")
            return
        }
        guard let prompt = snapshot.promptEnvelopeV2 else {
            GameHaptics.warning()
            onInteractionFeedback("XMage target prompt is no longer active")
            return
        }
        if (prompt.maxChoices ?? 1) > 1 || (prompt.minChoices ?? 1) > 1 {
            selectedCard = card
            isPromptDetailOpen = true
            return
        }
        let promptId = prompt.responseCommand?.promptId ?? prompt.id
        guard let command = UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: prompt,
            type: "choose_target",
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [card.instanceId]
        ) else {
            GameHaptics.warning()
            onInteractionFeedback("XMage did not expose a mobile-safe target command")
            return
        }
        GameHaptics.success()
        runCommand(command, "Target \(card.card.name)", "\(promptId)-\(card.instanceId)")
    }

    private func handleCombatCardTap(_ card: ZoneCard, snapshot: GameSnapshot) -> Bool {
        let actions = snapshot.legalActions ?? []
        if CombatSelectionState.isDeclareAttackers(snapshot) {
            if let attackerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.attackerHighlightIds(actions: actions)) {
                let defenders = combatSelection.defenderIds(forAttackerId: attackerId, actions: actions)
                combatSelection.selectAttacker(attackerId)
                if defenders.count == 1, let defenderId = defenders.first {
                    submitAttackers(defenderId: defenderId, snapshot: snapshot)
                    onInteractionFeedback("Combat selection sent")
                } else {
                    onInteractionFeedback("Choose who to attack")
                }
                return true
            }
            if let defenderId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.defenderHighlightIds(actions: actions)) {
                guard combatSelection.selectedAttackerId != nil else {
                    onInteractionFeedback("Select an attacker first")
                    return true
                }
                submitAttackers(defenderId: defenderId, snapshot: snapshot)
                return true
            }
        }

        if CombatSelectionState.isDeclareBlockers(snapshot) {
            if let blockerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.blockerHighlightIds(actions: actions)) {
                let attackers = combatSelection.attackingCreatureIds(forBlockerId: blockerId, actions: actions, combatGroups: snapshot.xmage?.combat ?? [])
                combatSelection.selectBlocker(blockerId)
                if attackers.count == 1, let attackerId = attackers.first {
                    combatSelection.pairSelectedBlocker(withAttackerId: attackerId)
                    submitBlockers(snapshot: snapshot)
                    onInteractionFeedback("Block selection sent")
                } else {
                    onInteractionFeedback("Choose attacker to block")
                }
                return true
            }
            if let attackerId = CombatSelectionState.matchingCardId(for: card, in: combatSelection.attackingCreatureHighlightIds(actions: actions, combatGroups: snapshot.xmage?.combat ?? [])) {
                guard combatSelection.selectedBlockerId != nil else {
                    onInteractionFeedback("Select a blocker first")
                    return true
                }
                combatSelection.pairSelectedBlocker(withAttackerId: attackerId)
                submitBlockers(snapshot: snapshot)
                onInteractionFeedback("Block selection sent")
                return true
            }
        }

        return false
    }

    private func submitAttackers(defenderId: String, snapshot: GameSnapshot) {
        let actions = snapshot.legalActions ?? []
        guard !combatSelection.selectedAttackerIds.isEmpty else {
            onInteractionFeedback("Select at least one attacker first")
            return
        }
        guard combatSelection.defenderHighlightIds(actions: actions).contains(defenderId) else {
            onInteractionFeedback("XMage did not expose that defender")
            return
        }
        guard let human = snapshot.human else { return }
        guard let command = combatSelection.attackCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            defenderId: defenderId,
            actions: actions,
            expectedBridgeRevision: snapshot.bridgeRevision
        ) else {
            onInteractionFeedback("XMage did not expose mobile-safe attacker data")
            return
        }
        let removesExistingAttack = command.attackers?.allSatisfy { pair in
            guard let defenderId = pair.defenderId else { return false }
            return (snapshot.xmage?.combat ?? []).contains { group in
                group.defenderId == defenderId && group.attackers.contains { card in
                    card.instanceId == pair.attackerId || card.id == pair.attackerId
                }
            }
        } == true
        combatPreviewArrows = removesExistingAttack ? [] : command.attackers?.compactMap { pair in
            guard let defenderId = pair.defenderId else { return nil }
            return CombatArrow(kind: .previewAttack, fromId: pair.attackerId, toId: defenderId, toKind: combatSelection.defenderKind(forDefenderId: defenderId, actions: actions))
        } ?? []
        runCommand(command, removesExistingAttack ? "Remove attacker" : "Declare attacker", "declare-attacker-\(snapshot.bridgeRevision ?? snapshot.turn)-\(defenderId)")
        combatSelection.clearAttackers()
    }

    private func submitBlockers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        guard let command = combatSelection.pendingBlockActionPayload(
            playerId: human.playerId,
            gameId: snapshot.id,
            expectedBridgeRevision: snapshot.bridgeRevision
        ) else {
            onInteractionFeedback("Select a blocker and the attacker it blocks")
            return
        }
        combatPreviewArrows = command.blockers?.compactMap { pair in
            guard let attackerId = pair.attackerId else { return nil }
            return CombatArrow(kind: .previewBlock, fromId: pair.blockerId, toId: attackerId, toKind: nil)
        } ?? []
        runCommand(command, "Declare blocker", "declare-blocker-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearBlockers()
    }

    private func finishAttackers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        let command = CombatSelectionState.finishAttackCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            expectedBridgeRevision: snapshot.bridgeRevision
        )
        runCommand(command, "Finish attackers", "declare-attackers-finish-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearAttackers()
    }

    private func finishBlockers(snapshot: GameSnapshot) {
        guard let human = snapshot.human else { return }
        let command = CombatSelectionState.finishBlockCommand(
            gameId: snapshot.id,
            playerId: human.playerId,
            expectedBridgeRevision: snapshot.bridgeRevision
        )
        runCommand(command, "Finish blockers", "declare-blockers-finish-\(snapshot.bridgeRevision ?? snapshot.turn)")
        combatSelection.clearBlockers()
    }

    private func designPreviewState(from snapshot: GameSnapshot) -> GameBoardDesignPreviewState {
        let raw = snapshot.id.replacingOccurrences(of: "design-preview-", with: "")
        return GameBoardDesignPreviewState(rawValue: raw) ?? .normalBattlefield
    }

    private func landPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        BattlefieldAttachments.lane(ownedCards: cards, allCards: snapshot?.players.flatMap { $0.zones.battlefield } ?? cards, lands: true, playerIDs: Set(snapshot?.players.map(\.playerId) ?? []))
    }

    private func landscapePermanents(_ cards: [ZoneCard], resources: Bool) -> [ZoneCard] {
        BattlefieldAttachments.lane(ownedCards: cards, allCards: snapshot?.players.flatMap { $0.zones.battlefield } ?? cards, lands: resources, playerIDs: Set(snapshot?.players.map(\.playerId) ?? []), includesManaRocks: true)
    }

    private func nonLandPermanents(_ cards: [ZoneCard]) -> [ZoneCard] {
        BattlefieldAttachments.lane(ownedCards: cards, allCards: snapshot?.players.flatMap { $0.zones.battlefield } ?? cards, lands: false, playerIDs: Set(snapshot?.players.map(\.playerId) ?? []))
    }
}

/// The phase cue's backing: a dark pill, or on the tavern board a leather ribbon in brass.
private struct PhaseCueChrome: ViewModifier {
    let tavern: Bool

    func body(content: Content) -> some View {
        if tavern && TavernUIKit.available {
            content
                .background { TavernFill(material: .leather).clipShape(RoundedRectangle(cornerRadius: 5.4)) }
                .overlay { TavernBrassFrame(scale: 0.45) }
        } else {
            content
                .background(MagicPalette.iron.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.7), lineWidth: 1))
        }
    }
}

/// Keeps the order in which your attackers or blockers were declared, oldest first.
private struct CombatDeclarationObserver: ViewModifier {
    let ids: [String]
    @Binding var order: [String]

    func body(content: Content) -> some View {
        content.onChange(of: ids) { _, current in
            order = order.filter(current.contains) + current.filter { !order.contains($0) }
        }
    }
}
