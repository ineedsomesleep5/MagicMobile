package io.magicmobile.android.game

/**
 * The combo loop shortcut (ComboLoop.swift; roadmap release B): after the player makes the same sequence of choices three times
 * in a row in one turn, the app offers to repeat it. Each repeat is an ordinary answer the engine checks, so no rule is skipped.
 * Steps are kept by meaning, never by ids: an action by its card's name and text, a choice by what kind of thing was chosen
 * (an opponent's creature, a Squirrel token), so a token made by the loop or a new creature of the same kind still matches.
 * Passing priority is not part of a round; the repeats pass on their own so the player's triggers resolve first.
 * parity/combo-loop-cases.json checks both platforms.
 */
class ComboTarget(
    val name: String,
    /** "you", "opponent", or "" for options that belong to nobody (modes, choices). */
    val controller: String = "",
    /** "creature", "planeswalker", "artifact", "enchantment", "land", "player", "card" or "option". */
    val kind: String = "option",
    val token: Boolean = false,
) {
    /** The same kind of thing: options by name, cards and players by whose they are, what they are and whether a token. */
    override fun equals(other: Any?): Boolean = other is ComboTarget && controller == other.controller && kind == other.kind &&
        token == other.token && (kind != "option" || name == other.name)

    override fun hashCode(): Int = listOf(controller, kind, token, if (kind == "option") name else "").hashCode()

    override fun toString(): String = "$name@$controller/$kind/${if (token) "token" else "card"}"

    /** Words for messages and the preview: "a Squirrel Token token", "an opponent's creature". */
    val phrase: String get() = when (kind) {
        "option", "player" -> name
        else -> if (controller == "opponent") (if (token) "an opponent's $kind token" else "an opponent's $kind")
            else (if (token) "a $name token" else "your $name")
    }
}

class ComboStep(
    val kind: Kind, val type: String, val source: String? = null, val label: String, val targets: List<ComboTarget> = emptyList(),
    val amount: Int? = null, val amounts: List<Int>? = null, val pile: Int? = null, val manaTypes: List<String>? = null,
    val confirmed: Boolean? = null, val pay: Boolean? = null, val useCommandZone: Boolean? = null,
    /** Taken with nothing on the stack: the repeats let the player's own triggers resolve before this step. */
    val stackEmpty: Boolean = false,
    /** Mana an action makes, for tapping another source of the same mana when the original is gone. */
    val producedMana: List<String>? = null,
) {
    /** A legal action from the board (cast, activate, play, tap for mana), or an answer to a prompt. */
    enum class Kind(val raw: String) { ACTION("action"), PROMPT("prompt") }

    /** The same step, whatever the stack and the exact mana source looked like. */
    override fun equals(other: Any?): Boolean = other is ComboStep && kind == other.kind && type == other.type && source == other.source &&
        label == other.label && targets == other.targets && amount == other.amount && amounts == other.amounts && pile == other.pile &&
        manaTypes == other.manaTypes && confirmed == other.confirmed && pay == other.pay && useCommandZone == other.useCommandZone

    override fun hashCode(): Int = listOf(kind, type, source, label, targets).hashCode()
}

/** How many rounds to repeat. */
sealed class ComboRepeat {
    data class Times(val rounds: Int) : ComboRepeat()
    /** Until a step can't be taken any more: a normal finish. */
    data object UntilCant : ComboRepeat()
    /** Until every opponent has lost. */
    data object UntilWin : ComboRepeat()

    val count: Int? get() = (this as? Times)?.rounds
    /** Small counts play their effects at a pace you can follow; long runs go fast and show the board once a round. */
    val watchable: Boolean get() = (count ?: Int.MAX_VALUE) <= ComboLoop.WATCHABLE_ROUNDS
}

/** What a player's answer means for spotting loops. */
sealed class ComboNote {
    data class Step(val step: ComboStep) : ComboNote()
    /** Not part of a round (passing priority): neither recorded nor breaking the rounds around it. */
    data object Ignore : ComboNote()
    /** Never part of a loop (combat, the opening): the rounds start over. */
    data object Breaks : ComboNote()
}

