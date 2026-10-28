package io.magicmobile.android.session

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.BoardFXRevisionKey
import io.magicmobile.android.game.BoardPresentationHold
import io.magicmobile.android.game.ComboLoop
import io.magicmobile.android.game.ComboLoopStop
import io.magicmobile.android.game.ComboNote
import io.magicmobile.android.game.ComboRepeat
import io.magicmobile.android.game.ComboReplay
import io.magicmobile.android.game.ComboStep
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EnginePrompt
import io.magicmobile.android.game.FreezeStallTracker
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.J
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.MatchPoll
import io.magicmobile.android.game.OnDeviceMessageLog
import io.magicmobile.android.game.OnDevicePromptAdapter
import io.magicmobile.android.game.OnDeviceSmartPass
import io.magicmobile.android.game.OnDeviceSnapshotAdapter
import io.magicmobile.android.game.OnDeviceYieldPolicy
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.jsonObject
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import io.magicmobile.android.game.withoutPrompts
import io.magicmobile.android.ondevice.FreezeLog
import io.magicmobile.android.ondevice.OnDeviceHostUnavailable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.yield
import java.io.IOException
import java.util.UUID
import kotlinx.serialization.json.JsonPrimitive

/**
 * Port of OnDeviceTableLink (OnDeviceSession.swift): a seat's side of a phone-hosted table. The host's
 * session announces each new game revision; a guest's session polls when an announcement arrives,
 * promptly while its own answer is outstanding, and otherwise only on a slow heartbeat, so a quiet
 * table sends almost nothing through the relay. Main thread only.
 */
class OnDeviceTableLink(val role: Role, hostName: String) {
    enum class Role { HOST, GUEST }

    /** The host's table name, for "Waiting for <host>…". */
    val hostName: String = hostName.trim().ifEmpty { "the host" }
    /** Host: shares a revision notice with every guest. Set by the table connection. */
    var announce: ((Long) -> Unit)? = null
    private var announcedRevision = -1L
    /** Guest: the newest revision the host announced. Until the first notice the guest cannot tell whether its host announces at all. */
    var noticedRevision = -1L; private set
    var hostAnnounces = false; private set
    private val wakes = MutableStateFlow(0L)

    val waitingStatus: String get() = "Waiting for $hostName…"

    /** Host: the session applied a poll at [revision]. Each revision is announced once. */
    fun applied(revision: Long) {
        if (role != Role.HOST || revision <= announcedRevision) return
        announcedRevision = revision
        announce?.invoke(revision)
    }

    /** Guest: the host announced [revision]. Repeated, late or out-of-order notices are harmless. */
    fun noticed(revision: Long) {
        if (role != Role.GUEST) return
        hostAnnounces = true
        noticedRevision = maxOf(noticedRevision, revision)
        wake()
    }

    /** Returns after a notice, [wake], cancellation or [timeoutMillis], whichever comes first. */
    suspend fun waitForNotice(timeoutMillis: Long) {
        val start = wakes.value
        withTimeoutOrNull(timeoutMillis.coerceIn(0L, 3_600_000L)) { wakes.first { it != start } }
    }

    /** Releases every waiting poll loop so it re-evaluates its schedule now. */
    fun wake() { wakes.value = wakes.value + 1 }
}

/** Port of OnDeviceGuestPollSchedule: when a guest at a phone-hosted table polls its host next. */
object OnDeviceGuestPollSchedule {
    /** Safety net for a dropped notice. Notices are never queued or acknowledged. */
    const val HEARTBEAT_MILLIS = 15_000L
    /** After sending an answer, the guest polls promptly this long, or until the answer lands. */
    const val ANSWER_WINDOW_MILLIS = 10_000L

    sealed interface Step {
        data class Poll(val afterMillis: Long) : Step
        data class AwaitNotice(val timeoutMillis: Long) : Step
    }

    fun next(hostAnnounces: Boolean, noticedRevision: Long, appliedRevision: Long?, awaitingAnswer: Boolean,
             sinceActionMillis: Long?, sinceLastPollMillis: Long, spacingMillis: Long): Step {
        val gap = maxOf(0L, spacingMillis - sinceLastPollMillis)
        // A host that never announced (an older build) is polled on the short timer, as before.
        if (!hostAnnounces || appliedRevision == null || noticedRevision > appliedRevision) return Step.Poll(gap)
        if (awaitingAnswer && sinceActionMillis != null && sinceActionMillis < ANSWER_WINDOW_MILLIS) return Step.Poll(gap)
        val remaining = HEARTBEAT_MILLIS - sinceLastPollMillis
        return if (remaining > gap) Step.AwaitNotice(remaining) else Step.Poll(gap)
    }
}

/**
 * Port of OnDeviceHostRetryPolicy: a guest retries a poll a few times when its host stops answering,
 * then gives up with the usual message. Only polls and hello are retried: an answer keeps its exact
 * request ID for the player's explicit retry, and a host that left ends the table through the roster.
 */
class OnDeviceHostRetryPolicy(private val delaysMillis: List<Long> = DEFAULT_DELAYS_MILLIS) {
    var attempts = 0; private set

    fun delayAfter(error: Throwable): Long? {
        if (error !is OnDeviceHostUnavailable || attempts >= delaysMillis.size) return null
        attempts += 1
        return delaysMillis[attempts - 1]
    }

    fun reset() { attempts = 0 }

    companion object { val DEFAULT_DELAYS_MILLIS = listOf(1_000L, 2_000L, 4_000L) }
}

/**
 * How often a local game asks its engine for the match (OnDeviceLocalPollSchedule in OnDeviceSession.swift). Every
 * poll returns the whole snapshot, so polling fast is only worth it while something can change.
 */
object OnDeviceLocalPollSchedule {
    /** The board just changed, or an answer is on its way. */
    const val ACTIVE_MILLIS = 300L
    /** Nothing changed for a few polls (the AI is thinking). */
    const val IDLE_MILLIS = 600L
    /**
     * The engine is waiting on this player: nothing can change until they answer, and an answer wakes the loop at
     * once. This is only a safety net (a failure notice, a late save notice).
     */
    const val AWAITING_PLAYER_MILLIS = 2_000L
    /** Unchanged polls before the idle spacing, and before the awaiting-player spacing. */
    const val IDLE_AFTER = 3
    const val AWAITING_AFTER = 8
    /**
     * A stack resolving right after this player's answer (a run of triggers, "Resolve all", a remembered answer): each
     * resolution shows as soon as the engine has it. Only while things keep changing, and only for a few seconds.
     */
    const val CHAIN_MILLIS = 120L
    const val CHAIN_WINDOW_MILLIS = 6_000L

    fun intervalMillis(idlePolls: Int, awaitingPlayer: Boolean, stackChain: Boolean = false): Long =
        if (awaitingPlayer && idlePolls >= AWAITING_AFTER) AWAITING_PLAYER_MILLIS
        else if (idlePolls >= IDLE_AFTER) IDLE_MILLIS else if (stackChain) CHAIN_MILLIS else ACTIVE_MILLIS
}

/**
 * Port of apps/ios/MagicMobile/OnDeviceSession.swift. One authenticated seat. UI state changes
 * only from a current engine poll. All state is read and written on the main thread; engine
 * calls suspend (the transport moves native work off the main thread).
 */
