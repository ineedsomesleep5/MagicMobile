package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Save/resume for solo games against the AI, the same rules and words as the iOS app.
 * The engine writes `game.checkpoint` at each of the human's priority decisions; the app owns
 * that file and its `resume.json` sidecar, and offers Resume or Abandon at the next launch for
 * 10 minutes after the player left. Relay tables and engines without `saveResume` never
 * checkpoint; they leave a small in-progress marker so a lost game is explained, not hidden.
 */
object GameResumeText {
    const val PROMPT_TITLE = "Resume your game?"
    const val RESUME = "Resume"
    const val ABANDON = "Abandon"
    const val RESUMED = "Resumed at your last decision."
    const val RESUME_FAILED = "Couldn't resume that game."
    const val EXPIRED = "Your unfinished game expired after 10 minutes."
    const val UPDATED = "Your unfinished game can't be resumed after an update."
    const val LOST = "Your last game ended when the app closed."
    /** The notice's close button, for TalkBack. */
    const val DISMISS = "Dismiss notification"
    /** A notice dismisses itself after this long. */
    const val NOTICE_MILLIS = 6_000L

    /** "Turn 12 against Alice and Bob · saved 3 min ago"; "Against …" before the first turn is known. */
    fun detail(turn: Long, opponents: List<String>, savedAgoMillis: Long): String {
        val names = names(opponents)
        val game = when {
            turn >= 1 -> if (names.isEmpty()) "Turn $turn" else "Turn $turn against $names"
            else -> if (names.isEmpty()) "Your game" else "Against $names"
        }
        return "$game · ${savedAgo(savedAgoMillis)}"
    }

    /** "Alice", "Alice and Bob", "Alice, Bob and Carol". */
    fun names(values: List<String>): String = when (values.size) {
        0 -> ""
        1 -> values[0]
        else -> values.dropLast(1).joinToString(", ") + " and " + values.last()
    }

    /** Whole minutes, rounded down: "saved just now" under a minute, then minutes, then hours. */
    fun savedAgo(millis: Long): String {
        val minutes = millis / 60_000
        return when {
            minutes < 1 -> "saved just now"
            minutes < 60 -> "saved $minutes min ago"
            else -> "saved ${minutes / 60} hr ago"
        }
    }
}

object GameResumePolicy {
    /** A saved game can be resumed for 10 minutes after the player left it. */
    const val WINDOW_MILLIS = 600_000L

    /** Only engine builds with checkpoint support say `saveResume: true`; the new request fields go to no other engine. */
    fun supported(capabilities: J?): Boolean = capabilities["saveResume"].bool == true

    /** A game checkpoints only on such an engine and with exactly one human seat. */
    fun checkpoints(capabilities: J?, seats: List<J>): Boolean =
        supported(capabilities) && seats.count { (it["controller"].string ?: "human") == "human" } == 1

    /**
     * The game is over for this seat: it ended, or the player left it (conceded or lost in a pod,
     * and now spectates). What was saved before must not come back.
     */
    fun over(poll: MatchPoll): Boolean {
        if (poll.phase == "ended" || poll.snapshot["outcome"]["ended"].bool == true) return true
        val viewer = poll.snapshot["enginePlayerId"].string ?: return false
        return poll.snapshot["gameView"]["players"].array?.any { it["playerId"].string == viewer && it["hasLeft"].bool == true } == true
    }

    /** Inclusive: exactly 600 s is still resumable. `leftAt` is null when the process died in the foreground. */
    fun expired(now: Long, leftAt: Long?, lastCheckpointAt: Long): Boolean = now - (leftAt ?: lastCheckpointAt) > WINDOW_MILLIS
}

/**
 * The engine a checkpoint belongs to. Built from capabilities when a game starts and from the
 * app's own build identity at launch (the two are validated equal before any game opens), so the
 * launch check needs no engine.
 */
object GameResumeIdentity {
    fun engine(protocol: Long, upstream: String, catalogueHash: String): String = "xmage/protocol-$protocol/$upstream/$catalogueHash"
    fun engine(identity: BuildIdentity): String = engine(identity.protocolVersion.toLong(), identity.upstreamCommit, identity.catalogueHash)
    fun engine(capabilities: J?): String? {
        val protocol = capabilities["protocol"].integer ?: return null
        val upstream = capabilities["upstream"].string ?: return null
        val catalogue = capabilities["catalogueHash"].string ?: return null
        return engine(protocol, upstream, catalogue)
    }
}

