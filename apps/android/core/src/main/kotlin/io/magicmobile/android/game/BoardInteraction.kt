package io.magicmobile.android.game

import java.text.Normalizer

/**
 * Ports of apps/ios/MagicMobile/GameBoardInteractionState.swift, PortraitInteractionPolicy.swift,
 * PromptCommandBuilder.swift and the command/selection helpers at the top of ContentView.swift.
 */
sealed class GameBoardInteractionMode {
    object Idle : GameBoardInteractionMode()
    data class SelectedCard(val cardId: String) : GameBoardInteractionMode()
    data class DraggingCard(val cardId: String, val legalActionIds: List<String>) : GameBoardInteractionMode()
    data class AwaitingCastSnapshot(val actionId: String) : GameBoardInteractionMode()
    data class ManaPayment(val promptId: String) : GameBoardInteractionMode()
    data class Targeting(val promptId: String, val sourceCardId: String?, val validTargetIds: Set<String>) : GameBoardInteractionMode()
    data class SearchSelecting(val promptId: String, val zoneName: String, val selectedIds: Set<String>) : GameBoardInteractionMode()
    object CombatSelectingAttackers : GameBoardInteractionMode()
    object CombatSelectingBlockers : GameBoardInteractionMode()
    data class DamageAllocating(val promptId: String) : GameBoardInteractionMode()
    object WaitingForXmage : GameBoardInteractionMode()
    object GameOver : GameBoardInteractionMode()
    data class UnsupportedPrompt(val promptId: String, val method: String, val responseKind: String) : GameBoardInteractionMode()
}

object GameplayActionPresentation {
    fun priorityDetail(hasStack: Boolean): String = if (hasStack) "Let others respond" else "Let this step continue"
    fun priorityHint(hasStack: Boolean): String = if (hasStack)
        "Pass without responding. If everyone passes, the top spell or ability resolves."
    else "Pass without taking an action. If everyone passes, the game moves to the next step or phase."

    private val yieldActionGroups = listOf(listOf("resolve_stack", "pass_until_stack_resolved"), listOf("pass_until_response"),
        listOf("end_turn", "pass_until_end_of_turn"), listOf("yield_until_next_turn", "pass_until_next_turn"))

    fun yieldActions(actions: List<LegalAction>): List<LegalAction> = yieldActionGroups.mapNotNull { types ->
        types.firstNotNullOfOrNull { type -> actions.firstOrNull { it.type == type } }
    }

    fun title(action: LegalAction?, snapshot: GameSnapshot): String {
        action ?: return "Wait"
        return when (action.type) {
            "pass_priority" -> "Pass Priority"
            "pass_until_response" -> "Pass Until Response"
            "resolve_stack", "pass_until_stack_resolved" -> "Resolve Stack"
            "end_turn" -> "End Turn"
            "pass_until_end_of_turn" -> "Yield Until End Step"
            "yield_until_next_turn", "pass_until_next_turn" -> "Yield Until Next Turn"
            "advance_phase" -> "Yield Until Next Main"
            "declare_attackers" -> "Done Attacking"
            "declare_blockers" -> "Done Blocking"
            else -> action.shortLabel?.takeIf { it.isNotEmpty() } ?: action.label
        }
    }
}

data class GameActionDockModel(val mode: Mode, val primaryAction: LegalAction?, val promptActions: List<LegalAction>,
                               val primaryTitle: String, val showsPromptDetails: Boolean, val isPrimaryEnabled: Boolean) {
    enum class Mode { PROMPT, PRIORITY, WAITING, GAME_OVER }

    companion object {
        fun make(snapshot: GameSnapshot, passAction: LegalAction?, promptActions: List<LegalAction>, decisionRequired: Boolean,
                 pendingActionId: String?): GameActionDockModel {
            if (snapshot.isCompleted) return GameActionDockModel(Mode.GAME_OVER, null, emptyList(), "Game Complete", false, false)
            if (pendingActionId != null) return GameActionDockModel(Mode.WAITING, null, promptActions, "Waiting for XMage", false, false)
            if (decisionRequired) {
                val primary = PortraitInteractionPolicy.primaryDockAction(promptActions, snapshot.promptEnvelopeV2)
                return GameActionDockModel(Mode.PROMPT, primary, promptActions, primary?.label ?: "Open Choice", true, true)
            }
            return GameActionDockModel(Mode.PRIORITY, passAction, emptyList(), GameplayActionPresentation.title(passAction, snapshot), false, passAction != null)
        }
    }
}

