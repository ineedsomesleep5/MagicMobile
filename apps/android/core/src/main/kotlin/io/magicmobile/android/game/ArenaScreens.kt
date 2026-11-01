package io.magicmobile.android.game

import kotlin.math.max
import kotlin.math.min

/*
 * The pure rules behind the Arena board's full-table screens (phase D): which screen takes XMage's question, what its title
 * and lines say, and the trigger order chosen in the ability browser. Ported from Board/NativeGameView+Arena.swift,
 * NativeGameView+ArenaActions.swift, ArenaBoardViews.swift (ArenaQuestionStage.headline, the browsers' copy),
 * BoardCardChoiceView.swift (its Arena stage) and Models.swift (startingPlayerHeading). The views live in the app module;
 * every answer they send is the Hearth panel's command (docs/ARENA_STYLE.md principle 8).
 */

/** Who goes first, as Arena titles the opening hand ("You Go First"); null once the first turn has begun or before the table says. */
val GameSnapshot.startingPlayerHeading: String? get() {
    val id = activePlayerId ?: return null
    if (turn > 1) return null
    return if (isViewer(id)) "You Go First" else "${playerLabel(id)} Goes First"
}

/** The state of the Arena board an answer depends on: what the table shows over the question and Auto Pay's colour question. */
data class ArenaScreenContext(
    val startingRollVisible: Boolean = false,
    /** Auto Pay's last tap may be asking a colour: that question is Auto Pay's. */
    val autoPayAwaitingColor: Boolean = false,
    /** The colour question ("id:messageId") Auto Pay answered, until its answer lands. */
    val autoPayAnsweredColor: String? = null,
    /** The trigger order chosen in the ability browser (ability ids, first to place first) and the prompt it last answered. */
    val triggerPlan: List<String> = emptyList(),
    val triggerSent: String? = null,
)

object ArenaScreens {
    // MARK: Abilities and the trigger order

    /** The plan answers this ordering prompt by itself: it offers a planned trigger and hasn't been answered yet. */
    fun triggerPlanAnswers(snapshot: GameSnapshot, context: ArenaScreenContext): Boolean {
        if (context.triggerPlan.isEmpty()) return false
        val prompt = snapshot.promptEnvelopeV2 ?: return false
        if (!snapshot.isViewer(prompt.playerId) || !prompt.isTriggerOrder) return false
        val abilities = prompt.abilities ?: return false
        return "${prompt.id}:${prompt.messageId}" != context.triggerSent && abilities.any { it.id in context.triggerPlan }
    }

    data class AbilityPrompt(val prompt: PromptEnvelopeV2, val ordering: Boolean)

    /** XMage asking which ability (CHOOSE_ABILITY) or the order of triggers (PICK_ABILITY), unless a chosen order answers it. */
    fun abilityPrompt(snapshot: GameSnapshot, context: ArenaScreenContext): AbilityPrompt? {
        if (triggerPlanAnswers(snapshot, context)) return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (!snapshot.isViewer(prompt.playerId) || prompt.abilities.isNullOrEmpty()) return null
        if ((prompt.responseCommand?.type ?: "").lowercase() != "choose_ability") return null
        return AbilityPrompt(prompt, prompt.isTriggerOrder)
    }

    /**
     * `resolveOrder` runs first to last. XMage asks which goes on the stack first, which resolves last: the plan is the picks in
     * reverse, and each ordering prompt gets the first planned trigger it still offers.
     */
    fun triggerPlan(resolveOrder: List<XmagePromptAbility>): List<String> = resolveOrder.reversed().map { it.id }

    /** The trigger plan after a new snapshot, and the trigger to send now (with the prompt key it answers). */
    data class TriggerStep(val plan: List<String>, val sent: String?, val pick: XmagePromptAbility? = null)

