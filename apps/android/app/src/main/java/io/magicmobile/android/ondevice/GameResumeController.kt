package io.magicmobile.android.ondevice

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.EngineCheckpoint
import io.magicmobile.android.game.EngineCheckpointResult
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineRestored
import io.magicmobile.android.game.GameResumeIdentity
import io.magicmobile.android.game.GameResumeLaunch
import io.magicmobile.android.game.GameResumePolicy
import io.magicmobile.android.game.GameResumeSettings
import io.magicmobile.android.game.GameResumeSidecar
import io.magicmobile.android.game.GameResumeStore
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.game.J
import io.magicmobile.android.game.MatchPoll
import io.magicmobile.android.game.jsonObject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.concurrent.Executor

/**
 * The app's side of save/resume, with the same rules as iOS: what the next launch offers,
 * what the live game has saved, when the engine is asked to save and when the files are deleted.
 * State is read and written on the main thread; file work runs in order on `io`. With no store
 * (design previews) nothing is checkpointed or offered. `uptime` is a monotonic clock in
 * milliseconds for the background save's deadline.
 */
class GameResumeController(private val store: GameResumeStore?, private val appBuild: String, private val io: Executor,
                           private val uptime: () -> Long = { System.nanoTime() / 1_000_000 }) {
    /** The Resume / Abandon prompt, shown over the main menu. */
    var offer by mutableStateOf<GameResumeLaunch.Offer?>(null); private set
    /** A one-time notice: expired, updated, lost, resumed or could not resume. */
    var notice by mutableStateOf<String?>(null)
    /** The live game resumed from a checkpoint, until it ends or is left (the versus intro is skipped). */
    var resumedGame by mutableStateOf(false); private set

    private var live: GameResumeSidecar? = null
    /** A game this controller saved or marked is on the board; its polls are followed until it is over. */
    private var following = false
    private var lastSequence = Long.MIN_VALUE
    private var launchChecked = false

    /** Whether the live game is being checkpointed. */
    val isCheckpointing: Boolean get() = live != null
    /** The live game's engine saves only when asked (`checkpointOnDemand`). Older engines save at every decision. */
    var savesOnDemand = false; private set

    /** Once per process, after the build identity is known: offer the saved game or explain why it is gone. */
    suspend fun checkAtLaunch(engineIdentity: String) {
        val store = store ?: return
        if (launchChecked) return
        launchChecked = true
        val result = withContext(io.asCoroutineDispatcher()) { runCatching { store.launch(appBuild, engineIdentity) }.getOrNull() }
        when (result) {
            is GameResumeLaunch.Offer -> offer = result
            is GameResumeLaunch.Notice -> notice = result.message
            else -> {}
        }
    }

    /**
     * The create configuration's `checkpoint` value for a new game, or null when this game must not
     * checkpoint: an engine without `saveResume`, more than one human, or no resume folder.
     */
    fun checkpointFor(capabilities: J?, seats: List<J>): JsonObject? {
        val store = store ?: return null
        if (!GameResumePolicy.checkpoints(capabilities, seats)) return null
        return runCatching { store.prepare(); jsonObject("path" to JsonPrimitive(store.checkpointFile.absolutePath)) }.getOrNull()
    }

    /**
     * A solo game has started. With a checkpoint the sidecar is written now; without one (an older
     * engine) only the in-progress marker is kept.
     */
    fun gameStarted(configuration: JsonObject, checkpoint: JsonObject?, capabilities: J?, seatID: String, playerDeckName: String,
                    settings: GameResumeSettings?) {
        resumedGame = false; following = true
        val engine = GameResumeIdentity.engine(capabilities)
        if (checkpoint == null || engine == null) { markInProgress("solo"); return }
        val now = store?.now() ?: return
        lastSequence = Long.MIN_VALUE
        savesOnDemand = GameResumePolicy.onDemand(capabilities)
        save(GameResumeSidecar(appBuild, engine, now, now, null, 0, playerDeckName, GameResumeSidecar.opponents(configuration),
            GameResumeSidecar.setup(configuration, seatID, settings)))
    }

    /** A relay table never checkpoints; the marker explains a game lost to process death. */
    fun tableStarted() { resumedGame = false; following = true; markInProgress("table") }

    /** Every applied poll: record the engine's newest checkpoint, and forget everything once the game is over for this seat. */
    fun observe(poll: MatchPoll) {
        if (!following) return
        if (GameResumePolicy.over(poll)) { discard(); return }
        poll.checkpoint?.let(::checkpointSaved)
    }

    /** A poll or a save request reported the engine's newest checkpoint. */
    fun checkpointSaved(checkpoint: EngineCheckpoint) {
        val current = live ?: return
        if (checkpoint.sequence <= lastSequence) return
        lastSequence = checkpoint.sequence
        save(current.copy(lastCheckpointAt = checkpoint.savedAtMillis, turn = checkpoint.turn))
    }

    /**
     * ON_PAUSE and ON_STOP: the player is leaving, and the 10 minutes start now. `leftAt` is written
     * once per absence, before the engine is asked to save. False when no saved game is being played.
     */
    fun backgrounded(): Boolean {
        val current = live ?: return false
        if (current.leftAt == null) save(current.copy(leftAt = store?.now() ?: return false))
        return true
    }

    /** The engine side of saving on leaving: the live solo game's client and match, from the setup model (fakes in tests). */
    interface SaveEngine {
        suspend fun checkpoint(waitMillis: Int): EngineCheckpointResult
        suspend fun cancel()
    }

    /** ON_PAUSE, after [backgrounded]: ask the engine to save at its next safe point, without waiting. */
    suspend fun armSave(engine: SaveEngine) {
        if (!awayOnDemand) return
        val result = try { engine.checkpoint(0) } catch (error: CancellationException) { throw error } catch (_: Throwable) { return }
        saveFinished(result)
    }

    /**
     * ON_STOP, after [backgrounded]: requests of up to one second each until the engine saves,
     * cannot save, or [budgetMillis] runs out. Cancelling the caller (the player came back) stops it.
     */
    suspend fun saveForBackground(engine: SaveEngine, budgetMillis: Long = BACKGROUND_SAVE_MILLIS) {
        if (!awayOnDemand) return
        val deadline = uptime() + budgetMillis
        while (awayOnDemand) {
            val wait = (deadline - uptime()).coerceIn(0, EngineCheckpointResult.MAX_WAIT_MILLIS.toLong()).toInt()
            val result = try { engine.checkpoint(wait) } catch (error: CancellationException) { throw error } catch (_: Throwable) { return }
            if (result != EngineCheckpointResult.WaitingForEngine || uptime() >= deadline) { saveFinished(result); return }
        }
    }

    /**
     * ON_START and ON_RESUME: back in the app. The live game continues however long the player was
     * away, and the save made on leaving is used up, so if the app now dies the next launch says the
     * game ended. True when the engine's armed save request must be cancelled.
     */
    fun foregrounded(): Boolean {
        val current = live ?: return false
        if (current.leftAt == null) return false
        save(current.copy(leftAt = null))
        if (!savesOnDemand) return false
        store?.let { store -> io.execute { runCatching { store.consumeCheckpoint() } } }
        return true
    }

    private val awayOnDemand: Boolean get() = savesOnDemand && live?.leftAt != null

    /** What the engine said about a save made while the player is away. */
    private fun saveFinished(result: EngineCheckpointResult) {
        if (live?.leftAt == null) return
        when (result) {
            is EngineCheckpointResult.Saved -> {
                store?.let { store -> io.execute { runCatching { store.restoreConsumedCheckpointIfLatest() } } }
                checkpointSaved(result.checkpoint)
            }
            EngineCheckpointResult.Over -> discard()
            else -> {}
        }
    }

    /** The game ended, the player conceded or left, or another game starts: delete both files and the marker. */
    fun discard() {
        live = null; resumedGame = false; following = false; lastSequence = Long.MIN_VALUE; savesOnDemand = false
        val store = store ?: return
        io.execute { runCatching { store.deleteAll() } }
    }

    /** Abandon: the saved game is deleted. */
    fun abandon() { offer = null; discard() }

    /** Resume: take the saved game out of the prompt. The deadline was checked when the prompt was shown. */
    fun accept(): GameResumeSidecar? = offer?.sidecar.also { offer = null }

    /**
     * Restores `sidecar` through `engine` and attaches the board. On any failure the engine is
     * cleaned up, both files are deleted and the player is told; the menu stays.
     */
    suspend fun resume(sidecar: GameResumeSidecar, engine: ResumeEngine): Boolean {
        try {
            val store = store ?: throw EngineError.InvalidMessage("Resume is unavailable")
            val seatID = sidecar.seatID ?: throw EngineError.InvalidMessage("The saved game has no seat")
            val client = engine.open()
            if (!GameResumePolicy.supported(engine.capabilities)) {
                throw EngineError.Rejected("checkpoint_unavailable", "This engine cannot restore saved games.")
            }
            val restored = EngineRestored.parse(engine.restore(client, store.checkpointFile.absolutePath))
            lastSequence = Long.MIN_VALUE
            savesOnDemand = GameResumePolicy.onDemand(engine.capabilities)
            save(sidecar.copy(leftAt = null, turn = restored.turn, lastCheckpointAt = restored.savedAtMillis))
            // Playing again uses up the save, as coming back to the app does.
            if (savesOnDemand) io.execute { runCatching { store.consumeCheckpoint() } }
            // Set before the board appears, so it opens without the new-game versus intro.
            resumedGame = true; following = true
            engine.attach(client, restored.matchID, seatID)
            notice = GameResumeText.RESUMED
            return true
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            runCatching { engine.cleanup() }
            discard()
            notice = GameResumeText.RESUME_FAILED
            return false
        }
    }

    /** The engine side of a resume, supplied by the setup model (and by fakes in tests). */
    interface ResumeEngine {
        suspend fun open(): EngineClient
        val capabilities: J?
        suspend fun restore(client: EngineClient, path: String): J
        suspend fun attach(client: EngineClient, matchID: String, seatID: String)
        suspend fun cleanup()
    }

    private fun save(sidecar: GameResumeSidecar) {
        live = sidecar
        val store = store ?: return
        io.execute { runCatching { store.write(sidecar) } }
    }

    private fun markInProgress(kind: String) {
        live = null; savesOnDemand = false
        val store = store ?: return
        io.execute { runCatching { store.deleteCheckpoint(); store.markInProgress(kind) } }
    }

    companion object {
        /** The longest the ON_STOP save keeps asking the engine. */
        const val BACKGROUND_SAVE_MILLIS = 5_000L
    }
}
