package io.magicmobile.android.game

import kotlin.math.max
import kotlin.math.min

/*
 * The Arena board's presentation rules, pure and JVM-tested (ArenaBoardPresentationTest): what ArenaBoardPresentation.swift's
 * ArenaBattlefieldCard decides on the Arena board (its glow, its colour line, the loyalty shield), BattlefieldRow.arenaTileUnits,
 * and the decisions NativeGameView+Arena.swift and NativeGameView+ArenaActions.swift make without drawing: the lane plans,
 * the phase strip's current icon, the corner's short words, the caption, the amount pill's setup and Auto Pay's colour
 * answer. The shared battlefield rules (attachments, row arrangement, ArenaPermanentLayout…) stay in BoardLayout.kt.
 */

/** The glow border's tones (ArenaOutlineGlow.Tone): the web board's colours, the prototype's orange and gold, a shadow. */
enum class ArenaGlowTone { PLAYABLE, ABILITY, PAYABLE, TARGET, SELECTED, ATTACKING, BLOCKING, SOURCE, SHADOW }

object ArenaCardLook {
    /** The Arena board's glow on a battlefield card: what you're choosing, attackers and blockers, then what you can use,
     *  orange while paying. Lands you could tap glow softer, so a full mana row doesn't shout. */
    fun glow(card: ZoneCard, selected: Boolean, legal: Boolean, targetable: Boolean, paying: Boolean,
             /** A non-mana ability XMage would let you activate now (its canPlayObjects): the yellow glow. */
             ability: Boolean = false): Pair<ArenaGlowTone, Float>? {
        if (card.isPhasedOut) return null
        if (selected) return ArenaGlowTone.SELECTED to 1f
        if (card.isAttacking == true) return ArenaGlowTone.ATTACKING to 1f
        if (!card.blocking.isNullOrEmpty()) return ArenaGlowTone.BLOCKING to 1f
        if (targetable) return ArenaGlowTone.TARGET to 1f
        if (!legal) return null
        if (paying) return ArenaGlowTone.PAYABLE to 1f
        if (ability) return ArenaGlowTone.ABILITY to 0.95f
        return ArenaGlowTone.PLAYABLE to if (card.card.isLand) 0.65f else 0.85f
    }

    /** A tapped card tilts and greys, except an attacker on the Arena board, which keeps its colour while it attacks. */
    fun showsTapped(card: ZoneCard, arena: Boolean): Boolean = card.tapped == true && !(arena && card.isAttacking == true)

    fun isToken(card: ZoneCard): Boolean = card.card.isToken == true || card.card.typeLine.contains("token", ignoreCase = true)

    /** The card's colours: its cost, a token's colours, else its basic land types. "M" for several, "" for none. */
    fun colorKey(card: ZoneCard): String {
        val colors = mutableSetOf<String>()
        val cost = card.card.manaCost?.uppercase() ?: ""
        for (symbol in listOf("W", "U", "B", "R", "G")) if (cost.contains(symbol)) colors += symbol
        for (color in card.card.tokenColors ?: emptyList()) when (color.lowercase()) {
            "w", "white" -> colors += "W"; "u", "blue" -> colors += "U"; "b", "black" -> colors += "B"
            "r", "red" -> colors += "R"; "g", "green" -> colors += "G"
        }
        if (colors.isEmpty()) for ((land, symbol) in listOf("Plains" to "W", "Island" to "U", "Swamp" to "B", "Mountain" to "R", "Forest" to "G")) {
            if (card.card.typeLine.contains(land, ignoreCase = true)) colors += symbol
        }
        return if (colors.size > 1) "M" else colors.firstOrNull() ?: ""
    }

    /** A planeswalker's loyalty, or a battle's defense: shown on a shield where a creature's stats sit. Value and whether it's a battle. */
    fun shieldCounter(card: ZoneCard): Pair<Int, Boolean>? {
        if (card.isCreature) return null
        val battle = card.card.typeLine.contains("battle", ignoreCase = true)
        if (!card.card.isPlaneswalker && !battle) return null
        val name = if (battle) "defense" else "loyalty"
        val value = card.counters?.entries?.firstOrNull { it.key.lowercase().contains(name) }?.value ?: return null
        return value to battle
    }

