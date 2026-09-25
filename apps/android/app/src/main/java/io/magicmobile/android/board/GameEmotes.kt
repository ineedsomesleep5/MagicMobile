package io.magicmobile.android.board

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.random.Random

/** Port of GameEmotes.swift. Quick chat: a fixed set of friendly lines, never free text. */
enum class GameEmote(val rawValue: String, val text: String, val symbol: String) {
    HELLO("hello", "Hello!", "hand.wave.fill"), WELL_PLAYED("wellPlayed", "Well played!", "hands.clap.fill"),
    THANKS("thanks", "Thanks!", "heart.fill"), OOPS("oops", "Oops!", "exclamationmark.bubble.fill"),
    WOW("wow", "Wow!", "sparkles"), GOOD_GAME("goodGame", "Good game!", "flag.checkered");

    /** What an AI opponent says back, when it answers at all. */
    val aiReply: GameEmote? get() = when (this) { HELLO -> HELLO; WELL_PLAYED -> THANKS; GOOD_GAME -> GOOD_GAME; WOW -> THANKS; else -> null }

    companion object { fun of(raw: String?): GameEmote? = entries.firstOrNull { it.rawValue == raw } }
}

/** Speech bubbles on the table, keyed by engine player ID, plus the way out to other players. */
class EmoteCenter(private val scope: CoroutineScope = MainScope()) {
    data class Bubble(val emote: GameEmote, val id: String = UUID.randomUUID().toString())

    val bubbles = mutableStateMapOf<String, Bubble>()
    var canSend by mutableStateOf(true); private set
    /** Online and Game Center-style games deliver your emote to the other players. */
    var send: ((GameEmote) -> Unit)? = null
    private val lastHeard = HashMap<String, Long>()

    fun show(emote: GameEmote, playerID: String) {
        val bubble = Bubble(emote)
        bubbles[playerID] = bubble
        GameAudio.play(GameSound.EMOTE)
        scope.launch { delay(2600); if (bubbles[playerID]?.id == bubble.id) bubbles.remove(playerID) }
    }

    /** You emote: show it, tell the other players, and let an AI opponent answer now and then. */
    fun say(emote: GameEmote, snapshot: GameSnapshot) {
        if (!canSend) return
        canSend = false
        scope.launch { delay(2000); canSend = true }
        show(emote, snapshot.viewerID)
        send?.invoke(emote)
        val bots = snapshot.players.filter { !snapshot.isViewer(it.playerId) && it.isHuman == false && !it.isOut }
        val reply = emote.aiReply
        val bot = bots.randomOrNull()
        if (reply != null && bot != null && Random.nextDouble() < 0.6) {
            scope.launch { delay((1100 + Random.nextDouble() * 900).toLong()); show(reply, bot.playerId) }
        }
    }

    /** Another player's emote, matched to their seat by the name shown at the table. */
    fun receive(emote: GameEmote, fromName: String, snapshot: GameSnapshot?) {
        snapshot ?: return
        val player = snapshot.players.firstOrNull { !snapshot.isViewer(it.playerId) && it.displayName == fromName } ?: return
        val now = System.currentTimeMillis()
        lastHeard[player.playerId]?.let { if (now - it < 1500) return }
        lastHeard[player.playerId] = now
        show(emote, player.playerId)
    }

    fun reset() { bubbles.clear(); lastHeard.clear() }
}

/** Set by on-device games (Swift `\.emoteCenter`). */
val LocalEmoteCenter = compositionLocalOf<EmoteCenter?> { null }

/** The bubble for one player, if they just emoted. */
@Composable
fun EmoteBubbleSlot(center: EmoteCenter, playerID: String, pointsUp: Boolean = false, modifier: Modifier = Modifier) {
    val bubble = center.bubbles[playerID]
    Box(modifier) {
        AnimatedVisibility(bubble != null,
            enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn(spring(0.62f, Spring.StiffnessMediumLow), 0.4f,
                TransformOrigin(0.5f, if (pointsUp) 0f else 1f)) + fadeIn(),
            exit = fadeOut()) {
            bubble?.let { EmoteBubble(it.emote, pointsUp) }
        }
    }
}

/** The latest opponent emote, named when it is not the opponent in focus. */
@Composable
fun OpponentEmoteSlot(center: EmoteCenter, snapshot: GameSnapshot, focusedID: String, modifier: Modifier = Modifier) {
    val opponents = snapshot.players.filter { !snapshot.isViewer(it.playerId) }
    val withBubbles = opponents.mapNotNull { player -> center.bubbles[player.playerId]?.let { player to it } }
    val latest = withBubbles.firstOrNull { it.first.playerId == focusedID } ?: withBubbles.firstOrNull()
    Box(modifier) {
        AnimatedVisibility(latest != null,
            enter = if (BoardMotion.reduceMotion) fadeIn() else scaleIn(spring(0.62f, Spring.StiffnessMediumLow), 0.4f, TransformOrigin(0.5f, 0f)) + fadeIn(),
            exit = fadeOut()) {
            latest?.let { (player, bubble) -> EmoteBubble(bubble.emote, name = if (player.playerId == focusedID) null else player.displayName) }
        }
    }
}

@Composable
fun EmoteBubble(emote: GameEmote, pointsUp: Boolean = false, name: String? = null) {
    val shape = RoundedCornerShape(14.dp)
    Row(Modifier.glow(Color.Black.copy(alpha = 0.45f), 8.dp, 14.dp)
        .background(Brush.verticalGradient(listOf(rgb(1.0, 0.98, 0.92), rgb(0.93, 0.87, 0.74))), shape)
        .border(1.5.dp, MagicPalette.antiqueGold, shape).padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(emote.symbol, MagicPalette.oxblood, 15.dp)
        if (name != null) Text("$name:", color = MagicPalette.oxblood, style = sf(13f, SfWeight.heavy, SfDesign.ROUNDED), softWrap = false)
        Text(emote.text, color = rgb(0.16, 0.11, 0.08), style = sf(15f, SfWeight.heavy, SfDesign.ROUNDED), softWrap = false)
    }
}

/** Emote choices shown when you tap your own life orb. */
@Composable
fun EmotePicker(center: EmoteCenter, snapshot: GameSnapshot, done: () -> Unit) {
    Column(Modifier.width(300.dp).background(MagicPalette.iron.copy(alpha = 0.97f)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("QUICK CHAT", color = MagicPalette.antiqueGold, style = sf(11f, SfWeight.black, tracking = 1.6f))
        for (row in GameEmote.entries.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (emote in row) {
                    CompactActionButton(isPrimary = false, enabled = center.canSend, modifier = Modifier.weight(1f),
                        onClick = { center.say(emote, snapshot); done() }) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                            SfImage(emote.symbol, Color.White, 15.dp)
                            Text(" ${emote.text}", style = sf(14f, SfWeight.heavy, SfDesign.ROUNDED), color = Color.White)
                        }
                    }
                }
            }
        }
    }
}
