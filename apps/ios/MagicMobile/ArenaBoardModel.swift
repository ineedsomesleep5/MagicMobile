import CoreGraphics
import Foundation

/// The board's two modes (Caleb, 2026-10-20). Hearth is the Walnut Tavern board with the hourglass, the mana rail and the
/// table's sockets. Arena is the reference game's board on a leaning tavern table: controls in one corner, a hand that
/// rises and rests, the stack's top card on the right, and your picture inside your life medallion. Each mode gets its
/// own themes later; Walnut Tavern is the first for both. Arena is the default board everywhere (Caleb, 2026-10-23);
/// Hearth stays as a classic mode a player picks in Options.
enum BoardMode: String, CaseIterable, Identifiable {
    case arena, hearth

    var id: String { rawValue }
    var title: String { self == .hearth ? "Hearth" : "Arena" }
    var summary: String {
        self == .hearth ? "The tavern table with the hourglass and mana rail."
                        : "Corner controls, a rising hand and the stack on the right."
    }

    static let key = "magicmobile.boardMode"
    static let defaultValue = BoardMode.arena.rawValue
    static func resolved(_ value: String) -> BoardMode { BoardMode(rawValue: value) ?? .arena }
}

/// Tavern frames on battlefield cards, kept per board mode (Caleb, 2026-10-20): on for Hearth, off for Arena, whose
/// cards look like the reference game's unless the player turns frames on.
enum CardFramesPreference {
    static let hearthKey = "magicmobile.cardFrames.hearth"
    static let arenaKey = "magicmobile.cardFrames.arena"
    static let hearthDefault = true
    static let arenaDefault = false
}

/// The Arena board's design canvases: landscape 956 × 440 (an iPhone 17 Pro Max held sideways) and portrait 440 × 956.
/// Every number was tuned in the Duel Board Prototype (Claude artifact) against the reference gameplay video, then moved
/// clear of the Dynamic Island and the home indicator. Other screens scale both axes; sizes scale by the smaller axis.
struct ArenaLayout: Equatable {
    struct Hand: Equatable {
        /// Card size before the resting scale.
        let card: CGSize
        let centerX: CGFloat
        /// Raised: centre line, widest pitch, total span of the centres, dip and tilt per step from the middle.
        let upY: CGFloat
        let upPitch: CGFloat
        let upSpan: CGFloat
        let upDrop: CGFloat
        let tilt: Double
        let maxTilt: Double
        /// Resting: a tight fan at a smaller scale (in portrait it tucks behind the front rail).
        let downY: CGFloat
        let downPitch: CGFloat
        let downSpan: CGFloat
        let downDrop: CGFloat
        let downScale: CGFloat
        /// How far a touched card rises from each posture.
        let lift: CGFloat
        let liftDown: CGFloat
        /// Raised: the outer cards dip at most this far, and no card's corner reaches below `upFloor`, so a full hand
        /// stays whole on the screen (Caleb, 2026-10-20: no cards clipped at the bottom).
        var maxDrop: CGFloat = .infinity
        var upFloor: CGFloat = .infinity
        /// Whether a tap on the tucked hand opens it into the raised fan. Off in both layouts (Caleb, 2026-10-20: the
        /// hand stays tucked; a tap or a slide pops one card up while the rest stay put).
        var opensOnTap = false
        /// Touches on the hand count down to this line (design points) and no lower: below it is the home gesture's edge
        /// (landscape) or the cards' hidden part behind the front rail (portrait).
        var touchBottom: CGFloat? = nil
        /// Portrait: the bottom of the spread hand's last row (design points), just over the front rail; nil where the
        /// hand has no spread (Caleb, 2026-10-21: an arrow at the hand's left lays every card out whole).
        var spreadBottom: CGFloat? = nil
    }

    let canvas: CGSize
    let landscape: Bool
    let hand: Hand
    /// The opponent's hand: card backs fanned from this point.
    let opponentHand: CGPoint
    let opponentHandCard: CGSize
    let opponentHandPitch: CGFloat
    /// Life medallions (the player's picture inside, the life number over it).
    let viewerMedallion: CGPoint
    let viewerMedallionDiameter: CGFloat
    let opponentMedallion: CGPoint
    let opponentMedallionDiameter: CGFloat
    /// Library and graveyard piles.
    let viewerLibrary: CGPoint
    let viewerGraveyard: CGPoint
    let viewerPile: CGSize
    /// Exile piles: shown only while they hold cards.
    let viewerExile: CGPoint
    let opponentExile: CGPoint
    let opponentLibrary: CGPoint
    let opponentGraveyard: CGPoint
    let opponentPile: CGSize
    /// Battlefield lanes. Creature rows sit near the midline; extra rows grow toward their owner.
    let opponentLands: CGRect
    let viewerLands: CGRect
    /// Landscape: the back row's second section, right of centre (artifacts, mana rocks, Treasures), as the current
    /// reference game lays it out; nil where the lands lane holds them at its right end (portrait).
    var opponentSupport: CGRect? = nil
    var viewerSupport: CGRect? = nil
    /// Landscape: the centre line of each side's section for planeswalkers, battles and sagas, standing on its own at the
    /// table's right edge; nil where that section ends the front row (portrait).
    var opponentSideY: CGFloat? = nil
    var viewerSideY: CGFloat? = nil
    let opponentCreatureY: CGFloat
    let viewerCreatureY: CGFloat
    let creatureLaneX: ClosedRange<CGFloat>
    let rowBack: CGFloat
    let tile: CGSize
    let land: CGSize
    /// The top of the stack, a big card on the right, and where a drawn card shows before joining the hand.
    let stack: CGRect
    let draw: CGRect
    /// The controls: the phase strip over the secondary and primary buttons, the pass-ahead pill, Undo and the menu.
    let primary: CGRect
    let secondary: CGRect
    let phaseStripX: ClosedRange<CGFloat>
    let phaseStripY: CGFloat
    let phaseStripRaisedY: CGFloat
    let passAhead: CGRect
    let undo: CGRect
    let menu: CGPoint
    /// Floating mana (tap to spend), the prompt caption over the midline, the turn banner and the play area for drops.
    let floatingMana: CGPoint
    let captionY: CGFloat
    let bannerY: CGFloat
    let dropArea: CGRect
    /// Portrait only: the walnut rail along the bottom; a resting hand tucks behind its top edge.
    let railTop: CGFloat?
    /// The corner the drop area leaves out (the controls), as the reference does.
    var dropCorner: CGRect? = nil
    /// How far a card has to be carried before letting go plays it: up a little, or a long way in any direction (in
    /// landscape a popped card already sits over your land row). A wiggle or a short slide along the hand puts it back.
    static let dropLift: CGFloat = 24
    static let dropCarry: CGFloat = 80