data class BattlefieldCardGroup(val id: String, val cards: List<ZoneCard>) {
    val representative: ZoneCard get() = cards[0]
    val count: Int get() = cards.size
}

object BattlefieldDensityPlanner {
    fun groups(cards: List<ZoneCard>): List<BattlefieldCardGroup> {
        val grouped = LinkedHashMap<String, MutableList<ZoneCard>>()
        for (card in cards) grouped.getOrPut(groupKey(card)) { mutableListOf() } += card
        return grouped.map { (key, value) -> BattlefieldCardGroup(key, value) }
    }

    private fun groupKey(card: ZoneCard): String {
        val counters = (card.counters ?: emptyMap()).toSortedMap().map { "${it.key}=${it.value}" }.joinToString(",")
        val icons = (card.cardIcons ?: emptyList()).map { "${it.iconType}:${it.resourceName ?: ""}" }.sorted().joinToString(",")
        val blockers = (card.blocking ?: emptyList()).sorted().joinToString(",")
        return listOf(card.card.name, card.card.typeLine, card.card.oracleText ?: "", (card.tapped ?: false).toString(),
            card.isPhasedOut.toString(), (card.summoningSickness ?: false).toString(), counters, card.displayPower ?: "",
            card.displayToughness ?: "", (card.damage ?: Int.MIN_VALUE).toString(), (card.isAttacking ?: false).toString(), blockers,
            card.attachedToInstanceId ?: "", (card.selectable ?: true).toString(), card.disabledReason ?: "", icons).joinToString("|")
    }
}

data class GameBoardInteractionState(val mode: GameBoardInteractionMode = GameBoardInteractionMode.Idle, val feedback: String? = null) {
    val isWaitingForAuthoritativeSnapshot: Boolean get() =
        mode is GameBoardInteractionMode.AwaitingCastSnapshot || mode is GameBoardInteractionMode.WaitingForXmage
    val targetableIds: Set<String> get() = (mode as? GameBoardInteractionMode.Targeting)?.validTargetIds ?: emptySet()
    fun isTargetable(card: ZoneCard): Boolean = targetableIds.contains(card.instanceId) || targetableIds.contains(card.id)

    companion object {
        val idle = GameBoardInteractionState()

        fun mode(snapshot: GameSnapshot, pendingActionId: String?, selectedCard: ZoneCard?): GameBoardInteractionMode {
            if (snapshot.isCompleted) return GameBoardInteractionMode.GameOver
            if (pendingActionId != null) return GameBoardInteractionMode.WaitingForXmage
            snapshot.promptEnvelopeV2?.let { prompt ->
                val promptID = prompt.responseCommand?.promptId ?: prompt.id
                if (isManaPaymentPrompt(prompt)) return GameBoardInteractionMode.ManaPayment(promptID)
                targetingMode(prompt, selectedCard)?.let { return it }
                if (isSearchPrompt(prompt)) return GameBoardInteractionMode.SearchSelecting(promptID, searchZoneName(prompt), emptySet())
                if (PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, snapshot.phase, snapshot.step)) return GameBoardInteractionMode.DamageAllocating(promptID)
                if (!hasMobileSafeControl(prompt)) return GameBoardInteractionMode.UnsupportedPrompt(promptID, prompt.method, prompt.responseKind)
            }
            val actions = snapshot.legalActions ?: emptyList()
            if (actions.any { it.type == "declare_attackers" }) return GameBoardInteractionMode.CombatSelectingAttackers
            if (actions.any { it.type == "declare_blockers" }) return GameBoardInteractionMode.CombatSelectingBlockers
            if (selectedCard != null) return GameBoardInteractionMode.SelectedCard(selectedCard.instanceId)
            return GameBoardInteractionMode.Idle
        }

