import SwiftUI

/// The Arena board's hand (the reference's hand): a fan that rises over the table while you can play and rests at its
/// edge otherwise. In portrait a resting hand tucks behind the front rail. A tap on a resting hand raises it; a tap on a
/// raised card lifts it, and a second tap plays it; drag a card up onto the table to play it; hold to read it. A card you
/// draw flies off the top of your deck, shows itself, then joins the fan.
struct ArenaHandFan: View {
    let cards: [ZoneCard]
    /// Playable cards from your graveyard or exile (ArenaExtraHand): the end of the fan, shimmering, with their zone.
    var extraCards: [ZoneCard] = []
    let legalActions: [LegalAction]
    let pendingCardInstanceId: String?
    let canvas: ArenaCanvas
    let posture: ArenaHandPosture
    @Binding var inspectedCard: ZoneCard?
    @Binding var interactionState: GameBoardInteractionState
    @Binding var isOverPlayerDropZone: Bool
    @Binding var liftedCardID: String?
    /// A spectator's stand-in: their hand stays hidden and only its size shows.
    var hiddenCount: Int? = nil
    let raise: () -> Void
    let onDropFeedback: (String) -> Void
    let onActionChoice: ([LegalAction], String) -> Void
    let runAction: (LegalAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging: (id: String, start: CGPoint, offset: CGSize)?
    @State private var known: Set<String>?
    /// Cards on their way in from the deck: 0 at the deck, 1 on show, 2 home in the fan.
    @State private var arrivals: [String: Int] = [:]

    private var layout: ArenaLayout { canvas.layout }
    private var cardSize: CGSize { canvas.size(layout.hand.card) }

    var body: some View {
        ZStack {
            if let hiddenCount {
                hiddenFan(count: hiddenCount)
            } else {
                ForEach(Array((cards + extraCards).enumerated()), id: \.element.id) { index, card in
                    handCard(card, index: index, extra: index >= cards.count)
                }
                if let dragging, let card = (cards + extraCards).first(where: { $0.id == dragging.id }) {
                    dragPreview(card, start: dragging.start, offset: dragging.offset)
                }
            }
        }
        .frame(width: canvas.screen.width, height: canvas.screen.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.hand.scroll")
        .onChange(of: cards.map(\.id), initial: true) { _, ids in noteArrivals(ids) }
        .onChange(of: (cards + extraCards).map(\.id)) { _, ids in
            if let dragging, !ids.contains(dragging.id) { self.dragging = nil; isOverPlayerDropZone = false }
            if let liftedCardID, !ids.contains(liftedCardID) { self.liftedCardID = nil }
        }
        .onChange(of: posture) { _, now in if now == .resting { liftedCardID = nil } }
    }

    // MARK: Cards

    private func slot(_ index: Int) -> ArenaHandSlot {
        let design = ArenaHandFanLayout.slot(index: index, count: cards.count + extraCards.count, posture: posture, hand: layout.hand)
        return ArenaHandSlot(center: canvas.point(design.center), rotation: design.rotation, scale: design.scale)
    }

    @ViewBuilder
    private func handCard(_ card: ZoneCard, index: Int, extra: Bool) -> some View {
        let playable = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
        let lifted = liftedCardID == card.id
        let home = slot(index)
        let arrival = arrivals[card.id]
        let position = arrival.map { arrivalPoint($0, home: home) } ?? liftedPoint(home, lifted: lifted)
        let scale = arrival.map { arrivalScale($0, home: home) } ?? (lifted ? (posture == .raised ? 1.24 : 1.04) : home.scale)
        CardTile(card: card, selected: false, pending: pendingCardInstanceId == card.instanceId,
                 legal: playable.contains { $0.type == "play_land" }, castOffered: playable.contains { $0.type == "cast_spell" },
                 zoneName: "Hand", width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .top) {
                HandManaCost(cost: card.card.manaCost ?? playable.first?.manaCost)
                    .offset(y: -14).allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay { if extra { ArenaExtraCardShimmer(zone: playable.first?.sourceZone ?? "") } }
            .overlay {
                HandCardPan(changed: { translation, start in dragChanged(card, translation: translation, start: start, home: home) },
                            ended: { translation, start, cancelled in dragEnded(card, translation: translation, start: start, cancelled: cancelled, home: home) },
                            inspect: { inspectedCard = card },
                            tap: { tapped(card) },
                            releaseInspection: { if inspectedCard?.id == card.id { inspectedCard = nil } })
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(lifted || arrival != nil ? 0 : home.rotation), anchor: .bottom)
            .opacity(dragging?.id == card.id ? 0 : 1)
            .position(position)
            .zIndex(lifted ? 900 : arrival == 1 ? 950 : Double(index))
            .animation(reduceMotion ? nil : postureAnimation, value: posture)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: lifted)
            .animation(reduceMotion ? nil : .easeInOut(duration: arrival == 0 ? 0.5 : 0.22), value: arrival)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(extra ? "\(card.card.name), playable from your \(playable.first?.sourceZone ?? "zone")" : card.card.name)
            .accessibilityHint("Tap to raise or lift, tap again to play. Hold to inspect. Drag upward to the table to play.")
            .accessibilityAction { inspectedCard = card }
            .accessibilityAction(named: "Inspect card") { inspectedCard = card }
            .accessibilityAction(named: "Play card") { play(card) }
            .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: "Hand"))
    }