    /** The counter chips leave out the one the shield already shows. */
    fun chipBadges(card: ZoneCard, plainTile: Boolean): List<CardCounterBadge> {
        val shield = shieldCounter(card)
        if (!plainTile || shield == null) return card.counterBadges
        val name = if (shield.second) "defense" else "loyalty"
        return card.counterBadges.filter { !it.name.lowercase().contains(name) }
    }

    /** Each tile's width in cards as the Arena board draws these cards, for ArenaRowFit (BattlefieldRow.arenaTileUnits): an
     *  attached Aura or Equipment peeks out 0.3 of a card per layer, a pile of lands 0.12 per copy underneath, and piles open
     *  into single cards while they are chosen from. */
    fun tileUnits(cards: List<ZoneCard>, targetableIds: Set<String>, chosenIds: Set<String>, combatHighlightIds: Set<String>): List<Float> =
        BattlefieldAttachments.groups(cards).flatMap { group ->
            val choosing = group.cards.any { targetableIds.contains(it.instanceId) || targetableIds.contains(it.id) } ||
                group.cards.any { it.isAttacking == true || it.blocking?.isNotEmpty() == true || combatHighlightIds.contains(it.instanceId) || combatHighlightIds.contains(it.id) }
            val expanded = !group.id.startsWith("attachment:") && group.count < BattlefieldTokenStack.threshold && choosing
            BattlefieldTokenStack.displayGroups(group, expanded, chosenIds)
        }.map { group ->
            when {
                group.id.startsWith("attachment:") -> 1 + 0.3f * min(group.count - 1, 3)
                group.count > 1 && group.representative.card.isLand -> 1 + 0.12f * min(group.count - 1, 5)
                else -> 1f
            }
        }
}

/** What the Arena board's lanes are choosing from right now, shared by every lane. */
data class ArenaLaneChoice(val targetableIds: Set<String>, val chosenIds: Set<String>, val highlights: Set<String>, val paying: Boolean)

enum class ArenaLaneAlignment { LEADING, CENTER, TRAILING }

/** One BattlefieldRow on the Arena board: its cards, where it goes (screen points) and at what card size. */
data class ArenaLanePlan(val title: String, val cards: List<ZoneCard>, val rect: BoardRect, val card: BoardSize, val rows: Int,
                         val alignment: ArenaLaneAlignment)

/**
 * Each side laid out the current reference game's way (NativeGameView+Arena.swift arenaLanePlans): creatures in the front row;
 * planeswalkers, battles and sagas in their own section (at the table's right edge in landscape, at the front row's end in
 * portrait); lands from the left of the back row, then artifacts, enchantments, mana rocks and Treasures. ArenaRowFit shrinks
 * the cards to use the table's whole width (portrait opens a second front row first) before any section scrolls.
 */
object ArenaLanePlanner {
    /** A lane's cards in its two sections, by the permanent each card is attached to (or itself). */
    fun sections(cards: List<ZoneCard>, trailing: (ZoneCard) -> Boolean, rank: (ZoneCard) -> Int): Pair<List<ZoneCard>, List<ZoneCard>> {
        val roots = BattlefieldAttachments.roots(cards)
        val byID = LinkedHashMap<String, ZoneCard>()
        cards.forEach { byID.putIfAbsent(it.instanceId, it) }
        fun root(card: ZoneCard): ZoneCard = byID[roots[card.instanceId] ?: card.instanceId] ?: card
        val leading = cards.filter { !trailing(root(it)) }
        val back = cards.withIndex().filter { trailing(root(it.value)) }
            .sortedWith(compareBy({ rank(root(it.value)) }, { it.index })).map { it.value }
        return leading to back
    }

    /** A lane split at its right end: the trailing section's width there, the rest (less a gap) before it. */
    fun split(lane: BoardRect, trailing: Float): Pair<BoardRect, BoardRect> {
        if (trailing <= 0f) return lane to BoardRect.zero
        val leadingWidth = max(0f, lane.width - trailing - ArenaRowFit.sectionGap)
        return BoardRect(lane.minX, lane.minY, leadingWidth, lane.height) to BoardRect(lane.maxX - trailing, lane.minY, trailing, lane.height)
    }

