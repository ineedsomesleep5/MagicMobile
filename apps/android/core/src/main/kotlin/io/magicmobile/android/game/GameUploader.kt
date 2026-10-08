package io.magicmobile.android.game

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** What sending a finished game to the profile server came to (iOS GameUploadResult). */
enum class GameUploadResult {
    /** Stored, or already there. */
    SENT,
    /** Offline, rate limited or not signed in: try again later. */
    RETRY_LATER,
    /** The server refused this game for good; sending it again would fail the same way. */
    REJECTED,
    /** The server doesn't record games yet, or there is no profile name: nothing to retry now. */
    UNAVAILABLE,
}

/**
 * Sends this phone's finished games to the profile server (mm_record_game), so other players can see them on the profile
 * (GameUploader.swift). The phone's own record is the source of truth: a game counts as sent once the server confirmed it, and any
 * recent game that is not yet confirmed is tried again whenever the app is open and online. That covers going offline mid-session, a
 * server that does not record games yet (the migration comes separately) and the games played before there was a profile name.
 * Sending never blocks play and never throws.
 */
class GameUploader(private val file: File?) {
    private val sent: MutableList<String> = file?.let { runCatching { Json.decodeFromString(ListSerializer(String.serializer()), it.readText()) }.getOrNull() }
        ?.toMutableList() ?: mutableListOf()
    private val running = AtomicBoolean(false)

    /** The recent games the server hasn't confirmed, oldest first. `matches` is newest first, like the record. */
    @Synchronized fun pending(matches: List<MatchRecord>): List<MatchRecord> {
        val confirmed = sent.toSet()
        return matches.take(WINDOW).filter { it.id !in confirmed }.asReversed()
    }

    /** Sends what is pending, oldest first, and stops at the first game that could not be sent for now. Returns how many the
     *  server confirmed. A pass already running makes this one a no-op. */
    suspend fun flush(matches: List<MatchRecord>, send: suspend (MatchRecord) -> GameUploadResult): Int {
        if (!running.compareAndSet(false, true)) return 0
        try {
            var confirmed = 0
            for (match in pending(matches).take(PER_PASS)) {
                when (send(match)) {
                    GameUploadResult.SENT -> { remember(match); confirmed++ }
                    GameUploadResult.REJECTED -> remember(match)
                    GameUploadResult.RETRY_LATER, GameUploadResult.UNAVAILABLE -> { save(); return confirmed }
                }
            }
            save()
            return confirmed
        } finally { running.set(false) }
    }

    @Synchronized private fun remember(match: MatchRecord) { sent.add(match.id) }

    @Synchronized private fun save() {
        if (sent.size > KEEP) repeat(sent.size - KEEP) { sent.removeAt(0) }
        val target = file ?: return
        // A failed save only means a few games are sent again; the server stores each once.
        runCatching {
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, target.name + ".tmp")
            temp.writeText(Json.encodeToString(ListSerializer(String.serializer()), sent))
            temp.renameTo(target)
        }
    }

    companion object {
        /** The newest games considered each time: older ones stay on the phone. */
        const val WINDOW = 60
        /** At most this many go in one pass (the server allows 100 an hour). */
        const val PER_PASS = 40
        private const val KEEP = 400
    }
}