        fun legalPlayActions(card: ZoneCard, actions: List<LegalAction>): List<LegalAction> =
            cardActions(card, actions).filter { it.type == "play_land" || it.type == "cast_spell" }

        fun cardActions(card: ZoneCard, actions: List<LegalAction>): List<LegalAction> {
            val ids = setOf(card.instanceId, card.id)
            return actions.filter { action ->
                action.effectiveCardInstanceId?.let(ids::contains) == true || action.effectiveSourceInstanceId?.let(ids::contains) == true
            }
        }

        fun validTargetIds(prompt: PromptEnvelopeV2?, actions: List<LegalAction>): Set<String> {
            val ids = mutableSetOf<String>()
            if (prompt != null) {
                ids += prompt.targetIds ?: emptyList()
                ids += prompt.targets?.map { it.id } ?: emptyList()
                ids += prompt.cards?.map { it.instanceId } ?: emptyList()
                ids += prompt.players?.map { it.playerId } ?: emptyList()
            }
            for (action in actions) {
                ids += action.validTargetIds ?: emptyList(); ids += action.targetIds ?: emptyList()
                ids += action.validCardInstanceIds ?: emptyList(); ids += action.cardInstanceIds ?: emptyList()
                ids += action.validPlayerIds ?: emptyList(); ids += action.playerIds ?: emptyList()
            }
            return ids
        }

        fun boardTargetableIds(snapshot: GameSnapshot): Set<String> {
            val prompt = snapshot.promptEnvelopeV2 ?: return emptySet()
            if (isManaPaymentPrompt(prompt) || snapshot.manaPayment?.active == true) return emptySet()
            val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
            val isTargetPrompt = type == "choose_target" || prompt.responseKind.lowercase() == "target" || prompt.method.contains("TARGET", ignoreCase = true)
            if (!isTargetPrompt) return emptySet()
            return validTargetIds(prompt, snapshot.legalActions ?: emptyList())
        }

        private fun targetingMode(prompt: PromptEnvelopeV2, selectedCard: ZoneCard?): GameBoardInteractionMode? {
            val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
            val looksLikeTarget = type == "choose_target" || prompt.responseKind.lowercase() == "target" || prompt.method.contains("TARGET", ignoreCase = true)
            if (!looksLikeTarget) return null
            val ids = validTargetIds(prompt, emptyList())
            if (ids.isEmpty()) return null
            return GameBoardInteractionMode.Targeting(prompt.responseCommand?.promptId ?: prompt.id, selectedCard?.instanceId, ids)
        }

        private fun isSearchPrompt(prompt: PromptEnvelopeV2): Boolean {
            val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
            return type == "search_select" || prompt.method.contains("search", ignoreCase = true)
        }

        private fun isManaPaymentPrompt(prompt: PromptEnvelopeV2): Boolean {
            val type = prompt.responseCommand?.type?.lowercase() ?: ""
            val kind = prompt.responseKind.lowercase()
            return type in setOf("play_mana", "choose_mana", "pay_cost", "play_x_mana") || kind in setOf("mana", "pay_cost", "cost", "x_mana") ||
                prompt.method == "GAME_PLAY_MANA" || prompt.method == "GAME_PLAY_XMANA"
        }

        private fun searchZoneName(prompt: PromptEnvelopeV2): String =
            prompt.options?.get("zone").string?.takeIf { it.isNotEmpty() }?.let(::capitalizedWords) ?: "Library"

        private fun hasMobileSafeControl(prompt: PromptEnvelopeV2): Boolean {
            if (prompt.choices?.isNotEmpty() == true) return true
            if (prompt.targets?.isNotEmpty() == true || prompt.targetIds?.isNotEmpty() == true) return true
            if (prompt.players?.isNotEmpty() == true || prompt.cards?.isNotEmpty() == true) return true
            if (prompt.piles?.isNotEmpty() == true || prompt.abilities?.isNotEmpty() == true) return true
            if (prompt.modes?.isNotEmpty() == true || prompt.amounts?.isNotEmpty() == true) return true
            if (prompt.multiAmounts?.isNotEmpty() == true || prompt.manaChoices?.isNotEmpty() == true) return true
            if (prompt.orderedItems?.isNotEmpty() == true || prompt.confirmation != null) return true
            val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
            return type in setOf("answer_yes_no", "commander_replacement", "pay_cost", "play_mana", "choose_mana", "order_triggers", "order_items")
        }
    }
}

