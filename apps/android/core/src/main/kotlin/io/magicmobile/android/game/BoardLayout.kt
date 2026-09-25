package io.magicmobile.android.game

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Board geometry in density-independent points (iOS points = Android dp). Ports of
 * BattlefieldViewportMetrics.swift and the layout helpers in ArenaBoardPresentation.swift,
 * so both apps place every lane, card and control at the same coordinates.
 */
data class BoardPoint(val x: Float, val y: Float)
data class BoardSize(val width: Float, val height: Float)
data class BoardInsets(val top: Float = 0f, val leading: Float = 0f, val bottom: Float = 0f, val trailing: Float = 0f)

data class BoardRect(val x: Float, val y: Float, val width: Float, val height: Float) {
    val minX get() = x
    val minY get() = y
    val maxX get() = x + width
    val maxY get() = y + height
    val midX get() = x + width / 2
    val midY get() = y + height / 2
    val isEmpty get() = width <= 0f || height <= 0f
    fun contains(other: BoardRect): Boolean = !other.isEmpty && other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    fun contains(point: BoardPoint): Boolean = point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    companion object { val zero = BoardRect(0f, 0f, 0f, 0f) }
}

class BattlefieldLayoutMetrics(val size: BoardSize, val safeArea: BoardInsets = BoardInsets(), val centerControlsVisible: Boolean = true) {
    companion object { const val magicCardHeightToWidth = 88f / 63f }

    val safeFrame: BoardRect get() {
        val margin = 10f
        return BoardRect(safeArea.leading + margin, safeArea.top + 8,
            maxOf(size.width - safeArea.leading - safeArea.trailing - margin * 2, 320f),
            maxOf(size.height - safeArea.top - safeArea.bottom - 8, 300f))
    }
    val topStatusRect get() = BoardRect(safeFrame.minX, safeFrame.minY, safeFrame.width, 40f)
    val rightDockRect: BoardRect get() {
        val width = minOf(maxOf(safeFrame.width * 0.20f, 210f), 268f)
        val top = topStatusRect.maxY + 8
        return BoardRect(safeFrame.maxX - width, top, width, maxOf(safeFrame.maxY - top, 220f))
    }
    val boardColumnRect: BoardRect get() {
        val top = safeFrame.minY
        return BoardRect(safeFrame.minX, top, maxOf(safeFrame.maxX - safeFrame.minX, 320f), maxOf(safeFrame.maxY - top, 260f))
    }
    val handRect get() = BoardRect(boardColumnRect.minX, boardColumnRect.maxY - handFrameHeight, boardColumnRect.width, handFrameHeight)
    val opponentBattlefieldRect get() = laneRects[0]
    val opponentLandsRect get() = laneRects[1]
    val centerStripRect get() = laneRects[2]
    val playerBattlefieldRect get() = laneRects[3]
    val playerLandsRect get() = laneRects[4]
    val bottomActionRect: BoardRect get() {
        val width = minOf(maxOf(boardColumnRect.width * 0.58f, 320f), 460f)
        val height = 38f
        return BoardRect(boardColumnRect.midX - width / 2, handRect.minY - height - 8, width, height)
    }
    val compactPromptRect: BoardRect get() {
        val width = minOf(maxOf(boardColumnRect.width * 0.30f, 260f), 340f)
        val height = minOf(maxOf(size.height * 0.20f, 98f), 178f)
        return BoardRect(boardColumnRect.midX - width / 2, maxOf(centerStripRect.maxY + 6, playerBattlefieldRect.minY + 3), width, height)
    }
    val detailSheetRect: BoardRect get() {
        val width = minOf(safeFrame.width, 560f)
        val height = safeFrame.height - 12
        return BoardRect(safeFrame.midX - width / 2, safeFrame.midY - height / 2, width, height)
    }
    val playerDropZone get() = playerPlayAreaRect
    val playerPlayAreaRect get() = BoardRect(boardColumnRect.minX, playerBattlefieldRect.minY - 6, boardColumnRect.width,
        playerLandsRect.maxY - playerBattlefieldRect.minY + 14)
    val handCardWidth: Float get() {
        val horizontalFit = boardColumnRect.width / 7.7f
        val verticalScale = if (safeFrame.height < 360) 0.24f else 0.30f
        val verticalFit = maxOf((safeFrame.height * verticalScale) / magicCardHeightToWidth, 58f)
        val minimumWidth = if (boardColumnRect.width < 540) 60f else 68f
        return minOf(maxOf(horizontalFit, minimumWidth), minOf(verticalFit, 90f))
    }
    val handCardHeight get() = handCardWidth * magicCardHeightToWidth
    val handFrameHeight get() = ArenaHandLayout.restingHeight(handCardHeight)
    val permanentCardWidth get() = minOf(88f, maxOf(44f, (opponentBattlefieldRect.height - 12) / 1.08f))
    val permanentCardHeight get() = permanentCardWidth * 1.08f
    val landCardWidth get() = minOf(48f, permanentCardWidth)
    val landCardHeight get() = landCardWidth * 1.08f

