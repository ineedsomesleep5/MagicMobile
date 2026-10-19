package io.magicmobile.android.ondevice

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.tavernSettingsPanel
import io.magicmobile.android.game.GamePerformanceLog
import io.magicmobile.android.ui.GamePerformanceRecorder
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernButtonText
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernPanel

/**
 * GamePerformancePanel (MainMenuViews.swift): recent games' memory and heat, always reachable in Settings so the player can
 * share it to compare app versions. Numbers only, no cards or player names.
 */
@Composable
fun GamePerformancePanel() {
    val entries = remember { GamePerformanceRecorder.entries }
    var showReport by remember { mutableStateOf(false) }
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TavernPanelTitle("Game Performance")
        Text("Memory and heat from your recent games, to compare app versions. Numbers only, no cards or names. Nothing is sent unless you share it.",
            color = TavernPalette.parchment.copy(alpha = 0.65f), style = sf(12f, design = SfDesign.SERIF))
        Text(entries.lastOrNull()?.let { "Last game: ${it.line}" } ?: "Finish a game to record one.", Modifier.testTag("settings.performance.last"),
            color = TavernPalette.parchment.copy(alpha = 0.85f), style = sf(12f, SfWeight.semibold, SfDesign.SERIF))
        TavernButton({ showReport = true }, Modifier.testTag("settings.performance"), kind = TavernButtonKind.SECONDARY, compact = true,
            fullWidth = true, enabled = entries.isNotEmpty()) {
            SfImage("chart.bar.fill", TavernPalette.brass, 13.dp)
            TavernButtonText("View and Share")
        }
    }
    if (showReport) GamePerformanceDialog(GamePerformanceLog.section(entries, "${BuildConfig.VERSION_NAME} (${BuildConfig.RELEASE_BUILD})") ?: "") {
        showReport = false
    }
}

@Composable
private fun GamePerformanceDialog(report: String, close: () -> Unit) {
    val context = LocalContext.current
    Dialog(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().tavernPanel(16.dp).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { TavernPanelTitle("Game Performance") }
                TavernSealButton(close, Modifier.testTag("performance.close"))
            }
            TavernButton({
                val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, report) }
                runCatching { context.startActivity(Intent.createChooser(send, "Share game performance")) }
            }, Modifier.testTag("performance.share"), compact = true, fullWidth = true) {
                SfImage("square.and.arrow.up", TavernPalette.parchment, 13.dp)
                TavernButtonText("Share Report")
            }
            SelectionContainer {
                Text(report, Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()).testTag("performance.report"),
                    color = TavernPalette.parchment, style = sf(12f, design = SfDesign.MONOSPACED))
            }
        }
    }
}
