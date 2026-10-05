package io.magicmobile.android.ranked

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.game.FriendChallenge
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernPanel

/** The challenger's wait while their friend answers (ChallengeWaitingOverlay, FriendChallengeViews.swift). */
@Composable
fun ChallengeWaitingOverlay(friend: String, mode: PlayMode, rank: RankPosition, cancel: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.72f)).clickable(remember { MutableInteractionSource() }, null) {}
        .testTag("challenge.waiting"), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(20.dp).widthIn(max = 420.dp).fillMaxWidth().tavernPanel(16.dp).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (mode == PlayMode.RANKED) RankSpinEmblem(rank.tier, 104.dp, durationMillis = 2400, forever = true)
            else Box(Modifier.height(104.dp), contentAlignment = Alignment.Center) { SfImage("figure.fencing", TavernPalette.brass, 54.dp) }
            Text(if (mode == PlayMode.RANKED) "Ranked challenge sent" else "Quick Match challenge sent", color = TavernPalette.parchment,
                style = sf(22f, SfWeight.black, SfDesign.SERIF), textAlign = TextAlign.Center)
            Text("Waiting for $friend…", color = TavernPalette.brass, style = sf(18f, SfWeight.bold, SfDesign.SERIF), textAlign = TextAlign.Center)
            Text(if (mode == PlayMode.RANKED) "This game counts for both of you." else "A friendly game: no rank change.",
                color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center)
            TavernPlaqueButton("Withdraw challenge", cancel, Modifier.testTag("challenge.cancel"), kind = TavernButtonKind.SECONDARY, compact = false)
        }
    }
}

/** A friend's challenge arriving on the menu: the mode and Accept or Decline (ChallengeInviteBanner). */
@Composable
fun ChallengeInviteBanner(challenge: FriendChallenge, accept: () -> Unit, decline: () -> Unit, modifier: Modifier = Modifier) {
    LaunchedEffect(challenge.id) { GameAudio.play(GameSound.UI_OPEN) }
    val pulse = if (LaunchEnvironment.reduceMotion) 1f else {
        val transition = rememberInfiniteTransition(label = "challengePulse")
        val value by transition.animateFloat(1f, 1.08f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "challengePulseScale")
        value
    }
    Row(modifier.padding(horizontal = 12.dp).widthIn(max = 560.dp).fillMaxWidth()
        .glow(TavernPalette.ember.copy(alpha = 0.45f), 12.dp, 14.dp).tavernPanel(14.dp).padding(horizontal = 14.dp, vertical = 10.dp)
        .testTag("challenge.invite"), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).scale(pulse), contentAlignment = Alignment.Center) {
            val step = challenge.challengerStep
            if (challenge.isRanked && step != null) RankEmblem(RankPosition.atStep(step).tier, 44.dp)
            else SfImage("figure.fencing", TavernPalette.brass, 24.dp)
        }
        Column(Modifier.weight(1f)) {
            Text("${challenge.challenger ?: "A friend"} challenges you", color = TavernPalette.parchment, maxLines = 1,
                style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
            Text(if (challenge.isRanked) "Ranked · counts for both" else "Quick Match · friendly", color = TavernPalette.parchment.copy(alpha = 0.8f),
                style = sf(12f, SfWeight.regular, SfDesign.SERIF))
        }
        TavernPlaqueButton("Decline", decline, Modifier.testTag("challenge.decline"), kind = TavernButtonKind.SECONDARY)
        TavernPlaqueButton("Accept", accept, Modifier.testTag("challenge.accept"))
    }
}
