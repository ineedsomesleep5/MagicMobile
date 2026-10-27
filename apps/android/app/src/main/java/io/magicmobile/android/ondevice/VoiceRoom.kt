package io.magicmobile.android.ondevice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import io.agora.rtc2.UserInfo
import io.magicmobile.android.game.VoiceChatRules
import io.magicmobile.android.game.VoiceChatState
import io.magicmobile.android.social.SupabaseLite
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * One game's voice channel (iOS VoiceRoom, web voiceRoom.ts; docs/VOICE_CHAT.md). The root makes one per online game once
 * the game has its channel and the server's voiceChat switch is on; the Agora engine starts only when the player taps the
 * mic. Tokens come from the agora-token function; one 30 s before expiry is renewed in place. Agora calls back on its own
 * thread, so every callback hops to the main thread before touching [state].
 */
class VoiceRoom(
    private val context: Context,
    val channel: String,
    val account: String,
    private val scope: CoroutineScope,
    private val token: suspend (channel: String, seat: String) -> Pair<String, String>,
) {
    var state by mutableStateOf(VoiceChatState()); private set
    /** The table's seat names: the board finds a player's seat by the name shown, as quick chat does. */
    var seatNames: () -> Map<String, String> = { emptyMap() }
    private var engine: RtcEngine? = null
    /** Agora's numeric ids for the seats it has told us about. */
    private val seats = HashMap<Int, String>()
    private val heard = HashMap<String, Double>()
    private var fade: Job? = null
    private var closed = false
    private val main = Handler(Looper.getMainLooper())

    fun seatNamed(name: String?): String? = name?.let { n -> seatNames().entries.firstOrNull { it.value == n }?.key }

    /** Joins; [micAllowed] is the microphone permission's answer (refused still joins to listen). */
    fun join(micAllowed: Boolean) {
        if (state.stage != VoiceChatState.Stage.OFF || closed) return
        state = state.copy(stage = VoiceChatState.Stage.JOINING)
        scope.launch {
            try {
                val (appId, ticket) = token(channel, account)
                if (closed) return@launch
                val config = RtcEngineConfig().apply {
                    mContext = context.applicationContext
                    mAppId = appId
                    mEventHandler = events
                    mChannelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION
                    mAudioScenario = Constants.AudioScenario.getValue(Constants.AudioScenario.CHATROOM)
                }
                val engine = RtcEngine.create(config)
                this@VoiceRoom.engine = engine
                engine.disableVideo()
                engine.enableAudio()
                engine.setAudioProfile(Constants.AUDIO_PROFILE_SPEECH_STANDARD)
                engine.setDefaultAudioRoutetoSpeakerphone(true)
                engine.enableAudioVolumeIndication(200, 3, false)
                val options = ChannelMediaOptions().apply {
                    clientRoleType = Constants.CLIENT_ROLE_BROADCASTER
                    publishMicrophoneTrack = micAllowed
                    autoSubscribeAudio = true
                }
                val code = engine.joinChannelWithUserAccount(ticket, channel, account, options)
                if (code != 0) throw SupabaseLite.Failure("voice_join_$code")
                state = state.copy(stage = VoiceChatState.Stage.LIVE, muted = !micAllowed, micBlocked = !micAllowed, inVoice = state.inVoice + account)
                startFading()
            } catch (error: Exception) {
                teardown()
                val unavailable = (error as? SupabaseLite.Failure)?.code == "voice_not_configured"
                state = VoiceChatState(stage = if (unavailable) VoiceChatState.Stage.UNAVAILABLE else VoiceChatState.Stage.OFF, silenced = state.silenced)
            }
        }
    }

    /** Your microphone off or on (the mic button opens the app's settings instead while it is refused). */
    fun toggleMute() {
        val engine = engine ?: return
        if (state.stage != VoiceChatState.Stage.LIVE || state.micBlocked) return
        val muted = !state.muted
        engine.muteLocalAudioStream(muted)
        heard.remove(account)
        state = state.copy(muted = muted)
        refreshSpeaking()
    }

    /** Silences a seat for you alone (they aren't told). */
    fun silence(seat: String, silenced: Boolean) {
        seats.entries.firstOrNull { it.value == seat }?.key?.let { engine?.muteRemoteAudioStream(it, silenced) }
        if (silenced) heard.remove(seat)
        state = state.copy(silenced = if (silenced) state.silenced + seat else state.silenced - seat)
        refreshSpeaking()
    }

    /** Leaves the channel; join() works again afterwards. */
    fun leave() {
        teardown()
        state = VoiceChatState(silenced = state.silenced)
    }

    /** The game is over: leaves for good. */
    fun close() {
        closed = true
        teardown()
    }

    private fun teardown() {
        fade?.cancel()
        fade = null
        if (engine != null) {
            engine?.leaveChannel()
            RtcEngine.destroy()
        }
        engine = null
        seats.clear()
        heard.clear()
    }

    private fun now() = SystemClock.elapsedRealtime() / 1000.0

    private fun startFading() {
        fade?.cancel()
        fade = scope.launch { while (isActive) { delay(200); refreshSpeaking() } }
    }

    private fun refreshSpeaking() {
        val now = now()
        val speaking = heard.filter { VoiceChatRules.stillSpeaking(it.value, now) && it.key !in state.silenced }.keys
        if (speaking != state.speaking) state = state.copy(speaking = speaking.toSet())
    }

    private fun seatFor(uid: Int): String? = seats[uid] ?: engine?.let { e ->
        val info = UserInfo()
        if (e.getUserInfoByUid(uid, info) == 0) info.userAccount?.takeIf { VoiceChatRules.account(it) != null }?.also { seats[uid] = it } else null
    }

    private val events = object : IRtcEngineEventHandler() {
        override fun onUserJoined(uid: Int, elapsed: Int) {
            main.post { seatFor(uid)?.let { state = state.copy(inVoice = state.inVoice + it) } }
        }

        override fun onUserInfoUpdated(uid: Int, userInfo: UserInfo) {
            val seat = userInfo.userAccount?.takeIf { VoiceChatRules.account(it) != null } ?: return
            main.post {
                seats[uid] = seat
                state = state.copy(inVoice = state.inVoice + seat)
                if (seat in state.silenced) engine?.muteRemoteAudioStream(uid, true)
            }
        }

        override fun onUserOffline(uid: Int, reason: Int) {
            main.post {
                val seat = seats.remove(uid) ?: return@post
                heard.remove(seat)
                state = state.copy(inVoice = state.inVoice - seat, speaking = state.speaking - seat, selfMuted = state.selfMuted - seat)
            }
        }

        override fun onAudioVolumeIndication(speakers: Array<out AudioVolumeInfo>?, totalVolume: Int) {
            val levels = speakers?.map { it.uid to it.volume } ?: return
            main.post {
                val now = now()
                for ((uid, volume) in levels) {
                    // Agora reports you as uid 0.
                    val seat = if (uid == 0) account else seatFor(uid) ?: continue
                    if (seat == account && (state.muted || state.micBlocked)) continue
                    if (VoiceChatRules.isSpeaking(volume / 255.0)) heard[seat] = now
                }
                refreshSpeaking()
            }
        }

        override fun onRemoteAudioStateChanged(uid: Int, state: Int, reason: Int, elapsed: Int) {
            if (reason != Constants.REMOTE_AUDIO_REASON_REMOTE_MUTED && reason != Constants.REMOTE_AUDIO_REASON_REMOTE_UNMUTED) return
            val muted = reason == Constants.REMOTE_AUDIO_REASON_REMOTE_MUTED
            main.post {
                val seat = seatFor(uid) ?: return@post
                if (muted) heard.remove(seat)
                val now = this@VoiceRoom.state
                this@VoiceRoom.state = now.copy(selfMuted = if (muted) now.selfMuted + seat else now.selfMuted - seat,
                    speaking = if (muted) now.speaking - seat else now.speaking)
            }
        }

        override fun onTokenPrivilegeWillExpire(token: String?) {
            scope.launch { runCatching { this@VoiceRoom.token(channel, account).second }.getOrNull()?.let { engine?.renewToken(it) } }
        }

        override fun onRequestToken() {
            main.post {
                val muted = state.muted
                val allowed = !state.micBlocked
                leave()
                join(allowed)
                if (muted) scope.launch { delay(1500); if (state.stage == VoiceChatState.Stage.LIVE && !state.muted) toggleMute() }
            }
        }
    }
}

/** Set by online games while the server's voiceChat switch is on; the board shows the mic only then. */
val LocalVoiceRoom = compositionLocalOf<VoiceRoom?> { null }