    private val battlefieldRect: BoardRect get() {
        val top = boardColumnRect.minY + 2
        val bottom = handRect.minY - 4
        return BoardRect(boardColumnRect.minX, top, boardColumnRect.width, maxOf(bottom - top, 190f))
    }
    private val centerStripHeight get() = if (centerControlsVisible) 56f else 0f
    private val laneRects: List<BoardRect> get() {
        // Lands share each player's row, leaving vertical space for readable cards and hand.
        val b = battlefieldRect
        val rowHeight = maxOf((b.height - centerStripHeight - 12) / 2, 44f)
        val landWidth = b.width * 0.32f
        val creatureWidth = b.width - landWidth - 10
        val top = b.minY
        val centerY = top + rowHeight + 6
        val playerY = centerY + centerStripHeight + 6
        fun creatures(y: Float) = BoardRect(b.minX, y, creatureWidth, rowHeight)
        fun lands(y: Float) = BoardRect(b.maxX - landWidth, y, landWidth, rowHeight)
        return listOf(creatures(top), lands(top), BoardRect(b.minX, centerY, b.width, centerStripHeight), creatures(playerY), lands(playerY))
    }
}

class PortraitBattlefieldLayoutMetrics(val size: BoardSize, val safeArea: BoardInsets = BoardInsets(), val paymentActive: Boolean = false,
                                       val largeText: Boolean = false, val centerControlsVisible: Boolean = true) {
    companion object { const val magicCardHeightToWidth = BattlefieldLayoutMetrics.magicCardHeightToWidth }

    val centerStripHeight get() = if (paymentActive) 60f else if (centerControlsVisible) 36f else 0f
    val safeFrame: BoardRect get() {
        val margin = 8f
        return BoardRect(safeArea.leading + margin, safeArea.top + 8,
            maxOf(size.width - safeArea.leading - safeArea.trailing - margin * 2, 300f),
            maxOf(size.height - safeArea.top - safeArea.bottom - 16, 0f))
    }
    val topHUDRect get() = BoardRect(safeFrame.minX, safeFrame.minY, safeFrame.width, if (largeText) 84f else 54f)
    val opponentBattlefieldRect get() = BoardRect(safeFrame.minX + 10, topHUDRect.maxY + 10, creatureLaneWidth, permanentGroupHeight)
    val opponentLandsRect: BoardRect get() = if (usesCompactLanes) {
        BoardRect(opponentBattlefieldRect.maxX + 8, opponentBattlefieldRect.minY, safeFrame.maxX - 10 - opponentBattlefieldRect.maxX - 8, permanentGroupHeight)
    } else BoardRect(safeFrame.minX + 10, opponentBattlefieldRect.maxY + 5, safeFrame.width - 20, landCardHeight + 8)
    val centerStripRect get() = BoardRect(safeFrame.minX + 8, opponentLandsRect.maxY + 10, safeFrame.width - 16, centerStripHeight)
    val playerBattlefieldRect get() = BoardRect(safeFrame.minX + 10, centerStripRect.maxY + 10, creatureLaneWidth, permanentGroupHeight)
    val playerLandsRect: BoardRect get() = if (usesCompactLanes) {
        BoardRect(playerBattlefieldRect.maxX + 8, playerBattlefieldRect.minY, safeFrame.maxX - 10 - playerBattlefieldRect.maxX - 8, permanentGroupHeight)
    } else BoardRect(safeFrame.minX + 10, playerBattlefieldRect.maxY + 5, safeFrame.width - 20, landCardHeight + 8)
    val bottomControlsRect: BoardRect get() {
        val height = 110f
        return BoardRect(safeFrame.minX, safeFrame.maxY - height, safeFrame.width, height)
    }
    val handRect: BoardRect get() {
        val top = playerLandsRect.maxY + 8
        val bottom = bottomControlsRect.minY - 8
        return BoardRect(safeFrame.minX, top, safeFrame.width, maxOf(bottom - top, 0f))
    }
    val bottomHUDRect get() = BoardRect(bottomControlsRect.minX, bottomControlsRect.minY,
        minOf(maxOf(bottomControlsRect.width * 0.34f, 132f), 146f), bottomControlsRect.height)
    val stackPanelRect: BoardRect get() {
        val width = minOf(maxOf(bottomControlsRect.width * 0.28f, 108f), 126f)
        return BoardRect(bottomControlsRect.maxX - width - 8, bottomControlsRect.minY + 8, width, bottomControlsRect.height - 16)
    }
    val bottomActionPanelRect: BoardRect get() {
        val x = bottomHUDRect.maxX + 10
        return BoardRect(x, bottomControlsRect.minY + 8, maxOf(stackPanelRect.minX - x - 10, 118f), bottomControlsRect.height - 16)
    }
    val passButtonRect get() = BoardRect(bottomActionPanelRect.minX, bottomActionPanelRect.minY + 18, bottomActionPanelRect.width, 44f)
    val skipButtonRect get() = BoardRect(passButtonRect.minX, passButtonRect.maxY + 10, passButtonRect.width, 34f)
    val bottomNavRect get() = BoardRect(bottomActionPanelRect.minX, skipButtonRect.maxY + 6, bottomActionPanelRect.width,
        maxOf(bottomActionPanelRect.maxY - skipButtonRect.maxY - 6, 34f))
    val settingsButtonRect get() = BoardRect(bottomNavRect.minX, bottomNavRect.midY - 17, 34f, 34f)
    val handScrubberRect get() = BoardRect(handRect.minX + 24, handRect.maxY - 12, maxOf(handRect.width - 48, 120f), 8f)
    val compactPromptRect get() = BoardRect(safeFrame.minX + 16, safeFrame.midY - 95, safeFrame.width - 32, 190f)
    val detailSheetRect get() = BoardRect(safeFrame.minX + 18, safeFrame.midY - minOf(safeFrame.height * 0.38f, 290f),
        safeFrame.width - 36, minOf(safeFrame.height * 0.76f, 580f))
    val playerPlayAreaRect get() = BoardRect(safeFrame.minX, playerBattlefieldRect.minY - 8, safeFrame.width,
        playerLandsRect.maxY - playerBattlefieldRect.minY + 16)
    val playerDropZone get() = playerPlayAreaRect
    val permanentCardWidth get() = minOf(92f, maxOf(50f, (permanentGroupHeight - 12) / 1.08f))
    val permanentCardHeight get() = permanentCardWidth * 1.08f
    val permanentRowHeight get() = permanentCardHeight + 8
    val permanentGroupHeight: Float get() = maxOf(80f, (safeFrame.height - topHUDRect.height - bottomControlsRect.height -
        ArenaHandLayout.restingHeight(handCardHeight) - 6 - centerStripHeight - (if (usesCompactLanes) 0f else 2 * (landCardHeight + 8)) - 56) / 2)
    /** Short phones put lands beside permanents to preserve a readable hand. */
    val usesCompactLanes: Boolean get() = safeFrame.height < topHUDRect.height + bottomControlsRect.height + handCardHeight + 36 +
        centerStripHeight + 2 * (landCardHeight + 8) + 56 + 160
    private val creatureLaneWidth get() = (safeFrame.width - 20) * (if (usesCompactLanes) 0.68f else 1f)
    val landCardWidth get() = 45f
    val landCardHeight get() = landCardWidth * 1.08f
    val handCardWidth get() = minOf(maxOf(safeFrame.width / 4.8f, 78f), 88f)
    val handCardHeight get() = handCardWidth * magicCardHeightToWidth
}