/** A poll's optional `checkpoint`: the engine's latest write. Malformed metadata is ignored, never fatal to the game. */
data class EngineCheckpoint(val sequence: Long, val savedAtMillis: Long, val turn: Long, val bytes: Long) {
    companion object {
        fun parse(value: J?): EngineCheckpoint? {
            if (value !is JsonObject) return null
            val sequence = value["sequence"].integer ?: return null
            val saved = value["savedAtMillis"].integer ?: return null
            val turn = value["turn"].integer ?: return null
            val bytes = value["bytes"].integer ?: return null
            if (sequence < 0 || saved < 0 || turn < 0 || bytes < 0) return null
            return EngineCheckpoint(sequence, saved, turn, bytes)
        }
    }
}

/** A `restore` result: the create result shape plus `restored`. */
data class EngineRestored(val matchID: String, val turn: Long, val savedAtMillis: Long) {
    companion object {
        fun parse(result: J): EngineRestored {
            val match = result["matchId"].string?.takeIf { it.isNotEmpty() }
            val restored = result["restored"]
            val turn = restored["turn"].integer
            val saved = restored["savedAtMillis"].integer
            if (match == null || turn == null || saved == null || turn < 0 || saved < 0) {
                throw EngineError.InvalidMessage("XMage did not return a restored match.")
            }
            return EngineRestored(match, turn, saved)
        }
    }
}

/** The local choices behind a game, so the menu can rebuild it (and its Rematch) after a restore. */
data class GameResumeSettings(val deckID: String, val aiDeckIDs: List<String>, val aiSkill: Int, val startingPlayerMode: String) {
    fun json(): JsonObject = jsonObject("deckId" to JsonPrimitive(deckID), "aiDeckIds" to JsonArray(aiDeckIDs.map(::JsonPrimitive)),
        "aiSkill" to JsonPrimitive(aiSkill), "startingPlayerMode" to JsonPrimitive(startingPlayerMode))

    companion object {
        fun decode(value: J?): GameResumeSettings? {
            val deck = value["deckId"].string ?: return null
            val ai = value["aiDeckIds"].array?.map { it.string ?: return null } ?: return null
            val skill = value["aiSkill"].integer?.toInt() ?: return null
            val mode = value["startingPlayerMode"].string ?: return null
            return GameResumeSettings(deck, ai, skill, mode)
        }
    }
}

/**
 * resume.json, format 1. `setup` holds the create configuration (without the checkpoint path),
 * the human seat and the local settings; nothing beyond what that configuration already holds.
 * Times are milliseconds since 1970. A sidecar of another format is read only so that the launch
 * can report it as expired or updated; it is never resumed.
 */
data class GameResumeSidecar(
    val appBuild: String,
    val engineIdentity: String,
    val createdAt: Long,
    val lastCheckpointAt: Long,
    val leftAt: Long?,
    val turn: Long,
    val playerDeckName: String,
    val opponents: List<String>,
    val setup: JsonObject,
    val format: Long = FORMAT,
) {
    val seatID: String? get() = setup["seatId"].string
    val settings: GameResumeSettings? get() = GameResumeSettings.decode(setup["settings"])

    fun json(): JsonObject = jsonObject("format" to JsonPrimitive(format), "appBuild" to JsonPrimitive(appBuild),
        "engineIdentity" to JsonPrimitive(engineIdentity), "createdAt" to JsonPrimitive(createdAt),
        "lastCheckpointAt" to JsonPrimitive(lastCheckpointAt), "leftAt" to (leftAt?.let(::JsonPrimitive) ?: JsonNull),
        "turn" to JsonPrimitive(turn), "playerDeckName" to JsonPrimitive(playerDeckName),
        "opponents" to JsonArray(opponents.map(::JsonPrimitive)), "setup" to setup)

    companion object {
        const val FORMAT = 1L

        fun setup(configuration: JsonObject, seatID: String, settings: GameResumeSettings?): JsonObject =
            jsonObject(linkedMapOf<String, J>("configuration" to JsonObject(configuration - "checkpoint"), "seatId" to JsonPrimitive(seatID))
                .apply { settings?.let { put("settings", it.json()) } })

        /** The AI seats' names from a create configuration, in seat order: the names the board shows. */
        fun opponents(configuration: J): List<String> =
            (configuration["seats"].array ?: emptyList()).filter { it["controller"].string == "ai" }.mapNotNull { it["name"].string }

        fun decode(value: J): GameResumeSidecar? {
            val format = value["format"].integer ?: return null
            val setup = value["setup"] as? JsonObject ?: return null
            val left = value["leftAt"]
            return GameResumeSidecar(
                appBuild = value["appBuild"].string ?: return null,
                engineIdentity = value["engineIdentity"].string ?: return null,
                createdAt = value["createdAt"].integer ?: return null,
                lastCheckpointAt = value["lastCheckpointAt"].integer ?: return null,
                leftAt = if (left.isNull) null else left.integer ?: return null,
                turn = value["turn"].integer ?: return null,
                playerDeckName = value["playerDeckName"].string ?: return null,
                opponents = value["opponents"].array?.map { it.string ?: return null } ?: return null,
                setup = setup,
                format = format,
            ).takeIf { it.seatID != null }
        }
    }
}