    /// The landscape table (scripts/brand/arena_layout.json "landscape").
    static let landscapeLayout = ArenaLayout(
        canvas: CGSize(width: 956, height: 440), landscape: true,
        // Positions follow the current reference game (Caleb's desktop screenshot, 2026-10-20): the opponent's piles top
        // right, their hand fanned behind their medallion. Your medallion sits in the bottom-left corner with your
        // graveyard, library and exile beside it, so the tucked hand can sit higher, its tops just under your lands and
        // clear of the home gesture's edge (Caleb, 2026-10-20). The fan runs between the piles and the controls corner.
        hand: Hand(card: CGSize(width: 93, height: 131), centerX: 490, upY: 368, upPitch: 92, upSpan: 520, upDrop: 2.6,
                   tilt: 3.5, maxTilt: 11, downY: 432, downPitch: 50, downSpan: 317, downDrop: 1.2, downScale: 1,
                   lift: 48, liftDown: 92, maxDrop: 14, upFloor: 437, touchBottom: 416),
        opponentHand: CGPoint(x: 478, y: 4), opponentHandCard: CGSize(width: 36, height: 50), opponentHandPitch: 30,
        // Your medallion and piles sit a little left with room between the stacks for their count badges (Caleb,
        // 2026-10-21: the badges ran over the next pile).
        viewerMedallion: CGPoint(x: 84, y: 402), viewerMedallionDiameter: 56,
        opponentMedallion: CGPoint(x: 478, y: 25), opponentMedallionDiameter: 50,
        viewerLibrary: CGPoint(x: 201, y: 404), viewerGraveyard: CGPoint(x: 147, y: 404), viewerPile: CGSize(width: 42, height: 59),
        viewerExile: CGPoint(x: 255, y: 404), opponentExile: CGPoint(x: 652, y: 30),
        opponentLibrary: CGPoint(x: 704, y: 30), opponentGraveyard: CGPoint(x: 756, y: 30), opponentPile: CGSize(width: 36, height: 50),
        opponentLands: CGRect(x: 80, y: 54, width: 360, height: 66),
        viewerLands: CGRect(x: 80, y: 290, width: 360, height: 70),
        opponentSupport: CGRect(x: 540, y: 54, width: 332, height: 66),
        viewerSupport: CGRect(x: 540, y: 290, width: 160, height: 70),
        opponentSideY: 116, viewerSideY: 248,
        // The front rows run the table's full width, inside the mat's leaning edges (Caleb, 2026-10-20).
        opponentCreatureY: 146, viewerCreatureY: 248, creatureLaneX: 84...872, rowBack: 76,
        tile: CGSize(width: 66, height: 71), land: CGSize(width: 58, height: 62.5),
        // Under the opponent's piles, its bottom above the phase strip and the storm and day pills when two plaques raise
        // them (Caleb, 2026-10-21: the stack card ran under both).
        stack: CGRect(x: 716, y: 60, width: 158, height: 222),
        draw: CGRect(x: 686, y: 187, width: 106, height: 148),
        primary: CGRect(x: 708, y: 388, width: 176, height: 36),
        secondary: CGRect(x: 708, y: 335, width: 176, height: 37),
        phaseStripX: 708...884, phaseStripY: 368, phaseStripRaisedY: 314,
        // The skip pill in the corner right of the main button, as in the reference.
        passAhead: CGRect(x: 890, y: 392, width: 40, height: 28),
        undo: CGRect(x: 650, y: 343, width: 52, height: 26),
        // Low enough that the gear's 44 pt target stays on screen on a 402 pt tall phone held sideways.
        menu: CGPoint(x: 876, y: 26),
        floatingMana: CGPoint(x: 80, y: 405),
        captionY: 197, bannerY: 210,
        // The whole table above the tucked hand, your land row included, as in the reference (Caleb, 2026-10-21: the
        // old box left out your lands and the right side), minus the controls corner.
        dropArea: CGRect(x: 0, y: 0, width: 956, height: 352),
        railTop: nil,
        dropCorner: CGRect(x: 640, y: 300, width: 316, height: 140))

    /// The portrait table (scripts/brand/arena_layout.json "portrait"): the board split at the compass, the opponent
    /// in the top half, you in the bottom half, and every control on the walnut rail under the mat.
    static let portraitLayout = ArenaLayout(
        canvas: CGSize(width: 440, height: 956), landscape: false,
        // The tucked hand at full size: card tops just below your lands, the rest behind the front rail (Caleb,
        // 2026-10-20), clear of the exile pile on the left.
        hand: Hand(card: CGSize(width: 104, height: 146), centerX: 220, upY: 784, upPitch: 58, upSpan: 336, upDrop: 2.2,
                   tilt: 3, maxTilt: 10, downY: 779, downPitch: 46, downSpan: 230, downDrop: 1, downScale: 1,
                   lift: 52, liftDown: 60, touchBottom: 825, spreadBottom: 808),
        opponentHand: CGPoint(x: 340, y: 20), opponentHandCard: CGSize(width: 30, height: 42), opponentHandPitch: 14,
        // Your medallion and piles sit low on the rail, level with the main button (Caleb, 2026-10-20).
        viewerMedallion: CGPoint(x: 50, y: 890), viewerMedallionDiameter: 74,
        opponentMedallion: CGPoint(x: 42, y: 36), opponentMedallionDiameter: 54,
        viewerLibrary: CGPoint(x: 118, y: 891), viewerGraveyard: CGPoint(x: 168, y: 891), viewerPile: CGSize(width: 38, height: 53),
        viewerExile: CGPoint(x: 30, y: 795), opponentExile: CGPoint(x: 168, y: 33),
        opponentLibrary: CGPoint(x: 98, y: 33), opponentGraveyard: CGPoint(x: 133, y: 33), opponentPile: CGSize(width: 30, height: 42),
        opponentLands: CGRect(x: 14, y: 95, width: 412, height: 62),
        viewerLands: CGRect(x: 14, y: 637, width: 412, height: 62),
        opponentCreatureY: 384, viewerCreatureY: 508, creatureLaneX: 12...428, rowBack: 78,
        tile: CGSize(width: 70, height: 75.5), land: CGSize(width: 54, height: 58),
        stack: CGRect(x: 312, y: 363, width: 116, height: 166),
        draw: CGRect(x: 280, y: 530, width: 100, height: 140),
        primary: CGRect(x: 272, y: 882, width: 156, height: 40),
        secondary: CGRect(x: 272, y: 840, width: 156, height: 36),
        phaseStripX: 272...428, phaseStripY: 860, phaseStripRaisedY: 822,
        passAhead: CGRect(x: 197, y: 887, width: 64, height: 30),
        undo: CGRect(x: 197, y: 843, width: 64, height: 30),
        menu: CGPoint(x: 414, y: 28),
        floatingMana: CGPoint(x: 112, y: 752),
        captionY: 446, bannerY: 446,
        dropArea: CGRect(x: 0, y: 0, width: 440, height: 700),
        railTop: 815)

    /// Whether a card carried from `start` and let go at `point` (design points) plays: over the table, out of the
    /// controls corner, and carried up at least `dropLift` or `dropCarry` in any direction.
    func drops(at point: CGPoint, from start: CGPoint) -> Bool {
        dropArea.contains(point) && !(dropCorner?.contains(point) ?? false)
            && (start.y - point.y >= Self.dropLift || hypot(point.x - start.x, point.y - start.y) >= Self.dropCarry)
    }

    static func current(for size: CGSize) -> ArenaLayout {
        size.width > size.height ? .landscapeLayout : .portraitLayout
    }

    /// Front rows a side may use: landscape has no room between the lanes for a second; portrait grows one toward its owner.
    var maxCreatureRows: Int { landscape ? 1 : 2 }

    /// Tile and land sizes: the tavern frames are nearly square; the reference's cropped cards are wider than tall.
    func tiles(frames: Bool) -> (tile: CGSize, land: CGSize) {
        guard !frames else { return (tile, land) }
        return landscape ? (CGSize(width: 84, height: 70), CGSize(width: 68, height: 57))
                         : (CGSize(width: 80, height: 67), CGSize(width: 62, height: 52))
    }

