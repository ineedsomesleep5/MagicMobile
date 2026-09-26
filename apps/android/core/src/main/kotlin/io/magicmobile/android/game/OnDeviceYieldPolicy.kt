package io.magicmobile.android.game

/**
 * Port of apps/ios/MagicMobile/OnDeviceYieldPolicy.swift. Local scheduling only: every pass
 * still requires an ordinary engine prompt. No skip commands, inferred choices or rules simulation.
 */
class OnDeviceYieldPolicy {
    enum class Mode(val duration: Double, val passLimit: Int, val status: String) {
        SAFE_END_TURN(60.0, 64, "Auto-passing routine priority this turn. Stop at any time."),
        END_TURN_SKIPPING_RESPONSES(120.0, 256, "Skipping responses this turn, including the stack. Stops for choices or after 120 seconds / 256 passes."),
        UNTIL_MY_TURN(180.0, 256, "Skipping responses until your next turn, including the stack. Stops for choices or after 180 seconds / 256 passes."),
    }

    data class Prompt(val id: String, val revision: Long, val kind: String, val selectMode: String?, val allowsBoolean: Boolean,
                      val submitted: Boolean, val manaPlayerID: String?)

    data class Context(val matchID: String, val seatID: String, val viewerID: String, val activePlayerID: String?, val turn: Long,
                       val phase: String, val localHumanEnabled: Boolean, val foreground: Boolean, val emptyStack: Boolean,
                       val selfAuthority: Boolean, val resyncRequired: Boolean, val prompt: Prompt?)

    enum class StopReason(val message: String) {
        UNAVAILABLE("Auto-pass stopped. Pass priority manually."),
        TURN_CHANGED("Auto-pass stopped. The turn changed."),
        CONTROL_CHANGED("Auto-pass stopped. Player control changed."),
        STACK("Auto-pass stopped. Check the stack."),
        DECISION("Auto-pass stopped. A choice needs your attention."),
        INTERRUPTED("Auto-pass stopped. Review the current game state."),
        LIMIT("Auto-pass stopped after its safety limit."),
    }

    sealed class Decision {
        object Wait : Decision()
        data class Pass(val prompt: Prompt) : Decision()
        data class Stop(val reason: StopReason) : Decision()
    }

    private var anchor: Context? = null
    private var mode = Mode.SAFE_END_TURN
    private var expiresAt = 0.0
    private val attempted = mutableSetOf<String>()
    private var latestRevision = -1L
    val isActive: Boolean get() = anchor != null

    fun start(value: Context, now: Double, mode: Mode = Mode.SAFE_END_TURN): Boolean {
        if (!canStart(value, mode)) return false
        this.mode = mode
        anchor = value; expiresAt = now + mode.duration; attempted.clear(); latestRevision = -1
        return true
    }

    fun stop() { anchor = null; attempted.clear(); latestRevision = -1 }

    fun evaluate(value: Context, now: Double): Decision {
        val anchor = anchor ?: return Decision.Wait
        val turnBoundary = if (mode == Mode.UNTIL_MY_TURN) {
            value.activePlayerID == value.viewerID && (value.turn != anchor.turn || anchor.activePlayerID != anchor.viewerID)
        } else value.turn != anchor.turn || value.activePlayerID != anchor.activePlayerID
        val prompt = value.prompt
        val reason = when {
            !value.localHumanEnabled || value.phase != "running" -> StopReason.UNAVAILABLE
            !value.foreground || value.resyncRequired -> StopReason.INTERRUPTED
            value.matchID != anchor.matchID || value.seatID != anchor.seatID || value.viewerID != anchor.viewerID || !value.selfAuthority -> StopReason.CONTROL_CHANGED
            value.turn < anchor.turn || value.activePlayerID.isNullOrEmpty() -> StopReason.INTERRUPTED
            turnBoundary -> StopReason.TURN_CHANGED
            mode == Mode.SAFE_END_TURN && !value.emptyStack -> StopReason.STACK
            now >= expiresAt || attempted.size >= mode.passLimit -> StopReason.LIMIT
            prompt != null && prompt.manaPlayerID != value.viewerID && prompt.kind == "SELECT" && prompt.selectMode == "priority" -> StopReason.CONTROL_CHANGED
            prompt != null && !ordinaryPriority(prompt, value.viewerID) -> StopReason.DECISION
            else -> null
        }
        if (reason != null) { stop(); return Decision.Stop(reason) }
        if (prompt == null || prompt.submitted || attempted.contains(prompt.id) || prompt.revision <= latestRevision) return Decision.Wait
        return Decision.Pass(prompt)
    }

    /** Reserve before dispatch, including uncertain/failed responses. Never auto-retry. */
    fun recordPass(prompt: Prompt) {
        if (!isActive || attempted.size >= mode.passLimit) return
        attempted += prompt.id; latestRevision = maxOf(latestRevision, prompt.revision)
    }

    companion object {
        fun canStart(value: Context, mode: Mode = Mode.SAFE_END_TURN): Boolean {
            val active = value.activePlayerID
            if (!value.localHumanEnabled || !value.foreground || value.phase != "running" || value.turn <= 0 ||
                active.isNullOrEmpty() || !value.selfAuthority || value.resyncRequired) return false
            if (!(mode == Mode.UNTIL_MY_TURN || active == value.viewerID) || !(mode != Mode.SAFE_END_TURN || value.emptyStack)) return false
            // Waiting on an opponent is safe to arm; it does not authorize an answer.
            val prompt = value.prompt ?: return mode == Mode.UNTIL_MY_TURN
            if (prompt.submitted) return false
            return ordinaryPriority(prompt, value.viewerID)
        }

        private fun ordinaryPriority(prompt: Prompt, viewer: String): Boolean =
            prompt.id.isNotEmpty() && prompt.revision >= 0 && prompt.kind == "SELECT" && prompt.selectMode == "priority" &&
                prompt.allowsBoolean && prompt.manaPlayerID == viewer
    }
}