sealed class DragCastDropResult {
    object Ignored : DragCastDropResult()
    data class Rejected(val message: String) : DragCastDropResult()
    data class RequiresChoice(val actions: List<LegalAction>, val message: String) : DragCastDropResult()
    data class Submit(val action: LegalAction) : DragCastDropResult()
}

object DragCastDropResolver {
    fun resolve(card: ZoneCard, legalActions: List<LegalAction>, droppedInPlayArea: Boolean): DragCastDropResult {
        if (!droppedInPlayArea) return DragCastDropResult.Ignored
        val playable = GameBoardInteractionState.legalPlayActions(card, legalActions)
        if (playable.size == 1) return DragCastDropResult.Submit(playable[0])
        if (playable.isEmpty()) return DragCastDropResult.Rejected("${card.card.name} is not currently playable")
        return DragCastDropResult.RequiresChoice(playable, "Choose how to play ${card.card.name}")
    }
}

/** Both means two current engine offers, never merely a double-faced card. */
enum class CardPlayAffordance {
    NONE, LAND, SPELL, LAND_AND_SPELL;
    val accessibilityValue: String get() = when (this) {
        NONE -> "No play offered"; LAND -> "Play land available"; SPELL -> "Cast spell available"; LAND_AND_SPELL -> "Play land or cast spell available"
    }
    companion object { fun of(land: Boolean, spell: Boolean) = if (land) (if (spell) LAND_AND_SPELL else LAND) else if (spell) SPELL else NONE }
}

/** A cue follows engine steps, never priority changes or repeated polls. */
data class BoardPhaseAnnouncement(val key: String, val title: String, val owner: String) {
    companion object {
        private val titles = mapOf("beginning" to "Beginning phase", "untap" to "Untap", "upkeep" to "Upkeep", "draw" to "Draw",
            "precombat-main" to "Main phase 1", "postcombat-main" to "Main phase 2", "combat" to "Combat", "begin-combat" to "Begin combat",
            "declare-attackers" to "Declare attackers", "declare-blockers" to "Declare blockers", "first-combat-damage" to "First-strike damage",
            "combat-damage" to "Combat damage", "end-combat" to "End combat", "ending" to "End step", "end-turn" to "End step", "cleanup" to "Cleanup")

        fun make(snapshot: GameSnapshot): BoardPhaseAnnouncement? {
            if (snapshot.isCompleted) return null
            val active = snapshot.activePlayerId ?: return null
            val raw = (snapshot.step ?: snapshot.phase).lowercase().replace("_", "-")
            val title = titles[raw] ?: return null
            return BoardPhaseAnnouncement("${snapshot.id}:${snapshot.turn}:$active:$raw", title,
                if (snapshot.isViewer(active)) "Your turn" else "${snapshot.playerLabel(active)}’s turn")
        }
    }
}

/** Presentation decisions never rewrite an engine action or a seat identity. */
object PortraitInteractionPolicy {
    fun primaryDockAction(actions: List<LegalAction>, prompt: PromptEnvelopeV2?): LegalAction? {
        if (prompt != null && prompt.method == "GAME_SELECT" && prompt.responseKind == "target") {
            // Combat's special string means Attack all; never a substitute for Done / Pass.
            return actions.firstOrNull {
                it.type == "answer_yes_no" && it.confirmed == true && it.promptId == (prompt.responseCommand?.promptId ?: prompt.id) &&
                    it.messageId == (prompt.responseCommand?.messageId ?: prompt.messageId) && it.playerId == prompt.playerId
            }
        }
        return actions.firstOrNull()
    }