    /// A creature lane for `rows` rows: the first row on its centre line, a second row toward its owner.
    func creatureLane(viewer: Bool, rows: Int, tileHeight: CGFloat? = nil) -> CGRect {
        let centerY = viewer ? viewerCreatureY : opponentCreatureY
        // The row pads its tiles 8 pt above and below, so the lane leaves that room.
        let rowHeight = (tileHeight ?? tile.height) + 18
        let height = rowHeight + CGFloat(max(rows - 1, 0)) * rowBack
        let top = viewer ? centerY - rowHeight / 2 : centerY + rowHeight / 2 - height
        return CGRect(x: creatureLaneX.lowerBound, y: top, width: creatureLaneX.upperBound - creatureLaneX.lowerBound, height: height)
    }
}

/// Maps the Arena design canvas onto a real screen. The table plate fills the screen, so points scale each axis on
/// its own; card, button and medallion sizes scale by the smaller axis so nothing stretches.
struct ArenaCanvas: Equatable {
    let layout: ArenaLayout
    let screen: CGSize

    init(screen: CGSize) {
        self.screen = screen
        layout = ArenaLayout.current(for: screen)
    }

    var scaleX: CGFloat { screen.width / layout.canvas.width }
    var scaleY: CGFloat { screen.height / layout.canvas.height }
    var scale: CGFloat { min(scaleX, scaleY) }

    func point(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scaleX, y: point.y * scaleY) }
    /// A screen point back in design points.
    func design(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x / max(scaleX, 0.001), y: point.y / max(scaleY, 0.001)) }
    /// Whether a card carried from `start` and let go at `point` (screen points) plays (ArenaLayout.drops).
    func drops(at point: CGPoint, from start: CGPoint) -> Bool { layout.drops(at: design(point), from: design(start)) }
    func x(_ value: CGFloat) -> CGFloat { value * scaleX }
    func y(_ value: CGFloat) -> CGFloat { value * scaleY }
    func length(_ value: CGFloat) -> CGFloat { value * scale }
    func size(_ size: CGSize) -> CGSize { CGSize(width: size.width * scale, height: size.height * scale) }
    /// A design rectangle: its centre maps by axis, its size by the smaller scale.
    func rect(_ rect: CGRect) -> CGRect {
        let center = point(CGPoint(x: rect.midX, y: rect.midY))
        let size = size(rect.size)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
    /// A design rectangle stretched with the screen on both axes (lanes and the play area).
    func area(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY, width: rect.width * scaleX, height: rect.height * scaleY)
    }
}

/// Where a non-land permanent sits, the current reference game's way: creatures across the front row; planeswalkers,
/// battles and sagas in a section of their own at the table's right edge (planeswalkers and battles outermost); every
/// other permanent (artifacts, enchantments, an unattached Equipment) in the back row right of the lands, with the mana
/// rocks and Treasures. An Aura or Equipment goes wherever the permanent it is attached to goes.
enum ArenaFrontSection: Equatable {
    case creatures, side, support

    static func of(_ card: ZoneCard) -> ArenaFrontSection {
        if card.isCreature { return .creatures }
        let type = card.card.typeLine
        if card.card.isPlaneswalker || type.localizedCaseInsensitiveContains("battle") || type.localizedCaseInsensitiveContains("saga") {
            return .side
        }
        return .support
    }

    /// Order inside the side section: sagas first, planeswalkers and battles at the far right.
    static func sideRank(_ card: ZoneCard) -> Int {
        card.card.isPlaneswalker || card.card.typeLine.localizedCaseInsensitiveContains("battle") ? 1 : 0
    }
}

/// Sizes one row of a side's board, a leading section and a trailing one, at a single card size, the reference game's
/// way: cards shrink as the row fills (a second row opens first where the layout has one), and only below the smallest
/// size does a section scroll. Widths include BattlefieldRow's 8-pt padding at each end and 4-pt spacing.
struct ArenaRowFit: Equatable {
    let cardWidth: CGFloat
    let rows: Int
    /// The trailing section's width (0 when it is empty); the leading section takes the rest of the row.
    let trailingWidth: CGFloat
    let overflows: Bool

    static let padding: CGFloat = 8, spacing: CGFloat = 4, sectionGap: CGFloat = 10
    /// The smallest a card shrinks to before its section scrolls, as a share of its full size.
    static let minimumScale: CGFloat = 0.7

    /// The width a section's piles need at `card` wide; `units` is each pile's width in cards (an attached Aura or
    /// Equipment peeking out from behind its creature, or a pile of lands, takes a little more than one).
    static func sectionWidth(_ units: [CGFloat], card: CGFloat) -> CGFloat {
        units.isEmpty ? 0 : 2 * padding + units.reduce(0, +) * card + CGFloat(units.count - 1) * spacing
    }

    /// A section's piles in `count` rows, BattlefieldRow's split: the first row takes the extra pile.
    static func rows(_ units: [CGFloat], count: Int) -> [[CGFloat]] {
        guard count > 1, units.count > 1 else { return [units] }
        let first = (units.count + 1) / 2
        return [Array(units.prefix(first)), Array(units.dropFirst(first))]
    }

    /// The trailing section's width at `card` wide in `rows` rows.
    static func trailingWidth(_ units: [CGFloat], card: CGFloat, rows: Int) -> CGFloat {
        Self.rows(units, count: rows).map { sectionWidth($0, card: card) }.max() ?? 0
    }

    /// Both sections fill their first row, then their second, side by side; each is as wide as its widest row. A one-row
    /// fit narrower than `secondRowBelow` opens the second row instead.
    static func fit(leading: [CGFloat], trailing: [CGFloat], width: CGFloat, maxCard: CGFloat,
                    maxRows: Int = 1, secondRowBelow: CGFloat = 0) -> ArenaRowFit {
        let minCard = maxCard * minimumScale
        // sectionWidth is linear in the card width, so the largest card that fits is the tightest pairing of a row
        // from each section.
        func largestCard(_ count: Int) -> CGFloat {
            var card = maxCard
            for row in rows(leading, count: count) {
                for side in rows(trailing, count: count) {
                    let units = row.reduce(0, +) + side.reduce(0, +)
                    guard units > 0 else { continue }
                    let fixed = sectionWidth(row, card: 0) + sectionWidth(side, card: 0)
                        + (row.isEmpty || side.isEmpty ? 0 : sectionGap)
                    card = min(card, (width - fixed) / units)
                }
            }
            return card
        }
        let maxRows = max(1, min(maxRows, max(leading.count, trailing.count)))
        for count in 1...maxRows {
            let card = largestCard(count)
            if card >= (count < maxRows ? max(secondRowBelow, minCard) : minCard) {
                return ArenaRowFit(cardWidth: card, rows: count,
                                   trailingWidth: trailingWidth(trailing, card: card, rows: count), overflows: false)
            }
        }
        // Full at the smallest size: the trailing section keeps at most 40% of the row, and each section scrolls.
        let widest = trailing.isEmpty ? 0 : min(trailingWidth(trailing, card: minCard, rows: maxRows), width * 0.4)
        return ArenaRowFit(cardWidth: minCard, rows: maxRows, trailingWidth: widest, overflows: true)
    }
}

/// Whether the hand is raised over the table or resting at its edge (the reference's hand has these two postures, plus
/// a lifted card and a dragged one, which the fan draws itself).
enum ArenaHandPosture: Equatable {
    case raised, resting
    /// Every card laid out whole in lined-up rows over the table (portrait, the tab at the hand's left).
    case spread

