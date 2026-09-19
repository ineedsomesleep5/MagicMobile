package io.magicmobile.android

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

@Composable internal fun DeckPlaytestInsights(
    deck:Deck,catalogue:Catalogue,games:List<RecordedPlaytest>,recordingEnabled:Boolean,setRecording:(Boolean)->Unit,
) {
    val context=LocalContext.current
    val signature=remember(deck,catalogue){runCatching{DeckSignature.from(deck,catalogue)}.getOrNull()}
    var refresh by remember {mutableIntStateOf(0)}
    var matching by remember(signature){mutableStateOf<List<RecordedPlaytest>>(emptyList())}
    var error by remember(signature){mutableStateOf<String?>(null)}
    var loading by remember(signature){mutableStateOf(true)}
    LaunchedEffect(signature,games,refresh) {
        loading=true
        if(signature==null){matching=emptyList();error=null;loading=false}
        else {
            val result=withContext(Dispatchers.IO){
                try {Result.success(PlaytestStore(context).forDeck(signature))}
                catch(error:CancellationException){throw error}
                catch(error:Exception){Result.failure(error)}
            }
            // A newer draft/refresh owns presentation as soon as it cancels this
            // effect, even when a synchronous storage read has just completed.
            currentCoroutineContext().ensureActive()
            result.onSuccess{matching=it;error=null}.onFailure{matching=emptyList();error="Saved playtest history could not be read. It is preserved; your deck and gameplay are unchanged."}
            loading=false
        }
    }
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            Text("Game history",style=MaterialTheme.typography.titleMedium)
            Row {Column(Modifier.weight(1f)){Text("Save AI game summaries");Text("Stored on this device. Your hand and opponents’ decks are not recorded.",style=MaterialTheme.typography.bodySmall)};Switch(recordingEnabled,setRecording)}
            when {
                signature==null -> Text("Resolve the playing deck's card names to match its history.")
                loading -> LinearProgressIndicator(Modifier.fillMaxWidth())
                error!=null -> Text(error!!,color=MaterialTheme.colorScheme.error)
                matching.isEmpty() -> Text("No games recorded for this deck yet. Turn on summaries before your next game.")
                else -> {
                    Text("${matching.size} recorded sessions · ${matching.count{it.end=="completed"}} completed")
                    matching.take(12).forEach {game->
                        HorizontalDivider()
                        Text("${DateFormat.getDateTimeInstance(DateFormat.MEDIUM,DateFormat.SHORT).format(Date(game.startedAt))} · ${game.resultLabel()}",style=MaterialTheme.typography.titleSmall)
                        Text("${game.aiOpponents} AI · skill ${game.aiSkill} · highest observed turn ${game.highestTurn} · ${((game.finishedAt ?: game.observedAt)-game.startedAt)/60_000} min recorded elapsed",style=MaterialTheme.typography.bodySmall)
                        game.commanderCasts.toSortedMap().forEach{(name,count)->Text("$name: $count observed command-zone casts",style=MaterialTheme.typography.bodySmall)}
                        Text("App ${game.appBuild} · XMage ${game.upstream.take(8)}",style=MaterialTheme.typography.labelSmall)
                    }
                }
            }
            DeckExplanation("What these summaries measure", "History matches exact playing cards and quantities, including commanders and companions. Sideboards, maybeboards and titles do not affect matching. Time includes pauses; interrupted games are not losses. Summaries do not record every draw, mulligan or payment.")
            if(signature!=null && !loading && error==null && matching.isNotEmpty())PlaytestExportButton(signature)
            TextButton(onClick={refresh++},enabled=!loading){Text("Refresh this deck's history")}
            Text("Keeps the 100 most recent sessions. Clear history from the library.",style=MaterialTheme.typography.labelSmall)
        }
    }
}

internal fun RecordedPlaytest.resultLabel():String=when(end) {
    "completed" -> when(won){true->"Won";false->"Completed — not won";null->"Completed"}
    "in_progress" -> "In progress"
    "left" -> "Left game"
    "interrupted" -> "Interrupted"
    "engine_failed" -> "Engine stopped"
    else -> "Unknown result"
}
