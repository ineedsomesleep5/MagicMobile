package io.magicmobile.android

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSelection
import io.magicmobile.android.board.LocalGameRematchTitle
import io.magicmobile.android.board.NativeGameView
import io.magicmobile.android.board.PortraitModePreference
import io.magicmobile.android.game.GameBoardDesignPreviewState
import io.magicmobile.android.game.GameBoardPreviewFixtures
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfText
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Debug builds only: the iOS design previews (MAGICMOBILE_DESIGN_PREVIEW) on the Android
 * board, fed by the same fixtures, so screens can be compared side by side. Commands are
 * captured, never sent to an engine.
 */
object DesignPreview {
    val keys = listOf("MAGICMOBILE_DESIGN_PREVIEW", "MAGICMOBILE_FORCE_CARD_PLACEHOLDERS", "MAGICMOBILE_UI_TEST_PREFERENCES",
        "MAGICMOBILE_PREVIEW_INSPECT", "MAGICMOBILE_BOARD_FX_AUTOPLAY", "MAGICMOBILE_BOARD_EFFECTS", "MAGICMOBILE_FONT_CHECK", "MAGICMOBILE_RELAY_URL",
        "MAGICMOBILE_BOARD_FX_FREEZE", "MAGICMOBILE_PREVIEW_OPEN_LOG")

    fun extras(intent: Intent?): Map<String, String> {
        if (!BuildConfig.DEBUG || intent == null) return emptyMap()
        return keys.mapNotNull { key -> intent.getStringExtra(key)?.let { key to it } }.toMap()
    }

    val active: Boolean get() = BuildConfig.DEBUG && !LaunchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"].isNullOrEmpty()
}

/** Debug: logs measured text widths (no letter spacing) so Apple width corrections can be calibrated on a device. */
@Composable
private fun FontCheck() {
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    LaunchedEffect(Unit) {
        val samples = listOf("Serra Angel", "Silvercoat Lion", "Isamaru, Hound of Konda", "Sol Ring", "Forest", "Plains", "Wastes", "Swords to Plowshares", "Grizzly Bears", "Llanowar Elves", "Spirited Companion", "Pass Priority", "Let this step continue", "YOUR TURN", "MAIN 1", "Your priority", "Aurelia", "31 life", "Hand · 8", "Creature — Angel", "Basic Land — Forest", "Choose a highlighted target", "Waiting for XMage", "Opening hand", "Mulligan", "Keep", "Timing Options", "Game Log", "Victory", "Defeat", "The quick brown fox jumps over the lazy dog", "Commander", "Deck Studio", "Play against the AI", "Sound Lab", "Settings", "Downloads", "Online", "New Game", "Main Menu")
        val names = mapOf(io.magicmobile.android.ui.SfDesign.DEFAULT to "sans", io.magicmobile.android.ui.SfDesign.SERIF to "serif", io.magicmobile.android.ui.SfDesign.ROUNDED to "rounded")
        for ((design, name) in names) for (weight in listOf(400, 500, 600, 700, 800, 900)) for (size in listOf(8f, 10f, 12f, 15f, 17f, 20f, 24f, 34f, 48f)) {
            val style = io.magicmobile.android.ui.sf(size, androidx.compose.ui.text.font.FontWeight(weight), design).copy(letterSpacing = androidx.compose.ui.unit.TextUnit.Unspecified)
            val widths = samples.joinToString("\t") { "%.3f".format(measurer.measure(it, style, softWrap = false).multiParagraph.intrinsics.maxIntrinsicWidth / density) }
            android.util.Log.d("MMFontCheck", "$name\t$weight\t${size.toInt()}\t$widths")
        }
        android.util.Log.d("MMFontCheck", "done")
    }
}

