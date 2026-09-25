package io.magicmobile.android.session

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EnginePrompt
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.J
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.MatchPoll
import io.magicmobile.android.game.OnDeviceMessageLog
import io.magicmobile.android.game.OnDevicePromptAdapter
import io.magicmobile.android.game.OnDeviceSnapshotAdapter
import io.magicmobile.android.game.OnDeviceYieldPolicy
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.UUID

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
    var errorMessage by mutableStateOf<String?>(null); private set
    var isAutoPassing by mutableStateOf(false); private set
    var autoPassStatus by mutableStateOf(""); private set
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
    private var epoch = UUID.randomUUID()
    private var visibilityEpoch = UUID.randomUUID()
    private var refreshSequence = 0L
    private var appliedRefreshSequence = 0L
    private var isForeground = true
    private var automaticPolling = true
    private var reconnectsAutomatically = false

    private class Submission(val prompt: EnginePrompt, val answer: J, val requestID: UUID, val label: String)
    private var pending: Submission? = null

    /** The exact ability picked when activating a source with several; XMage's follow-up is answered with it. */
    private data class ChosenAbility(val sourceID: String, val abilityID: String, val activationPromptID: String)
    private var chosenAbility: ChosenAbility? = null
    /** A follow-up ability prompt answered automatically: its snapshot stays unpublished. */
    private var heldAbilitySnapshot: Pair<String, GameSnapshot>? = null
    private var abilityAutoAnswer: Job? = null

    private fun uptime(): Double = System.nanoTime() / 1_000_000_000.0

    suspend fun attach(client: EngineClient, matchID: String, seatID: String, autoPoll: Boolean = true,
                       allowsSeatScopedAutoYield: Boolean = false, reconnectsAutomatically: Boolean = false,
                       close: suspend () -> Unit) {
        if (this.client != null || isWorking) throw EngineError.InvalidMessage("Close the active game first")
        this.client = client; this.matchID = matchID; this.seatID = seatID
        this.allowsSeatScopedAutoYield = allowsSeatScopedAutoYield
        this.reconnectsAutomatically = reconnectsAutomatically
        autoPassStatus = ""
        closeEndpoint = close; automaticPolling = autoPoll; epoch = UUID.randomUUID()
        refreshSequence = 0; appliedRefreshSequence = 0; isClosing = false
        messageLog = OnDeviceMessageLog()
        status = "Starting game"
        try { refresh() } catch (error: Exception) {
            if (!reconnectsAutomatically || error !is IOException) throw error
            status = "Reconnecting…"
            errorMessage = "Connection interrupted. Reconnecting to your game."
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
            // While the AI thinks, polls repeat the same board; do not re-adapt it every 300 ms.
            val unchanged = poll?.raw == next.raw && heldAbilitySnapshot == null && snapshot != null
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
            messageLog = publishedLog
            poll = next
            appliedRefreshSequence = maxOf(appliedRefreshSequence, sequence)
            pending?.let { current ->
                if (next.prompt?.id != current.prompt.id || next.prompt?.revision != current.prompt.revision) {
                    pending = null
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
            beginPolling()
        } finally {
            activeRefreshes -= 1
        }
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
            try {
                while (isActive) {
                    delay(300)
                    if (epoch != token || yieldGeneration != generation || !isAutoPassing) return@launch
                    if (isWorking || activeRefreshes != 0) continue
                    // A new authenticated poll, never the rendered snapshot, authorizes each pass.
                    refresh()
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
                            submit(command, "Pass priority", "auto-pass-${prompt.id}")
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
        return OnDeviceYieldPolicy.Context(poll.matchID, poll.seatID, viewer, active, turn, poll.phase, allowsSeatScopedAutoYield,
            isForeground && !isClosing, stack.isEmpty(), selfAuthority, poll.resyncRequired, prompt)
    }

    suspend fun send(action: LegalAction) {
        stopAutoPass()
        val snapshot = snapshot
        val current = snapshot?.legalActions?.firstOrNull { it.id == action.id }
            ?: throw EngineError.InvalidMessage("This action is no longer available")
        val command = GameCommand(type = current.type, gameId = snapshot.id, playerId = current.playerId,
            cardInstanceId = current.cardInstanceId, sourceInstanceId = current.sourceInstanceId, abilityId = current.abilityId,
            promptId = current.promptId, messageId = current.messageId, choiceIds = current.choiceIds, targetIds = current.targetIds,
            cardInstanceIds = current.cardInstanceIds, modeIds = current.modeIds, pile = current.pile?.value, amount = current.amount,
            amounts = current.amounts, orderedIds = current.orderedIds, useCommandZone = current.useCommandZone, manaType = current.manaType,
            manaTypes = current.manaTypes, playerIds = current.playerIds, confirmed = current.confirmed, pay = current.pay,
            sourceZone = current.sourceZone, fromZone = current.sourceZone, cardName = current.cardName, attackers = current.attackers,
            blockers = current.blockers, expectedBridgeRevision = snapshot.bridgeRevision)
        send(command, current.label, current.id)
    }

    suspend fun send(command: GameCommand, label: String, actionID: String) {
        stopAutoPass()
        submit(command, label, actionID)
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
            val answer = OnDevicePromptAdapter.answer(command, prompt, snapshot.viewerID)
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
                    this.pending = null; pendingActionID = null; pendingCardID = null
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
        chosenAbility = null; heldAbilitySnapshot = null
        client.concede(matchID, seatID)
        // The engine retracted this seat's open question; nothing sent earlier can still apply.
        pending = null; pendingActionID = null; pendingCardID = null
        errorMessage = null; status = "Conceded"
        try { refresh() } catch (_: Exception) {}
        beginPolling()
    }

    suspend fun close() {
        stopAutoPass()
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
            messageLog = OnDeviceMessageLog()
            this.closeEndpoint = null; pending = null; pendingActionID = null; pendingCardID = null; errorMessage = null; status = "Ready"
        } finally {
            isWorking = false
        }
    }

    fun setForeground(value: Boolean) {
        if (isForeground != value) visibilityEpoch = UUID.randomUUID()
        if (!value) stopAutoPass()
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
            while (isActive) {
                try {
                    val idle = idlePolls >= 3
                    delay(if (reconnectsAutomatically) 1000 else if (idle) 600 else 300)
                    if (isAutoPassing) continue
                    refresh()
                    failures = 0
                    if (poll?.phase in setOf("ended", "failed", "closed")) { pollingJob = null; return@launch }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (reconnectsAutomatically && error is IOException) {
                        failures += 1
                        status = "Reconnecting…"
                        errorMessage = "Connection interrupted. Reconnecting to your game."
                        delay(minOf(10, failures * 2) * 1000L)
                        continue
                    }
                    pollingJob = null
                    errorMessage = error.message; status = "Updates interrupted. Refresh to retry."
                    return@launch
                }
            }
        }
    }
}