/** Why repeating a loop stopped. */
sealed class ComboLoopStop(val message: String) {
    data object Finished : ComboLoopStop("Done.")
    data object GameOver : ComboLoopStop("The game is over.")
    data class StepMissing(val why: String) : ComboLoopStop("Stopped: $why.")
    data object OpponentResponded : ComboLoopStop("An opponent responded, so it's your turn to choose.")
    data object NothingChanged : ComboLoopStop("The loop stopped changing the game.")
    data object ReachedLimit : ComboLoopStop("Stopped after ${ComboLoop.MAX_REPEATS} rounds.")
    data object StoppedByPlayer : ComboLoopStop("Stopped.")
    data class Failed(val reason: String) : ComboLoopStop(reason)
}

/** The answer a step makes now, and what it chose (so the next round can keep the same target). */
data class ComboReplay(
    val command: GameCommand, val label: String, val actionID: String, val chosenNames: List<String> = emptyList(),
    /** A target was gone and another of the same kind was chosen ("Kinjalli's Caller" to "Zacama"). */
    val retargeted: Pair<String, String>? = null,
)

object ComboLoop {
    /** How many identical rounds in a row make a loop worth offering. */
    const val REPEATS_TO_OFFER = 3
    /** The longest loop looked for, in steps. */
    const val MAX_CYCLE_LENGTH = 12
    /** Steps remembered for spotting loops. */
    const val HISTORY_LIMIT = 48
    /** The most rounds one shortcut runs, whatever was asked. */
    const val MAX_REPEATS = 300
    /** The count picker starts here. */
    const val PICKER_DEFAULT = 5
    /** Up to this many rounds play their effects, at a pace you can follow. */
    const val WATCHABLE_ROUNDS = 10
    /** Open-ended repeats stop when this many rounds in a row change nothing visible. */
    const val UNCHANGED_ROUNDS_TO_STOP = 3

    private val comboTypes = setOf("activate_ability", "cast_spell")
    private val ignoredTypes = setOf("pass_priority")
    private val excludedTypes = setOf("declare_attackers", "declare_blockers", "mulligan", "keep_hand", "concede", "commander_replacement",
        "choose_starting_player")

    fun normalized(label: String): String = label.lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    // What things are

    data class Known(val name: String, val controller: String, val kind: String, val token: Boolean)

    fun kind(card: CardIdentity): String {
        val type = card.typeLine.lowercase()
        return listOf("creature", "planeswalker", "artifact", "enchantment", "land").firstOrNull { type.contains(it) } ?: "card"
    }

    /** Everything nameable by id: cards in every visible zone (with whose they are), players, and the prompt's options. */
    fun known(snapshot: GameSnapshot): Map<String, Known> {
        val known = HashMap<String, Known>()
        for (player in snapshot.players) {
            val side = if (snapshot.isViewer(player.playerId)) "you" else "opponent"
            known[player.playerId] = Known(if (side == "you") "You" else player.displayName ?: player.playerId, side, "player", false)
            val z = player.zones
            for (card in z.battlefield + z.hand + z.graveyard + z.exile + z.command + z.stack + z.library) {
                known[card.instanceId] = Known(card.card.name, side, kind(card.card), card.card.isToken == true)
            }
        }
        for (obj in snapshot.xmage?.stack.orEmpty()) {
            val id = obj.sourceInstanceId; val name = obj.sourceName
            if (id != null && name != null) known.putIfAbsent(id, Known(name, "", "card", false))
        }
        snapshot.promptEnvelopeV2?.let { prompt ->
            for (option in prompt.targets.orEmpty() + prompt.choices.orEmpty() + prompt.modes.orEmpty() + prompt.orderedItems.orEmpty()) {
                if (option.id in known) continue
                known[option.id] = option.cardInstanceId?.let { known[it] } ?: Known(option.label, "", "option", false)
            }
            for (card in prompt.cards.orEmpty()) known.putIfAbsent(card.instanceId, Known(card.card.name, "", kind(card.card), card.card.isToken == true))
            for (player in prompt.players.orEmpty()) {
                known.putIfAbsent(player.playerId, Known(player.label, if (snapshot.isViewer(player.playerId)) "you" else "opponent", "player", false))
            }
            for (ability in prompt.abilities.orEmpty()) known[ability.id] = Known(ability.label, "", "option", false)
        }
        return known
    }

