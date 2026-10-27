package io.magicmobile.android.game

/**
 * Voice chat at online tables (iOS VoiceChatRules, web voiceChat.ts, parity/voice-cases.json; docs/VOICE_CHAT.md). Each
 * game has its own Agora channel, "mm-" + the game's epoch: a UUID only that table's players receive, so knowing the
 * channel is being at the table. Each player joins as their seat id. Nobody is in voice until they tap the mic.
 */
object VoiceChatRules {
    /** The server switch (mm_app_config). Off unless the server turns it on, unlike the older switches. */
    const val SWITCH = "voiceChat"
    /** A level (0–1) at or past this is speech. */
    const val SPEAKING_LEVEL = 0.08
    /** A speaker stays lit this long after the last loud report, so a sentence doesn't flicker. */
    const val HOLD_SECONDS = 0.6

    private val EPOCH = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    private val SEAT = Regex("^player[1-9]$")

    /** The game's channel, lower case (iPhones write UUIDs upper case). */
    fun channel(epoch: String?): String? = epoch?.lowercase()?.takeIf { EPOCH.matches(it) }?.let { "mm-$it" }

    /** The Agora account for a seat: the seat id itself. */
    fun account(seat: String?): String? = seat?.takeIf { SEAT.matches(it) }

    fun isSpeaking(level: Double): Boolean = level >= SPEAKING_LEVEL

    fun stillSpeaking(heardAt: Double?, now: Double): Boolean = heardAt != null && now - heardAt <= HOLD_SECONDS + 1e-9

    /** Whether the board shows the mic: the switch on, a table with people, the game started, the server able to answer. */
    fun shown(switchOn: Boolean, solo: Boolean, channel: Boolean, account: Boolean, unavailable: Boolean): Boolean =
        switchOn && !solo && channel && account && !unavailable
}

/** What the board shows of a game's voice channel (VoiceRoom keeps it). */
data class VoiceChatState(
    val stage: Stage = Stage.OFF,
    /** Your microphone is off (you still hear the table). */
    val muted: Boolean = false,
    /** The microphone permission was refused: you hear the table but can't talk. */
    val micBlocked: Boolean = false,
    /** Seats in the channel, yours included while live. */
    val inVoice: Set<String> = emptySet(),
    /** Seats talking right now (lit HOLD_SECONDS past the last loud report). */
    val speaking: Set<String> = emptySet(),
    /** Seats that turned their own microphone off. */
    val selfMuted: Set<String> = emptySet(),
    /** Seats you silenced for yourself. */
    val silenced: Set<String> = emptySet(),
) {
    enum class Stage { OFF, JOINING, LIVE, UNAVAILABLE }
}
