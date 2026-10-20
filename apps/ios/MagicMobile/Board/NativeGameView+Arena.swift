import SwiftUI
import UIKit

/// An Auto Pay in progress: the payment states it has already acted on, so it stops instead of tapping in circles.
struct ArenaAutoPayRun: Equatable {
    var steps = 0
    var signatures: Set<String> = []
}

/// The Arena board (BoardMode.arena), laid out by ArenaLayout on the leaning tavern table. Everything the board does
/// goes through the same commands as the Hearth board: BattlefieldRow for permanents, the hand's drop resolver,
/// submitTarget and the combat helpers, PlayerZoneMenu for zones and the commander, GameActionDockModel for passing.
extension NativeGameView {
    func arenaBoard(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, rootProxy: GeometryProxy) -> some View {
        let screen = CGSize(width: rootProxy.size.width + rootProxy.safeAreaInsets.leading + rootProxy.safeAreaInsets.trailing,
                            height: rootProxy.size.height + rootProxy.safeAreaInsets.top + rootProxy.safeAreaInsets.bottom)
        let canvas = ArenaCanvas(screen: screen)
        return ZStack {
            ArenaTableBackdrop()
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { arenaTapTable(snapshot: snapshot) }
                .accessibilityHidden(true)
            arenaTable(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas)
        }
        .frame(width: screen.width, height: screen.height)
        .coordinateSpace(name: "portrait-board")
        .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
            arenaDrawnLayers(anchors: anchors, snapshot: snapshot, human: human, opponent: opponent, canvas: canvas)
        }
        .ignoresSafeArea()
        .environment(\.tavernBoard, true)
        .environment(\.arenaBoard, true)
        .modifier(ArenaAutoPayDriver(key: "\(snapshot.bridgeRevision ?? -1)|\(pendingActionId ?? "")",
                                     active: arenaAutoPay != nil || arenaAttackQueue != nil) {
            arenaAutoPayStep(snapshot: snapshot)
            arenaAttackStep(snapshot: snapshot)
        })
        .onChange(of: snapshot.step ?? snapshot.phase) { _, _ in arenaTucked = false }
        .onChange(of: InlinePaymentPromptState.isActive(in: snapshot)) { _, paying in if !paying { arenaAutoPay = nil } }
        .onAppear {
            interactionState.mode = GameBoardInteractionState.mode(for: snapshot, pendingActionId: pendingActionId, selectedCard: selectedCard)
            GameAudio.shared.preload(GameAudio.boardSounds)
        }
        .onChange(of: GameBoardInteractionState.mode(for: snapshot, pendingActionId: pendingActionId, selectedCard: selectedCard)) { _, mode in
            if case .draggingCard = interactionState.mode { return }
            interactionState.mode = mode
        }
        .onChange(of: snapshot.combatSelectionResetKey) { _, _ in
            combatSelection.resetIfInactive(snapshot)
            combatPreviewArrows = []
        }
        .onChange(of: pendingActionId) { _, newValue in if newValue == nil { combatPreviewArrows = [] } }
    }

    // MARK: Layers

    @ViewBuilder
    private func arenaTable(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let posture = arenaHandPosture(snapshot: snapshot)
        let controlsOnTop = arenaControlsOnTop(snapshot: snapshot)
        arenaLanes(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas)
        if isOverPlayerDropZone {
            RoundedRectangle(cornerRadius: 16)
                .fill(TavernPalette.ember.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TavernPalette.ember.opacity(0.55), lineWidth: 2))
                .frame(width: canvas.area(canvas.layout.dropArea).width, height: canvas.area(canvas.layout.dropArea).height)
                .position(x: canvas.area(canvas.layout.dropArea).midX, y: canvas.area(canvas.layout.dropArea).midY)
                .allowsHitTesting(false)
        }
        arenaOpponentSeat(snapshot: snapshot, opponent: opponent, canvas: canvas)
        arenaStack(snapshot: snapshot, canvas: canvas)
        arenaCaption(snapshot: snapshot, canvas: canvas)
        arenaViewerSeat(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas)
        if let railTop = canvas.layout.railTop {
            // The front rail drawn again over a resting hand, so the hand tucks behind the table's edge.
            ArenaFrontRail(top: canvas.y(railTop))
                .zIndex(posture == .resting ? 60 : 40)
        }
        arenaHand(snapshot: snapshot, human: human, canvas: canvas, posture: posture)
            .zIndex(50)
        if !snapshot.isSpectating {
            arenaControls(snapshot: snapshot, canvas: canvas)
                .zIndex(controlsOnTop || posture == .resting ? 70 : 45)
        }
        arenaOverlays(snapshot: snapshot, human: human, canvas: canvas)
            .zIndex(90)
    }

    /// Opponent's lands at their edge, their creatures toward the middle; yours mirrored. BattlefieldRow keeps grouping,
    /// attachments, targeting, combat taps and mana undo exactly as on the Hearth board.
    @ViewBuilder
    private func arenaLanes(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let layout = canvas.layout
        let actions = snapshot.legalActions ?? []
        let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        let chosenIds = GameBoardInteractionState.boardChosenTargetIds(for: snapshot)
        let highlights = CombatHighlightSet(selection: combatSelection, actions: actions, combatGroups: snapshot.xmage?.combat ?? []).cardIds
        let opponentCreatures = landscapePermanents(opponent.zones.battlefield, resources: false)
        let viewerCreatures = landscapePermanents(human.zones.battlefield, resources: false)
        // Portrait grows a second row toward its owner; landscape keeps one row that scrolls (no room between the lanes).
        let opponentRows = layout.landscape ? 1 : ArenaLayout.creatureRows(groups: BattlefieldAttachments.groups(opponentCreatures).count)
        let viewerRows = layout.landscape ? 1 : ArenaLayout.creatureRows(groups: BattlefieldAttachments.groups(viewerCreatures).count)
        let opponentLane = canvas.area(layout.creatureLane(viewer: false, rows: opponentRows))
        let viewerLane = canvas.area(layout.creatureLane(viewer: true, rows: viewerRows))
        let tile = canvas.size(layout.tile), land = canvas.size(layout.land)
        let paying = snapshot.manaPayment?.active == true
        arenaLane(title: "Opponent lands", cards: landscapePermanents(opponent.zones.battlefield, resources: true), rect: canvas.area(layout.opponentLands),
                  card: land, flipped: true, resources: true, snapshot: snapshot, targetableIds: targetableIds, chosenIds: chosenIds,
                  highlights: highlights, viewer: false, paying: paying)
        arenaLane(title: "Opponent board", cards: opponentCreatures, rect: opponentLane, card: tile, flipped: true, resources: false,
                  snapshot: snapshot, targetableIds: targetableIds, chosenIds: chosenIds, highlights: highlights, viewer: false, paying: paying)
        arenaLane(title: "Your board", cards: viewerCreatures, rect: viewerLane, card: tile, flipped: false, resources: false,
                  snapshot: snapshot, targetableIds: targetableIds, chosenIds: chosenIds, highlights: highlights, viewer: true, paying: paying)
        arenaLane(title: "Your lands", cards: landscapePermanents(human.zones.battlefield, resources: true), rect: canvas.area(layout.viewerLands),
                  card: land, flipped: false, resources: true, snapshot: snapshot, targetableIds: targetableIds, chosenIds: chosenIds,
                  highlights: highlights, viewer: true, paying: paying)
    }

    // swiftlint:disable:next function_parameter_count
    private func arenaLane(title: String, cards: [ZoneCard], rect: CGRect, card: CGSize, flipped: Bool, resources: Bool,
                           snapshot: GameSnapshot, targetableIds: Set<String>, chosenIds: Set<String>, highlights: Set<String>,
                           viewer: Bool, paying: Bool) -> some View {
        BattlefieldRow(title: title, cards: cards, legalActions: snapshot.legalActions ?? [], targetableIds: targetableIds,
                       chosenIds: chosenIds, combatHighlightIds: highlights, selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                       flipped: flipped, cardWidth: card.width, cardHeight: card.height, rowWidth: rect.width,
                       adaptsToDensity: true, availableHeight: rect.height, arrangement: resources ? .landscapeResources : .automatic,
                       allowsManaUndo: viewer, manaPaymentActive: paying, alignment: resources ? .leading : .center, runAction: runAction,
                       runTargetAction: { submitTarget($0, snapshot: snapshot) },
                       runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func arenaOpponentSeat(snapshot: GameSnapshot, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let layout = canvas.layout
        ArenaOpponentHandFan(count: opponent.zones.visibleHandCount, card: canvas.size(layout.opponentHandCard),
                             pitch: canvas.length(layout.opponentHandPitch))
            .position(canvas.point(layout.opponentHand))
        ArenaDeckPile(count: opponent.zones.visibleLibraryCount, size: canvas.size(layout.opponentPile),
                      label: "\(snapshot.playerLabel(opponent.playerId))'s library, \(opponent.zones.visibleLibraryCount) cards")
            .overlay {
                // A revealed top card (Courser of Kruphix, Future Sight…) lies face up on the deck.
                if let top = opponent.zones.library.first {
                    TopOfLibraryCard(card: top, owner: "\(snapshot.playerLabel(opponent.playerId))'s", height: canvas.size(layout.opponentPile).height) {
                        localViewZone(title: "Top of \(snapshot.playerLabel(opponent.playerId))'s library", cards: [top])
                    }
                }
            }
            .position(canvas.point(layout.opponentLibrary))
        ArenaGraveyardPile(cards: opponent.zones.graveyard, size: canvas.size(layout.opponentPile),
                           label: "\(snapshot.playerLabel(opponent.playerId))'s graveyard") {
            inspectBoardZone(.player(playerID: opponent.playerId, zone: .graveyard))
        }
        .position(canvas.point(layout.opponentGraveyard))
        let medallionCenter = canvas.point(layout.opponentMedallion)
        let medallionRadius = canvas.length(layout.opponentMedallionDiameter) / 2
        // Commander damage, poison, the monarch… curve around the medallion, toward the table.
        TavernEffectOrbitBadges(summary: PlayerStatusSummary(player: opponent, snapshot: snapshot), center: medallionCenter,
                                radius: medallionRadius + 14, bearingDegrees: layout.landscape ? 90 : 45, limit: layout.landscape ? 5 : 3)
        if !opponent.zones.exile.isEmpty {
            ArenaGraveyardPile(cards: opponent.zones.exile, size: canvas.size(layout.opponentPile),
                               label: "\(snapshot.playerLabel(opponent.playerId))'s exile", exile: true) {
                inspectBoardZone(.player(playerID: opponent.playerId, zone: .exile))
            }
            .position(canvas.point(layout.opponentExile))
        }
        arenaOpponentMedallion(snapshot: snapshot, opponent: opponent, canvas: canvas)
            .position(medallionCenter)
        if snapshot.thinkingPlayerID == opponent.playerId {
            Text("Thinking…")
                .font(.system(size: 11, weight: .semibold, design: .serif)).italic()
                .foregroundStyle(TavernPalette.parchment.opacity(0.85))
                .shadow(color: .black, radius: 2)
                .fixedSize()
                .position(x: medallionCenter.x + (layout.landscape ? medallionRadius + 40 : 0),
                          y: medallionCenter.y + (layout.landscape ? 0 : medallionRadius + 12))
                .allowsHitTesting(false)
                .accessibilityLabel("\(snapshot.playerLabel(opponent.playerId)) is thinking")
        }
        arenaGameMenu(snapshot: snapshot)
            .position(canvas.point(layout.menu))
    }

    private func arenaOpponentMedallion(snapshot: GameSnapshot, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let diameter = canvas.length(canvas.layout.opponentMedallionDiameter)
        let defenders = CombatHighlightSet(selection: combatSelection, actions: snapshot.legalActions ?? [],
                                           combatGroups: snapshot.xmage?.combat ?? []).defenderIds
        let attackID = CombatPlayerIdentity.targetID(for: opponent.playerId, in: snapshot, candidates: defenders)
        let targetID = arenaPlayerTargetID(opponent.playerId, snapshot: snapshot)
        let name = snapshot.playerLabel(opponent.playerId)
        let medallion = ArenaHeroMedallion(player: opponent, diameter: diameter, active: snapshot.activePlayerId == opponent.playerId,
                                           glow: attackID != nil && !combatSelection.selectedAttackerIds.isEmpty ? ArenaPalette.attackGlow
                                               : targetID != nil ? ArenaPalette.targetGlow : nil)
            .overlay { if let turnClockFeed, let playerName = opponent.displayName {
                TurnClockRing(feed: turnClockFeed, playerName: playerName, diameter: diameter * 1.08)
            } }
            .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [TavernSeatAnchor.top: $0] }
        let label = opponent.isOut ? "\(name), out of the game" : "\(name), \(opponent.life) life"
        return Group {
            if let attackID, !combatSelection.selectedAttackerIds.isEmpty {
                Button { submitAttackers(defenderId: attackID, snapshot: snapshot) } label: { medallion }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label).accessibilityHint("Attacks this player")
            } else if let targetID {
                Button { arenaSubmitPlayerTarget(targetID, snapshot: snapshot) } label: { medallion }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label).accessibilityHint("Chooses this player")
            } else {
                PlayerZoneMenu(player: opponent, viewZone: { localViewZone(title: $0, cards: $1) },
                               customLabel: AnyView(medallion.frame(width: diameter + 8, height: diameter + 8)),
                               accessibilityOverride: (label, "board.zones.\(opponent.playerId)"), menuArrowEdge: .top,
                               statusSnapshot: snapshot, swapOpponents: BoardOpponentFocus.opponents(in: snapshot),
                               swap: { focusTracker.select($0) })
            }
        }
        .overlay(alignment: .bottom) {
            if let emoteCenter {
                OpponentEmoteSlot(center: emoteCenter, snapshot: snapshot, focusedID: opponent.playerId)
                    .fixedSize().offset(y: diameter * 0.9)
            }
        }
    }

    @ViewBuilder
    private func arenaViewerSeat(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let layout = canvas.layout
        ArenaDeckPile(count: human.zones.visibleLibraryCount, size: canvas.size(layout.viewerPile),
                      label: "Your library, \(human.zones.visibleLibraryCount) cards")
            .overlay {
                if let top = human.zones.library.first {
                    TopOfLibraryCard(card: top, playable: GameplayAffordances.castableZones(player: human, snapshot: snapshot,
                                     pendingActionID: pendingActionId).contains(.library), owner: "your",
                                     height: canvas.size(layout.viewerPile).height) {
                        localViewZone(title: "Top of your library", cards: [top])
                    }
                }
            }
            .position(canvas.point(layout.viewerLibrary))
        ArenaGraveyardPile(cards: human.zones.graveyard, size: canvas.size(layout.viewerPile), label: "Your graveyard") {
            inspectBoardZone(.player(playerID: human.playerId, zone: .graveyard))
        }
        .position(canvas.point(layout.viewerGraveyard))
        if !human.zones.exile.isEmpty {
            ArenaGraveyardPile(cards: human.zones.exile, size: canvas.size(layout.viewerPile), label: "Your exile", exile: true) {
                inspectBoardZone(.player(playerID: human.playerId, zone: .exile))
            }
            .position(canvas.point(layout.viewerExile))
        }
        arenaViewerMedallion(snapshot: snapshot, human: human, canvas: canvas)
            .position(canvas.point(layout.viewerMedallion))
            .zIndex(65)
        if let pool = human.manaPool, pool.W + pool.U + pool.B + pool.R + pool.G + pool.C > 0 {
            // The reference's floating mana: plain symbols by your portrait. XMage still asks for floating mana while
            // you pay, so a symbol takes a tap then (Auto Pay spends it first).
            ArenaFloatingMana(pool: pool, payable: GameplayAffordances.floatingManaSymbols(in: snapshot, pendingActionID: pendingActionId)) { symbol in
                if pendingActionId == nil, let command = GameplayAffordances.floatingManaCommand(symbol: symbol, in: snapshot) {
                    runCommand(command, "Spend floating {\(symbol)}", "floating-\(snapshot.promptEnvelopeV2?.id ?? "")-\(symbol)")
                }
            }
            .fixedSize()
            // Landscape: beside your graveyard, clear of the hand; portrait: on the table just above a resting hand.
            .position(canvas.point(layout.floatingMana))
            .zIndex(66)
        }
    }

    private func arenaViewerMedallion(snapshot: GameSnapshot, human: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let diameter = canvas.length(canvas.layout.viewerMedallionDiameter)
        let castable = GameplayAffordances.castableZones(player: human, snapshot: snapshot, pendingActionID: pendingActionId)
        let targetID = arenaPlayerTargetID(human.playerId, snapshot: snapshot)
        let medallion = ArenaHeroMedallion(player: human, diameter: diameter, active: snapshot.isViewer(snapshot.activePlayerId),
                                           glow: targetID != nil ? ArenaPalette.targetGlow : nil, commanderReady: !castable.isEmpty)
            .overlay { if let turnClockFeed { TurnClockRing(feed: turnClockFeed, diameter: diameter * 1.08) } }
            .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { [TavernSeatAnchor.bottom: $0] }
        return Group {
            if let targetID {
                Button { arenaSubmitPlayerTarget(targetID, snapshot: snapshot) } label: { medallion }
                    .buttonStyle(.plain)
                    .accessibilityLabel("You, \(human.life) life").accessibilityHint("Chooses you")
            } else {
                PlayerZoneMenu(player: human, viewZone: { localViewZone(title: $0, cards: $1) }, snapshot: snapshot,
                               pendingActionID: pendingActionId,
                               customLabel: AnyView(medallion.frame(width: diameter + 8, height: diameter + 8)),
                               accessibilityOverride: ("Your life: \(human.life)\(PortraitBottomCommandBar.castableDescription(castable))", "board.lifeOrb"))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Poison and commander damage at a glance; the medallion's pop-over lists every status.
            TavernStatusGlance(summary: PlayerStatusSummary(player: human, snapshot: snapshot))
                .offset(x: diameter * 0.3, y: diameter * 0.05)
        }
        .overlay(alignment: .top) {
            if let emoteCenter {
                HStack(spacing: 4) {
                    EmoteBubbleSlot(center: emoteCenter, playerID: human.playerId).fixedSize()
                    TableChatButton(center: emoteCenter)
                }
                .offset(y: -diameter * 0.85)
            }
        }
    }

    @ViewBuilder
    private func arenaStack(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let objects = snapshot.stackTopFirst
        if let top = objects.first {
            let rect = canvas.rect(canvas.layout.stack)
            ArenaStackCard(object: top, count: snapshot.xmage?.stack.count ?? objects.count, size: rect.size,
                           inspect: { inspectedCard = $0 }, openStack: { isTavernStackOpen = true })
                .id(top.id)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .position(x: rect.midX, y: rect.midY)
                .sheet(isPresented: $isTavernStackOpen) {
                    BoardStackInspector(snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard, runCommand: runCommand)
                        .tavernSheet(true)
                }
                .onChange(of: isTavernStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
                .zIndex(30)
        }
    }

    @ViewBuilder
    private func arenaCaption(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let y = canvas.y(canvas.layout.captionY)
        VStack(spacing: 6) {
            if let text = arenaNotice ?? arenaCaptionText(snapshot: snapshot) {
                ArenaPromptCaption(text: text)
            }
            HStack(spacing: 8) {
                let revealed = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
                let lookedAt = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
                if !revealed.isEmpty {
                    FloatingZoneChip(title: "Revealed", count: revealed.count, icon: "eye") { inspectBoardZone(.collection(.revealed)) }
                }
                if !lookedAt.isEmpty {
                    FloatingZoneChip(title: "Looked", count: lookedAt.count, icon: "eye.trianglebadge.exclamationmark") {
                        inspectBoardZone(.collection(.lookedAt))
                    }
                }
            }
            if let lastActionRejection {
                ActionRejectionInlineView(notice: lastActionRejection) { recover(from: lastActionRejection) }
                    .frame(maxWidth: min(canvas.screen.width - 40, 420))
            }
        }
        .frame(maxWidth: canvas.screen.width * (canvas.layout.landscape ? 0.6 : 0.9))
        .position(x: canvas.layout.landscape ? canvas.x(478) : canvas.screen.width / 2, y: y)
        .zIndex(35)
    }

    private func arenaHand(snapshot: GameSnapshot, human: PlayerGameState, canvas: ArenaCanvas, posture: ArenaHandPosture) -> some View {
        ArenaHandFan(cards: BoardOpponentFocus.seatHand(in: snapshot),
                     extraCards: snapshot.isViewer(human.playerId) ? ArenaExtraHand.cards(for: human, actions: snapshot.legalActions ?? []) : [],
                     legalActions: snapshot.legalActions ?? [],
                     pendingCardInstanceId: pendingCardInstanceId, canvas: canvas, posture: posture,
                     inspectedCard: $inspectedCard, interactionState: $interactionState, isOverPlayerDropZone: $isOverPlayerDropZone,
                     liftedCardID: $arenaLiftedCardID,
                     hiddenCount: snapshot.isViewer(human.playerId) ? nil : human.zones.visibleHandCount,
                     raise: { arenaTucked = false },
                     onDropFeedback: onInteractionFeedback,
                     onActionChoice: { actions, message in dragActionChoice = DragActionChoice(message: message, actions: actions) },
                     runAction: runAction)
    }

    // MARK: Controls

    @ViewBuilder
    private func arenaControls(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let layout = canvas.layout
        let plan = arenaButtonPlan(snapshot: snapshot)
        let primaryRect = canvas.rect(layout.primary), secondaryRect = canvas.rect(layout.secondary)
        let stripWidth = canvas.length(layout.phaseStripX.upperBound - layout.phaseStripX.lowerBound)
        let stripX = canvas.x((layout.phaseStripX.lowerBound + layout.phaseStripX.upperBound) / 2)
        ArenaPhaseStrip(step: snapshot.step ?? snapshot.phase, viewerTurn: snapshot.isViewer(snapshot.activePlayerId),
                        width: stripWidth, iconSize: canvas.length(layout.landscape ? 17 : 16))
            .position(x: stripX, y: canvas.y(plan.secondary == nil ? layout.phaseStripY : layout.phaseStripRaisedY))
            .onTapGesture { arenaShowPhaseStops = true }
        TavernTableHints(dayNight: snapshot.dayNight, stormCount: snapshot.stormCount)
            .fixedSize()
            .position(x: stripX, y: canvas.y((plan.secondary == nil ? layout.phaseStripY : layout.phaseStripRaisedY) - 18))
            .allowsHitTesting(false)
        if let secondary = plan.secondary {
            arenaButton(secondary, rect: secondaryRect, fontSize: canvas.length(layout.landscape ? 17 : 16))
        }
        if let primary = plan.primary {
            arenaButton(primary, rect: primaryRect, fontSize: canvas.length(layout.landscape ? 19 : 18))
                .modifier(FullControlHold(control: nativeTurnControl, swallowNextPass: $arenaSwallowNextPass, tavern: false))
                .accessibilityIdentifier("board.action.primary")
        }
        ArenaPassAheadPill()
            .frame(width: canvas.rect(layout.passAhead).width, height: canvas.rect(layout.passAhead).height)
            .position(x: canvas.rect(layout.passAhead).midX, y: canvas.rect(layout.passAhead).midY)
        if let undo = ManaPaymentTray.manaUndoActions(in: snapshot).first(where: { $0.type == "undo_mana" }) {
            Button { runAction(undo) } label: {
                HStack(spacing: 3) { Text("Undo"); Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .black)) }
            }
            .buttonStyle(ArenaPillStyle())
            .disabled(pendingActionId != nil)
            .frame(width: canvas.rect(layout.undo).width, height: canvas.rect(layout.undo).height)
            .position(x: canvas.rect(layout.undo).midX, y: canvas.rect(layout.undo).midY)
            .accessibilityLabel("Undo mana")
        }
    }

    private func arenaButton(_ button: ArenaButtonPlan.Choice, rect: CGRect, fontSize: CGFloat) -> some View {
        Button {
            if arenaSwallowNextPass { arenaSwallowNextPass = false; return }
            button.action()
        } label: {
            VStack(spacing: 0) {
                Text(button.title)
                if let subtitle = button.subtitle {
                    Text(subtitle.uppercased()).font(.system(size: fontSize * 0.42, weight: .heavy, design: .serif)).tracking(1).opacity(0.85)
                }
            }
        }
        .buttonStyle(ArenaPlaqueButtonStyle(kind: button.kind, fontSize: fontSize))
        .disabled(!button.enabled)
        .frame(width: rect.width, height: max(44, rect.height + 8))
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(button.subtitle.map { "\(button.title), \($0)" } ?? button.title)
        .id("\(button.title)|\(snapshot?.promptEnvelopeV2?.id ?? "")|\(snapshot?.promptEnvelopeV2?.messageId ?? -1)")
    }

    /// The brass gear: the log, the stack, phase stops, full control and the game's settings, in a leather pop-over.
    private func arenaGameMenu(snapshot: GameSnapshot) -> some View {
        TavernMenu(arrowEdge: .top) {
            TavernMenuItem(title: "Game Log", systemImage: "list.bullet.rectangle") { isLogOpen = true }
            if !snapshot.stackTopFirst.isEmpty {
                TavernMenuItem(title: "Stack (\(snapshot.stackTopFirst.count))", systemImage: "square.stack.3d.up") { isTavernStackOpen = true }
            }
            TavernMenuItem(title: "Phase Stops", systemImage: "pause.circle") { arenaShowPhaseStops = true }
            if let control = nativeTurnControl {
                TavernMenuItem(title: control.isFullControl ? "Full control: on (this turn)" : "Full control this turn",
                               systemImage: "hand.raised.fill", action: control.toggleFullControl)
            }
            if snapshot.source == "xmage-ondevice" {
                TavernMenuItem(title: "More actions", systemImage: "ellipsis") { openPromptDetails() }
            }
            TavernMenuDivider()
            TavernMenuItem(title: "Game Settings", systemImage: "gearshape.fill") { isGameMenuOpen = true }
        } label: {
            ZStack {
                if let coin = UIImage(named: "tavern-ui-coin") { Image(uiImage: coin).resizable().scaledToFit() }
                Image(systemName: "gearshape.fill").font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04))
            }
            .frame(width: 30, height: 30)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Game menu")
        .accessibilityIdentifier("board.arena.menu")
    }

    // MARK: Overlays

    @ViewBuilder
    private func arenaOverlays(snapshot: GameSnapshot, human: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let promptWidth = min(max(canvas.screen.width * (canvas.layout.landscape ? 0.34 : 0.86), 260), 360)
        let promptCenter = CGPoint(x: canvas.layout.landscape ? canvas.x(478) : canvas.screen.width / 2,
                                   y: canvas.y(canvas.layout.landscape ? 196 : 446))
        let targetableIds = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        if !startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId) && !isPromptDetailOpen
            && arenaShowsPromptPopup(snapshot: snapshot, targetableIds: targetableIds) {
            CompactPromptPopup(snapshot: snapshot, pendingActionId: pendingActionId, runAction: runAction, runCommand: runCommand,
                               openDetails: { isPromptDetailOpen = true })
                .frame(width: promptWidth)
                .fixedSize(horizontal: false, vertical: true)
                .position(promptCenter)
                .transition(boardOverlayTransition)
        }
        if let dragActionChoice {
            DragActionChoicePopup(choice: dragActionChoice, pendingActionId: pendingActionId,
                                  runAction: { action in self.dragActionChoice = nil; selectedCard = nil; runAction(action) },
                                  cancel: { self.dragActionChoice = nil; selectedCard = nil })
                .frame(width: promptWidth)
                .position(promptCenter)
                .transition(boardOverlayTransition)
        }
        if let inspectingZoneTitle {
            CompactZoneInspectorOverlay(
                title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                legalActions: snapshot.legalActions ?? [], pendingActionId: pendingActionId,
                selectedCard: $selectedCard, inspectedCard: $inspectedCard, runAction: runAction,
                closeAction: { self.inspectingZoneTitle = nil; self.inspectingZoneCards = []; self.inspectingZoneReference = nil },
                targetableIDs: targetableIds, runTargetAction: { submitTarget($0, snapshot: snapshot) },
                availableHeight: canvas.screen.height * 0.8)
                .frame(width: min(canvas.screen.width - 32, 520), height: canvas.screen.height * (canvas.layout.landscape ? 0.82 : 0.62))
                .position(x: canvas.screen.width / 2, y: canvas.screen.height / 2)
                .transition(boardOverlayTransition)
        }
        if let inspectedCard {
            Color.black.opacity(0.01).ignoresSafeArea()
                .onTapGesture { self.inspectedCard = nil }
                .inspectionTouchPassthrough()
            let size = arenaInspectorSize(canvas: canvas)
            CardInspector(card: inspectedCard)
                .inspectionTouchPassthrough()
                .frame(width: size.width, height: size.height)
                .position(x: canvas.layout.landscape ? canvas.x(478) : canvas.screen.width / 2,
                          y: canvas.layout.landscape ? canvas.screen.height * 0.47 : canvas.screen.height * 0.44)
        }
        if snapshot.isWaitingOnAIOrStalled {
            AIWaitFallbackControls(snapshot: snapshot, pendingActionId: pendingActionId, liveUpdateStatus: liveUpdateStatus,
                                   beganAt: aiWaitBeganAt, didRefresh: didAutoRefreshAIWaitKey == aiWaitKey,
                                   didReconnect: didAutoReconnectAIWaitKey == aiWaitKey, didDiagnose: didAutoDiagnoseAIWaitKey == aiWaitKey,
                                   refreshAction: refreshGame, reconnectAction: reconnectGame)
                .frame(width: min(canvas.screen.width - 28, 360))
                .position(x: canvas.screen.width / 2, y: canvas.screen.height / 2)
        }
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: $arenaShowPhaseStops) { PhaseStopsSheet() }
    }

    private func arenaInspectorSize(canvas: ArenaCanvas) -> CGSize {
        if canvas.layout.landscape {
            let height = canvas.screen.height * 0.86
            return CGSize(width: min(canvas.screen.width * 0.42, height * 0.95), height: height)
        }
        return CGSize(width: canvas.screen.width - 40, height: canvas.screen.height * 0.6)
    }

    /// Arrows and effects: drawn layers only, hidden from VoiceOver and touches.
    private func arenaDrawnLayers(anchors: [String: Anchor<CGRect>], snapshot: GameSnapshot, human: PlayerGameState,
                                  opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        GeometryReader { geometry in
            let bounds = anchors.mapValues { geometry[$0] }
            if inspectingZoneTitle == nil && inspectedCard == nil {
                ArenaCombatArrows(snapshot: snapshot, previewArrows: combatPreviewArrows, bounds: bounds, opponentID: opponent.playerId)
            }
            let stack = canvas.rect(canvas.layout.stack)
            boardFXOverlay(bounds: bounds, snapshot: snapshot,
                           opponentRect: canvas.area(canvas.layout.creatureLane(viewer: false, rows: 1)),
                           playerRect: canvas.area(canvas.layout.creatureLane(viewer: true, rows: 1)),
                           stackRect: stack,
                           handRect: CGRect(x: canvas.x(canvas.layout.hand.centerX) - 60, y: canvas.y(canvas.layout.hand.upY) - 40, width: 120, height: 80),
                           viewerLife: bounds[TavernSeatAnchor.bottom].map { CGPoint(x: $0.midX, y: $0.midY) },
                           opponentLife: bounds[TavernSeatAnchor.top].map { CGPoint(x: $0.midX, y: $0.midY) })
        }
        .allowsHitTesting(false)
        .accessibilityRepresentation { EmptyView() }
    }

    // MARK: Decisions

    func arenaHandPosture(snapshot: GameSnapshot) -> ArenaHandPosture {
        let actions = snapshot.legalActions ?? []
        let hand = BoardOpponentFocus.seatHand(in: snapshot)
        let decision = InlinePaymentPromptState.isActive(in: snapshot)
            || !GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty
            || arenaCombatPhase(snapshot) != nil
            || isCardChoiceOpen || isPromptDetailOpen || committedCardChoice != nil
            || (!startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        var dragging = false
        if case .draggingCard = interactionState.mode { dragging = true }
        let phase = TavernPhaseTrack.describe(snapshot.step ?? snapshot.phase).phase
        return ArenaHandPosture.resolve(.init(
            hasPriority: snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId),
            isViewerTurn: snapshot.isViewer(snapshot.activePlayerId),
            isMainPhase: phase == 1 || phase == 3,
            hasPlayableCard: hand.contains { !GameBoardInteractionState.legalPlayActions(for: $0, actions: actions).isEmpty },
            boardDecision: decision, dragging: dragging, tucked: arenaTucked, spectating: snapshot.isSpectating))
    }

    /// The raised hand covers the corner controls, as in the reference, except while the table asks you something.
    private func arenaControlsOnTop(snapshot: GameSnapshot) -> Bool {
        InlinePaymentPromptState.isActive(in: snapshot) || !snapshot.stackTopFirst.isEmpty || arenaCombatPhase(snapshot) != nil
            || !GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty
    }

    /// A tap on the empty table: drops a lifted card, then puts a raised hand down, then clears any selection.
    private func arenaTapTable(snapshot: GameSnapshot) {
        if arenaLiftedCardID != nil {
            arenaLiftedCardID = nil
        } else if arenaHandPosture(snapshot: snapshot) == .raised {
            arenaTucked = true
            GameAudio.shared.play(.cardPickup)
        }
        clearBoardSelection()
    }

    /// The caption over the midline: what the table wants right now, in the reference's few words.
    private func arenaCaptionText(snapshot: GameSnapshot) -> String? {
        if InlinePaymentPromptState.isActive(in: snapshot), let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) {
            let text = snapshot.manaPayment?.remainingText ?? prompt.message
            let clean = PromptDisplayText.clean(text)
            return clean.isEmpty ? "Pay the cost" : clean.hasPrefix("{") ? "Pay \(clean)" : clean
        }
        switch arenaCombatPhase(snapshot) {
        case .attackers:
            return combatSelection.selectedAttackerIds.isEmpty ? "Choose attackers." : "Choose who to attack."
        case .blockers:
            return combatSelection.selectedBlockerId == nil ? "Choose blockers." : "Choose the attacker to block."
        case nil: break
        }
        if !GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty, let prompt = snapshot.promptEnvelopeV2 {
            return PromptDisplayText.clean(prompt.message.isEmpty ? "Choose a target." : prompt.message)
        }
        return nil
    }

    /// Board targets are chosen on the board; the pop-up stays for questions and for players the table doesn't show.
    private func arenaShowsPromptPopup(snapshot: GameSnapshot, targetableIds: Set<String>) -> Bool {
        guard !targetableIds.isEmpty else { return true }
        let shown = Set([snapshot.seatID, snapshot.opponent?.playerId].compactMap { $0 }.flatMap { CombatPlayerIdentity.ids(for: $0, in: snapshot) })
        let players = Set(snapshot.players.flatMap { CombatPlayerIdentity.ids(for: $0.playerId, in: snapshot) })
        return targetableIds.contains { players.contains($0) && !shown.contains($0) }
    }

    /// The id a player-target prompt accepts for this seat, when the prompt offers it.
    func arenaPlayerTargetID(_ playerID: String, snapshot: GameSnapshot) -> String? {
        let targetable = GameBoardInteractionState.boardTargetableIds(for: snapshot)
        guard !targetable.isEmpty else { return nil }
        return CombatPlayerIdentity.ids(for: playerID, in: snapshot).first { targetable.contains($0) }
    }

    func arenaSubmitPlayerTarget(_ id: String, snapshot: GameSnapshot) {
        guard let prompt = snapshot.promptEnvelopeV2 else { return }
        if (prompt.maxChoices ?? 1) > 1 || (prompt.minChoices ?? 1) > 1 {
            isPromptDetailOpen = true
            return
        }
        let promptId = prompt.responseCommand?.promptId ?? prompt.id
        guard let command = UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt, type: "choose_target",
            promptId: promptId, playerId: prompt.playerId, ids: [id]) else {
            GameHaptics.warning()
            onInteractionFeedback("XMage did not expose a mobile-safe target command")
            return
        }
        GameHaptics.success()
        runCommand(command, "Target \(snapshot.playerLabel(id))", "\(promptId)-\(id)")
    }
}