    /// Up: a quick ease-out with a small overshoot; down: a quicker ease-in (the reference's 0.22 s and 0.18 s).
    private var postureAnimation: Animation {
        posture == .raised ? .timingCurve(0.2, 0.9, 0.3, 1.12, duration: 0.22) : .timingCurve(0.5, 0, 0.75, 0.4, duration: 0.18)
    }

    private func liftedPoint(_ home: ArenaHandSlot, lifted: Bool) -> CGPoint {
        guard lifted else { return home.center }
        let rise = canvas.length(posture == .raised ? layout.hand.lift : layout.hand.liftDown)
        return CGPoint(x: home.center.x, y: home.center.y - rise)
    }

    private func hiddenFan(count: Int) -> some View {
        ForEach(0..<min(count, 12), id: \.self) { index in
            let design = ArenaHandFanLayout.slot(index: index, count: min(count, 12), posture: .resting, hand: layout.hand)
            ArenaCardBack()
                .frame(width: cardSize.width, height: cardSize.height)
                .scaleEffect(design.scale)
                .rotationEffect(.degrees(design.rotation), anchor: .bottom)
                .position(canvas.point(design.center))
        }
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 card in hand" : "\(count) cards in hand")
    }

    // MARK: Taps and drags

    private func tapped(_ card: ZoneCard) {
        if posture == .resting {
            raise()
            return
        }
        if liftedCardID == card.id {
            play(card)
        } else {
            liftedCardID = card.id
            GameAudio.shared.play(.cardPickup)
            GameHaptics.selection()
        }
    }