    /** Swift `localizedStandardContains`: case- and diacritic-insensitive. */
    fun standardContains(text: String, word: String): Boolean = fold(text).contains(fold(word))
    private fun fold(value: String): String =
        Normalizer.normalize(value, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

    fun matchesCardSearch(card: ZoneCard, query: String): Boolean {
        val words = query.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val visible = listOf(card.card.name, card.card.typeLine, card.card.oracleText ?: "").joinToString(" ")
        return words.all { standardContains(visible, it) }
    }

    fun cardChoiceKey(snapshot: GameSnapshot): String? {
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (snapshot.isCompleted || !snapshot.isViewer(prompt.playerId) || prompt.cards.isNullOrEmpty() ||
            prompt.responseCommand?.type != "choose_target" || prompt.maxChoices != 1) return null
        return "${snapshot.id}:${prompt.playerId}:${prompt.id}:${prompt.messageId}"
    }

    fun detailChoiceKey(snapshot: GameSnapshot): String? {
        if (cardChoiceKey(snapshot) != null || snapshot.isCompleted) return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (!snapshot.isViewer(prompt.playerId)) return null
        // Priority can contain a "pass" choice, but it belongs in the dock.
        if (prompt.responseCommand?.type == "pass_priority" || prompt.responseKind == "priority") return null
        val kind = MobilePromptPresentation.kind(prompt)
        if (kind !in setOf(MobilePromptKind.CARD_CHOICE, MobilePromptKind.SEARCH, MobilePromptKind.ABILITY_CHOICE, MobilePromptKind.ORDER,
                MobilePromptKind.AMOUNT, MobilePromptKind.MULTI_AMOUNT, MobilePromptKind.PILE)) return null
        return "${snapshot.id}:${prompt.playerId}:${prompt.id}:${prompt.messageId}"
    }

    fun automaticCardAction(cardActions: List<LegalAction>): LegalAction? = if (cardActions.size == 1) cardActions[0] else null

    fun authorizedCards(snapshot: GameSnapshot): List<ZoneCard> {
        val cards = mutableListOf<ZoneCard>()
        for (player in snapshot.players) {
            val z = player.zones
            cards += z.hand; cards += z.library; cards += z.battlefield; cards += z.graveyard; cards += z.exile; cards += z.command; cards += z.stack
        }
        snapshot.xmage?.let { x ->
            cards += x.stack.mapNotNull { it.displaySourceCard }
            for (group in x.revealed + x.lookedAt + x.exileZones + x.companion) cards += group.cards
        }
        cards += snapshot.promptEnvelopeV2?.cards ?: emptyList()
        cards += snapshot.promptEnvelopeV2?.abilities?.mapNotNull { it.sourceCard } ?: emptyList()
        for (pile in snapshot.promptEnvelopeV2?.piles ?: emptyList()) cards += pile.cards
        return cards
    }

    fun isCardAction(action: LegalAction): Boolean =
        action.type in setOf("play_land", "cast_spell", "make_mana", "activate_ability") && (action.cardInstanceId != null || action.sourceInstanceId != null)

    fun dockActions(actions: List<LegalAction>): List<LegalAction> = actions.filter { !isCardAction(it) && it.type != "concede" }

    fun turnCueKey(snapshot: GameSnapshot): String? {
        if (snapshot.isCompleted || !snapshot.isViewer(snapshot.activePlayerId)) return null
        return "${snapshot.id}:${snapshot.turn}:${snapshot.viewerID}"
    }
}

/** Which players the board shows. Presentation only: the viewer's seat, permissions, polling and hidden information never change. */
object BoardOpponentFocus {
    /**
     * The bottom seat. While the viewer watches after leaving the game, the next living player
     * after them in turn order stands in, so the board never shows an empty seat. Recomputed on
     * every poll, so a knocked-out stand-in hands the seat to the next player.
     */
    fun seatPlayerID(snapshot: GameSnapshot): String {
        val players = snapshot.players
        val viewer = players.indexOfFirst { snapshot.isViewer(it.playerId) }
        if (!snapshot.isSpectating || viewer < 0) return snapshot.viewerID
        for (offset in 1 until maxOf(players.size, 1)) {
            val player = players[(viewer + offset) % players.size]
            // Someone else must stay for the top of the board.
            if (!player.isOut && players.any { !snapshot.isViewer(it.playerId) && it.playerId != player.playerId }) return player.playerId
        }
        return snapshot.viewerID
    }

