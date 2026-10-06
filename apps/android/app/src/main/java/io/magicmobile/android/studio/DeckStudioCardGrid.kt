package io.magicmobile.android.studio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight

/** The Cards grid's columns: adaptive 100-point tiles with 10-point spacing, as on iOS. */
@Composable
fun deckStudioGridColumns(): Int = maxOf(1, (LocalConfiguration.current.screenWidthDp - 40 + 10) / 95)   // four across on a big phone

/**
 * DeckStudioCardImageTile: a card-shaped image that respects the artwork and privacy preference.
 * With no downloaded art it becomes a text tile (name, cost and type), never a blank box.
 */
@Composable
fun DeckStudioCardImage(name: String, card: CardInfo?, modifier: Modifier = Modifier, large: Boolean = false) {
    val shape = RoundedCornerShape(if (large) 14.dp else DeckStudioMetrics.cardRadius)
    CardArtwork(name, modifier.aspectRatio(63f / 88f).clip(shape).border(1.dp, DeckStudioPalette.separator, shape)) {
        Column(Modifier.fillMaxSize().background(DeckStudioPalette.surfaceElevated).padding(if (large) 16.dp else 8.dp),
            verticalArrangement = Arrangement.spacedBy(if (large) 10.dp else 4.dp)) {
            Text(name, color = DeckStudioPalette.ink, style = if (large) StudioText.title3.weight(SfWeight.bold) else StudioText.caption.weight(SfWeight.semibold),
                maxLines = if (large) 4 else 3, overflow = TextOverflow.Ellipsis)
            card?.manaCost?.takeIf { it.isNotEmpty() }?.let { NativeDeckManaCost(it) }
            Spacer(Modifier.weight(1f))
            Text(card?.typeLine ?: "Unknown card", color = DeckStudioPalette.secondaryInk, style = if (large) StudioText.subheadline else StudioText.caption2,
                maxLines = if (large) 3 else 2, overflow = TextOverflow.Ellipsis)
            if (large) card?.oracleText?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption, maxLines = 10, overflow = TextOverflow.Ellipsis) }
        }
    }
}

/** DeckStudioIssueBadges: inline quick-check badges on a Cards row or grid tile. */
@Composable
fun DeckStudioIssueBadges(issues: List<DeckStudioPreflight.Issue>, modifier: Modifier = Modifier) {
    if (issues.isEmpty()) return
    Row(modifier.clearAndSetSemantics { contentDescription = "Quick check: " + issues.joinToString(", ") { it.badge } },
        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (issue in issues) Text(issue.badge, Modifier.background(DeckStudioPalette.warning.copy(alpha = 0.12f), CircleShape).padding(horizontal = 6.dp, vertical = 2.dp),
            color = DeckStudioPalette.warning, style = StudioText.caption2.weight(SfWeight.semibold), maxLines = 1)
    }
}

/**
 * One card in the Cards grid: its full art, with how many copies the deck holds. While the deck is being
 * edited (`change` non-null) the corners show what a tap does: the left half takes a copy away, the right half
 * adds one (Caleb, 2026-10-05). In select mode (`selected` non-null) a tap toggles the selection; a read-only
 * deck's card opens on a tap. A long press shows the large preview with the card actions, Android's
 * counterpart of the iOS context menu.
 */
@Composable
fun DeckStudioCardGridTile(row: NativeDeckRow, card: CardInfo?, issues: List<DeckStudioPreflight.Issue>, selected: Boolean?,
                           tap: () -> Unit, preview: () -> Unit, modifier: Modifier = Modifier, change: ((Int) -> Unit)? = null) {
    DeckStudioArtTile(row.cardName, row.quantity, card, issues.map { it.badge }, selected, tap, preview, modifier, change,
        addLabel = "Add one ${row.cardName}", removeLabel = "Remove one ${row.cardName}")
}