/** Attachment relationships come only from the current public engine snapshot. */
object BattlefieldAttachments {
    private val manaEffect = Regex("^\\s*add\\s+(?:\\{[cwubrg]\\}|(?:one|two|three|\\d+) mana)", RegexOption.IGNORE_CASE)

    fun isManaRock(card: ZoneCard): Boolean {
        if (!card.card.isArtifact || card.isCreature || card.card.isLand) return false
        val rules = card.card.oracleText ?: return false
        // Match an activated cost and an explicit mana effect, not incidental "add" text.
        return rules.split("\n").any { line ->
            val parts = line.split(":", limit = 2)
            if (parts.size != 2) return@any false
            val cost = parts[0].trim().lowercase()
            if (cost.startsWith("when ") || cost.startsWith("whenever ") || cost.startsWith("at ") ||
                !(cost.contains("{t}") || cost.contains("sacrifice") || cost.startsWith("tap "))) return@any false
            manaEffect.containsMatchIn(parts[1])
        }
    }

    fun isSupport(card: ZoneCard): Boolean = !card.isCreature && !card.card.isPlaneswalker &&
        !card.card.typeLine.contains("battle", ignoreCase = true) && !card.card.typeLine.contains("equipment", ignoreCase = true)

    fun roots(cards: List<ZoneCard>): Map<String, String> {
        val byID = LinkedHashMap<String, ZoneCard>()
        cards.forEach { byID.putIfAbsent(it.instanceId, it) }
        val result = LinkedHashMap<String, String>()
        for (card in cards) {
            if (result.containsKey(card.instanceId)) continue
            var current = card.instanceId
            val seen = mutableSetOf<String>()
            var root: String = card.instanceId
            while (true) {
                val parent = byID[current]?.attachedToInstanceId
                if (parent == null || byID[parent] == null) { root = current; break }
                if (!seen.add(current) || seen.contains(parent)) { root = card.instanceId; break }
                current = parent
            }
            result[card.instanceId] = root
        }
        return result
    }

