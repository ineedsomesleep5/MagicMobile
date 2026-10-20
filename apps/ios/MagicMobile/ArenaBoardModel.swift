import CoreGraphics
import Foundation

/// The board's two modes (Caleb, 2026-10-20). Hearth is the Walnut Tavern board with the hourglass, the mana rail and the
/// table's sockets. Arena is the reference game's board on a leaning tavern table: controls in one corner, a hand that
/// rises and rests, the stack's top card on the right, and your picture inside your life medallion. Each mode gets its
/// own themes later; Walnut Tavern is the first for both.
enum BoardMode: String, CaseIterable, Identifiable {
    case hearth, arena

    var id: String { rawValue }
    var title: String { self == .hearth ? "Hearth" : "Arena" }
    var summary: String {
        self == .hearth ? "The tavern table with the hourglass and mana rail."
                        : "Corner controls, a rising hand and the stack on the right."
    }

    static let key = "magicmobile.boardMode"
    static let defaultValue = BoardMode.hearth.rawValue
    static func resolved(_ value: String) -> BoardMode { BoardMode(rawValue: value) ?? .hearth }
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

    /// The landscape table (scripts/brand/arena_layout.json "landscape").
    static let landscapeLayout = ArenaLayout(
        canvas: CGSize(width: 956, height: 440), landscape: true,
        // Positions follow the current reference game (Caleb's desktop screenshot, 2026-10-20): your hand rests tucked
        // along the bottom edge in a wide fan and opens when touched; your medallion stands above it in the gap of your
        // back row; your graveyard, library and exile sit in the bottom-left corner, the opponent's top right.
        // The tucked fan ends before the controls corner on the right and after the exile pile on the left.
        hand: Hand(card: CGSize(width: 93, height: 131), centerX: 450, upY: 368, upPitch: 92, upSpan: 520, upDrop: 2.6,
                   tilt: 3.5, maxTilt: 11, downY: 448, downPitch: 58, downSpan: 430, downDrop: 1.2, downScale: 1,
                   lift: 48, liftDown: 92, maxDrop: 14, upFloor: 437),
        opponentHand: CGPoint(x: 478, y: 4), opponentHandCard: CGSize(width: 36, height: 50), opponentHandPitch: 30,
        viewerMedallion: CGPoint(x: 478, y: 352), viewerMedallionDiameter: 58,
        opponentMedallion: CGPoint(x: 478, y: 25), opponentMedallionDiameter: 50,
        viewerLibrary: CGPoint(x: 108, y: 398), viewerGraveyard: CGPoint(x: 60, y: 398), viewerPile: CGSize(width: 42, height: 59),
        viewerExile: CGPoint(x: 156, y: 398), opponentExile: CGPoint(x: 652, y: 30),
        opponentLibrary: CGPoint(x: 704, y: 30), opponentGraveyard: CGPoint(x: 756, y: 30), opponentPile: CGSize(width: 36, height: 50),
        opponentLands: CGRect(x: 80, y: 54, width: 360, height: 66),
        viewerLands: CGRect(x: 80, y: 290, width: 360, height: 70),
        opponentSupport: CGRect(x: 540, y: 54, width: 332, height: 66),
        viewerSupport: CGRect(x: 540, y: 290, width: 160, height: 70),
        opponentSideY: 116, viewerSideY: 248,
        // The front rows run the table's full width, inside the mat's leaning edges (Caleb, 2026-10-20).
        opponentCreatureY: 146, viewerCreatureY: 248, creatureLaneX: 84...872, rowBack: 76,
        tile: CGSize(width: 66, height: 71), land: CGSize(width: 58, height: 62.5),
        stack: CGRect(x: 708, y: 46, width: 175, height: 250),
        draw: CGRect(x: 686, y: 187, width: 106, height: 148),
        primary: CGRect(x: 708, y: 388, width: 176, height: 36),
        secondary: CGRect(x: 708, y: 335, width: 176, height: 37),
        phaseStripX: 708...884, phaseStripY: 368, phaseStripRaisedY: 314,
        passAhead: CGRect(x: 656, y: 392, width: 42, height: 28),
        undo: CGRect(x: 650, y: 343, width: 52, height: 26),
        menu: CGPoint(x: 876, y: 23),
        floatingMana: CGPoint(x: 92, y: 405),
        captionY: 197, bannerY: 210,
        dropArea: CGRect(x: 60, y: 30, width: 640, height: 258),
        railTop: nil)

