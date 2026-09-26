package io.magicmobile.android.ondevice

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
 * what the live game has saved and when both files are deleted. State is read and written on the
 * main thread; file work runs in order on `io`. With no store (design previews) nothing is
 * checkpointed or offered.
 */
class GameResumeController(private val store: GameResumeStore?, private val appBuild: String, private val io: Executor) {
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
        save(GameResumeSidecar(appBuild, engine, now, now, null, 0, playerDeckName, GameResumeSidecar.opponents(configuration),
            GameResumeSidecar.setup(configuration, seatID, settings)))
    }

    /** A relay table never checkpoints; the marker explains a game lost to process death. */
    fun tableStarted() { resumedGame = false; following = true; markInProgress("table") }

    /** Every applied poll: record the engine's newest checkpoint, and forget everything once the game is over for this seat. */
    fun observe(poll: MatchPoll) {
        if (!following) return
        if (GameResumePolicy.over(poll)) { discard(); return }
        val checkpoint = poll.checkpoint ?: return
        val current = live ?: return
        if (checkpoint.sequence <= lastSequence) return
        lastSequence = checkpoint.sequence
        save(current.copy(lastCheckpointAt = checkpoint.savedAtMillis, turn = checkpoint.turn))
    }

    /** ON_STOP: the 10 minutes start now. A surviving process keeps its live game however long it is away. */
    fun backgrounded() {
        val current = live ?: return
        save(current.copy(leftAt = store?.now() ?: return))
    }

    fun foregrounded() {
        val current = live ?: return
        if (current.leftAt != null) save(current.copy(leftAt = null))
    }

    /** The game ended, the player conceded or left, or another game starts: delete both files and the marker. */
    fun discard() {
        live = null; resumedGame = false; following = false; lastSequence = Long.MIN_VALUE
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
            save(sidecar.copy(leftAt = null, turn = restored.turn, lastCheckpointAt = restored.savedAtMillis))
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
        live = null
        val store = store ?: return
        io.execute { runCatching { store.deleteCheckpoint(); store.markInProgress(kind) } }
    }
}
