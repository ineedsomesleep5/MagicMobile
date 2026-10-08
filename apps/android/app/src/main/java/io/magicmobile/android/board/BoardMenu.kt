package io.magicmobile.android.board

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import io.magicmobile.android.studio.Binder
import io.magicmobile.android.studio.BinderCornerStyle
import io.magicmobile.android.studio.DeckStudioPalette
import io.magicmobile.android.studio.binderCorners
import io.magicmobile.android.studio.binderLeather
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.studio.grimoirePaper
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.LocalTavernBoard
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuDivider
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuHeading
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** Entries of an iOS `Menu { … }`. */
sealed class MenuEntry {
    data class Item(val title: String, val icon: String? = null, val enabled: Boolean = true, val destructive: Boolean = false,
                    val checked: Boolean = false, val mana: String? = null, val action: () -> Unit) : MenuEntry()
    data class Label(val title: String) : MenuEntry()
    data class Section(val title: String) : MenuEntry()
    object Divider : MenuEntry()
}

private val menuBackground = rgb(0.17, 0.17, 0.18).copy(alpha = 0.98f)
private val menuSeparator = Color.White.copy(alpha = 0.12f)
/** The light appearance Deck Studio uses (`.preferredColorScheme(.light)`). */
private val lightMenuBackground = rgb(0.97, 0.97, 0.97).copy(alpha = 0.99f)
private val lightMenuSeparator = Color.Black.copy(alpha = 0.12f)

/**
 * An iOS-style pull-down menu: a dark rounded panel of 44-point rows anchored to its label. On the Walnut
 * Tavern table it is the tavern's leather pop-over instead (TavernMenu), so the board shows no system UI.
 */
@Composable
fun BoardMenu(entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true, light: Boolean = false,
              edge: TavernMenuEdge = TavernMenuEdge.ABOVE, label: @Composable () -> Unit) {
    if (LocalTavernBoard.current && !light) {
        TavernMenu(modifier, edge, enabled, label = { label() }) { TavernMenuEntries(entries()) }
        return
    }
    var open by remember { mutableStateOf(false) }
    if (light) {
        // Deck Studio: the binder's own menu, parchment in a brass edge (GrimoireBinderMenu.swift on iOS).
        Box(modifier) {
            PressableBox({ open = true }, enabled = enabled) { label() }
            BinderDropdown(open, { open = false }) { BinderMenuEntries(if (open) entries() else emptyList()) { open = false } }
        }
        return
    }
    val background = menuBackground
    Box(modifier) {
        PressableBox({ open = true }, enabled = enabled) { label() }
        MaterialTheme(colorScheme = darkColorScheme(surface = background, surfaceContainer = background)) {
            DropdownMenu(open, { open = false }, Modifier.background(background).widthIn(min = 220.dp, max = 300.dp), offset = DpOffset(0.dp, 4.dp),
                shape = RoundedCornerShape(13.dp), containerColor = background) {
                MenuEntries(if (open) entries() else emptyList(), light) { open = false }
            }
        }
    }
}

@Composable
private fun MenuEntries(entries: List<MenuEntry>, light: Boolean, dismiss: () -> Unit) {
    val ink = if (light) Color.Black else Color.White
    entries.forEachIndexed { index, entry ->
        when (entry) {
            is MenuEntry.Item -> Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                .clickable(enabled = entry.enabled) { dismiss(); entry.action() }
                .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (entry.checked) SfImage("checkmark", ink, 14.dp, Modifier.padding(end = 8.dp))
                Text(entry.title, Modifier.weight(1f), color = when {
                    !entry.enabled -> ink.copy(alpha = 0.3f); entry.destructive -> rgb(1.0, 0.27, 0.23); else -> ink
                }, style = sf(17f))
                entry.icon?.let { SfImage(it, when { !entry.enabled -> ink.copy(alpha = 0.3f); entry.destructive -> rgb(1.0, 0.27, 0.23); else -> ink }, 17.dp) }
            }
            is MenuEntry.Label -> Text(entry.title, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                color = ink.copy(alpha = 0.9f), style = sf(17f))
            is MenuEntry.Section -> {
                if (index > 0) Box(Modifier.fillMaxWidth().height(8.dp).background(Color.Black.copy(alpha = if (light) 0.06f else 0.25f)))
                Text(entry.title, Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp), color = ink.copy(alpha = 0.55f), style = sf(13f))
            }
            MenuEntry.Divider -> Box(Modifier.fillMaxWidth().height(8.dp).background(Color.Black.copy(alpha = if (light) 0.06f else 0.25f)))
        }
        if (entry is MenuEntry.Item && index < entries.lastIndex && entries[index + 1] is MenuEntry.Item) {
            HorizontalDivider(thickness = 0.5.dp, color = if (light) lightMenuSeparator else menuSeparator)
        }
    }
}

