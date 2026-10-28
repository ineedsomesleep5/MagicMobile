package io.magicmobile.android.board

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import io.magicmobile.android.game.VoiceChatRules
import io.magicmobile.android.game.VoiceChatState
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.ondevice.VoiceRoom
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb

/** Voice chat on the Arena board (iOS ArenaVoiceViews, the web board's .amic, .aspeak and .avoice; docs/VOICE_CHAT.md). */
object ArenaVoice {
    val talking = rgb(0.55, 1.0, 0.65)
    val muted = rgb(1.0, 0.54, 0.48)
}

/** The mic by your medallion: tap to join voice (asking for the microphone first), then to turn it off and on. */
@Composable
fun ArenaVoiceMic(room: VoiceRoom, modifier: Modifier = Modifier) {
    val state = room.state
    if (state.stage == VoiceChatState.Stage.UNAVAILABLE) return
    val context = LocalContext.current
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> room.join(granted) }
    val pushToTalk by AppPreferences.boolean(VoiceChatRules.PUSH_TO_TALK_KEY, false)
    LaunchedEffect(room, pushToTalk) { room.setPushToTalk(pushToTalk) }
    // Push to talk while live: held, the microphone is open; let go, it closes.
    val holdToTalk = pushToTalk && state.stage == VoiceChatState.Stage.LIVE && !state.micBlocked
    val live = state.stage == VoiceChatState.Stage.LIVE
    val talking = live && room.account in state.speaking
    val tint = when {
        talking -> ArenaVoice.talking
        live && state.muted -> ArenaVoice.muted
        live -> ArenaMenuStyle.gold
        else -> ArenaMenuStyle.gold.copy(alpha = 0.7f)
    }
    val label = when {
        state.stage == VoiceChatState.Stage.OFF -> "Join voice chat"
        holdToTalk -> "Hold to talk"
        state.micBlocked -> "Microphone not allowed, open settings"
        state.muted -> "Turn your microphone on"
        else -> "Turn your microphone off"
    }
    val press = if (holdToTalk) Modifier.pointerInput(room) {
        detectTapGestures(onPress = { room.talk(true); tryAwaitRelease(); room.talk(false) })
    } else Modifier.clickable(enabled = state.stage != VoiceChatState.Stage.JOINING) {
        when {
            state.stage == VoiceChatState.Stage.OFF ->
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) room.join(true)
                else ask.launch(Manifest.permission.RECORD_AUDIO)
            state.micBlocked -> context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            else -> room.toggleMute()
        }
    }
    Box(modifier.size(44.dp).then(press).semantics { contentDescription = label; testTag = "board.voice.mic" }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(30.dp).alpha(if (state.stage == VoiceChatState.Stage.JOINING) 0.5f else 1f)
            .glow(if (talking) ArenaVoice.talking.copy(alpha = 0.6f) else Color.Black.copy(alpha = 0.5f), if (talking) 6.dp else 2.dp, 15.dp)
            .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape)
            .border(1.dp, if (talking) Brush.verticalGradient(listOf(ArenaVoice.talking, ArenaVoice.talking))
                else if (live && state.muted) Brush.verticalGradient(listOf(ArenaVoice.muted, ArenaVoice.muted)) else ArenaGlass.hairline, CircleShape),
            contentAlignment = Alignment.Center) {
            SfImage(if (live && !state.muted) "mic.fill" else "mic.slash.fill", tint, 13.dp)
        }
    }
}

/** A green halo round a player who is talking, and on an opponent in voice a small mic (red when muted). */
@Composable
fun ArenaVoiceHalo(room: VoiceRoom, seat: String, diameter: Dp, badge: Boolean) {
    val state = room.state
    val talking = seat in state.speaking
    val quiet = seat in state.selfMuted || seat in state.silenced
    val breath = if (BoardMotion.reduceMotion || !talking) null else rememberBoardBreath(900, 0.6f, 1f)
    Box(Modifier.size(diameter).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (talking) Box(Modifier.requiredSize(diameter * 1.16f).alpha(breath?.invoke() ?: 1f)
            .glow(ArenaVoice.talking.copy(alpha = 0.6f), diameter * 0.12f, diameter * 0.58f)
            .border(2.dp, ArenaVoice.talking.copy(alpha = 0.9f), CircleShape))
        if (badge && state.stage == VoiceChatState.Stage.LIVE && seat in state.inVoice) {
            Box(Modifier.align(Alignment.Center).offset(diameter * 0.4f, -diameter * 0.4f).size(diameter * 0.34f)
                .background(ArenaGlass.bottom, CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
                SfImage(if (quiet) "mic.slash.fill" else "mic.fill", if (quiet) ArenaVoice.muted else ArenaMenuStyle.gold, diameter * 0.16f)
            }
        }
    }
}

/** Mute Voice / Unmute Voice on an opponent's player card, for you alone. */
@Composable
fun ArenaVoiceSilenceButton(room: VoiceRoom, seat: String) {
    val state = room.state
    if (state.stage != VoiceChatState.Stage.LIVE || seat !in state.inVoice) return
    val silenced = seat in state.silenced
    ArenaButton({ room.silence(seat, !silenced) }, Modifier.fillMaxWidth(), kind = ArenaButtonKind.SECONDARY, compact = true,
        identifier = "board.voice.silence") { ArenaButtonText(if (silenced) "Unmute Voice" else "Mute Voice") }
}