    /**
     * The next pick of a chosen trigger order. Triggers XMage no longer offers are on the stack and leave the plan; a target
     * question for one of them keeps it; your next priority, or an ordering prompt with none of its triggers (the last one XMage
     * places itself), ends it.
     */
    fun triggerStep(snapshot: GameSnapshot, plan: List<String>, sent: String?, pending: Boolean): TriggerStep {
        if (plan.isEmpty() || pending) return TriggerStep(plan, sent)
        val prompt = snapshot.promptEnvelopeV2 ?: return TriggerStep(plan, sent)
        if (!snapshot.isViewer(prompt.playerId)) return TriggerStep(plan, sent)
        val abilities = prompt.abilities
        if (!prompt.isTriggerOrder || abilities.isNullOrEmpty()) {
            if (prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority") return TriggerStep(emptyList(), null)
            return TriggerStep(plan, sent)
        }
        val left = plan.filter { id -> abilities.any { it.id == id } }
        val next = left.firstOrNull()?.let { id -> abilities.firstOrNull { it.id == id } } ?: return TriggerStep(left, null)
        val key = "${prompt.id}:${prompt.messageId}"
        if (key == sent) return TriggerStep(left, sent)
        return TriggerStep(left, key, next)
    }

    // MARK: Modes

    /** XMage asking for a modal spell's mode: the Arena's mode browser answers it. */
    fun modePrompt(snapshot: GameSnapshot): PromptEnvelopeV2? {
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        return if (snapshot.isViewer(prompt.playerId) && !prompt.modes.isNullOrEmpty()) prompt else null
    }

    private val trailingId = Regex("""\s*\[[^\]]*\]\s*$""")

    /** The spell whose modes these are: named on the prompt's second line ("Black Market Connections [4cb]"), else the stack's top. */
    fun modeSource(prompt: PromptEnvelopeV2, snapshot: GameSnapshot): ZoneCard? {
        val lines = prompt.message.split("\n")
        if (lines.size > 1) {
            val name = lines[1].replace(trailingId, "").trim()
            PortraitInteractionPolicy.authorizedCards(snapshot).firstOrNull { it.card.name == name }?.let { return it }
        }
        return snapshot.stackTopFirst.firstOrNull()?.displaySourceCard
    }

    fun modeTitle(prompt: PromptEnvelopeV2): String = if ((prompt.maxChoices ?: 1) > 1) "Choose modes" else "Choose a mode"

    /** The count rule under the title ("Choose 2", "Up to 3"), else XMage's first line. */
    fun modeDetail(prompt: PromptEnvelopeV2): String {
        val bounds = CardChoicePlan.selectionBounds(prompt.message)
            ?: return PromptDisplayText.clean(prompt.message.split("\n").firstOrNull() ?: "")
        val (least, most) = bounds
        return when {
            most == Int.MAX_VALUE -> "Any number"
            least == most -> "Choose $most"
            least > 0 -> "Up to $most, at least $least"
            else -> "Up to $most"
        }
    }

    private val modeNumber = Regex("""^\d+\.\s*""")

    /** "1. Create a Treasure token." without its number: the card's place shows the order. */
    fun modeText(label: String): String = PromptDisplayText.clean(label).replace(modeNumber, "")

    /** Upright, more than two modes sit two to a row so none runs off the edge. */
    fun modeColumns(count: Int, landscape: Boolean): Int = if (landscape || count <= 2) max(1, count) else 2

    // MARK: Choices, players, numbers, splits and piles

    /** The card a choice names: on the battlefield first, then anywhere you can see. */
    fun card(named: String, snapshot: GameSnapshot): ZoneCard? =
        snapshot.visibleBattlefield.firstOrNull { it.card.name == named }
            ?: PortraitInteractionPolicy.authorizedCards(snapshot).firstOrNull { it.card.name == named }

    /**
     * A list of named choices (replacement effects, creature types, colours): more than three, or ones naming a card, or with
     * XMage's "Remember answer" twins. Auto Pay's own colour question is left to Auto Pay.
     */
    fun choicePrompt(snapshot: GameSnapshot, context: ArenaScreenContext): PromptEnvelopeV2? {
        val prompt = ArenaTableRules.ownPrompt(snapshot, context.startingRollVisible) ?: return null
        val choices = prompt.choices
        if (choices.isNullOrEmpty() || !prompt.modes.isNullOrEmpty() || !prompt.abilities.isNullOrEmpty() || !prompt.cards.isNullOrEmpty()) return null
        if (prompt.confirmation != null || PromptCommandBuilder.isCommanderReplacement(prompt) || context.autoPayAwaitingColor) return null
        if (context.autoPayAnsweredColor == "${prompt.id}:${prompt.messageId}") return null
        val options = ArenaChoiceList.options(choices.map { it.id to it.label })
        val namesCard = options.any { option -> option.name?.let { card(it, snapshot) != null } ?: false }
        return if (choices.size > 3 || namesCard || options.size < choices.size) prompt else null
    }

    data class ChoiceOption(val id: String, val rememberID: String?, val label: String, val text: String, val card: ZoneCard?, val symbol: String?)

    fun choiceOptions(prompt: PromptEnvelopeV2, snapshot: GameSnapshot): List<ChoiceOption> =
        ArenaChoiceList.options((prompt.choices ?: emptyList()).map { it.id to it.label }).map { option ->
            ChoiceOption(option.id, option.rememberID, option.label, option.text, option.name?.let { card(it, snapshot) }, ArenaChoiceList.colorSymbol(option.label))
        }

    /** The choice browser's look: cards when the options name some (eight at most), mana symbols for colours, else glass tiles. */
    enum class ChoiceLook { CARDS, SYMBOLS, TILES }

    fun choiceLook(options: List<ChoiceOption>): ChoiceLook = when {
        options.any { it.card != null } && options.size <= 8 -> ChoiceLook.CARDS
        options.all { it.symbol != null } -> ChoiceLook.SYMBOLS
        else -> ChoiceLook.TILES
    }

    data class Seat(val id: String, val player: PlayerGameState?, val name: String)
    data class PlayerPrompt(val prompt: PromptEnvelopeV2, val seats: List<Seat>, val type: String)

    /** Choosing a player: XMage's player list, or a "starting player" question whose targets are the players. */
    fun playerPrompt(snapshot: GameSnapshot, context: ArenaScreenContext): PlayerPrompt? {
        val prompt = ArenaTableRules.ownPrompt(snapshot, context.startingRollVisible) ?: return null
        fun seat(id: String, label: String): Seat {
            val player = snapshot.players.firstOrNull { it.playerId == id || CombatPlayerIdentity.ids(it.playerId, snapshot).contains(id) }
            return Seat(id, player, player?.let { if (snapshot.isViewer(it.playerId)) "You" else snapshot.playerLabel(it.playerId) } ?: label)
        }
        val players = prompt.players
        if (!players.isNullOrEmpty()) {
            return PlayerPrompt(prompt, players.filter { it.selectable != false }.map { seat(it.playerId, it.label) },
                PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, "choose_player"))
        }
        val ids = snapshot.players.flatMap { CombatPlayerIdentity.ids(it.playerId, snapshot) }.toSet()
        val targets = prompt.targets
        if (asksStartingPlayer(prompt.message) && !targets.isNullOrEmpty() && targets.all { it.id in ids }) {
            return PlayerPrompt(prompt, targets.map { seat(it.id, it.label) }, PromptCommandBuilder.idCommandType(prompt.responseCommand?.type, "choose_target"))
        }
        return null
    }

