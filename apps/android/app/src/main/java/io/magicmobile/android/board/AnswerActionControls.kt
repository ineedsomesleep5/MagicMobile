package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.text.style.TextAlign
import io.magicmobile.android.game.OnDeviceSmartPass
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernButtonText
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernToggle
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf

/**
 * What this game's engine lets a seat ask XMage to remember (OnDeviceSession.supportedAnswerActions), and the controls to
 * forget it again (BoardAnswerActions on iOS). Empty on older engines and for guests, which hides every remember control.
 */
data class BoardAnswerActions(
    val supported: Set<String> = emptySet(),
    val rememberedAnswers: Int = 0,
    val rememberedTriggerOrders: Int = 0,
    val forgetAnswers: () -> Unit = {},
    val forgetTriggerOrder: () -> Unit = {},
)

val LocalBoardAnswerActions = compositionLocalOf { BoardAnswerActions() }

/**
 * "Don't ask again this game" under a card's yes/no question, "Always put my pick first" on the trigger order: a brass check
 * box on leather. Ticked, the next answer also asks XMage to remember it.
 */
@Composable
fun RememberChoiceToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.defaultMinSize(minHeight = 44.dp).clickable { onChange(!isOn) }
        .semantics { contentDescription = "prompt.remember"; stateDescription = if (isOn) "On" else "Off"; role = Role.Checkbox },
        horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        if (io.magicmobile.android.menus.LocalArenaBoard.current) {
            // On the Arena board: a gold diamond and light sans words, Arena's checkbox, no brass or parchment.
            SfImage(if (isOn) "diamond.fill" else "diamond", if (isOn) io.magicmobile.android.menus.ArenaMenuStyle.gold
                else io.magicmobile.android.menus.ArenaGlass.text.copy(alpha = 0.7f), 12.dp)
            Text(title, color = io.magicmobile.android.menus.ArenaGlass.text.copy(alpha = 0.9f), style = io.magicmobile.android.menus.ArenaMenuStyle.font(13f, SfWeight.medium), maxLines = 2)
            return@Row
        }
        SfImage(if (isOn) "checkmark.square.fill" else "square", if (isOn) TavernPalette.brass else TavernPalette.parchment.copy(alpha = 0.7f), 15.dp)
        Text(title, color = TavernPalette.parchment.copy(alpha = 0.92f), style = sf(13f, SfWeight.semibold, SfDesign.SERIF), maxLines = 2)
    }
}

/** A small brass plaque on leather: "Resolve all" for the stack (CommandBar's resolve-stack command). */
@Composable
fun ResolveStackButton(action: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.defaultMinSize(minHeight = 44.dp).clickable(onClick = action)
        .semantics { contentDescription = "Resolve all. Passes until the stack has resolved; stops if an opponent responds." },
        contentAlignment = Alignment.Center) {
        Row(Modifier.glow(Color.Black.copy(alpha = 0.45f), 3.dp, 15.dp).background(TavernPalette.leather.copy(alpha = 0.95f), CircleShape)
            .border(1.2.dp, TavernPalette.brass, CircleShape).padding(horizontal = 11.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("forward.fill", TavernPalette.parchment, 10.dp)
            Text("Resolve all", color = TavernPalette.parchment, style = sf(12f, SfWeight.bold, SfDesign.SERIF), maxLines = 1)
        }
    }
}

/** Settings: after you cast a spell, priority passes so it resolves without another tap. On by default. */
object AutoPassAfterCast {
    const val KEY = "magicmobile.autoPassAfterCast"
}

@Composable
fun AutoPassAfterCastToggle() {
    var isOn by AppPreferences.boolean(AutoPassAfterCast.KEY, true)
    Box(Modifier.tavernSettingsPanel().semantics { contentDescription = "settings.autoPassAfterCast" }) {
        TavernToggle("Pass After Casting", isOn, { isOn = it }, subtitle = "Your spell resolves without another tap. Opponents can still respond.",
            color = TavernPalette.parchment)
    }
}

/** Settings: smart auto-pass (OnDeviceSmartPass, on by default) and the button to its phase stops. SmartAutoPassToggle on iOS. */
@Composable
fun SmartAutoPassToggle() {
    var isOn by AppPreferences.boolean(OnDeviceSmartPass.ENABLED_KEY, true)
    var stopForOwn by AppPreferences.boolean(OnDeviceSmartPass.STOP_FOR_OWN_SPELLS_KEY, false)
    var stopForThreats by AppPreferences.boolean(OnDeviceSmartPass.STOP_FOR_THREATS_KEY, true)
    var showStops by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.tavernSettingsPanel().semantics { contentDescription = "settings.smartAutoPass" }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TavernToggle("Smart Auto-Pass", isOn, { isOn = it },
            subtitle = "Passes for you when you have nothing to play, and skips steps you don\u2019t stop at.", color = TavernPalette.parchment)
        TavernToggle("Stop for My Own Spells", stopForOwn, { stopForOwn = it },
            Modifier.semantics { contentDescription = "settings.stopForOwnSpells" },
            subtitle = "Off: your own spells and triggers resolve without a stop, as on Arena.", enabled = isOn, color = TavernPalette.parchment)
        TavernToggle("Stop for Removal", stopForThreats, { stopForThreats = it }, Modifier.semantics { contentDescription = "settings.stopForThreats" },
            subtitle = "An opponent's spell that destroys, exiles or takes your permanents waits for you, even when you can't answer it.",
            color = TavernPalette.parchment)
        TavernButton({ showStops = true }, Modifier.fillMaxWidth().semantics { contentDescription = "settings.phaseStops" },
            kind = TavernButtonKind.SECONDARY, compact = true, enabled = isOn) {
            SfImage("hand.raised.fill", TavernPalette.parchment, 13.dp); TavernButtonText("Phase Stops")
        }
    }
    if (showStops) PhaseStopsSheet { showStops = false }
}