    fun target(id: String, known: Map<String, Known>): ComboTarget =
        known[id]?.let { ComboTarget(it.name, it.controller, it.kind, it.token) } ?: ComboTarget("?")

    /** Nothing on the stack, anyone's. */
    fun stackIsEmpty(snapshot: GameSnapshot): Boolean = snapshot.xmage?.stack.orEmpty().isEmpty() && snapshot.players.all { it.zones.stack.isEmpty() }

    // Recording

    /** What a player's answer means for spotting loops. */
    fun note(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?): ComboNote {
        if (command.type in ignoredTypes) return ComboNote.Ignore
        if (snapshot == null || command.type in excludedTypes) return ComboNote.Breaks
        val known = known(snapshot)
        fun chosen(ids: List<String>?): List<ComboTarget> = ids.orEmpty().map { target(it, known) }
        val empty = stackIsEmpty(snapshot)
        val manaTypes = command.manaTypes ?: command.manaType?.let { listOf(it) }
        val action = snapshot.legalActions?.firstOrNull { it.id == actionID }
        if (action != null) {
            val source = (action.sourceInstanceId ?: action.cardInstanceId)?.let { known[it]?.name } ?: action.cardName
            return ComboNote.Step(ComboStep(ComboStep.Kind.ACTION, command.type, source, normalized(action.label),
                chosen(command.targetIds) + chosen(command.cardInstanceIds) + chosen(command.playerIds), command.amount, command.amounts, command.pile,
                manaTypes, command.confirmed, command.pay, command.useCommandZone, empty, action.producedMana))
        }
        val prompt = snapshot.promptEnvelopeV2 ?: return ComboNote.Breaks
        if (command.promptId != prompt.id && command.promptId != prompt.responseCommand?.promptId) return ComboNote.Breaks
        val picked = chosen(command.targetIds) + chosen(command.cardInstanceIds) + chosen(command.playerIds) + chosen(command.choiceIds) +
            chosen(command.modeIds) + chosen(command.orderedIds) + chosen(command.abilityId?.let { listOf(it) })
        return ComboNote.Step(ComboStep(ComboStep.Kind.PROMPT, command.type, null, prompt.method, picked, command.amount, command.amounts, command.pile,
            manaTypes, command.confirmed, command.pay, command.useCommandZone, empty))
    }

    /** The step a player's answer makes, or null when it isn't one. */
    fun step(command: GameCommand, label: String, actionID: String, snapshot: GameSnapshot?): ComboStep? =
        (note(command, label, actionID, snapshot) as? ComboNote.Step)?.step

    // Spotting a loop

    /** A round worth repeating: something is cast or activated, and nothing in it is combat or the opening. */
    fun isLoopable(round: List<ComboStep>): Boolean =
        round.any { it.kind == ComboStep.Kind.ACTION && it.type in comboTypes } && round.none { it.type in excludedTypes }

    /** The shortest round the last steps repeat REPEATS_TO_OFFER times in a row, or null. */
    fun cycle(history: List<ComboStep>): List<ComboStep>? {
        val longest = minOf(MAX_CYCLE_LENGTH, history.size / REPEATS_TO_OFFER)
        if (longest < 1) return null
        for (length in 1..longest) {
            val tail = history.takeLast(length * REPEATS_TO_OFFER)
            if ((length until tail.size).all { tail[it] == tail[it - length] }) {
                val round = tail.take(length)
                if (isLoopable(round)) return round
            }
        }
        return null
    }

    /** The round's casts and activations, briefly. */
    fun describe(round: List<ComboStep>): String = round.filter { it.kind == ComboStep.Kind.ACTION && it.type in comboTypes }
        .joinToString(" → ") { "${if (it.type == "cast_spell") "Cast" else "Activate"} ${it.source ?: it.label}" }