    /// The reference game's hand (Caleb, 2026-10-20): it rests tucked along the bottom edge with only the cards' tops
    /// showing, and opens into a fan when you touch it; a tap on the table puts it back.
    struct Situation: Equatable {
        /// The player tapped the hand open.
        var opened = false
        /// The player spread the hand with its tab.
        var spread = false
        /// Paying a cost, choosing a target, declaring attackers or blockers, or answering a choice: the hand gets out
        /// of the way so the board can be read and tapped.
        var boardDecision = false
        var dragging = false
        var spectating = false
    }

    static func resolve(_ situation: Situation) -> ArenaHandPosture {
        if situation.spectating || situation.dragging || situation.boardDecision { return .resting }
        if situation.spread { return .spread }
        return situation.opened ? .raised : .resting
    }
}

/// One fan slot: where a hand card sits for a posture.
struct ArenaHandSlot: Equatable {
    let center: CGPoint
    let rotation: Double
    let scale: CGFloat
}

enum ArenaHandFanLayout {
    /// The spread hand (Caleb, 2026-10-21): one flat row of whole cards, lined up, just over the rail; a hand wider than
    /// the table swipes sideways (`scroll`, design points from the first card).
    struct Spread: Equatable {
        let count: Int
        let scale: CGFloat
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let gap: CGFloat
        /// Room above the row for the mana costs.
        let costRoom: CGFloat
        let bottom: CGFloat
        let centerX: CGFloat

        var contentWidth: CGFloat { CGFloat(count) * cardWidth + CGFloat(max(count - 1, 0)) * gap }
        /// How far the row swipes: 0 when it fits.
        var maxScroll: CGFloat { max(0, contentWidth - ArenaHandFanLayout.spreadWidth) }
        /// The top of the row, its mana costs included.
        var top: CGFloat { bottom - cardHeight - costRoom }
        var centerY: CGFloat { bottom - cardHeight / 2 }

        func centerX(of index: Int, scroll: CGFloat) -> CGFloat {
            let start = maxScroll > 0 ? centerX - ArenaHandFanLayout.spreadWidth / 2 - min(max(scroll, 0), maxScroll)
                                      : centerX - contentWidth / 2
            return start + cardWidth / 2 + CGFloat(index) * (cardWidth + gap)
        }
    }

    static let spreadWidth: CGFloat = 416

    static func spread(count: Int, hand: ArenaLayout.Hand) -> Spread? {
        guard let bottom = hand.spreadBottom, count > 0 else { return nil }
        let scale: CGFloat = 0.96
        return Spread(count: count, scale: scale, cardWidth: hand.card.width * scale, cardHeight: hand.card.height * scale,
                      gap: 8, costRoom: 20, bottom: bottom, centerX: hand.centerX)
    }

    /// Card `index` of `count` in the given posture, in design points.
    static func slot(index: Int, count: Int, posture: ArenaHandPosture, hand: ArenaLayout.Hand, scroll: CGFloat = 0) -> ArenaHandSlot {
        if posture == .spread, let row = spread(count: count, hand: hand) {
            return ArenaHandSlot(center: CGPoint(x: row.centerX(of: index, scroll: scroll), y: row.centerY), rotation: 0, scale: row.scale)
        }
        let raised = posture == .raised
        let pitch = count > 1 ? (raised ? min(hand.upPitch, hand.upSpan / CGFloat(count - 1))
                                        : min(hand.downPitch, hand.downSpan / CGFloat(count - 1))) : 0
        let offset = CGFloat(index) - CGFloat(count - 1) / 2
        let x = hand.centerX + offset * pitch
        if raised {
            let tilt = max(-hand.maxTilt, min(hand.maxTilt, Double(offset) * hand.tilt))
            // The arc flattens as the hand grows, and the whole fan rises until its outermost corner clears the floor.
            let edge = CGFloat(count - 1) / 2
            let drop = edge > 0 ? min(hand.upDrop, hand.maxDrop / (edge * edge)) : 0
            let edgeTilt = min(hand.maxTilt, Double(edge) * hand.tilt) * .pi / 180
            let reach = drop * edge * edge + hand.card.height / 2 * CGFloat(cos(edgeTilt)) + hand.card.width / 2 * CGFloat(sin(edgeTilt))
            let rise = max(0, hand.upY + reach - hand.upFloor)
            return ArenaHandSlot(center: CGPoint(x: x, y: hand.upY - rise + drop * offset * offset), rotation: tilt, scale: 1)
        }
        return ArenaHandSlot(center: CGPoint(x: x, y: hand.downY + offset * offset * hand.downDrop),
                             rotation: Double(offset) * 1.8, scale: hand.downScale)
    }
}

/// Auto Pay for the Arena board: taps your mana sources one at a time until the cost is paid, the way the reference
/// game's Auto Pay button does. XMage leaves land payment to the client (it only auto-pays the one obvious land), so each
/// step sends the same `make_mana` a tap on the land sends, or spends floating mana with `play_mana`.
enum ArenaAutoPay {
    enum Step: Equatable {
        /// `color`: the colour to name when the source makes a mana of any colour.
        case tap(actionID: String, color: String? = nil)
        case spend(symbol: String)
        case done
        case blocked(String)
    }

    /// What a cost still needs, read from XMage's "Pay {2}{R}" text.
    struct Need: Equatable {
        var generic = 0
        /// Coloured (and {C}) pips: exactly that symbol.
        var symbols: [String: Int] = [:]
        /// Hybrid pips: any one of the listed colours.
        var hybrids: [[String]] = []

        var isEmpty: Bool { generic == 0 && symbols.values.allSatisfy { $0 <= 0 } && hybrids.isEmpty }
    }

    static let colors = ["W", "U", "B", "R", "G"]