class OnDeviceSession(private val scope: CoroutineScope) {
    var snapshot by mutableStateOf<GameSnapshot?>(null); private set
    var matchID by mutableStateOf<String?>(null); private set
    var seatID by mutableStateOf<String?>(null); private set
    var pendingActionID by mutableStateOf<String?>(null); private set
    var pendingCardID by mutableStateOf<String?>(null); private set
    var isWorking by mutableStateOf(false); private set
    var isClosing by mutableStateOf(false); private set
    var status by mutableStateOf("Ready"); private set
    private var errorState by mutableStateOf<String?>(null)
    /** Each new error is a freeze-log breadcrumb. */
    var errorMessage: String?
        get() = errorState
        private set(value) { if (value != null && value != errorState) FreezeLog.crumb("Error: $value"); errorState = value }
    var isAutoPassing by mutableStateOf(false); private set
    var autoPassStatus by mutableStateOf(""); private set
    /** Answer actions this game's engine accepts (its `answerActions` capability); empty on older engines. */
    var supportedAnswerActions by mutableStateOf<Set<String>>(emptySet()); private set
    /** Questions and trigger orders this seat asked XMage to remember this game, for the "forget" controls. */
    var rememberedAnswers by mutableIntStateOf(0); private set
    var rememberedTriggerOrders by mutableIntStateOf(0); private set
    /** Standing instructions waiting for this seat's next answer of any kind (a preference, a reset), by type. */
    private var standingActions: Map<String, J> = emptyMap()
    private var activeRefreshes by mutableIntStateOf(0)

    private var allowsSeatScopedAutoYield = false
    private var responding = false
    private var waitingForPolls = false
    /** Consecutive polls that returned exactly the previous poll. */
    private var idlePolls = 0
    private val yieldPolicy = OnDeviceYieldPolicy()
    private var yieldJob: Job? = null
    private var yieldGeneration = UUID.randomUUID()
    private var client: EngineClient? = null
    private var poll: MatchPoll? = null
    private var messageLog = OnDeviceMessageLog()
    private var pollingJob: Job? = null
    private var closeEndpoint: (suspend () -> Unit)? = null
    /** Sees every applied poll: save/resume follows checkpoints and the game's end through it. */
    private var observer: ((MatchPoll) -> Unit)? = null
    private var epoch = UUID.randomUUID()
    private var visibilityEpoch = UUID.randomUUID()
    private var refreshSequence = 0L
    private var appliedRefreshSequence = 0L
    private var isForeground = true
    private var automaticPolling = true
    private var reconnectsAutomatically = false
    /** Set for a seat at a phone-hosted table; null for local and online games. */
    private var table: OnDeviceTableLink? = null
    /** Uptime of this seat's latest answer or concede, for prompt polling until it lands. */
    private var lastActionAt: Long? = null
    /** Backoff between a guest's poll retries after its host stops answering (shortened by tests). */
    var hostRetryDelaysMillis: List<Long> = OnDeviceHostRetryPolicy.DEFAULT_DELAYS_MILLIS

    private class Submission(val prompt: EnginePrompt, val answer: J, val requestID: UUID, val label: String)
    private var pending: Submission? = null

    /** The exact ability picked when activating a source with several; XMage's follow-up is answered with it. */
    private data class ChosenAbility(val sourceID: String, val abilityID: String, val activationPromptID: String)
    private var chosenAbility: ChosenAbility? = null
    /** A follow-up ability prompt answered automatically: its snapshot stays unpublished. */
    private var heldAbilitySnapshot: Pair<String, GameSnapshot>? = null
    private var abilityAutoAnswer: Job? = null
    /** Smart auto-pass (OnDeviceSmartPass); null leaves every priority to the player. */
    private var smartPass: OnDeviceSmartPass.Settings? = null
    private var smartPassJob: Job? = null
    private var smartPassGeneration = UUID.randomUUID()
    /** The last prompt smart pass answered: each prompt is passed at most once, never retried. */
    private var smartPassedPromptID: String? = null
    /** What the board is still showing; smart pass lets it finish before passing. */
    var presentationHold: BoardPresentationHold = BoardPresentationHold.shared
    /** Full control (long-press Pass, or the controls menu): smart pass stops at every priority until this turn ends. */
    var fullControlTurn by mutableStateOf<Long?>(null); private set
    /** A local log line was added since the last snapshot: the next poll republishes even if the game didn't change. */
    private var logChanged = false
    /** The freeze log's stall watch (docs/FREEZE_LOG.md): checked every 5 s while a game is on. */
    private val stall = FreezeStallTracker()
    private var stallJob: Job? = null
    private var lastSnapshotCrumb: String? = null

    /** The stack is resolving shortly after this seat's own answer (OnDeviceLocalPollSchedule.CHAIN_MILLIS). */
    private val inStackChain: Boolean get() {
        val at = lastActionAt ?: return false
        if (snapshot?.xmage?.stack.isNullOrEmpty()) return false
        return nowMillis() - at < OnDeviceLocalPollSchedule.CHAIN_WINDOW_MILLIS
    }

    private fun uptime(): Double = System.nanoTime() / 1_000_000_000.0
    private fun nowMillis(): Long = System.nanoTime() / 1_000_000

    suspend fun attach(client: EngineClient, matchID: String, seatID: String, autoPoll: Boolean = true,
                       allowsSeatScopedAutoYield: Boolean = false, reconnectsAutomatically: Boolean = false,
                       table: OnDeviceTableLink? = null, observe: ((MatchPoll) -> Unit)? = null,
                       answerActions: Set<String> = emptySet(), autoPassAfterCast: Boolean? = null,
                       smartPass: OnDeviceSmartPass.Settings? = null, close: suspend () -> Unit) {
        if (this.client != null || isWorking) throw EngineError.InvalidMessage("Close the active game first")
        this.client = client; this.matchID = matchID; this.seatID = seatID; observer = observe
        supportedAnswerActions = answerActions; rememberedAnswers = 0; rememberedTriggerOrders = 0; standingActions = emptyMap()
        comboHistory = emptyList(); comboOffer = null; comboDeclined = null; comboResult = null
        autoPassAfterCast?.let(::setAutoPassAfterCast)
        if (devicePaceHot) queueDevicePace()
        this.smartPass = smartPass; smartPassJob?.cancel(); smartPassJob = null; smartPassedPromptID = null; fullControlTurn = null
        this.allowsSeatScopedAutoYield = allowsSeatScopedAutoYield
        this.reconnectsAutomatically = reconnectsAutomatically
        this.table = table; lastActionAt = null
        autoPassStatus = ""
        closeEndpoint = close; automaticPolling = autoPoll; epoch = UUID.randomUUID()
        refreshSequence = 0; appliedRefreshSequence = 0; isClosing = false
        messageLog = OnDeviceMessageLog()
        status = "Starting game"
        stall.restart(uptime()); lastSnapshotCrumb = null
        FreezeLog.crumb("Game attached (${table?.role?.name?.lowercase() ?: "solo"})"); FreezeLog.gameChanged()
        if (autoPoll) beginStallWatch()
        try { refresh() } catch (error: Exception) {
            if (table != null && table.role == OnDeviceTableLink.Role.GUEST && error is OnDeviceHostUnavailable) {
                // The poll loop retries the host a few times before giving up.
                status = table.waitingStatus
            } else {
                if (!reconnectsAutomatically || error !is IOException) throw error
                status = "Reconnecting…"
                errorMessage = "Connection interrupted. Reconnecting to your game."
            }
        }
        beginPolling()
    }