/**
 * A card as its full art with the copies the deck holds: a deck's own card, or a search result (which may
 * hold none yet: then the whole card adds the first copy). Just the card (Caleb, 2026-10-05): its own text is
 * on it, so nothing is written beneath, and what there is to know (`notes`) sits on it as a small disc.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioArtTile(name: String, quantity: Int, card: CardInfo?, notes: List<String>, selected: Boolean?,
                      tap: () -> Unit, preview: () -> Unit, modifier: Modifier = Modifier, change: ((Int) -> Unit)? = null,
                      addLabel: String = "Add one $name", removeLabel: String = "Remove one $name") {
    val editable = change != null && selected == null
    Column(modifier.then(if (editable) Modifier else Modifier.combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview, onClick = tap)
        .semantics {
            contentDescription = (if (selected != null) "" else "Inspect ") + "$name, quantity $quantity"
            if (selected != null) this.selected = selected
        }), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box {
            DeckStudioCardImage(name, card, Modifier.fillMaxWidth())
            if (quantity > 1 || (editable && quantity > 0)) Text("×$quantity", Modifier.align(Alignment.TopEnd).padding(4.dp).background(DeckStudioPalette.ink.copy(alpha = 0.85f), CircleShape)
                .padding(horizontal = 6.dp, vertical = 2.dp).semantics { contentDescription = "$name, quantity $quantity" },
                color = DeckStudioPalette.surfaceElevated, style = StudioText.caption.weight(SfWeight.bold))
            if (selected != null) Box(Modifier.align(Alignment.TopStart).padding(4.dp)
                .background(if (selected) DeckStudioPalette.surfaceElevated else DeckStudioPalette.ink.copy(alpha = 0.35f), CircleShape)) {
                SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) DeckStudioPalette.accent else DeckStudioPalette.surfaceElevated, 20.dp)
            }
            if (selected == true) Box(Modifier.matchParentSize().border(3.dp, DeckStudioPalette.accent, RoundedCornerShape(DeckStudioMetrics.cardRadius)))
            if (selected == null && notes.isNotEmpty()) Box(Modifier.align(Alignment.TopStart).padding(4.dp).size(22.dp)
                .background(DeckStudioPalette.warning.copy(alpha = 0.92f), CircleShape)
                .semantics { contentDescription = "Quick check: " + notes.joinToString(", ") }, contentAlignment = Alignment.Center) {
                SfImage("exclamationmark.triangle.fill", DeckStudioPalette.surfaceElevated, 11.dp)
            }
            if (editable) {
                // What tapping each side of the card does (nothing to take away from a card the deck does not hold).
                if (quantity > 0) CornerHint("minus", Modifier.align(Alignment.BottomStart))
                CornerHint("plus", Modifier.align(Alignment.BottomEnd))
                // The two halves of the card: the left takes a copy away, the right adds one.
                Row(Modifier.matchParentSize()) {
                    if (quantity > 0) Box(Modifier.weight(1f).fillMaxHeight().combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview) { change?.invoke(-1) }
                        .semantics { contentDescription = removeLabel; role = Role.Button })
                    Box(Modifier.weight(1f).fillMaxHeight().combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview) { change?.invoke(1) }
                        .semantics { contentDescription = addLabel; role = Role.Button })
                }
            }
        }
    }
}

/** A small inked disc in a bottom corner of a card: what tapping that side does. */
@Composable
private fun CornerHint(symbol: String, modifier: Modifier) {
    Box(modifier.padding(5.dp).size(22.dp).background(DeckStudioPalette.ink.copy(alpha = 0.78f), CircleShape)
        .border(0.8.dp, DeckStudioPalette.surfaceElevated.copy(alpha = 0.35f), CircleShape), contentAlignment = Alignment.Center) {
        SfImage(symbol, DeckStudioPalette.surfaceElevated, 10.dp)
    }
}

/** A row of grid tiles; a short last row keeps the tile width. */
@Composable
fun DeckStudioCardGridRow(rows: List<NativeDeckRow>, columns: Int, tile: @Composable (NativeDeckRow, Modifier) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        for (row in rows) tile(row, Modifier.weight(1f))
        repeat(columns - rows.size) { Spacer(Modifier.weight(1f)) }
    }
}

/** One long-press action under the preview; `choices` makes it expand (Move to…). */
data class DeckStudioCardAction(val title: String, val icon: String?, val destructive: Boolean = false,
                                val choices: List<Pair<String, () -> Unit>> = emptyList(), val action: () -> Unit = {})

/**
 * DeckStudioCardPreview: the card at a readable size, in a dialog, with the same actions as the iOS
 * long-press menu. Tap the card to close; an action closes the dialog and runs.
 */
@Composable
fun DeckStudioCardPreviewDialog(name: String, card: CardInfo?, actions: List<DeckStudioCardAction> = emptyList(), dismiss: () -> Unit) {
    Dialog(dismiss) {
        var expanded by remember { mutableStateOf<String?>(null) }
        Column(Modifier.background(DeckStudioPalette.background, RoundedCornerShape(18.dp)).padding(8.dp).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.clickable(remember { MutableInteractionSource() }, null) { dismiss() }.semantics { contentDescription = "$name preview. Tap to close." }) {
                DeckStudioCardImage(name, card, Modifier.width(if (actions.isEmpty()) 300.dp else 240.dp), large = true)
            }
            if (actions.isNotEmpty()) Column(Modifier.width(300.dp).background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(13.dp))) {
                actions.forEachIndexed { index, entry ->
                    if (index > 0) Box(Modifier.fillMaxWidth().height(0.5.dp).background(DeckStudioPalette.separator))
                    val tint = if (entry.destructive) DeckStudioPalette.danger else DeckStudioPalette.ink
                    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) {
                        if (entry.choices.isEmpty()) { dismiss(); entry.action() } else expanded = if (expanded == entry.title) null else entry.title
                    }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(entry.title, Modifier.weight(1f), color = tint, style = StudioText.body)
                        val icon = entry.icon ?: if (entry.choices.isEmpty()) null else if (expanded == entry.title) "chevron.up" else "chevron.down"
                        icon?.let { SfImage(it, tint, if (entry.icon != null) 17.dp else 13.dp) }
                    }
                    if (expanded == entry.title) for ((title, run) in entry.choices) Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                        .clickable(role = Role.Button) { dismiss(); run() }.padding(start = 32.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(title, color = DeckStudioPalette.ink, style = StudioText.body)
                    }
                }
            }
        }
    }
}