    fun plans(player: PlayerGameState, viewer: Boolean, allBattlefield: List<ZoneCard>, playerIDs: Set<String>, canvas: ArenaCanvas,
              choice: ArenaLaneChoice, frames: Boolean): List<ArenaLanePlan> {
        val layout = canvas.layout
        val (tileBase, landBase) = layout.tiles(frames)
        val tile = canvas.size(tileBase); val land = canvas.size(landBase)
        fun units(cards: List<ZoneCard>) = ArenaCardLook.tileUnits(cards, choice.targetableIds, choice.chosenIds, choice.highlights)
        fun sized(width: Float, base: BoardSize) = BoardSize(width, width * base.height / max(base.width, 1f))
        fun permanents(resources: Boolean) = BattlefieldAttachments.lane(player.zones.battlefield, allBattlefield, resources, playerIDs, includesManaRocks = true)
        val owner = if (viewer) "Your" else "Opponent"
        val gap = ArenaRowFit.sectionGap
        val plans = mutableListOf<ArenaLanePlan>()

        // Non-land permanents: creatures in front, planeswalkers, battles and sagas in the side section, the rest to the back row.
        val nonLand = permanents(false)
        val bySupport = sections(nonLand, { ArenaFrontSection.of(it) == ArenaFrontSection.SUPPORT }, { 0 })
        val supportCards = bySupport.second
        val front = sections(bySupport.first, { ArenaFrontSection.of(it) == ArenaFrontSection.SIDE }, ArenaFrontSection::sideRank)
        val sideUnits = units(front.second)
        val laneWidth = canvas.area(layout.creatureLane(viewer, 1)).width
        var sideRect: BoardRect? = null
        var frontRows = 1
        val sideY = if (viewer) layout.viewerSideY else layout.opponentSideY
        if (sideY != null) {
            // One fit for the creatures and the side section's cards a size up, so both shrink together as the row fills.
            val sideScale = 1.15f
            val frontFit = ArenaRowFit.fit(units(front.first), sideUnits.map { it * sideScale }, laneWidth, tile.width,
                layout.maxCreatureRows, tile.width * 0.85f)
            val sideWidth = if (sideUnits.isEmpty()) 0f else frontFit.trailingWidth
            val reserved = if (sideWidth > 0) sideWidth + gap else 0f
            val frontCard = sized(frontFit.cardWidth, tile)
            val lane = canvas.area(layout.creatureLane(viewer, frontFit.rows, frontCard.height / canvas.scale))
            plans += ArenaLanePlan("$owner board", front.first, BoardRect(lane.minX, lane.minY, lane.width - reserved, lane.height),
                frontCard, frontFit.rows, ArenaLaneAlignment.CENTER)
            if (sideWidth > 0) {
                val sideCard = sized(frontFit.cardWidth * sideScale, tile)
                val height = sideCard.height + 18
                val rect = BoardRect(lane.maxX - sideWidth, canvas.y(sideY) - height / 2, sideWidth, height)
                sideRect = rect
                plans += ArenaLanePlan("$owner permanents", front.second, rect, sideCard, 1, ArenaLaneAlignment.TRAILING)
            }
        } else {
            val frontFit = ArenaRowFit.fit(units(front.first), sideUnits, laneWidth, tile.width, layout.maxCreatureRows, tile.width * 0.85f)
            frontRows = frontFit.rows
            val frontCard = sized(frontFit.cardWidth, tile)
            val lane = canvas.area(layout.creatureLane(viewer, frontFit.rows, frontCard.height / canvas.scale))
            val firstRow = canvas.area(layout.creatureLane(viewer, 1, frontCard.height / canvas.scale))
            val (leading, trailing) = split(lane, frontFit.trailingWidth)
            plans += ArenaLanePlan("$owner board", front.first, leading, frontCard, frontFit.rows, ArenaLaneAlignment.CENTER)
            if (front.second.isNotEmpty()) {
                // With two rows the side section stacks into both; a lone permanent keeps to the row nearest the middle.
                val sideRows = if (sideUnits.size > 1) frontFit.rows else 1
                val band = if (sideRows > 1) lane else firstRow
                plans += ArenaLanePlan("$owner permanents", front.second, BoardRect(trailing.minX, band.minY, trailing.width, band.height),
                    frontCard, sideRows, ArenaLaneAlignment.TRAILING)
            }
        }

        val backLane = canvas.area(if (viewer) layout.viewerLands else layout.opponentLands)
        val resources = sections(permanents(true), { !it.card.isLand }, { 0 })
        val backLeading = resources.first
        val backTrailing = resources.second + supportCards
        val supportArea = (if (viewer) layout.viewerSupport else layout.opponentSupport)?.let(canvas::area)
        if (supportArea != null) {
            var support: BoardRect = supportArea
            // The opponent's support section stops short of their side section where the two meet.
            sideRect?.let { side ->
                if (side.maxY > support.minY && side.minY < support.maxY) {
                    support = BoardRect(support.minX, support.minY, max(0f, min(support.maxX, side.minX - gap) - support.minX), support.height)
                }
            }
            if (backTrailing.isEmpty() || support.width <= 0) {
                val fit = ArenaRowFit.fit(units(backLeading), units(backTrailing), backLane.width, land.width)
                val (leading, trailing) = split(backLane, if (backTrailing.isEmpty()) 0f else fit.trailingWidth)
                plans += ArenaLanePlan("$owner lands", backLeading, if (backTrailing.isEmpty()) backLane else leading, sized(fit.cardWidth, land), 1, ArenaLaneAlignment.LEADING)
                if (backTrailing.isNotEmpty()) plans += ArenaLanePlan("$owner artifacts", backTrailing, trailing, sized(fit.cardWidth, land), 1, ArenaLaneAlignment.TRAILING)
            } else {
                // Lands from the left and artifacts from the support section's right end share the whole back row; the
                // artifacts keep at least the support section's width, taken only from room the lands don't need.
                val band = BoardRect(backLane.minX, backLane.minY, max(backLane.maxX, support.maxX) - backLane.minX, backLane.height)
                val fit = ArenaRowFit.fit(units(backLeading), units(backTrailing), band.width, land.width)
                val landsNeed = ArenaRowFit.sectionWidth(units(backLeading), fit.cardWidth)
                val spare = max(0f, band.width - landsNeed - gap)
                val (leading, trailing) = split(band, max(fit.trailingWidth, min(support.width, spare)))
                plans += ArenaLanePlan("$owner lands", backLeading, leading, sized(fit.cardWidth, land), 1, ArenaLaneAlignment.LEADING)
                plans += ArenaLanePlan("$owner artifacts", backTrailing, trailing, sized(fit.cardWidth, land), 1, ArenaLaneAlignment.TRAILING)
            }
        } else if (backTrailing.isNotEmpty() && (!viewer || frontRows <= 1)) {
            // Portrait with room: artifacts, enchantments, mana rocks and Treasures get a row of their own in front of the lands.
            val landsFit = ArenaRowFit.fit(units(backLeading), emptyList(), backLane.width, land.width)
            val supportFit = ArenaRowFit.fit(units(backTrailing), emptyList(), backLane.width, land.width)
            val step = backLane.height + canvas.length(4f)
            plans += ArenaLanePlan("$owner lands", backLeading, backLane, sized(landsFit.cardWidth, land), 1, ArenaLaneAlignment.LEADING)
            plans += ArenaLanePlan("$owner artifacts", backTrailing, backLane.offsetBy(0f, if (viewer) -step else step),
                sized(supportFit.cardWidth, land), 1, ArenaLaneAlignment.TRAILING)
        } else {
            val backFit = ArenaRowFit.fit(units(backLeading), units(backTrailing), backLane.width, land.width)
            val card = sized(backFit.cardWidth, land)
            val (leading, trailing) = split(backLane, backFit.trailingWidth)
            plans += ArenaLanePlan("$owner lands", backLeading, leading, card, 1, ArenaLaneAlignment.LEADING)
            if (backTrailing.isNotEmpty()) plans += ArenaLanePlan("$owner artifacts", backTrailing, trailing, card, 1, ArenaLaneAlignment.TRAILING)
        }
        return plans
    }
}