    suspend fun refresh() {
        try { performRefresh() } catch (error: Exception) {
            stopAutoPass(OnDeviceYieldPolicy.StopReason.INTERRUPTED.message); throw error
        }
    }

    private suspend fun performRefresh() {
        val client = client ?: return
        val matchID = matchID ?: return
        val seatID = seatID ?: return
        if (!isForeground || isClosing || responding || waitingForPolls || (isAutoPassing && activeRefreshes != 0)) return
        activeRefreshes += 1
        try {
            val token = epoch
            val visibility = visibilityEpoch
            refreshSequence += 1
            val sequence = refreshSequence
            val next = try { client.poll(matchID, seatID, poll?.revision ?: 0) } catch (error: Exception) {
                // Obsolete reads must not interrupt a replacement or resumed session.
                if (epoch != token || visibilityEpoch != visibility || !isForeground || isClosing || error is CancellationException) return
                throw error
            }
            if (epoch != token || this.matchID != matchID || visibilityEpoch != visibility || !isForeground || isClosing) return
            if (next.matchID != matchID || next.seatID != seatID) throw EngineError.UnboundPeer
            // Submission can change at the same revision. An older in-flight poll must not restore a hidden choice.
            poll?.let { current -> if (next.revision < current.revision || (next.revision == current.revision && sequence <= appliedRefreshSequence)) return }
            // While the AI thinks, polls repeat the same board; do not re-adapt it every 300 ms. A repeated reply comes back
            // as the very same poll (EngineClient.poll), so the deep comparison is skipped too.
            val unchanged = (poll === next || poll?.raw == next.raw) && heldAbilitySnapshot == null && snapshot != null && !logChanged
            logChanged = false
            idlePolls = if (unchanged) idlePolls + 1 else 0
            val nextLog = messageLog.copy()
            if (!unchanged) nextLog.ingest(next)
            val autoAbility = chosenAbilityAnswer(next.prompt)
            var publishedLog = nextLog
            if (unchanged && autoAbility == null) {
                // Same board and prompt: keep the published snapshot.
            } else if (next.phase == "closed") {
                snapshot = null
                publishedLog = OnDeviceMessageLog()
                pending = null; pendingActionID = null; pendingCardID = null
            } else if (next.snapshot != null) {
                val adapted = OnDeviceSnapshotAdapter.snapshot(next, seatID, nextLog.entries)
                val prompt = next.prompt
                if (autoAbility != null && prompt != null) {
                    heldAbilitySnapshot = prompt.id to adapted
                    pendingActionID = "auto-ability-${autoAbility.abilityID}"; pendingCardID = autoAbility.sourceID
                } else {
                    heldAbilitySnapshot = null
                    snapshot = adapted
                }
            }
            if (!unchanged) noteProgress(next)
            messageLog = publishedLog
            poll = next
            observer?.invoke(next)
            appliedRefreshSequence = maxOf(appliedRefreshSequence, sequence)
            // A host tells its guests about each new revision, so they need not poll it constantly.
            table?.applied(next.revision)
            pending?.let { current ->
                if (next.prompt?.id != current.prompt.id || next.prompt?.revision != current.prompt.revision) {
                    pending = null; stall.answerLanded()
                    if (autoAbility == null) { pendingActionID = null; pendingCardID = null }
                }
            }
            val prompt = next.prompt
            if (autoAbility != null && prompt != null && abilityAutoAnswer?.isActive != true) {
                // The main dispatcher may run this to completion at once: register it before it starts.
                val job = scope.launch(start = CoroutineStart.LAZY) { answerChosenAbility(autoAbility, prompt.id) }
                abilityAutoAnswer = job
                job.start()
            }
            status = when (next.phase) {
                "ended" -> "Game complete"; "failed" -> "Game stopped"; "closed" -> "Game closed"; "starting" -> "Starting game"
                else -> "Live"
            }
            errorMessage = next.raw["failure"]["message"].string
            if (errorMessage != null) stopAutoPass(OnDeviceYieldPolicy.StopReason.INTERRUPTED.message)
            if (isAutoPassing) {
                val context = yieldContext
                if (context != null) {
                    val decision = yieldPolicy.evaluate(context, uptime())
                    if (decision is OnDeviceYieldPolicy.Decision.Stop) stopAutoPass(decision.reason.message)
                } else stopAutoPass(OnDeviceYieldPolicy.StopReason.INTERRUPTED.message)
            }
            scheduleSmartPass()
            beginPolling()
        } finally {
            activeRefreshes -= 1
        }
    }

    /** Smart auto-pass settings changed (Settings or the phase stops sheet); applies from the next prompt. */
    fun setSmartPass(settings: OnDeviceSmartPass.Settings) {
        if (smartPass == null) return
        smartPass = settings
        scheduleSmartPass()
    }

    private val currentTurn: Long? get() = poll?.snapshot?.get("gameView")?.get("turn")?.integer

    /** Full control is on for the turn being played. */
    val isFullControl: Boolean get() = fullControlTurn != null && fullControlTurn == currentTurn

    /** Turns full control for this turn on or off. Turning it on stops a smart pass that hasn't been sent yet. */
    fun toggleFullControl() {
        if (isFullControl) {
            fullControlTurn = null
            scheduleSmartPass()
        } else {
            fullControlTurn = currentTurn
            smartPassGeneration = UUID.randomUUID(); smartPassJob?.cancel(); smartPassJob = null
        }
    }

    /** What a smart pass let go by, for the game log: the top of the stack, else the step. */
    private fun autoPassLabel(situation: OnDeviceSmartPass.Situation, shown: GameSnapshot): String =
        shown.stackTopFirst.firstOrNull()?.displayName ?: OnDeviceSmartPass.Step.fromEngine(situation.step)?.title ?: "Priority"

    private val smartPassSituation: OnDeviceSmartPass.Situation? get() {
        val context = yieldContext ?: return null
        val view = poll?.snapshot?.get("gameView") ?: return null
        val owner = view["players"].array?.firstOrNull { it["playerId"].string == context.viewerID } ?: return null
        return OnDeviceSmartPass.Situation(context, view["step"].string, OnDeviceSmartPass.hasPlay(view), OnDeviceSmartPass.manaFloating(owner),
            OnDeviceSmartPass.topStackIsMine(poll?.snapshot, context.viewerID), OnDeviceSmartPass.hasResponse(view),
            !context.emptyStack && (snapshot?.let(OnDeviceSmartPass::threatensViewer) ?: false), OnDeviceSmartPass.hasAbilityResponse(view))
    }

    private fun smartPassPrompt(): OnDeviceYieldPolicy.Prompt? {
        val settings = smartPass ?: return null
        val situation = smartPassSituation ?: return null
        return OnDeviceSmartPass.passPrompt(situation, settings)?.takeIf { it.id != smartPassedPromptID }
    }

