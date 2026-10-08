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