    fun asksStartingPlayer(message: String): Boolean {
        val text = message.lowercase()
        return text.contains("starting player") || text.contains("first turn") || text.contains("goes first")
    }

    fun playerChoiceTitle(message: String): String = if (asksStartingPlayer(PromptDisplayText.clean(message))) "Choose who goes first" else PromptDisplayText.clean(message)

    /** Upright, three or four players sit two to a row so none is cut off at the edge. */
    fun playerColumns(count: Int, landscape: Boolean): Int = max(1, if (landscape || count <= 2) count else 2)

    /** A split of damage, counters or mana among rows. */
    fun splitPrompt(snapshot: GameSnapshot, context: ArenaScreenContext): PromptEnvelopeV2? =
        ArenaTableRules.ownPrompt(snapshot, context.startingRollVisible)?.takeIf { !it.multiAmounts.isNullOrEmpty() }

    data class SplitRow(val id: String, val label: String, val card: ZoneCard?, val player: PlayerGameState?, val symbol: String?,
                        val minimum: Int, val maximum: Int, val initial: Int, val lethal: Int?)
    data class SplitSetup(val title: String, val rows: List<SplitRow>, val source: XmageStackObject?, val sourceCard: ZoneCard?)

    /** Each row as what it names: a blocker or target card, a player, a mana colour. Combat's source is the attacker. */
    fun splitSetup(prompt: PromptEnvelopeV2, snapshot: GameSnapshot): SplitSetup {
        // Combat's split comes in the combat damage step; "assign damage among targets" outside it is a spell's.
        val step = "${snapshot.phase} ${snapshot.step ?: ""}".lowercase()
        val combat = step.contains("combat") && step.contains("damage")
        val message = PromptDisplayText.clean(prompt.message.split("\n").firstOrNull() ?: "")
        val damage = combat || message.lowercase().contains("damage")
        var attacker: ZoneCard? = null
        val battlefield = snapshot.visibleBattlefield
        val rows = (prompt.multiAmounts ?: emptyList()).map { slot ->
            val name = ArenaSplit.name(slot.label)
            val card = battlefield.firstOrNull { it.card.name == name && (!combat || !it.blocking.isNullOrEmpty()) }
                ?: battlefield.firstOrNull { it.card.name == name }
            if (combat && attacker == null) card?.blocking?.let { blocked ->
                attacker = snapshot.human?.zones?.battlefield?.firstOrNull { it.instanceId in blocked || it.id in blocked }
            }
            val player = if (card == null) snapshot.players.firstOrNull { (it.displayName ?: "") == name || snapshot.playerLabel(it.playerId) == name } else null
            SplitRow(slot.id, slot.label, card, player, if (card == null && player == null) ArenaChoiceList.colorSymbol(name) else null,
                slot.min, slot.max, min(max(slot.defaultValue ?: slot.min, slot.min), slot.max), null)
        }
        val deathtouch = (attacker?.card?.oracleText ?: snapshot.stackTopFirst.firstOrNull()?.rulesText ?: "").lowercase().contains("deathtouch")
        val withLethal = rows.map { row ->
            val card = row.card
            val toughness = card?.displayToughness?.toIntOrNull()
            if (!damage || card == null || !card.isCreature || toughness == null) row
            else row.copy(lethal = ArenaSplit.lethal(toughness, card.damage ?: 0, deathtouch))
        }
        val title = if (combat) "Assign combat damage" else message.ifEmpty { "Divide" }
        return SplitSetup(title, withLethal, if (combat) null else snapshot.stackTopFirst.firstOrNull(), attacker)
    }