    /**
     * Passes this seat's ordinary priority when it has nothing to play, or nothing it stops for.
     * The same pass a tap sends, once per prompt; a failure is left to the player, never retried.
     */
    private fun scheduleSmartPass() {
        if (smartPassJob != null || isAutoPassing || isFullControl || pending != null || pendingActionID != null || errorMessage != null ||
            heldAbilitySnapshot != null || abilityAutoAnswer != null || isClosing) return
        val prompt = smartPassPrompt() ?: return
        val token = epoch
        val generation = UUID.randomUUID()
        smartPassGeneration = generation
        // The main dispatcher may run this to completion at once: register it before it starts.
        val job = scope.launch(start = CoroutineStart.LAZY) {
            var sent = false
            try {
                // The response lane frees right after the answer that led here.
                repeat(150) { if (isWorking || activeRefreshes != 0) delay(20) }
                waitForBoardPresentation()
                // Re-check against the poll applied meanwhile: the same prompt, still a pass.
                val current = smartPassPrompt()
                val shown = snapshot
                val situation = smartPassSituation
                if (epoch != token || isWorking || pending != null || pendingActionID != null || isAutoPassing || isFullControl ||
                    current == null || current.id != prompt.id || current.revision != prompt.revision || shown == null || situation == null) return@launch
                smartPassedPromptID = current.id
                messageLog.noteAutoPass(autoPassLabel(situation, shown), current.id)
                logChanged = true
                val command = GameCommand(type = "pass_priority", gameId = situation.context.matchID, playerId = situation.context.viewerID,
                    promptId = current.id, messageId = current.revision.toInt(), expectedBridgeRevision = shown.bridgeRevision)
                try { submit(command, "Pass priority", OnDeviceYieldPolicy.SMART_PASS_ACTION_PREFIX + current.id); sent = true }
                catch (error: CancellationException) { throw error }
                catch (_: Exception) { }
            } finally {
                if (smartPassGeneration == generation) smartPassJob = null
            }
            // The answer's own refresh may already show the next routine priority.
            if (sent && smartPassGeneration == generation) scheduleSmartPass()
        }
        smartPassJob = job
        job.start()
    }

    /**
     * Lets the board finish what it is showing (an opponent's removal spell read at the centre, the creature
     * it exiles) before smart pass moves the game on: first the board takes in the published snapshot, then
     * its held effects play out, never longer than [BoardPresentationHold.MAXIMUM_WAIT_MS].
     */
    private suspend fun waitForBoardPresentation() {
        // A long combo loop shows the board once a round, so there's nothing to wait for between its steps.
        if (comboFastMode) return
        val key = BoardFXRevisionKey(snapshot ?: return)
        val start = System.currentTimeMillis()
        fun elapsed() = System.currentTimeMillis() - start
        while (presentationHold.ingested != key && elapsed() < BoardPresentationHold.INGEST_WAIT_MS) delay(20)
        while (elapsed() < BoardPresentationHold.MAXIMUM_WAIT_MS) {
            val left = (presentationHold.until ?: break) - System.currentTimeMillis()
            if (left <= 0) break
            delay(minOf(left, 100L))
        }
        // Holding a card to read it holds the pass too, as tapping the reference game's spell does (the Arena board).
        while (presentationHold.reading && elapsed() < BoardPresentationHold.READING_WAIT_MS) delay(100)
    }

    val canEndTurn: Boolean get() = canStartYield(OnDeviceYieldPolicy.Mode.SAFE_END_TURN)
    val canEndTurnSkippingResponses: Boolean get() = canStartYield(OnDeviceYieldPolicy.Mode.END_TURN_SKIPPING_RESPONSES)
    val canSkipToMyTurn: Boolean get() = canStartYield(OnDeviceYieldPolicy.Mode.UNTIL_MY_TURN)

    /** Availability follows the game, not the poll loop: an in-flight refresh must not flicker Skip. */
    private fun canStartYield(mode: OnDeviceYieldPolicy.Mode): Boolean {
        if (isAutoPassing || isClosing || pending != null || errorMessage != null) return false
        val context = yieldContext ?: return false
        return OnDeviceYieldPolicy.canStart(context, mode)
    }

    /** Cancellable local scheduling of ordinary passes, not an engine skip-turn command. */
    fun endTurn() = startYield(OnDeviceYieldPolicy.Mode.SAFE_END_TURN)
    fun endTurnSkippingResponses() = startYield(OnDeviceYieldPolicy.Mode.END_TURN_SKIPPING_RESPONSES)
    fun skipToMyTurn() = startYield(OnDeviceYieldPolicy.Mode.UNTIL_MY_TURN)