/** The phase stops on a tavern sheet; also opened by tapping the phase plate in a game. PhaseStopsSheet on iOS. */
@Composable
fun PhaseStopsSheet(dismiss: () -> Unit) {
    BoardSheet(dismiss) {
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 10.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            TavernPanelTitle("Phase Stops", Modifier.weight(1f, fill = false))
            Spacer(Modifier.weight(1f))
            TavernSealButton(dismiss, Modifier.semantics { contentDescription = "phaseStops.close" })
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(18.dp)) { PhaseStopsGrid() }
    }
}

/**
 * Where smart auto-pass stops when you have something to play: one row per step, a stop for your turn and one for your
 * opponents' turns. Stored under the same key and words as iOS.
 */
@Composable
fun PhaseStopsGrid() {
    val enabled by AppPreferences.boolean(OnDeviceSmartPass.ENABLED_KEY, true)
    var raw by AppPreferences.string(OnDeviceSmartPass.STOPS_KEY, OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops))
    val stops = OnDeviceSmartPass.Settings.decode(raw)
    Column(Modifier.fillMaxWidth()) {
        // In the Arena look the grid speaks for itself (AGENTS.md: no helper text); off, it says why nothing stops.
        if (!io.magicmobile.android.menus.LocalArenaBoard.current || !enabled) Text(if (enabled) "With something to play, the game stops at the steps you mark. With nothing to play it passes for you. It stops when you can answer an opponent's spell or attack, and lets your own spells resolve unless you turn on Stop for My Own Spells in Settings."
             else "Smart Auto-Pass is off, so every step waits for you. Turn it on in Settings to use these stops.",
            Modifier.padding(bottom = 12.dp), color = TavernPalette.parchment.copy(alpha = 0.75f), style = sf(13f, design = SfDesign.SERIF))
        Row(Modifier.fillMaxWidth().padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Spacer(Modifier.weight(1f))
            for (title in listOf("YOUR TURN", "THEIRS")) {
                Text(title, Modifier.width(76.dp), style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 0.8f).copy(brush = TavernPalette.goldText),
                    textAlign = TextAlign.Center, maxLines = 1)
            }
        }
        for (step in OnDeviceSmartPass.Step.entries) {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(step.title, Modifier.weight(1f), color = TavernPalette.parchment, style = sf(15f, SfWeight.semibold, SfDesign.SERIF), maxLines = 1)
                for (myTurn in listOf(true, false)) {
                    val key = OnDeviceSmartPass.stopKey(step, myTurn)
                    val on = key in stops
                    Box(Modifier.width(76.dp).height(44.dp).clickable {
                        raw = OnDeviceSmartPass.Settings.encode(if (on) stops - key else stops + key)
                    }.semantics {
                        contentDescription = "${step.title}, ${if (myTurn) "your turn" else "opponents\u2019 turns"}"
                        stateDescription = if (on) "Stop" else "Pass"; role = Role.Checkbox
                    }, contentAlignment = Alignment.Center) {
                        Box(Modifier.fillMaxWidth().height(36.dp).padding(1.5.dp)
                            .tavernFill(if (on) TavernMaterial.EMBER else TavernMaterial.LEATHER, CircleShape).tavernCapsuleRim(thin = true),
                            contentAlignment = Alignment.Center) {
                            SfImage(if (on) "hand.raised.fill" else "circle.dotted",
                                if (on) Color(0xFFFFE8A8) else TavernPalette.brass.copy(alpha = 0.6f), 15.dp)
                        }
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(TavernPalette.brass.copy(alpha = 0.35f)))
        }
        TavernButton({ raw = OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops) },
            Modifier.align(Alignment.CenterHorizontally).padding(top = 14.dp).semantics { contentDescription = "phaseStops.reset" },
            kind = TavernButtonKind.SECONDARY, compact = true) { TavernButtonText("Reset Stops") }
    }
}

/**
 * The questions and trigger orders this game remembers ("Don't ask again", "Always first"), with a button to forget each kind.
 * Hidden until something is remembered.
 */
@Composable
fun RememberedChoicesPanel() {
    val answerActions = LocalBoardAnswerActions.current
    if (answerActions.rememberedAnswers == 0 && answerActions.rememberedTriggerOrders == 0) return
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Remembered this game", color = TavernPalette.parchment, style = sf(15f, SfWeight.bold, SfDesign.SERIF))
        Text("XMage answers these for you until you forget them.", color = TavernPalette.parchment.copy(alpha = 0.75f),
            style = sf(12f, design = SfDesign.SERIF).copy(fontStyle = FontStyle.Italic))
        if (answerActions.rememberedAnswers > 0) {
            TavernButton(answerActions.forgetAnswers, Modifier.semantics { contentDescription = "board.menu.forgetAnswers" },
                kind = TavernButtonKind.SECONDARY, compact = true) { TavernButtonText("Ask Again (${answerActions.rememberedAnswers} answered)") }
        }
        if (answerActions.rememberedTriggerOrders > 0) {
            TavernButton(answerActions.forgetTriggerOrder, Modifier.semantics { contentDescription = "board.menu.forgetTriggerOrder" },
                kind = TavernButtonKind.SECONDARY, compact = true) { TavernButtonText("Ask Trigger Order Again") }
        }
    }
}