    /** What's left to give, under the split's title. */
    fun splitDetail(total: Int, totalMin: Int?, totalMax: Int?): String {
        if (totalMax != null && totalMax == (totalMin ?: totalMax)) {
            val left = totalMax - total
            return when {
                left == 0 -> "All $totalMax given out"
                left > 0 -> "$left of $totalMax left to give"
                else -> "${-left} too many"
            }
        }
        return "$total given"
    }

    /** Choosing one of two piles. */
    fun pilePrompt(snapshot: GameSnapshot, context: ArenaScreenContext): PromptEnvelopeV2? =
        ArenaTableRules.ownPrompt(snapshot, context.startingRollVisible)?.takeIf { !it.piles.isNullOrEmpty() }

    /** One of these screens has this question; the pop-up, question screen and detail panel stay away. */
    fun screenPrompt(snapshot: GameSnapshot, context: ArenaScreenContext): Boolean =
        choicePrompt(snapshot, context) != null || playerPrompt(snapshot, context) != null ||
            ArenaTableRules.amountPrompt(snapshot, context.startingRollVisible) != null || splitPrompt(snapshot, context) != null ||
            pilePrompt(snapshot, context) != null

    // MARK: The question stage

    data class Question(val title: String, val stackObject: XmageStackObject?, val card: ZoneCard?, val key: String)

