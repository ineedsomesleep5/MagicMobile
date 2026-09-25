@file:Suppress("PropertyName")
package io.magicmobile.android.game

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * Port of apps/ios/MagicMobile/Models.swift (the board's game model). Field names match the
 * Swift Codable keys, so the same JSON decodes the same way on both platforms. Types that only
 * served the retired server gateway are not ported.
 */
@Serializable
enum class AiDifficulty { @SerialName("easy") EASY, @SerialName("normal") NORMAL, @SerialName("hard") HARD, @SerialName("expert") EXPERT;
    val rawValue: String get() = name.lowercase()
    val displayName: String get() = when (this) { EASY -> "Easy"; NORMAL -> "Normal"; HARD -> "Hard"; EXPERT -> "Expert" }
}

@Serializable
data class EngineHealth(val status: String, val reason: String, val checkedAt: String, val recoveryAction: String? = null)

@Serializable
enum class GameStatus { @SerialName("in_progress") IN_PROGRESS, @SerialName("completed") COMPLETED }

@Serializable
data class GameSnapshot(
    val id: String,
    val source: String? = null,
    val activePlayerId: String? = null,
    val phase: String,
    val step: String? = null,
    val turn: Int,
    val priorityPlayerId: String? = null,
    val waitingOnPlayerId: String? = null,
    val promptText: String? = null,
    val players: List<PlayerGameState>,
    val log: List<GameLogEntry>,
    val legalActions: List<LegalAction>? = null,
    val choicePrompt: ChoicePrompt? = null,
    val promptEnvelope: PromptEnvelope? = null,
    val promptEnvelopeV2: PromptEnvelopeV2? = null,
    val startupOpeningPrompts: List<StartupOpeningPrompt>? = null,
    val xmage: XmageMobileSnapshot? = null,
    val engineHealth: EngineHealth? = null,
    val bridgeRevision: Int? = null,
    val xmageCycle: Int? = null,
    val pendingStatus: String? = null,
    val manaPayment: ManaPayment? = null,
    val gameStatus: GameStatus? = null,
    val winnerPlayerIds: List<String>? = null,
    val endReason: String? = null,
    val viewerPlayerId: String? = null,
    val selectedOpponentId: String? = null,
) {
    val viewerID: String get() = viewerPlayerId ?: "human"
    fun isViewer(playerID: String?): Boolean = playerID == viewerID
    fun playerLabel(playerID: String?): String {
        if (playerID == null) return "Waiting"
        if (isViewer(playerID)) return "You"
        return players.firstOrNull { it.playerId == playerID }?.displayName ?: playerID
    }
    val human: PlayerGameState? get() = players.firstOrNull { it.playerId == viewerID }
    val opponent: PlayerGameState? get() {
        val selected = selectedOpponentId
        if (selected != null && selected != viewerID) players.firstOrNull { it.playerId == selected }?.let { return it }
        return players.firstOrNull { it.playerId != viewerID }
    }
    val isCompleted: Boolean get() = gameStatus == GameStatus.COMPLETED
    val stackTopFirst: List<XmageStackObject> get() {
        val objects = xmage?.stack ?: emptyList()
        return if (source == "xmage-ondevice") objects else objects.reversed()
    }
    /** The viewer conceded or was eliminated and the others play on: watch, never act. */
    val isSpectating: Boolean get() = human?.isOut == true && !isCompleted
    /** An AI opponent holds priority and the game waits on its decision. */
    val thinkingPlayerID: String? get() {
        if (isCompleted) return null
        val id = priorityPlayerId ?: return null
        if (isViewer(id) || promptEnvelopeV2 != null) return null
        val player = players.firstOrNull { it.playerId == id } ?: return null
        return if (player.isHuman == false && !player.isOut) id else null
    }
    /** Opponents still in the game. */
    val remainingOpponents: List<PlayerGameState> get() = players.filter { !isViewer(it.playerId) && !it.isOut }
    val winnerDisplayNames: List<String> get() {
        val winners = (winnerPlayerIds ?: emptyList()).toSet()
        return players.mapNotNull { if (winners.contains(it.playerId)) playerLabel(it.playerId) else null }
    }
    val isStalled: Boolean get() = pendingStatus == "stalled" || engineHealth?.status == "stalled"
    val isWaitingOnAIOrStalled: Boolean get() = isStalled || priorityPlayerId == "ai-1" || waitingOnPlayerId == "ai-1"
    val aiWaitSignature: String get() =
        "$id|$turn|$phase|${step ?: ""}|${priorityPlayerId ?: ""}|${waitingOnPlayerId ?: ""}|${pendingStatus ?: ""}|${engineHealth?.status ?: ""}|${bridgeRevision ?: -1}|${xmageCycle ?: -1}"
}

enum class MobilePromptKind { PAYMENT, TARGET, CONFIRMATION, CARD_CHOICE, PLAYER_CHOICE, ABILITY_CHOICE, ORDER, AMOUNT, MULTI_AMOUNT, PILE, SEARCH, COMBAT, UNSUPPORTED }

data class MobilePromptPresentation(val kind: MobilePromptKind, val title: String, val message: String,
                                    val requiresDetail: Boolean, val isUnsupported: Boolean) {
    companion object {
        fun make(snapshot: GameSnapshot, legalActions: List<LegalAction>): MobilePromptPresentation? {
            if (isCombatSelection(snapshot, legalActions)) {
                val isBlock = legalActions.any { it.type == "declare_blockers" } || normalizedStep(snapshot).contains("declare-block")
                return MobilePromptPresentation(MobilePromptKind.COMBAT, if (isBlock) "Select blockers" else "Select attackers",
                    snapshot.promptText ?: if (isBlock) "Choose blockers" else "Choose attackers", false, false)
            }
            val prompt = snapshot.promptEnvelopeV2 ?: return null
            val kind = kind(prompt)
            val detailKinds = setOf(MobilePromptKind.CARD_CHOICE, MobilePromptKind.PLAYER_CHOICE, MobilePromptKind.ABILITY_CHOICE,
                MobilePromptKind.ORDER, MobilePromptKind.AMOUNT, MobilePromptKind.MULTI_AMOUNT, MobilePromptKind.PILE,
                MobilePromptKind.SEARCH, MobilePromptKind.TARGET, MobilePromptKind.UNSUPPORTED)
            return MobilePromptPresentation(kind, title(kind, prompt), prompt.message,
                detailKinds.contains(kind) || optionCount(prompt) > 3, kind == MobilePromptKind.UNSUPPORTED)
        }

        fun kind(prompt: PromptEnvelopeV2): MobilePromptKind {
            val type = prompt.responseCommand?.type?.lowercase() ?: ""
            val kind = prompt.responseKind.lowercase()
            val method = prompt.method.uppercase()
            if (type == "play_mana" || type == "choose_mana" || type == "pay_cost" || type == "play_x_mana" ||
                kind == "mana" || kind == "pay_cost" || kind == "cost" || kind == "x_mana" ||
                method == "GAME_PLAY_MANA" || method == "GAME_PLAY_XMANA") return MobilePromptKind.PAYMENT
            if (type == "choose_target" || kind == "target" || method.contains("TARGET") || prompt.targets?.isNotEmpty() == true ||
                prompt.targetIds?.isNotEmpty() == true) return MobilePromptKind.TARGET
            if (type == "answer_yes_no" || kind == "confirmation" || prompt.confirmation != null) return MobilePromptKind.CONFIRMATION
            if (type == "choose_player" || kind == "player" || prompt.players?.isNotEmpty() == true) return MobilePromptKind.PLAYER_CHOICE
            if (type == "choose_ability" || kind == "ability" || prompt.abilities?.isNotEmpty() == true) return MobilePromptKind.ABILITY_CHOICE
            if (type == "order_triggers" || type == "order_items" || kind == "order" || prompt.orderedItems?.isNotEmpty() == true) return MobilePromptKind.ORDER
            if (type == "choose_multi_amount" || kind == "multi_amount" || prompt.multiAmounts?.isNotEmpty() == true) return MobilePromptKind.MULTI_AMOUNT
            if (type == "choose_amount" || kind == "amount" || prompt.amounts?.isNotEmpty() == true) return MobilePromptKind.AMOUNT
            if (type == "choose_pile" || kind == "pile" || prompt.piles?.isNotEmpty() == true) return MobilePromptKind.PILE
            if (type == "search_select" || kind == "search") return MobilePromptKind.SEARCH
            if (type == "choose_card" || kind == "card" || prompt.cards?.isNotEmpty() == true || prompt.choices?.isNotEmpty() == true ||
                prompt.modes?.isNotEmpty() == true) return MobilePromptKind.CARD_CHOICE
            return MobilePromptKind.UNSUPPORTED
        }

        private fun title(kind: MobilePromptKind, prompt: PromptEnvelopeV2): String {
            if (prompt.message.lowercase().contains("starting player")) return "Starting player"
            return when (kind) {
                MobilePromptKind.PAYMENT -> "Pay cost"
                MobilePromptKind.TARGET -> "Select target"
                MobilePromptKind.CONFIRMATION -> "Confirm choice"
                MobilePromptKind.CARD_CHOICE -> if (prompt.modes?.isNotEmpty() == true) "Choose mode" else if (prompt.cards?.isNotEmpty() == true) "Choose card" else "Make a choice"
                MobilePromptKind.PLAYER_CHOICE -> "Choose player"
                MobilePromptKind.ABILITY_CHOICE -> "Choose ability"
                MobilePromptKind.ORDER -> "Order choices"
                MobilePromptKind.AMOUNT -> "Choose amount"
                MobilePromptKind.MULTI_AMOUNT -> "Assign amounts"
                MobilePromptKind.PILE -> "Choose pile"
                MobilePromptKind.SEARCH -> "Search"
                MobilePromptKind.COMBAT -> "Combat"
                MobilePromptKind.UNSUPPORTED -> if (prompt.responseKind.isEmpty()) "XMage prompt" else capitalizedWords(prompt.responseKind.replace("_", " "))
            }
        }

        private fun optionCount(prompt: PromptEnvelopeV2): Int =
            (prompt.choices?.size ?: 0) + (prompt.cards?.size ?: 0) + (prompt.targets?.size ?: 0) + (prompt.players?.size ?: 0) +
                (prompt.abilities?.size ?: 0) + (prompt.piles?.size ?: 0) + (prompt.amounts?.size ?: 0) +
                (prompt.multiAmounts?.size ?: 0) + (prompt.orderedItems?.size ?: 0)

        private fun isCombatSelection(snapshot: GameSnapshot, legalActions: List<LegalAction>): Boolean =
            legalActions.any { it.type == "declare_attackers" || it.type == "declare_blockers" } ||
                ((snapshot.isViewer(snapshot.waitingOnPlayerId) || snapshot.isViewer(snapshot.priorityPlayerId)) &&
                    (normalizedStep(snapshot).contains("declare-attack") || normalizedStep(snapshot).contains("declare-block")))

        private fun normalizedStep(snapshot: GameSnapshot): String = "${snapshot.step ?: ""} ${snapshot.promptText ?: ""}".lowercase()
    }
}

enum class XmageWaitKind { YOUR_PRIORITY, XMAGE_THINKING, WAITING_FOR_BRIDGE, BRIDGE_DISCONNECTED, ACTION_STILL_RESOLVING, SNAPSHOT_STALE, MANUAL_RECONNECT_AVAILABLE }

data class XmageWaitPresentation(val kind: XmageWaitKind, val title: String, val detail: String) {
    companion object {
        fun make(snapshot: GameSnapshot, pendingActionId: String?, liveUpdateStatus: String, elapsedSeconds: Double = 0.0,
                 didRefresh: Boolean = false, didReconnect: Boolean = false, didDiagnose: Boolean = false): XmageWaitPresentation {
            val live = liveUpdateStatus.lowercase()
            if (live.contains("unavailable") || live.contains("disconnect")) return XmageWaitPresentation(XmageWaitKind.BRIDGE_DISCONNECTED, "Bridge disconnected", "Reconnect live updates.")
            if (pendingActionId != null) return XmageWaitPresentation(XmageWaitKind.ACTION_STILL_RESOLVING, "Action still resolving", "Waiting for XMage to advance.")
            if (snapshot.pendingStatus == "waiting_for_xmage") return XmageWaitPresentation(XmageWaitKind.WAITING_FOR_BRIDGE, "Waiting for bridge", "XMage accepted the command.")
            if (elapsedSeconds >= AIWaitRecoveryPolicy.diagnoseThresholdSeconds && didRefresh && didReconnect && didDiagnose) {
                return XmageWaitPresentation(XmageWaitKind.MANUAL_RECONNECT_AVAILABLE, "Manual reconnect available", "Automatic refresh, reconnect, and health check already ran.")
            }
            if (snapshot.isStalled) return XmageWaitPresentation(XmageWaitKind.SNAPSHOT_STALE, "Snapshot stale", "Refresh or reconnect to recover.")
            if (snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId)) {
                return XmageWaitPresentation(XmageWaitKind.YOUR_PRIORITY, "Your priority", "Choose an action.")
            }
            return XmageWaitPresentation(XmageWaitKind.XMAGE_THINKING, "XMage thinking", "Waiting for AI or rules resolution.")
        }
    }
}

