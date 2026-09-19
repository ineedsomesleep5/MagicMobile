package io.magicmobile.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.*

@Composable internal fun DeckChoice(label:String,value:String,choices:List<String>,select:(String)->Unit) {
    var expanded by remember{mutableStateOf(false)}
    Box {TextButton(onClick={expanded=true}){Text("$label: ${value.ifEmpty{"All"}}")};DropdownMenu(expanded=expanded,onDismissRequest={expanded=false}){choices.forEach{choice->DropdownMenuItem(text={Text(choice.ifEmpty{"All"})},onClick={select(choice);expanded=false})}}}
}

@Composable internal fun CommanderReplacementDialog(deck:Deck,catalogue:Catalogue,close:()->Unit,replace:(Deck,String,Boolean)->Boolean) {
    var query by remember{mutableStateOf("")};var keepOld by remember{mutableStateOf(true)};var error by remember{mutableStateOf<String?>(null)}
    val results=remember(query,catalogue){DeckCatalogueSearch.search(catalogue.cards,query)}
    AlertDialog(onDismissRequest=close,title={Text("Change primary commander")},text={Column{
        Text("Partners remain. One matching main-deck copy is promoted. XMage still checks eligibility and duplicates.")
        Row{Checkbox(checked=keepOld,onCheckedChange={keepOld=it});Text("Keep replaced commander in maybeboard")}
        OutlinedTextField(value=query,onValueChange={query=it.take(200)},label={Text("Search local catalogue")})
        error?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        LazyColumn(Modifier.heightIn(max=300.dp)){items(results,key={it.name}){card->TextButton(onClick={if(replace(deck,card.name,keepOld))close()else error="The draft changed or exceeds its limits. Nothing was partially applied."}){Text(card.name)}}}
    }},confirmButton={},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}