    static func need(from text: String) -> Need {
        var need = Need()
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9WUBRGCSXP/]+)\\}") else { return need }
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let token = source.substring(with: match.range(at: 1)).uppercased()
            if let amount = Int(token) {
                need.generic += amount
            } else if token == "S" {
                need.generic += 1
            } else if token == "X" {
                continue
            } else if token.contains("/") {
                let parts = token.split(separator: "/").map(String.init)
                // Phyrexian ({R/P}) pays with its colour here; life payment stays a manual choice.
                if parts.contains("P"), let color = parts.first(where: { colors.contains($0) }) {
                    need.symbols[color, default: 0] += 1
                } else if let two = parts.first.flatMap(Int.init) {
                    // {2/W}: two generic or one white; pay the white when a source has it, else two generic.
                    need.hybrids.append(parts.filter { colors.contains($0) } + ["generic\(two)"])
                } else {
                    need.hybrids.append(parts.filter { colors.contains($0) || $0 == "C" })
                }
            } else if colors.contains(token) || token == "C" {
                need.symbols[token, default: 0] += 1
            }
        }
        return need
    }

    /// What one tap of a mana action produces: one symbol list per alternative ("Add {W} or {U}" has two), or any
    /// colour. Nil when the ability costs more than a tap and sacrificing the source itself (life, other mana, another
    /// permanent): those stay manual.
    struct Production: Equatable {
        var options: [[String]]
        var anyColor = false
        /// The source goes away to make it (a Treasure, a Gold token): spent only when nothing else can pay.
        var sacrifices = false

        func makes(_ symbol: String) -> Bool { anyColor && colors.contains(symbol) || options.contains { $0.contains(symbol) } }
        var amount: Int { anyColor ? 1 : options.map(\.count).max() ?? 0 }
        var colorCount: Int { anyColor ? 5 : Set(options.flatMap { $0 }.filter { colors.contains($0) }).count }
        var colorlessOnly: Bool { !anyColor && !options.isEmpty && options.allSatisfy { $0.allSatisfy { $0 == "C" } } }
    }

    static func production(of action: LegalAction) -> Production? {
        let label = action.label
        let addRange = label.range(of: "Add", options: .caseInsensitive)
        var sacrifices = false
        if let addRange {
            let costPart = String(label[..<addRange.lowerBound])
            if let colon = costPart.lastIndex(of: ":") {
                let cost = costPart[..<colon].uppercased().replacingOccurrences(of: " ", with: "")
                let name = (action.cardName ?? "").uppercased().replacingOccurrences(of: " ", with: "")
                // A tap, a sacrifice of the source itself, or both ("{T}, Sacrifice this artifact"); anything else is
                // a cost the player chooses to pay.
                let parts = cost.split(separator: ",").map(String.init)
                for part in parts {
                    if part == "{T}" { continue }
                    if part.hasPrefix("SACRIFICE"), part.hasPrefix("SACRIFICETHIS") || part == "SACRIFICEIT" || (!name.isEmpty && part == "SACRIFICE" + name) {
                        sacrifices = true
                        continue
                    }
                    return nil
                }
            }
        }
        if let produced = action.producedMana?.map({ $0.uppercased() }), !produced.isEmpty {
            // One symbol repeated is one ability making that much ({C}{C}); different symbols are alternatives.
            return Production(options: Set(produced).count == 1 ? [produced] : produced.map { [$0] }, sacrifices: sacrifices)
        }
        guard let addRange else { return nil }
        let effect = String(label[addRange.upperBound...])
        if effect.range(of: "any color", options: .caseInsensitive) != nil || effect.range(of: "any colour", options: .caseInsensitive) != nil {
            return Production(options: [], anyColor: true, sacrifices: sacrifices)
        }
        // Stop at the first sentence: reminder text and riders ("Activate only…", "deals 1 damage") follow it.
        let clause = effect.split(separator: ".", maxSplits: 1).first.map(String.init) ?? effect
        // "Add {W}, {B}, or {G}" is three choices of one mana each, not {W}{B} or {G}.
        let alternatives = clause.replacingOccurrences(of: ", or ", with: "|").replacingOccurrences(of: " or ", with: "|")
            .replacingOccurrences(of: ",", with: "|").components(separatedBy: "|")
        let options = alternatives.map { part -> [String] in
            symbols(in: part).filter { colors.contains($0) || $0 == "C" }
        }.filter { !$0.isEmpty }
        guard !options.isEmpty else { return nil }
        return Production(options: options, sacrifices: sacrifices)
    }

    private static func symbols(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{([A-Z0-9]+)\\}") else { return [] }
        let source = text.uppercased() as NSString
        return regex.matches(in: source as String, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) }
    }

    /// What kind of permanent a mana source is, when the board says: a creature tapped for mana can't attack or block.
    enum SourceKind { case land, creature, other }

    /// One permanent that can make mana now, and the ways it can (a dual land offers one action per colour).
    struct Source {
        let key: String
        var yields: [Yield]
        /// Its cheapest yield's cost: the order sources are tried in.
        var cost: Int { yields.map(\.cost).min() ?? 0 }

        /// One way to tap it: the action to send, what it makes (`*` is a mana of any colour) and what using it costs
        /// the plan (a land's sacrifice ability costs more than its tap: Crystal Vein).
        struct Yield {
            let actionID: String
            let symbols: [String]
            var cost: Int
        }
    }

    /// The order a payment spends sources in, as a cost: single-colour lands, then duals, then tri-lands and
    /// any-colour lands, then creatures, and a sacrifice (Treasure) only when nothing else will do. Mana a source makes
    /// beyond the cost is waste.
    static func sources(from actions: [LegalAction], kinds: [String: SourceKind] = [:]) -> [Source] {
        var byKey: [String: Source] = [:]
        var order: [String] = []
        for action in actions where action.type == "make_mana" {
            guard let key = action.sourceInstanceId ?? action.cardInstanceId, let production = production(of: action) else { continue }
            var cost = production.anyColor ? 18 : [0, 10, 14, 16, 16, 16][min(production.colorCount, 5)]
            // Colourless-only sources pay generic before any coloured one, keeping colours open.
            if production.colorlessOnly { cost = 9 }
            if production.sacrifices { cost = 60 }
            if kinds[key] == .creature { cost += 10 }
            let yields: [Source.Yield] = production.anyColor
                ? [Source.Yield(actionID: action.id, symbols: ["*"], cost: cost)]
                : production.options.map { Source.Yield(actionID: action.id, symbols: $0, cost: cost) }
            if var existing = byKey[key] {
                existing.yields += yields
                byKey[key] = existing
            } else {
                byKey[key] = Source(key: key, yields: yields)
                order.append(key)
            }
        }
        // Several abilities on one permanent (a dual land's two colours) make it as flexible as their colours together.
        return order.compactMap { key in
            guard var source = byKey[key] else { return nil }
            let taps = source.yields.filter { $0.cost < 60 }
            let colorsMade = Set(taps.flatMap(\.symbols).filter { colors.contains($0) }).count
            if taps.count > 1, !taps.contains(where: { $0.symbols.contains("*") }) {
                let combined = [0, 10, 14, 16, 16, 16][min(colorsMade, 5)] + (kinds[key] == .creature ? 10 : 0)
                for index in source.yields.indices where source.yields[index].cost < 60 {
                    source.yields[index].cost = max(source.yields[index].cost, combined)
                }
            }
            return source
        }
    }

    /// One planned tap: the permanent, the action and, for a mana of any colour, which colour to name.
    struct PlannedTap: Equatable {
        let key: String
        let actionID: String
        let color: String?
    }

    /// The cheapest way to pay the whole cost from these sources, or nil when they can't. Coloured pips are matched
    /// first (the most constrained first), hybrids take whichever half is cheaper, and generic takes what is left;
    /// taps for coloured pips come first in the plan.
    static func plan(need: Need, sources: [Source]) -> [PlannedTap]? {
        struct Pip { let accepts: [String]; let generic: Int }
        var pips: [Pip] = []
        for (symbol, count) in need.symbols.sorted(by: { $0.key < $1.key }) where count > 0 {
            pips += Array(repeating: Pip(accepts: [symbol], generic: 0), count: count)
        }
        for hybrid in need.hybrids {
            let generic = hybrid.compactMap { $0.hasPrefix("generic") ? Int($0.dropFirst(7)) : nil }.first ?? 0
            pips.append(Pip(accepts: hybrid.filter { !$0.hasPrefix("generic") }, generic: generic))
        }
        func accepts(_ yield: Source.Yield, _ pip: Pip) -> Bool {
            yield.symbols.contains { $0 == "*" ? pip.accepts.contains(where: colors.contains) : pip.accepts.contains($0) }
        }
        pips.sort { lhs, rhs in
            func options(_ pip: Pip) -> Int { sources.filter { $0.yields.contains { accepts($0, pip) } }.count }
            return (options(lhs), lhs.accepts.joined()) < (options(rhs), rhs.accepts.joined())
        }

        // A used source: the yield chosen and the units of it still unspent.
        struct Use { var yield: Int; var left: [String] }
        var best: (cost: Int, uses: [Int: Use], colors: [Int: String], order: [Int])?
        var uses: [Int: Use] = [:]
        var named: [Int: String] = [:]
        var order: [Int] = []
        var nodes = 0

        func spentCost() -> Int { uses.reduce(0) { $0 + sources[$1.key].yields[$1.value.yield].cost } }

        func finish(extraGeneric: Int) {
            // Generic: leftover units first, then the cheapest fill of unused sources (small knapsack on units).
            let owed = need.generic + extraGeneric
            let leftover = uses.values.reduce(0) { $0 + $1.left.count }
            var cost = spentCost()
            var fill: [(index: Int, yield: Int)] = []
            if owed > leftover {
                let short = owed - leftover
                let unused = sources.indices.filter { uses[$0] == nil }
                // dp over units reached (capped): the cheapest set of sources, each used one way at most.
                let cap = short + 2
                var dp: [(cost: Int, picks: [(index: Int, yield: Int)])?] = Array(repeating: nil, count: cap + 1)
                dp[0] = (0, [])
                for index in unused {
                    let previous = dp
                    for (yieldIndex, yield) in sources[index].yields.enumerated() {
                        for reached in 0...cap {
                            guard let current = previous[reached] else { continue }
                            let next = min(cap, reached + max(1, yield.symbols.count))
                            let candidate: (cost: Int, picks: [(index: Int, yield: Int)]) = (current.cost + yield.cost, current.picks + [(index: index, yield: yieldIndex)])
                            if dp[next] == nil || candidate.0 < dp[next]!.cost { dp[next] = candidate }
                        }
                    }
                }
                guard let pick = (short...cap).compactMap({ reached in dp[reached].map { (reached, $0) } })
                    .min(by: { ($0.1.cost + 3 * ($0.0 - short)) < ($1.1.cost + 3 * ($1.0 - short)) }) else { return }
                cost += pick.1.cost + 3 * (pick.0 - short)
                fill = pick.1.picks
            } else {
                cost += 3 * (leftover - owed)
            }
            if best == nil || cost < best!.cost {
                var all = uses
                for pick in fill { all[pick.index] = Use(yield: pick.yield, left: []) }
                best = (cost, all, named, order + fill.map(\.index))
            }
        }

        func assign(_ next: Int, extraGeneric: Int) {
            nodes += 1
            if nodes > 40_000 { return }
            if let best, spentCost() >= best.cost { return }
            guard next < pips.count else { finish(extraGeneric: extraGeneric); return }
            let pip = pips[next]
            // A unit left on a source already tapped costs nothing more.
            for index in uses.keys.sorted() {
                guard let slot = uses[index]!.left.firstIndex(where: { $0 == "*" ? pip.accepts.contains(where: colors.contains) : pip.accepts.contains($0) }) else { continue }
                var use = uses[index]!
                let unit = use.left.remove(at: slot)
                uses[index] = use
                let before = named[index]
                if unit == "*" { named[index] = pip.accepts.first(where: colors.contains) }
                assign(next + 1, extraGeneric: extraGeneric)
                named[index] = before
                use.left.insert(unit, at: slot)
                uses[index] = use
            }
            // A new source: one of each identical kind is enough to try.
            var tried = Set<String>()
            for index in sources.indices.sorted(by: { (sources[$0].cost, $0) < (sources[$1].cost, $1) }) where uses[index] == nil {
                for (yieldIndex, yield) in sources[index].yields.enumerated() where accepts(yield, pip) {
                    let signature = sources[index].yields.map { "\($0.cost):" + $0.symbols.joined() }.joined(separator: ",") + "|\(yieldIndex)"
                    guard tried.insert(signature).inserted else { continue }
                    var left = yield.symbols
                    let slot = left.firstIndex(where: { $0 == "*" ? pip.accepts.contains(where: colors.contains) : pip.accepts.contains($0) })!
                    let unit = left.remove(at: slot)
                    uses[index] = Use(yield: yieldIndex, left: left)
                    if unit == "*" { named[index] = pip.accepts.first(where: colors.contains) }
                    order.append(index)
                    assign(next + 1, extraGeneric: extraGeneric)
                    order.removeLast()
                    named[index] = nil
                    uses[index] = nil
                }
            }
            // {2/W}: pay its generic half instead.
            if pip.generic > 0 { assign(next + 1, extraGeneric: extraGeneric + pip.generic) }
        }

        assign(0, extraGeneric: 0)
        guard let best else { return nil }
        return best.order.map { index in
            let source = sources[index]
            let yield = source.yields[best.uses[index]?.yield ?? 0]
            let color = yield.symbols.contains("*") ? (best.colors[index] ?? colors.first) : nil
            return PlannedTap(key: source.key, actionID: yield.actionID, color: color)
        }
    }

    /// The next Auto Pay step for a cost (`remainingText`), given the floating mana the prompt can spend and the
    /// legal actions: floating mana first, then the first tap of the cheapest plan that pays the whole cost.
    static func next(remainingText: String, floating: [String: Int], actions: [LegalAction], kinds: [String: SourceKind] = [:]) -> Step {
        let need = need(from: remainingText)
        guard !need.isEmpty else { return .done }

        // Floating mana first: it empties at the end of the step anyway.
        for (symbol, count) in need.symbols.sorted(by: { $0.key < $1.key }) where count > 0 && (floating[symbol] ?? 0) > 0 {
            return .spend(symbol: symbol)
        }
        for hybrid in need.hybrids {
            if let symbol = hybrid.first(where: { (floating[$0] ?? 0) > 0 }) { return .spend(symbol: symbol) }
        }
        if need.generic > 0 {
            // Generic takes floating mana that no coloured pip still wants, the most plentiful first.
            let surplus = floating.map { ($0.key, $0.value - (need.symbols[$0.key] ?? 0)) }.filter { $0.1 > 0 }
            if let symbol = surplus.sorted(by: { ($1.1, $0.0) < ($0.1, $1.0) }).first?.0 {
                return .spend(symbol: symbol)
            }
        }

        let sources = sources(from: actions, kinds: kinds)
        guard let plan = plan(need: need, sources: sources), let first = plan.first else {
            // Say what is short: a colour no source makes, or just not enough mana.
            let owed = need.generic + need.symbols.values.reduce(0, +) + need.hybrids.count
            if sources.count < owed { return .blocked("Not enough untapped mana for this cost") }
            if let missing = need.symbols.keys.sorted().first(where: { symbol in !sources.contains { $0.yields.contains { $0.symbols.contains(symbol) || $0.symbols.contains("*") && colors.contains(symbol) } } }) {
                return .blocked("No untapped source makes {\(missing)}")
            }
            return .blocked("Your untapped mana can't pay this cost")
        }
        return .tap(actionID: first.actionID, color: first.color)
    }
}