/** The reference's phase strip: the eight steps of a turn (ArenaPhaseStrip). */
object ArenaPhaseStripRules {
    enum class Icon { DIAMOND, CARD, SWORD, SHIELD, BURST }

    /** Beginning, main 1, attackers, blockers, damage, end of combat, main 2, end. */
    val icons = listOf(Icon.DIAMOND, Icon.CARD, Icon.SWORD, Icon.SHIELD, Icon.BURST, Icon.DIAMOND, Icon.CARD, Icon.DIAMOND)

    /** Which of the eight icons a step lights. */
    fun current(step: String?): Int? = when ((step ?: "").lowercase().replace("_", "-")) {
        "beginning", "untap", "upkeep", "draw" -> 0
        "precombat-main", "main1" -> 1
        "combat", "begin-combat", "declare-attackers" -> 2
        "declare-blockers" -> 3
        "first-combat-damage", "first-strike-damage", "combat-damage" -> 4
        "end-combat" -> 5
        "postcombat-main", "main2" -> 6
        "ending", "end", "end-turn", "cleanup" -> 7
        else -> null
    }
}

/** The corner's words and the table's caption (NativeGameView+ArenaActions.swift). */
object ArenaCornerText {
    /** The reference's short words: Next to move on, End Turn late in your turn, Resolve over a stack, Pass otherwise. */
    fun passTitle(action: LegalAction, snapshot: GameSnapshot): Pair<String, String?> {
        if (action.type != "pass_priority") return GameplayActionPresentation.title(action, snapshot) to null
        if (snapshot.stackTopFirst.isNotEmpty()) return "Resolve" to null
        if (!snapshot.isViewer(snapshot.activePlayerId)) return "Pass" to null
        return when (TavernPhaseTrack.describe(snapshot.step ?: snapshot.phase).second) {
            0 -> "Next" to "To Main"
            1 -> "Next" to "To Combat"
            2 -> "Next" to "To Main 2"
            else -> "End Turn" to null
        }
    }