/** Authoritative mana-payment state: present and `active` only while the viewer is mid-payment. */
@Serializable
data class ManaPayment(val active: Boolean, val spellName: String? = null, val manaCostText: String? = null,
                       val remainingText: String? = null, val remaining: ManaPips? = null)

class PromptAmountBounds(minimum: Int?, maximum: Int?) {
    val minimum: Int = maxOf(Int.MIN_VALUE, minimum ?: 0)
    val maximum: Int = maxOf(this.minimum, minOf(Int.MAX_VALUE, maximum ?: Int.MAX_VALUE))
    fun clamp(value: Int): Int = minOf(maximum, maxOf(minimum, value))
    fun stepping(value: Int, delta: Int): Int {
        val next = value.toLong() + delta.toLong()
        return if (next > Int.MAX_VALUE || next < Int.MIN_VALUE) (if (delta < 0) minimum else maximum) else clamp(next.toInt())
    }
}

@Serializable
data class ManaPips(val generic: Int, val W: Int, val U: Int, val B: Int, val R: Int, val G: Int, val C: Int, val total: Int) {
    /** Ordered (symbol, count) pairs for rendering, WUBRG then C. */
    val orderedColors: List<Pair<String, Int>> get() = listOf("W" to W, "U" to U, "B" to B, "R" to R, "G" to G, "C" to C).filter { it.second > 0 }
}

