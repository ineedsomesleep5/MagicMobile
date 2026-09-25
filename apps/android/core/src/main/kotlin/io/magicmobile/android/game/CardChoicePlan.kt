package io.magicmobile.android.game

/**
 * Port of apps/ios/MagicMobile/CardChoicePlan.swift. Retains the failure source so clearing
 * an old setup error cannot surface an older session error as a new failure.
 */
data class CardChoiceCommandFailure(val message: String, val source: Source) {
    enum class Source { LEGACY, SETUP, SESSION }

    companion object {
        fun of(message: String?, source: Source): CardChoiceCommandFailure? = message?.let { CardChoiceCommandFailure(it, source) }

        fun isNewFailure(old: CardChoiceCommandFailure?, new: CardChoiceCommandFailure?): Boolean {
            if (new == null || new == old) return false
            return !(old?.source == Source.SETUP && new.source == Source.SESSION)
        }
    }
}

/**
 * A visual draft delivered as individual, freshly authorized native answers. A value type on
 * iOS; here `next` mutates in place, and callers keep the returned plan exactly as Swift does.
 */
class CardChoicePlan private constructor(
    val gameID: String, val playerID: String, val turn: Int, val activePlayerID: String?, val phase: String, val step: String?,
    val kind: Kind, val universe: Set<String>, val selected: List<String>, val top: List<String>, val context: String,
    val minimumSelection: Int?, val maximumSelection: Int?,
) {
    enum class Kind { SELECTION, SCRY, TOP_ORDER, BOTTOM_ORDER }

    var stopped = false; private set
    var lastPrompt: String? = null; private set
    private var expectedChosen: Set<String>? = null
    private var remainingOrder: List<String>? = null
    private var orderKind: Kind? = null
    private var orderContext: String? = null
    private var doneSent = false

    /** `selected` is bottom first for scry; `top` is the desired top first. */
    constructor(snapshot: GameSnapshot, prompt: PromptEnvelopeV2, selected: List<String>, top: List<String> = emptyList()) : this(
        snapshot.id, prompt.playerId, snapshot.turn, snapshot.activePlayerId, snapshot.phase, snapshot.step, kind(prompt),
        (prompt.cards ?: emptyList()).filter { it.isPromptSelectable }.map { it.id }.toSet(), selected, top, context(prompt),
        selectionBounds(prompt.message)?.first, selectionBounds(prompt.message)?.second)

    fun copy(): CardChoicePlan = CardChoicePlan(gameID, playerID, turn, activePlayerID, phase, step, kind, universe, selected, top, context,
        minimumSelection, maximumSelection).also {
        it.stopped = stopped; it.lastPrompt = lastPrompt; it.expectedChosen = expectedChosen; it.remainingOrder = remainingOrder
        it.orderKind = orderKind; it.orderContext = orderContext; it.doneSent = doneSent
    }

    fun cancel() { stopped = true }

    /** A cleared pending submission with the same prompt has not authorized another reply. */
    fun submittedPromptIsUnchanged(snapshot: GameSnapshot): Boolean {
        val last = lastPrompt ?: return false
        val prompt = snapshot.promptEnvelopeV2 ?: return false
        return last == "${prompt.id}:${prompt.messageId}"
    }

    /** Null means wait, finish, or return an unexpected prompt to manual control. */
    fun next(snapshot: GameSnapshot, pending: Boolean): GameCommand? {
        if (stopped) return null
        if (!(snapshot.id == gameID && snapshot.turn == turn && snapshot.phase == phase &&
                (activePlayerID == null || snapshot.activePlayerId == activePlayerID) && (step == null || snapshot.step == step) &&
                !snapshot.isCompleted)) { stopped = true; return null }
        if (pending) return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        val key = "${prompt.id}:${prompt.messageId}"
        if (key == lastPrompt) return null
        if (!(prompt.playerId == playerID && prompt.responseCommand?.type == "choose_target" && snapshot.isViewer(playerID) &&
                (prompt.targets ?: emptyList()).isEmpty())) { stopped = true; return null }
        val currentKind = kind(prompt)
        val candidates = (prompt.cards ?: emptyList()).filter { it.isPromptSelectable }.map { it.id }.toSet()
        if (candidates.isEmpty() || !universe.containsAll(candidates) || selected.toSet().size != selected.size || top.toSet().size != top.size ||
            !universe.containsAll(selected) || !universe.containsAll(top)) { stopped = true; return null }
        if (kind == Kind.SCRY && (selected.any { it in top } || (selected.toSet() + top) != universe)) { stopped = true; return null }

        if (currentKind == Kind.TOP_ORDER || currentKind == Kind.BOTTOM_ORDER) {
            val desired: List<String>
            if (kind == Kind.SCRY) {
                if (!(doneSent || expectedChosen == selected.toSet())) { stopped = true; return null }
                desired = if (currentKind == Kind.TOP_ORDER) top else selected
                val allowed = (currentKind == Kind.BOTTOM_ORDER && (orderKind == null || orderKind == Kind.BOTTOM_ORDER)) ||
                    (currentKind == Kind.TOP_ORDER && (orderKind == Kind.TOP_ORDER || orderKind == Kind.BOTTOM_ORDER || (orderKind == null && selected.size <= 1)))
                if (!allowed) { stopped = true; return null }
            } else if (kind == currentKind) desired = selected
            else { stopped = true; return null }
            if (orderKind != currentKind) {
                if ((remainingOrder?.size ?: 0) > 1 || candidates != desired.toSet()) { stopped = true; return null }
                orderKind = currentKind
                orderContext = context(prompt)
                remainingOrder = if (currentKind == Kind.TOP_ORDER) desired.reversed() else desired
            }
            if (orderContext != context(prompt)) { stopped = true; return null }
            val remaining = remainingOrder
            val id = remaining?.firstOrNull()
            if (remaining == null || id == null || candidates != remaining.toSet()) { stopped = true; return null }
            val command = command(prompt, gameID, id) ?: run { stopped = true; return null }
            remainingOrder = remaining.drop(1)
            lastPrompt = key
            return command
        }

        val bounds = selectionBounds(prompt.message)
        val boundsMatch = if (kind == Kind.SCRY) maximumSelection == null || (bounds?.first == minimumSelection && bounds?.second == maximumSelection)
            else bounds?.first == minimumSelection && bounds?.second == maximumSelection
        val chosenArray = prompt.options?.get("chosenTargets").stringArrayValue
        if (!((kind == Kind.SELECTION || kind == Kind.SCRY) && orderKind == null && !doneSent && currentKind == kind && context(prompt) == context &&
                boundsMatch && chosenArray != null && chosenArray.toSet().size == chosenArray.size)) { stopped = true; return null }
        val chosen = chosenArray.toSet()
        if (!universe.containsAll(chosen) || (expectedChosen != null && expectedChosen != chosen)) { stopped = true; return null }
        val removal = (chosen - selected.toSet()).sorted().firstOrNull()
        val addition = selected.firstOrNull { it !in chosen }
        val id = removal ?: addition
        if (id != null) {
            if (id !in candidates) { stopped = true; return null }
            val command = command(prompt, gameID, id) ?: run { stopped = true; return null }
            expectedChosen = if (id in chosen) chosen - id else chosen + id
            lastPrompt = key
            return command
        }
        // False is Done only when the engine explicitly labels it Done.
        if (kind == Kind.SELECTION) {
            val minimum = minimumSelection; val maximum = maximumSelection
            if (minimum == null || maximum == null || selected.size < minimum || selected.size > maximum) { stopped = true; return null }
        }
        val hasDone = (snapshot.legalActions ?: emptyList()).any {
            it.promptId == prompt.id && it.messageId == prompt.messageId && it.type == "answer_yes_no" && it.confirmed == false && it.label.lowercase() == "done"
        }
        if (!hasDone) { stopped = true; return null }
        doneSent = true; lastPrompt = key
        return GameCommand(type = "answer_yes_no", gameId = gameID, playerId = playerID, promptId = prompt.id, messageId = prompt.messageId, confirmed = false)
    }

    companion object {
        fun kind(prompt: PromptEnvelopeV2): Kind {
            val text = prompt.message.lowercase()
            if (text.contains("card order to put") && text.contains("top of your library") && text.contains("last one chosen will be topmost")) return Kind.TOP_ORDER
            if (text.contains("card order to put") && text.contains("bottom of your library") && text.contains("last one chosen will be bottommost")) return Kind.BOTTOM_ORDER
            if (text.contains("(scry)") && text.contains("bottom of your library")) return Kind.SCRY
            return Kind.SELECTION
        }

        private val selectedSuffix = Regex("\\s*\\(selected \\d+ of \\d+(?:, min \\d+)?\\)")
        fun context(prompt: PromptEnvelopeV2): String = prompt.message.replace(selectedSuffix, "")

        fun supportsDraft(prompt: PromptEnvelopeV2): Boolean {
            val kind = kind(prompt)
            return prompt.responseCommand?.type == "choose_target" &&
                ((kind != Kind.SELECTION && kind != Kind.SCRY) ||
                    (prompt.options?.get("chosenTargets").stringArrayValue != null && (kind == Kind.SCRY || selectionBounds(prompt.message) != null))) &&
                (prompt.cards?.any { it.isPromptSelectable } == true) && (prompt.targets ?: emptyList()).isEmpty()
        }

        fun toggled(ids: List<String>, id: String): List<String> = if (id in ids) ids - id else ids + id

        private val boundsPattern = Regex("(?:selected\\s+)\\d+\\s+of\\s+(\\d+)(?:,\\s*min\\s+(\\d+))?", RegexOption.IGNORE_CASE)
        /** (minimum, maximum). TargetImpl omits ", min 0" while retaining "of <max>". */
        fun selectionBounds(message: String): Pair<Int, Int>? {
            val match = boundsPattern.find(message) ?: return null
            val numbers = Regex("\\d+").findAll(match.value).mapNotNull { it.value.toIntOrNull() }.toList()
            if (numbers.size < 2) return null
            return (if (numbers.size >= 3) numbers[2] else 0) to numbers[1]
        }

        private fun command(prompt: PromptEnvelopeV2, gameID: String, id: String): GameCommand? =
            PromptCommandBuilder.command(gameID, prompt, "choose_target", prompt.id, prompt.playerId, listOf(id))
    }
}