    private func play(_ card: ZoneCard) {
        liftedCardID = nil
        switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: true) {
        case let .submit(action):
            interactionState.mode = .awaitingCastSnapshot(actionId: action.id)
            if action.type == "cast_spell" { GameAudio.shared.play(.cardPlay) }
            runAction(action)
        case let .requiresChoice(actions, message):
            onActionChoice(actions, message)
        case let .rejected(message):
            onDropFeedback(message)
            GameHaptics.warning()
        case .ignored:
            break
        }
    }

    private func dragChanged(_ card: ZoneCard, translation: CGSize, start: CGPoint, home: ArenaHandSlot) {
        if dragging?.id != card.id {
            GameAudio.shared.play(.cardPickup)
            liftedCardID = nil
            inspectedCard = nil
        }
        // The finger's point on the card, measured from the card's centre at its home slot.
        let grab = CGPoint(x: home.center.x - cardSize.width / 2 + start.x, y: home.center.y - cardSize.height / 2 + start.y)
        dragging = (card.id, grab, translation)
        let finger = CGPoint(x: grab.x + translation.width, y: grab.y + translation.height)
        isOverPlayerDropZone = canvas.area(layout.dropArea).contains(finger)
        interactionState.mode = .draggingCard(cardId: card.instanceId,
                                              legalActionIds: GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions).map(\.id))
    }

    private func dragEnded(_ card: ZoneCard, translation: CGSize, start: CGPoint, cancelled: Bool, home: ArenaHandSlot) {
        guard let current = dragging, current.id == card.id else { return }
        let finger = CGPoint(x: current.start.x + translation.width, y: current.start.y + translation.height)
        let dropped = !cancelled && canvas.area(layout.dropArea).contains(finger)
        dragging = nil
        isOverPlayerDropZone = false
        guard dropped else {
            interactionState.mode = .idle
            return
        }
        switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: true) {
        case .ignored:
            interactionState.mode = .idle
        case let .rejected(message):
            onDropFeedback(message)
            interactionState.mode = .idle
        case let .requiresChoice(actions, message):
            onDropFeedback(message)
            onActionChoice(actions, message)
            interactionState.mode = .idle
        case let .submit(action):
            interactionState.mode = .awaitingCastSnapshot(actionId: action.id)
            if action.type == "cast_spell" { GameAudio.shared.play(.cardPlay) }
            runAction(action)
        }
    }

    /// The dragged card follows the finger, half again its size, leaning with the drag; over the table it settles a
    /// little smaller, the way the reference's card shrinks toward the stack.
    private func dragPreview(_ card: ZoneCard, start: CGPoint, offset: CGSize) -> some View {
        let finger = CGPoint(x: start.x + offset.width, y: start.y + offset.height)
        let over = canvas.area(layout.dropArea).contains(finger)
        let actions = GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions)
        return CardTile(card: card, selected: false, legal: actions.contains { $0.type == "play_land" },
                        castOffered: actions.contains { $0.type == "cast_spell" }, zoneName: "Hand",
                        width: cardSize.width, height: cardSize.height)
            .scaleEffect(over ? 1.38 : 1.5)
            .rotationEffect(.degrees(max(-12, min(12, Double(offset.width) * 0.06))))
            .shadow(color: (over && !actions.isEmpty ? TavernPalette.ember : .black).opacity(0.7), radius: over ? 16 : 10, y: 8)
            .position(x: finger.x, y: finger.y - 10)
            .zIndex(2000)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Draws

    /// A card that joins the hand after the opening hand flies in from the deck. Several at once (a new hand, a big draw)
    /// just slide in.
    private func noteArrivals(_ ids: [String]) {
        defer { known = Set(ids) }
        guard let known, !reduceMotion else { return }
        let new = ids.filter { !known.contains($0) }
        guard !new.isEmpty, new.count <= 3 else { return }
        for (offset, id) in new.enumerated() {
            arrivals[id] = 0
            let delay = Double(offset) * 0.25
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay + 0.02))
                arrivals[id] = 1
                try? await Task.sleep(for: .seconds(0.5 + 0.4))
                arrivals[id] = 2
                try? await Task.sleep(for: .seconds(0.24))
                arrivals[id] = nil
            }
        }
    }

    private func arrivalPoint(_ phase: Int, home: ArenaHandSlot) -> CGPoint {
        switch phase {
        case 0: return canvas.point(layout.viewerLibrary)
        case 1: return canvas.point(CGPoint(x: layout.draw.midX, y: layout.draw.midY))
        default: return home.center
        }
    }

    private func arrivalScale(_ phase: Int, home: ArenaHandSlot) -> CGFloat {
        switch phase {
        case 0: return layout.viewerPile.width / layout.hand.card.width
        case 1: return layout.draw.width / layout.hand.card.width
        default: return home.scale
        }
    }
}

/// The shimmer around a card you can play from your graveyard or exile, with that zone's mark in its corner.
struct ArenaExtraCardShimmer: View {
    let zone: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: width * 0.06)
                    .strokeBorder(LinearGradient(colors: [Color(red: 0.75, green: 0.6, blue: 1), Color(red: 0.45, green: 0.85, blue: 1),
                                                          Color(red: 0.75, green: 0.6, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: max(1.5, width * 0.025))
                    .shadow(color: Color(red: 0.6, green: 0.55, blue: 1), radius: width * 0.06)
                Image(systemName: zone.lowercased() == "graveyard" ? "flame.fill" : "sparkles")
                    .font(.system(size: max(9, width * 0.12), weight: .black))
                    .foregroundStyle(.white)
                    .padding(width * 0.05)
                    .background(Circle().fill(Color(red: 0.32, green: 0.22, blue: 0.55)))
                    .overlay(Circle().strokeBorder(TavernPalette.brass, lineWidth: 1))
                    .offset(x: -width * 0.06, y: -width * 0.06)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