    fun lane(ownedCards: List<ZoneCard>, allCards: List<ZoneCard>, lands: Boolean, playerIDs: Set<String> = emptySet(),
             includesManaRocks: Boolean = false): List<ZoneCard> {
        val roots = roots(allCards)
        val laneRoots = ownedCards.filter {
            (it.card.isLand || (includesManaRocks && isManaRock(it))) == lands && roots[it.instanceId] == it.instanceId &&
                !playerIDs.contains(it.attachedToInstanceId ?: "")
        }.map { it.instanceId }.toSet()
        return allCards.filter { laneRoots.contains(roots[it.instanceId] ?: it.instanceId) }
    }

    fun groups(cards: List<ZoneCard>): List<BattlefieldCardGroup> {
        val roots = roots(cards)
        val hostIDs = cards.mapNotNull { card -> roots[card.instanceId]?.takeIf { it != card.instanceId } }.toSet()
        val unattached = cards.filter { !hostIDs.contains(roots[it.instanceId] ?: it.instanceId) }
        val densityGroups = BattlefieldDensityPlanner.groups(unattached).toMutableList()
        val result = mutableListOf<BattlefieldCardGroup>()
        for (card in cards) {
            if (hostIDs.contains(card.instanceId)) {
                val children = cards.filter { it.instanceId != card.instanceId && roots[it.instanceId] == card.instanceId }
                result += BattlefieldCardGroup("attachment:" + card.instanceId, listOf(card) + children)
            } else {
                val index = densityGroups.indexOfFirst { it.cards.contains(card) }
                if (index >= 0) result += densityGroups.removeAt(index)
            }
        }
        return result
    }

