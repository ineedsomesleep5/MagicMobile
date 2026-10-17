package io.magicmobile.android.ondevice

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.ComboLoop
import io.magicmobile.android.session.OnDeviceSession
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernPanel
import kotlinx.coroutines.delay

/**
 * The combo loop shortcut on the board (ComboLoopViews.swift): the offer after three identical rounds, the repeating card with its
 * Stop button (over a scrim that keeps stray taps off the board), and the closing line.
 */
@Composable
fun ComboLoopOverlay(session: OnDeviceSession, modifier: Modifier = Modifier) {
    val run = session.comboRun
    val offer = session.comboOffer
    val result = session.comboResult
    Box(modifier.fillMaxSize()) {
        if (run != null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
            .clickable(remember { MutableInteractionSource() }, null) {})
        Column(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 64.dp).padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            AnimatedVisibility(run != null, enter = fadeIn(), exit = fadeOut()) {
                if (run != null) Column(Modifier.widthIn(max = 380.dp).fillMaxWidth().tavernPanel(14.dp).padding(16.dp).testTag("comboLoop.running"),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("arrow.triangle.2.circlepath", TavernPalette.brass, 16.dp)
                        Text(run.target?.let { "Repeating · ${run.done} of $it" } ?: "Repeating · ${run.done} done", color = TavernPalette.parchment,
                            style = sf(16f, SfWeight.black, SfDesign.SERIF))
                    }
                    val target = run.target
                    if (target != null) LinearProgressIndicator({ run.done.toFloat() / maxOf(target, 1) }, Modifier.fillMaxWidth(), color = TavernPalette.ember)
                    else Text("Until every opponent has lost", Modifier.alpha(0.75f), color = TavernPalette.parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                    Text(ComboLoop.describe(run.round), Modifier.alpha(0.7f), color = TavernPalette.parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    TavernPlaqueButton("Stop", { GameAudio.play(GameSound.UI_BACK); session.stopComboLoop() }, Modifier.fillMaxWidth().testTag("comboLoop.stop"),
                        kind = TavernButtonKind.DANGER, systemImage = "stop.fill")
                }
            }
            AnimatedVisibility(run == null && offer != null, enter = slideInVertically { -it / 2 } + fadeIn(), exit = slideOutVertically { -it / 2 } + fadeOut()) {
                if (offer != null) Column(Modifier.widthIn(max = 460.dp).fillMaxWidth().tavernPanel(14.dp).padding(14.dp).testTag("comboLoop.offer"),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SfImage("arrow.triangle.2.circlepath", TavernPalette.brass, 16.dp)
                        Text("Loop spotted", Modifier.weight(1f), color = TavernPalette.parchment, style = sf(16f, SfWeight.black, SfDesign.SERIF))
                        Box(Modifier.size(36.dp).clickable { GameAudio.play(GameSound.UI_BACK); session.declineComboLoop() }
                            .semantics { contentDescription = "Not now"; role = Role.Button }.testTag("comboLoop.decline"), contentAlignment = Alignment.Center) {
                            SfImage("xmark", TavernPalette.parchment, 12.dp)
                        }
                    }
                    Text(ComboLoop.describe(offer), Modifier.alpha(0.85f), color = TavernPalette.parchment, style = sf(13f, SfWeight.regular, SfDesign.SERIF), maxLines = 2)
                    Text("You've done this three times. Repeat it? Every step is still checked by the rules, and it stops if anything changes.",
                        Modifier.alpha(0.7f), color = TavernPalette.parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (count in ComboLoop.repeatChoices) TavernPlaqueButton("$count×", { GameAudio.play(GameSound.MENU_PLAY); session.startComboLoop(count) },
                            Modifier.testTag("comboLoop.repeat.$count").semantics { contentDescription = "Repeat $count times" }, kind = TavernButtonKind.SECONDARY)
                        TavernPlaqueButton("Until they lose", { GameAudio.play(GameSound.MENU_PLAY); session.startComboLoop(null) }, Modifier.testTag("comboLoop.untilWin"))
                    }
                }
            }
            AnimatedVisibility(run == null && offer == null && result != null, enter = slideInVertically { -it / 2 } + fadeIn(), exit = fadeOut()) {
                if (result != null) {
                    LaunchedEffect(result) { delay(9_000); if (session.comboResult == result) session.comboResult = null }
                    Row(Modifier.widthIn(max = 460.dp).fillMaxWidth().tavernPanel(14.dp).padding(start = 14.dp, end = 6.dp, top = 8.dp, bottom = 8.dp)
                        .semantics(mergeDescendants = true) {}.testTag("comboLoop.result"),
                        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("checkmark.seal.fill", TavernPalette.brass, 15.dp)
                        Text(result, Modifier.weight(1f), color = TavernPalette.parchment, style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
                        Box(Modifier.size(32.dp).clickable { session.comboResult = null }.semantics { contentDescription = "Dismiss"; role = Role.Button },
                            contentAlignment = Alignment.Center) { SfImage("xmark", TavernPalette.parchment, 11.dp) }
                    }
                }
            }
        }
    }
}