@Serializable
data class StartupOpeningPrompt(val promptId: String? = null, val method: String? = null, val responseKind: String? = null,
                                val message: String? = null, val playerId: String? = null, val bridgeRevision: Int? = null,
                                val xmageCycle: Int? = null)

enum class CastSubmissionOutcome {
    ACCEPTED, PAYMENT, TARGETING, WAITING, REJECTED_STILL_IN_HAND, NOT_CAST_OR_PLAY;
    val statusMessage: String get() = when (this) {
        ACCEPTED -> "XMage accepted the play"
        PAYMENT -> "Tap mana sources to pay"
        TARGETING -> "Choose a highlighted XMage target"
        WAITING -> "Waiting for XMage update"
        REJECTED_STILL_IN_HAND -> "Cast did not progress. Refresh and try again."
        NOT_CAST_OR_PLAY -> "Action submitted"
    }
}

object CastSubmissionClassifier {
    fun classify(action: LegalAction, before: GameSnapshot, after: GameSnapshot): CastSubmissionOutcome {
        if (action.type !in setOf("cast_spell", "play_land")) return CastSubmissionOutcome.NOT_CAST_OR_PLAY
        if (isPaymentPrompt(after.promptEnvelopeV2)) return CastSubmissionOutcome.PAYMENT
        if (isTargetPrompt(after.promptEnvelopeV2)) return CastSubmissionOutcome.TARGETING
        if (isActionableFollowUpPrompt(after.promptEnvelopeV2)) return CastSubmissionOutcome.WAITING
        if (after.pendingStatus == "waiting_for_xmage") return CastSubmissionOutcome.WAITING
        val cardId = action.effectiveCardInstanceId ?: action.effectiveSourceInstanceId ?: return CastSubmissionOutcome.ACCEPTED
        val wasInHand = before.human?.zones?.hand?.any { it.instanceId == cardId } == true
        val stillInHand = after.human?.zones?.hand?.any { it.instanceId == cardId } == true
        return if (wasInHand && stillInHand) CastSubmissionOutcome.REJECTED_STILL_IN_HAND else CastSubmissionOutcome.ACCEPTED
    }
    fun shouldKeepPollingForCastOutcome(action: LegalAction, before: GameSnapshot, after: GameSnapshot): Boolean =
        action.type in setOf("cast_spell", "play_land") && classify(action, before, after) == CastSubmissionOutcome.REJECTED_STILL_IN_HAND
    fun isPaymentPrompt(prompt: PromptEnvelopeV2?): Boolean {
        prompt ?: return false
        val method = prompt.method.uppercase()
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        return method == "GAME_PLAY_MANA" || method == "GAME_PLAY_XMANA" || type in setOf("play_mana", "choose_mana", "pay_cost", "play_x_mana", "mana", "x_mana")
    }
    fun isTargetPrompt(prompt: PromptEnvelopeV2?): Boolean {
        prompt ?: return false
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        return prompt.method.uppercase().contains("TARGET") || type == "choose_target" || type == "target"
    }
    fun isActionableFollowUpPrompt(prompt: PromptEnvelopeV2?): Boolean {
        prompt ?: return false
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        val actionable = setOf("answer_yes_no", "choose_ability", "choose_amount", "choose_card", "choose_mode", "choose_multi_amount",
            "choose_pile", "choose_player", "commander_replacement", "generic_replacement", "order_items", "order_triggers",
            "pay_cost", "play_x_mana", "resolve_choice", "search_select")
        if (type !in actionable) return false
        val hasChoices = prompt.choices?.isNotEmpty() == true || prompt.cards?.isNotEmpty() == true || prompt.targets?.isNotEmpty() == true ||
            prompt.players?.isNotEmpty() == true || prompt.piles?.isNotEmpty() == true || prompt.abilities?.isNotEmpty() == true ||
            prompt.modes?.isNotEmpty() == true || prompt.multiAmounts?.isNotEmpty() == true || prompt.targetIds?.isNotEmpty() == true ||
            (prompt.minChoices ?: 0) > 0 || prompt.required == true
        return hasChoices || prompt.responseCommand != null
    }
}