    /**
     * A question for you that the Arena asks on its own screen (the question stage): a yes or no, a few choices, the commander's
     * zone. Targets stay on the table, payments in the corner. The card shown is the one the question names: the top of the
     * stack when it names its source, else a card of the prompt's, else a card it mentions.
     */
    fun question(snapshot: GameSnapshot, targetableIds: Set<String>, pendingActionId: String?, promptDetailOpen: Boolean,
                 context: ArenaScreenContext): Question? {
        // Only where the corner pop-up would ask it: never a payment, the opening hand, the starting roll or a browser's.
        if (targetableIds.isNotEmpty() || context.startingRollVisible || promptDetailOpen || OpeningHandChoice.of(snapshot) != null) return null
        if (InlinePaymentPromptState.isActive(snapshot) || !CompactPromptPopup.shouldShow(snapshot, pendingActionId)) return null
        if (modePrompt(snapshot) != null || abilityPrompt(snapshot, context) != null || screenPrompt(snapshot, context)) return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (!snapshot.isViewer(prompt.playerId) || CompactPromptPopup.isManaPaymentPrompt(prompt)) return null
        if (!prompt.cards.isNullOrEmpty() && prompt.confirmation == null) return null
        val asks = prompt.confirmation != null || PromptCommandBuilder.isCommanderReplacement(prompt) ||
            (prompt.choices?.let { it.isNotEmpty() && it.size <= 3 } ?: false) || CompactPromptPopup.compactLegalPromptActions(snapshot).isNotEmpty()
        if (!asks || prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority") return null
        val message = prompt.message.lowercase()
        val top = snapshot.stackTopFirst.firstOrNull()
        var stackObject: XmageStackObject? = null
        var card: ZoneCard? = null
        if (top != null && (message.contains(top.displaySourceName.lowercase()) || message.contains(top.displayName.lowercase()))) {
            stackObject = top
        } else if (!prompt.cards.isNullOrEmpty()) {
            card = prompt.cards!!.first()
        } else {
            card = PortraitInteractionPolicy.authorizedCards(snapshot).filter { it.card.name.isNotEmpty() && message.contains(it.card.name.lowercase()) }
                .maxByOrNull { it.card.name.length }
        }
        if (stackObject == null && card == null && top != null && message.contains("you may")) stackObject = top
        // An ability whose card XMage didn't send shows its permanent's art from the table.
        if (stackObject != null && stackObject.displaySourceCard == null && card == null) card = ArenaTableRules.sourceCard(stackObject, snapshot)
        return Question(prompt.message, stackObject, card, "${prompt.id}:${prompt.messageId}")
    }

    data class Headline(val title: String, val detail: String?)

    /**
     * The question in a few words, the reference's way ("Use Esper Sentinel's ability?"); the rest of XMage's message goes under
     * it when it says more. Never cut off, and never said twice.
     */
    fun headline(message: String, stackObject: XmageStackObject?, card: ZoneCard?): Headline {
        val clean = PromptDisplayText.clean(message)
        if (clean.length <= 64 || (stackObject == null && card == null)) return Headline(clean, null)
        val mark = clean.indexOf('?')
        if (mark in 0 until 64) {
            val rest = clean.substring(mark + 1).trim()
            return Headline(clean.substring(0, mark + 1), rest.ifEmpty { null })
        }
        // "Use X's ability?" only when the message is about X; otherwise its first sentence.
        val name = stackObject?.displaySourceName ?: card?.card?.name ?: ""
        if (name.isNotEmpty() && clean.contains(name, ignoreCase = true) && stackObject?.let(ArenaTableRules::isAbility) == true) {
            return Headline("Use $name's ability?", clean)
        }
        val stop = clean.indexOf(". ")
        if (stop in 0 until 70) {
            val rest = clean.substring(stop + 2).trim()
            return Headline(clean.substring(0, stop) + ".", rest.ifEmpty { null })
        }
        return Headline(clean, null)
    }

    /** On the question stage "No", "Cancel" and the like are Arena's blue pill, the rest the orange one. */
    fun declines(label: String): Boolean = CompactPromptPopup.yesNoIcon(label) == "xmark.circle"

    // MARK: Zones

    /** Only what the table can't show: an empty zone, or that a card is wanted. */
    fun zoneDetail(title: String, cards: List<ZoneCard>, anyTargetable: Boolean): String? = when {
        cards.isEmpty() -> if (title.contains("Library")) "Face down" else "No cards"
        anyTargetable -> "Choose a card"
        else -> null
    }

    /** As many columns as cards, up to three. */
    fun zoneColumns(count: Int): Int = min(3, max(1, count))

    // MARK: The stack browser

    fun stackOwner(item: XmageStackObject, snapshot: GameSnapshot): String {
        val controller = item.controllerId ?: return item.displaySourceName
        return if (snapshot.isViewer(controller)) "Yours" else "${snapshot.playerLabel(controller)}’s"
    }

    fun stackResponding(snapshot: GameSnapshot): Boolean =
        (snapshot.legalActions ?: emptyList()).any { it.type in setOf("pass_priority", "pass_until_response", "advance_phase") }
}

/** Card choices on the Arena board (BoardCardChoiceView.arenaStage): its zones, title, instruction line, card size and count. */
object ArenaCardChoice {
    /** Scry's Bottom and Top, surveil's Graveyard and Library, and the two piles of Fact or Fiction. */
    enum class Zones { SCRY, SURVEIL, PILES }

    fun zones(kind: CardChoicePlan.Kind?, message: String): Zones? {
        val text = message.lowercase()
        return when {
            kind == CardChoicePlan.Kind.SCRY -> Zones.SCRY
            kind == CardChoicePlan.Kind.SELECTION && text.contains("surveil") -> Zones.SURVEIL
            kind == CardChoicePlan.Kind.SELECTION && text.contains("first pile") -> Zones.PILES
            else -> null
        }
    }

