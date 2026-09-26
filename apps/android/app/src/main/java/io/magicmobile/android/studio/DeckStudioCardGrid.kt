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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight

/** The Cards tab's image grid: as many 104-point columns as fit, at least three on a phone. */
@Composable
fun deckStudioGridColumns(): Int = maxOf(3, (LocalConfiguration.current.screenWidthDp - 40) / 104)

/**
 * A whole card image, or a text tile with name, cost and type when artwork is off or not saved
 * (DeckStudioCardGridView.swift). It follows the app's artwork and privacy setting via CardArtwork.
 */
@Composable
fun DeckStudioCardImage(name: String, card: CardInfo?, modifier: Modifier = Modifier) {
    CardArtwork(name, modifier.aspectRatio(63f / 88f).clip(RoundedCornerShape(DeckStudioMetrics.cardRadius))) {
        Column(Modifier.fillMaxSize().background(DeckStudioPalette.surfaceElevated).border(1.dp, DeckStudioPalette.separator, RoundedCornerShape(DeckStudioMetrics.cardRadius))
            .padding(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(name, color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold), maxLines = 3, overflow = TextOverflow.Ellipsis)
            card?.manaCost?.takeIf { it.isNotEmpty() }?.let { NativeDeckManaCost(it) }
            Spacer(Modifier.weight(1f))
            Text(card?.typeLine ?: "Unknown card", color = if (card == null) DeckStudioPalette.warning else DeckStudioPalette.secondaryInk,
                style = StudioText.caption2, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** One grid tile: tap inspects (or selects in Select mode), long-press previews the card large. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioCardGridTile(row: NativeDeckRow, card: CardInfo?, issues: List<DeckStudioPreflight.Kind>, selecting: Boolean, selected: Boolean,
                           tap: () -> Unit, preview: () -> Unit, modifier: Modifier = Modifier) {
    val description = buildString {
        append("${row.cardName}, quantity ${row.quantity}")
        if (issues.isNotEmpty()) append(", " + issues.joinToString(", ") { it.badge })
        if (selecting) append(if (selected) ", selected" else ", not selected")
    }
    Box(modifier.combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview, onClick = tap)
        .semantics { contentDescription = description }) {
        DeckStudioCardImage(row.cardName, card, Modifier.fillMaxWidth().alpha(if (selecting && !selected) 0.6f else 1f))
        if (row.quantity > 1) {
            Text("×${row.quantity}", Modifier.align(Alignment.TopEnd).padding(4.dp).background(DeckStudioPalette.ink.copy(alpha = 0.85f), CircleShape)
                .padding(horizontal = 7.dp, vertical = 2.dp), color = Color.White, style = StudioText.caption.weight(SfWeight.bold))
        }
        if (issues.isNotEmpty()) {
            Box(Modifier.align(Alignment.BottomStart).padding(4.dp).background(DeckStudioPalette.warning, CircleShape).padding(4.dp)) {
                SfImage("exclamationmark.triangle.fill", Color.White, 11.dp)
            }
        }
        if (selecting) {
            Box(Modifier.align(Alignment.TopStart).padding(4.dp).background(if (selected) DeckStudioPalette.ink else Color.White.copy(alpha = 0.9f), CircleShape)
                .border(1.dp, DeckStudioPalette.ink, CircleShape).padding(3.dp)) {
                SfImage(if (selected) "checkmark" else "circle", if (selected) Color.White else Color.Transparent, 12.dp)
            }
        }
    }
}

/** A row of grid tiles; short rows keep their tile width. */
@Composable
fun DeckStudioCardGridRow(rows: List<NativeDeckRow>, columns: Int, tile: @Composable (NativeDeckRow, Modifier) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in rows) tile(row, Modifier.weight(1f))
        repeat(columns - rows.size) { Spacer(Modifier.weight(1f)) }
    }
}

/** The Android long-press preview: a large card image in a dialog; tap anywhere to close. */
@Composable
fun DeckStudioCardPreviewDialog(name: String, card: CardInfo?, dismiss: () -> Unit) {
    Dialog(dismiss) {
        Column(Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, null) { dismiss() }
            .semantics { contentDescription = "$name preview. Tap to close." }, horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            DeckStudioCardImage(name, card, Modifier.widthIn(max = 340.dp).fillMaxWidth())
            Text(name, Modifier.background(DeckStudioPalette.surface, CircleShape).padding(horizontal = 14.dp, vertical = 6.dp),
                color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