enum class AIWaitRecoveryAction { NONE, REFRESH, RECONNECT, DIAGNOSE }

object AIWaitRecoveryPolicy {
    const val refreshThresholdSeconds = 10.0
    const val reconnectThresholdSeconds = 20.0
    const val diagnoseThresholdSeconds = 30.0
    fun action(snapshot: GameSnapshot, elapsedSeconds: Double, didRefresh: Boolean, didReconnect: Boolean, didDiagnose: Boolean = false): AIWaitRecoveryAction {
        if (!snapshot.isWaitingOnAIOrStalled) return AIWaitRecoveryAction.NONE
        if (elapsedSeconds >= diagnoseThresholdSeconds && didRefresh && didReconnect && !didDiagnose) return AIWaitRecoveryAction.DIAGNOSE
        if (elapsedSeconds >= reconnectThresholdSeconds && didRefresh && !didReconnect) return AIWaitRecoveryAction.RECONNECT
        if (elapsedSeconds >= refreshThresholdSeconds && !didRefresh) return AIWaitRecoveryAction.REFRESH
        return AIWaitRecoveryAction.NONE
    }
}

@Serializable
data class GameLogEntry(val id: String, val message: String, val createdAt: String? = null)

@Serializable
data class PlayerGameState(
    val playerId: String,
    val displayName: String? = null,
    val life: Int,
    val poison: Int,
    val commanderTax: Int,
    val manaPool: ManaPool? = null,
    val zones: PlayerZones,
    val commanderDamage: Map<String, Int>? = null,
    val commanderTaxKnown: Boolean? = null,
    val commanders: List<CommanderPublicState>? = null,
    val counters: Map<String, Int>? = null,
    val monarch: Boolean? = null,
    val initiative: Boolean? = null,
    /** XMage removed this player from the game: they conceded or lost while others play on. */
    val hasLeft: Boolean? = null,
    /** False for the engine's AI seats. */
    val isHuman: Boolean? = null,
) {
    val hasKnownCommanderTax: Boolean get() = commanderTaxKnown ?: true
    val isOut: Boolean get() = hasLeft == true
    val id: String get() = playerId
}

@Serializable
data class CommanderPublicState(val id: String, val name: String? = null, val ownerPlayerId: String, val castsFromCommandZone: Int? = null,
                                val commanderTax: Int? = null, val damageToPlayers: Map<String, Int>? = null)

@Serializable
data class ManaPool(val W: Int, val U: Int, val B: Int, val R: Int, val G: Int, val C: Int)

@Serializable
data class PlayerZones(
    val library: List<ZoneCard>, val hand: List<ZoneCard>, val battlefield: List<ZoneCard>, val graveyard: List<ZoneCard>,
    val exile: List<ZoneCard>, val command: List<ZoneCard>, val stack: List<ZoneCard>,
    val handCount: Int? = null, val libraryCount: Int? = null,
) {
    val visibleHandCount: Int get() = handCount ?: hand.size
    val visibleLibraryCount: Int get() = libraryCount ?: library.size
}