/// Which combat declaration the table is asking you for. The on-device engine asks it as a target prompt in the
/// declare steps (tap a creature to toggle it, then Done); the gateway sent declare_attackers / declare_blockers actions.
enum ArenaCombatPhase: Equatable {
    case attackers, blockers

    static func current(in snapshot: GameSnapshot) -> ArenaCombatPhase? {
        let actions = snapshot.legalActions ?? []
        if actions.contains(where: { $0.type == "declare_attackers" }) { return .attackers }
        if actions.contains(where: { $0.type == "declare_blockers" }) { return .blockers }
        guard let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
              prompt.responseKind.lowercased() == "target" || prompt.responseCommand?.type?.lowercased() == "choose_target" else { return nil }
        let step = (snapshot.step ?? snapshot.phase).lowercased().replacingOccurrences(of: "_", with: "-")
        if step.contains("declare-attack") { return .attackers }
        if step.contains("declare-block") { return .blockers }
        return nil
    }
}

extension ArenaAutoPay {
    /// The next Auto Pay step for the cost being paid in this snapshot: XMage's own remaining-cost text, the floating
    /// mana its payment prompt offers, and the mana sources it lists as legal.
    static func next(in snapshot: GameSnapshot) -> Step {
        guard snapshot.manaPayment?.active == true || snapshot.promptEnvelopeV2?.responseKind.lowercased() == "mana" else { return .done }
        let remaining = snapshot.manaPayment?.remainingText ?? snapshot.promptEnvelopeV2?.message ?? ""
        var floating: [String: Int] = [:]
        for choice in snapshot.promptEnvelopeV2?.manaChoices ?? [] { floating[choice.manaType ?? choice.id, default: 0] += choice.amount ?? 0 }
        return next(remainingText: remaining, floating: floating, actions: snapshot.legalActions ?? [], kinds: sourceKinds(in: snapshot))
    }

