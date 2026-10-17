package io.magicmobile.android.game

/**
 * The combo loop shortcut (ComboLoop.swift; roadmap release B): after the player makes the same sequence of choices three times
 * in a row in one turn, the app offers to repeat it. Each repeat is an ordinary answer the engine checks, so no rule is skipped,
 * and the repeats stop the moment anything differs. Steps are kept by meaning (the card's name, the action's text, the targets'
 * names), never by ids: a token made by the loop has a new id each time round. parity/combo-loop-cases.json checks both platforms.
 */
data class ComboStep(
    val kind: Kind, val type: String, val source: String? = null, val label: String, val targets: List<String> = emptyList(),
    val amount: Int? = null, val amounts: List<Int>? = null, val pile: Int? = null, val manaTypes: List<String>? = null,
    val confirmed: Boolean? = null, val pay: Boolean? = null, val useCommandZone: Boolean? = null,
) {
    /** A legal action from the board (cast, activate, play, tap for mana, pass), or an answer to a prompt. */
    enum class Kind(val raw: String) { ACTION("action"), PROMPT("prompt") }
}

/** Why repeating a loop stopped. */
sealed class ComboLoopStop(val message: String) {
    data object Finished : ComboLoopStop("Done.")
    data object GameOver : ComboLoopStop("The game is over.")
    data object StepMissing : ComboLoopStop("A step isn't available any more, so it's your turn to choose.")
    data object OpponentResponded : ComboLoopStop("An opponent responded, so it's your turn to choose.")
    data object NothingChanged : ComboLoopStop("The loop stopped changing the game.")
    data object ReachedLimit : ComboLoopStop("Stopped after ${ComboLoop.MAX_REPEATS} rounds.")
    data object StoppedByPlayer : ComboLoopStop("Stopped.")
    data class Failed(val reason: String) : ComboLoopStop(reason)
}

/** The answer a step makes now. */
data class ComboReplay(val command: GameCommand, val label: String, val actionID: String)

object ComboLoop {
    /** How many identical rounds in a row make a loop worth offering. */
    const val REPEATS_TO_OFFER = 3
    /** The longest loop looked for, in steps. */
    const val MAX_CYCLE_LENGTH = 12
    /** Steps remembered for spotting loops. */
    const val HISTORY_LIMIT = 48
    /** The most rounds one shortcut runs, whatever was asked. */
    const val MAX_REPEATS = 300
    /** A full round that changes nothing visible twice in a row stops the repeats. */
    const val UNCHANGED_ROUNDS_TO_STOP = 2
    /** The counts offered (plus "until they lose"). */
    val repeatChoices = listOf(5, 10, 20)

    private val comboTypes = setOf("activate_ability", "cast_spell")
    private val excludedTypes = setOf("declare_attackers", "declare_blockers", "mulligan", "keep_hand", "concede", "commander_replacement",
        "choose_starting_player")

    fun normalized(label: String): String = label.lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    /** A card or option's shown name by id, from the prompt first, then every visible zone and the stack. */
    fun names(snapshot: GameSnapshot): Map<String, String> {
        val names = HashMap<String, String>()
        for (player in snapshot.players) {
            names[player.playerId] = if (player.playerId == snapshot.viewerID) "You" else player.displayName ?: player.playerId
            val z = player.zones
            for (card in z.battlefield + z.hand + z.graveyard + z.exile + z.command + z.stack + z.library) names[card.instanceId] = card.card.name
        }
        for (obj in snapshot.xmage?.stack.orEmpty()) {
            val id = obj.sourceInstanceId; val name = obj.sourceName
            if (id != null && name != null) names.putIfAbsent(id, name)
        }
        snapshot.promptEnvelopeV2?.let { prompt ->
            for (option in prompt.targets.orEmpty() + prompt.choices.orEmpty() + prompt.modes.orEmpty() + prompt.orderedItems.orEmpty()) names[option.id] = option.label
            for (card in prompt.cards.orEmpty()) names[card.instanceId] = card.card.name
            for (player in prompt.players.orEmpty()) { names[player.id] = player.label; names[player.playerId] = player.label }
            for (ability in prompt.abilities.orEmpty()) names[ability.id] = ability.label
        }
        return names
    }