@Serializable
data class ZoneCard(
    val instanceId: String,
    val card: CardIdentity,
    val tapped: Boolean? = null,
    val summoningSickness: Boolean? = null,
    val cardIcons: List<XmageCardIcon>? = null,
    val counters: Map<String, Int>? = null,
    val power: Int? = null,
    val toughness: Int? = null,
    val isCreaturePermanent: Boolean? = null,
    val damage: Int? = null,
    val isAttacking: Boolean? = null,
    val blocking: List<String>? = null,
    val attachedToInstanceId: String? = null,
    val selectable: Boolean? = null,
    val disabledReason: String? = null,
    val reportedPower: String? = null,
    val reportedToughness: String? = null,
    val phasedIn: Boolean? = null,
) {
    val isPhasedOut: Boolean get() = phasedIn == false
    val displayPower: String? get() = reportedPower ?: power?.toString()
    val displayToughness: String? get() = reportedToughness ?: toughness?.toString()
    val id: String get() = instanceId
    val isCreature: Boolean get() = isCreaturePermanent ?: card.isCreature
    val showsPowerToughness: Boolean get() = displayPower != null && displayToughness != null && isCreature
    val isPromptSelectable: Boolean get() = selectable ?: true
    val isSyntheticStackAbilityPlaceholder: Boolean get() {
        val name = card.name.trim().lowercase()
        val type = card.typeLine.trim().lowercase()
        return name == "ability" || name == "activated ability" || name == "triggered ability" || type == "card"
    }

    /** Engine icons in the ability and commander categories, plus keyword icons from bare keyword rules lines. */
    val visibleXmageIcons: List<XmageCardIcon> get() {
        val engine = (cardIcons ?: emptyList()).filter { icon ->
            val category = icon.category
            (category.equals("ABILITY", ignoreCase = true) || category.equals("COMMANDER", ignoreCase = true)) &&
                (XmageCardIcon.assetName(icon.iconType) != null || icon.textBadge != null)
        }
        val present = engine.map { it.iconType.uppercase() }.toSet()
        return engine + XmageCardIcon.keywordIcons(card.oracleText).filter { !present.contains(it.iconType) }
    }

    val counterBadges: List<CardCounterBadge> get() = (counters ?: emptyMap()).filter { it.value > 0 }
        .map { CardCounterBadge(it.key, it.value) }
        .sortedWith(compareBy<CardCounterBadge> { it.priority }.thenBy { it.label })

    fun accessibilityLabel(zoneName: String? = null, selected: Boolean = false, legal: Boolean = false, pending: Boolean = false): String {
        val parts = mutableListOf("${if (zoneName.isNullOrEmpty()) "Game" else zoneName} card", card.name)
        if (card.typeLine.isNotEmpty()) parts += card.typeLine
        if (tapped == true) parts += "tapped"
        if (summoningSickness == true) parts += "summoning sick"
        parts += visibleXmageIcons.mapNotNull { it.displayText }
        if (isAttacking == true) parts += "attacking"
        if (showsPowerToughness) parts += "$displayPower/$displayToughness"
        parts += counterBadges.map { "${it.label} counter ${it.count}" }
        if (legal) parts += "playable"
        if (pending) parts += "pending"
        if (selected) parts += "selected"
        return parts.joinToString(", ")
    }

    fun accessibilityIdentifier(zoneName: String? = null): String {
        val zone = slug(if (zoneName.isNullOrEmpty()) "game" else zoneName)
        return "card-$zone-${slug(card.name)}-${slug(instanceId.take(8))}"
    }

    companion object {
        private fun slug(value: String): String = value.lowercase().map { if (it.isLetterOrDigit()) it else '-' }
            .joinToString("").split('-').filter { it.isNotEmpty() }.joinToString("-")

        /** Attachment chains can end at a player (a Curse) or another permanent. Cycles never match. */
        fun enchanting(playerID: String, cards: List<ZoneCard>): List<ZoneCard> {
            val byID = LinkedHashMap<String, ZoneCard>()
            cards.forEach { byID.putIfAbsent(it.instanceId, it) }
            return cards.filter { card ->
                var parent = card.attachedToInstanceId
                val visited = mutableSetOf(card.instanceId)
                while (parent != null) {
                    if (parent == playerID) return@filter true
                    if (!visited.add(parent)) return@filter false
                    parent = byID[parent]?.attachedToInstanceId
                }
                false
            }
        }
    }
}

@Serializable
data class CardIdentity(
    val name: String,
    val typeLine: String,
    val oracleText: String? = null,
    /** CardView's visible face cost, not the cost to pay after modifiers or taxes. */
    val manaCost: String? = null,
    val isToken: Boolean? = null,
    val tokenColors: List<String>? = null,
    val copySourceArtworkName: String? = null,
    val tokenArtwork: TokenArtworkIdentity? = null,
) {
    val isLand: Boolean get() = typeLine.contains("land", ignoreCase = true)
    val isCreature: Boolean get() = typeLine.contains("creature", ignoreCase = true)
    val isPlaneswalker: Boolean get() = typeLine.contains("planeswalker", ignoreCase = true)
    val isArtifact: Boolean get() = typeLine.contains("artifact", ignoreCase = true)
    val isEnchantment: Boolean get() = typeLine.contains("enchantment", ignoreCase = true)
}

@Serializable
data class TokenArtworkIdentity(val name: String, val typeLine: String, val oracleText: String, val power: String? = null,
                                val toughness: String? = null, val colors: List<String>)

/** An integer or a numeric string (Swift `FlexibleInt`). */
@Serializable(with = FlexibleIntSerializer::class)
data class FlexibleInt(val value: Int)

object FlexibleIntSerializer : KSerializer<FlexibleInt> {
    override val descriptor = PrimitiveSerialDescriptor("FlexibleInt", PrimitiveKind.INT)
    override fun serialize(encoder: Encoder, value: FlexibleInt) = encoder.encodeInt(value.value)
    override fun deserialize(decoder: Decoder): FlexibleInt {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return FlexibleInt(decoder.decodeInt())
        val primitive = element as? JsonPrimitive ?: throw IllegalArgumentException("Expected an integer or numeric string.")
        val number = if (primitive.isString) primitive.content.toIntOrNull() else primitive.intOrNull
        return FlexibleInt(number ?: throw IllegalArgumentException("Expected an integer or numeric string."))
    }
}