    /** Players the top of the board can show: everyone but the viewer and the bottom seat. */
    fun opponents(snapshot: GameSnapshot): List<PlayerGameState> {
        val seat = seatPlayerID(snapshot)
        return snapshot.players.filter { !snapshot.isViewer(it.playerId) && it.playerId != seat }
    }

    fun snapshot(snapshot: GameSnapshot, selecting: String?): GameSnapshot {
        val seat = seatPlayerID(snapshot)
        val selected = selecting?.takeIf { id -> opponents(snapshot).any { it.playerId == id } }
        return snapshot.copy(seatPlayerId = if (snapshot.isViewer(seat)) null else seat, selectedOpponentId = selected ?: snapshot.selectedOpponentId)
    }

    /** The bottom seat's hand as cards. A stand-in's hand is hidden: the board shows its count only. */
    fun seatHand(snapshot: GameSnapshot): List<ZoneCard> =
        if (snapshot.isViewer(snapshot.seatID)) snapshot.seat?.zones?.hand ?: emptyList() else emptyList()

    /** The viewer is answering a prompt, so the board holds still under their finger. */
    fun viewerIsAnswering(snapshot: GameSnapshot): Boolean {
        if (snapshot.isCompleted) return false
        val prompt = snapshot.promptEnvelopeV2 ?: return false
        return snapshot.isViewer(prompt.playerId)
    }
}

/**
 * The top of the board follows the turn: when a turn starts it shows the active player, unless
 * that is the viewer (or the stand-in at the bottom), where it keeps the last one shown. A tap on
 * another opponent sticks until the next turn starts. The switch never happens while the viewer
 * answers a prompt; it waits until the prompt is answered. (Swift BoardFocusTracker, a value
 * type here too, so it can live in Compose state.)
 */
data class BoardFocusTracker(
    /** The opponent the viewer picked or the turn moved to; null shows the first opponent. */
    val focusedID: String? = null,
    private val gameID: String? = null,
    private val turnKey: String? = null,
    private val switchPending: Boolean = false,
) {
    /** A tap on an opponent. It replaces any switch still waiting on a prompt. */
    fun select(playerID: String): BoardFocusTracker = copy(focusedID = playerID, switchPending = false)

    fun observe(snapshot: GameSnapshot, followTurns: Boolean): BoardFocusTracker {
        var next = if (snapshot.id != gameID) BoardFocusTracker(gameID = snapshot.id) else this
        val key = "${snapshot.turn}:${snapshot.activePlayerId ?: ""}"
        if (key != next.turnKey) next = next.copy(turnKey = key, switchPending = snapshot.activePlayerId != null)
        if (!followTurns) return next.copy(switchPending = false)
        if (!next.switchPending || BoardOpponentFocus.viewerIsAnswering(snapshot)) return next
        val active = snapshot.activePlayerId
        val switched = active != null && BoardOpponentFocus.opponents(snapshot).any { it.playerId == active }
        return next.copy(focusedID = if (switched) active else next.focusedID, switchPending = false)
    }

    companion object {
        const val followTurnsKey = "magicmobile.followTurns"

        /** Changes whenever a poll could move the focus; the board observes each new value. */
        fun observationKey(snapshot: GameSnapshot, followTurns: Boolean): String =
            "${snapshot.id}|${snapshot.turn}|${snapshot.activePlayerId ?: ""}|${BoardOpponentFocus.viewerIsAnswering(snapshot)}|" +
                "${BoardOpponentFocus.seatPlayerID(snapshot)}|$followTurns"
    }
}

/** The bar that replaces the viewer's controls while they watch: whose seat the bottom shows. */
object SpectatorSeatPresentation {
    fun title(snapshot: GameSnapshot): String {
        val seat = snapshot.seat
        if (seat == null || snapshot.isViewer(seat.playerId)) return "Watching"
        return "Watching ${snapshot.playerLabel(seat.playerId)}"
    }

