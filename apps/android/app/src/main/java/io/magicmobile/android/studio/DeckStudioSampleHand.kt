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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import kotlin.random.Random

/**
 * DeckStudioSampleHandView.swift: goldfish a sample hand from the main deck. Draw seven, London
 * mulligan, then draw a card per turn. Commanders stay out of the library. Nothing here plays a game
 * or changes the deck.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioSampleHandPanel(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, inspect: (String) -> Unit, preview: (String) -> Unit) {
    val names = remember(draft) { DeckStudioSampleHand.libraryNames(draft) }
    var hand by remember(names) { mutableStateOf<DeckStudioSampleHand?>(null) }
    fun deal() { hand = DeckStudioSampleHand.of(names).dealt(Random.Default) }
    StudioPanel(spacing = 12.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("hand.raised", DeckStudioPalette.ink, 20.dp)
            Text("Sample hand", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
        }
        Text("Draw seven from your main deck. Commanders stay in the command zone, and sideboard and maybeboard cards stay out.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        val current = hand
        when {
            names.isEmpty() -> Text("Add main-deck cards to draw a sample hand.", color = DeckStudioPalette.ink, style = StudioText.subheadline)
            current == null -> StudioButton("Draw 7", ::deal, Modifier.testTag("deckStudio.sampleHand.draw7"), icon = "hand.raised")
            else -> {
                val status = if (current.toBottom > 0) "Put ${CardCountText.label(current.toBottom)} on the bottom"
                else "Turn ${current.turn}" + if (current.mulligans == 0) "" else " · ${current.mulligans} ${if (current.mulligans == 1) "mulligan" else "mulligans"}"
                Text(status, Modifier.testTag("deckStudio.sampleHand.status"), color = if (current.toBottom > 0) DeckStudioPalette.accent else DeckStudioPalette.ink,
                    style = StudioText.subheadline.weight(SfWeight.semibold))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (card in current.hand) {
                        val bottoming = current.toBottom > 0
                        Box(Modifier.width(96.dp).combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = { preview(card.name) },
                            onClick = { if (bottoming) hand = current.puttingOnBottom(card.id) else inspect(card.name) })
                            .semantics { contentDescription = card.name + if (bottoming) ". Puts this card on the bottom of your library" else ". Shows the card" }) {
                            DeckStudioCardImage(card.name, metadata?.card(card.name))
                        }
                    }
                }
                Text("${CardCountText.label(current.hand.size)} in hand · ${CardCountText.label(current.library.size)} in library",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StudioButton("New hand", ::deal, primary = false, compactText = true)
                    StudioButton("Mulligan", { hand = current.mulliganed(Random.Default) }, primary = false, enabled = current.canMulligan, compactText = true)
                    StudioButton("Draw", { hand = current.drawn() }, Modifier.testTag("deckStudio.sampleHand.drawCard"), enabled = current.canDraw, compactText = true)
                }
            }
        }
    }
}