    /// The portrait table (scripts/brand/arena_layout.json "portrait"): the board split at the compass, the opponent
    /// in the top half, you in the bottom half, and every control on the walnut rail under the mat.
    static let portraitLayout = ArenaLayout(
        canvas: CGSize(width: 440, height: 956), landscape: false,
        // The tucked hand at full size: card tops just below your lands, the rest behind the front rail (Caleb,
        // 2026-10-20), clear of the exile pile on the left.
        hand: Hand(card: CGSize(width: 104, height: 146), centerX: 220, upY: 784, upPitch: 58, upSpan: 336, upDrop: 2.2,
                   tilt: 3, maxTilt: 10, downY: 779, downPitch: 46, downSpan: 230, downDrop: 1, downScale: 1,
                   lift: 52, liftDown: 60),
        opponentHand: CGPoint(x: 340, y: 20), opponentHandCard: CGSize(width: 30, height: 42), opponentHandPitch: 14,
        // Your medallion and piles sit low on the rail, level with the main button (Caleb, 2026-10-20).
        viewerMedallion: CGPoint(x: 50, y: 890), viewerMedallionDiameter: 74,
        opponentMedallion: CGPoint(x: 42, y: 36), opponentMedallionDiameter: 54,
        viewerLibrary: CGPoint(x: 123, y: 891), viewerGraveyard: CGPoint(x: 167, y: 891), viewerPile: CGSize(width: 38, height: 53),
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
        dropArea: CGRect(x: 0, y: 70, width: 440, height: 630),
        railTop: 815)

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

/// Where a non-land permanent sits in its side's front row, the reference game's way: creatures across the row,
/// everything else (planeswalkers, battles, sagas and other enchantments, artifacts) in a section of its own at the
/// row's right end, planeswalkers and battles outermost. Lands, mana rocks and Treasures take the back row.
/// An Aura or Equipment goes wherever the permanent it is attached to goes.
enum ArenaFrontSection: Equatable {
    case creatures, side

    static func of(_ card: ZoneCard) -> ArenaFrontSection { card.isCreature ? .creatures : .side }

    /// Order inside the side section: other permanents first, planeswalkers and battles at the far right.
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

    /// The reference game's hand (Caleb, 2026-10-20): it rests tucked along the bottom edge with only the cards' tops
    /// showing, and opens into a fan when you touch it; a tap on the table puts it back.
    struct Situation: Equatable {
        /// The player tapped the hand open.
        var opened = false
        /// Paying a cost, choosing a target, declaring attackers or blockers, or answering a choice: the hand gets out
        /// of the way so the board can be read and tapped.
        var boardDecision = false
        var dragging = false
        var spectating = false
    }