    fun detail(snapshot: GameSnapshot): String {
        val count = snapshot.remainingOpponents.size
        val players = if (count == 1) "1 player still in" else "$count players still in"
        val seat = snapshot.seat
        if (seat == null || snapshot.isViewer(seat.playerId)) return "You’re out · $players · Turn ${snapshot.turn}"
        // The hand row already shows the stand-in's hand count; this line fits a phone.
        return "${seat.life} life · $players · Turn ${snapshot.turn}"
    }
}

object PromptCommandBuilder {
    fun isCommanderReplacement(prompt: PromptEnvelopeV2): Boolean =
        (prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()) == "commander_replacement"

    fun command(gameId: String, promptEnvelope: PromptEnvelopeV2?, type: String, promptId: String, playerId: String,
                ids: List<String> = emptyList(), amount: Int? = null, amounts: List<Int>? = null, pile: Int? = null,
                useCommandZone: Boolean? = null, manaType: String? = null, pay: Boolean? = null): GameCommand? {
        val t = type.lowercase()
        val messageId = resolvedMessageId(promptEnvelope, promptId)
        fun base(): GameCommand = GameCommand(type = t, gameId = gameId, playerId = playerId, promptId = promptId, messageId = messageId)
        return when (t) {
            "resolve_choice" -> base().copy(choiceIds = ids)
            "choose_target" -> base().copy(targetIds = ids)
            "choose_card" -> base().copy(cardInstanceIds = ids)
            "choose_player" -> base().copy(playerIds = ids)
            "choose_mode" -> base().copy(modeIds = ids)
            "choose_ability" -> ids.firstOrNull()?.let { base().copy(abilityId = it) }
            "choose_pile" -> (pile ?: ids.firstOrNull()?.toIntOrNull())?.takeIf { it == 1 || it == 2 }?.let { base().copy(pile = it) }
            "choose_amount", "play_x_mana" -> (amount ?: ids.firstOrNull()?.toIntOrNull())?.let { base().copy(amount = it) }
            "choose_multi_amount" -> {
                val choices = amounts ?: ids.mapNotNull { it.toIntOrNull() }
                if (choices.isEmpty() || (amounts == null && choices.size != ids.size)) null else base().copy(amounts = choices)
            }
            "play_mana" -> exactManaSymbol(manaType)?.let { base().copy(manaType = it) }
            "choose_mana" -> {
                val choices = manaType?.let { listOf(it) } ?: ids
                val exact = choices.mapNotNull(::exactManaSymbol)
                if (exact.isEmpty() || exact.size != choices.size) null else base().copy(manaTypes = exact)
            }
            "search_select" -> base().copy(cardInstanceIds = ids)
            "order_triggers", "order_items" -> base().copy(orderedIds = ids)
            "commander_replacement" -> useCommandZone?.let { base().copy(useCommandZone = it) }
            "pay_cost" -> (pay ?: boolChoice(ids.firstOrNull()))?.let { base().copy(confirmed = it, pay = it) }
            "answer_yes_no" -> boolChoice(ids.firstOrNull())?.let { base().copy(confirmed = it) }
            else -> null
        }
    }

    fun idCommandType(preferred: String?, fallback: String): String {
        val p = preferred?.lowercase() ?: return fallback
        return if (p in setOf("resolve_choice", "choose_target", "choose_card", "choose_player", "choose_mode", "choose_ability",
                "search_select", "order_triggers", "order_items", "answer_yes_no")) p else fallback
    }

    fun amountCommandType(preferred: String?): String {
        val p = preferred?.lowercase() ?: return "choose_amount"
        return if (p in setOf("choose_amount", "choose_multi_amount", "play_x_mana")) p else "choose_amount"
    }

    fun exactManaSymbol(value: String?): String? = value?.takeIf { it in setOf("W", "U", "B", "R", "G", "C") }

    fun boolChoice(value: String?): Boolean? = when (value?.trim()?.lowercase()) {
        "true", "yes" -> true; "false", "no" -> false; else -> null
    }

