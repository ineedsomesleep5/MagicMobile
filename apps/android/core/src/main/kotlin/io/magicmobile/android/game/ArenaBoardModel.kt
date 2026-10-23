package io.magicmobile.android.game

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * Port of apps/ios/MagicMobile/ArenaBoardModel.swift: the board's two modes, Card Frames per mode, the Arena board's design
 * canvases (ArenaLayout, ArenaCanvas), its row fitting, the hand's postures and fan, Auto Pay, the combat phase, the extra
 * hand, and the small readers its screens share (choices, loyalty, amounts, splits, the keyword glossary, a taken commander,
 * a board wipe's recap). Pure logic; the numbers are the iOS ones (JVM tests: ArenaBoardModelTest).
 */

/**
 * The board's two modes (Caleb, 2026-10-20). Hearth is the Walnut Tavern board with the hourglass, the mana rail and the
 * table's sockets. Arena is the reference game's board on a leaning tavern table: controls in one corner, a hand that rises
 * and rests, the stack's top card on the right, and your picture inside your life medallion.
 */
enum class BoardMode(val rawValue: String, val title: String, val summary: String) {
    HEARTH("hearth", "Hearth", "The tavern table with the hourglass and mana rail."),
    ARENA("arena", "Arena", "Corner controls, a rising hand and the stack on the right.");

    companion object {
        const val key = "magicmobile.boardMode"
        val defaultValue = HEARTH.rawValue
        fun resolved(value: String?): BoardMode = entries.firstOrNull { it.rawValue == value } ?: HEARTH
    }
}

/** Tavern frames on battlefield cards, kept per board mode (Caleb, 2026-10-20): on for Hearth, off for Arena. */
object CardFramesPreference {
    const val hearthKey = "magicmobile.cardFrames.hearth"
    const val arenaKey = "magicmobile.cardFrames.arena"
    const val hearthDefault = true
    const val arenaDefault = false
}

fun BoardRect.offsetBy(dx: Float, dy: Float): BoardRect = BoardRect(x + dx, y + dy, width, height)
fun BoardRect.union(other: BoardRect): BoardRect {
    val left = min(minX, other.minX); val top = min(minY, other.minY)
    return BoardRect(left, top, max(maxX, other.maxX) - left, max(maxY, other.maxY) - top)
}
fun BoardRect.insetBy(dx: Float, dy: Float): BoardRect = BoardRect(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

/**
 * The Arena board's design canvases: landscape 956 × 440 (an iPhone 17 Pro Max held sideways) and portrait 440 × 956. Every
 * number was tuned in the Duel Board Prototype against the reference gameplay video. Other screens scale both axes; sizes
 * scale by the smaller axis.
 */
data class ArenaLayout(
    val canvas: BoardSize, val landscape: Boolean, val hand: Hand,
    /** The opponent's hand: card backs fanned from this point. */
    val opponentHand: BoardPoint, val opponentHandCard: BoardSize, val opponentHandPitch: Float,
    val viewerMedallion: BoardPoint, val viewerMedallionDiameter: Float, val opponentMedallion: BoardPoint, val opponentMedallionDiameter: Float,
    val viewerLibrary: BoardPoint, val viewerGraveyard: BoardPoint, val viewerPile: BoardSize,
    /** Exile piles: shown only while they hold cards. */
    val viewerExile: BoardPoint, val opponentExile: BoardPoint, val opponentLibrary: BoardPoint, val opponentGraveyard: BoardPoint,
    val opponentPile: BoardSize,
    val opponentLands: BoardRect, val viewerLands: BoardRect,
    /** Landscape: the back row's second section, right of centre (artifacts, mana rocks, Treasures); null in portrait. */
    val opponentSupport: BoardRect? = null, val viewerSupport: BoardRect? = null,
    /** Landscape: the centre line of each side's section for planeswalkers, battles and sagas; null in portrait. */
    val opponentSideY: Float? = null, val viewerSideY: Float? = null,
    val opponentCreatureY: Float, val viewerCreatureY: Float, val creatureLaneX: ClosedFloatingPointRange<Float>, val rowBack: Float,
    val tile: BoardSize, val land: BoardSize,
    /** The top of the stack, a big card on the right, and where a drawn card shows before joining the hand. */
    val stack: BoardRect, val draw: BoardRect,
    val primary: BoardRect, val secondary: BoardRect, val phaseStripX: ClosedFloatingPointRange<Float>, val phaseStripY: Float,
    val phaseStripRaisedY: Float, val passAhead: BoardRect, val undo: BoardRect, val menu: BoardPoint,
    val floatingMana: BoardPoint, val captionY: Float, val bannerY: Float, val dropArea: BoardRect,
    /** Portrait only: the walnut rail along the bottom; a resting hand tucks behind its top edge. */
    val railTop: Float?,
    /** The corner the drop area leaves out (the controls), as the reference does. */
    val dropCorner: BoardRect? = null,
) {
    data class Hand(
        /** Card size before the resting scale. */
        val card: BoardSize, val centerX: Float,
        /** Raised: centre line, widest pitch, total span of the centres, dip and tilt per step from the middle. */
        val upY: Float, val upPitch: Float, val upSpan: Float, val upDrop: Float, val tilt: Float, val maxTilt: Float,
        /** Resting: a tight fan at a smaller scale (in portrait it tucks behind the front rail). */
        val downY: Float, val downPitch: Float, val downSpan: Float, val downDrop: Float, val downScale: Float,
        /** How far a touched card rises from each posture. */
        val lift: Float, val liftDown: Float,
        /** Raised: the outer cards dip at most this far, and no card's corner reaches below `upFloor`. */
        val maxDrop: Float = Float.POSITIVE_INFINITY, val upFloor: Float = Float.POSITIVE_INFINITY,
        /** Whether a tap on the tucked hand opens it into the raised fan. Off in both layouts (Caleb, 2026-10-20). */
        val opensOnTap: Boolean = false,
        /** Touches on the hand count down to this line (design points) and no lower. */
        val touchBottom: Float? = null,
        /** Portrait: the bottom of the spread hand's row (design points), just over the front rail; null where there is no spread. */
        val spreadBottom: Float? = null,
    )

    /** Whether a card carried from `start` and let go at `point` (design points) plays: over the table, out of the controls
     *  corner, and carried up at least [dropLift] or [dropCarry] in any direction. */
    fun drops(point: BoardPoint, start: BoardPoint): Boolean =
        dropArea.contains(point) && dropCorner?.contains(point) != true &&
            (start.y - point.y >= dropLift || hypot(point.x - start.x, point.y - start.y) >= dropCarry)

    /** Front rows a side may use: landscape has no room between the lanes for a second; portrait grows one toward its owner. */
    val maxCreatureRows: Int get() = if (landscape) 1 else 2

    /** Tile and land sizes: the tavern frames are nearly square; the reference's cropped cards are wider than tall. */
    fun tiles(frames: Boolean): Pair<BoardSize, BoardSize> {
        if (frames) return tile to land
        return if (landscape) BoardSize(84f, 70f) to BoardSize(68f, 57f) else BoardSize(80f, 67f) to BoardSize(62f, 52f)
    }

    /** A creature lane for `rows` rows: the first row on its centre line, a second row toward its owner. */
    fun creatureLane(viewer: Boolean, rows: Int, tileHeight: Float? = null): BoardRect {
        val centerY = if (viewer) viewerCreatureY else opponentCreatureY
        // The row pads its tiles 8 pt above and below, so the lane leaves that room.
        val rowHeight = (tileHeight ?: tile.height) + 18
        val height = rowHeight + max(rows - 1, 0) * rowBack
        val top = if (viewer) centerY - rowHeight / 2 else centerY + rowHeight / 2 - height
        return BoardRect(creatureLaneX.start, top, creatureLaneX.endInclusive - creatureLaneX.start, height)
    }

    companion object {
        /** How far a card has to be carried before letting go plays it. */
        const val dropLift = 24f
        const val dropCarry = 80f

        /** The landscape table (scripts/brand/arena_layout.json "landscape"). */
        val landscapeLayout = ArenaLayout(
            canvas = BoardSize(956f, 440f), landscape = true,
            hand = Hand(card = BoardSize(93f, 131f), centerX = 490f, upY = 368f, upPitch = 92f, upSpan = 520f, upDrop = 2.6f,
                tilt = 3.5f, maxTilt = 11f, downY = 432f, downPitch = 50f, downSpan = 317f, downDrop = 1.2f, downScale = 1f,
                lift = 48f, liftDown = 92f, maxDrop = 14f, upFloor = 437f, touchBottom = 416f),
            opponentHand = BoardPoint(478f, 4f), opponentHandCard = BoardSize(36f, 50f), opponentHandPitch = 30f,
            viewerMedallion = BoardPoint(84f, 402f), viewerMedallionDiameter = 56f,
            opponentMedallion = BoardPoint(478f, 25f), opponentMedallionDiameter = 50f,
            viewerLibrary = BoardPoint(201f, 404f), viewerGraveyard = BoardPoint(147f, 404f), viewerPile = BoardSize(42f, 59f),
            viewerExile = BoardPoint(255f, 404f), opponentExile = BoardPoint(652f, 30f),
            opponentLibrary = BoardPoint(704f, 30f), opponentGraveyard = BoardPoint(756f, 30f), opponentPile = BoardSize(36f, 50f),
            opponentLands = BoardRect(80f, 54f, 360f, 66f), viewerLands = BoardRect(80f, 290f, 360f, 70f),
            opponentSupport = BoardRect(540f, 54f, 332f, 66f), viewerSupport = BoardRect(540f, 290f, 160f, 70f),
            opponentSideY = 116f, viewerSideY = 248f,
            opponentCreatureY = 146f, viewerCreatureY = 248f, creatureLaneX = 84f..872f, rowBack = 76f,
            tile = BoardSize(66f, 71f), land = BoardSize(58f, 62.5f),
            stack = BoardRect(716f, 60f, 158f, 222f), draw = BoardRect(686f, 187f, 106f, 148f),
            primary = BoardRect(708f, 388f, 176f, 36f), secondary = BoardRect(708f, 335f, 176f, 37f),
            phaseStripX = 708f..884f, phaseStripY = 368f, phaseStripRaisedY = 314f,
            passAhead = BoardRect(890f, 392f, 40f, 28f), undo = BoardRect(650f, 343f, 52f, 26f), menu = BoardPoint(876f, 23f),
            floatingMana = BoardPoint(80f, 405f), captionY = 197f, bannerY = 210f,
            dropArea = BoardRect(0f, 0f, 956f, 352f), railTop = null, dropCorner = BoardRect(640f, 300f, 316f, 140f))

        /** The portrait table (scripts/brand/arena_layout.json "portrait"): every control on the walnut rail under the mat. */
        val portraitLayout = ArenaLayout(
            canvas = BoardSize(440f, 956f), landscape = false,
            hand = Hand(card = BoardSize(104f, 146f), centerX = 220f, upY = 784f, upPitch = 58f, upSpan = 336f, upDrop = 2.2f,
                tilt = 3f, maxTilt = 10f, downY = 779f, downPitch = 46f, downSpan = 230f, downDrop = 1f, downScale = 1f,
                lift = 52f, liftDown = 60f, touchBottom = 825f, spreadBottom = 808f),
            opponentHand = BoardPoint(340f, 20f), opponentHandCard = BoardSize(30f, 42f), opponentHandPitch = 14f,
            viewerMedallion = BoardPoint(50f, 890f), viewerMedallionDiameter = 74f,
            opponentMedallion = BoardPoint(42f, 36f), opponentMedallionDiameter = 54f,
            viewerLibrary = BoardPoint(118f, 891f), viewerGraveyard = BoardPoint(168f, 891f), viewerPile = BoardSize(38f, 53f),
            viewerExile = BoardPoint(30f, 795f), opponentExile = BoardPoint(168f, 33f),
            opponentLibrary = BoardPoint(98f, 33f), opponentGraveyard = BoardPoint(133f, 33f), opponentPile = BoardSize(30f, 42f),
            opponentLands = BoardRect(14f, 95f, 412f, 62f), viewerLands = BoardRect(14f, 637f, 412f, 62f),
            opponentCreatureY = 384f, viewerCreatureY = 508f, creatureLaneX = 12f..428f, rowBack = 78f,
            tile = BoardSize(70f, 75.5f), land = BoardSize(54f, 58f),
            stack = BoardRect(312f, 363f, 116f, 166f), draw = BoardRect(280f, 530f, 100f, 140f),
            primary = BoardRect(272f, 882f, 156f, 40f), secondary = BoardRect(272f, 840f, 156f, 36f),
            phaseStripX = 272f..428f, phaseStripY = 860f, phaseStripRaisedY = 822f,
            passAhead = BoardRect(197f, 887f, 64f, 30f), undo = BoardRect(197f, 843f, 64f, 30f), menu = BoardPoint(414f, 28f),
            floatingMana = BoardPoint(112f, 752f), captionY = 446f, bannerY = 446f,
            dropArea = BoardRect(0f, 0f, 440f, 700f), railTop = 815f)

        fun current(size: BoardSize): ArenaLayout = if (size.width > size.height) landscapeLayout else portraitLayout
    }
}

/**
 * Maps the Arena design canvas onto a real screen. The table plate fills the screen, so points scale each axis on its own;
 * card, button and medallion sizes scale by the smaller axis so nothing stretches.
 */
data class ArenaCanvas(val screen: BoardSize) {
    val layout: ArenaLayout = ArenaLayout.current(screen)
    val scaleX: Float get() = screen.width / layout.canvas.width
    val scaleY: Float get() = screen.height / layout.canvas.height
    val scale: Float get() = min(scaleX, scaleY)

    fun point(point: BoardPoint): BoardPoint = BoardPoint(point.x * scaleX, point.y * scaleY)
    /** A screen point back in design points. */
    fun design(point: BoardPoint): BoardPoint = BoardPoint(point.x / max(scaleX, 0.001f), point.y / max(scaleY, 0.001f))
    /** Whether a card carried from `start` and let go at `point` (screen points) plays (ArenaLayout.drops). */
    fun drops(point: BoardPoint, start: BoardPoint): Boolean = layout.drops(design(point), design(start))
    fun x(value: Float): Float = value * scaleX
    fun y(value: Float): Float = value * scaleY
    fun length(value: Float): Float = value * scale
    fun size(size: BoardSize): BoardSize = BoardSize(size.width * scale, size.height * scale)
    /** A design rectangle: its centre maps by axis, its size by the smaller scale. */
    fun rect(rect: BoardRect): BoardRect {
        val center = point(BoardPoint(rect.midX, rect.midY))
        val size = size(BoardSize(rect.width, rect.height))
        return BoardRect(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height)
    }
    /** A design rectangle stretched with the screen on both axes (lanes and the play area). */
    fun area(rect: BoardRect): BoardRect = BoardRect(rect.minX * scaleX, rect.minY * scaleY, rect.width * scaleX, rect.height * scaleY)
}

/**
 * Where a non-land permanent sits, the current reference game's way: creatures across the front row; planeswalkers, battles
 * and sagas in a section of their own (planeswalkers and battles outermost); every other permanent in the back row right of
 * the lands. An Aura or Equipment goes wherever the permanent it is attached to goes.
 */
enum class ArenaFrontSection {
    CREATURES, SIDE, SUPPORT;

    companion object {
        fun of(card: ZoneCard): ArenaFrontSection {
            if (card.isCreature) return CREATURES
            val type = card.card.typeLine
            if (card.card.isPlaneswalker || type.contains("battle", true) || type.contains("saga", true)) return SIDE
            return SUPPORT
        }

        /** Order inside the side section: sagas first, planeswalkers and battles at the far right. */
        fun sideRank(card: ZoneCard): Int = if (card.card.isPlaneswalker || card.card.typeLine.contains("battle", true)) 1 else 0
    }
}

/**
 * Sizes one row of a side's board, a leading section and a trailing one, at a single card size, the reference game's way:
 * cards shrink as the row fills (a second row opens first where the layout has one), and only below the smallest size does
 * a section scroll. Widths include BattlefieldRow's 8-pt padding at each end and 4-pt spacing.
 */
data class ArenaRowFit(val cardWidth: Float, val rows: Int, val trailingWidth: Float, val overflows: Boolean) {
    companion object {
        const val padding = 8f
        const val spacing = 4f
        const val sectionGap = 10f
        /** The smallest a card shrinks to before its section scrolls, as a share of its full size. */
        const val minimumScale = 0.7f

        /** The width a section's piles need at `card` wide; `units` is each pile's width in cards. */
        fun sectionWidth(units: List<Float>, card: Float): Float =
            if (units.isEmpty()) 0f else 2 * padding + units.sum() * card + (units.size - 1) * spacing

        /** A section's piles in `count` rows, BattlefieldRow's split: the first row takes the extra pile. */
        fun rows(units: List<Float>, count: Int): List<List<Float>> {
            if (count <= 1 || units.size <= 1) return listOf(units)
            val first = (units.size + 1) / 2
            return listOf(units.take(first), units.drop(first))
        }

        /** The trailing section's width at `card` wide in `rows` rows. */
        fun trailingWidth(units: List<Float>, card: Float, rows: Int): Float = rows(units, rows).maxOfOrNull { sectionWidth(it, card) } ?: 0f

        /** Both sections fill their first row, then their second, side by side. A one-row fit narrower than `secondRowBelow`
         *  opens the second row instead. */
        fun fit(leading: List<Float>, trailing: List<Float>, width: Float, maxCard: Float, maxRows: Int = 1, secondRowBelow: Float = 0f): ArenaRowFit {
            val minCard = maxCard * minimumScale
            fun largestCard(count: Int): Float {
                var card = maxCard
                for (row in rows(leading, count)) for (side in rows(trailing, count)) {
                    val units = row.sum() + side.sum()
                    if (units <= 0f) continue
                    val fixed = sectionWidth(row, 0f) + sectionWidth(side, 0f) + if (row.isEmpty() || side.isEmpty()) 0f else sectionGap
                    card = min(card, (width - fixed) / units)
                }
                return card
            }
            val rowsAllowed = max(1, min(maxRows, max(leading.size, trailing.size)))
            for (count in 1..rowsAllowed) {
                val card = largestCard(count)
                if (card >= (if (count < rowsAllowed) max(secondRowBelow, minCard) else minCard)) {
                    return ArenaRowFit(card, count, trailingWidth(trailing, card, count), false)
                }
            }
            // Full at the smallest size: the trailing section keeps at most 40% of the row, and each section scrolls.
            val widest = if (trailing.isEmpty()) 0f else min(trailingWidth(trailing, minCard, rowsAllowed), width * 0.4f)
            return ArenaRowFit(minCard, rowsAllowed, widest, true)
        }
    }
}

/** Whether the hand is raised over the table, resting at its edge, or spread out whole (portrait, the tab at its left). */
enum class ArenaHandPosture {
    RAISED, RESTING, SPREAD;

    /** The reference game's hand (Caleb, 2026-10-20): it rests tucked along the bottom edge and steps aside for a decision. */
    data class Situation(val opened: Boolean = false, val spread: Boolean = false,
                         /** Paying a cost, choosing a target, declaring attackers or blockers, or answering a choice. */
                         val boardDecision: Boolean = false, val dragging: Boolean = false, val spectating: Boolean = false)

    companion object {
        fun resolve(situation: Situation): ArenaHandPosture = when {
            situation.spectating || situation.dragging || situation.boardDecision -> RESTING
            situation.spread -> SPREAD
            situation.opened -> RAISED
            else -> RESTING
        }
    }
}

/** One fan slot: where a hand card sits for a posture (design points; rotation in degrees). */
data class ArenaHandSlot(val center: BoardPoint, val rotation: Float, val scale: Float)

object ArenaHandFanLayout {
    /** The spread hand (Caleb, 2026-10-21): one flat row of whole cards, lined up, just over the rail; a wider hand swipes. */
    data class Spread(val count: Int, val scale: Float, val cardWidth: Float, val cardHeight: Float, val gap: Float,
                      /** Room above the row for the mana costs. */
                      val costRoom: Float, val bottom: Float, val centerX: Float) {
        val contentWidth: Float get() = count * cardWidth + max(count - 1, 0) * gap
        /** How far the row swipes: 0 when it fits. */
        val maxScroll: Float get() = max(0f, contentWidth - spreadWidth)
        /** The top of the row, its mana costs included. */
        val top: Float get() = bottom - cardHeight - costRoom
        val centerY: Float get() = bottom - cardHeight / 2

        fun centerX(index: Int, scroll: Float): Float {
            val start = if (maxScroll > 0) centerX - spreadWidth / 2 - scroll.coerceIn(0f, maxScroll) else centerX - contentWidth / 2
            return start + cardWidth / 2 + index * (cardWidth + gap)
        }
    }

    const val spreadWidth = 416f

    fun spread(count: Int, hand: ArenaLayout.Hand): Spread? {
        val bottom = hand.spreadBottom ?: return null
        if (count <= 0) return null
        val scale = 0.96f
        return Spread(count, scale, hand.card.width * scale, hand.card.height * scale, 8f, 20f, bottom, hand.centerX)
    }

    /** Card `index` of `count` in the given posture, in design points. */
    fun slot(index: Int, count: Int, posture: ArenaHandPosture, hand: ArenaLayout.Hand, scroll: Float = 0f): ArenaHandSlot {
        if (posture == ArenaHandPosture.SPREAD) {
            spread(count, hand)?.let { row -> return ArenaHandSlot(BoardPoint(row.centerX(index, scroll), row.centerY), 0f, row.scale) }
        }
        val raised = posture == ArenaHandPosture.RAISED
        val pitch = if (count > 1) (if (raised) min(hand.upPitch, hand.upSpan / (count - 1)) else min(hand.downPitch, hand.downSpan / (count - 1))) else 0f
        val offset = index - (count - 1) / 2f
        val x = hand.centerX + offset * pitch
        if (raised) {
            val tilt = (offset * hand.tilt).coerceIn(-hand.maxTilt, hand.maxTilt)
            // The arc flattens as the hand grows, and the whole fan rises until its outermost corner clears the floor.
            val edge = (count - 1) / 2f
            val drop = if (edge > 0) min(hand.upDrop, hand.maxDrop / (edge * edge)) else 0f
            val edgeTilt = Math.toRadians(min(hand.maxTilt, edge * hand.tilt).toDouble())
            val reach = drop * edge * edge + hand.card.height / 2 * cos(edgeTilt).toFloat() + hand.card.width / 2 * sin(edgeTilt).toFloat()
            val rise = max(0f, hand.upY + reach - hand.upFloor)
            return ArenaHandSlot(BoardPoint(x, hand.upY - rise + drop * offset * offset), tilt, 1f)
        }
        return ArenaHandSlot(BoardPoint(x, hand.downY + offset * offset * hand.downDrop), offset * 1.8f, hand.downScale)
    }
}

/**
 * Auto Pay for the Arena board: taps your mana sources one at a time until the cost is paid, the way the reference game's
 * Auto Pay button does. Each step sends the same `make_mana` a tap on the land sends, or spends floating mana with `play_mana`.
 */
object ArenaAutoPay {
    sealed class Step {
        /** `color`: the colour to name when the source makes a mana of any colour. */
        data class Tap(val actionID: String, val color: String? = null) : Step()
        data class Spend(val symbol: String) : Step()
        object Done : Step() { override fun toString() = "Done" }
        data class Blocked(val reason: String) : Step()
    }

    /** What a cost still needs, read from XMage's "Pay {2}{R}" text. */
    data class Need(var generic: Int = 0, val symbols: MutableMap<String, Int> = mutableMapOf(), val hybrids: MutableList<List<String>> = mutableListOf()) {
        val isEmpty: Boolean get() = generic == 0 && symbols.values.all { it <= 0 } && hybrids.isEmpty()
    }

    val colors = listOf("W", "U", "B", "R", "G")
    private val needPattern = Regex("""\{([0-9WUBRGCSXP/]+)\}""")
    private val symbolPattern = Regex("""\{([A-Z0-9]+)\}""")

    fun need(text: String): Need {
        val need = Need()
        for (match in needPattern.findAll(text)) {
            val token = match.groupValues[1].uppercase()
            val amount = token.toIntOrNull()
            when {
                amount != null -> need.generic += amount
                token == "S" -> need.generic += 1
                token == "X" -> {}
                token.contains("/") -> {
                    val parts = token.split("/")
                    val color = parts.firstOrNull { it in colors }
                    val two = parts.firstOrNull()?.toIntOrNull()
                    // Phyrexian ({R/P}) pays with its colour here; life payment stays a manual choice.
                    if ("P" in parts && color != null) need.symbols[color] = (need.symbols[color] ?: 0) + 1
                    // {2/W}: two generic or one white.
                    else if (two != null) need.hybrids += parts.filter { it in colors } + listOf("generic$two")
                    else need.hybrids += parts.filter { it in colors || it == "C" }
                }
                token in colors || token == "C" -> need.symbols[token] = (need.symbols[token] ?: 0) + 1
            }
        }
        return need
    }

    /** What one tap of a mana action produces: one symbol list per alternative, or any colour. Null when the ability costs
     *  more than a tap and sacrificing the source itself. */
    data class Production(val options: List<List<String>>, val anyColor: Boolean = false,
                          /** The source goes away to make it (a Treasure): spent only when nothing else can pay. */
                          val sacrifices: Boolean = false) {
        fun makes(symbol: String): Boolean = (anyColor && symbol in colors) || options.any { symbol in it }
        val amount: Int get() = if (anyColor) 1 else options.maxOfOrNull { it.size } ?: 0
        val colorCount: Int get() = if (anyColor) 5 else options.flatten().filter { it in colors }.toSet().size
        val colorlessOnly: Boolean get() = !anyColor && options.isNotEmpty() && options.all { option -> option.all { it == "C" } }
    }

    fun production(action: LegalAction): Production? {
        val label = action.label
        val addIndex = label.indexOf("Add", ignoreCase = true).takeIf { it >= 0 }
        var sacrifices = false
        if (addIndex != null) {
            val costPart = label.substring(0, addIndex)
            val colon = costPart.lastIndexOf(':')
            if (colon >= 0) {
                val cost = costPart.substring(0, colon).uppercase().replace(" ", "")
                val name = (action.cardName ?: "").uppercase().replace(" ", "")
                // A tap, a sacrifice of the source itself, or both; anything else is a cost the player chooses to pay.
                for (part in cost.split(",")) {
                    if (part == "{T}") continue
                    if (part.startsWith("SACRIFICE") && (part.startsWith("SACRIFICETHIS") || part == "SACRIFICEIT" || (name.isNotEmpty() && part == "SACRIFICE$name"))) {
                        sacrifices = true
                        continue
                    }
                    return null
                }
            }
        }
        val produced = action.producedMana?.map { it.uppercase() }
        if (!produced.isNullOrEmpty()) {
            // One symbol repeated is one ability making that much ({C}{C}); different symbols are alternatives.
            return Production(if (produced.toSet().size == 1) listOf(produced) else produced.map { listOf(it) }, sacrifices = sacrifices)
        }
        if (addIndex == null) return null
        val effect = label.substring(addIndex + 3)
        if (effect.contains("any color", true) || effect.contains("any colour", true)) return Production(emptyList(), anyColor = true, sacrifices = sacrifices)
        // Stop at the first sentence: reminder text and riders follow it.
        val clause = effect.split('.').firstOrNull { it.isNotEmpty() } ?: effect
        // "Add {W}, {B}, or {G}" is three choices of one mana each.
        val alternatives = clause.replace(", or ", "|").replace(" or ", "|").replace(",", "|").split("|")
        val options = alternatives.map { part -> symbols(part).filter { it in colors || it == "C" } }.filter { it.isNotEmpty() }
        if (options.isEmpty()) return null
        return Production(options, sacrifices = sacrifices)
    }

    private fun symbols(text: String): List<String> = symbolPattern.findAll(text.uppercase()).map { it.groupValues[1] }.toList()

    /** What kind of permanent a mana source is: a creature tapped for mana can't attack or block. */
    enum class SourceKind { LAND, CREATURE, OTHER }

    /** One permanent that can make mana now, and the ways it can (a dual land offers one action per colour). */
    data class Source(val key: String, val yields: MutableList<Yield>) {
        /** Its cheapest yield's cost: the order sources are tried in. */
        val cost: Int get() = yields.minOfOrNull { it.cost } ?: 0

        /** One way to tap it: the action to send, what it makes (`*` is a mana of any colour) and what it costs the plan. */
        data class Yield(val actionID: String, val symbols: List<String>, var cost: Int)
    }

    private val colourCost = listOf(0, 10, 14, 16, 16, 16)

    /** The order a payment spends sources in, as a cost: single-colour lands, then duals, then tri-lands and any-colour lands,
     *  then creatures, and a sacrifice (Treasure) only when nothing else will do. */
    fun sources(actions: List<LegalAction>, kinds: Map<String, SourceKind> = emptyMap()): List<Source> {
        val byKey = LinkedHashMap<String, Source>()
        for (action in actions) {
            if (action.type != "make_mana") continue
            val key = action.sourceInstanceId ?: action.cardInstanceId ?: continue
            val production = production(action) ?: continue
            var cost = if (production.anyColor) 18 else colourCost[min(production.colorCount, 5)]
            // Colourless-only sources pay generic before any coloured one, keeping colours open.
            if (production.colorlessOnly) cost = 9
            if (production.sacrifices) cost = 60
            if (kinds[key] == SourceKind.CREATURE) cost += 10
            val yields = if (production.anyColor) listOf(Source.Yield(action.id, listOf("*"), cost))
                else production.options.map { Source.Yield(action.id, it, cost) }
            val existing = byKey[key]
            if (existing != null) existing.yields += yields else byKey[key] = Source(key, yields.toMutableList())
        }
        // Several abilities on one permanent (a dual land's two colours) make it as flexible as their colours together.
        return byKey.values.map { source ->
            val taps = source.yields.filter { it.cost < 60 }
            val colorsMade = taps.flatMap { it.symbols }.filter { it in colors }.toSet().size
            if (taps.size > 1 && taps.none { "*" in it.symbols }) {
                val combined = colourCost[min(colorsMade, 5)] + if (kinds[source.key] == SourceKind.CREATURE) 10 else 0
                for (yield in source.yields) if (yield.cost < 60) yield.cost = max(yield.cost, combined)
            }
            source
        }
    }

    /** One planned tap: the permanent, the action and, for a mana of any colour, which colour to name. */
    data class PlannedTap(val key: String, val actionID: String, val color: String?)

    private class Pip(val accepts: List<String>, val generic: Int)
    private class Use(val yield: Int, val left: MutableList<String>) { fun copy() = Use(yield, left.toMutableList()) }
    private class Best(val cost: Int, val uses: Map<Int, Use>, val colors: Map<Int, String>, val order: List<Int>)

    /**
     * The cheapest way to pay the whole cost from these sources, or null when they can't. Coloured pips are matched first
     * (the most constrained first), hybrids take whichever half is cheaper, and generic takes what is left; taps for coloured
     * pips come first in the plan.
     */
    fun plan(need: Need, sources: List<Source>): List<PlannedTap>? {
        val pips = mutableListOf<Pip>()
        for ((symbol, count) in need.symbols.toSortedMap()) if (count > 0) repeat(count) { pips += Pip(listOf(symbol), 0) }
        for (hybrid in need.hybrids) {
            val generic = hybrid.firstNotNullOfOrNull { if (it.startsWith("generic")) it.drop(7).toIntOrNull() else null } ?: 0
            pips += Pip(hybrid.filter { !it.startsWith("generic") }, generic)
        }
        fun takes(symbol: String, pip: Pip) = if (symbol == "*") pip.accepts.any { it in colors } else symbol in pip.accepts
        fun accepts(yield: Source.Yield, pip: Pip) = yield.symbols.any { takes(it, pip) }
        val sortedPips = pips.sortedWith(compareBy<Pip>({ pip -> sources.count { source -> source.yields.any { accepts(it, pip) } } },
            { it.accepts.joinToString("") }))

        var best: Best? = null
        val uses = HashMap<Int, Use>()
        val named = HashMap<Int, String>()
        val order = mutableListOf<Int>()
        var nodes = 0

        fun spentCost(): Int = uses.entries.sumOf { (index, use) -> sources[index].yields[use.yield].cost }

        fun finish(extraGeneric: Int) {
            // Generic: leftover units first, then the cheapest fill of unused sources (small knapsack on units).
            val owed = need.generic + extraGeneric
            val leftover = uses.values.sumOf { it.left.size }
            var cost = spentCost()
            var fill: List<Pair<Int, Int>> = emptyList()
            if (owed > leftover) {
                val short = owed - leftover
                val unused = sources.indices.filter { uses[it] == null }
                val cap = short + 2
                var dp = arrayOfNulls<Pair<Int, List<Pair<Int, Int>>>>(cap + 1)
                dp[0] = 0 to emptyList()
                for (index in unused) {
                    val previous = dp.copyOf()
                    for ((yieldIndex, yield) in sources[index].yields.withIndex()) {
                        for (reached in 0..cap) {
                            val current = previous[reached] ?: continue
                            val next = min(cap, reached + max(1, yield.symbols.size))
                            val candidate = (current.first + yield.cost) to (current.second + (index to yieldIndex))
                            val existing = dp[next]
                            if (existing == null || candidate.first < existing.first) dp[next] = candidate
                        }
                    }
                }
                val pick = (short..cap).mapNotNull { reached -> dp[reached]?.let { reached to it } }
                    .minByOrNull { it.second.first + 3 * (it.first - short) } ?: return
                cost += pick.second.first + 3 * (pick.first - short)
                fill = pick.second.second
            } else {
                cost += 3 * (leftover - owed)
            }
            val current = best
            if (current == null || cost < current.cost) {
                val all = HashMap<Int, Use>()
                uses.forEach { (key, use) -> all[key] = use.copy() }
                for ((index, yield) in fill) all[index] = Use(yield, mutableListOf())
                best = Best(cost, all, HashMap(named), order.toList() + fill.map { it.first })
            }
        }

        fun assign(next: Int, extraGeneric: Int) {
            nodes += 1
            if (nodes > 40_000) return
            best?.let { if (spentCost() >= it.cost) return }
            if (next >= sortedPips.size) { finish(extraGeneric); return }
            val pip = sortedPips[next]
            // A unit left on a source already tapped costs nothing more.
            for (index in uses.keys.sorted()) {
                val use = uses[index] ?: continue
                val slot = use.left.indexOfFirst { takes(it, pip) }
                if (slot < 0) continue
                val unit = use.left.removeAt(slot)
                val before = named[index]
                if (unit == "*") pip.accepts.firstOrNull { it in colors }?.let { named[index] = it }
                assign(next + 1, extraGeneric)
                if (before == null) named.remove(index) else named[index] = before
                use.left.add(slot, unit)
            }
            // A new source: one of each identical kind is enough to try.
            val tried = HashSet<String>()
            for (index in sources.indices.sortedWith(compareBy({ sources[it].cost }, { it }))) {
                if (uses[index] != null) continue
                for ((yieldIndex, yield) in sources[index].yields.withIndex()) {
                    if (!accepts(yield, pip)) continue
                    val signature = sources[index].yields.joinToString(",") { "${it.cost}:" + it.symbols.joinToString("") } + "|$yieldIndex"
                    if (!tried.add(signature)) continue
                    val left = yield.symbols.toMutableList()
                    val slot = left.indexOfFirst { takes(it, pip) }
                    val unit = left.removeAt(slot)
                    uses[index] = Use(yieldIndex, left)
                    if (unit == "*") pip.accepts.firstOrNull { it in colors }?.let { named[index] = it }
                    order += index
                    assign(next + 1, extraGeneric)
                    order.removeAt(order.size - 1)
                    named.remove(index)
                    uses.remove(index)
                }
            }
            // {2/W}: pay its generic half instead.
            if (pip.generic > 0) assign(next + 1, extraGeneric + pip.generic)
        }

        assign(0, 0)
        val found = best ?: return null
        return found.order.map { index ->
            val source = sources[index]
            val yield = source.yields[found.uses[index]?.yield ?: 0]
            val color = if ("*" in yield.symbols) found.colors[index] ?: colors.first() else null
            PlannedTap(source.key, yield.actionID, color)
        }
    }

    /** The next Auto Pay step for a cost: floating mana first, then the first tap of the cheapest plan that pays it all. */
    fun next(remainingText: String, floating: Map<String, Int>, actions: List<LegalAction>, kinds: Map<String, SourceKind> = emptyMap()): Step {
        val need = need(remainingText)
        if (need.isEmpty) return Step.Done
        // Floating mana first: it empties at the end of the step anyway.
        for ((symbol, count) in need.symbols.toSortedMap()) if (count > 0 && (floating[symbol] ?: 0) > 0) return Step.Spend(symbol)
        for (hybrid in need.hybrids) hybrid.firstOrNull { (floating[it] ?: 0) > 0 }?.let { return Step.Spend(it) }
        if (need.generic > 0) {
            // Generic takes floating mana that no coloured pip still wants, the most plentiful first.
            val surplus = floating.map { it.key to it.value - (need.symbols[it.key] ?: 0) }.filter { it.second > 0 }
            surplus.sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { it.first }).firstOrNull()?.let { return Step.Spend(it.first) }
        }
        val sources = sources(actions, kinds)
        val first = plan(need, sources)?.firstOrNull()
        if (first == null) {
            // Say what is short: a colour no source makes, or just not enough mana.
            val owed = need.generic + need.symbols.values.sum() + need.hybrids.size
            if (sources.size < owed) return Step.Blocked("Not enough untapped mana for this cost")
            val missing = need.symbols.keys.sorted().firstOrNull { symbol ->
                sources.none { source -> source.yields.any { symbol in it.symbols || ("*" in it.symbols && symbol in colors) } }
            }
            if (missing != null) return Step.Blocked("No untapped source makes {$missing}")
            return Step.Blocked("Your untapped mana can't pay this cost")
        }
        return Step.Tap(first.actionID, first.color)
    }

    /** The next Auto Pay step for the cost being paid in this snapshot: XMage's remaining-cost text, the floating mana its
     *  payment prompt offers, and the mana sources it lists as legal. */
    fun next(snapshot: GameSnapshot): Step {
        if (snapshot.manaPayment?.active != true && snapshot.promptEnvelopeV2?.responseKind?.lowercase() != "mana") return Step.Done
        val remaining = snapshot.manaPayment?.remainingText ?: snapshot.promptEnvelopeV2?.message ?: ""
        val floating = HashMap<String, Int>()
        for (choice in snapshot.promptEnvelopeV2?.manaChoices ?: emptyList()) {
            val key = choice.manaType ?: choice.id
            floating[key] = (floating[key] ?: 0) + (choice.amount ?: 0)
        }
        return next(remaining, floating, snapshot.legalActions ?: emptyList(), sourceKinds(snapshot))
    }

    /** Lands, creatures and other permanents on the battlefield, by instance id. */
    fun sourceKinds(snapshot: GameSnapshot): Map<String, SourceKind> =
        snapshot.players.flatMap { it.zones.battlefield }.associate {
            it.instanceId to if (it.isCreature) SourceKind.CREATURE else if (it.card.isLand) SourceKind.LAND else SourceKind.OTHER
        }
}

/** Which combat declaration the table is asking you for: the on-device engine asks it as a target prompt in the declare
 *  steps (tap a creature to toggle it, then Done); the gateway sent declare_attackers / declare_blockers actions. */
enum class ArenaCombatPhase {
    ATTACKERS, BLOCKERS;

    companion object {
        fun current(snapshot: GameSnapshot): ArenaCombatPhase? {
            val actions = snapshot.legalActions ?: emptyList()
            if (actions.any { it.type == "declare_attackers" }) return ATTACKERS
            if (actions.any { it.type == "declare_blockers" }) return BLOCKERS
            val prompt = snapshot.promptEnvelopeV2 ?: return null
            if (!snapshot.isViewer(prompt.playerId)) return null
            if (prompt.responseKind.lowercase() != "target" && prompt.responseCommand?.type?.lowercase() != "choose_target") return null
            val step = (snapshot.step ?: snapshot.phase).lowercase().replace("_", "-")
            if (step.contains("declare-attack")) return ATTACKERS
            if (step.contains("declare-block")) return BLOCKERS
            return null
        }
    }
}

/** Cards you can play from somewhere other than your hand (flashback, impulse draws, adventures in exile): the reference
 *  shows them just right of your hand, shimmering, though they stay in their zone. */
object ArenaExtraHand {
    fun cards(player: PlayerGameState, actions: List<LegalAction>): List<ZoneCard> {
        val playable = actions.filter { it.type == "cast_spell" || it.type == "play_land" }.mapNotNull { it.cardInstanceId ?: it.sourceInstanceId }.toSet()
        if (playable.isEmpty()) return emptyList()
        return (player.zones.graveyard + player.zones.exile).filter { it.instanceId in playable || it.id in playable }
    }
}

/** XMage's named choices, read for the Arena choice browser: "Remember answer: X" pairs with its X, and "Name: text" splits
 *  into the card it names and that card's text. */
object ArenaChoiceList {
    data class Option(val id: String, val rememberID: String?, val label: String, val name: String?, val text: String)

    const val rememberPrefix = "Remember answer: "
    private val trailingId = Regex("""\s*\[[^\]]*\]\s*$""")

    fun options(choices: List<Pair<String, String>>): List<Option> {
        val remembered = LinkedHashMap<String, String>()
        for ((id, label) in choices) if (label.startsWith(rememberPrefix)) remembered.putIfAbsent(label.drop(rememberPrefix.length), id)
        return choices.filter { !it.second.startsWith(rememberPrefix) }.map { (id, label) ->
            var name: String? = null
            var text = label
            val colon = label.indexOf(": ")
            if (colon in 0..40) {
                // XMage names a card with its id: "Doubling Season [8f2]".
                name = label.substring(0, colon).replace(trailingId, "")
                text = label.substring(colon + 2)
            }
            Option(id, remembered[label], label, name, text)
        }
    }

    /** "White" or "Red mana" as its mana symbol, for colour choices. */
    fun colorSymbol(label: String): String? {
        val names = mapOf("white" to "W", "blue" to "U", "black" to "B", "red" to "R", "green" to "G", "colorless" to "C", "colourless" to "C")
        return names[label.lowercase().replace(" mana", "").trim()]
    }
}

/** A planeswalker ability's loyalty cost, as the reference shows it on a badge: "+1: Create a…" is +1 and its text. */
object ArenaLoyalty {
    private val pattern = Regex("""^\s*([+−-]?\s*(?:\d+|X))\s*:\s*""")
    fun split(text: String): Pair<String, String>? {
        val match = pattern.find(text) ?: return null
        val cost = match.value.replace(":", "").replace(" ", "").replace("-", "−").trim()
        return cost to text.substring(match.range.last + 1)
    }
}

/** The values the Arena's amount pill steps through: XMage's list when it gives one, else its minimum to maximum. */
class ArenaAmountRange(amounts: List<Int>?, minimum: Int?, maximum: Int?) {
    val values: List<Int> = if (!amounts.isNullOrEmpty()) amounts.toSet().sorted() else {
        // XMage's own bounds (negative ones too); an open maximum stops 99 above the minimum.
        val low = minimum ?: 0
        val high = max(low, min(maximum ?: (low + 99), low + 999))
        (low..high).toList()
    }

    val minimum: Int get() = values.firstOrNull() ?: 0
    val maximum: Int get() = values.lastOrNull() ?: 0

    /** `places` places along the allowed values, held at the ends. */
    fun step(value: Int, places: Int): Int {
        val index = values.indexOf(value).takeIf { it >= 0 } ?: values.indexOfFirst { it >= value }.takeIf { it >= 0 } ?: 0
        return values[(index + places).coerceIn(0, values.size - 1)]
    }

    /** The nearest allowed value. */
    fun clamp(value: Int): Int = values.minByOrNull { abs(it - value) } ?: value

    companion object {
        /** The largest X the mana you have can pay: `sources` mana available, `cost` the spell's mana cost with its X. */
        fun affordableX(cost: String, sources: Int): Int? {
            val symbols = cost.uppercase().split('{', '}').filter { it.isNotEmpty() }
            val xs = symbols.count { it == "X" }
            if (xs == 0) return null
            val fixed = symbols.sumOf { symbol -> if (symbol == "X") 0 else symbol.toIntOrNull() ?: 1 }
            return max(0, (sources - fixed) / xs)
        }
    }
}

/** Rows of a damage, counter or mana split, read for the Arena split browser. */
object ArenaSplit {
    private val trailingId = Regex("""\s*\[[^\]]*\]\s*$""")

    /** "Grizzly Bears, P/T: 2/2" or "Grizzly Bears [8f2]" is Grizzly Bears. */
    fun name(label: String): String {
        var name = label
        val pt = name.indexOf(", P/T:")
        if (pt >= 0) name = name.substring(0, pt)
        return name.replace(trailingId, "").trim()
    }

    /** Damage that destroys a creature: what's left of its toughness, or 1 from a source with deathtouch. */
    fun lethal(toughness: Int, damage: Int, deathtouch: Boolean): Int = if (deathtouch) 1 else max(1, toughness - damage)
}

/** The reference's keyword glossary beside an inspected card: what each keyword on it means, in a sentence. */
object ArenaKeywordGlossary {
    val entries: List<Pair<String, String>> = listOf(
        "Flying" to "Can be blocked only by creatures with flying or reach.",
        "Reach" to "Can block creatures with flying.",
        "Trample" to "Combat damage beyond what its blockers need goes on to the player or planeswalker it's attacking.",
        "Deathtouch" to "Any damage it deals to a creature is enough to destroy it.",
        "Lifelink" to "Damage it deals also gains its controller that much life.",
        "Vigilance" to "Attacking doesn't tap it.",
        "Haste" to "It can attack and use tap abilities the turn it comes under your control.",
        "First strike" to "Deals combat damage before creatures without first strike.",
        "Double strike" to "Deals both first-strike and regular combat damage.",
        "Menace" to "Can't be blocked except by two or more creatures.",
        "Hexproof" to "Can't be the target of spells or abilities your opponents control.",
        "Shroud" to "Can't be the target of any spell or ability.",
        "Indestructible" to "Damage and \"destroy\" effects don't destroy it.",
        "Defender" to "Can't attack.",
        "Flash" to "You may cast it any time you could cast an instant.",
        "Ward" to "When it becomes the target of an opponent's spell or ability, that player pays the ward cost or it's countered.",
        "Prowess" to "Whenever you cast a noncreature spell, it gets +1/+1 until end of turn.",
        "Flashback" to "You may cast this card from your graveyard for its flashback cost. Then it's exiled.",
        "Kicker" to "You may pay an extra cost as you cast it for an extra effect.",
        "Cycling" to "Pay its cycling cost and discard it to draw a card.",
        "Equip" to "Attach it to a creature you control, any time you could cast a sorcery.",
        "Toxic" to "Players it deals combat damage to also get that many poison counters.",
        "Infect" to "Deals damage to creatures as -1/-1 counters and to players as poison counters.",
        "Persist" to "When it dies without a -1/-1 counter, it returns with one.",
        "Undying" to "When it dies without a +1/+1 counter, it returns with one.",
        "Convoke" to "Your creatures can help cast it: each one you tap pays for {1} or one mana of its colour.",
        "Cascade" to "When you cast it, reveal cards until a cheaper nonland card; you may cast that card free.",
        "Storm" to "When you cast it, copy it for each spell cast before it this turn.",
        "Changeling" to "It is every creature type.",
        "Protection" to "Can't be blocked, targeted, damaged, enchanted or equipped by anything with that quality.",
        "Treasure" to "A token artifact: tap and sacrifice it to add one mana of any colour.",
        "Food" to "A token artifact: pay {2}, tap and sacrifice it to gain 3 life.",
        "Clue" to "A token artifact: pay {2} and sacrifice it to draw a card.",
    )

    /** The keywords a card's rules mention, in the order they first appear, at most `limit`. */
    fun entries(rules: String, limit: Int = 4): List<Pair<String, String>> {
        val text = rules.lowercase()
        return entries.mapNotNull { entry ->
            val match = Regex("\\b" + Regex.escape(entry.first.lowercase()) + "\\b").find(text) ?: return@mapNotNull null
            match.range.first to entry
        }.sortedBy { it.first }.map { it.second }.take(limit)
    }
}

/**
 * Your commander on an opponent's battlefield (Caleb, 2026-10-21: Necromantic Selection took Chatterfang). XMage moves a dead
 * commander home as a state-based action, after the spell that killed it has finished, so a spell that destroys and then
 * returns creatures can take it first. The board names who has it and explains.
 */
object ArenaCommanderSteal {
    /** "Name|holder id" for each of your commanders an opponent controls now. */
    fun taken(snapshot: GameSnapshot): List<String> {
        val viewer = snapshot.players.firstOrNull { snapshot.isViewer(it.playerId) } ?: return emptyList()
        val names = (viewer.commanders ?: emptyList()).mapNotNull { it.name }.filter { it.isNotEmpty() }.toSet()
        if (names.isEmpty()) return emptyList()
        return snapshot.players.filter { !snapshot.isViewer(it.playerId) }.flatMap { player ->
            player.zones.battlefield.filter { it.card.name in names }.map { "${it.card.name}|${player.playerId}" }
        }.sorted()
    }

    /** The notice for a commander that has just been taken. */
    fun notice(entry: String, snapshot: GameSnapshot): String {
        val parts = entry.split("|", limit = 2)
        val name = parts.firstOrNull() ?: "Your commander"
        val holder = if (parts.size > 1) snapshot.playerLabel(parts[1]) else "An opponent"
        return "$holder took $name. A commander goes to the command zone only after the spell that moved it finishes, so that spell could take it first."
    }
}

/** A board wipe's recap for the caption: the spell that just resolved and what left the battlefield because of it, three or
 *  more at once (Caleb, 2026-10-21: a wipe went by too fast to see what it took). */
object ArenaSweepRecap {
    /** BoardFXScheduler.sweepMinimum on iOS: three or more leaving at once is a wipe. */
    const val sweepMinimum = 3

    fun text(spell: String?, events: List<BoardFXEvent>): String? {
        var graveyard = 0; var exile = 0; var other = 0
        for (event in events) {
            if (event !is BoardFXEvent.LeftBattlefield) continue
            when (event.to) {
                BoardFXZone.GRAVEYARD -> graveyard += 1
                BoardFXZone.EXILE -> exile += 1
                else -> other += 1
            }
        }
        if (graveyard + exile + other < sweepMinimum) return null
        val what = listOfNotNull(if (graveyard > 0) "$graveyard to the graveyard" else null, if (exile > 0) "$exile exiled" else null,
            if (other > 0) "$other returned or moved" else null).joinToString(", ")
        return spell?.let { "$it: $what" } ?: "${graveyard + exile + other} permanents left the battlefield: $what"
    }
}