    fun waitingTitle(snapshot: GameSnapshot): String {
        val active = snapshot.activePlayerId
        if (active == null || snapshot.isViewer(active)) return "Waiting…"
        return if (BoardOpponentFocus.opponents(snapshot).size > 1) "${snapshot.playerLabel(active)}’s Turn" else "Opponent’s Turn"
    }

    /** The caption over the midline: what the table wants right now, in the reference's few words. */
    fun caption(snapshot: GameSnapshot, combat: CombatSelectionState): String? {
        if (InlinePaymentPromptState.isActive(snapshot)) {
            val prompt = InlinePaymentPromptState.paymentPrompt(snapshot)
            if (prompt != null) {
                val clean = PromptDisplayText.clean(snapshot.manaPayment?.remainingText ?: prompt.message)
                return if (clean.isEmpty()) "Pay the cost" else if (clean.startsWith("{")) "Pay $clean" else clean
            }
        }
        when (ArenaCombatPhase.current(snapshot)) {
            ArenaCombatPhase.ATTACKERS -> return if (combat.selectedAttackerIds.isEmpty()) "Choose attackers." else "Choose who to attack."
            ArenaCombatPhase.BLOCKERS -> return if (combat.selectedBlockerId == null) "Choose blockers." else "Choose the attacker to block."
            null -> {}
        }
        val prompt = snapshot.promptEnvelopeV2
        if (GameBoardInteractionState.boardTargetableIds(snapshot).isNotEmpty() && prompt != null) {
            return PromptDisplayText.clean(if (prompt.message.isEmpty()) "Choose a target." else prompt.message)
        }
        return null
    }

    /** The choice that names `wanted` in XMage's mana-colour question, or its first colour when any will do; null when the
     *  prompt isn't a colour question (Auto Pay answers the one its tap asked). */
    fun colorChoice(prompt: PromptEnvelopeV2, wanted: String?): String? {
        val names = mapOf("W" to "white", "U" to "blue", "B" to "black", "R" to "red", "G" to "green")
        val choices = prompt.choices ?: return null
        if (prompt.responseKind.lowercase() != "choice" || choices.isEmpty() ||
            !choices.all { choice -> names.values.any { choice.label.lowercase().contains(it) } }) return null
        val name = wanted?.let { names[it] }
        if (name != null) choices.firstOrNull { it.label.lowercase().contains(name) }?.let { return it.id }
        return choices.firstOrNull()?.id
    }
}

