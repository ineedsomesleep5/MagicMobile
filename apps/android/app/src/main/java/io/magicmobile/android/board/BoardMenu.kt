package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** Entries of an iOS `Menu { … }`. */
sealed class MenuEntry {
    data class Item(val title: String, val icon: String? = null, val enabled: Boolean = true, val destructive: Boolean = false,
                    val checked: Boolean = false, val action: () -> Unit) : MenuEntry()
    data class Label(val title: String) : MenuEntry()
    data class Section(val title: String) : MenuEntry()
    object Divider : MenuEntry()
}

private val menuBackground = rgb(0.17, 0.17, 0.18).copy(alpha = 0.98f)
private val menuSeparator = Color.White.copy(alpha = 0.12f)

/** An iOS-style pull-down menu: a dark rounded panel of 44-point rows anchored to its label. */
@Composable
fun BoardMenu(entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        PressableBox({ open = true }, enabled = enabled) { label() }
        MaterialTheme(colorScheme = darkColorScheme(surface = menuBackground, surfaceContainer = menuBackground)) {
            DropdownMenu(open, { open = false }, Modifier.background(menuBackground).widthIn(min = 220.dp, max = 300.dp), offset = DpOffset(0.dp, 4.dp),
                shape = RoundedCornerShape(13.dp), containerColor = menuBackground) {
                MenuEntries(if (open) entries() else emptyList()) { open = false }
            }
        }
    }
}

@Composable
private fun MenuEntries(entries: List<MenuEntry>, dismiss: () -> Unit) {
    entries.forEachIndexed { index, entry ->
        when (entry) {
            is MenuEntry.Item -> Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                .clickable(enabled = entry.enabled) { dismiss(); entry.action() }
                .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (entry.checked) SfImage("checkmark", Color.White, 14.dp, Modifier.padding(end = 8.dp))
                Text(entry.title, Modifier.weight(1f), color = when {
                    !entry.enabled -> Color.White.copy(alpha = 0.3f); entry.destructive -> rgb(1.0, 0.27, 0.23); else -> Color.White
                }, style = sf(17f))
                entry.icon?.let { SfImage(it, if (entry.enabled) Color.White else Color.White.copy(alpha = 0.3f), 17.dp) }
            }
            is MenuEntry.Label -> Text(entry.title, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                color = Color.White.copy(alpha = 0.9f), style = sf(17f))
            is MenuEntry.Section -> {
                if (index > 0) Box(Modifier.fillMaxWidth().height(8.dp).background(Color.Black.copy(alpha = 0.25f)))
                Text(entry.title, Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp), color = Color.White.copy(alpha = 0.55f), style = sf(13f))
            }
            MenuEntry.Divider -> Box(Modifier.fillMaxWidth().height(8.dp).background(Color.Black.copy(alpha = 0.25f)))
        }
        if (entry is MenuEntry.Item && index < entries.lastIndex && entries[index + 1] is MenuEntry.Item) {
            HorizontalDivider(thickness = 0.5.dp, color = menuSeparator)
        }
    }
}

/** An iOS `confirmationDialog`: an action sheet with a title, message, actions and Cancel. */
data class ConfirmationAction(val title: String, val destructive: Boolean = false, val action: () -> Unit)

@Composable
fun ConfirmationDialog(title: String, message: String?, actions: List<ConfirmationAction>, cancelTitle: String = "Cancel", dismiss: () -> Unit) {
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().clickable(onClick = dismiss, indication = null,
            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() })
            .padding(horizontal = 8.dp).navigationBarsPadding().padding(bottom = 8.dp), verticalArrangement = Arrangement.Bottom) {
            Column(Modifier.fillMaxWidth().background(menuBackground, RoundedCornerShape(14.dp))) {
                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(title, color = Color.White.copy(alpha = 0.6f), style = sf(13f, SfWeight.semibold))
                    message?.let { Text(it, color = Color.White.copy(alpha = 0.6f), style = sf(13f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
                }
                for (action in actions) {
                    HorizontalDivider(thickness = 0.5.dp, color = menuSeparator)
                    Box(Modifier.fillMaxWidth().heightIn(min = 57.dp).clickable { dismiss(); action.action() }, contentAlignment = Alignment.Center) {
                        Text(action.title, color = if (action.destructive) rgb(1.0, 0.27, 0.23) else rgb(0.04, 0.52, 1.0), style = sf(20f))
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Box(Modifier.fillMaxWidth().heightIn(min = 57.dp).background(menuBackground, RoundedCornerShape(14.dp)).clickable(onClick = dismiss),
                contentAlignment = Alignment.Center) {
                Text(cancelTitle, color = rgb(0.04, 0.52, 1.0), style = sf(20f, SfWeight.semibold))
            }
        }
    }
}

/** An iOS `.sheet` with medium/large detents: a dark bottom sheet with a grabber. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardSheet(onDismiss: () -> Unit, background: Color = rgb(0.11, 0.11, 0.12), skipPartiallyExpanded: Boolean = false,
               sound: Boolean = true, content: @Composable () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded)
    androidx.compose.runtime.LaunchedEffect(Unit) { if (sound) GameAudio.play(GameSound.UI_OPEN) }
    ModalBottomSheet({ if (sound) GameAudio.play(GameSound.UI_CLOSE); onDismiss() }, sheetState = state, containerColor = background,
        contentColor = MagicPalette.parchment, shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
        dragHandle = { Box(Modifier.padding(vertical = 6.dp).widthIn(36.dp, 36.dp).height(5.dp).background(Color.White.copy(alpha = 0.3f), RoundedCornerShape(3.dp))) }) {
        content()
    }
}

/** The dark iOS-style circle outline used by several controls. */
fun Modifier.iosCircleOutline(color: Color = MagicPalette.parchment.copy(alpha = 0.25f)): Modifier =
    this.border(1.dp, color, androidx.compose.foundation.shape.CircleShape)