    fun enchanting(playerID: String, allCards: List<ZoneCard>): List<ZoneCard> = ZoneCard.enchanting(playerID, allCards)
}

enum class BattlefieldRowArrangement {
    AUTOMATIC, LANDSCAPE_RESOURCES, PORTRAIT_PERMANENTS;

    fun rows(groups: List<BattlefieldCardGroup>, flipped: Boolean, twoRows: Boolean): List<List<BattlefieldCardGroup>> {
        if (!twoRows) return listOf(groups)
        fun halves(values: List<BattlefieldCardGroup>): List<List<BattlefieldCardGroup>> {
            val midpoint = (values.size + 1) / 2
            return listOf(values.take(midpoint), values.drop(midpoint))
        }
        return when (this) {
            AUTOMATIC -> halves(groups)
            LANDSCAPE_RESOURCES -> {
                val lands = groups.filter { it.representative.card.isLand }
                val rocks = groups.filter { !it.representative.card.isLand }
                if (rocks.isNotEmpty()) listOf(lands, rocks) else halves(lands)
            }
            PORTRAIT_PERMANENTS -> {
                val foreground = groups.filter { !BattlefieldAttachments.isSupport(it.representative) }
                val background = groups.filter { BattlefieldAttachments.isSupport(it.representative) }
                if (foreground.isEmpty() || background.isEmpty()) halves(groups)
                else if (flipped) listOf(background, foreground) else listOf(foreground, background)
            }
        }
    }
}

object BoardPlayerStatus {
    fun counters(player: PlayerGameState): List<Pair<String, Int>> {
        val values = (player.counters ?: emptyMap()).toMutableMap()
        if (player.poison > 0 && values.keys.none { it.lowercase() == "poison" }) values["Poison"] = player.poison
        return values.filter { it.value > 0 }.entries.sortedWith { left, right ->
            val l = left.key.lowercase() == "poison"; val r = right.key.lowercase() == "poison"
            when {
                l && !r -> -1
                r && !l -> 1
                l && r -> 0
                else -> left.key.compareTo(right.key)
            }
        }.map { it.key to it.value }
    }
}