/**
 * The binder's drop-down (Caleb, 2026-10-06: no Liquid Glass or system menus anywhere): parchment in a brass edge,
 * anchored to its label, with the binder's rows inside.
 */
@Composable
fun BinderDropdown(expanded: Boolean, dismiss: () -> Unit, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(11.dp)
    MaterialTheme(colorScheme = androidx.compose.material3.lightColorScheme(surface = Color.Transparent, surfaceContainer = Color.Transparent)) {
        DropdownMenu(expanded, dismiss, Modifier.widthIn(min = 240.dp, max = 320.dp).grimoirePaper(DeckStudioPalette.surface, 0.2f, shape),
            offset = DpOffset(0.dp, 6.dp), shape = shape, containerColor = Color.Transparent, tonalElevation = 0.dp, shadowElevation = 10.dp,
            border = androidx.compose.foundation.BorderStroke(1.6.dp, Binder.brass), content = content)
    }
}

/** Menu entries as the binder's rows: an engraved symbol (or a mana symbol), the title in the book's hand, a check when chosen. */
@Composable
fun BinderMenuEntries(entries: List<MenuEntry>, dismiss: () -> Unit) {
    entries.forEachIndexed { index, entry ->
        when (entry) {
            is MenuEntry.Item -> {
                val ink = when { entry.destructive -> DeckStudioPalette.danger; else -> DeckStudioPalette.ink }
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (entry.enabled) 1f else 0.4f)
                    .clickable(enabled = entry.enabled) { dismiss(); entry.action() }
                    .semantics(mergeDescendants = true) { if (entry.checked) selected = true }
                    .padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
                        when {
                            entry.mana != null -> ManaSymbolView(entry.mana, 20.dp)
                            entry.icon != null -> SfImage(entry.icon, if (entry.destructive) DeckStudioPalette.danger else Binder.brassDeep, 15.dp)
                        }
                    }
                    Text(entry.title, Modifier.weight(1f), color = ink,
                        style = sf(16f, if (entry.checked) SfWeight.bold else SfWeight.regular, io.magicmobile.android.ui.SfDesign.SERIF))
                    if (entry.checked) SfImage("checkmark", DeckStudioPalette.accent, 13.dp)
                }
            }
            is MenuEntry.Label -> Text(entry.title, Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp), color = DeckStudioPalette.secondaryInk,
                style = sf(13f, SfWeight.regular, io.magicmobile.android.ui.SfDesign.SERIF))
            is MenuEntry.Section -> {
                if (index > 0) BinderMenuRule()
                Text(entry.title.uppercase(), Modifier.padding(start = 14.dp, top = 8.dp, bottom = 2.dp).semantics { heading() }, color = DeckStudioPalette.accent,
                    style = sf(11f, SfWeight.heavy, io.magicmobile.android.ui.SfDesign.SERIF, tracking = 1f))
            }
            MenuEntry.Divider -> BinderMenuRule()
        }
    }
}

@Composable
private fun BinderMenuRule() {
    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).height(0.8.dp).background(DeckStudioPalette.ink.copy(alpha = 0.15f)))
}