@Composable
fun DesignPreviewHost() {
    if (LaunchEnvironment["MAGICMOBILE_FONT_CHECK"] == "1") FontCheck()
    val preview = LaunchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] ?: return
    val state = GameBoardDesignPreviewState.of(preview) ?: GameBoardDesignPreviewState.NORMAL_BATTLEFIELD
    var boardFXStep by remember { mutableIntStateOf(0) }
    var snapshot by remember { mutableStateOf(if (preview == "board-fx") GameBoardPreviewFixtures.boardFXStep(0)
        else GameBoardPreviewFixtures.snapshot(state, environment = LaunchEnvironment.values)) }
    var status by remember { mutableStateOf("") }
    val selection = remember {
        BoardSelection().also { selection ->
            val initial = snapshot
            selection.selectedCard = GameBoardPreviewFixtures.selectedCard(state, initial)
            selection.inspectedCard = GameBoardPreviewFixtures.inspectedCard(state, initial)
            LaunchEnvironment["MAGICMOBILE_PREVIEW_INSPECT"]?.let { id ->
                selection.inspectedCard = initial.players.flatMap { it.zones.battlefield }.firstOrNull { it.instanceId == id }
            }
        }
    }
    var portrait by AppPreferences.boolean(PortraitModePreference.key, true)
    if (preview == "board-fx" && LaunchEnvironment["MAGICMOBILE_BOARD_FX_AUTOPLAY"] == "1") {
        LaunchedEffect(Unit) {
            while (true) {
                delay(3600)
                boardFXStep = (boardFXStep + 1) % GameBoardPreviewFixtures.boardFXStepCount
                snapshot = GameBoardPreviewFixtures.boardFXStep(boardFXStep)
            }
        }
    }
    if (preview == "first-strike") {
        LaunchedEffect(Unit) {
            // Declared blocks first, then XMage's first-strike damage step. Replays unless
            // MAGICMOBILE_BOARD_FX_FREEZE holds the beat for a screenshot.
            while (true) {
                delay(1200)
                snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FIRST_STRIKE, specialStateAdvanced = true)
                if (io.magicmobile.android.board.BoardFXPreviewFreeze.seconds != null) break
                delay(3600)
                snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FIRST_STRIKE)
            }
        }
    }
    if (preview == "ability-showcase") {
        LaunchedEffect(Unit) {
            // The ability goes on the stack once the board has settled, and replays unless
            // MAGICMOBILE_BOARD_FX_FREEZE holds it for a screenshot.
            while (true) {
                delay(1200)
                snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.ABILITY_SHOWCASE, specialStateAdvanced = true)
                if (io.magicmobile.android.board.BoardFXPreviewFreeze.seconds != null) break
                delay(2400)
                snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.ABILITY_SHOWCASE)
            }
        }
    }
    MaterialTheme(colorScheme = darkColorScheme()) {
        Box(Modifier.fillMaxSize()) {
            NativeGameView(snapshot, selection, null, null, null, "Design Preview", { status = it },
                { action -> status = "Development fixture: captured ${action.label}. No engine command sent." },
                { _, label, _ -> status = "Development fixture: captured $label. No engine command sent." },
                {}, {}, { null }, {}, {}, portrait, { portrait = it })
            Column(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 24.dp)) {
                if (status.startsWith("Development fixture: captured")) {
                    Text(status, Modifier.background(Color.Black).padding(4.dp).semantics { contentDescription = "preview.captured-command" },
                        color = Color.White, style = SfText.caption2())
                }
                if (preview == "board-fx") {
                    Text("Next board FX step ($boardFXStep)", Modifier.background(Color.Black).clickable {
                        boardFXStep = (boardFXStep + 1) % GameBoardPreviewFixtures.boardFXStepCount
                        snapshot = GameBoardPreviewFixtures.boardFXStep(boardFXStep)
                    }.padding(8.dp).semantics { contentDescription = "preview.boardFX.next" }, color = Color(0xFF0A84FF), style = SfText.caption())
                }
                if (preview == "first-strike") {
                    val scope = androidx.compose.runtime.rememberCoroutineScope()
                    Text("Replay first strike", Modifier.background(Color.Black).clickable {
                        snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FIRST_STRIKE)
                        scope.launch {
                            delay(400)
                            snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.FIRST_STRIKE, specialStateAdvanced = true)
                        }
                    }.padding(8.dp).semantics { contentDescription = "preview.advance" }, color = Color(0xFF0A84FF), style = SfText.caption())
                }
                if (preview == "ability-showcase") {
                    val scope = androidx.compose.runtime.rememberCoroutineScope()
                    Text("Replay ability", Modifier.background(Color.Black).clickable {
                        snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.ABILITY_SHOWCASE)
                        scope.launch {
                            delay(400)
                            snapshot = GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.ABILITY_SHOWCASE, specialStateAdvanced = true)
                        }
                    }.padding(8.dp).semantics { contentDescription = "preview.advance" }, color = Color(0xFF0A84FF), style = SfText.caption())
                }
                if (preview == "phase-announcement" || preview == "life-change" || preview == "attached-permanents") {
                    Text(if (preview == "phase-announcement") "Advance preview phase" else "Preview life change", Modifier.background(Color.Black).clickable {
                        snapshot = when (preview) {
                            "phase-announcement" -> GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.PHASE_ANNOUNCEMENT, step = "DECLARE_BLOCKERS")
                            "attached-permanents" -> GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.ATTACHED_PERMANENTS, specialStateAdvanced = true)
                            else -> GameBoardPreviewFixtures.snapshot(GameBoardDesignPreviewState.LIFE_CHANGE, life = if (snapshot.human?.life == 37) 35 else 43)
                        }
                    }.padding(8.dp).semantics { contentDescription = "preview.advance" }, color = Color(0xFF0A84FF), style = SfText.caption())
                }
            }
        }
    }
}