    /// Lands, creatures and other permanents on the battlefield, by instance id.
    static func sourceKinds(in snapshot: GameSnapshot) -> [String: SourceKind] {
        var kinds: [String: SourceKind] = [:]
        for card in snapshot.players.flatMap(\.zones.battlefield) {
            kinds[card.instanceId] = card.isCreature ? .creature : card.card.isLand ? .land : .other
        }
        return kinds
    }
}

/// Cards you can play from somewhere other than your hand (flashback from the graveyard, impulse draws and adventures
/// in exile): the reference shows them just right of your hand, shimmering, though they stay in their zone.
enum ArenaExtraHand {
    static func cards(for player: PlayerGameState, actions: [LegalAction]) -> [ZoneCard] {
        let playable = Set(actions.filter { ["cast_spell", "play_land"].contains($0.type) }.compactMap { $0.cardInstanceId ?? $0.sourceInstanceId })
        guard !playable.isEmpty else { return [] }
        return (player.zones.graveyard + player.zones.exile).filter { playable.contains($0.instanceId) || playable.contains($0.id) }
    }
}

// MARK: - Choices, numbers, splits and the glossary (docs/ARENA_STYLE.md)

/// XMage's named choices, read for the Arena choice browser: each "Remember answer: X" pairs with its X (one "Remember
/// my choice" toggle instead of a second list), and "Doubling Season: If an effect…" splits into the card it names and
/// that card's text.
enum ArenaChoiceList {
    struct Option: Equatable {
        let id: String
        /// The same answer, remembered for the rest of the game.
        let rememberID: String?
        let label: String
        /// The card the choice names, when it starts with one ("Name: text").
        let name: String?
        let text: String
    }

    static let rememberPrefix = "Remember answer: "

    static func options(_ choices: [(id: String, label: String)]) -> [Option] {
        let remembered = Dictionary(choices.filter { $0.label.hasPrefix(rememberPrefix) }
            .map { (String($0.label.dropFirst(rememberPrefix.count)), $0.id) }, uniquingKeysWith: { first, _ in first })
        return choices.filter { !$0.label.hasPrefix(rememberPrefix) }.map { choice in
            var name: String?
            var text = choice.label
            if let colon = choice.label.range(of: ": "), choice.label.distance(from: choice.label.startIndex, to: colon.lowerBound) <= 40 {
                // XMage names a card with its id: "Doubling Season [8f2]".
                name = String(choice.label[..<colon.lowerBound])
                    .replacingOccurrences(of: #"\s*\[[^\]]*\]\s*$"#, with: "", options: .regularExpression)
                text = String(choice.label[colon.upperBound...])
            }
            return Option(id: choice.id, rememberID: remembered[choice.label], label: choice.label, name: name, text: text)
        }
    }

    /// "White" or "Red mana" as its mana symbol, for colour choices.
    static func colorSymbol(_ label: String) -> String? {
        let names = ["white": "W", "blue": "U", "black": "B", "red": "R", "green": "G", "colorless": "C", "colourless": "C"]
        let word = label.lowercased().replacingOccurrences(of: " mana", with: "").trimmingCharacters(in: .whitespaces)
        return names[word]
    }
}

/// A planeswalker ability's loyalty cost, as the reference shows it on a badge: "+1: Create a…" is +1 and its text.
enum ArenaLoyalty {
    static func split(_ text: String) -> (cost: String, text: String)? {
        guard let match = text.range(of: #"^\s*([+−-]?\s*(?:\d+|X))\s*:\s*"#, options: .regularExpression) else { return nil }
        let cost = text[match].replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "−")
        return (cost, String(text[match.upperBound...]))
    }
}

/// The values the Arena's amount pill steps through: XMage's list when it gives one, else its minimum to maximum (an
/// open maximum stops 99 above the minimum).
struct ArenaAmountRange: Equatable {
    let values: [Int]

    init(amounts: [Int]?, minimum: Int?, maximum: Int?) {
        if let amounts, !amounts.isEmpty {
            values = Array(Set(amounts)).sorted()
        } else {
            // XMage's own bounds (negative ones too); an open maximum stops 99 above the minimum.
            let low = minimum ?? 0
            let high = max(low, min(maximum ?? (low + 99), low + 999))
            values = Array(low...high)
        }
    }

    var minimum: Int { values.first ?? 0 }
    var maximum: Int { values.last ?? 0 }

    /// `by` places along the allowed values, held at the ends.
    func step(_ value: Int, by places: Int) -> Int {
        let index = values.firstIndex(of: value) ?? values.firstIndex { $0 >= value } ?? 0
        return values[min(max(index + places, 0), values.count - 1)]
    }

    /// The nearest allowed value.
    func clamp(_ value: Int) -> Int { values.min { abs($0 - value) < abs($1 - value) } ?? value }

