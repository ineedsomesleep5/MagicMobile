import SwiftUI
import UIKit

/// The Arena board's hand, the reference game's way (Caleb, 2026-10-20): it rests tucked along the bottom edge with only
/// the cards' tops showing (in portrait, behind the front rail). A tap or a slide along the hand pops up the card under
/// the finger while the rest stay tucked; a second tap plays it, and carrying it up off the hand and onto the table
/// plays it too. A hold magnifies the card under the finger and follows it along the hand. (Where the layout allows it,
/// a tap opens the hand into a raised fan instead; neither layout does today.) A card you draw flies off the top of your deck, shows itself, then joins the fan.
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
    /// Puts an opened hand back down (after a card is played from it).
    var lower: () -> Void = {}
    let onDropFeedback: (String) -> Void
    let onActionChoice: ([LegalAction], String) -> Void
    let runAction: (LegalAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.holdCardInspection) private var inspection
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
                if !(cards + extraCards).isEmpty {
                    let band = touchBand
                    ArenaHandTouch(tap: { tapped(at: band.origin + $0) },
                                   hold: { held(at: band.origin + $0) },
                                   holdEnded: endHold,
                                   pan: { panned(to: band.origin + $0, band: band) },
                                   panEnded: { panEnded(at: band.origin + $0, cancelled: $1) })
                        .frame(width: band.width, height: band.height)
                        .position(x: band.midX, y: band.midY)
                        .zIndex(1500)
                        .accessibilityHidden(true)
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
        let scale = arrival.map { arrivalScale($0, home: home) } ?? (lifted ? liftedScale : home.scale)
        CardTile(card: card, selected: false, pending: pendingCardInstanceId == card.instanceId,
                 legal: playable.contains { $0.type == "play_land" }, castOffered: playable.contains { $0.type == "cast_spell" },
                 zoneName: "Hand", width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .top) {
                HandManaCost(cost: card.card.manaCost ?? playable.first?.manaCost)
                    .offset(y: -14).allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay { if extra { ArenaExtraCardShimmer(zone: playable.first?.sourceZone ?? "") } }
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
            .accessibilityHint("Tap to open the hand or lift the card, tap again to play. Hold to inspect. Slide along the hand, then up onto the table to play.")
            .accessibilityAction { inspectedCard = card }
            .accessibilityAction(named: "Inspect card") { inspectedCard = card }
            .accessibilityAction(named: "Play card") { play(card) }
            .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: "Hand"))
    }

    /// Up: a quick ease-out with a small overshoot; down: a quicker ease-in (the reference's 0.22 s and 0.18 s).
    private var postureAnimation: Animation {
        posture == .raised ? .timingCurve(0.2, 0.9, 0.3, 1.12, duration: 0.22) : .timingCurve(0.5, 0, 0.75, 0.4, duration: 0.18)
    }

    /// A lifted card from a raised hand grows to read; one popped out of the tucked hand shows whole, a little larger.
    private var liftedScale: CGFloat { posture == .raised ? 1.24 : 1.18 }

    private func liftedPoint(_ home: ArenaHandSlot, lifted: Bool) -> CGPoint {
        guard lifted else { return home.center }
        let rise = canvas.length(posture == .raised ? layout.hand.lift : layout.hand.liftDown)
        // Never below the point where the whole card clears the bottom edge.
        let highest = canvas.screen.height - cardSize.height * liftedScale / 2 - canvas.length(8)
        return CGPoint(x: home.center.x, y: min(home.center.y - rise, highest))
    }

    /// The fan's touch surface: every card's home frame, to the bottom of the screen.
    private var touchBand: CGRect {
        let count = cards.count + extraCards.count
        let frames = (0..<count).map { index -> CGRect in
            let home = slot(index)
            let size = CGSize(width: cardSize.width * home.scale, height: cardSize.height * home.scale)
            return CGRect(x: home.center.x - size.width / 2, y: home.center.y - size.height / 2, width: size.width, height: size.height)
        }
        guard let first = frames.first else { return .zero }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return CGRect(x: union.minX, y: union.minY, width: union.width, height: max(0, canvas.screen.height - union.minY))
    }

    /// The card under a point: of the cards whose home slot spans its x, the top one (each card lies over the one before).
    private func card(at point: CGPoint) -> ZoneCard? {
        let all = cards + extraCards
        guard !all.isEmpty else { return nil }
        let homes = all.indices.map { slot($0) }
        if let liftedCardID, let index = all.firstIndex(where: { $0.id == liftedCardID }),
           abs(point.x - homes[index].center.x) <= cardSize.width * liftedScale / 2,
           point.y >= liftedPoint(homes[index], lifted: true).y - cardSize.height * liftedScale / 2 {
            return all[index]
        }
        if let index = all.indices.last(where: { abs(point.x - homes[$0].center.x) <= cardSize.width * homes[$0].scale / 2 }) {
            return all[index]
        }
        return all.indices.min { abs(point.x - homes[$0].center.x) < abs(point.x - homes[$1].center.x) }.map { all[$0] }
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

    private func tapped(at point: CGPoint) {
        guard let card = card(at: point) else { return }
        if liftedCardID == card.id {
            play(card)
        } else if posture == .resting && layout.hand.opensOnTap {
            raise()
        } else {
            liftedCardID = card.id
            GameAudio.shared.play(.cardPickup)
            GameHaptics.selection()
        }
    }

    /// A hold magnifies the card under the finger; sliding while holding moves the magnifier along the hand.
    private func held(at point: CGPoint) {
        guard let card = card(at: point), inspectedCard?.id != card.id else { return }
        if inspectedCard == nil { inspection?.begin { inspectedCard = nil } }
        inspectedCard = card
        GameHaptics.selection()
    }

    private func endHold() {
        if let inspection { inspection.end() } else { inspectedCard = nil }
    }

    private func play(_ card: ZoneCard) {
        liftedCardID = nil
        switch DragCastDropResolver.resolve(card: card, legalActions: legalActions, droppedInPlayArea: true) {
        case let .submit(action):
            interactionState.mode = .awaitingCastSnapshot(actionId: action.id)
            if action.type == "cast_spell" { GameAudio.shared.play(.cardPlay) }
            runAction(action)
            lower()
        case let .requiresChoice(actions, message):
            onActionChoice(actions, message)
        case let .rejected(message):
            onDropFeedback(message)
            GameHaptics.warning()
        case .ignored:
            break
        }
    }

    /// Along the hand the card under the finger pops up; carried up off the hand, that card is picked up and follows the
    /// finger until it is dropped.
    private func panned(to point: CGPoint, band: CGRect) {
        let all = cards + extraCards
        if var current = dragging {
            current.offset = CGSize(width: point.x - current.start.x, height: point.y - current.start.y)
            dragging = current
            isOverPlayerDropZone = canvas.area(layout.dropArea).contains(point)
            return
        }
        if point.y >= band.minY - canvas.length(12) {
            guard let card = card(at: point), liftedCardID != card.id else { return }
            liftedCardID = card.id
            GameHaptics.selection()
            return
        }
        let popped = liftedCardID.flatMap { id in all.first { $0.id == id } }
        guard let card = popped ?? card(at: CGPoint(x: point.x, y: band.midY)) else { return }
        GameAudio.shared.play(.cardPickup)
        liftedCardID = nil
        inspectedCard = nil
        dragging = (card.id, point, .zero)
        isOverPlayerDropZone = canvas.area(layout.dropArea).contains(point)
        interactionState.mode = .draggingCard(cardId: card.instanceId,
                                              legalActionIds: GameBoardInteractionState.legalPlayActions(for: card, actions: legalActions).map(\.id))
    }

    /// A slide that never left the hand leaves its card popped up; a carried card plays if it lands on the table.
    private func panEnded(at point: CGPoint, cancelled: Bool) {
        guard let current = dragging, let card = (cards + extraCards).first(where: { $0.id == current.id }) else { return }
        let dropped = !cancelled && canvas.area(layout.dropArea).contains(point)
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
            lower()
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

/// One touch surface over the whole fan. A tap; a hold (0.3 s) that reports where the finger is while it stays down; and
/// a pan that starts once the finger moves before the hold, in any direction. Points are in the surface's space.
struct ArenaHandTouch: UIViewRepresentable {
    var tap: (CGPoint) -> Void
    var hold: (CGPoint) -> Void
    var holdEnded: () -> Void
    var pan: (CGPoint) -> Void
    var panEnded: (CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        update(view)
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) { update(view) }

    private func update(_ view: TouchView) {
        view.onTap = tap
        view.onHold = hold
        view.onHoldEnded = holdEnded
        view.onPan = pan
        view.onPanEnded = panEnded
    }

    final class TouchView: UIView {
        var onTap: ((CGPoint) -> Void)?
        var onHold: ((CGPoint) -> Void)?
        var onHoldEnded: (() -> Void)?
        var onPan: ((CGPoint) -> Void)?
        var onPanEnded: ((CGPoint, Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.3
            hold.allowableMovement = 10
            addGestureRecognizer(hold)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            // A finger that moves first slides; one that holds still first magnifies.
            pan.require(toFail: hold)
            addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.require(toFail: hold)
            tap.require(toFail: pan)
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) { onTap?(gesture.location(in: self)) }

        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began, .changed: onHold?(gesture.location(in: self))
            case .ended, .cancelled, .failed: onHoldEnded?()
            default: break
            }
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: self)
            switch gesture.state {
            case .began, .changed: onPan?(point)
            case .ended: onPanEnded?(point, false)
            case .cancelled, .failed: onPanEnded?(point, true)
            default: break
            }
        }
    }
}

private extension CGPoint {
    static func + (origin: CGPoint, point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x, y: origin.y + point.y) }
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
