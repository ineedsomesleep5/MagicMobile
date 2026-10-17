package io.magicmobile.android.ondevice

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.ComboLoop
import io.magicmobile.android.game.ComboRepeat
import io.magicmobile.android.game.ComboStep
import io.magicmobile.android.session.OnDeviceSession
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.tavernPanel
import kotlinx.coroutines.delay

/**
 * The combo loop shortcut on the board (ComboLoopViews.swift): the offer after three identical rounds (what a round does, a count
 * picker, until I can't, until they lose), the repeating card with its last rounds and Stop (over a scrim that keeps stray taps off
 * the board), and the closing line.
 */
@Composable
fun ComboLoopOverlay(session: OnDeviceSession, modifier: Modifier = Modifier) {
    val run = session.comboRun
    val offer = session.comboOffer
    val result = session.comboResult
    var count by rememberSaveable { mutableIntStateOf(ComboLoop.PICKER_DEFAULT) }
    fun start(mode: ComboRepeat) { GameAudio.play(GameSound.MENU_PLAY); session.startComboLoop(mode) }
    Box(modifier.fillMaxSize()) {
        if (run != null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
            .clickable(remember { MutableInteractionSource() }, null) {})
        Column(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 64.dp).padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            AnimatedVisibility(run != null, enter = fadeIn(), exit = fadeOut()) {
                if (run != null) Column(Modifier.widthIn(max = 400.dp).fillMaxWidth().tavernPanel(14.dp).padding(16.dp).testTag("comboLoop.running"),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("arrow.triangle.2.circlepath", TavernPalette.brass, 16.dp)
                        Text(title(run), color = TavernPalette.parchment, style = sf(16f, SfWeight.black, SfDesign.SERIF))
                    }
                    run.mode.count?.let { target ->
                        LinearProgressIndicator({ run.done.toFloat() / maxOf(target, 1) }, Modifier.fillMaxWidth(), color = TavernPalette.ember)
                    }
                    Column(Modifier.fillMaxWidth().testTag("comboLoop.rounds"), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        run.lines.forEachIndexed { index, line ->
                            Text(line, Modifier.alpha(if (index == run.lines.lastIndex) 0.95f else 0.55f), color = TavernPalette.parchment,
                                style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    TavernPlaqueButton("Stop", { GameAudio.play(GameSound.UI_BACK); session.stopComboLoop() }, Modifier.fillMaxWidth().testTag("comboLoop.stop"),
                        kind = TavernButtonKind.DANGER, compact = false, systemImage = "stop.fill", fullWidth = true)
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
                    Preview(offer)
                    Text("Every step is still checked by the rules. It waits for your own triggers, keeps the same target until it's gone, and stops if an opponent responds.",
                        Modifier.alpha(0.7f), color = TavernPalette.parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF))
                    Picker(count) { count = it.coerceIn(1, ComboLoop.MAX_REPEATS) }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        TavernPlaqueButton("Repeat $count×", { start(ComboRepeat.Times(count)) }, Modifier.testTag("comboLoop.repeat"))
                        TavernPlaqueButton("Until I can't", { start(ComboRepeat.UntilCant) }, Modifier.testTag("comboLoop.untilCant"), kind = TavernButtonKind.SECONDARY)
                        TavernPlaqueButton("Until they lose", { start(ComboRepeat.UntilWin) }, Modifier.testTag("comboLoop.untilWin"), kind = TavernButtonKind.SECONDARY)
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

private fun title(run: OnDeviceSession.ComboRun): String = when (val mode = run.mode) {
    is ComboRepeat.Times -> "Repeating · ${run.done} of ${mode.rounds}"
    ComboRepeat.UntilCant -> "Repeating until you can't · ${run.done}"
    ComboRepeat.UntilWin -> "Repeating until they lose · ${run.done}"
}

/** EACH ROUND: what one round does, step by step. */
@Composable
private fun Preview(round: List<ComboStep>) {
    Column(Modifier.semantics(mergeDescendants = true) {}.testTag("comboLoop.preview"), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text("EACH ROUND", color = TavernPalette.brass, style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.2f))
        for (line in ComboLoop.preview(round)) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("chevron.right", TavernPalette.brass, 8.dp)
            Text(line, color = TavernPalette.parchment, style = sf(13f, SfWeight.regular, SfDesign.SERIF), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** − count +, with +5 and +10. */
@Composable
private fun Picker(count: Int, onChange: (Int) -> Unit) {
    @Composable
    fun ring(symbol: String, label: String, tag: String, enabled: Boolean, step: Int) {
        Box(Modifier.size(40.dp).alpha(if (enabled) 1f else 0.4f).tavernFill(TavernMaterial.LEATHER, CircleShape)
            .border(1.5.dp, BrandTheme.brassGradient, CircleShape)
            .clickable(remember { MutableInteractionSource() }, null, enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onChange(count + step) }
            .semantics { contentDescription = label }.testTag(tag), contentAlignment = Alignment.Center) {
            SfImage(symbol, TavernPalette.brass, 14.dp)
        }
    }
    Row(Modifier.fillMaxWidth().semantics { stateDescription = "$count rounds" }, horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        ring("minus", "One fewer", "comboLoop.minus", count > 1, -1)
        Text("$count", Modifier.widthIn(min = 44.dp).testTag("comboLoop.count"), color = TavernPalette.parchment, style = sf(22f, SfWeight.black, SfDesign.SERIF),
            textAlign = TextAlign.Center)
        ring("plus", "One more", "comboLoop.plus", count < ComboLoop.MAX_REPEATS, 1)
        Spacer(Modifier.weight(1f))
        TavernPlaqueButton("+5", { GameAudio.play(GameSound.UI_TICK); onChange(count + 5) }, Modifier.testTag("comboLoop.plus5"), kind = TavernButtonKind.SECONDARY)
        TavernPlaqueButton("+10", { GameAudio.play(GameSound.UI_TICK); onChange(count + 10) }, Modifier.testTag("comboLoop.plus10"), kind = TavernButtonKind.SECONDARY)
    }
}