/** The Arena table's smaller readers. */
/**
 * The stack card can step aside (iOS ArenaStackTuck; Danny, 2026-10-26: sideways, the stack card covered what he wanted to
 * tap). A tab on its left edge tucks it to the table's edge, a slim tab there brings it back, and it tucks itself while you
 * pick something on the table. A tuck lasts for the spell or ability on top: the next one shows.
 */
object ArenaStackTuck {
    /** [tuckedTop]: the top object the player tucked; [peekTop]: the one they brought back while picking. */
    fun isTucked(top: String, tuckedTop: String?, peekTop: String?, picking: Boolean): Boolean =
        peekTop != top && (tuckedTop == top || picking)
}

/**
 * Where a target question's choices are when the table can't show them (iOS ArenaTargetReach; Caleb, 2026-10-28: Gogo
 * copying Zur's attack trigger offered only abilities on the stack, so nothing could be tapped). Spells and abilities on
 * the stack are chosen in the stack browser. With four players the board shows one opponent: when it offers nothing to
 * choose and another opponent's permanents do, the board turns to that opponent.
 */
data class ArenaTargetReach(
    /** Stack objects that can be chosen, the one that resolves next first. */
    val stack: List<String>,
    /** Opponents the board doesn't show whose permanents can be chosen, in seat order. */
    val hiddenOpponents: List<String>,
    /** Something on the table as shown can be chosen: a permanent on your side or the shown opponent's, or one of you. */
    val onTable: Boolean,
) {
    /** The opponent to show for this question: the first hidden one with choices, when the table as shown has none. */
    val opponentToShow: String? get() = if (onTable || stack.isNotEmpty()) null else hiddenOpponents.firstOrNull()

    companion object {
        fun of(snapshot: GameSnapshot, targetable: Set<String> = GameBoardInteractionState.boardTargetableIds(snapshot)): ArenaTargetReach {
            if (targetable.isEmpty()) return ArenaTargetReach(emptyList(), emptyList(), false)
            fun chosen(card: ZoneCard) = card.id in targetable || card.instanceId in targetable
            val shown = listOfNotNull(snapshot.seat?.playerId, snapshot.opponent?.playerId)
            val onTable = snapshot.players.any { player ->
                player.playerId in shown && (player.playerId in targetable || player.zones.battlefield.any(::chosen))
            }
            val hidden = snapshot.players.filter { player ->
                player.playerId !in shown && !snapshot.isViewer(player.playerId) && player.zones.battlefield.any(::chosen)
            }.map { it.playerId }
            return ArenaTargetReach(snapshot.stackTopFirst.map { it.id }.filter { it in targetable }, hidden, onTable)
        }
    }
}

object ArenaTableRules {
    /** The library's top card when it is revealed; the design fixtures' "Hidden card" placeholders stay face down. */
    fun revealedTop(player: PlayerGameState): ZoneCard? = player.zones.library.firstOrNull()?.takeIf { it.card.name != "Hidden card" }

    /** XMage marks spells; everything else on the stack is an activated or triggered ability. */
    fun isAbility(item: XmageStackObject): Boolean = item.objectType != null && item.objectType.uppercase() != "SPELL"

    /** The spell's landing light: its one colour, "M" for several, a commander or an ability, "" for colourless. */
    fun arrivalColor(item: XmageStackObject, commander: Boolean): String {
        if (commander || isAbility(item)) return "M"
        val cost = (item.displaySourceCard?.card?.manaCost ?: "").uppercase()
        val colors = listOf("W", "U", "B", "R", "G").filter { cost.contains("{$it") || cost.contains("/$it") }
        return if (colors.size == 1) colors[0] else if (colors.isEmpty()) "" else "M"
    }