sealed interface GameResumeLaunch {
    object Nothing : GameResumeLaunch
    /** The prompt. Its deadline was checked now; Resume stays honored however long the player takes to tap it. */
    data class Offer(val sidecar: GameResumeSidecar, val detail: String) : GameResumeLaunch
    data class Notice(val message: String) : GameResumeLaunch
}

/**
 * The resume directory: `game.checkpoint` (engine-written), `resume.json` and the in-progress
 * marker. Production passes Android's noBackupFilesDir/resume; tests pass a temporary directory
 * and a fixed clock, so they never touch the real files.
 */
class GameResumeStore(val directory: File, private val clock: () -> Long = System::currentTimeMillis) {
    val checkpointFile: File get() = File(directory, CHECKPOINT)
    val sidecarFile: File get() = File(directory, SIDECAR)
    val markerFile: File get() = File(directory, MARKER)

    fun now(): Long = clock()

    fun prepare(): File {
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) throw java.io.IOException("Could not create the resume folder")
        return directory
    }

    /** Written through a temporary file, synced, then renamed over the old one: a reader sees the old or the new sidecar, never half of one. */
    fun write(sidecar: GameResumeSidecar) = atomicWrite(sidecarFile, EngineJson.encode(sidecar.json()))

    fun read(): GameResumeSidecar? = runCatching {
        if (!sidecarFile.isFile) return null
        GameResumeSidecar.decode(EngineJson.decode(sidecarFile.readBytes()))
    }.getOrNull()

    /** Deletes the checkpoint, the sidecar and any temporary file either writer left behind. */
    fun deleteCheckpoint() {
        for (name in listOf(CHECKPOINT, "$CHECKPOINT.tmp", SIDECAR, "$SIDECAR.tmp")) File(directory, name).delete()
    }

    fun markInProgress(kind: String) {
        atomicWrite(markerFile, EngineJson.encode(jsonObject("format" to JsonPrimitive(1), "kind" to JsonPrimitive(kind),
            "startedAt" to JsonPrimitive(clock()))))
    }

    fun clearMarker() { markerFile.delete(); File(directory, "$MARKER.tmp").delete() }

    fun deleteAll() { deleteCheckpoint(); clearMarker() }

    /**
     * The launch decision. Resumable iff both files exist, the player left at most 10 minutes
     * ago and the saved app build, engine and sidecar format match this app. Anything else is
     * deleted, with at most one notice: a game that died before it could be saved (or whose sidecar
     * cannot be read), then expired whatever the build, then an update.
     */
    fun launch(appBuild: String, engineIdentity: String): GameResumeLaunch {
        val marker = markerFile.exists()
        val hasSidecar = sidecarFile.exists()
        val hasCheckpoint = checkpointFile.isFile
        if (!hasSidecar) {
            // A checkpoint without its sidecar is a leftover from a game the player already left.
            deleteAll()
            return if (marker) GameResumeLaunch.Notice(GameResumeText.LOST) else GameResumeLaunch.Nothing
        }
        val sidecar = read()
        val now = clock()
        val outcome = when {
            sidecar == null || !hasCheckpoint -> GameResumeLaunch.Notice(GameResumeText.LOST)
            GameResumePolicy.expired(now, sidecar.leftAt, sidecar.lastCheckpointAt) -> GameResumeLaunch.Notice(GameResumeText.EXPIRED)
            sidecar.format != GameResumeSidecar.FORMAT || sidecar.appBuild != appBuild || sidecar.engineIdentity != engineIdentity ->
                GameResumeLaunch.Notice(GameResumeText.UPDATED)
            else -> GameResumeLaunch.Offer(sidecar, GameResumeText.detail(sidecar.turn, sidecar.opponents, now - sidecar.lastCheckpointAt))
        }
        if (outcome is GameResumeLaunch.Offer) clearMarker() else deleteAll()
        return outcome
    }

    private fun atomicWrite(target: File, bytes: ByteArray) {
        prepare()
        val temporary = File(directory, target.name + ".tmp")
        try {
            FileOutputStream(temporary).use { output -> output.write(bytes); output.flush(); output.fd.sync() }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (error: Throwable) {
            temporary.delete(); throw error
        }
    }

    companion object {
        const val CHECKPOINT = "game.checkpoint"
        const val SIDECAR = "resume.json"
        const val MARKER = "game-in-progress.json"
    }
}