    /** What one round does, step by step, for the offer's preview. */
    fun preview(round: List<ComboStep>): List<String> = round.map { step ->
        when (step.kind) {
            ComboStep.Kind.ACTION -> {
                val name = step.source ?: step.label
                when (step.type) {
                    "cast_spell" -> "Cast $name"
                    "activate_ability" -> "Activate $name"
                    "make_mana" -> "Mana from $name"
                    "play_land" -> "Play $name"
                    else -> name
                }
            }
            ComboStep.Kind.PROMPT -> when {
                step.type == "answer_yes_no" -> if (step.confirmed == true) "Answer Yes" else "Answer No"
                step.type == "play_mana" || step.type == "choose_mana" -> "Pay {${step.manaTypes.orEmpty().joinToString("")}}"
                else -> step.targets.joinToString(", ") { it.phrase }.let { if (it.isEmpty()) step.label else "Choose $it" }
            }
        }
    }

    // Repeating it

    /** The step must wait for the stack to clear first: it was taken with nothing on the stack. */
    fun waitsForStack(step: ComboStep, snapshot: GameSnapshot): Boolean = step.stackEmpty && !stackIsEmpty(snapshot)

    /** Passing priority so the player's own triggers resolve: the board's pass, when it's offered. */
    fun pass(snapshot: GameSnapshot): ComboReplay? {
        val action = snapshot.legalActions?.firstOrNull { it.type == "pass_priority" } ?: return null
        return ComboReplay(commandFrom(action, snapshot.id, snapshot.bridgeRevision), action.label, action.id)
    }