    /** The step a player's answer makes, or null for answers that never belong in a loop. */
    fun step(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?): ComboStep? {
        if (snapshot == null || command.type in excludedTypes) return null
        val names = names(snapshot)
        fun named(ids: List<String>?): List<String> = ids.orEmpty().map { names[it] ?: "?" }
        val action = snapshot.legalActions?.firstOrNull { it.id == actionID }
        if (action != null) {
            val source = (action.sourceInstanceId ?: action.cardInstanceId)?.let { names[it] } ?: action.cardName
            return ComboStep(ComboStep.Kind.ACTION, command.type, source, normalized(action.label),
                named(command.targetIds) + named(command.cardInstanceIds) + named(command.playerIds), command.amount, command.amounts, command.pile,
                command.manaTypes ?: command.manaType?.let { listOf(it) }, command.confirmed, command.pay, command.useCommandZone)
        }
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (command.promptId != prompt.id && command.promptId != prompt.responseCommand?.promptId) return null
        val chosen = named(command.targetIds) + named(command.cardInstanceIds) + named(command.playerIds) + named(command.choiceIds) +
            named(command.modeIds) + named(command.orderedIds) + named(command.abilityId?.let { listOf(it) })
        return ComboStep(ComboStep.Kind.PROMPT, command.type, null, prompt.method, chosen, command.amount, command.amounts, command.pile,
            command.manaTypes ?: command.manaType?.let { listOf(it) }, command.confirmed, command.pay, command.useCommandZone)
    }

    /** A round worth repeating: something is cast or activated, and nothing in it is combat or the opening. */
    fun isLoopable(round: List<ComboStep>): Boolean =
        round.any { it.kind == ComboStep.Kind.ACTION && it.type in comboTypes } && round.none { it.type in excludedTypes }

    /** The shortest round the last steps repeat REPEATS_TO_OFFER times in a row, or null. */
    fun cycle(history: List<ComboStep>): List<ComboStep>? {
        if (history.isEmpty()) return null
        for (length in 1..minOf(MAX_CYCLE_LENGTH, history.size / REPEATS_TO_OFFER)) {
            val tail = history.takeLast(length * REPEATS_TO_OFFER)
            if ((length until tail.size).all { tail[it] == tail[it - length] }) {
                val round = tail.take(length)
                if (isLoopable(round)) return round
            }
        }
        return null
    }

    /** What the offer says about the loop: its casts and activations, briefly. */
    fun describe(round: List<ComboStep>): String = round.filter { it.kind == ComboStep.Kind.ACTION && it.type in comboTypes }
        .joinToString(" → ") { "${if (it.type == "cast_spell") "Cast" else "Activate"} ${it.source ?: it.label}" }

    /** The answer this step makes now, from the current legal actions or prompt; null when it isn't available. */
    fun command(step: ComboStep, snapshot: GameSnapshot): ComboReplay? {
        val names = names(snapshot)
        when (step.kind) {
            ComboStep.Kind.ACTION -> {
                val action = snapshot.legalActions?.firstOrNull { action ->
                    action.type == step.type && normalized(action.label) == step.label &&
                        ((action.sourceInstanceId ?: action.cardInstanceId)?.let { names[it] } ?: action.cardName) == step.source
                } ?: return null
                return ComboReplay(commandFrom(action, snapshot.id, snapshot.bridgeRevision), action.label, action.id)
            }
            ComboStep.Kind.PROMPT -> {
                val prompt = snapshot.promptEnvelopeV2 ?: return null
                if (prompt.method != step.label || !snapshot.isViewer(prompt.playerId)) return null
                // Each chosen name takes a different option with that name (two Squirrels are two choices).
                val pool = ArrayList<Pair<String, String>>()
                for (option in prompt.targets.orEmpty() + prompt.choices.orEmpty() + prompt.modes.orEmpty() + prompt.orderedItems.orEmpty()) pool += option.id to option.label
                for (card in prompt.cards.orEmpty()) pool += card.instanceId to card.card.name
                for (player in prompt.players.orEmpty()) pool += player.playerId to player.label
                for (ability in prompt.abilities.orEmpty()) pool += ability.id to ability.label
                val ids = ArrayList<String>()
                for (name in step.targets) {
                    val index = pool.indexOfFirst { it.second == name || names[it.first] == name }
                    if (index < 0) return null
                    ids += pool.removeAt(index).first
                }
                val promptID = prompt.responseCommand?.promptId ?: prompt.id
                if (step.type == "answer_yes_no" || step.type == "pay_cost") {
                    val confirmed = step.confirmed ?: step.pay ?: return null
                    return ComboReplay(GameCommand(step.type, snapshot.id, snapshot.viewerID, promptId = promptID,
                        messageId = prompt.responseCommand?.messageId ?: prompt.messageId, confirmed = confirmed,
                        pay = if (step.type == "pay_cost") confirmed else null), step.type, "combo-loop-$promptID")
                }
                val command = PromptCommandBuilder.command(snapshot.id, prompt, step.type, promptID, snapshot.viewerID, ids, step.amount, step.amounts,
                    step.pile, step.useCommandZone, step.manaTypes?.firstOrNull(), step.pay) ?: return null
                return ComboReplay(command, step.type, "combo-loop-$promptID")
            }
        }
    }