    fun canSubmitShownOrder(ids: List<String>): Boolean = ids.size == 1
    fun defaultMultiAmountValue(slot: XmagePromptMultiAmount): Int = minOf(maxOf(slot.defaultValue ?: slot.min, slot.min), slot.max)
    fun adjustedMultiAmountValue(value: Int, delta: Int, slot: XmagePromptMultiAmount): Int = minOf(maxOf(value + delta, slot.min), slot.max)

    fun isValidMultiAmountValues(values: List<Int>, slots: List<XmagePromptMultiAmount>, totalMin: Int?, totalMax: Int?): Boolean {
        if (values.size != slots.size || values.isEmpty()) return false
        slots.forEachIndexed { i, slot -> if (values[i] < slot.min || values[i] > slot.max) return false }
        val total = values.sum()
        if (totalMin != null && total < totalMin) return false
        if (totalMax != null && total > totalMax) return false
        return true
    }

    fun movedOrder(ids: List<String>, from: Int, to: Int): List<String> {
        if (from !in ids.indices || to !in ids.indices || from == to) return ids
        return ids.toMutableList().apply { add(to, removeAt(from)) }
    }

    fun isCombatDamageAllocationPrompt(prompt: PromptEnvelopeV2, phase: String?, step: String?): Boolean {
        val type = prompt.responseCommand?.type?.lowercase() ?: ""
        val kind = prompt.responseKind.lowercase()
        if (type == "damage_assignment" || kind == "damage_assignment" || prompt.message.lowercase().contains("assign damage")) return true
        val phaseStep = "${phase ?: ""} ${step ?: ""}".lowercase()
        return prompt.method.lowercase() == "game_get_multi_amount" && type == "choose_multi_amount" &&
            phaseStep.contains("combat") && phaseStep.contains("damage") && prompt.multiAmounts?.isNotEmpty() == true
    }

    fun hasPrebuiltCombatPayload(action: LegalAction): Boolean = when (action.type) {
        "declare_attackers" -> action.attackers?.isNotEmpty() == true || action.commandTemplate?.get("attackers").array?.isNotEmpty() == true
        "declare_blockers" -> action.blockers?.isNotEmpty() == true || action.commandTemplate?.get("blockers").array?.isNotEmpty() == true
        else -> false
    }

    private fun resolvedMessageId(prompt: PromptEnvelopeV2?, promptId: String): Int? {
        prompt ?: return null
        return if (prompt.id == promptId || prompt.responseCommand?.promptId == promptId) prompt.responseCommand?.messageId ?: prompt.messageId else null
    }
}

object UniversalPromptResponseCommandBuilder {
    fun command(gameId: String, bridgeRevision: Int?, promptEnvelope: PromptEnvelopeV2?, type: String, promptId: String, playerId: String,
                ids: List<String> = emptyList(), amount: Int? = null, amounts: List<Int>? = null, pile: Int? = null,
                useCommandZone: Boolean? = null, manaType: String? = null, pay: Boolean? = null): GameCommand? {
        val command = PromptCommandBuilder.command(gameId, promptEnvelope, type, promptId, playerId, ids, amount, amounts, pile,
            useCommandZone, manaType, pay) ?: return null
        return if (bridgeRevision == null) command else command.copy(expectedBridgeRevision = bridgeRevision)
    }
}

object PromptSelectionRules {
    fun isValidSelectedCount(count: Int, minChoices: Int?, maxChoices: Int?): Boolean =
        minChoices != null && maxChoices != null && count >= minChoices && count <= maxChoices

    fun selectedPromptCardId(selectedCard: ZoneCard?, validCards: List<ZoneCard>): String? {
        selectedCard ?: return null
        val valid = validCards.flatMap { listOf(it.id, it.instanceId) }.toSet()
        return if (valid.contains(selectedCard.id) || valid.contains(selectedCard.instanceId)) selectedCard.instanceId else null
    }

    fun boundsText(minChoices: Int?, maxChoices: Int?): String =
        if (minChoices == null || maxChoices == null) "min/max unavailable" else "min $minChoices / max $maxChoices"
}