/** BoardMenu entries as tavern rows: parchment strips, headings in gold and brass rules. */
@Composable
private fun TavernMenuEntries(entries: List<MenuEntry>) {
    for (entry in entries) when (entry) {
        is MenuEntry.Item -> TavernMenuItem(entry.title, entry.action, systemImage = if (entry.checked) "checkmark" else entry.icon,
            destructive = entry.destructive, enabled = entry.enabled)
        is MenuEntry.Label -> Text(entry.title, Modifier.padding(horizontal = 4.dp, vertical = 2.dp), color = TavernPalette.parchment,
            style = sf(14f, SfWeight.semibold, io.magicmobile.android.ui.SfDesign.SERIF))
        is MenuEntry.Section -> TavernMenuHeading(entry.title)
        MenuEntry.Divider -> TavernMenuDivider()
    }
}

/** An iOS `confirmationDialog`: an action sheet with a title, message, actions and Cancel. */
data class ConfirmationAction(val title: String, val destructive: Boolean = false, val action: () -> Unit)

/** The system-style action sheet, or on the tavern table the tavern's leather dialog (tavernConfirmation). */
@Composable
fun ConfirmationDialog(title: String, message: String?, actions: List<ConfirmationAction>, cancelTitle: String = "Cancel", light: Boolean = false,
                       dismiss: () -> Unit) {
    if (LocalTavernBoard.current && !light) {
        TavernConfirmationDialog(title, message, actions.map { TavernDialogAction(it.title, it.destructive, it.action) }, cancelTitle, dismiss)
        return
    }
    if (light) {
        BinderConfirmationDialog(title, message, actions, cancelTitle, dismiss)
        return
    }
    val menuBackground = if (light) Color.White.copy(alpha = 0.97f) else menuBackground
    val menuSeparator = if (light) lightMenuSeparator else menuSeparator
    val caption = if (light) Color.Black.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.6f)
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().clickable(onClick = dismiss, indication = null,
            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() })
            .padding(horizontal = 8.dp).navigationBarsPadding().padding(bottom = 8.dp), verticalArrangement = Arrangement.Bottom) {
            Column(Modifier.fillMaxWidth().background(menuBackground, RoundedCornerShape(14.dp))) {
                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(title, color = caption, style = sf(13f, SfWeight.semibold))
                    message?.let { Text(it, color = caption, style = sf(13f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
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

/**
 * A Deck Studio confirmation on a parchment card in a brass edge (binderConfirm on iOS): brass for the main choice,
 * oxblood leather for a destructive one, a quiet Cancel.
 */
@Composable
private fun BinderConfirmationDialog(title: String, message: String?, actions: List<ConfirmationAction>, cancelTitle: String, dismiss: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().clickable(onClick = dismiss, indication = null,
            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }), contentAlignment = Alignment.Center) {
            Column(Modifier.widthIn(max = 380.dp).padding(horizontal = 20.dp).fillMaxWidth()
                .grimoirePaper(DeckStudioPalette.surface, 0.2f, shape).border(2.dp, Binder.brass, shape).binderCorners(18.dp, BinderCornerStyle.LEAF)
                .clickable(enabled = false) {}.padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(title, Modifier.semantics { heading() }, color = DeckStudioPalette.ink,
                    style = sf(19f, SfWeight.bold, io.magicmobile.android.ui.SfDesign.SERIF), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                message?.let {
                    Text(it, color = DeckStudioPalette.secondaryInk, style = sf(14f, SfWeight.regular, io.magicmobile.android.ui.SfDesign.SERIF),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
                io.magicmobile.android.studio.GrimoireRule()
                for (action in actions) BinderDialogButton(action.title, if (action.destructive) 1 else 0) { dismiss(); action.action() }
                BinderDialogButton(cancelTitle, 2, dismiss)
            }
        }
    }
}

/** kind: 0 main (brass), 1 destructive (oxblood leather), 2 cancel (quiet). */
@Composable
private fun BinderDialogButton(title: String, kind: Int, onClick: () -> Unit) {
    val shape = RoundedCornerShape(9.dp)
    val base = Modifier.fillMaxWidth().heightIn(min = 44.dp)
    val fill = when (kind) {
        0 -> base.background(Binder.brass, shape).border(1.dp, Binder.brassDeep.copy(alpha = 0.7f), shape)
        1 -> base.binderLeather(Binder.oxblood, 0.7f, shape).border(1.dp, Binder.brassDeep.copy(alpha = 0.7f), shape)
        else -> base.background(DeckStudioPalette.ink.copy(alpha = 0.06f), shape).border(1.dp, DeckStudioPalette.ink.copy(alpha = 0.2f), shape)
    }
    Box(fill.clip(shape).clickable(role = androidx.compose.ui.semantics.Role.Button) { onClick() }, contentAlignment = Alignment.Center) {
        Text(title, color = if (kind == 1) io.magicmobile.android.ui.TavernPalette.parchment else Binder.engraved,
            style = sf(16f, SfWeight.heavy, io.magicmobile.android.ui.SfDesign.SERIF), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
    }
}

/**
 * An iOS 26 `.sheet` with medium/large detents: a rounded card inset from the screen edges,
 * with a grabber, over a dimmed board.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardSheet(onDismiss: () -> Unit, background: Color = rgb(0.11, 0.11, 0.12), skipPartiallyExpanded: Boolean = false,
               // Every sheet wears the tavern (Caleb, 2026-10-03), from the menu as much as from the board, except a
               // Deck Studio sheet, which is a loose leaf of the spell book's paper (`paper`; ink text reads on it).
               sound: Boolean = true, tavern: Boolean = true, paper: Boolean = false, content: @Composable () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded)
    androidx.compose.runtime.LaunchedEffect(Unit) { if (sound) GameAudio.play(GameSound.UI_OPEN) }
    ModalBottomSheet({ if (sound) GameAudio.play(GameSound.UI_CLOSE); onDismiss() }, sheetState = state, containerColor = Color.Transparent,
        contentColor = MagicPalette.parchment, shape = RoundedCornerShape(0.dp), dragHandle = null, tonalElevation = 0.dp,
        scrimColor = Color.Black.copy(alpha = 0.32f), contentWindowInsets = { WindowInsets(0) }) {
        val shape = RoundedCornerShape(36.dp)
        // A sheet opened from the tavern board: leather backing under a brass rule, and the tavern kit inside (`.tavernSheet`).
        val backing = if (paper) Modifier.grimoirePaper(shape = shape).border(0.8.dp, io.magicmobile.android.studio.DeckStudioPalette.ink.copy(alpha = 0.25f), shape)
        else if (tavern) Modifier.tavernFill(TavernMaterial.LEATHER, shape,
            overlayBrush = androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.35f))))
            .border(1.dp, TavernPalette.brass.copy(alpha = 0.55f), shape)
        else Modifier.background(background, shape).border(0.5.dp, Color.White.copy(alpha = 0.12f), shape)
        Column(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp).navigationBarsPadding().padding(bottom = 8.dp)
            .clip(shape).then(backing)) {
            Box(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 2.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.widthIn(36.dp, 36.dp).height(5.dp).background(if (paper) io.magicmobile.android.studio.DeckStudioPalette.ink.copy(alpha = 0.35f)
                    else if (tavern) TavernPalette.brass.copy(alpha = 0.6f) else Color.White.copy(alpha = 0.3f),
                    RoundedCornerShape(3.dp)))
            }
            androidx.compose.runtime.CompositionLocalProvider(LocalTavernBoard provides (tavern && !paper)) { content() }
        }
    }
}

/** The dark iOS-style circle outline used by several controls. */
fun Modifier.iosCircleOutline(color: Color = MagicPalette.parchment.copy(alpha = 0.25f)): Modifier =
    this.border(1.dp, color, androidx.compose.foundation.shape.CircleShape)