    static func resolve(_ situation: Situation) -> ArenaHandPosture {
        if situation.spectating || situation.dragging || situation.boardDecision { return .resting }
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
    /// Card `index` of `count` in the given posture, in design points.
    static func slot(index: Int, count: Int, posture: ArenaHandPosture, hand: ArenaLayout.Hand) -> ArenaHandSlot {
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
        case tap(actionID: String)
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
    /// colour. Nil when the ability costs more than a tap (life, other mana, a sacrifice): those stay manual.
    struct Production: Equatable {
        var options: [[String]]
        var anyColor = false

        func makes(_ symbol: String) -> Bool { anyColor && colors.contains(symbol) || options.contains { $0.contains(symbol) } }
        var amount: Int { anyColor ? 1 : options.map(\.count).max() ?? 0 }
        var colorCount: Int { anyColor ? 5 : Set(options.flatMap { $0 }.filter { colors.contains($0) }).count }
        var colorlessOnly: Bool { !anyColor && !options.isEmpty && options.allSatisfy { $0.allSatisfy { $0 == "C" } } }
    }

    static func production(of action: LegalAction) -> Production? {
        if let produced = action.producedMana?.map({ $0.uppercased() }), !produced.isEmpty {
            // One symbol repeated is one ability making that much ({C}{C}); different symbols are alternatives.
            return Production(options: Set(produced).count == 1 ? [produced] : produced.map { [$0] })
        }
        let label = action.label
        guard let addRange = label.range(of: "Add", options: .caseInsensitive) else { return nil }
        let costPart = String(label[..<addRange.lowerBound])
        if let colon = costPart.lastIndex(of: ":") {
            let cost = costPart[..<colon].uppercased().replacingOccurrences(of: " ", with: "")
            guard cost == "{T}" || cost.isEmpty else { return nil }
        }
        let effect = String(label[addRange.upperBound...])
        if effect.range(of: "any color", options: .caseInsensitive) != nil || effect.range(of: "any colour", options: .caseInsensitive) != nil {
            return Production(options: [], anyColor: true)
        }
        // Stop at the first sentence: reminder text and riders ("Activate only…", "deals 1 damage") follow it.
        let clause = effect.split(separator: ".", maxSplits: 1).first.map(String.init) ?? effect
        let options = clause.components(separatedBy: " or ").map { part -> [String] in
            symbols(in: part).filter { colors.contains($0) || $0 == "C" }
        }.filter { !$0.isEmpty }
        guard !options.isEmpty else { return nil }
        return Production(options: options)
    }

    private static func symbols(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{([A-Z0-9]+)\\}") else { return [] }
        let source = text.uppercased() as NSString
        return regex.matches(in: source as String, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range(at: 1)) }
    }

    /// The next Auto Pay step for a cost (`remainingText`), given the floating mana the prompt can spend and the
    /// legal actions. Coloured pips go first, starting with the colour the fewest sources make; single-colour sources
    /// are spent before flexible ones, and generic costs take colourless sources first.
    static func next(remainingText: String, floating: [String: Int], actions: [LegalAction]) -> Step {
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

        let sources: [(action: LegalAction, production: Production)] = actions
            .filter { $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil) }
            .compactMap { action in production(of: action).map { (action, $0) } }
        // How many colours each permanent can make across all its mana abilities: the less flexible, the sooner spent.
        var flexibility: [String: Int] = [:]
        var amounts: [String: Int] = [:]
        for source in sources {
            let key = source.action.sourceInstanceId ?? source.action.cardInstanceId ?? source.action.id
            flexibility[key] = max(flexibility[key] ?? 0, source.production.colorCount)
            amounts[key] = max(amounts[key] ?? 0, source.production.amount)
        }
        // Never start tapping for a cost that can't be finished: the lands would stay tapped for nothing.
        let owed = need.generic + need.symbols.values.reduce(0, +) + need.hybrids.count
        // Floating mana that could help was spent above, so only untapped sources count here.
        let available = amounts.values.reduce(0, +)
        if available < owed { return .blocked("Not enough untapped mana for this cost") }
        func flex(_ action: LegalAction) -> Int { flexibility[action.sourceInstanceId ?? action.cardInstanceId ?? action.id] ?? 0 }

        // Coloured and colourless-specific pips, most constrained first.
        var demands: [[String]] = need.symbols.filter { $0.value > 0 }.map { [$0.key] }
        demands += need.hybrids.map { $0.filter { !$0.hasPrefix("generic") } }.filter { !$0.isEmpty }
        let ranked = demands.map { demand -> (demand: [String], candidates: [(action: LegalAction, production: Production)]) in
            (demand, sources.filter { source in demand.contains { source.production.makes($0) } })
        }.sorted { ($0.candidates.count, $0.demand.joined()) < ($1.candidates.count, $1.demand.joined()) }
        if let first = ranked.first {
            guard let pick = first.candidates.sorted(by: { lhs, rhs in
                (lhs.production.anyColor ? 1 : 0, flex(lhs.action), lhs.action.id) < (rhs.production.anyColor ? 1 : 0, flex(rhs.action), rhs.action.id)
            }).first else {
                // A {2/W}-style hybrid with no white source falls back to its generic half.
                if need.hybrids.contains(where: { $0.contains { $0.hasPrefix("generic") } }) && first.demand.allSatisfy({ colors.contains($0) }) {
                    return genericStep(sources: sources, flex: flex) ?? .blocked("No mana source left for this cost")
                }
                return .blocked("No untapped source makes {\(first.demand.joined(separator: "/"))}")
            }
            return .tap(actionID: pick.action.id)
        }
        return genericStep(sources: sources, flex: flex, generic: need.generic) ?? .blocked("No mana source left for this cost")
    }

    private static func genericStep(sources: [(action: LegalAction, production: Production)], flex: (LegalAction) -> Int,
                                    generic: Int = 1) -> Step? {
        let pick = sources.sorted { lhs, rhs in
            // Colourless first, then single colours, then flexible lands, then any-colour rocks; a two-mana rock is
            // welcome when two or more generic remain.
            func score(_ source: (action: LegalAction, production: Production)) -> (Int, Int, Int, String) {
                // A rock that would make more than is owed wastes the rest, so it waits; one that fits goes first.
                let multi = source.production.amount > 1 ? (generic >= source.production.amount ? -1 : 1) : 0
                return (multi, source.production.colorlessOnly ? 0 : source.production.anyColor ? 3 : 1, flex(source.action), source.action.id)
            }
            return score(lhs) < score(rhs)
        }.first
        return pick.map { .tap(actionID: $0.action.id) }
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
        return next(remainingText: remaining, floating: floating, actions: snapshot.legalActions ?? [])
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
