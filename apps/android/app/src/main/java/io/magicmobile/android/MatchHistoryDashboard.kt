package io.magicmobile.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date

/**
 * Drop-in replacement for the temporary Settings summary/12-row preview/actions:
 * item { MatchHistoryDashboard(state.playtests, model::clearPlaytests) }
 * The browse sheet owns the only history scroll; Settings remains a single LazyColumn.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun MatchHistoryDashboard(games:List<RecordedPlaytest>,onClear:()->Unit) {
    var browsing by remember { mutableStateOf(false) }
    val completed=games.filter { it.end=="completed" }
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Game history",style=MaterialTheme.typography.titleMedium)
            Text("${games.size} retained sessions · ${completed.size} completed · ${completed.count { it.won==true }} confirmed wins")
            Text("${completed.count { it.won==null }} completed without a known result · ${games.count { it.end!="completed" }} unfinished",
                style=MaterialTheme.typography.bodySmall)
            Text("Local AI summaries only. Results and turn/commander metrics count completed games; interruptions are not losses.",
                style=MaterialTheme.typography.bodySmall)
            TextButton(onClick={browsing=true},enabled=games.isNotEmpty()) { Text("Browse all ${games.size} sessions") }
            PlaytestHistoryActions(onClear)
        }
    }
    if(browsing) {
        var filter by remember { mutableStateOf(HistoryFilter.ALL) }
        val visible=remember(games,filter) { games.filter(filter::includes).sortedByDescending { it.startedAt } }
        ModalBottomSheet(onDismissRequest={browsing=false}) {
            Column(Modifier.fillMaxHeight(0.82f)) {
                Text("Match history",style=MaterialTheme.typography.titleLarge,modifier=Modifier.padding(horizontal=20.dp,vertical=8.dp))
                Text("All retained decks, including older records without exact-deck identity.",
                    style=MaterialTheme.typography.bodySmall,modifier=Modifier.padding(horizontal=20.dp))
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal=16.dp),
                    horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    HistoryFilter.entries.forEach { choice ->
                        FilterChip(selected=filter==choice,onClick={filter=choice},label={Text(choice.label)})
                    }
                }
                if(visible.isEmpty()) Text("No sessions match this result filter.",modifier=Modifier.padding(20.dp))
                LazyColumn(contentPadding=PaddingValues(start=16.dp,end=16.dp,bottom=28.dp),
                    verticalArrangement=Arrangement.spacedBy(10.dp)) {
                    items(visible,key={it.id}) { game -> HistoryMatchRow(game) }
                }
            }
        }
    }
}

private enum class HistoryFilter(val label:String) {
    ALL("All"), COMPLETED("Completed"), WINS("Wins"), NOT_WON("Not won"), UNFINISHED("Unfinished");
    fun includes(game:RecordedPlaytest):Boolean=when(this) {
        ALL -> true
        COMPLETED -> game.end=="completed"
        WINS -> game.end=="completed"&&game.won==true
        NOT_WON -> game.end=="completed"&&game.won==false
        UNFINISHED -> game.end!="completed"
    }
}

@Composable private fun HistoryMatchRow(game:RecordedPlaytest) {
    var expanded by remember(game.id) { mutableStateOf(false) }
    val ownCommander=game.commanderNames.firstOrNull()
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                ownCommander?.let { name -> CommanderThumbnail(name) }
                Column(Modifier.weight(1f)) {
                    Text(game.deckName,style=MaterialTheme.typography.titleSmall,maxLines=2,overflow=TextOverflow.Ellipsis)
                    Text("${game.resultLabel()} · ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM,DateFormat.SHORT).format(Date(game.startedAt))}",
                        style=MaterialTheme.typography.bodySmall)
                    Text("${((game.finishedAt ?: game.observedAt)-game.startedAt)/60_000} min recorded · ${game.aiOpponents} AI",
                        style=MaterialTheme.typography.bodySmall)
                }
            }
            TextButton(onClick={expanded=!expanded}) { Text(if(expanded)"Hide match details" else "Match details") }
            if(expanded) {
                Text("Your commanders: "+game.commanderNames.joinToString(" · ").ifBlank { "not recorded" },
                    style=MaterialTheme.typography.bodySmall)
                Text(game.deck?.let { signature ->
                    "Exact playing list saved · ${signature.cards.sumOf { it.quantity }} cards · ${signature.cards.size} distinct entries"
                } ?: "Legacy summary · exact playing list was not saved",style=MaterialTheme.typography.bodySmall)
                val opponents=game.opponents.orEmpty()
                if(opponents.isEmpty()) {
                    Text("Public opponent identities were not recorded for this session.",style=MaterialTheme.typography.bodySmall)
                } else opponents.forEach { opponent ->
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        opponent.commanders.firstOrNull()?.let { CommanderThumbnail(it) }
                        Text("${opponent.name} · ${opponent.commanders.joinToString(" / ").ifBlank { "commander unknown" }}",
                            style=MaterialTheme.typography.bodySmall,modifier=Modifier.weight(1f))
                    }
                }
                if(game.end=="completed") {
                    Text("Final observed turn ${game.highestTurn}",style=MaterialTheme.typography.bodySmall)
                    game.commanderCasts.toSortedMap().forEach { (name,count) ->
                        Text("$name: $count observed command-zone casts",style=MaterialTheme.typography.bodySmall)
                    }
                } else Text("Unfinished session · no result or completed-game metrics",style=MaterialTheme.typography.bodySmall)
                Text("App ${game.appBuild} · XMage ${game.upstream} · catalogue ${game.catalogueHash} · AI skill ${game.aiSkill}",
                    style=MaterialTheme.typography.labelSmall)
                Text("Only public opponent names and commanders were retained. No hand or opponent decklist is stored.",
                    style=MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable private fun CommanderThumbnail(name:String) {
    CardArtwork(name,Modifier.width(42.dp).height(58.dp).clip(RoundedCornerShape(6.dp))) {
        Text("Art unavailable",style=MaterialTheme.typography.labelSmall,modifier=Modifier.padding(3.dp))
    }
}