@Serializable
data class LegalAction(
    val id: String,
    val type: String,
    val playerId: String,
    val label: String,
    val promptId: String? = null,
    val cardInstanceId: String? = null,
    val cardName: String? = null,
    val manaCost: String? = null,
    val sourceZone: String? = null,
    val sourceInstanceId: String? = null,
    val abilityId: String? = null,
    val targetIds: List<String>? = null,
    val validTargetIds: List<String>? = null,
    val playerIds: List<String>? = null,
    val validPlayerIds: List<String>? = null,
    val choiceIds: List<String>? = null,
    val cardInstanceIds: List<String>? = null,
    val validCardInstanceIds: List<String>? = null,
    val modeIds: List<String>? = null,
    val orderedIds: List<String>? = null,
    val amount: Int? = null,
    val amounts: List<Int>? = null,
    val multiAmounts: List<XmagePromptMultiAmount>? = null,
    val manaType: String? = null,
    val manaTypes: List<String>? = null,
    val pile: FlexibleInt? = null,
    val confirmed: Boolean? = null,
    val pay: Boolean? = null,
    val useCommandZone: Boolean? = null,
    val isPrimary: Boolean? = null,
    val requiresTarget: Boolean? = null,
    val requiresPayment: Boolean? = null,
    val producedMana: List<String>? = null,
    val responseKind: String? = null,
    val messageId: Int? = null,
    val minChoices: Int? = null,
    val maxChoices: Int? = null,
    val zoneContext: String? = null,
    val shortLabel: String? = null,
    val commandTemplate: Map<String, JsonElement>? = null,
    val attackers: List<AttackDeclaration>? = null,
    val blockers: List<BlockDeclaration>? = null,
    val defenderId: String? = null,
    val defenderKind: String? = null,
    val defenderName: String? = null,
) {
    val compactPromptTitle: String get() {
        when (type) {
            "pass_priority" -> return "Pass Priority"
            "resolve_stack", "pass_until_stack_resolved" -> return "Resolve Stack"
            "end_turn" -> return "End Turn"
            "pass_until_end_of_turn" -> return "Yield Until End Step"
            "yield_until_next_turn", "pass_until_next_turn" -> return "Yield Until Next Turn"
        }
        val trimmedLabel = label.trim()
        val trimmedShort = shortLabel?.trim()
        val generic = setOf("ability", "activated ability", "triggered ability")
        if (type in setOf("choose_ability", "activate_ability") && trimmedShort != null && generic.contains(trimmedShort.lowercase()) &&
            trimmedLabel.isNotEmpty() && !generic.contains(trimmedLabel.lowercase())) return trimmedLabel
        if (!trimmedShort.isNullOrEmpty()) return trimmedShort
        return trimmedLabel.ifEmpty { type }
    }
    val effectiveSourceInstanceId: String? get() = commandTemplate?.get("sourceInstanceId").stringValue ?: sourceInstanceId ?: cardInstanceId
    val effectiveCardInstanceId: String? get() = commandTemplate?.get("cardInstanceId").stringValue ?: cardInstanceId ?: effectiveSourceInstanceId
    val effectiveSourceZone: String? get() = commandTemplate?.get("sourceZone").stringValue ?: sourceZone
    val effectiveFromZone: String? get() = commandTemplate?.get("fromZone").stringValue ?: sourceZone
    val effectiveAbilityId: String? get() = commandTemplate?.get("abilityId").stringValue ?: abilityId
}

@Serializable
data class ChoicePrompt(val id: String, val playerId: String, val message: String, val minChoices: Int, val maxChoices: Int,
                        val choices: List<ChoicePromptOption>)

@Serializable
data class ChoicePromptOption(val id: String, val label: String, val cardInstanceId: String? = null)

@Serializable
data class PromptEnvelope(val id: String, val method: String, val messageId: Int, val playerId: String, val responseKind: String,
                          val message: String, val required: Boolean? = null, val minChoices: Int? = null, val maxChoices: Int? = null,
                          val totalMin: Int? = null, val totalMax: Int? = null, val targetIds: List<String>? = null,
                          val choices: List<ChoicePromptOption>? = null)

@Serializable
data class PromptEnvelopeV2(
    val id: String,
    val method: String,
    val messageId: Int,
    val playerId: String,
    val responseKind: String,
    val message: String,
    val required: Boolean? = null,
    val minChoices: Int? = null,
    val maxChoices: Int? = null,
    val totalMin: Int? = null,
    val totalMax: Int? = null,
    val targetIds: List<String>? = null,
    val choices: List<ChoicePromptOption>? = null,
    val responseCommand: XmageResponseCommand? = null,
    val cards: List<ZoneCard>? = null,
    val targets: List<ChoicePromptOption>? = null,
    val players: List<XmagePromptPlayer>? = null,
    val piles: List<XmagePromptPile>? = null,
    val abilities: List<XmagePromptAbility>? = null,
    val modes: List<ChoicePromptOption>? = null,
    val amounts: List<Int>? = null,
    val multiAmounts: List<XmagePromptMultiAmount>? = null,
    val manaChoices: List<XmagePromptManaChoice>? = null,
    val orderedItems: List<ChoicePromptOption>? = null,
    val confirmation: XmagePromptConfirmation? = null,
    val options: Map<String, JsonElement>? = null,
)

@Serializable
data class XmageResponseCommand(val type: String? = null, val promptId: String? = null, val messageId: Int? = null,
                                val confirmed: Boolean? = null, val pay: Boolean? = null)

@Serializable
data class XmagePromptPile(val id: String, val label: String, val cards: List<ZoneCard>) {
    val explicitPileNumber: Int? get() {
        if (id == "1" || id == "2") return id.toInt()
        val normalizedId = id.lowercase()
        if (normalizedId in setOf("pile-1", "pile_1", "pile 1")) return 1
        if (normalizedId in setOf("pile-2", "pile_2", "pile 2")) return 2
        val normalizedLabel = label.trim().lowercase()
        if (normalizedLabel in setOf("pile 1", "pile-1", "pile_1")) return 1
        if (normalizedLabel in setOf("pile 2", "pile-2", "pile_2")) return 2
        return null
    }
}

@Serializable
data class XmagePromptAbility(val id: String, val label: String, val rulesText: String? = null, val sourceInstanceId: String? = null,
                              val sourceCard: ZoneCard? = null, val sourceName: String? = null, val sourceUnavailableReason: String? = null)

@Serializable
data class XmagePromptMultiAmount(val id: String, val label: String, val min: Int, val max: Int, val defaultValue: Int? = null)

@Serializable
data class XmagePromptPlayer(val id: String, val label: String, val playerId: String, val life: Int? = null, val selectable: Boolean? = null)

@Serializable
data class XmagePromptManaChoice(val id: String, val label: String, val manaType: String? = null, val amount: Int? = null)

@Serializable
data class XmagePromptConfirmation(val yesLabel: String? = null, val noLabel: String? = null, val defaultValue: Boolean? = null,
                                   val yesCommand: XmageResponseCommand? = null, val noCommand: XmageResponseCommand? = null)

@Serializable
data class AttackDeclaration(val attackerId: String, val defenderId: String? = null)

@Serializable
data class BlockDeclaration(val blockerId: String, val attackerId: String? = null)

