package io.magicmobile.android

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import io.magicmobile.android.core.DeckSignature

@Composable internal fun PlaytestHistoryActions(clear:()->Unit) {
    val context=LocalContext.current
    var confirmClear by remember{mutableStateOf(false)}
    var status by remember{mutableStateOf<String?>(null)}
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")){uri->
        if(uri!=null)runCatching{
            val bytes=PlaytestStore(context).exportJson().toByteArray()
            context.contentResolver.openOutputStream(uri)?.use{it.write(bytes)}?:error("Unable to open selected file")
        }.onSuccess{status="Playtest history exported."}.onFailure{status="Export failed: ${it.message}"}
    }
    Column {
        Text("Export includes your deck's card names, game settings and observed results. No hands or opponent decklists.",style=MaterialTheme.typography.bodySmall)
        TextButton(onClick={export.launch("magicmobile-playtests.json")}){Text("Export playtest history")}
        TextButton(onClick={confirmClear=true}){Text("Clear playtest history")}
        status?.let{Text(it,style=MaterialTheme.typography.bodySmall)}
    }
    if(confirmClear)AlertDialog(onDismissRequest={confirmClear=false},title={Text("Clear playtest history?")},text={Text("This permanently removes the recorded summaries on this device. Your decks and exported files are kept.")},confirmButton={TextButton(onClick={confirmClear=false;clear()}){Text("Clear history")}},dismissButton={TextButton(onClick={confirmClear=false}){Text("Cancel")}})
}

/** Snapshot the selected scope before opening the system picker. A draft change
 * while it is open must never widen an export to other decks or all history. */
@Composable internal fun PlaytestExportButton(signature:DeckSignature) {
    val context=LocalContext.current
    var pendingJson by remember {mutableStateOf<String?>(null)}
    var status by remember {mutableStateOf<String?>(null)}
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")){uri->
        val json=pendingJson;pendingJson=null
        if(uri!=null)runCatching {
            checkNotNull(json){"Export was interrupted. Choose Export again."}
            context.contentResolver.openOutputStream(uri)?.use{it.write(json.toByteArray())} ?: error("Unable to open selected file")
        }.onSuccess{status="This deck's playtest summaries exported."}.onFailure{status="Export failed: ${it.message}"}
    }
    Column {
        Text("Export includes these playing cards, settings and observed results. No hands or opponents' decklists.",style=MaterialTheme.typography.bodySmall)
        TextButton(onClick={runCatching{PlaytestStore(context).exportJson(signature)}.onSuccess{pendingJson=it;export.launch("magicmobile-deck-playtests.json")}.onFailure{status="History could not be read; no file exported. Stored history is preserved."}}){Text("Export this deck's summaries")}
        status?.let{Text(it,style=MaterialTheme.typography.bodySmall)}
    }
}