/** Priority is a response opportunity inside a real phase/step, not a new phase. */
data class BoardResponseCue(val title: String, val detail: String) {
    companion object {
        fun make(snapshot: GameSnapshot): BoardResponseCue? {
            if (snapshot.isCompleted || !snapshot.isViewer(snapshot.priorityPlayerId)) return null
            val prompt = snapshot.promptEnvelopeV2 ?: return null
            if (!snapshot.isViewer(prompt.playerId) || !(prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority")) return null
            val rawStep = snapshot.step ?: snapshot.phase
            val step = EngineDisplayText.phaseLabel(rawStep)
            val waiting = snapshot.stackTopFirst.isNotEmpty() || snapshot.players.any { it.zones.stack.isNotEmpty() }
            val normalized = rawStep.uppercase().filter { it.isLetterOrDigit() }
            val mainPhase = normalized in setOf("PRECOMBATMAIN", "POSTCOMBATMAIN", "MAIN1", "MAIN2")
            if (!waiting && snapshot.isViewer(snapshot.activePlayerId) && mainPhase) return null
            return BoardResponseCue(if (waiting) "Respond to the stack" else "Your response window", step)
        }
    }
}

/** A second permanent row is used only when both rows retain 44-point targets. */
class ArenaPermanentLayout private constructor(val rows: Int, val columns: Int, val cardWidth: Float, val cardHeight: Float, val contentWidth: Float) {
    companion object {
        fun of(count: Int, width: Float, height: Float, maxCardWidth: Float, ratio: Float): ArenaPermanentLayout =
            of(if (count > 5) listOf((count + 1) / 2, count / 2) else listOf(count), width, height, maxCardWidth, ratio)

        fun of(rowCounts: List<Int>, width: Float, height: Float, maxCardWidth: Float, ratio: Float): ArenaPermanentLayout {
            val r = maxOf(ratio, 1f)
            val rows = if (rowCounts.size > 1 && height >= 2 * 44 * r + 20) 2 else 1
            val columns = maxOf(1, if (rows == 2) rowCounts.maxOrNull() ?: 0 else rowCounts.sum())
            val heightFit = (height - 16 - (rows - 1) * 4) / rows / r
            val visibleColumns = minOf(5, columns).toFloat()
            val widthFit = (width - 16 - (visibleColumns - 1) * 4) / visibleColumns
            val cardWidth = maxOf(44f, minOf(maxCardWidth, heightFit, widthFit))
            return ArenaPermanentLayout(rows, columns, cardWidth, cardWidth * r, 16 + columns * cardWidth + (columns - 1) * 4)
        }
    }
}

object HandManaCostSymbols {
    private val pattern = Regex("\\{([0-9WUBRGC/SXP]+)\\}|//")
    /** Printed-cost symbols in order; "//" separates split halves. Presentation only. */
    fun symbols(cost: String): List<String> = pattern.findAll(cost).map { it.groups[1]?.value ?: "//" }.toList()
}

/** Keep current public engine icons inside the compact art area, even on narrow cards. */
class BattlefieldAbilityBadgePlan(icons: List<XmageCardIcon>, cardWidth: Float) {
    val visible: List<XmageCardIcon>
    val hiddenCount: Int

    init {
        val slots = minOf(4, maxOf(1, ((cardWidth - 4) / (iconSize(cardWidth) + 5)).toInt()))
        val visibleCount = minOf(icons.size, if (icons.size > slots) maxOf(0, slots - 1) else slots)
        visible = icons.take(visibleCount)
        hiddenCount = icons.size - visibleCount
    }

    companion object {
        fun iconSize(cardWidth: Float): Float = minOf(15f, maxOf(10f, cardWidth * 0.17f))
        fun accessibleName(icon: XmageCardIcon): String = icon.displayText
            ?: icon.iconType.replace("ABILITY_", "").replace("_", " ").lowercase().split(" ")
                .joinToString(" ") { word -> word.replaceFirstChar { it.titlecase() } }
    }
}

object ArenaHandLayout {
    fun spacing(count: Int, width: Float, cardWidth: Float, expanded: Boolean): Float {
        if (expanded || count <= 1) return 8f
        // Never reduce the exposed touch strip below 44 points; oversized hands scroll.
        val stride = maxOf(44f, minOf(cardWidth + 8, (width - cardWidth - 12) / (count - 1)))
        return stride - cardWidth
    }
    fun restingHeight(cardHeight: Float): Float = cardHeight * 0.62f + 48
}

object HandScrubberGeometry {
    fun thumbWidth(trackWidth: Float): Float = minOf(maxOf(trackWidth * 0.22f, 34f), minOf(72f, maxOf(trackWidth, 1f)))
    fun progress(location: Float, trackWidth: Float, grabOffset: Float): Float {
        val travel = maxOf(1f, trackWidth - thumbWidth(trackWidth))
        return minOf(1f, maxOf(0f, (location - grabOffset) / travel))
    }
}

data class CombatViewportAnchor(val point: BoardPoint, val isClipped: Boolean)

object CombatViewportAnchors {
    // Shared lane order: opponent permanents, opponent lands, your permanents, your lands.
    private const val landscapeResourcePrefix = "landscape-resource:"

    fun laneIndices(human: List<ZoneCard>, opponent: List<ZoneCard>): Map<String, Int> {
        val result = HashMap<String, Int>()
        val cards = human + opponent
        for (card in BattlefieldAttachments.lane(opponent, cards, lands = false)) result[card.instanceId] = 0
        for (card in BattlefieldAttachments.lane(opponent, cards, lands = true)) result[card.instanceId] = 1
        for (card in BattlefieldAttachments.lane(human, cards, lands = false)) result[card.instanceId] = 2
        for (card in BattlefieldAttachments.lane(human, cards, lands = true)) result[card.instanceId] = 3
        // A mana rock stays in the portrait permanent lane but uses the landscape resource lane.
        val roots = BattlefieldAttachments.roots(cards)
        val byID = LinkedHashMap<String, ZoneCard>()
        cards.forEach { byID.putIfAbsent(it.instanceId, it) }
        for (card in cards) {
            if (byID[roots[card.instanceId] ?: card.instanceId]?.let(BattlefieldAttachments::isManaRock) == true) {
                result[landscapeResourcePrefix + card.instanceId] = 1
            }
        }
        return result
    }

    fun resolve(bounds: Map<String, BoardRect>, authorizedIDs: Set<String>, viewports: List<BoardRect>,
                laneIndices: Map<String, Int> = emptyMap()): Map<String, CombatViewportAnchor> {
        val result = HashMap<String, CombatViewportAnchor>()
        for ((id, rect) in bounds) {
            if (!authorizedIDs.contains(id) || rect.isEmpty) continue
            val sideBySideResources = viewports.size == 4 && abs(viewports[0].midY - viewports[1].midY) < 1
            val landscapeResource = sideBySideResources && laneIndices[landscapeResourcePrefix + id] != null
            val index = (if (landscapeResource) laneIndices[id]?.plus(1) else laneIndices[id]) ?: (if (viewports.size == 1) 0 else null)
            if (index == null || index !in viewports.indices) continue
            val lane = viewports[index]
            if (rect.midY < lane.minY || rect.midY > lane.maxY) continue
            val point = BoardPoint(minOf(maxOf(rect.midX, lane.minX + 12), lane.maxX - 12), minOf(maxOf(rect.midY, lane.minY + 12), lane.maxY - 12))
            result[id] = CombatViewportAnchor(point, !lane.contains(rect))
        }
        return result
    }
}

data class CombatEdgeCluster(val id: String, val point: BoardPoint, val cardIDs: List<String>) {
    companion object {
        fun groups(anchors: Map<String, CombatViewportAnchor>): List<CombatEdgeCluster> {
            val clipped = anchors.filter { it.value.isClipped }
            val grouped = clipped.keys.groupBy { id -> val p = clipped.getValue(id).point; "${p.x.roundToInt()}:${p.y.roundToInt()}" }
            return grouped.keys.sorted().mapNotNull { key ->
                val ids = grouped[key]?.sorted() ?: return@mapNotNull null
                val first = ids.firstOrNull() ?: return@mapNotNull null
                CombatEdgeCluster(key, clipped.getValue(first).point, ids)
            }
        }
    }
}

/** Port of BattlefieldAdaptiveSizing.swift. One flag per rendered slot; at the readable floor, overflow scrolls. */
object BattlefieldAdaptiveSizing {
    fun cardWidth(availableRowWidth: Float, maxCardWidth: Float, heightRatio: Float, tappedSlots: List<Boolean>): Float {
        if (!maxCardWidth.isFinite() || maxCardWidth <= 0) return 0f
        if (tappedSlots.isEmpty()) return maxCardWidth
        val minimum = minOf(44f, maxCardWidth)
        val available = if (availableRowWidth.isFinite()) maxOf(0f, availableRowWidth) else 0f
        val ratio = if (heightRatio.isFinite() && heightRatio > 0) heightRatio else 1f
        val footprint = tappedSlots.sumOf { (if (it) ratio else 1f).toDouble() }.toFloat()
        val gaps = (tappedSlots.size - 1) * 4f
        val fitting = maxOf(0f, available - 16 - gaps) / footprint
        return maxOf(minimum, minOf(maxCardWidth, fitting))
    }
}