@Serializable
data class XmageMobileSnapshot(
    val schemaVersion: Int, val gameId: String, val bridgeRevision: Int, val xmageCycle: Int? = null,
    val callbackCoverage: List<String>, val stack: List<XmageStackObject>, val combat: List<XmageCombatGroup>,
    val players: List<XmageMobilePlayer>, val exileZones: List<XmageNamedZone>, val revealed: List<XmageNamedZone>,
    val lookedAt: List<XmageNamedZone>, val companion: List<XmageNamedZone>, val playableObjects: List<XmagePlayableObject>,
    val panels: XmagePanels,
)

@Serializable
data class XmageMobilePlayer(val playerId: String, val xmagePlayerId: String? = null, val name: String, val active: Boolean,
                             val hasPriority: Boolean, val timerActive: Boolean, val skipState: XmageSkipState, val manaPool: ManaPool,
                             val command: List<ZoneCard>, val zones: XmagePlayerZones) {
    val id: String get() = playerId
}

@Serializable
data class XmageSkipState(val passedTurn: Boolean, val passedUntilEndOfTurn: Boolean, val passedUntilNextMain: Boolean,
                          val passedUntilStackResolved: Boolean, val passedAllTurns: Boolean, val passedUntilEndStepBeforeMyTurn: Boolean)

@Serializable
data class XmagePlayerZones(val battlefield: List<ZoneCard>, val graveyard: List<ZoneCard>, val exile: List<ZoneCard>, val sideboard: List<ZoneCard>)

@Serializable
data class XmageStackObject(
    val id: String, val objectId: String? = null, val objectType: String? = null, val name: String, val rulesText: String? = null,
    val sourceInstanceId: String? = null, val sourceName: String? = null, val sourceZone: String? = null, val sourceCard: ZoneCard? = null,
    val sourceCardUnavailableReason: String? = null, val controllerId: String? = null, val controllerXmageId: String? = null,
    val targetIds: List<String>? = null, val paid: Boolean? = null,
) {
    val displayName: String get() = name.ifEmpty { "Stack object" }
    val displaySourceName: String get() = displaySourceCard?.card?.name ?: sourceName ?: "Source unavailable"
    val syntheticTileTitle: String get() = when {
        displayName.contains("ability", ignoreCase = true) -> displayName
        objectType?.contains("ability", ignoreCase = true) == true -> "Activated ability"
        else -> displayName
    }
    val syntheticTileSubtitle: String get() = sourceName?.trim()?.takeIf { it.isNotEmpty() } ?: "Stack"
    val syntheticTileDetail: String get() {
        if (!rulesText.isNullOrBlank()) return rulesText
        compactFallbackDetail?.let { return it }
        return sourceCardUnavailableReason ?: "Source card image unavailable"
    }
    val displaySourceCard: ZoneCard? get() = sourceCard?.takeUnless { it.isSyntheticStackAbilityPlaceholder }
    val compactFallbackDetail: String? get() {
        if (!sourceCardUnavailableReason.isNullOrEmpty()) return sourceCardUnavailableReason
        if (displaySourceCard == null && displaySourceName != "Source unavailable") return "Source: $displaySourceName"
        return null
    }
    val displayMetadata: String? get() {
        val parts = mutableListOf<String>()
        if (!controllerId.isNullOrEmpty()) parts += "Controller: $controllerId"
        if (!sourceZone.isNullOrEmpty()) parts += "From: $sourceZone"
        if (!targetIds.isNullOrEmpty()) parts += "Targets: ${targetIds.size}"
        return if (parts.isEmpty()) null else parts.joinToString(" | ")
    }
}

@Serializable
data class XmageCombatGroup(val defenderId: String, val defenderName: String, val defenderKind: String? = null, val blocked: Boolean,
                            val attackers: List<ZoneCard>, val blockers: List<ZoneCard>) {
    val id: String get() = defenderId
}

@Serializable
data class XmageNamedZone(val id: String, val name: String, val cards: List<ZoneCard>)

@Serializable
data class XmagePlayableObject(val sourceInstanceId: String, val sourceZone: String? = null, val cardName: String,
                               val categories: List<String>, val abilities: List<XmagePlayableAbility>) {
    val id: String get() = sourceInstanceId
}

@Serializable
data class XmagePlayableAbility(val id: String, val label: String, val category: String)

@Serializable
data class XmagePanels(val stack: Boolean, val command: Boolean, val graveyard: Boolean, val exile: Boolean, val revealed: Boolean,
                       val lookedAt: Boolean, val search: Boolean)

/** A command the board asks the session to send (Swift `GameCommand`). */
data class GameCommand(
    val type: String,
    val gameId: String,
    val playerId: String,
    val cardInstanceId: String? = null,
    val sourceInstanceId: String? = null,
    val abilityId: String? = null,
    val promptId: String? = null,
    val messageId: Int? = null,
    val choiceIds: List<String>? = null,
    val targetIds: List<String>? = null,
    val cardInstanceIds: List<String>? = null,
    val modeIds: List<String>? = null,
    val sourceInstanceIds: List<String>? = null,
    val paymentId: String? = null,
    val abilityIdChoice: String? = null,
    val pile: Int? = null,
    val amount: Int? = null,
    val amounts: List<Int>? = null,
    val orderedIds: List<String>? = null,
    val useCommandZone: Boolean? = null,
    val manaType: String? = null,
    val manaTypes: List<String>? = null,
    val playerIds: List<String>? = null,
    val confirmed: Boolean? = null,
    val pay: Boolean? = null,
    val sourceZone: String? = null,
    val fromZone: String? = null,
    val cardName: String? = null,
    val attackers: List<AttackDeclaration>? = null,
    val blockers: List<BlockDeclaration>? = null,
    val combatComplete: Boolean? = null,
    val expectedBridgeRevision: Int? = null,
)