    /** A commander cast from the command zone: the stack card wears a gold rim and a crown. */
    fun isCommanderSpell(item: XmageStackObject, snapshot: GameSnapshot): Boolean = !isAbility(item) && snapshot.players.any { player ->
        player.commanders?.any { it.name == item.displaySourceName || it.name == item.displayName } == true
    }

    /** The card a stack object comes from: XMage's own, else its permanent on the table, else a card of its name there. */
    fun sourceCard(item: XmageStackObject, snapshot: GameSnapshot): ZoneCard? {
        item.displaySourceCard?.let { return it }
        val battlefield = snapshot.players.flatMap { it.zones.battlefield }
        item.sourceInstanceId?.let { id -> battlefield.firstOrNull { it.instanceId == id || it.id == id }?.let { return it } }
        val name = item.displaySourceName
        return if (name.isEmpty()) null else battlefield.firstOrNull { it.card.name == name }
    }

    /** Where a player's card opens (300 wide, at most 360 tall): beside the medallion toward the table, kept on the screen. */
    fun playerCardCenter(medallion: BoardPoint, viewer: Boolean, landscape: Boolean, screen: BoardSize): BoardPoint {
        val width = 300f; val height = min(screen.height - 24, 360f)
        var x: Float; var y: Float
        if (landscape) {
            if (viewer) { x = medallion.x + 40 + width / 2; y = medallion.y - height / 2 - 10 } else { x = medallion.x; y = medallion.y + 40 + height / 2 }
        } else {
            x = medallion.x + width / 2 - 20
            y = if (viewer) medallion.y - 50 - height / 2 else medallion.y + 40 + height / 2
        }
        x = x.coerceIn(width / 2 + 12, max(width / 2 + 12, screen.width - width / 2 - 12))
        y = y.coerceIn(height / 2 + 12, max(height / 2 + 12, screen.height - height / 2 - 12))
        return BoardPoint(x, y)
    }

    /** A question of yours the Arena's own screens take: not a payment, the opening hand or the starting roll. */
    fun ownPrompt(snapshot: GameSnapshot, startingRollVisible: Boolean): PromptEnvelopeV2? {
        if (startingRollVisible || OpeningHandChoice.of(snapshot) != null || InlinePaymentPromptState.isActive(snapshot)) return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (!snapshot.isViewer(prompt.playerId) || CompactPromptPopup.isManaPaymentPrompt(prompt) ||
            prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority") return null
        return prompt
    }

    /** A number to choose (X, how many): XMage's amount question. Paying X mana stays with the payment. */
    fun amountPrompt(snapshot: GameSnapshot, startingRollVisible: Boolean): PromptEnvelopeV2? {
        val prompt = ownPrompt(snapshot, startingRollVisible) ?: return null
        if (prompt.multiAmounts?.isNotEmpty() == true) return null
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        return if (prompt.amounts?.isNotEmpty() == true || type == "choose_amount") prompt else null
    }

    data class AmountSetup(val range: ArenaAmountRange, val label: String, val initial: Int)

    /** The amount pill's values, label and first value: X starts at the most your mana pays, anything else at its least. */
    fun amountSetup(prompt: PromptEnvelopeV2, snapshot: GameSnapshot): AmountSetup {
        val range = ArenaAmountRange(prompt.amounts, prompt.minChoices, prompt.maxChoices)
        val isX = prompt.message.contains("{X}") || prompt.message.lowercase().contains("value for x")
        val cost = snapshot.stackTopFirst.firstOrNull()?.displaySourceCard?.card?.manaCost
        val human = snapshot.human
        if (!isX || cost == null || human == null) return AmountSetup(range, if (isX) "Pay X" else "Choose", range.minimum)
        val sources = human.zones.battlefield.count { card ->
            val rules = (card.card.oracleText ?: "").lowercase()
            card.tapped != true && (card.card.isLand || rules.contains("add {") || rules.contains("add one mana"))
        }
        val pool = human.manaPool?.let { it.W + it.U + it.B + it.R + it.G + it.C } ?: 0
        val affordable = ArenaAmountRange.affordableX(cost, sources + pool) ?: range.minimum
        return AmountSetup(range, "Pay X", range.clamp(affordable))
    }
}