    /**
     * The answer this step makes now, from the current legal actions or prompt; null when it isn't available. Each chosen thing
     * prefers the name [prefer] gives for its place (last round's choice, so a shrinking creature stays the target until it dies),
     * then the recorded name, then anything of the same kind.
     */
    fun command(step: ComboStep, snapshot: GameSnapshot, prefer: List<String> = emptyList()): ComboReplay? {
        val known = known(snapshot)
        when (step.kind) {
            ComboStep.Kind.ACTION -> {
                val actions = snapshot.legalActions.orEmpty()
                fun source(action: LegalAction) = (action.sourceInstanceId ?: action.cardInstanceId)?.let { known[it]?.name } ?: action.cardName
                var match = actions.firstOrNull { it.type == step.type && normalized(it.label) == step.label && source(it) == step.source }
                // The same mana from another source when the original is gone (a sacrificed Treasure).
                val mana = step.producedMana
                if (match == null && step.type == "make_mana" && !mana.isNullOrEmpty()) {
                    match = actions.firstOrNull { it.type == "make_mana" && it.producedMana.orEmpty().containsAll(mana) }
                }
                val action = match ?: return null
                return ComboReplay(commandFrom(action, snapshot.id, snapshot.bridgeRevision), action.label, action.id)
            }
            ComboStep.Kind.PROMPT -> {
                val prompt = snapshot.promptEnvelopeV2 ?: return null
                if (prompt.method != step.label || !snapshot.isViewer(prompt.playerId)) return null
                val pool = ArrayList<Pair<String, ComboTarget>>()
                for (option in prompt.targets.orEmpty() + prompt.choices.orEmpty() + prompt.modes.orEmpty() + prompt.orderedItems.orEmpty()) pool += option.id to target(option.id, known)
                for (card in prompt.cards.orEmpty()) pool += card.instanceId to target(card.instanceId, known)
                for (player in prompt.players.orEmpty()) pool += player.playerId to target(player.playerId, known)
                for (ability in prompt.abilities.orEmpty()) pool += ability.id to target(ability.id, known)
                val ids = ArrayList<String>(); val names = ArrayList<String>()
                var retargeted: Pair<String, String>? = null
                step.targets.forEachIndexed { place, wanted ->
                    val preferred = prefer.getOrNull(place) ?: wanted.name
                    var index = pool.indexOfFirst { it.second == wanted && it.second.name == preferred }
                    if (index < 0) index = pool.indexOfFirst { it.second == wanted && it.second.name == wanted.name }
                    if (index < 0) index = pool.indexOfFirst { it.second == wanted }
                    if (index < 0) return null
                    val picked = pool.removeAt(index)
                    if (picked.second.name != preferred && wanted.kind != "option" && wanted.controller == "opponent" && retargeted == null) {
                        retargeted = preferred to picked.second.name
                    }
                    ids += picked.first; names += picked.second.name
                }
                val promptID = prompt.responseCommand?.promptId ?: prompt.id
                if (step.type == "answer_yes_no" || step.type == "pay_cost") {
                    val confirmed = step.confirmed ?: step.pay ?: return null
                    return ComboReplay(GameCommand(step.type, snapshot.id, snapshot.viewerID, promptId = promptID,
                        messageId = prompt.responseCommand?.messageId ?: prompt.messageId, confirmed = confirmed,
                        pay = if (step.type == "pay_cost") confirmed else null), step.type, "combo-loop-$promptID", names)
                }
                val command = PromptCommandBuilder.command(snapshot.id, prompt, step.type, promptID, snapshot.viewerID, ids, step.amount, step.amounts,
                    step.pile, step.useCommandZone, step.manaTypes?.firstOrNull(), step.pay) ?: return null
                return ComboReplay(command, step.type, "combo-loop-$promptID", names, retargeted)
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

    /**
     * The parts of the game a loop changes: life, poison, every permanent's power, toughness, damage, counters and tapped state,
     * zone sizes, mana and spells cast. A round that leaves all of it unchanged did nothing visible.
     */
    fun digest(snapshot: GameSnapshot): String = snapshot.players.sortedBy { it.playerId }.joinToString("|") { player ->
        val z = player.zones
        val pool = player.manaPool?.let { "${it.W},${it.U},${it.B},${it.R},${it.G},${it.C}" } ?: ""
        val permanents = z.battlefield.map { card ->
            val counters = card.counters.orEmpty().toSortedMap().entries.joinToString("") { "${it.key}${it.value}" }
            "${card.card.name}/${card.power ?: -99}/${card.toughness ?: -99}/${card.damage ?: 0}/${if (card.tapped == true) 1 else 0}/$counters"
        }.sorted().joinToString(",")
        val counters = player.counters.orEmpty().toSortedMap().entries.joinToString("") { "${it.key}${it.value}" }
        "${player.playerId}:${player.life}:${player.poison}:${z.visibleHandCount}:${z.visibleLibraryCount}:" +
            "${z.graveyard.size}:${z.exile.size}:$counters:$pool:[$permanents]"
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

    /** One round on the running card: "Round 3 · Activate Chatterfang → Kinjalli's Caller". */
    fun roundLine(round: Int, cycle: List<ComboStep>, chosen: List<String>): String =
        "Round $round · ${describe(cycle)}${chosen.firstOrNull()?.let { " → $it" } ?: ""}"

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

    /** Why a step couldn't be taken, in words: "no Squirrel Token token left", "Chatterfang isn't available". */
    fun missing(step: ComboStep): String = when (step.kind) {
        ComboStep.Kind.ACTION -> "${step.source ?: step.label} isn't available"
        ComboStep.Kind.PROMPT -> {
            val thing = step.targets.firstOrNull()
            when {
                thing == null || thing.kind == "option" -> "the next choice isn't offered"
                thing.controller == "opponent" -> if (thing.token) "no opponent's ${thing.kind} token left to choose" else "no opponent's ${thing.kind} left to choose"
                else -> if (thing.token) "no ${thing.name} token left" else "${thing.name} isn't there to choose"
            }
        }
    }
}

/** The board's copy while a loop repeats: the prompts the repeats answer are not shown. */
fun GameSnapshot.withoutPrompts(): GameSnapshot =
    copy(legalActions = null, choicePrompt = null, promptEnvelope = null, promptEnvelopeV2 = null, manaPayment = null)
