package io.magicmobile.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import io.magicmobile.android.core.*

@Composable internal fun ImportReceiptDialog(receipt:ImportReceipt,close:()->Unit) {
    val context=LocalContext.current
    var exportStatus by remember{mutableStateOf<String?>(null)}
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")){uri->
        if(uri!=null)runCatching{context.contentResolver.openOutputStream(uri)?.use{it.write(io.magicmobile.core.Json.write(receipt.json()).toByteArray())}?:error("Unable to open export file")}.onSuccess{exportStatus="Source receipt exported."}.onFailure{exportStatus="Export failed: ${it.message}"}
    }
    AlertDialog(onDismissRequest=close,title={Text("Import source")},text={
        Column(Modifier.verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(receipt.source)
            Text("Original imported deck: ${receipt.importedDeck.name} · ${receipt.importedDeck.entries.sumOf{it.quantity}} cards. This source record is retained separately from later edits.")
            receipt.annotations.forEach {Text(it,style=MaterialTheme.typography.bodySmall)}
            if(receipt.originalText.isNotEmpty())Text(receipt.originalText.take(12000),style=MaterialTheme.typography.bodySmall)
            if(receipt.originalText.length>12000)Text("Preview shortened. Export includes the entire source.")
            exportStatus?.let{Text(it)}
        }
    },confirmButton={TextButton(onClick=close){Text("Done")}},dismissButton={TextButton(onClick={
        export.launch("magicmobile-import-receipt.json")
    }){Text("Export receipt")}})
}

@Composable internal fun DeckImportPreviewDialog(preview: DeckTextPreview, close: () -> Unit, open: () -> Unit) {
    AlertDialog(onDismissRequest=close, title={Text("Review imported deck")}, text={
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text("${preview.deck.entries.sumOf {it.quantity}} cards in ${preview.deck.entries.map {it.section}.distinct().joinToString()}")
            Text("Names are checked against the local catalogue in the editor; legality requires XMage validation.")
            if(preview.annotations.isNotEmpty()) {
                Text("Export annotations (not gameplay settings):")
                preview.annotations.forEach {Text(it,style=MaterialTheme.typography.bodySmall)}
            }
        }
    },confirmButton={TextButton(onClick=open){Text("Open draft")}},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}

@Composable internal fun BasicLandsDialog(deck: Deck, close: () -> Unit, apply: (Deck) -> Unit) {
    var counts by remember(deck) { mutableStateOf(DeckEditing.basics.associateWith { name ->
        deck.entries.filter { it.section == "deck" && it.name == name }.sumOf { it.quantity }.toString()
    }) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(onDismissRequest = close, title = { Text("Basic lands") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Set main-deck quantities. Other boards are preserved; Undo reverses the whole change.")
            DeckEditing.basics.forEach { name ->
                OutlinedTextField(value = counts.getValue(name), onValueChange = { value ->
                    if (value.length <= 4 && value.all(Char::isDigit)) counts = counts + (name to value)
                }, label = { Text(name) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(onClick = {
        runCatching { DeckEditing.setBasics(deck, counts.mapValues { it.value.toIntOrNull() ?: 0 }) }
            .onSuccess { apply(it); close() }.onFailure { error = "Enter valid quantities within the deck size limit." }
    }) { Text("Apply lands") } }, dismissButton = { TextButton(onClick = close) { Text("Cancel") } })
}

@Composable internal fun CatalogueCardDialog(name: String, catalogue: Catalogue?, close: () -> Unit) {
    val card = catalogue?.find(name)
    AlertDialog(onDismissRequest = close, title = { Text(name) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CardArtwork(name, Modifier.fillMaxWidth().height(260.dp)) { ArtworkHint() }
            ManaCost(card?.cost, size = 20)
            Text(card?.type ?: "Unresolved in the local catalogue")
            Text(card?.rules.orEmpty())
            card?.identity?.let { Text("Color identity: ${it.joinToString().ifEmpty { "Colorless" }}") }
        }
    }, confirmButton = { TextButton(onClick = close) { Text("Done") } })
}
