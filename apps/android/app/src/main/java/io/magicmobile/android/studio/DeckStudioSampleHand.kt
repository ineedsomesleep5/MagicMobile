package io.magicmobile.android.studio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.SfWeight
import kotlin.random.Random

/**
 * DeckStudioSampleHandView.swift: a goldfish opening hand in the Playtest tab. Draw 7 from the main
 * deck (commanders and other boards stay out), London mulligan, draw the next card and count turns.
 * Nothing here plays a game or changes the deck.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioSampleHandPanel(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, preview: (String) -> Unit) {
    val names = remember(draft) { DeckStudioSampleHand.library(draft) }
    var hand by remember(names) { mutableStateOf<DeckStudioSampleHand?>(null) }
    StudioPanel(spacing = 12.dp) {
        Text("Sample hand", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
        Text("Draw 7 from the main deck. Commanders stay out of the library.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        val current = hand
        when {
            names.isEmpty() -> Text("Add main-deck cards to draw a sample hand.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            current == null -> StudioButton("Draw 7", { hand = DeckStudioSampleHand.start(names, Random.Default) },
                Modifier.testTag("deckStudio.sampleHand.draw"), icon = "dice")
            else -> {
                Text("Turn ${current.turn} · ${CardCountText.label(current.hand.size)} in hand · ${CardCountText.label(current.library.size)} in library",
                    color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                if (current.mulligans > 0) Text("Mulligans: ${current.mulligans}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                if (current.toBottom > 0) Text("Tap ${CardCountText.label(current.toBottom)} to put on the bottom", color = DeckStudioPalette.accent,
                    style = StudioText.caption.weight(SfWeight.semibold))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (card in current.hand) {
                        val bottoming = current.toBottom > 0
                        Box(Modifier.width(92.dp).combinedClickable(remember { MutableInteractionSource() }, null,
                            onLongClick = { preview(card.name) }, onClick = { if (bottoming) hand = current.putOnBottom(card.id) else preview(card.name) })
                            .semantics { contentDescription = if (bottoming) "Put ${card.name} on the bottom" else "Preview ${card.name}" }) {
                            DeckStudioCardImage(card.name, metadata?.card(card.name))
                        }
                    }
                }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StudioButton("New hand", { hand = DeckStudioSampleHand.start(names, Random.Default) }, primary = false, compactText = true)
                    StudioButton("Mulligan", { hand = current.mulligan(Random.Default) }, primary = false, enabled = current.canMulligan, compactText = true)
                    StudioButton("Draw", { hand = current.draw() }, primary = false, enabled = current.canDraw, compactText = true)
                    StudioButton("Next turn", { hand = current.nextTurn() }, enabled = current.canDraw, compactText = true)
                }
            }
        }
    }
}
