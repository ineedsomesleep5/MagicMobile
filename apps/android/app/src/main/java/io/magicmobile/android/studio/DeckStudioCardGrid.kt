package io.magicmobile.android.studio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
fun deckStudioGridColumns(): Int = maxOf(1, (LocalConfiguration.current.screenWidthDp - 40 + 10) / 110)

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
 * One card in the Cards grid. In select mode (`selected` non-null) a tap toggles the selection;
 * otherwise it inspects. A long press shows the large preview, Android's counterpart of the iOS
 * context-menu preview.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioCardGridTile(row: NativeDeckRow, card: CardInfo?, issues: List<DeckStudioPreflight.Issue>, selected: Boolean?,
                           tap: () -> Unit, preview: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview, onClick = tap)
        .semantics {
            contentDescription = (if (selected != null) "" else "Inspect ") + "${row.cardName}, quantity ${row.quantity}"
            if (selected != null) this.selected = selected
        }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box {
            DeckStudioCardImage(row.cardName, card, Modifier.fillMaxWidth())
            if (row.quantity > 1) Text("×${row.quantity}", Modifier.align(Alignment.TopEnd).padding(4.dp).background(DeckStudioPalette.ink.copy(alpha = 0.85f), CircleShape)
                .padding(horizontal = 6.dp, vertical = 2.dp), color = DeckStudioPalette.surfaceElevated, style = StudioText.caption.weight(SfWeight.bold))
            if (selected != null) Box(Modifier.align(Alignment.TopStart).padding(4.dp)
                .background(if (selected) DeckStudioPalette.surfaceElevated else DeckStudioPalette.ink.copy(alpha = 0.35f), CircleShape)) {
                SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) DeckStudioPalette.accent else DeckStudioPalette.surfaceElevated, 20.dp)
            }
            if (selected == true) Box(Modifier.matchParentSize().border(3.dp, DeckStudioPalette.accent, RoundedCornerShape(DeckStudioMetrics.cardRadius)))
        }
        DeckStudioIssueBadges(issues)
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

/** DeckStudioCardPreview: the card at a readable size, in a dialog; tap anywhere to close. */
@Composable
fun DeckStudioCardPreviewDialog(name: String, card: CardInfo?, dismiss: () -> Unit) {
    Dialog(dismiss) {
        Box(Modifier.clickable(remember { MutableInteractionSource() }, null) { dismiss() }.background(DeckStudioPalette.background, RoundedCornerShape(18.dp))
            .padding(8.dp).semantics { contentDescription = "$name preview. Tap to close." }) {
            DeckStudioCardImage(name, card, Modifier.width(300.dp), large = true)
        }
    }
}