    /// The largest X the mana you have can pay: `sources` mana available, `cost` the spell's mana cost with its X.
    static func affordableX(cost: String, sources: Int) -> Int? {
        let symbols = cost.uppercased().components(separatedBy: CharacterSet(charactersIn: "{}")).filter { !$0.isEmpty }
        let xs = symbols.filter { $0 == "X" }.count
        guard xs > 0 else { return nil }
        let fixed = symbols.reduce(0) { total, symbol in
            if symbol == "X" { return total }
            if let generic = Int(symbol) { return total + generic }
            return total + 1
        }
        return max(0, (sources - fixed) / xs)
    }
}

/// Rows of a damage, counter or mana split, read for the Arena split browser.
enum ArenaSplit {
    /// "Grizzly Bears, P/T: 2/2" or "Grizzly Bears [8f2]" is Grizzly Bears.
    static func name(of label: String) -> String {
        var name = label
        if let range = name.range(of: ", P/T:") { name = String(name[..<range.lowerBound]) }
        name = name.replacingOccurrences(of: #"\s*\[[^\]]*\]\s*$"#, with: "", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Damage that destroys a creature: what's left of its toughness, or 1 from a source with deathtouch.
    static func lethal(toughness: Int, damage: Int, deathtouch: Bool) -> Int {
        deathtouch ? 1 : max(1, toughness - damage)
    }
}

/// The reference's keyword glossary beside an inspected card: what each keyword on it means, in a sentence.
enum ArenaKeywordGlossary {
    static let entries: [(keyword: String, meaning: String)] = [
        ("Flying", "Can be blocked only by creatures with flying or reach."),
        ("Reach", "Can block creatures with flying."),
        ("Trample", "Combat damage beyond what its blockers need goes on to the player or planeswalker it's attacking."),
        ("Deathtouch", "Any damage it deals to a creature is enough to destroy it."),
        ("Lifelink", "Damage it deals also gains its controller that much life."),
        ("Vigilance", "Attacking doesn't tap it."),
        ("Haste", "It can attack and use tap abilities the turn it comes under your control."),
        ("First strike", "Deals combat damage before creatures without first strike."),
        ("Double strike", "Deals both first-strike and regular combat damage."),
        ("Menace", "Can't be blocked except by two or more creatures."),
        ("Hexproof", "Can't be the target of spells or abilities your opponents control."),
        ("Shroud", "Can't be the target of any spell or ability."),
        ("Indestructible", "Damage and \"destroy\" effects don't destroy it."),
        ("Defender", "Can't attack."),
        ("Flash", "You may cast it any time you could cast an instant."),
        ("Ward", "When it becomes the target of an opponent's spell or ability, that player pays the ward cost or it's countered."),
        ("Prowess", "Whenever you cast a noncreature spell, it gets +1/+1 until end of turn."),
        ("Flashback", "You may cast this card from your graveyard for its flashback cost. Then it's exiled."),
        ("Kicker", "You may pay an extra cost as you cast it for an extra effect."),
        ("Cycling", "Pay its cycling cost and discard it to draw a card."),
        ("Equip", "Attach it to a creature you control, any time you could cast a sorcery."),
        ("Toxic", "Players it deals combat damage to also get that many poison counters."),
        ("Infect", "Deals damage to creatures as -1/-1 counters and to players as poison counters."),
        ("Persist", "When it dies without a -1/-1 counter, it returns with one."),
        ("Undying", "When it dies without a +1/+1 counter, it returns with one."),
        ("Convoke", "Your creatures can help cast it: each one you tap pays for {1} or one mana of its colour."),
        ("Cascade", "When you cast it, reveal cards until a cheaper nonland card; you may cast that card free."),
        ("Storm", "When you cast it, copy it for each spell cast before it this turn."),
        ("Changeling", "It is every creature type."),
        ("Protection", "Can't be blocked, targeted, damaged, enchanted or equipped by anything with that quality."),
        ("Treasure", "A token artifact: tap and sacrifice it to add one mana of any colour."),
        ("Food", "A token artifact: pay {2}, tap and sacrifice it to gain 3 life."),
        ("Clue", "A token artifact: pay {2} and sacrifice it to draw a card."),
    ]

    /// The keywords a card's rules mention, in the order they first appear, at most `limit`.
    static func entries(rules: String, limit: Int = 4) -> [(keyword: String, meaning: String)] {
        let text = rules.lowercased()
        let found: [(Int, (keyword: String, meaning: String))] = entries.compactMap { entry in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: entry.keyword.lowercased()) + "\\b"
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            return (text.distance(from: text.startIndex, to: range.lowerBound), entry)
        }
        return Array(found.sorted { $0.0 < $1.0 }.map(\.1).prefix(limit))
    }
}

/// Your commander on an opponent's battlefield (Caleb, 2026-10-21: Necromantic Selection took Chatterfang and he never
/// saw why). XMage moves a dead commander home as a state-based action, after the spell that killed it has finished, so
/// a spell that destroys and then returns creatures can take it first. The board names who has it and explains.
enum ArenaCommanderSteal {
    /// "Name|holder id" for each of your commanders an opponent controls now.
    static func taken(in snapshot: GameSnapshot) -> [String] {
        guard let viewer = snapshot.players.first(where: { snapshot.isViewer($0.playerId) }) else { return [] }
        let names = Set((viewer.commanders ?? []).compactMap(\.name).filter { !$0.isEmpty })
        guard !names.isEmpty else { return [] }
        return snapshot.players.filter { !snapshot.isViewer($0.playerId) }.flatMap { player in
            player.zones.battlefield.filter { names.contains($0.card.name) }.map { "\($0.card.name)|\(player.playerId)" }
        }.sorted()
    }

    /// The notice for a commander that has just been taken.
    static func notice(_ entry: String, snapshot: GameSnapshot) -> String {
        let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
        let name = parts.first ?? "Your commander"
        let holder = parts.count > 1 ? snapshot.playerLabel(parts[1]) : "An opponent"
        return "\(holder) took \(name). A commander goes to the command zone only after the spell that moved it finishes, so that spell could take it first."
    }
}

/// A board wipe's recap for the caption: the spell that just resolved and what left the battlefield because of it
/// ("Necromantic Selection: 6 to the graveyard"), three or more at once, as BoardFXScheduler's cascade (Caleb,
/// 2026-10-21: a wipe went by too fast to see what it took).
enum ArenaSweepRecap {
    static func text(spell: String?, events: [BoardFXEvent]) -> String? {
        var graveyard = 0, exile = 0, other = 0
        for event in events {
            guard case let .leftBattlefield(_, _, zone, _) = event else { continue }
            switch zone {
            case .graveyard: graveyard += 1
            case .exile: exile += 1
            default: other += 1
            }
        }
        guard graveyard + exile + other >= BoardFXScheduler.sweepMinimum else { return nil }
        let parts = [graveyard > 0 ? "\(graveyard) to the graveyard" : nil, exile > 0 ? "\(exile) exiled" : nil,
                     other > 0 ? "\(other) returned or moved" : nil].compactMap { $0 }
        let what = parts.joined(separator: ", ")
        return spell.map { "\($0): \(what)" } ?? "\(graveyard + exile + other) permanents left the battlefield: \(what)"
    }
}

/// A chosen trigger order's decisions, apart from the view's state (parity/trigger-plan-cases.json; the web's TriggerPlan
/// runs the same cases). `plan`: ability ids in the order they go on the stack; `sent`: the ordering prompt
/// ("id:messageId") last answered from it.
enum ArenaTriggerPlan {
    /// `resolveOrder` runs first to last; XMage asks which goes on the stack first, which resolves last.
    static func start(_ resolveOrder: [XmagePromptAbility]) -> [String] { resolveOrder.reversed().map(\.id) }

    /// The plan answers this ordering prompt by itself: it offers a planned trigger and hasn't been answered yet. A prompt
    /// the plan already answered and still showing (a refused pick) goes back to the browser.
    static func answers(plan: [String], sent: String?, snapshot: GameSnapshot) -> Bool {
        guard !plan.isEmpty, let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
              prompt.isTriggerOrder, let abilities = prompt.abilities else { return false }
        return "\(prompt.id):\(prompt.messageId)" != sent && abilities.contains { plan.contains($0.id) }
    }

    /// The next pick of a chosen trigger order. Triggers XMage no longer offers are on the stack and leave the plan; a
    /// target question for one of them keeps it; your next priority, or an ordering prompt with none of its triggers
    /// (the last one XMage places itself), ends it.
    static func step(plan: [String], sent: String?, snapshot: GameSnapshot, pending: Bool)
        -> (plan: [String], sent: String?, pick: XmagePromptAbility?) {
        guard !plan.isEmpty, !pending, let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId) else { return (plan, sent, nil) }
        guard prompt.isTriggerOrder, let abilities = prompt.abilities, !abilities.isEmpty else {
            if prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority" { return ([], nil, nil) }
            return (plan, sent, nil)
        }
        let remaining = plan.filter { id in abilities.contains { $0.id == id } }
        guard let next = remaining.first, let ability = abilities.first(where: { $0.id == next }) else { return (remaining, nil, nil) }
        let key = "\(prompt.id):\(prompt.messageId)"
        guard key != sent else { return (remaining, sent, nil) }
        return (remaining, key, ability)
    }
}