@Serializable
data class XmageCardIcon(val iconType: String, val resourceName: String? = null, val category: String? = null,
                         val text: String? = null, val hint: String? = null) {
    /** No bundled XMage menace asset exists. Render this engine signal as text. */
    val textBadge: String? get() = if (iconType == "ABILITY_MENACE") "Menace" else null
    val displayText: String? get() = listOf(text, hint).firstOrNull { !it.isNullOrBlank() }

    companion object {
        /** Native Gson serializes CardIconType as an enum name, without its category. */
        fun nativeCategory(iconType: String): String? = when (iconType.uppercase()) {
            "PLAYABLE_COUNT" -> "PLAYABLE_COUNT"
            "COMMANDER", "RINGBEARER", "OTHER_HAS_TARGETS" -> "COMMANDER"
            "SYSTEM_COMBINED", "SYSTEM_DEBUG" -> "SYSTEM"
            "ABILITY_MENACE" -> "ABILITY"
            else -> if (assetName(iconType) == null) null else "ABILITY"
        }

        private val keywordTypes = mapOf(
            "flying" to "ABILITY_FLYING", "defender" to "ABILITY_DEFENDER", "deathtouch" to "ABILITY_DEATHTOUCH",
            "lifelink" to "ABILITY_LIFELINK", "double strike" to "ABILITY_DOUBLE_STRIKE", "first strike" to "ABILITY_FIRST_STRIKE",
            "trample" to "ABILITY_TRAMPLE", "hexproof" to "ABILITY_HEXPROOF", "infect" to "ABILITY_INFECT",
            "indestructible" to "ABILITY_INDESTRUCTIBLE", "vigilance" to "ABILITY_VIGILANCE", "reach" to "ABILITY_REACH")

        /** Readable name for a keyword icon ("ABILITY_DOUBLE_STRIKE" → "Double strike"). */
        fun keywordName(iconType: String): String? {
            if (!iconType.startsWith("ABILITY_") || assetName(iconType) == null) return null
            val words = iconType.removePrefix("ABILITY_").replace("_", " ").lowercase()
            return words.take(1).uppercase() + words.drop(1)
        }

        private val reminder = Regex("\\([^)]*\\)")

        /** Keyword icons from rules lines made only of keywords ("Flying", "Vigilance, trample"). */
        fun keywordIcons(rules: String?): List<XmageCardIcon> {
            rules ?: return emptyList()
            val found = mutableListOf<String>()
            for (rawLine in rules.split('\n', '\r')) {
                val line = rawLine.replace(reminder, "").trim { it.isWhitespace() || it == '.' }
                if (line.isEmpty()) continue
                val parts = line.split(',').map { it.trim().lowercase() }
                val types = parts.mapNotNull { keywordTypes[it] }
                if (types.size != parts.size) continue
                for (type in types) if (!found.contains(type)) found += type
            }
            return found.map { XmageCardIcon(it, null, "ABILITY", null, null) }
        }

        fun assetName(iconType: String): String? = when (iconType.uppercase()) {
            "PLAYABLE_COUNT" -> "xmage-icon-playable-count"
            "ABILITY_FLYING" -> "xmage-icon-flying"
            "ABILITY_DEFENDER" -> "xmage-icon-defender"
            "ABILITY_DEATHTOUCH" -> "xmage-icon-deathtouch"
            "ABILITY_LIFELINK" -> "xmage-icon-lifelink"
            "ABILITY_DOUBLE_STRIKE" -> "xmage-icon-double-strike"
            "ABILITY_FIRST_STRIKE" -> "xmage-icon-first-strike"
            "ABILITY_CREW" -> "xmage-icon-crew"
            "ABILITY_TRAMPLE" -> "xmage-icon-trample"
            "ABILITY_HEXPROOF" -> "xmage-icon-hexproof"
            "ABILITY_INFECT" -> "xmage-icon-infect"
            "ABILITY_INDESTRUCTIBLE" -> "xmage-icon-indestructible"
            "ABILITY_VIGILANCE" -> "xmage-icon-vigilance"
            "ABILITY_CLASS_LEVEL" -> "xmage-icon-class-level"
            "ABILITY_REACH" -> "xmage-icon-reach"
            "OTHER_FACEDOWN" -> "xmage-icon-facedown"
            "OTHER_COST_X" -> "xmage-icon-cost-x"
            "OTHER_HAS_RESTRICTIONS" -> "xmage-icon-restrictions"
            "OTHER_HAS_TARGETS" -> "xmage-icon-targets"
            "RINGBEARER" -> "xmage-icon-ringbearer"
            "COMMANDER" -> "xmage-icon-commander"
            "SYSTEM_COMBINED" -> "xmage-icon-combined"
            else -> null
        }
    }
}

data class CardCounterBadge(val name: String, val count: Int) {
    val label: String get() {
        val lower = name.lowercase()
        if (lower.contains("+1") || lower.contains("p1p1")) return "+1/+1"
        if (lower.contains("-1") || lower.contains("m1m1")) return "-1/-1"
        if (lower.contains("loyalty")) return "LOY"
        if (lower.contains("shield")) return "SHD"
        return name.replace(" counter", "", ignoreCase = true).replace("counter", "", ignoreCase = true).trim().uppercase()
    }
    val priority: Int get() {
        val lower = name.lowercase()
        return when {
            lower.contains("+1") || lower.contains("p1p1") -> 0
            lower.contains("-1") || lower.contains("m1m1") -> 1
            lower.contains("loyalty") -> 2
            lower.contains("shield") -> 3
            else -> 4
        }
    }
}

/** Foundation's `String.capitalized`: each whitespace-delimited word gets an initial capital, the rest lowercase. */
fun capitalizedWords(value: String): String {
    val out = StringBuilder(value.length)
    var startOfWord = true
    for (ch in value) {
        if (ch.isWhitespace()) { out.append(ch); startOfWord = true; continue }
        out.append(if (startOfWord) ch.titlecaseChar() else ch.lowercaseChar())
        startOfWord = false
    }
    return out.toString()
}
