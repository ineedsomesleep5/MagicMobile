package io.magicmobile.android

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.core.*
import java.util.Locale

private val roleTitles=mapOf(DeckRole.RAMP to "Ramp",DeckRole.CARD_FLOW to "Draw / card flow",DeckRole.INTERACTION to "Targeted interaction",DeckRole.BOARD_WIPE to "Board wipes",DeckRole.PROTECTION to "Protection",DeckRole.GRAVEYARD_HATE to "Graveyard interaction",DeckRole.RECURSION to "Recursion",DeckRole.TUTOR to "Tutors")

/** Analyses the current draft. Only auxiliary role preferences are saved, keyed by
 * the saved deck's immutable ID; closing never changes the deck or engine payload. */
@Composable
fun DeckInsightsDialog(deck:Deck,catalogue:Catalogue,savedDeckId:String?,close:()->Unit) {
    val context=LocalContext.current
    val store=remember {context.getSharedPreferences("magicmobile.insights.v1",Context.MODE_PRIVATE)}
    val loaded=remember(savedDeckId) {runCatching {
        if(savedDeckId==null)InsightPreferences() else {
            require(Wire.uuid(savedDeckId))
            store.getString(savedDeckId,null)?.let { InsightPreferences.decode(it.toByteArray()) } ?: InsightPreferences()
        }
    }}
    var preferences by remember(savedDeckId) {mutableStateOf(loaded.getOrDefault(InsightPreferences()))}
    var error by remember(savedDeckId) {mutableStateOf(if(loaded.isFailure)"Saved analysis preferences need recovery. They are preserved; customizing is paused." else null)}
    val editable=savedDeckId!=null && loaded.isSuccess
    val result=remember(deck,preferences,catalogue){runCatching {DeckInsights.analyze(deck,catalogue,preferences)}}
    val analysis=remember(deck,catalogue){DeckAnalyzer.analyze(deck,catalogue)}
    var selectedBin by remember {mutableStateOf<Int?>(null)}
    var selectedRole by remember {mutableStateOf<DeckRole?>(null)}
    var review by remember {mutableStateOf<InsightCard?>(null)}
    var target by remember {mutableStateOf<DeckRole?>(null)}
    var required by remember {mutableStateOf(3)}
    var seen by remember {mutableStateOf(7)}
    fun save(value:InsightPreferences):Boolean {
        if(!editable)return false
        return runCatching {
            val encoded=value.encode().toString(Charsets.UTF_8)
            check(store.edit().putString(savedDeckId,encoded).commit())
            preferences=value;error=null;true
        }.getOrElse {error="Could not save analysis preferences. Your deck is unchanged.";false}
    }
    Dialog(onDismissRequest=close,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.SpaceBetween) {Text("Deck insights",style=MaterialTheme.typography.headlineSmall);TextButton(onClick=close){Text("Done")}}
                LazyColumn(contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    item {Text(deck.name,style=MaterialTheme.typography.titleLarge);Text("${analysis.mainCardCount} main cards · ${analysis.landCount} lands · average nonland mana ${analysis.averageNonlandManaValue?.let {String.format(Locale.getDefault(),"%.2f",it)} ?: "unknown"}")}
                    error?.let {item {Text(it,color=MaterialTheme.colorScheme.error)}}
                    item {Text("Mana curve",style=MaterialTheme.typography.titleMedium);Text("Main-deck nonlands. Tap a row to see the cards.",style=MaterialTheme.typography.bodySmall)}
                    items((0..7).toList()) {bin->
                        TextButton(onClick={selectedBin=if(selectedBin==bin)null else bin},modifier=Modifier.fillMaxWidth()) {Text("${if(bin==7)"7+" else bin} mana · ${analysis.manaCurveBins[bin] ?: 0} cards")}
                        if(selectedBin==bin)deck.entries.filter {row->row.section=="deck" && catalogue.find(row.name)?.let {card->card.types?.contains("LAND")==false && card.manaValue?.let {if(it>=7)7 else it.toInt()}==bin}==true}.forEach {Text("${it.quantity} × ${it.name}")}
                    }
                    item {Text("Printed mana symbols",style=MaterialTheme.typography.titleMedium)}
                    result.getOrNull()?.let {insights->
                        items(insights.symbols.entries.toList()) {(symbol,count)->Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){ManaSymbol(symbol,22);Text("$count")}}
                        item {Text("Hybrid and Phyrexian symbols stay distinct. Printed costs are not usable mana sources. ${insights.missingCostCount} cards have unknown cost metadata.",style=MaterialTheme.typography.bodySmall)}
                        item {Text("Card types & colors",style=MaterialTheme.typography.titleMedium);Text(insights.types.entries.joinToString(" · "){"${it.key.lowercase().replaceFirstChar(Char::titlecase)} ${it.value}"});Text(analysis.printedColorCounts.entries.joinToString(" · "){"${it.key} ${it.value}"}+" · Colorless ${analysis.knownColorlessCount}");Text("Categories overlap. Unknown metadata is not assumed colorless.",style=MaterialTheme.typography.bodySmall)}
                        item {HorizontalDivider();Text("What your cards do",style=MaterialTheme.typography.titleMedium);Text("Offline curated tags and conservative text-pattern hints. Draw includes cantrips; this is not a deck score. Your reviewed tags replace automatic hints.",style=MaterialTheme.typography.bodySmall);if(savedDeckId==null)Text("Save this draft to customize roles and target ranges.")}
                        items(DeckRole.entries) {role->
                            val count=insights.count(role)
                            TextButton(onClick={selectedRole=if(selectedRole==role)null else role}){Text("${roleTitles[role]} · $count")}
                            preferences.targets[role]?.let {range->Text("${range.comparison(count)} · ${range.lower}–${range.upper}",style=MaterialTheme.typography.bodySmall)}
                            if(selectedRole==role) {
                                insights.cards.filter {card->card.evidence.any {it.role==role}}.forEach {card->Text("${card.quantity} × ${card.name} · ${card.evidence.first{it.role==role}.source}")}
                                TextButton(onClick={target=role},enabled=editable){Text("Set my target range")}
                            }
                        }
                        item {Text("${insights.unclassifiedCount} main-deck cards have no role tag. One card may have multiple roles. Lands are not inferred as ramp.",style=MaterialTheme.typography.bodySmall);HorizontalDivider();Text("Review card roles",style=MaterialTheme.typography.titleMedium)}
                        items(insights.cards) {card->TextButton(onClick={review=card},enabled=editable,modifier=Modifier.fillMaxWidth()) {Column(Modifier.fillMaxWidth()){Text("${card.quantity} × ${card.name}");Text(card.evidence.joinToString(" · "){roleTitles[it.role].orEmpty()}.ifEmpty{"Unclassified"},style=MaterialTheme.typography.bodySmall)}}}
                    }
                    if(result.isFailure)item {Text("Role analysis is unavailable for malformed or oversized draft data.",color=MaterialTheme.colorScheme.error)}
                    item {HorizontalDivider();Text("Opening hands & land draws",style=MaterialTheme.typography.titleMedium)
                        InsightStepper("At least $required lands",required,1..7){required=it}
                        InsightStepper("Cards seen: $seen",seen,7..30){seen=it}
                        if(analysis.mainCardCount in seen..2000 && analysis.unknownTypeCount==0) {
                            val probability=LandDrawProbability.atLeast(required,analysis.landCount,analysis.mainCardCount,seen)
                            Text(String.format(Locale.getDefault(),"%.1f%%",100*probability),style=MaterialTheme.typography.headlineLarge)
                        } else Text("Requires at least $seen main-deck cards and known types.")
                        Text("Random cards from the main deck, without replacement. No mulligans, tutors, extra-draw spells, land-side choices or play decisions are modeled. Enough lands does not prove each land drop or the right colors.",style=MaterialTheme.typography.bodySmall)
                    }
                    if(analysis.unknownNames.isNotEmpty())item {Text("Unresolved: ${analysis.unknownNames.joinToString()}")}
                }
            }
        }
    }
    review?.let {card->
        var roles by remember(card.name){mutableStateOf(card.evidence.map{it.role}.toSet())}
        AlertDialog(onDismissRequest={review=null},title={Text(card.name)},text={Column(Modifier.verticalScroll(rememberScrollState())) {
            DeckRole.entries.forEach{role->Row {Checkbox(checked=role in roles,onCheckedChange={roles=if(it)roles+role else roles-role});Text(roleTitles[role].orEmpty(),Modifier.padding(top=12.dp))}}
            Text("An empty selection explicitly clears automatic hints.",style=MaterialTheme.typography.bodySmall)
            TextButton(onClick={if(save(preferences.copy(overrides=preferences.overrides-card.name)))review=null}){Text("Use automatic hints")}
        }},confirmButton={TextButton(onClick={if(save(preferences.copy(overrides=preferences.overrides+(card.name to roles))))review=null}){Text("Save")}},dismissButton={TextButton(onClick={review=null}){Text("Cancel")}})
    }
    target?.let {role->
        var low by remember(role){mutableStateOf(preferences.targets[role]?.lower?.toString().orEmpty())}
        var high by remember(role){mutableStateOf(preferences.targets[role]?.upper?.toString().orEmpty())}
        val lower=low.toIntOrNull();val upper=high.toIntOrNull();val valid=lower!=null && upper!=null && lower in 0..2000 && upper in lower..2000
        AlertDialog(onDismissRequest={target=null},title={Text("${roleTitles[role]} target")},text={Column {
            Text("Your own range; there is no universal ideal Commander deck.")
            OutlinedTextField(low,{low=it.filter(Char::isDigit).take(4)},label={Text("Minimum")})
            OutlinedTextField(high,{high=it.filter(Char::isDigit).take(4)},label={Text("Maximum")})
            TextButton(onClick={if(save(preferences.copy(targets=preferences.targets-role)))target=null}){Text("Turn target off")}
        }},confirmButton={TextButton(enabled=valid,onClick={if(valid && save(preferences.copy(targets=preferences.targets+(role to RoleTarget(lower!!,upper!!)))))target=null}){Text("Save")}},dismissButton={TextButton(onClick={target=null}){Text("Cancel")}})
    }
}

@Composable private fun InsightStepper(label:String,value:Int,range:IntRange,change:(Int)->Unit) {
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
        TextButton(onClick={change(value-1)},enabled=value>range.first){Text("−")}
        Text(label,Modifier.padding(top=12.dp))
        TextButton(onClick={change(value+1)},enabled=value<range.last){Text("+")}
    }
}
