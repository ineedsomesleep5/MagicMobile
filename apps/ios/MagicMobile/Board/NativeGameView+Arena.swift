import SwiftUI
import UIKit

/// What the Arena board's lanes are choosing from right now, shared by every lane.
struct ArenaLaneChoice {
    let targetableIds: Set<String>
    let chosenIds: Set<String>
    let highlights: Set<String>
    let paying: Bool
}

/// One BattlefieldRow on the Arena board: its cards, where it goes and at what card size.
struct ArenaLanePlan: Identifiable {
    let title: String
    let cards: [ZoneCard]
    let rect: CGRect
    let card: CGSize
    let rows: Int
    let alignment: Alignment
    var id: String { title }
}

/// An Auto Pay in progress: the payment states it has already acted on, so it stops instead of tapping in circles.
struct ArenaAutoPayRun: Equatable {
    var steps = 0
    /// How often each payment state has been acted on: a state seen a third time means Auto Pay is going in circles.
    var signatures: [String: Int] = [:]
    /// The colour to name when XMage asks what a mana of any colour should be (a Treasure, Command Tower).
    var color: String?
    /// Auto Pay's last tap may be asking a colour: only then does it answer a colour question, never one a spell asks later.
    var awaitingColor = false
    /// The colour question ("id:messageId") Auto Pay answered, kept out of the choice browser until its answer lands.
    var answeredColor: String?
    /// Snapshots in a row without the payment: XMage can send one between answers, so only a few end the run.
    var quiet = 0
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
            ArenaLayer { arenaTable(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas) }
        }
        .frame(width: screen.width, height: screen.height)
        .coordinateSpace(name: "portrait-board")
        .overlayPreferenceValue(PortraitCardBoundsKey.self) { anchors in
            ArenaLayer { arenaDrawnLayers(anchors: anchors, snapshot: snapshot, human: human, opponent: opponent, canvas: canvas) }
        }
        .ignoresSafeArea()
        // A swipe up from the bottom edge first shows the home bar instead of leaving the game: the hand lives there.
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
        .environment(\.tavernBoard, true)
        .environment(\.arenaBoard, true)
        .environment(\.arenaTableLean, ArenaTableLean(canvas: canvas))
        // Every new answer from XMage steps the helpers: its revision, a new prompt or the pending answer clearing.
        .modifier(ArenaAutoPayDriver(key: "\(snapshot.bridgeRevision ?? -1)|\(snapshot.promptEnvelopeV2?.id ?? "")|"
                                         + "\(snapshot.promptEnvelopeV2?.messageId ?? -1)|\(pendingActionId ?? "")",
                                     active: arenaAutoPay != nil || arenaAttackQueue != nil || !arenaTriggerPlan.isEmpty) {
            arenaAutoPayStep(snapshot: snapshot)
            arenaAttackStep(snapshot: snapshot)
            arenaTriggerStep(snapshot: snapshot)
        })
        .onChange(of: snapshot.step ?? snapshot.phase) { _, _ in arenaHandOpen = false }
        // The spread hand tucks at a new turn and when the phone turns (landscape has no spread).
        .onChange(of: snapshot.turn) { _, _ in arenaHandSpread = false }
        .onChange(of: canvas.layout.landscape) { _, _ in arenaHandSpread = false }
        // A new decision puts a player's card away.
        .onChange(of: snapshot.promptEnvelopeV2?.id) { _, _ in arenaPlayerCardID = nil; arenaCornerMenu = nil }
        // Reading a card holds smart pass until the inspector closes (BoardPresentationHold.reading).
        .onChange(of: inspectedCard?.id, initial: true) { _, id in BoardPresentationHold.shared.reading = id != nil }
        .onDisappear { BoardPresentationHold.shared.reading = false }
        // Your commander taken by an opponent: say who has it and why it never went home.
        .onChange(of: ArenaCommanderSteal.taken(in: snapshot)) { old, now in
            if let taken = now.first(where: { !old.contains($0) }) {
                arenaShowNotice(ArenaCommanderSteal.notice(taken, snapshot: snapshot), seconds: 7)
            }
        }
        .onAppear {
            interactionState.mode = GameBoardInteractionState.mode(for: snapshot, pendingActionId: pendingActionId, selectedCard: selectedCard)
            GameAudio.shared.preload(GameAudio.boardSounds)
            // Design fixtures only: MAGICMOBILE_ARENA_HAND=open shows the hand opened, =pop one card popped out of it,
            // =spread the hand spread out (portrait).
            if snapshot.id.hasPrefix("design-preview-") {
                switch ProcessInfo.processInfo.environment["MAGICMOBILE_ARENA_HAND"] {
                case "open": arenaHandOpen = true
                case "spread": arenaHandSpread = true
                case "pop": arenaLiftedCardID = BoardOpponentFocus.seatHand(in: snapshot).dropFirst(3).first?.id
                default: break
                }
            }
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

    /// The table's layers. Each large layer is type-erased (`ArenaLayer`, an AnyView in its own ZStack, the z-order kept
    /// outside it): built as one nested view this table overflowed the main thread's stack in Release builds on iPhone
    /// (TestFlight 56, iOS 26.6.2: EXC_BAD_ACCESS in the stack guard while the runtime instantiated the opponent seat's
    /// type). Keep new layers erased the same way.
    @ViewBuilder
    private func arenaTable(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let posture = arenaHandPosture(snapshot: snapshot)
        let controlsOnTop = arenaControlsOnTop(snapshot: snapshot)
        ArenaLayer { arenaLanes(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas) }
        if isOverPlayerDropZone {
            // Over the table a carried card lights the table's edge, the reference's way: soft warm light, no box.
            let area = canvas.area(canvas.layout.dropArea)
            ZStack {
                RoundedRectangle(cornerRadius: 34).strokeBorder(TavernPalette.ember.opacity(0.75), lineWidth: 16).blur(radius: 18)
                RoundedRectangle(cornerRadius: 28).strokeBorder(Color(red: 1, green: 0.86, blue: 0.6).opacity(0.35), lineWidth: 3)
                    .blur(radius: 3).padding(6)
            }
            .blendMode(.plusLighter)
            .frame(width: area.width, height: area.height)
            .position(x: area.midX, y: area.midY)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        ArenaLayer { arenaOpponentSeat(snapshot: snapshot, opponent: opponent, canvas: canvas) }
        // A browser over the table (card choices, the stack, abilities, questions) says what to do and shows the card it's
        // about itself.
        let browserOpen = arenaScreenUp(snapshot)
        let amountPrompt = browserOpen ? nil : arenaAmountPrompt(snapshot)
        ArenaLayer { arenaStack(snapshot: snapshot, canvas: canvas) }
            .opacity(browserOpen ? 0 : 1)
            .zIndex(30)
        ArenaLayer { arenaCaption(snapshot: snapshot, canvas: canvas) }
            .opacity(browserOpen ? 0 : 1)
            .zIndex(35)
        ArenaLayer { arenaRevealedChips(snapshot: snapshot, canvas: canvas) }
            .opacity(browserOpen ? 0 : 1)
            .zIndex(36)
        // Over the front rail and a resting hand, under a raised one (its own parts keep their order inside).
        ArenaLayer { arenaViewerSeat(snapshot: snapshot, human: human, opponent: opponent, canvas: canvas) }
            .zIndex(64)
        if let railTop = canvas.layout.railTop {
            // The front rail drawn again over a resting hand, so the hand tucks behind the table's edge.
            ArenaFrontRail(top: canvas.y(railTop))
                .zIndex(posture == .resting ? 60 : 40)
        }
        let openingHand = OpeningHandChoice(snapshot) != nil
        // The opening hand's own screen shows these cards and its buttons; the fan and corner wait behind it.
        ArenaLayer { arenaHand(snapshot: snapshot, human: human, canvas: canvas, posture: posture) }
            .opacity(openingHand ? 0 : 1)
            .allowsHitTesting(!openingHand)
            // An opened hand, and in landscape a card popped out of it, cover your medallion and mana; controls the table
            // needs stay on top. In portrait a popped card already clears the rail, which keeps the rest tucked behind it.
            .zIndex(posture == .raised || posture == .spread || (arenaLiftedCardID != nil && canvas.layout.railTop == nil) ? 68 : 50)
        if canvas.layout.hand.spreadBottom != nil, !openingHand, !browserOpen, !snapshot.isSpectating,
           !BoardOpponentFocus.seatHand(in: snapshot).isEmpty,
           arenaHandPosture(snapshot: snapshot, spread: true) == .spread || posture == .spread {
            arenaHandSpreadTab(snapshot: snapshot, canvas: canvas, spread: posture == .spread)
                .zIndex(69)
        }
        if let amountPrompt {
            // X and other numbers: the reference's pill takes the corner; the board, caption and stack stay in view.
            let setup = arenaAmountSetup(amountPrompt, snapshot: snapshot)
            let primary = canvas.rect(canvas.layout.primary), secondary = canvas.rect(canvas.layout.secondary)
            let back = arenaPromptAnswers(snapshot, excluding: ["choose_amount"]).first
            let cancel: (title: String, action: () -> Void)? = back.map { item in (item.title, item.action) }
            ArenaAmountPill(label: setup.label, range: setup.range, initial: setup.initial, pending: pendingActionId != nil,
                            submit: { arenaAnswerAmount($0, prompt: amountPrompt, snapshot: snapshot) }, cancel: cancel)
                .id("\(amountPrompt.id):\(amountPrompt.messageId)")
                .fixedSize()
                // The pill where the secondary plaque sits, Cancel under it where the primary does (the reference's corner).
                .position(x: min(canvas.screen.width - 142, max(142, primary.midX)),
                          y: secondary.midY + (cancel == nil ? 0 : 24))
                .zIndex(75)
        } else if !snapshot.isSpectating && !openingHand && !browserOpen {
            ArenaLayer { arenaControls(snapshot: snapshot, canvas: canvas) }
                // The spread hand sits over the table, not the rail, so the corner stays on top of it.
                .zIndex(controlsOnTop || posture != .raised ? 70 : 45)
        }
        ArenaLayer { arenaOverlays(snapshot: snapshot, human: human, canvas: canvas) }
            .zIndex(90)
            // The stack browser closes once the stack empties, so it doesn't reopen with the next spell.
            .onChange(of: snapshot.stackTopFirst.isEmpty) { _, empty in
                if empty { isTavernStackOpen = false; arenaLandedStackIDs = [] }
            }
    }

    /// A full-table screen is up (a browser, the stack, a question): it hides the corner, the caption, the stack card and
    /// the arrows over the table.
    func arenaScreenUp(_ snapshot: GameSnapshot) -> Bool {
        isCardChoiceOpen || isTavernStackOpen || arenaAbilityPrompt(snapshot) != nil || arenaModePrompt(snapshot) != nil
            || arenaChoicePrompt(snapshot) != nil || arenaPlayerPrompt(snapshot) != nil || arenaSplitPrompt(snapshot) != nil
            || arenaPilePrompt(snapshot) != nil
            || arenaQuestion(snapshot, targetableIds: GameBoardInteractionState.boardTargetableIds(for: snapshot)) != nil
            || inspectingZoneTitle != nil
    }

    /// Each side laid out the current reference game's way (Caleb, 2026-10-20): creatures in the front row nearest
    /// the middle; planeswalkers, battles and sagas in their own section (at the table's right edge in landscape, at
    /// the front row's end in portrait); lands from the left of the back row, then artifacts, enchantments, mana rocks
    /// and Treasures. ArenaRowFit shrinks the cards to use the table's whole width (portrait opens a second front row
    /// first) before any section scrolls. BattlefieldRow keeps grouping, attachments, targeting, combat taps and mana
    /// undo exactly as on the Hearth board.
    @ViewBuilder
    private func arenaLanes(snapshot: GameSnapshot, human: PlayerGameState, opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        let choice = ArenaLaneChoice(
            targetableIds: GameBoardInteractionState.boardTargetableIds(for: snapshot),
            chosenIds: GameBoardInteractionState.boardChosenTargetIds(for: snapshot),
            highlights: CombatHighlightSet(selection: combatSelection, actions: snapshot.legalActions ?? [],
                                           combatGroups: snapshot.xmage?.combat ?? []).cardIds,
            paying: snapshot.manaPayment?.active == true)
        arenaSide(opponent, viewer: false, snapshot: snapshot, canvas: canvas, choice: choice)
        arenaSide(human, viewer: true, snapshot: snapshot, canvas: canvas, choice: choice)
    }

    @ViewBuilder
    private func arenaSide(_ player: PlayerGameState, viewer: Bool, snapshot: GameSnapshot, canvas: ArenaCanvas,
                           choice: ArenaLaneChoice) -> some View {
        ForEach(arenaLanePlans(player, viewer: viewer, canvas: canvas, choice: choice)) { plan in
            arenaLane(title: plan.title, cards: plan.cards, rect: plan.rect, card: plan.card, rows: plan.rows,
                      alignment: plan.alignment, viewer: viewer, snapshot: snapshot, choice: choice)
        }
    }

    /// Where each of a side's lanes goes and how big its cards are. Front row: creatures, and planeswalkers, battles
    /// and sagas in their own section; in landscape that section stands alone at the table's right edge a size up (the
    /// current reference game), in portrait it ends the front row. Back row: lands, then artifacts, enchantments, mana
    /// rocks and Treasures, right of centre in landscape, at the lands lane's right end in portrait.
    private func arenaLanePlans(_ player: PlayerGameState, viewer: Bool, canvas: ArenaCanvas,
                                choice: ArenaLaneChoice) -> [ArenaLanePlan] {
        let layout = canvas.layout
        let sizes = layout.tiles(frames: arenaCardFrames)
        let tile = canvas.size(sizes.tile), land = canvas.size(sizes.land)
        let units = { (cards: [ZoneCard]) in
            BattlefieldRow.arenaTileUnits(cards, targetableIds: choice.targetableIds, chosenIds: choice.chosenIds,
                                          combatHighlightIds: choice.highlights)
        }
        func sized(_ width: CGFloat, like base: CGSize) -> CGSize { CGSize(width: width, height: width * base.height / max(base.width, 1)) }
        let owner = viewer ? "Your" : "Opponent"
        let gap = ArenaRowFit.sectionGap
        var plans: [ArenaLanePlan] = []

        // Non-land permanents: creatures in front, planeswalkers, battles and sagas in the side section, the rest to
        // the back row with the mana rocks.
        let nonLand = landscapePermanents(player.zones.battlefield, resources: false)
        let supportCards = arenaSections(nonLand, trailing: { ArenaFrontSection.of($0) == .support }, rank: { _ in 0 }).trailing
        let front = arenaSections(arenaSections(nonLand, trailing: { ArenaFrontSection.of($0) == .support }, rank: { _ in 0 }).leading,
                                  trailing: { ArenaFrontSection.of($0) == .side }, rank: ArenaFrontSection.sideRank)
        let sideUnits = units(front.trailing)
        let laneWidth = canvas.area(layout.creatureLane(viewer: viewer, rows: 1)).width
        var sideRect: CGRect?
        var frontRows = 1
        if let sideY = viewer ? layout.viewerSideY : layout.opponentSideY {
            // One fit for the creatures and the side section's cards a size up, so both shrink together as the row fills.
            let sideScale: CGFloat = 1.15
            let frontFit = ArenaRowFit.fit(leading: units(front.leading), trailing: sideUnits.map { $0 * sideScale }, width: laneWidth,
                                           maxCard: tile.width, maxRows: layout.maxCreatureRows, secondRowBelow: tile.width * 0.85)
            let sideWidth = sideUnits.isEmpty ? 0 : frontFit.trailingWidth
            let reserved = sideWidth > 0 ? sideWidth + gap : 0
            let frontCard = sized(frontFit.cardWidth, like: tile)
            let lane = canvas.area(layout.creatureLane(viewer: viewer, rows: frontFit.rows, tileHeight: frontCard.height / canvas.scale))
            plans.append(ArenaLanePlan(title: "\(owner) board", cards: front.leading,
                                       rect: CGRect(x: lane.minX, y: lane.minY, width: lane.width - reserved, height: lane.height),
                                       card: frontCard, rows: frontFit.rows, alignment: .center))
            if sideWidth > 0 {
                let sideCard = sized(frontFit.cardWidth * sideScale, like: tile)
                let height = sideCard.height + 18
                let rect = CGRect(x: lane.maxX - sideWidth, y: canvas.y(sideY) - height / 2, width: sideWidth, height: height)
                sideRect = rect
                plans.append(ArenaLanePlan(title: "\(owner) permanents", cards: front.trailing, rect: rect, card: sideCard, rows: 1,
                                           alignment: .trailing))
            }
        } else {
            let frontFit = ArenaRowFit.fit(leading: units(front.leading), trailing: sideUnits, width: laneWidth, maxCard: tile.width,
                                           maxRows: layout.maxCreatureRows, secondRowBelow: tile.width * 0.85)
            frontRows = frontFit.rows
            let frontCard = sized(frontFit.cardWidth, like: tile)
            let lane = canvas.area(layout.creatureLane(viewer: viewer, rows: frontFit.rows, tileHeight: frontCard.height / canvas.scale))
            let firstRow = canvas.area(layout.creatureLane(viewer: viewer, rows: 1, tileHeight: frontCard.height / canvas.scale))
            let split = Self.arenaSplit(lane, trailing: frontFit.trailingWidth)
            plans.append(ArenaLanePlan(title: "\(owner) board", cards: front.leading, rect: split.leading, card: frontCard,
                                       rows: frontFit.rows, alignment: .center))
            if !front.trailing.isEmpty {
                // With two rows the side section stacks into both; a lone permanent keeps to the row nearest the middle.
                let sideRows = sideUnits.count > 1 ? frontFit.rows : 1
                let band = sideRows > 1 ? lane : firstRow
                plans.append(ArenaLanePlan(title: "\(owner) permanents", cards: front.trailing,
                                           rect: CGRect(x: split.trailing.minX, y: band.minY, width: split.trailing.width, height: band.height),
                                           card: frontCard, rows: sideRows, alignment: .trailing))
            }
        }

        let backLane = canvas.area(viewer ? layout.viewerLands : layout.opponentLands)
        let resources = arenaSections(landscapePermanents(player.zones.battlefield, resources: true),
                                      trailing: { !$0.card.isLand }, rank: { _ in 0 })
        let back = (leading: resources.leading, trailing: resources.trailing + supportCards)
        if var support = (viewer ? layout.viewerSupport : layout.opponentSupport).map(canvas.area) {
            // The opponent's support section stops short of their side section where the two meet.
            if let sideRect, sideRect.maxY > support.minY, sideRect.minY < support.maxY {
                support.size.width = max(0, min(support.maxX, sideRect.minX - gap) - support.minX)
            }
            if back.trailing.isEmpty || support.width <= 0 {
                let fit = ArenaRowFit.fit(leading: units(back.leading), trailing: units(back.trailing), width: backLane.width, maxCard: land.width)
                let split = Self.arenaSplit(backLane, trailing: back.trailing.isEmpty ? 0 : fit.trailingWidth)
                plans.append(ArenaLanePlan(title: "\(owner) lands", cards: back.leading, rect: back.trailing.isEmpty ? backLane : split.leading,
                                           card: sized(fit.cardWidth, like: land), rows: 1, alignment: .leading))
                if !back.trailing.isEmpty {
                    plans.append(ArenaLanePlan(title: "\(owner) artifacts", cards: back.trailing, rect: split.trailing,
                                               card: sized(fit.cardWidth, like: land), rows: 1, alignment: .trailing))
                }
            } else {
                // Lands from the left and artifacts, enchantments and Treasures from the support section's right end share the
                // whole back row (Caleb, 2026-10-20: a narrow support section hid most of them). The artifacts keep at least
                // the support section's width, taken only from room the lands don't need.
                let band = CGRect(x: backLane.minX, y: backLane.minY, width: max(backLane.maxX, support.maxX) - backLane.minX, height: backLane.height)
                let fit = ArenaRowFit.fit(leading: units(back.leading), trailing: units(back.trailing), width: band.width, maxCard: land.width)
                let landsNeed = ArenaRowFit.sectionWidth(units(back.leading), card: fit.cardWidth)
                let spare = max(0, band.width - landsNeed - gap)
                let split = Self.arenaSplit(band, trailing: max(fit.trailingWidth, min(support.width, spare)))
                plans.append(ArenaLanePlan(title: "\(owner) lands", cards: back.leading, rect: split.leading,
                                           card: sized(fit.cardWidth, like: land), rows: 1, alignment: .leading))
                plans.append(ArenaLanePlan(title: "\(owner) artifacts", cards: back.trailing, rect: split.trailing,
                                           card: sized(fit.cardWidth, like: land), rows: 1, alignment: .trailing))
            }
        } else if !back.trailing.isEmpty, !viewer || frontRows <= 1 {
            // Portrait with room (Caleb, 2026-10-20: eight artifacts showed three): artifacts, enchantments, mana rocks and
            // Treasures get a row of their own in front of the lands, nearer the middle, each row the table's full width.
            // Your side has the room while your creatures fit one row; the opponent's always has.
            let landsFit = ArenaRowFit.fit(leading: units(back.leading), trailing: [], width: backLane.width, maxCard: land.width)
            let supportFit = ArenaRowFit.fit(leading: units(back.trailing), trailing: [], width: backLane.width, maxCard: land.width)
            let step = backLane.height + canvas.length(4)
            plans.append(ArenaLanePlan(title: "\(owner) lands", cards: back.leading, rect: backLane,
                                       card: sized(landsFit.cardWidth, like: land), rows: 1, alignment: .leading))
            plans.append(ArenaLanePlan(title: "\(owner) artifacts", cards: back.trailing, rect: backLane.offsetBy(dx: 0, dy: viewer ? -step : step),
                                       card: sized(supportFit.cardWidth, like: land), rows: 1, alignment: .trailing))
        } else {
            let backFit = ArenaRowFit.fit(leading: units(back.leading), trailing: units(back.trailing), width: backLane.width,
                                          maxCard: land.width)
            let card = sized(backFit.cardWidth, like: land)
            let split = Self.arenaSplit(backLane, trailing: backFit.trailingWidth)
            plans.append(ArenaLanePlan(title: "\(owner) lands", cards: back.leading, rect: split.leading, card: card, rows: 1,
                                       alignment: .leading))
            if !back.trailing.isEmpty {
                plans.append(ArenaLanePlan(title: "\(owner) artifacts", cards: back.trailing, rect: split.trailing, card: card, rows: 1,
                                           alignment: .trailing))
            }
        }
        return plans
    }

    /// A lane's cards in its two sections, by the permanent each card is attached to (or itself): the engine's order,
    /// the trailing section sorted by `rank`.
    private func arenaSections(_ cards: [ZoneCard], trailing: (ZoneCard) -> Bool,
                               rank: (ZoneCard) -> Int) -> (leading: [ZoneCard], trailing: [ZoneCard]) {
        let roots = BattlefieldAttachments.roots(cards)
        let byID = Dictionary(cards.map { ($0.instanceId, $0) }, uniquingKeysWith: { first, _ in first })
        func root(_ card: ZoneCard) -> ZoneCard { byID[roots[card.instanceId] ?? card.instanceId] ?? card }
        let leading = cards.filter { !trailing(root($0)) }
        let back = cards.enumerated().filter { trailing(root($0.element)) }
            .sorted { (rank(root($0.element)), $0.offset) < (rank(root($1.element)), $1.offset) }
            .map(\.element)
        return (leading, back)
    }

    /// The library's top card when it is revealed. XMage sends a library card only then; the design fixtures fill
    /// libraries with "Hidden card" placeholders, which stay face down.
    static func arenaRevealedTop(_ player: PlayerGameState) -> ZoneCard? {
        guard let top = player.zones.library.first, top.card.name != "Hidden card" else { return nil }
        return top
    }

    /// A lane split at its right end: the trailing section's width there, the rest (less a gap) before it.
    static func arenaSplit(_ lane: CGRect, trailing: CGFloat) -> (leading: CGRect, trailing: CGRect) {
        guard trailing > 0 else { return (lane, .zero) }
        let leadingWidth = max(0, lane.width - trailing - ArenaRowFit.sectionGap)
        return (CGRect(x: lane.minX, y: lane.minY, width: leadingWidth, height: lane.height),
                CGRect(x: lane.maxX - trailing, y: lane.minY, width: trailing, height: lane.height))
    }

    // swiftlint:disable:next function_parameter_count
    private func arenaLane(title: String, cards: [ZoneCard], rect: CGRect, card: CGSize, rows: Int, alignment: Alignment,
                           viewer: Bool, snapshot: GameSnapshot, choice: ArenaLaneChoice) -> some View {
        BattlefieldRow(title: title, cards: cards, legalActions: snapshot.legalActions ?? [], targetableIds: choice.targetableIds,
                       chosenIds: choice.chosenIds, combatHighlightIds: choice.highlights, selectedCard: $selectedCard,
                       inspectedCard: $inspectedCard, flipped: !viewer, cardWidth: card.width, cardHeight: card.height,
                       rowWidth: rect.width, adaptsToDensity: true, availableHeight: rect.height, arrangement: .automatic,
                       allowsManaUndo: viewer, manaPaymentActive: choice.paying, alignment: alignment, preferredRows: rows,
                       runAction: runAction,
                       runTargetAction: { submitTarget($0, snapshot: snapshot) },
                       runCombatCardAction: { handleCombatCardTap($0, snapshot: snapshot) })
            .environment(\.arenaPaying, choice.paying)
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
                if let top = Self.arenaRevealedTop(opponent) {
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
                .font(ArenaMenuStyle.font(11, .semibold)).italic()
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
                // The medallion opens the player's card on the table (ArenaPlayerCard), not a menu.
                Button { arenaPlayerCardID = opponent.playerId } label: { medallion.frame(width: diameter + 8, height: diameter + 8) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityHint("Shows their life, counters and zones")
                    .accessibilityIdentifier("board.zones.\(opponent.playerId)")
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
                if let top = Self.arenaRevealedTop(human) {
                    TopOfLibraryCard(card: top, playable: GameplayAffordances.castableZones(player: human, snapshot: snapshot,
                                     pendingActionID: pendingActionId).contains(.library), owner: "your",
                                     height: canvas.size(layout.viewerPile).height) {
                        localViewZone(title: "Top of your library", cards: [top])
                    }
                }
            }
            .position(canvas.point(layout.viewerLibrary))
            // On the portrait rail, over the rail drawn across a resting hand.
            .zIndex(64)
        ArenaGraveyardPile(cards: human.zones.graveyard, size: canvas.size(layout.viewerPile), label: "Your graveyard") {
            inspectBoardZone(.player(playerID: human.playerId, zone: .graveyard))
        }
        .position(canvas.point(layout.viewerGraveyard))
        .zIndex(64)
        if !human.zones.exile.isEmpty {
            ArenaGraveyardPile(cards: human.zones.exile, size: canvas.size(layout.viewerPile), label: "Your exile", exile: true) {
                inspectBoardZone(.player(playerID: human.playerId, zone: .exile))
            }
            .position(canvas.point(layout.viewerExile))
            .zIndex(64)
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
            // The reference keeps the mana pool right above your avatar; it is tapped there to spend it.
            .position(x: canvas.point(layout.viewerMedallion).x + (layout.landscape ? 0 : 6),
                      y: canvas.point(layout.viewerMedallion).y - canvas.length(layout.viewerMedallionDiameter) / 2 - (layout.landscape ? 13 : 15))
            .zIndex(67)
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
                Button { arenaPlayerCardID = human.playerId } label: { medallion.frame(width: diameter + 8, height: diameter + 8) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your life: \(human.life)\(PortraitBottomCommandBar.castableDescription(castable))")
                    .accessibilityHint("Shows your counters and zones")
                    .accessibilityIdentifier("board.lifeOrb")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Poison and commander damage at a glance; the medallion's pop-over lists every status.
            TavernStatusGlance(summary: PlayerStatusSummary(player: human, snapshot: snapshot))
                .offset(x: diameter * 0.3, y: diameter * 0.05)
        }
        .overlay(alignment: .top) {
            if let emoteCenter {
                // Above the floating mana when there is some (it sits right over the medallion).
                let pool = human.manaPool
                let floating = (pool?.W ?? 0) + (pool?.U ?? 0) + (pool?.B ?? 0) + (pool?.R ?? 0) + (pool?.G ?? 0) + (pool?.C ?? 0) > 0
                HStack(spacing: 4) {
                    EmoteBubbleSlot(center: emoteCenter, playerID: human.playerId).fixedSize()
                    TableChatButton(center: emoteCenter)
                }
                .offset(y: -diameter * 0.85 - (floating ? 30 : 0))
            }
        }
    }

    @ViewBuilder
    private func arenaStack(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let objects = snapshot.stackTopFirst
        if let top = objects.first {
            let rect = canvas.rect(canvas.layout.stack)
            let commander = !ArenaStackCard.isAbility(top) && snapshot.players.contains { player in
                player.commanders?.contains { $0.name == top.displaySourceName || $0.name == top.displayName } == true
            }
            let revealing = arenaRevealID == top.id
            ArenaStackCard(object: top, count: snapshot.xmage?.stack.count ?? objects.count, size: rect.size, commander: commander,
                           fallbackSource: arenaSourceCard(top, snapshot: snapshot), lands: !arenaLandedStackIDs.contains(top.id),
                           inspect: { inspectedCard = $0 }, openStack: { isTavernStackOpen = true })
                // An opponent's spell is revealed first, larger and toward the middle, then settles onto the stack card
                // (the reference's ~0.4 s grow, ~0.9 s hold, 0.3 s settle).
                // Low enough that the larger card clears the opponent's piles above the stack card.
                .scaleEffect(revealing ? 1.2 : 1)
                .offset(x: revealing ? -rect.width * 0.8 : 0, y: revealing ? rect.height * 0.14 : 0)
                .animation(.easeInOut(duration: 0.3), value: revealing)
                .anchorPreference(key: PortraitCardBoundsKey.self, value: .bounds) { ["arena.stack": $0] }
                .id(top.id)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .position(x: rect.midX, y: rect.midY)
                .onAppear {
                    arenaBeginReveal(top, snapshot: snapshot)
                    arenaLandedStackIDs.insert(top.id)
                }
                .onChange(of: isTavernStackOpen) { _, open in GameAudio.shared.play(open ? .uiOpen : .uiClose) }
                .zIndex(30)
        }
    }

    /// An opponent's spell (not an ability) holds the reveal for its first 1.3 s, then settles.
    private func arenaBeginReveal(_ top: XmageStackObject, snapshot: GameSnapshot) {
        guard !accessibilityReduceMotion, !ArenaStackCard.isAbility(top), let controller = top.controllerId,
              !snapshot.isViewer(controller) else { return }
        arenaRevealID = top.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            if arenaRevealID == top.id { arenaRevealID = nil }
        }
    }

    @ViewBuilder
    private func arenaCaption(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let y = canvas.y(canvas.layout.captionY)
        let band = arenaCaptionBand(snapshot: snapshot, canvas: canvas)
        VStack(spacing: 6) {
            if let text = arenaNotice ?? arenaCaptionText(snapshot: snapshot) {
                ArenaPromptCaption(text: text)
            }
            if let lastActionRejection {
                ActionRejectionInlineView(notice: lastActionRejection) { recover(from: lastActionRejection) }
                    .frame(maxWidth: min(canvas.screen.width - 40, 420))
            }
        }
        .frame(maxWidth: band.width)
        .position(x: band.midX, y: y)
        .zIndex(35)
    }

    /// The tab at the left of the tucked hand (portrait): ▲ spreads every card out whole in lined-up rows, ▼ tucks
    /// them again (Caleb, 2026-10-21). Spread, it sits just above the cards' top row.
    private func arenaHandSpreadTab(snapshot: GameSnapshot, canvas: ArenaCanvas, spread: Bool) -> some View {
        let extra = snapshot.human.map { snapshot.isViewer($0.playerId) ? ArenaExtraHand.cards(for: $0, actions: snapshot.legalActions ?? []).count : 0 } ?? 0
        let count = BoardOpponentFocus.seatHand(in: snapshot).count + extra
        let top = ArenaHandFanLayout.spread(count: count, hand: canvas.layout.hand)?.top ?? 700
        let center = canvas.point(CGPoint(x: 22, y: spread ? top - 6 : 740))
        return Button {
            withAnimation(accessibilityReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                arenaHandSpread = !spread
                arenaLiftedCardID = nil
            }
            GameAudio.shared.play(.cardPickup)
            GameHaptics.selection()
        } label: {
            Image(systemName: spread ? "chevron.down" : "chevron.up")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.52))
                .frame(width: 34, height: 34)
                .background(Circle().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(center)
        .accessibilityLabel(spread ? "Tuck your hand" : "Spread your hand")
        .accessibilityHint(spread ? "Puts the cards back along the bottom" : "Lays every card in your hand out whole")
        .accessibilityIdentifier("arena.hand.spread")
    }

    /// Revealed and looked-at cards, as small glass pills beside the opponent's piles, clear of the creature rows
    /// (Caleb, 2026-10-21: the chip sat over a creature's power and toughness). A tap opens them in a browser.
    @ViewBuilder
    private func arenaRevealedChips(snapshot: GameSnapshot, canvas: ArenaCanvas) -> some View {
        let revealed = snapshot.xmage?.revealed.flatMap(\.cards) ?? []
        let lookedAt = snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
        if !revealed.isEmpty || !lookedAt.isEmpty {
            // Landscape: one over the other in the gap between the opponent's graveyard and the gear. Portrait: side by
            // side under the opponent's piles.
            let pills = Group {
                if !revealed.isEmpty { arenaZonePill("eye.fill", count: revealed.count, label: "Revealed") { inspectBoardZone(.collection(.revealed)) } }
                if !lookedAt.isEmpty { arenaZonePill("eye", count: lookedAt.count, label: "Looked at") { inspectBoardZone(.collection(.lookedAt)) } }
            }
            if canvas.layout.landscape {
                VStack(spacing: 0) { pills }
                    .fixedSize()
                    .position(x: canvas.x(818), y: canvas.y(12) + (revealed.isEmpty || lookedAt.isEmpty ? 22 : 44) / 2)
                    .zIndex(36)
            } else {
                HStack(spacing: 6) { pills }
                    .fixedSize()
                    .position(canvas.point(CGPoint(x: 122, y: 74)))
                    .zIndex(36)
            }
        }
    }

    private func arenaZonePill(_ symbol: String, count: Int, label: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text("\(count)").font(ArenaMenuStyle.font(12, .heavy)).monospacedDigit()
            }
            .foregroundStyle(ArenaGlass.text)
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(minWidth: 44, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 1 ? "\(label), 1 card" : "\(label), \(count) cards")
        .accessibilityIdentifier("arena.chip.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
    }

    /// Where the caption may run: the middle of the table, kept left of the stack card while one is up.
    private func arenaCaptionBand(snapshot: GameSnapshot, canvas: ArenaCanvas) -> (midX: CGFloat, width: CGFloat) {
        let center = canvas.layout.landscape ? canvas.x(478) : canvas.screen.width / 2
        let width = canvas.screen.width * (canvas.layout.landscape ? 0.6 : 0.9)
        guard !snapshot.stackTopFirst.isEmpty else { return (center, width) }
        let left = center - width / 2
        let right = min(center + width / 2, canvas.rect(canvas.layout.stack).minX - canvas.length(10))
        return ((left + right) / 2, max(0, right - left))
    }

    private func arenaHand(snapshot: GameSnapshot, human: PlayerGameState, canvas: ArenaCanvas, posture: ArenaHandPosture) -> some View {
        ArenaHandFan(cards: BoardOpponentFocus.seatHand(in: snapshot),
                     extraCards: snapshot.isViewer(human.playerId) ? ArenaExtraHand.cards(for: human, actions: snapshot.legalActions ?? []) : [],
                     legalActions: snapshot.legalActions ?? [],
                     pendingCardInstanceId: pendingCardInstanceId, canvas: canvas, posture: posture,
                     inspectedCard: $inspectedCard, interactionState: $interactionState, isOverPlayerDropZone: $isOverPlayerDropZone,
                     liftedCardID: $arenaLiftedCardID,
                     hiddenCount: snapshot.isViewer(human.playerId) ? nil : human.zones.visibleHandCount,
                     raise: { arenaHandOpen = true },
                     lower: { arenaHandOpen = false; arenaHandSpread = false },
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
                        width: stripWidth, iconSize: canvas.length(layout.landscape ? 19 : 18))
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
        ArenaPassAheadPill(openMenu: { arenaCornerMenu = "pass" })
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
    /// The gear's menu, as an Arena menu card on the table.
    private func arenaGameMenuItems(snapshot: GameSnapshot) -> [ArenaMenuItem] {
        var items = [ArenaMenuItem(id: "log", title: "Game Log", symbol: "list.bullet.rectangle") { isLogOpen = true }]
        if !snapshot.stackTopFirst.isEmpty {
            items.append(ArenaMenuItem(id: "stack", title: "Stack (\(snapshot.stackTopFirst.count))", symbol: "square.stack.3d.up") { isTavernStackOpen = true })
        }
        items.append(ArenaMenuItem(id: "stops", title: "Phase Stops", symbol: "pause.circle") { arenaShowPhaseStops = true })
        if let control = nativeTurnControl {
            items.append(ArenaMenuItem(id: "full-control", title: "Full control", subtitle: control.isFullControl ? "On for this turn" : "Stop at every priority this turn",
                                       symbol: "hand.raised.fill", lit: control.isFullControl, action: control.toggleFullControl))
        }
        if snapshot.source == "xmage-ondevice" {
            items.append(ArenaMenuItem(id: "more", title: "More actions", symbol: "ellipsis") { openPromptDetails() })
        }
        items.append(ArenaMenuItem(id: "settings", title: "Game Settings", symbol: "gearshape.fill") { isGameMenuOpen = true })
        return items
    }

    private func arenaGameMenu(snapshot: GameSnapshot) -> some View {
        Button { arenaCornerMenu = "game" } label: {
            // Arena's gear: a light symbol on a dark glass disc, no brass coin.
            Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold))
                .foregroundStyle(ArenaGlass.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
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
        let abilityPrompt = arenaAbilityPrompt(snapshot)
        if let menu = arenaCornerMenu {
            // The gear's menu under the gear; the skip choices above the corner (in portrait above your lands, so the
            // hand stays in view). A tap anywhere else closes it.
            Color.black.opacity(0.25).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { arenaCornerMenu = nil }
                .accessibilityHidden(true)
            let items = menu == "game" ? arenaGameMenuItems(snapshot: snapshot) : nativeTurnControl.map(ArenaPassAheadPill.items) ?? []
            let gear = canvas.point(canvas.layout.menu)
            ArenaMenuCard(items: items, close: { arenaCornerMenu = nil })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: menu == "game" ? .topTrailing : .bottomTrailing)
                .padding(.top, menu == "game" ? gear.y + 26 : 0)
                .padding(.bottom, menu == "game" ? 0 : canvas.screen.height - canvas.y(canvas.layout.landscape ? 326 : 628))
                .padding(.trailing, menu == "game" ? max(12, canvas.screen.width - gear.x - 22) : 14)
                .transition(.scale(scale: 0.95, anchor: menu == "game" ? .topTrailing : .bottomTrailing).combined(with: .opacity))
        }
        // First, so any decision that comes up draws over it (it also closes when one does).
        if let cardOwner = arenaPlayerCardID, let player = snapshot.players.first(where: { $0.playerId == cardOwner }) {
            // A player's card beside their medallion; a tap anywhere else puts it away.
            Color.black.opacity(0.35).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { arenaPlayerCardID = nil }
                .accessibilityHidden(true)
            let viewer = snapshot.isViewer(player.playerId)
            let medallion = canvas.point(viewer ? canvas.layout.viewerMedallion : canvas.layout.opponentMedallion)
            ArenaPlayerCard(player: player, snapshot: snapshot, pendingActionID: pendingActionId,
                            opponents: viewer ? [] : BoardOpponentFocus.opponents(in: snapshot),
                            swap: { id in focusTracker.select(id); arenaPlayerCardID = id },
                            open: { reference in arenaPlayerCardID = nil; inspectBoardZone(reference) },
                            close: { arenaPlayerCardID = nil })
                .frame(maxHeight: canvas.screen.height - 24)
                .position(arenaPlayerCardCenter(medallion: medallion, viewer: viewer, canvas: canvas))
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        if let abilityPrompt {
            // A choice XMage lets you back out of keeps its Cancel inside the browser (the corner is hidden behind it).
            let back = CompactPromptPopup.compactLegalPromptActions(in: snapshot).first { $0.type != "choose_ability" }
            ArenaAbilityBrowser(prompt: abilityPrompt.prompt, abilities: abilityPrompt.prompt.abilities ?? [], ordering: abilityPrompt.ordering,
                                pending: pendingActionId != nil, screen: canvas.screen,
                                canRemember: abilityPrompt.ordering && answerActions.supported.contains("rememberTriggerFirst"),
                                cancel: back.map { action in (action.compactPromptTitle, { runAction(action) }) },
                                choose: { arenaChooseAbility($0, prompt: abilityPrompt.prompt, snapshot: snapshot, remember: false) },
                                order: { resolveOrder, remember in arenaOrderTriggers(resolveOrder, remember: remember, prompt: abilityPrompt.prompt, snapshot: snapshot) },
                                inspect: { inspectedCard = $0 })
                .id("\(abilityPrompt.prompt.id):\(abilityPrompt.prompt.messageId)")
                .transition(.opacity)
        }
        if abilityPrompt == nil, let modes = arenaModePrompt(snapshot) {
            let bounds = CardChoicePlan.selectionBounds(modes.message)
            let firstLine = PromptDisplayText.clean(modes.message.components(separatedBy: "\n").first ?? "")
            ArenaModeBrowser(title: (modes.maxChoices ?? 1) > 1 ? "Choose modes" : "Choose a mode",
                             detail: bounds.map { b in b.1 == Int.max ? "Tap a mode to add it" : "Tap a mode to add it · up to \(b.1), at least \(b.0)" }
                                ?? firstLine,
                             source: arenaModeSource(modes, snapshot: snapshot), modes: modes.modes ?? [], pending: pendingActionId != nil,
                             screen: canvas.screen,
                             answers: CompactPromptPopup.compactLegalPromptActions(in: snapshot).filter { $0.type != "choose_mode" }
                                .map { action in (action.id, action.compactPromptTitle, { runAction(action) }) },
                             choose: { arenaChooseMode($0, prompt: modes, snapshot: snapshot) },
                             inspect: { inspectedCard = $0 })
                .id("\(modes.id):\(modes.messageId)")
                .transition(.opacity)
        }
        if abilityPrompt == nil && arenaModePrompt(snapshot) == nil {
            if let choice = arenaChoicePrompt(snapshot) {
                let lines = PromptDisplayText.clean(choice.message).components(separatedBy: "\n")
                ArenaChoiceBrowser(title: lines.first ?? "Make a choice", detail: lines.dropFirst().first,
                                   options: arenaChoiceOptions(choice, snapshot: snapshot), source: snapshot.stackTopFirst.first,
                                   pending: pendingActionId != nil, screen: canvas.screen,
                                   answers: arenaPromptAnswers(snapshot, excluding: ["resolve_choice"]),
                                   choose: { option, remember in arenaAnswerChoice(option, remember: remember, prompt: choice, snapshot: snapshot) },
                                   inspect: { inspectedCard = $0 })
                    .id("\(choice.id):\(choice.messageId)")
                    .transition(.opacity)
            } else if let players = arenaPlayerPrompt(snapshot) {
                let message = PromptDisplayText.clean(players.prompt.message)
                let first = ["starting player", "first turn", "goes first"].contains { message.lowercased().contains($0) }
                ArenaPlayerChoice(title: first ? "Choose who goes first" : message,
                                  seats: players.seats, pending: pendingActionId != nil, screen: canvas.screen,
                                  answers: arenaPromptAnswers(snapshot, excluding: ["choose_player", "choose_target"]),
                                  choose: { seat in
                                      arenaAnswerPlayer(seat, type: players.type, prompt: players.prompt, snapshot: snapshot)
                                  })
                    .id("\(players.prompt.id):\(players.prompt.messageId)")
                    .transition(.opacity)
            } else if let split = arenaSplitPrompt(snapshot) {
                let setup = arenaSplitSetup(split, snapshot: snapshot)
                ArenaSplitBrowser(title: setup.title, rows: setup.rows, slots: split.multiAmounts ?? [], totalMin: split.totalMin,
                                  totalMax: split.totalMax, source: setup.source, sourceCard: setup.sourceCard,
                                  pending: pendingActionId != nil, screen: canvas.screen,
                                  answers: arenaPromptAnswers(snapshot, excluding: ["choose_multi_amount"]),
                                  submit: { arenaAnswerSplit($0, prompt: split, snapshot: snapshot) }, inspect: { inspectedCard = $0 })
                    .id("\(split.id):\(split.messageId)")
                    .transition(.opacity)
            } else if let piles = arenaPilePrompt(snapshot) {
                ArenaPileBrowser(title: "Choose a pile", detail: PromptDisplayText.clean(piles.message), piles: piles.piles ?? [],
                                 source: snapshot.stackTopFirst.first, pending: pendingActionId != nil, screen: canvas.screen,
                                 choose: { arenaAnswerPile($0, prompt: piles, snapshot: snapshot) }, inspect: { inspectedCard = $0 })
                    .id("\(piles.id):\(piles.messageId)")
                    .transition(.opacity)
            }
        }
        if isTavernStackOpen && !snapshot.stackTopFirst.isEmpty {
            let resolve = GameplayAffordances.resolveStackCommand(snapshot: snapshot, pendingActionID: pendingActionId, supported: answerActions.supported)
            ArenaStackBrowser(snapshot: snapshot, screen: canvas.screen,
                              resolveAll: resolve.map { command in {
                                  isTavernStackOpen = false
                                  runCommand(command, "Resolve the stack", "resolve-stack-\(command.promptId ?? "")")
                              } },
                              stopSkipping: nativeTurnControl.flatMap { control in control.isAutoPassing ? control.stop : nil },
                              inspect: { inspectedCard = $0 },
                              close: { isTavernStackOpen = false })
                .transition(.opacity)
        }
        // The opening hand has its own screen (OpeningHandOverlay): XMage's mulligan question never shows behind it.
        if !startingRollVisible && OpeningHandChoice(snapshot) == nil && abilityPrompt == nil && arenaModePrompt(snapshot) == nil
            && !arenaScreenPrompt(snapshot)
            && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId) && !isPromptDetailOpen
            && arenaShowsPromptPopup(snapshot: snapshot, targetableIds: targetableIds) {
            if let question = arenaQuestion(snapshot, targetableIds: targetableIds) {
                ArenaQuestionStage(title: question.title, object: question.object, card: question.card, screen: canvas.screen,
                                   inspect: { inspectedCard = $0 }) {
                    CompactPromptPopup(snapshot: snapshot, pendingActionId: pendingActionId, runAction: runAction, runCommand: runCommand,
                                       openDetails: { isPromptDetailOpen = true }, stage: true)
                        .frame(maxWidth: min(520, canvas.screen.width - 48))
                }
                .id(question.key)
                .transition(.opacity)
            } else {
                CompactPromptPopup(snapshot: snapshot, pendingActionId: pendingActionId, runAction: runAction, runCommand: runCommand,
                                   openDetails: { isPromptDetailOpen = true })
                    .frame(width: promptWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(promptCenter)
                    .transition(boardOverlayTransition)
            }
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
            ArenaZoneBrowser(
                title: inspectingZoneReference?.title(in: snapshot) ?? inspectingZoneTitle,
                cards: inspectingZoneReference?.cards(in: snapshot) ?? inspectingZoneCards,
                legalActions: snapshot.legalActions ?? [], pendingActionId: pendingActionId, screen: canvas.screen,
                targetableIDs: targetableIds, runTargetAction: { submitTarget($0, snapshot: snapshot) },
                inspectedCard: $inspectedCard, runAction: runAction,
                close: { self.inspectingZoneTitle = nil; self.inspectingZoneCards = []; self.inspectingZoneReference = nil })
                .transition(.opacity)
        }
        if let inspectedCard {
            // The reference dims the table a little behind a card you're reading.
            Color.black.opacity(0.45).ignoresSafeArea()
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
    }

    /// Where a player's card opens: beside the medallion toward the table, kept on the screen.
    private func arenaPlayerCardCenter(medallion: CGPoint, viewer: Bool, canvas: ArenaCanvas) -> CGPoint {
        let size = CGSize(width: 300, height: min(canvas.screen.height - 24, 360))
        var center: CGPoint
        if canvas.layout.landscape {
            center = viewer ? CGPoint(x: medallion.x + 40 + size.width / 2, y: medallion.y - size.height / 2 - 10)
                            : CGPoint(x: medallion.x, y: medallion.y + 40 + size.height / 2)
        } else {
            center = viewer ? CGPoint(x: medallion.x + size.width / 2 - 20, y: medallion.y - 50 - size.height / 2)
                            : CGPoint(x: medallion.x + size.width / 2 - 20, y: medallion.y + 40 + size.height / 2)
        }
        center.x = min(max(center.x, size.width / 2 + 12), canvas.screen.width - size.width / 2 - 12)
        center.y = min(max(center.y, size.height / 2 + 12), canvas.screen.height - size.height / 2 - 12)
        return center
    }

    /// The card and its notes (CardInspector's Arena look): in landscape the card at most of the height with the notes
    /// beside it, in portrait the card over its notes.
    private func arenaInspectorSize(canvas: ArenaCanvas) -> CGSize {
        if canvas.layout.landscape {
            let height = canvas.screen.height * 0.86
            return CGSize(width: min(canvas.screen.width * 0.82, height / BattlefieldLayoutMetrics.magicCardHeightToWidth + 316), height: height)
        }
        return CGSize(width: canvas.screen.width - 32, height: canvas.screen.height * 0.78)
    }

    /// Arrows and effects: drawn layers only, hidden from VoiceOver and touches.
    private func arenaDrawnLayers(anchors: [String: Anchor<CGRect>], snapshot: GameSnapshot, human: PlayerGameState,
                                  opponent: PlayerGameState, canvas: ArenaCanvas) -> some View {
        GeometryReader { geometry in
            let bounds = anchors.mapValues { geometry[$0] }
            // Nothing is drawn over a full-table screen (Caleb, 2026-10-21: combat arrows crossed the browsers).
            if inspectedCard == nil && arenaPlayerCardID == nil && !arenaScreenUp(snapshot) {
                ArenaCombatArrows(snapshot: snapshot, previewArrows: combatPreviewArrows, bounds: bounds, opponentID: opponent.playerId)
                // The top of the stack points at its targets, a spell as well as an ability, with a reticle on each target
                // while it waits; an ability without targets points back at its source, as in the reference.
                if let top = snapshot.stackTopFirst.first, let from = bounds["arena.stack"], arenaRevealID != top.id {
                    let ability = ArenaStackCard.isAbility(top)
                    let targetIds = top.targetIds ?? []
                    let ids = !targetIds.isEmpty ? targetIds : ability ? [top.sourceInstanceId].compactMap { $0 } : []
                    let targets = ids.compactMap { id -> CGRect? in
                        if let card = bounds[id] { return card }
                        if CombatPlayerIdentity.ids(for: human.playerId, in: snapshot).contains(id) { return bounds[TavernSeatAnchor.bottom] }
                        if CombatPlayerIdentity.ids(for: opponent.playerId, in: snapshot).contains(id) { return bounds[TavernSeatAnchor.top] }
                        return nil
                    }
                    // Yours in the playable cyan, the opponent's in red.
                    let theirs = top.controllerId.map { !snapshot.isViewer($0) } ?? false
                    let color = theirs ? Color(red: 1, green: 0.38, blue: 0.27) : Color(red: 0.55, green: 0.85, blue: 1)
                    ArenaStackArc(from: from, to: targets, color: color)
                        .id(top.id)
                    if !targetIds.isEmpty {
                        ForEach(Array(targets.enumerated()), id: \.offset) { _, rect in
                            ArenaTargetReticle(rect: rect, color: color)
                        }
                        .id("reticle-\(top.id)")
                    }
                }
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

    /// `spread` asks what the posture would be with the hand spread (whether the tab may spread it now).
    func arenaHandPosture(snapshot: GameSnapshot, spread: Bool? = nil) -> ArenaHandPosture {
        let decision = InlinePaymentPromptState.isActive(in: snapshot)
            || !GameBoardInteractionState.boardTargetableIds(for: snapshot).isEmpty
            || arenaCombatPhase(snapshot) != nil
            || isCardChoiceOpen || isPromptDetailOpen || committedCardChoice != nil
            || (!startingRollVisible && CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        var dragging = false
        if case .draggingCard = interactionState.mode { dragging = true }
        return ArenaHandPosture.resolve(.init(opened: arenaHandOpen, spread: spread ?? arenaHandSpread,
                                              boardDecision: decision, dragging: dragging, spectating: snapshot.isSpectating))
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
        } else if arenaHandPosture(snapshot: snapshot) == .raised || arenaHandPosture(snapshot: snapshot) == .spread {
            arenaHandOpen = false
            arenaHandSpread = false
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
    /// A question for you that the Arena asks on its own screen (ArenaQuestionStage): a yes or no, a few choices, the
    /// commander's zone. Targets stay on the table, payments in the corner. The card shown is the one the question
    /// names: the top of the stack when it names its source, else a card of the prompt's, else a card it mentions.
    func arenaQuestion(_ snapshot: GameSnapshot, targetableIds: Set<String>) -> (title: String, object: XmageStackObject?, card: ZoneCard?, key: String)? {
        // Only where the corner pop-up would ask it: never a payment, the opening hand, the starting roll or a browser's.
        guard targetableIds.isEmpty, !startingRollVisible, !isPromptDetailOpen, OpeningHandChoice(snapshot) == nil,
              !InlinePaymentPromptState.isActive(in: snapshot), CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId),
              arenaModePrompt(snapshot) == nil, arenaAbilityPrompt(snapshot) == nil, !arenaScreenPrompt(snapshot),
              let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId), !CompactPromptPopup.isManaPaymentPrompt(prompt),
              prompt.cards?.isEmpty != false || prompt.confirmation != nil else { return nil }
        let asks = prompt.confirmation != nil || PromptCommandBuilder.isCommanderReplacement(prompt)
            || (prompt.choices.map { !$0.isEmpty && $0.count <= 3 } ?? false)
            || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
        guard asks, prompt.responseKind != "priority", prompt.responseCommand?.type != "pass_priority" else { return nil }
        let message = prompt.message.lowercased()
        let top = snapshot.stackTopFirst.first
        var object: XmageStackObject?
        var card: ZoneCard?
        if let top, message.contains(top.displaySourceName.lowercased()) || message.contains(top.displayName.lowercased()) {
            object = top
        } else if let first = prompt.cards?.first {
            card = first
        } else {
            card = PortraitInteractionPolicy.authorizedCards(snapshot)
                .filter { !$0.card.name.isEmpty && message.contains($0.card.name.lowercased()) }
                .max { $0.card.name.count < $1.card.name.count }
        }
        if object == nil && card == nil, let top, message.contains("you may") { object = top }
        // An ability whose card XMage didn't send shows its permanent's art from the table.
        if let object, object.displaySourceCard == nil, card == nil { card = arenaSourceCard(object, snapshot: snapshot) }
        return (prompt.message, object, card, "\(prompt.id):\(prompt.messageId)")
    }

    /// The card a stack object comes from: XMage's own, else its permanent on the table, else a card of its name there.
    func arenaSourceCard(_ object: XmageStackObject, snapshot: GameSnapshot) -> ZoneCard? {
        if let card = object.displaySourceCard { return card }
        let battlefield = snapshot.players.flatMap(\.zones.battlefield)
        if let id = object.sourceInstanceId, let card = battlefield.first(where: { $0.instanceId == id || $0.id == id }) { return card }
        let name = object.displaySourceName
        return name.isEmpty ? nil : battlefield.first { $0.card.name == name }
    }

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

/// One layer of the Arena table, type-erased: its views in a ZStack inside an AnyView, so the table is a list of shallow
/// layers rather than one deeply nested view type (see `arenaTable`). Apply a layer's z-order to the ArenaLayer.
struct ArenaLayer: View {
    private let content: AnyView

    init<Content: View>(@ViewBuilder _ content: () -> Content) {
        self.content = AnyView(ZStack { content() })
    }

    var body: some View { content }
}
