package io.magicmobile.android.ranked

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import io.magicmobile.android.studio.DeckStudioRecordedGame
import io.magicmobile.android.studio.DeckStudioServices
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernToggle
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The detailed records behind the profile's recent games (ProfileHistory.swift): Deck Studio's saved game history, found by the
 * engine's match id. A game without one still shows on the profile; it just has no dashboard to open.
 */
class ProfileGameDetails {
    var byMatch by mutableStateOf<Map<String, DeckStudioRecordedGame>>(emptyMap()); private set
    var notice by mutableStateOf<String?>(null); private set

    suspend fun refresh() {
        try {
            val games = withContext(Dispatchers.IO) { DeckStudioServices.playtests.summaries() }
            byMatch = games.associateBy { it.matchID }
            notice = DeckStudioServices.playtests.failure
        } catch (failure: Exception) {
            notice = "Saved game history could not be read. It is kept; clear it only to discard it on purpose."
        }
    }

    suspend fun clear() {
        try {
            withContext(Dispatchers.IO) { DeckStudioServices.playtests.clear() }
            byMatch = emptyMap(); notice = null
        } catch (failure: Exception) { notice = "Could not remove the saved history. Existing data is kept." }
    }
}

@Composable
fun rememberProfileGameDetails(): ProfileGameDetails {
    val details = remember { ProfileGameDetails() }
    LaunchedEffect(Unit) { details.refresh() }
    return details
}

/**
 * Which games keep a detailed record, and what is kept (ProfileHistorySettings in ProfileHistory.swift). These are the choices Deck
 * Studio's Playtest chapter used to hold; they are local to this phone and apply to the next games against the AI.
 */
@Composable
fun ProfileHistorySettings(details: ProfileGameDetails) {
    val store = DeckStudioServices.playtests
    val scope = rememberCoroutineScope()
    var enabled by remember { mutableStateOf(store.admission().enabled) }
    var detailed by remember { mutableStateOf(store.admission().detailedEnabled) }
    var open by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    val status = if (enabled) (if (detailed) "Detail on" else "Summaries on") else "Saving off"
    val parchment = TavernPalette.parchment
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { open = !open }
            .semantics(mergeDescendants = true) { role = Role.Button; stateDescription = if (open) "Expanded" else "Collapsed" }.testTag("deckHistory.settings"),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("shield.fill", TavernPalette.brass, 16.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text("History settings & privacy", color = parchment, style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
                Text(status, Modifier.alpha(0.7f), color = parchment, style = sf(12f, SfWeight.semibold, SfDesign.SERIF))
            }
            SfImage("chevron.down", TavernPalette.brass, 13.dp, Modifier.rotate(if (open) 180f else 0f))
        }
        details.notice?.let { Text(it, color = ProfilePalette.win, style = sf(12f, SfWeight.semibold, SfDesign.SERIF)) }
        if (open) Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TavernToggle("Save AI game summaries", enabled, { value ->
                enabled = value; if (!value) detailed = false; store.setEnabled(value)
            }, Modifier.testTag("deckHistory.summaries"), color = parchment)
            TavernToggle("Save detailed public game history", detailed, { value -> detailed = value; store.setDetailedEnabled(value) },
                Modifier.testTag("deckHistory.detail"), enabled = enabled, color = parchment)
            Text("Both choices are local and apply to future AI matches. Detail saves sampled public life totals, battlefield counts, visible cards and recognized public notices. It never saves hands, opponent decks or raw game messages. Turning detail off keeps saved history until you delete it.",
                Modifier.alpha(0.75f), color = parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TavernPlaqueButton("Refresh history", { scope.launch { details.refresh() } }, Modifier.testTag("deckHistory.refresh"), kind = TavernButtonKind.SECONDARY)
                TavernPlaqueButton("Clear all history", { confirmClear = true }, Modifier.testTag("deckHistory.clear"), kind = TavernButtonKind.DANGER)
            }
            Text("Up to 100 recent sessions within 8 MB; oldest sessions are removed first.", Modifier.alpha(0.6f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF))
        }
    }
    if (confirmClear) TavernConfirmationDialog("Delete all local game history?", "Decks are not deleted. Games already in progress will not restore the cleared history.",
        listOf(TavernDialogAction("Delete history", destructive = true) { scope.launch { details.clear() } })) { confirmClear = false }
}