    fun title(kind: CardChoicePlan.Kind?, message: String): String {
        val text = message.lowercase()
        when (kind) {
            CardChoicePlan.Kind.SCRY -> return "Scry"
            CardChoicePlan.Kind.TOP_ORDER -> return "Order the top of your library"
            CardChoicePlan.Kind.BOTTOM_ORDER -> return "Order the bottom of your library"
            else -> {}
        }
        return when {
            text.contains("surveil") -> "Surveil"
            text.contains("first pile") -> "Separate into two piles"
            text.contains("discard") -> "Discard"
            text.contains("search") || text.contains("from your library") -> "Search your library"
            text.contains("graveyard") -> "Choose from a graveyard"
            text.contains("exile") -> "Choose a card to exile"
            kind == CardChoicePlan.Kind.SELECTION -> "Choose cards"
            else -> "Choose a card"
        }
    }

    /** XMage's own words under the title, only when they add to it; scry, surveil, piles and ordering say nothing more. */
    fun instruction(kind: CardChoicePlan.Kind?, prompt: PromptEnvelopeV2): String? {
        if (zones(kind, prompt.message) != null || kind == CardChoicePlan.Kind.TOP_ORDER || kind == CardChoicePlan.Kind.BOTTOM_ORDER) return null
        val message = PromptDisplayText.clean(CardChoicePlan.context(prompt))
        val words = message.trim('.', ' ').lowercase()
        return if (words.isEmpty() || words == title(kind, prompt.message).lowercase()) null else message
    }

    /**
     * The cards' width: landscape fits the height left once the title room under the opponent's medallion (50), the search
     * field, the targets and the wells' labels are reserved; upright three to a row.
     */
    fun cardWidth(width: Float, height: Float, cards: Int, hasTargets: Boolean, zoned: Boolean): Float {
        if (width > height) {
            val reserved = 192f + (if (cards > 6) 46f else 0f) + (if (hasTargets) 56f else 0f) + (if (zoned) 30f else 0f)
            return max(74f, min(150f, (height - reserved) / 1.4f))
        }
        return if (zoned) min(112f, (width - 72f) / 3.2f) else min(124f, (width - 64f) / 3f)
    }

    /** The wells' cards side by side in landscape, shrinking so all fit (an empty well keeps room for one). */
    fun wellCardWidth(width: Float, available: Float, left: Int, right: Int, landscape: Boolean): Float {
        if (!landscape) return width
        val slots = (max(1, left) + max(1, right)).toFloat()
        return max(64f, min(width, (available - 14f - 4 * 10f) / slots - 10f))
    }

    /** "2 of 3" on the Done plaque while choosing several. */
    fun count(kind: CardChoicePlan.Kind?, message: String, chosen: Int): String? {
        if (kind != CardChoicePlan.Kind.SELECTION) return null
        val bounds = CardChoicePlan.selectionBounds(message) ?: return null
        if (CardChoicePlan.isUnbounded(bounds)) return "$chosen chosen"
        return if (bounds.first == bounds.second) "$chosen of ${bounds.second}" else "$chosen · choose ${bounds.first}–${bounds.second}"
    }
}

/** The end of a game on the Arena board (ArenaGameResultView): the word, its flare and the rank line. */
object ArenaGameResult {
    enum class Outcome { VICTORY, DEFEAT, DRAW }

    fun outcome(snapshot: GameSnapshot): Outcome {
        val winners = snapshot.winnerPlayerIds
        if (winners.isNullOrEmpty()) return Outcome.DRAW
        return if (snapshot.viewerID in winners) Outcome.VICTORY else Outcome.DEFEAT
    }

    fun word(outcome: Outcome): String = when (outcome) { Outcome.VICTORY -> "Victory"; Outcome.DEFEAT -> "Defeat"; Outcome.DRAW -> "Draw" }

    fun rankLine(change: RankChange): String = when (change.kind) {
        RankChangeKind.TIER_UP -> "Promoted"
        RankChangeKind.TIER_DOWN -> "Demoted"
        RankChangeKind.DIVISION_UP -> "Division up"
        RankChangeKind.DIVISION_DOWN -> "Division down"
        RankChangeKind.PIP_UP -> "+${change.pipDelta} pip"
        RankChangeKind.PIP_DOWN -> "${change.pipDelta} pip"
        RankChangeKind.NONE, RankChangeKind.PLACING -> "Ranked"
        RankChangeKind.PLACED -> "Placed"
    }
}