    private fun startYield(mode: OnDeviceYieldPolicy.Mode) {
        val context = yieldContext
        if (!canStartYield(mode) || context == null || !yieldPolicy.start(context, uptime(), mode)) return
        isAutoPassing = true
        autoPassStatus = mode.status
        yieldGeneration = UUID.randomUUID()
        val generation = yieldGeneration
        val token = epoch
        yieldJob = scope.launch {
            var lastPoll = nowMillis()
            try {
                while (isActive) {
                    waitForNextPoll(lastPoll, 300)
                    lastPoll = nowMillis()
                    if (epoch != token || yieldGeneration != generation || !isAutoPassing) return@launch
                    if (isWorking || activeRefreshes != 0) continue
                    // A new authenticated poll, never the rendered snapshot, authorizes each pass.
                    refresh()
                    lastPoll = nowMillis()
                    if (!isActive || epoch != token || yieldGeneration != generation || !isAutoPassing) return@launch
                    if (isWorking || activeRefreshes != 0) continue
                    val current = yieldContext ?: run { stopAutoPass(OnDeviceYieldPolicy.StopReason.INTERRUPTED.message); return@launch }
                    when (val decision = yieldPolicy.evaluate(current, uptime())) {
                        is OnDeviceYieldPolicy.Decision.Wait -> continue
                        is OnDeviceYieldPolicy.Decision.Stop -> { stopAutoPass(decision.reason.message); return@launch }
                        is OnDeviceYieldPolicy.Decision.Pass -> {
                            val prompt = poll?.prompt
                            val shown = snapshot
                            if (pending != null || prompt == null || prompt.id != decision.prompt.id || prompt.revision != decision.prompt.revision || shown == null) continue
                            yieldPolicy.recordPass(decision.prompt)
                            val command = GameCommand(type = "pass_priority", gameId = current.matchID, playerId = current.viewerID,
                                promptId = prompt.id, messageId = prompt.revision.toInt(), expectedBridgeRevision = shown.bridgeRevision)
                            submit(command, "Pass priority", OnDeviceYieldPolicy.YIELD_PASS_ACTION_PREFIX + prompt.id)
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (yieldGeneration != generation) return@launch
                // Keep uncertain pending responses for the explicit retry UI; never retry automatically.
                stopAutoPass(OnDeviceYieldPolicy.StopReason.INTERRUPTED.message)
            }
        }
    }

    fun stopAutoPass() = stopAutoPass("Auto-pass stopped. A pass already sent may still finish.")

    private fun stopAutoPass(reason: String) {
        if (!isAutoPassing && yieldJob == null) return
        yieldGeneration = UUID.randomUUID(); yieldPolicy.stop(); isAutoPassing = false
        yieldJob?.cancel(); yieldJob = null; autoPassStatus = reason
    }

    private val yieldContext: OnDeviceYieldPolicy.Context? get() {
        val poll = poll ?: return null
        val root = poll.snapshot ?: return null
        val view = root["gameView"] ?: return null
        val viewer = root["enginePlayerId"].string ?: return null
        if (view["myPlayerId"].string != viewer) return null
        val turn = view["turn"].integer ?: return null
        val active = view["activePlayerId"].string ?: return null
        val stack = view["stack"].obj ?: return null
        val controls = root["controlledPlayerViews"].obj ?: return null
        val players = view["players"].array ?: return null
        val owner = players.firstOrNull { it["playerId"].string == viewer } ?: return null
        if (owner["isHuman"].bool != true) return null
        val priority = owner["hasPriority"].bool ?: return null
        val timer = owner["timerActive"].bool ?: return null
        val prompt = poll.prompt?.let {
            OnDeviceYieldPolicy.Prompt(it.id, it.revision, it.kind, it.payload["selectMode"].string, it.responseTypes.contains("boolean"),
                it.submitted, it.payload["manaPlayerId"].string)
        }
        // `controlled` is only a viewer marker upstream. A routed self-priority prompt and active timer are required.
        val selfAuthority = controls.isEmpty() && (!priority || timer) && (prompt == null || priority)
        // A skip that passes responses still stops for an opponent's removal or sweeper, if you asked to (Stop for Removal).
        val threat = stack.isNotEmpty() && (smartPass?.stopForThreats ?: true) && (snapshot?.let(OnDeviceSmartPass::threatensViewer) ?: false)
        return OnDeviceYieldPolicy.Context(poll.matchID, poll.seatID, viewer, active, turn, poll.phase, allowsSeatScopedAutoYield,
            isForeground && !isClosing, stack.isEmpty(), selfAuthority, poll.resyncRequired, prompt, threat)
    }

    suspend fun send(action: LegalAction) {
        stopAutoPass()
        val snapshot = snapshot
        val current = snapshot?.legalActions?.firstOrNull { it.id == action.id }
            ?: throw EngineError.InvalidMessage("This action is no longer available")
        send(ComboLoop.commandFrom(current, snapshot.id, snapshot.bridgeRevision), current.label, current.id)
    }

    suspend fun send(command: GameCommand, label: String, actionID: String) {
        stopAutoPass()
        val decision = snapshot
        submit(command, label, actionID)
        noteComboStep(command, label, actionID, decision)
    }

    // MARK: Combo loop shortcut (ComboLoop)

    /** Solo games only: the root turns it on for games against the AI. */
    var comboLoopsAllowed = false
        set(value) { field = value; if (!value) { comboHistory = emptyList(); comboOffer = null } }
    /** A round the player has made three times in a row this turn, offered for repeating. */
    var comboOffer by mutableStateOf<List<ComboStep>?>(null); private set
    /** Repeating a round: how far it has got, and the last few rounds and notes. */
    var comboRun by mutableStateOf<ComboRun?>(null); private set
    /** The line shown when repeating stops: rounds, life changes and why. */
    var comboResult by mutableStateOf<String?>(null)
    /**
     * What the board shows while a loop repeats: the game without the prompts the repeats answer, updated after every step for a
     * short run (so its effects play) and once a round for a long one.
     */
    private var comboPresented by mutableStateOf<GameSnapshot?>(null)
    data class ComboRun(val round: List<ComboStep>, val mode: ComboRepeat, val done: Int, val lines: List<String> = emptyList())
    /** The board's snapshot: the live game, or the repeats' quiet copy while a loop runs. */
    val presentedSnapshot: GameSnapshot? get() = if (comboRun == null) snapshot else comboPresented ?: snapshot?.withoutPrompts()
    private var comboHistory: List<Pair<ComboStep, Int>> = emptyList()
    private var comboDeclined: List<ComboStep>? = null
    @Volatile private var comboStopRequested = false
    @Volatile private var comboFastMode = false
    private var comboJob: Job? = null

    private fun noteComboStep(command: GameCommand, label: String, actionID: String, decision: GameSnapshot?) {
        if (!comboLoopsAllowed || comboRun != null) return
        when (val note = ComboLoop.note(command, label, actionID, decision)) {
            ComboNote.Ignore -> return
            ComboNote.Breaks -> { comboHistory = emptyList(); comboOffer = null }
            is ComboNote.Step -> {
                val turn = decision?.turn ?: 0
                // A loop is offered only for rounds made in one turn.
                if (comboHistory.lastOrNull()?.second?.let { it != turn } == true) comboHistory = emptyList()
                comboHistory = (comboHistory + (note.step to turn)).takeLast(ComboLoop.HISTORY_LIMIT)
                val round = ComboLoop.cycle(comboHistory.map { it.first })
                comboOffer = if (round != null && round != comboDeclined) round else null
            }
        }
    }

    /** The player said no to this round: it isn't offered again until they make a different one. */
    fun declineComboLoop() { comboDeclined = comboOffer; comboOffer = null }

    /**
     * Repeats the offered round: a number of times, until a step can't be taken, or until every opponent has lost (at most
     * ComboLoop.MAX_REPEATS rounds).
     */
    fun startComboLoop(mode: ComboRepeat) {
        val round = comboOffer ?: return
        val start = snapshot ?: return
        if (comboRun != null) return
        comboOffer = null; comboResult = null; comboStopRequested = false
        comboPresented = start.withoutPrompts()
        comboRun = ComboRun(round, mode, 0)
        comboJob = scope.launch { runComboLoop(round, mode, start) }
    }

    fun stopComboLoop() { comboStopRequested = true }

    private fun noteComboLine(line: String) { comboRun = comboRun?.let { it.copy(lines = (it.lines + line).takeLast(3)) } }

    private suspend fun runComboLoop(round: List<ComboStep>, mode: ComboRepeat, start: GameSnapshot) {
        // A long run skips the board's effects and shows the board once a round; a short one plays them at a pace you can follow.
        val watch = mode.watchable
        comboFastMode = !watch
        io.magicmobile.android.game.BoardFXLevel.suppressedForLoop = !watch
        var rounds = 0
        var stop: ComboLoopStop = ComboLoopStop.Finished
        try {
            val limit = minOf(mode.count ?: ComboLoop.MAX_REPEATS, ComboLoop.MAX_REPEATS)
            var unchanged = 0
            var lastDigest = ComboLoop.digest(start)
            val prefer = HashMap<Int, List<String>>()
            repeating@ while (rounds < limit) {
                var chosen = emptyList<String>()
                for ((index, step) in round.withIndex()) {
                    val replay = when (val wait = waitForComboStep(step, prefer[index].orEmpty())) {
                        is ComboWait.Stop -> { stop = wait.reason; break@repeating }
                        is ComboWait.Ready -> wait.replay
                    }
                    try { submit(replay.command, replay.label, replay.actionID) }
                    catch (error: CancellationException) { throw error }
                    catch (error: Exception) { stop = ComboLoopStop.Failed(error.message ?: "The game didn't take that step."); break@repeating }
                    if (replay.chosenNames.isNotEmpty()) {
                        prefer[index] = replay.chosenNames
                        if (chosen.isEmpty() || step.targets.any { it.controller == "opponent" }) chosen = replay.chosenNames
                    }
                    replay.retargeted?.let { (from, to) -> noteComboLine("$from is gone, now $to") }
                    if (watch) snapshot?.let { comboPresented = it.withoutPrompts() }
                }
                rounds += 1
                comboRun = comboRun?.copy(done = rounds)
                noteComboLine(ComboLoop.roundLine(rounds, round, chosen))
                val current = snapshot ?: break
                comboPresented = current.withoutPrompts()
                if (current.isCompleted) { stop = ComboLoopStop.GameOver; break }
                if (watch) { waitForBoardPresentation(); delay(450) }
                // Open-ended repeats stop a loop that has stopped doing anything visible; a count simply runs out.
                if (mode.count == null) {
                    val digest = ComboLoop.digest(current)
                    unchanged = if (digest == lastDigest) unchanged + 1 else 0
                    lastDigest = digest
                    if (unchanged >= ComboLoop.UNCHANGED_ROUNDS_TO_STOP) { stop = ComboLoopStop.NothingChanged; break }
                }
            }
            if (mode.count == null && stop == ComboLoopStop.Finished) stop = ComboLoopStop.ReachedLimit
        } finally {
            io.magicmobile.android.game.BoardFXLevel.suppressedForLoop = false
            comboFastMode = false
            val summary = ComboLoop.summary(rounds, start, snapshot ?: start)
            val last = stop
            comboResult = when {
                last == ComboLoopStop.Finished || last == ComboLoopStop.GameOver -> summary
                last is ComboLoopStop.StepMissing && mode == ComboRepeat.UntilCant && rounds > 0 -> "$summary, until it couldn't go on: ${last.why}."
                else -> "$summary. ${last.message}"
            }
            comboRun = null; comboPresented = null; comboHistory = emptyList(); comboDeclined = round; comboJob = null
        }
    }

    private sealed class ComboWait {
        data class Ready(val replay: ComboReplay) : ComboWait()
        data class Stop(val reason: ComboLoopStop) : ComboWait()
    }

    /**
     * Waits for this step's answer to be possible: the session idle, the player's own triggers resolved when the step was taken
     * with an empty stack (passing priority for them), and the step among the choices. Stops when the game ends, an opponent
     * responds, the player is asked something the round doesn't answer, or nothing comes.
     */
    private suspend fun waitForComboStep(step: ComboStep, prefer: List<String>): ComboWait {
        val started = System.currentTimeMillis()
        var askedSince: Long? = null
        var passedFor: String? = null
        fun askedTooLong(): Boolean {
            val since = askedSince ?: System.currentTimeMillis().also { askedSince = it }
            return System.currentTimeMillis() - since > 3_000
        }
        while (System.currentTimeMillis() - started < 45_000) {
            if (comboStopRequested || isClosing) return ComboWait.Stop(ComboLoopStop.StoppedByPlayer)
            val current = snapshot
            if (current != null) {
                if (current.isCompleted || current.isSpectating) return ComboWait.Stop(ComboLoopStop.GameOver)
                val idle = !isWorking && !isAutoPassing && pendingActionID == null && pending == null && smartPassJob == null &&
                    heldAbilitySnapshot == null && abilityAutoAnswer == null
                if (idle) {
                    if (ComboLoop.opponentResponded(current)) return ComboWait.Stop(ComboLoopStop.OpponentResponded)
                    val asked = current.legalActions?.isNotEmpty() == true || current.promptEnvelopeV2?.let { current.isViewer(it.playerId) } == true
                    val pass = ComboLoop.pass(current)
                    if (ComboLoop.waitsForStack(step, current)) {
                        // The round's own triggers are still resolving: pass for them, once per prompt.
                        val key = current.promptEnvelopeV2?.id ?: "${current.bridgeRevision ?: 0}"
                        if (pass != null && passedFor != key) {
                            passedFor = key; askedSince = null
                            try { submit(pass.command, pass.label, "combo-loop-pass-$key") }
                            catch (error: CancellationException) { throw error }
                            catch (error: Exception) { return ComboWait.Stop(ComboLoopStop.Failed(error.message ?: "The game didn't take that step.")) }
                            continue
                        }
                        if (asked && pass == null && askedTooLong()) return ComboWait.Stop(ComboLoopStop.StepMissing("a choice the loop doesn't make came up"))
                    } else {
                        val replay = ComboLoop.command(step, current, prefer)
                        if (replay != null) return ComboWait.Ready(replay)
                        if (asked) { if (askedTooLong()) return ComboWait.Stop(ComboLoopStop.StepMissing(ComboLoop.missing(step))) }
                        else askedSince = null
                    }
                }
            }
            delay(120)
        }
        return ComboWait.Stop(ComboLoopStop.StepMissing(ComboLoop.missing(step)))
    }

    /** Passing priority after casting a spell (Settings), sent with this seat's next answer. */
    fun setAutoPassAfterCast(enabled: Boolean) {
        if ("autoPassAfterCast" !in supportedAnswerActions) return
        standingActions = standingActions + ("autoPassAfterCast" to jsonObject("type" to JsonPrimitive("autoPassAfterCast"), "enabled" to JsonPrimitive(enabled)))
    }

    /**
     * The phone is hot and the engine runs on it: AI seats think for less time (answer action devicePace, engine release C).
     * The root sets it from DeviceHeat; it rides on the next answer, and again after every attach.
     */
    var devicePaceHot = false
        set(value) { if (field != value) { field = value; queueDevicePace() } }

    private fun queueDevicePace() {
        if ("devicePace" !in supportedAnswerActions) return
        standingActions = standingActions + ("devicePace" to jsonObject("type" to JsonPrimitive("devicePace"), "hot" to JsonPrimitive(devicePaceHot)))
    }

    /** Forget every remembered answer (asked again from the next one). */
    fun forgetRememberedAnswers() {
        if ("resetRememberedAnswers" !in supportedAnswerActions) return
        standingActions = standingActions + ("resetRememberedAnswers" to jsonObject("type" to JsonPrimitive("resetRememberedAnswers")))
        rememberedAnswers = 0
    }

    /** Forget every remembered trigger order. */
    fun forgetTriggerOrder() {
        if ("resetTriggerOrder" !in supportedAnswerActions) return
        standingActions = standingActions + ("resetTriggerOrder" to jsonObject("type" to JsonPrimitive("resetTriggerOrder")))
        rememberedTriggerOrders = 0
    }

    private suspend fun submit(command: GameCommand, label: String, actionID: String) {
        val token = epoch
        acquireResponseSlot()
        try {
            val snapshot = snapshot
            val prompt = poll?.prompt
            if (client == null || matchID == null || seatID == null || snapshot == null || prompt == null || isClosing ||
                pendingActionID != null || !isForeground || snapshot.isCompleted || poll?.phase in setOf("ended", "failed", "closed") ||
                command.gameId != matchID || command.playerId != snapshot.viewerID ||
                (command.expectedBridgeRevision != null && command.expectedBridgeRevision != snapshot.bridgeRevision)) {
                throw EngineError.InvalidMessage("The game or decision changed. Refresh before choosing again.")
            }
            val requested = command.answerActions.orEmpty().filter { it in supportedAnswerActions }
            val standing = standingActions.values.toList()
            val answer = OnDevicePromptAdapter.answer(OnDevicePromptAdapter.answer(command, prompt, snapshot.viewerID),
                OnDevicePromptAdapter.answerActions(requested, command, prompt) + standing)
            val ability = command.abilityId
            val source = command.sourceInstanceId ?: command.cardInstanceId
            if (command.type in setOf("make_mana", "activate_ability", "play_land", "cast_spell") && ability != null && source != null) {
                chosenAbility = ChosenAbility(source, ability, prompt.id)
            } else if (command.type != "choose_ability") {
                chosenAbility = null
            }
            pending = Submission(prompt, answer, UUID.randomUUID(), label)
            pendingActionID = actionID; pendingCardID = command.cardInstanceId ?: command.sourceInstanceId
            performPendingResponse()
            // Delivered: the standing instructions went with it (one changed meanwhile stays queued), and what was
            // remembered is counted for the forget controls.
            if (epoch == token) {
                standingActions = standingActions.filterValues { it !in standing }
                if ("rememberAnswer" in requested) rememberedAnswers += 1
                if ("rememberTriggerFirst" in requested) rememberedTriggerOrders += 1
            }
        } finally {
            if (epoch == token) { isWorking = false; responding = false; waitingForPolls = false }
        }
    }

    suspend fun retryPending() {
        stopAutoPass()
        val requestID = pending?.requestID
        val token = epoch
        acquireResponseSlot()
        try {
            val pending = pending
            if (pending == null || pending.requestID != requestID || poll?.prompt?.id != pending.prompt.id ||
                poll?.prompt?.revision != pending.prompt.revision || poll?.phase in setOf("ended", "failed", "closed")) {
                throw EngineError.InvalidMessage("There is no pending response to retry")
            }
            performPendingResponse()
        } finally {
            if (epoch == token) { isWorking = false; responding = false; waitingForPolls = false }
        }
    }

    /** Reserve the response lane before suspending so refreshes cannot overtake the tap. */
    private suspend fun acquireResponseSlot() {
        if (isWorking || isClosing || !isForeground || client == null) throw EngineError.InvalidMessage("Wait for the current operation before responding")
        val token = epoch
        isWorking = true
        waitingForPolls = true
        try {
            while (activeRefreshes > 0) {
                if (epoch != token || !isForeground || isClosing) throw EngineError.InvalidMessage("The game changed while waiting to respond")
                delay(10)
            }
            if (epoch != token || !isForeground || isClosing) throw EngineError.InvalidMessage("The game changed while waiting to respond")
        } catch (error: Exception) {
            if (epoch == token) { isWorking = false; waitingForPolls = false }
            throw error
        }
    }

    private suspend fun performPendingResponse() {
        val pending = pending ?: throw EngineError.InvalidMessage("There is no pending response to retry")
        val client = client ?: throw EngineError.InvalidMessage("There is no pending response to retry")
        val matchID = matchID ?: throw EngineError.InvalidMessage("There is no pending response to retry")
        val seatID = seatID ?: throw EngineError.InvalidMessage("There is no pending response to retry")
        val token = epoch
        var acknowledged = false
        try {
            responding = true
            waitingForPolls = false
            noteAction()
            stall.answerSent(uptime())
            FreezeLog.crumb("Sent ${pending.label} (${pending.prompt.kind})")
            client.respond(matchID, seatID, pending.prompt, pending.answer, pending.requestID)
            acknowledged = true
            responding = false
            if (epoch != token) return
            errorMessage = null; status = "${pending.label} sent; waiting for XMage"
            refresh()
        } catch (error: Exception) {
            responding = false
            if (epoch == token && error !is CancellationException) {
                errorMessage = error.message
                // An engine rejection is certain; a timeout or busy RPC is not: keep the exact request for retry.
                if (!acknowledged && error is EngineError.Rejected && error.code != "rpc_busy") {
                    this.pending = null; pendingActionID = null; pendingCardID = null; stall.answerLanded()
                    try { refresh() } catch (_: Exception) {}
                }
            }
            throw error
        }
    }

    /** Only a fresh ability prompt offering the exact chosen ability qualifies; anything else forgets it. */
    private fun chosenAbilityAnswer(prompt: EnginePrompt?): ChosenAbility? {
        val chosen = chosenAbility ?: return null
        prompt ?: return null
        if (prompt.id == chosen.activationPromptID) return null
        val rows = prompt.payload["abilities"].array
        if (prompt.kind !in setOf("CHOOSE_ABILITY", "PICK_ABILITY") || prompt.submitted || rows == null ||
            rows.none { it["id"].string == chosen.abilityID }) {
            chosenAbility = null
            return null
        }
        return chosen
    }

    private suspend fun answerChosenAbility(chosen: ChosenAbility, promptID: String) {
        try {
            // The activation's own response slot releases right after its refresh.
            repeat(150) { if (isWorking) delay(20) }
            chosenAbility = null
            val matchID = matchID
            val snapshot = snapshot
            if (matchID == null || snapshot == null || poll?.prompt?.id != promptID) { publishHeldAbilityPrompt(); return }
            val command = GameCommand(type = "choose_ability", gameId = matchID, playerId = snapshot.viewerID, abilityId = chosen.abilityID,
                promptId = promptID, messageId = poll?.prompt?.revision?.toInt())
            pendingActionID = null
            try {
                submit(command, "Choose ability", "auto-ability-${chosen.abilityID}")
                heldAbilitySnapshot = null
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                publishHeldAbilityPrompt()
            }
        } finally {
            abilityAutoAnswer = null
        }
    }

    /** Show the held ability prompt so the player can answer it by hand. */
    private fun publishHeldAbilityPrompt() {
        heldAbilitySnapshot?.let { (promptID, held) -> if (poll?.prompt?.id == promptID) snapshot = held }
        heldAbilitySnapshot = null
        if (pendingActionID?.startsWith("auto-ability-") == true) { pendingActionID = null; pendingCardID = null }
    }

    /** This seat concedes. In a pod the others play on and this seat keeps polling as a spectator. */
    suspend fun concede() {
        stopAutoPass()
        val client = client
        val matchID = matchID
        val seatID = seatID
        if (client == null || matchID == null || seatID == null || isClosing || poll?.phase in setOf("ended", "failed", "closed")) {
            throw EngineError.InvalidMessage("This game is already over.")
        }
        abilityAutoAnswer?.cancel(); abilityAutoAnswer = null
        smartPassJob?.cancel(); smartPassJob = null
        chosenAbility = null; heldAbilitySnapshot = null
        noteAction()
        FreezeLog.crumb("Conceded")
        client.concede(matchID, seatID)
        // The engine retracted this seat's open question; nothing sent earlier can still apply.
        pending = null; pendingActionID = null; pendingCardID = null
        errorMessage = null; status = "Conceded"
        try { refresh() } catch (_: Exception) {}
        beginPolling()
    }

    suspend fun close() {
        comboStopRequested = true; comboJob?.cancel(); comboHistory = emptyList(); comboOffer = null
        stopAutoPass()
        smartPassJob?.cancel(); smartPassJob = null
        abilityAutoAnswer?.cancel(); abilityAutoAnswer = null
        chosenAbility = null; heldAbilitySnapshot = null
        if (isWorking) throw EngineError.InvalidMessage("Wait for the current operation before closing")
        val closeEndpoint = closeEndpoint ?: return
        isWorking = true; isClosing = true; pollingJob?.cancel(); pollingJob = null
        status = "Closing game"
        epoch = UUID.randomUUID()
        try {
            try { closeEndpoint() } catch (error: Exception) {
                errorMessage = error.message
                status = "Closing interrupted. Leave again to retry cleanup."
                throw error
            }
            isClosing = false
            refreshSequence = 0; appliedRefreshSequence = 0
            epoch = UUID.randomUUID(); client = null; matchID = null; seatID = null; poll = null; snapshot = null
            table = null; lastActionAt = null; observer = null
            stallJob?.cancel(); stallJob = null; FreezeLog.gameEnded(); FreezeLog.crumb("Game closed")
            messageLog = OnDeviceMessageLog()
            this.closeEndpoint = null; pending = null; pendingActionID = null; pendingCardID = null; errorMessage = null; status = "Ready"
        } finally {
            isWorking = false
        }
    }

    fun setForeground(value: Boolean) {
        if (isForeground != value) visibilityEpoch = UUID.randomUUID()
        // Nothing polls in the background, so the game can't look stalled from time spent there.
        if (value && !isForeground) stall.resumed(uptime())
        if (!value) { stopAutoPass(); smartPassJob?.cancel(); smartPassJob = null }
        isForeground = value
        if (value) beginPolling() else {
            pollingJob?.cancel(); pollingJob = null
            if (!isClosing && client != null && poll?.phase !in setOf("ended", "failed", "closed")) {
                status = "Paused while this app is in the background"
            }
        }
    }

    private fun beginPolling() {
        if (pollingJob != null || !automaticPolling || client == null || !isForeground || isClosing ||
            poll?.phase in setOf("ended", "failed", "closed")) return
        pollingJob = scope.launch {
            var failures = 0
            val hostRetries = OnDeviceHostRetryPolicy(hostRetryDelaysMillis)
            var lastPoll = nowMillis()
            // A new loop (attach, return to the foreground, a manual refresh) polls on the short
            // timer first, so a guest catches up on notices it could not receive meanwhile.
            var firstPoll = true
            var retryNow = false
            while (isActive) {
                try {
                    val interval = if (reconnectsAutomatically) 1000L
                        else OnDeviceLocalPollSchedule.intervalMillis(idlePolls, awaitsLocalAnswer, inStackChain)
                    if (firstPoll) delay(if (reconnectsAutomatically) interval else minOf(interval, OnDeviceLocalPollSchedule.IDLE_MILLIS))
                    else if (!retryNow) waitForNextPoll(lastPoll, interval)
                    firstPoll = false; retryNow = false
                    if (isAutoPassing) { lastPoll = nowMillis(); continue }
                    refresh()
                    lastPoll = nowMillis()
                    failures = 0; hostRetries.reset()
                    if (poll?.phase in setOf("ended", "failed", "closed")) { pollingJob = null; return@launch }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    lastPoll = nowMillis()
                    if (reconnectsAutomatically && error is IOException) {
                        failures += 1
                        status = "Reconnecting…"
                        errorMessage = "Connection interrupted. Reconnecting to your game."
                        delay(minOf(10, failures * 2) * 1000L)
                        continue
                    }
                    // A lost host answer: poll again (never re-send an answer) before giving up.
                    val table = table
                    val backoff = if (table?.role == OnDeviceTableLink.Role.GUEST) hostRetries.delayAfter(error) else null
                    if (table != null && backoff != null) {
                        status = table.waitingStatus
                        delay(backoff)
                        retryNow = true
                        continue
                    }
                    pollingJob = null
                    errorMessage = error.message; status = "Updates interrupted. Refresh to retry."
                    return@launch
                }
            }
        }
    }

    /**
     * Local and online games poll on a short timer. A guest at a phone-hosted table waits for its
     * host's revision notice, polls promptly while its own answer is outstanding, and otherwise
     * polls only on the heartbeat.
     */
    private suspend fun waitForNextPoll(lastPoll: Long, intervalMillis: Long) {
        val table = table
        if (table == null || table.role != OnDeviceTableLink.Role.GUEST) {
            // The long wait (the engine is waiting on this player) ends as soon as an answer goes out or the board
            // changes, so the next poll is prompt again.
            val action = lastActionAt
            var remaining = intervalMillis
            while (remaining > 0) {
                val step = minOf(remaining, OnDeviceLocalPollSchedule.ACTIVE_MILLIS)
                delay(step)
                remaining -= step
                if (lastActionAt != action || idlePolls < OnDeviceLocalPollSchedule.IDLE_AFTER) return
            }
            return
        }
        while (true) {
            val now = nowMillis()
            val step = OnDeviceGuestPollSchedule.next(table.hostAnnounces, table.noticedRevision, poll?.revision,
                pending != null || abilityAutoAnswer != null, lastActionAt?.let { now - it }, now - lastPoll, intervalMillis)
            when (step) {
                is OnDeviceGuestPollSchedule.Step.Poll -> { if (step.afterMillis > 0) delay(step.afterMillis) else yield(); return }
                is OnDeviceGuestPollSchedule.Step.AwaitNotice -> table.waitForNotice(step.timeoutMillis)
            }
        }
    }

    /**
     * A local game (no table) whose engine is waiting on this player: nothing can change until they answer. A hosted
     * table never qualifies, because other people act at any time.
     */
    private val awaitsLocalAnswer: Boolean
        get() {
            val prompt = poll?.prompt ?: return false
            return table == null && pending == null && abilityAutoAnswer?.isActive != true && !isAutoPassing && !responding &&
                !reconnectsAutomatically && !prompt.submitted && poll?.phase != "starting"
        }

    // MARK: Freeze log (docs/FREEZE_LOG.md)

    /** The game moved: a new stall episode, and a breadcrumb when the turn, step or your prompt differs. */
    private fun noteProgress(next: MatchPoll) {
        stall.changed(uptime()); FreezeLog.gameChanged()
        val shown = snapshot
        val prompt = next.prompt?.takeIf { !it.submitted }?.kind ?: "none"
        val line = "Snapshot: round ${shown?.displayTurn ?: 0} · ${shown?.step ?: shown?.phase ?: next.phase} · prompt $prompt"
        if (line != lastSnapshotCrumb) { lastSnapshotCrumb = line; FreezeLog.crumb(line) }
        FreezeLog.game = freezeContext()
    }

    private fun beginStallWatch() {
        stallJob?.cancel()
        stallJob = scope.launch {
            while (isActive) {
                delay(5_000)
                if (client == null) break
                FreezeLog.game = freezeContext()
                if (!isForeground || isClosing) continue
                val over = poll?.phase in setOf("ended", "failed", "closed") || snapshot?.isCompleted == true
                val waitingOnYou = poll?.prompt?.submitted == false
                val waitingOnPerson = table != null && snapshot?.waitingOnPersonID != null
                stall.check(uptime(), true, over, waitingOnYou, table != null, waitingOnPerson)?.let { kind -> FreezeLog.record(kind) }
            }
        }
    }

    /** The game's lines for a freeze report: no names, deck lists or account details; prompt messages may name cards. */
    fun freezeContext(): List<Pair<String, String>> = buildList {
        val shown = snapshot
        val prompt = poll?.prompt
        val now = uptime()
        add("Table" to (table?.role?.name?.lowercase() ?: "solo"))
        add("Match" to "${poll?.phase ?: "none"} · revision ${poll?.revision ?: 0}")
        if (shown != null) {
            add("Round" to "${shown.displayTurn} (turn ${shown.turn}) · ${shown.phase}${shown.step?.let { " / $it" } ?: ""}")
            add("Whose turn" to when { shown.activePlayerId == null -> "nobody"; shown.isViewer(shown.activePlayerId) -> "you"; else -> "opponent" })
        }
        add("Waiting on you" to if (prompt != null && !prompt.submitted)
            "yes · ${prompt.kind} · ${(prompt.payload["message"].string ?: "").replace('\n', ' ').take(300)}" else "no")
        add("Pending answer" to (pending?.label ?: "none"))
        stall.answerPendingSeconds(now)?.let { add("Answer pending" to "${it.toInt()} s") }
        add("Busy" to "working $isWorking · responding $responding · auto-pass ${if (isAutoPassing) autoPassStatus.ifEmpty { "on" } else "off"}" +
            " · smart pass ${if (smartPass?.enabled == true) "on" else "off"}${if (fullControlTurn != null) " · full control" else ""}")
        add("Status" to status.take(200))
        errorMessage?.let { add("Error" to it.take(300)) }
        add("Quiet" to "${stall.quietSeconds(now).toInt()} s")
    }

    /** An answer or concede is on its way: a waiting guest polls promptly until it lands. */
    private fun noteAction() {
        lastActionAt = nowMillis()
        table?.wake()
    }
}