    /** The command a board action sends (OnDeviceSession.send(action)). */
    fun commandFrom(action: LegalAction, gameId: String, bridgeRevision: Int?): GameCommand = GameCommand(type = action.type, gameId = gameId,
        playerId = action.playerId, cardInstanceId = action.cardInstanceId, sourceInstanceId = action.sourceInstanceId, abilityId = action.abilityId,
        promptId = action.promptId, messageId = action.messageId, choiceIds = action.choiceIds, targetIds = action.targetIds,
        cardInstanceIds = action.cardInstanceIds, modeIds = action.modeIds, pile = action.pile?.value, amount = action.amount,
        amounts = action.amounts, orderedIds = action.orderedIds, useCommandZone = action.useCommandZone, manaType = action.manaType,
        manaTypes = action.manaTypes, playerIds = action.playerIds, confirmed = action.confirmed, pay = action.pay,
        sourceZone = action.sourceZone, fromZone = action.sourceZone, cardName = action.cardName, attackers = action.attackers,
        blockers = action.blockers, expectedBridgeRevision = bridgeRevision)

    /** The parts of the game a loop changes: life, poison, zone sizes, counters, mana and spells cast. */
    fun digest(snapshot: GameSnapshot): String = snapshot.players.sortedBy { it.playerId }.joinToString("|") { player ->
        val z = player.zones
        val pool = player.manaPool?.let { "${it.W},${it.U},${it.B},${it.R},${it.G},${it.C}" } ?: ""
        val counters = z.battlefield.sumOf { card -> card.counters?.values?.sum() ?: 0 } + (player.counters?.values?.sum() ?: 0)
        "${player.playerId}:${player.life}:${player.poison}:${z.visibleHandCount}:${z.visibleLibraryCount}:${z.battlefield.size}:" +
            "${z.graveyard.size}:${z.exile.size}:$counters:$pool"
    } + "|storm:${snapshot.stormCount ?: 0}"

    /** An opponent put something on the stack: their spell, or an ability of one of their permanents. */
    fun opponentResponded(snapshot: GameSnapshot): Boolean {
        val opponents = snapshot.players.filter { !snapshot.isViewer(it.playerId) }
        if (opponents.any { it.zones.stack.isNotEmpty() }) return true
        val theirs = opponents.flatMap { p -> p.zones.battlefield.map { it.instanceId } }.toSet()
        return snapshot.xmage?.stack.orEmpty().any { obj ->
            val controller = obj.controllerId
            (controller != null && controller.isNotEmpty() && !snapshot.isViewer(controller) && snapshot.players.any { it.playerId == controller }) ||
                (obj.sourceInstanceId?.let { it in theirs } ?: false)
        }
    }

    /** The closing line: how many rounds ran and whose life changed. */
    fun summary(rounds: Int, before: GameSnapshot, after: GameSnapshot): String {
        val parts = mutableListOf(if (rounds == 1) "Repeated once" else "Repeated $rounds times")
        for (player in after.players) {
            val old = before.players.firstOrNull { it.playerId == player.playerId } ?: continue
            if (old.life == player.life) continue
            val name = if (after.isViewer(player.playerId)) "You" else player.displayName ?: "Opponent"
            parts += "$name ${old.life} → ${player.life}"
        }
        return parts.joinToString(" · ")
    }
}
