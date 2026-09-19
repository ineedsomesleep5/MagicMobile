package io.magicmobile.android

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.magicmobile.android.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

private val Cream=Color(0xFFF7F2E8)
private val Ink=Color(0xFF20352D)
private val Night=Color(0xFF121A17)
private val Parchment=Color(0xFFF2E9D8)
class MainActivity: ComponentActivity() {
    private val model: AppModel by viewModels()
    override fun onCreate(savedInstanceState:Bundle?) { super.onCreate(savedInstanceState);setContent { MagicApp(model) } }
    override fun onResume(){super.onResume();model.foreground(true)}
    override fun onStop(){model.foreground(false);super.onStop()}
}
private data class EditorRequest(val deck:Deck,val original:SavedDeck?=null)
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MagicApp(model:AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    var importing by remember { mutableStateOf(false) }
    var play by remember { mutableStateOf<Deck?>(null) }
    var inspect by remember { mutableStateOf<String?>(null) }
    var organize by remember { mutableStateOf<SavedDeck?>(null) }
    var delete by remember { mutableStateOf<SavedDeck?>(null) }
    var libraryQuery by remember { mutableStateOf("") }
    val context=LocalContext.current
    val fileImport=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {uri->
        if(uri!=null)runCatching {
            val bytes=context.contentResolver.openInputStream(uri)?.use {readBounded(it,2*1024*1024)} ?: error("Unable to open that file")
            Deck.parse("Imported Commander deck",bytes.toString(Charsets.UTF_8))
        }.onSuccess {deck->editor=EditorRequest(deck);model.recover(deck)}.onFailure {model.error(it.message ?: "Unable to import that file")}
    }
    val colors=if(isSystemInDarkTheme())darkColorScheme(primary=Color(0xFFB7D6C8),background=Night,surface=Color(0xFF1C2823),onBackground=Parchment,onSurface=Parchment) else lightColorScheme(primary=Ink,background=Cream,surface=Color(0xFFFFFCF6),onBackground=Ink,onSurface=Ink)
    MaterialTheme(colorScheme=colors) {
        Scaffold(topBar={TopAppBar(title={Text("MagicMobile",fontFamily=FontFamily.Serif)},actions={Text("Android alpha",style=MaterialTheme.typography.labelSmall,modifier=Modifier.padding(12.dp))})}) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).background(MaterialTheme.colorScheme.background)) {
                if(!BuildConfig.NATIVE_ENGINE) Text("DIAGNOSTIC BUILD · No native engine. Deck editing only; cannot play.",color=MaterialTheme.colorScheme.error,modifier=Modifier.padding(12.dp))
                if(state.error != null) Card(Modifier.fillMaxWidth().padding(12.dp)) { Column(Modifier.padding(12.dp)) { Text(state.error!!);Row {if(state.closing&&!state.playing)TextButton(onClick=model::close){Text("Retry engine cleanup")};TextButton(onClick={model.error(null)}){Text("Dismiss")}}} }
                when {
                    state.playing -> GameScreen(model,state) { inspect=it }
                    editor!=null -> DeckEditor(model,state,editor!!.deck,editor!!.original,{editor=null},{play=it})
                    !state.loaded -> { LinearProgressIndicator(Modifier.fillMaxWidth());Text(state.status,modifier=Modifier.padding(20.dp)) }
                    else -> LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                        item { Text("My Decks",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif);Text("Build. Refine. Play.",style=MaterialTheme.typography.bodyMedium) }
                        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onClick={editor=EditorRequest(Deck("New Commander deck",emptyList()))}){Text("Create deck")};OutlinedButton(onClick={importing=true}){Text("Paste")};OutlinedButton(onClick={fileImport.launch(arrayOf("text/plain","text/*","application/octet-stream"))}){Text("Import file")}} }
                        item { OutlinedTextField(value=libraryQuery,onValueChange={libraryQuery=it.take(200)},label={Text("Search decks, commanders, or tags")},modifier=Modifier.fillMaxWidth()) }
                        if(state.recovered!=null) item { OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)){Text("Recovered draft: ${state.recovered!!.name}");Row { TextButton(onClick={editor=EditorRequest(state.recovered!!)}){Text("Open as copy")};TextButton(onClick={model.discardRecovery()}){Text("Discard recovery")}}} } }
                        val savedDecks=state.decks.filter { saved->libraryQuery.isBlank() || listOf(saved.deck.name,saved.tags.joinToString(" "),saved.deck.entries.filter {it.section=="commanders"}.joinToString(" "){it.name}).any {it.contains(libraryQuery,true)} }
                        items(savedDecks,key={it.id}) { saved -> DeckTile(saved.deck,"Saved on this device",saved,{editor=EditorRequest(saved.deck,saved)},{play=saved.deck},{organize=saved},{model.duplicate(saved)},{delete=saved}) }
                        item { Text("Included Commander decks",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif) }
                        val precons=state.precons.filter { deck->libraryQuery.isBlank() || deck.name.contains(libraryQuery,true) || deck.entries.any {it.section=="commanders" && it.name.contains(libraryQuery,true)} }
                        items(precons,key={it.name}) { deck -> DeckTile(deck,"Included · edit a local copy",null,{editor=EditorRequest(deck)},{play=deck},{},{},{}) }
                        item { HorizontalDivider();Text("Private playtest history",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)
                            Row(verticalAlignment=Alignment.CenterVertically){Switch(checked=state.recordingEnabled,onCheckedChange=model::setRecording);Spacer(Modifier.width(10.dp));Column{Text(if(state.recordingEnabled)"Recording summaries" else "Recording off");Text("Device-only, bounded to 100 games; no hands or opponent decklists.",style=MaterialTheme.typography.bodySmall)}}
                            if(state.playtests.isEmpty())Text("No recorded playtests.",style=MaterialTheme.typography.bodySmall)
                        }
                        items(state.playtests.take(12),key={it.id}) { row->OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(row.deckName,style=MaterialTheme.typography.titleMedium);Text("${row.end.replace('_',' ')} · highest observed turn ${row.highestTurn} · AI skill ${row.aiSkill}",style=MaterialTheme.typography.bodySmall);if(row.commanderCasts.isNotEmpty())Text(row.commanderCasts.entries.joinToString {"${it.key}: ${it.value} cast(s)"},style=MaterialTheme.typography.bodySmall)}} }
                        if(state.playtests.isNotEmpty())item{TextButton(onClick=model::clearPlaytests){Text("Clear playtest history")}}
                        item { ArtworkConsentRow() }
                        item { Text(state.status,style=MaterialTheme.typography.bodySmall);Text("Games run locally with the packaged XMage engine. No external computer or account. Cross-device multiplayer is not in this Android alpha.",style=MaterialTheme.typography.bodySmall) }
                    }
                }
            }
        }
        if(importing) ImportDialog({importing=false}) { deck -> importing=false;editor=EditorRequest(deck);model.recover(deck) }
        if(play!=null) {
            val deck=play!!;val preferences=remember {context.getSharedPreferences("magicmobile.play",android.content.Context.MODE_PRIVATE)}
            var ai by remember { mutableIntStateOf(1) };var aiSkill by remember { mutableIntStateOf(preferences.getInt("aiSkill",2).coerceIn(1,10)) };var exclude by remember { mutableStateOf(false) }
            var opponent by remember { mutableIntStateOf(0) }
            val validated=model.validationMatches(deck,exclude)
            AlertDialog(onDismissRequest={play=null},title={Text("Start local Commander")},text={Column {
                Text(deck.name);Text("XMage validates the deck while starting. Parsing alone is not Commander legality.")
                Row {TextButton(onClick={ai=(ai-1).coerceAtLeast(1)}){Text("−")};Text("$ai AI opponent(s)",modifier=Modifier.padding(12.dp));TextButton(onClick={ai=(ai+1).coerceAtMost(3)}){Text("+")}}
                Text("AI skill · $aiSkill");Slider(value=aiSkill.toFloat(),onValueChange={aiSkill=it.toInt().coerceIn(1,10);preferences.edit().putInt("aiSkill",aiSkill).apply()},valueRange=1f..10f,steps=8)
                if(state.precons.isNotEmpty()) { Text("Opponent deck");TextButton(onClick={opponent=(opponent+1)%state.precons.size}){Text(state.precons[opponent].name)} }
                if(deck.entries.any { it.section !in setOf("deck","commanders","companions") })Row {Checkbox(checked=exclude,onCheckedChange={exclude=it;model.invalidateValidation()});Text("Exclude other boards from this game only. Keep source draft intact.")}
                Text(if(validated)"Commander validation passed for this exact deck and engine." else "Validate this exact playing deck before starting.",color=if(validated)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)
                Text("This alpha has no durable game resume after Android kills the process. Begin with one AI.",style=MaterialTheme.typography.bodySmall)
            }},confirmButton={if(validated)Button(enabled=!state.busy && state.precons.isNotEmpty(),onClick={model.start(deck,state.precons[opponent],ai,exclude,aiSkill);play=null}){Text("Start local game")}else Button(enabled=BuildConfig.NATIVE_ENGINE&&!state.busy,onClick={model.validate(deck,exclude)}){Text("Validate deck")}},dismissButton={TextButton(onClick={play=null}){Text("Cancel")}})
        }
        organize?.let { saved->OrganizationDialog(saved,{organize=null}) {favorite,tags,notes->model.organize(saved,favorite,tags,notes);organize=null} }
        delete?.let {saved->AlertDialog(onDismissRequest={delete=null},title={Text("Delete ${saved.deck.name}?")},text={Text("This removes the local deck. Playtest summaries are retained until you clear their separate history.")},confirmButton={TextButton(onClick={model.delete(saved);delete=null}){Text("Delete")}},dismissButton={TextButton(onClick={delete=null}){Text("Cancel")}})}
        if(inspect!=null) {
            val card=model.catalogue?.find(inspect!!)
            AlertDialog(onDismissRequest={inspect=null},title={Text(inspect!!)},text={Column(Modifier.verticalScroll(rememberScrollState())) {CardArtwork(inspect!!,Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(10.dp))){ArtworkHint()};Spacer(Modifier.height(10.dp));ManaCost(card?.cost,size=20);Text(card?.type.orEmpty());Text(Decisions.plain(card?.rules ?: "No local metadata for this object."))}},confirmButton={TextButton(onClick={inspect=null}){Text("Done")}})
        }
    }
}
@Composable private fun DeckTile(deck:Deck,subtitle:String,saved:SavedDeck?,edit:()->Unit,play:()->Unit,organize:()->Unit,duplicate:()->Unit,delete:()->Unit) {
    Card(Modifier.fillMaxWidth()){Column(Modifier.padding(18.dp)){Text(deck.name,style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)
        Text(deck.entries.filter { it.section=="commanders" }.joinToString(" + "){it.name},style=MaterialTheme.typography.bodyMedium)
        Text("${if(saved?.favorite==true)"★ · " else ""}${deck.entries.sumOf { it.quantity }} cards · $subtitle",style=MaterialTheme.typography.bodySmall)
        if(!saved?.tags.isNullOrEmpty())Text(saved!!.tags.joinToString(" · "),style=MaterialTheme.typography.labelSmall)
        Row {TextButton(onClick=edit){Text("Open")};TextButton(onClick=play){Text("Playtest")}}
        if(saved!=null)Row {TextButton(onClick=organize){Text("Organize")};TextButton(onClick=duplicate){Text("Copy")};TextButton(onClick=delete){Text("Delete")}}}}
}
@Composable private fun OrganizationDialog(saved:SavedDeck,close:()->Unit,save:(Boolean,List<String>,String)->Unit) {
    var favorite by remember(saved){mutableStateOf(saved.favorite)};var tags by remember(saved){mutableStateOf(saved.tags.joinToString(", "))};var notes by remember(saved){mutableStateOf(saved.notes)}
    AlertDialog(onDismissRequest=close,title={Text("Organize ${saved.deck.name}")},text={Column(Modifier.verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)){
        Row(verticalAlignment=Alignment.CenterVertically){Checkbox(checked=favorite,onCheckedChange={favorite=it});Text("Favorite")}
        OutlinedTextField(value=tags,onValueChange={tags=it.take(1000)},label={Text("Tags · comma separated")},modifier=Modifier.fillMaxWidth())
        OutlinedTextField(value=notes,onValueChange={notes=it.take(16384)},label={Text("Private notes · 16 KiB max")},modifier=Modifier.fillMaxWidth().heightIn(min=140.dp))
        Text("Organization stays on this device and is never sent to XMage.",style=MaterialTheme.typography.bodySmall)
    }},confirmButton={TextButton(onClick={save(favorite,tags.split(',').map(String::trim).filter(String::isNotBlank),notes)}){Text("Save details")}},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}
@Composable private fun ImportDialog(close:()->Unit,import:(Deck)->Unit) {
    var name by remember {mutableStateOf("Imported Commander deck")};var text by remember {mutableStateOf("")};var error by remember {mutableStateOf<String?>(null)}
    AlertDialog(onDismissRequest=close,title={Text("Paste a decklist")},text={Column(Modifier.verticalScroll(rememberScrollState())) {
        OutlinedTextField(value=name,onValueChange={name=it.take(300)},label={Text("Deck name")})
        OutlinedTextField(value=text,onValueChange={if(it.length<200000)text=it},label={Text("Commander\n1 Card Name\n\nDeck\n1 Sol Ring")},modifier=Modifier.heightIn(min=240.dp))
        Text("Export plain card names and counts from Archidekt or ManaBox. Unrecognized rows are reported, never silently dropped. Name support and Commander legality are checked separately.",style=MaterialTheme.typography.bodySmall)
        error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
    }},confirmButton={TextButton(onClick={try{import(Deck.parse(name,text))}catch(e:Exception){error=e.message}}){Text("Review draft")}},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}
@Composable private fun DeckEditor(model:AppModel,state:ScreenState,initial:Deck,original:SavedDeck?,close:()->Unit,play:(Deck)->Unit) {
    var draft by remember(initial,original){mutableStateOf(initial)}
    var undo by remember(initial){mutableStateOf(emptyList<Deck>())};var redo by remember(initial){mutableStateOf(emptyList<Deck>())}
    var search by remember {mutableStateOf("")};var results by remember {mutableStateOf(emptyList<CardInfo>())}
    var section by remember {mutableStateOf("deck")};var message by remember {mutableStateOf<String?>(null)}
    var exclude by remember {mutableStateOf(false)}
    var title by remember(initial){mutableStateOf(initial.name)}
    val context=LocalContext.current
    fun change(next:Deck){undo=(undo+draft).takeLast(50);redo=emptyList();draft=next;model.invalidateValidation();model.recover(next)}
    LaunchedEffect(initial,original?.revision){model.invalidateValidation()}
    LaunchedEffect(search){results=withContext(Dispatchers.Default){model.catalogue?.search(search).orEmpty()}}
    val analysis=remember(draft,model.catalogue){model.catalogue?.let {DeckAnalyzer.analyze(draft,it)}}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        item {Text("Deck Studio",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif)
            OutlinedTextField(value=title,onValueChange={title=it.take(300)},label={Text("Deck name")},modifier=Modifier.fillMaxWidth())
            Row {TextButton(enabled=title.isNotBlank(),onClick={change(draft.copy(name=title))}){Text("Rename")};TextButton(onClick={model.recover(draft);close()}){Text("Back · keep draft")}}
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onClick={model.save(draft,original){Handler(Looper.getMainLooper()).post {close()}}}){Text("Save deck")};OutlinedButton(onClick={play(draft)}){Text("Playtest")};OutlinedButton(enabled=BuildConfig.NATIVE_ENGINE&&!state.busy,onClick={model.validate(draft,exclude)}){Text("Validate")}}
            Row{TextButton(enabled=undo.isNotEmpty(),onClick={redo=redo+draft;draft=undo.last();undo=undo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Undo")};TextButton(enabled=redo.isNotEmpty(),onClick={undo=undo+draft;draft=redo.last();redo=redo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Redo")};TextButton(onClick={context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply{type="text/plain";putExtra(Intent.EXTRA_TEXT,draft.export())},"Export deck"))}){Text("Export")}}
            if(draft.entries.any {it.section !in setOf("deck","commanders","companions")})Row(verticalAlignment=Alignment.CenterVertically){Checkbox(checked=exclude,onCheckedChange={exclude=it;model.invalidateValidation()});Text("Validate without other boards")}
            state.validation?.takeIf {model.validationApplies(draft,exclude)}?.let {report->Text(report.summary,color=if(report.valid)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error);report.issues.take(20).forEach{Text("• ${it.cardName?.let {name->"$name: "}.orEmpty()}${it.message}",style=MaterialTheme.typography.bodySmall)}}
            message?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        }
        item {OutlinedTextField(value=search,onValueChange={search=it.take(200)},label={Text("Add cards · name or rules text")},modifier=Modifier.fillMaxWidth())
            Row {listOf("deck","commanders","maybeboard").forEach{target->FilterChip(selected=section==target,onClick={section=target},label={Text(target)})}}}
        items(results,key={it.name}) { card -> OutlinedCard(Modifier.fillMaxWidth()){Row(Modifier.padding(10.dp),verticalAlignment=Alignment.CenterVertically){CardArtwork(card.name,Modifier.size(38.dp,52.dp).clip(RoundedCornerShape(4.dp))){Text(card.name.take(1),style=MaterialTheme.typography.labelSmall)};Spacer(Modifier.width(10.dp));Column(Modifier.weight(1f)){Text(card.name);Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){ManaCost(card.cost);Text(card.type.orEmpty(),style=MaterialTheme.typography.bodySmall)}};TextButton(onClick={try{change(draft.copy(entries=draft.entries+CardEntry(card.name,1,section)));message=null}catch(e:Exception){message=e.message}}){Text("+ Add")}}} }
        if(search.isNotBlank())item{Text("Local compiled catalogue · up to 80 results",style=MaterialTheme.typography.bodySmall)}
        analysis?.let { facts->item {OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){
            Text("Deck analysis",style=MaterialTheme.typography.titleMedium)
            Text("${facts.mainCardCount} main cards · ${facts.landCount} lands · average nonland mana ${facts.averageNonlandManaValue?.let {String.format(Locale.US,"%.2f",it)} ?: "unknown"}")
            Text("Curve 0–7+: "+facts.manaCurveBins.entries.joinToString(" · "){"${it.key}${if(it.key==7)"+" else ""}: ${it.value}"},style=MaterialTheme.typography.bodySmall)
            val roles=facts.roles.filterValues {it.count>0};if(roles.isNotEmpty())Text(roles.entries.joinToString(" · "){"${it.key.name.lowercase().replace('_',' ')} ${it.value.count}"},style=MaterialTheme.typography.bodySmall)
            if(facts.unknownNameCount>0)Text("${facts.unknownNameCount} unresolved card(s): ${facts.unknownNames.take(8).joinToString()}",color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)
            Text("Catalogue facts only—not a power score, mana-source estimate, simulation, or legality result.",style=MaterialTheme.typography.labelSmall)
        }}}}
        draft.entries.withIndex().groupBy{it.value.section}.forEach { (section,rows) ->
            item(key="header-$section"){Text("${section.replaceFirstChar{it.uppercase()}} · ${rows.sumOf {it.value.quantity}}",style=MaterialTheme.typography.titleMedium)}
            items(rows,key={"row-${it.index}"}) { (index,row) -> Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(row.name);model.catalogue?.find(row.name).let { info -> if(info?.cost != null) ManaCost(info.cost) else Text(if(info==null) "Unresolved in local catalogue" else info.type.orEmpty(),style=MaterialTheme.typography.bodySmall) }
                Row {TextButton(onClick={try{change(draft.change(index,-1))}catch(e:Exception){message=e.message}}){Text("−")};Text("${row.quantity}",modifier=Modifier.padding(12.dp));TextButton(onClick={try{change(draft.change(index,1))}catch(e:Exception){message=e.message}}){Text("+")}
                    TextButton(onClick={val destination=if(row.section=="commanders")"deck" else "commanders";change(draft.copy(entries=draft.entries.toMutableList().apply {set(index,row.copy(section=destination))}))}){Text(if(row.section=="commanders")"To main" else "Commander")}} }} }
        }
        item {Text("Explore ideas",style=MaterialTheme.typography.titleMedium)
            Text("User-controlled websites. This alpha does not upload your deck or extract recommendations.",style=MaterialTheme.typography.bodySmall)
            Row {TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://scryfall.com/search?q=${Uri.encode(search.ifBlank {draft.entries.firstOrNull {it.section=="commanders"}?.name.orEmpty()})}")))}){Text("Scryfall ↗")};TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://edhrec.com/commanders")))}){Text("EDHREC ↗")};TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://commanderspellbook.com/find-my-combos/")))}){Text("Spellbook ↗")}}
        }
    }
}
@Composable private fun GameScreen(model:AppModel,state:ScreenState,inspect:(String)->Unit) {
    val poll=state.game;val snapshot=poll?.snapshot;val game=snapshot?.obj("gameView")
    val decision=poll?.decision
    val choices=remember(decision,snapshot){runCatching{if(decision==null)emptyList() else Decisions.choices(decision,snapshot)}.getOrElse{emptyList()}}
    var confirmClose by remember {mutableStateOf(false)}
    val context=LocalContext.current
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal=12.dp)){Text(state.status,modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall);TextButton(onClick={model.refresh()},enabled=!state.closing){Text("Refresh")};TextButton(onClick={confirmClose=true}){Text(if(state.closing)"Retry cleanup" else "Leave")}}
        if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        if(state.pendingAnswer)Row(Modifier.padding(12.dp)){Text("Uncertain response",modifier=Modifier.weight(1f));Button(onClick={model.retry()},enabled=!state.closing){Text("Retry same action")}}
        val board=rememberLazyListState()
        // A new decision must not land below the fold: on a phone an unseen prompt reads as
        // a frozen game, which is exactly how the mulligan question presented on device.
        LaunchedEffect(decision?.id,decision?.revision) {
            if(decision!=null && !decision.submitted) runCatching { board.animateScrollToItem(board.layoutInfo.totalItemsCount.coerceAtLeast(1)-1) }
        }
        LazyColumn(Modifier.weight(1f),state=board,contentPadding=PaddingValues(12.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            item {Text("${game?.get("turn") ?: "—"} · ${game?.get("step") ?: "Waiting for state"}",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)}
            val players=runCatching{game?.array("players").orEmpty().map(Wire::objectValue)}.getOrDefault(emptyList())
            items(players,key={it["playerId"].toString()}) { player -> Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text("${player["name"]} · ${player["life"]} life",style=MaterialTheme.typography.titleMedium)
                Text("Hand ${player["handCount"] ?: "?"} · Library ${player["libraryCount"] ?: "?"}",style=MaterialTheme.typography.bodySmall)
                Zone("Battlefield",player.obj("battlefield"),inspect)
                var expanded by remember {mutableStateOf(false)}
                TextButton(onClick={expanded=!expanded}){Text(if(expanded)"Hide other zones" else "Graveyard / exile / commanders")}
                if(expanded){Zone("Graveyard",player.obj("graveyard"),inspect);Zone("Exile",player.obj("exile"),inspect);player.array("commandList").forEach {card->PublicCard(card,inspect)}}
            }}}
            item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Zone("Your hand",game?.obj("myHand"),inspect)}}}
            item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Zone("Stack",game?.obj("stack"),inspect)}}}
            if(decision!=null)item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(decision.kind.replace('_',' '),style=MaterialTheme.typography.titleMedium)
                Text(Decisions.plain(decision.payload.text("message").orEmpty()))
                if(decision.submitted)Text("Answer submitted · waiting for XMage")
                choices.forEach { choice -> OutlinedButton(onClick={model.answer(choice.type,choice.value)},enabled=!state.busy && !state.pendingAnswer && !state.closing && !decision.submitted,modifier=Modifier.fillMaxWidth()) {Text(choice.label)} }
                if("integer" in decision.responseTypes) {
                    // The engine sends the Int sentinels to mean "no limit". Showing them
                    // literally prefilled the field with -2147483648 and labelled the range
                    // "-2147483648 … 2147483647", which reads as a broken prompt.
                    val range=PromptPresentation.integerRange(decision)
                    var amount by remember(decision.id,decision.revision){mutableStateOf(range.initialValue)}
                    val entered=amount.toLongOrNull()
                    val withinRange=range.contains(entered)
                    OutlinedTextField(value=amount,onValueChange={amount=it.filter{c->c.isDigit()||c=='-'}.take(12)},
                        isError=amount.isNotEmpty() && !withinRange,label={Text("Amount · ${range.label}")})
                    TextButton(onClick={entered?.let{model.answer("integer",it)}},enabled=!state.busy && !decision.submitted && withinRange){Text("Submit amount")}
                }
                if("integers" in decision.responseTypes){
                    var values by remember(decision.id,decision.revision){mutableStateOf("")}
                    Text(Decisions.plain(decision.payload.toString()).take(1600),style=MaterialTheme.typography.bodySmall)
                    OutlinedTextField(value=values,onValueChange={values=it.take(2000)},label={Text("Amounts in shown order, comma separated")})
                    TextButton(onClick={runCatching{values.split(',').map{it.trim().toLong()}}.onSuccess{model.answer("integers",it)}.onFailure{model.error("Enter one integer per listed item.")}},enabled=!state.busy && !decision.submitted){Text("Submit allocation")}
                }
                if(choices.isEmpty() && decision.responseTypes.none{it=="integer" || it=="integers"} && !decision.submitted)Text("This prompt variant needs additional Android presentation support. No choice will be guessed. Export diagnostics and report the prompt kind.",color=MaterialTheme.colorScheme.error)
            }}}
            if(poll?.phase in setOf("ended","failed"))item{Text(if(poll?.phase=="ended")"Game finished" else "Game stopped — not recorded as a loss",style=MaterialTheme.typography.titleLarge)}
            item {TextButton(onClick={model.diagnostics {text->Handler(Looper.getMainLooper()).post{context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply{type="text/plain";putExtra(Intent.EXTRA_TEXT,text)},"Share private diagnostics"))}}}){Text("Export diagnostics (may contain private card data)")}}
        }
    }
    if(confirmClose)AlertDialog(onDismissRequest={confirmClose=false},title={Text("Leave this game?")},text={Text("There is no saved-game resume in this Android alpha. Engine cleanup will finish before another game can start.")},confirmButton={TextButton(onClick={confirmClose=false;model.close()}){Text("Leave / retry cleanup")}},dismissButton={TextButton(onClick={confirmClose=false}){Text("Keep playing")}})
}
@Composable private fun Zone(title:String,cards:Obj?,inspect:(String)->Unit) {Text(title,style=MaterialTheme.typography.labelLarge);if(cards.isNullOrEmpty())Text("—",style=MaterialTheme.typography.bodySmall);cards?.values?.forEach{PublicCard(it,inspect)}}
@Composable private fun PublicCard(raw:Any?,inspect:(String)->Unit) {
    val card=raw as? Map<*,*> ?: return;val hidden=card["hideInfo"]==true || card["faceDown"]==true
    val name=Decisions.cardLabel(card)
    Row(Modifier.fillMaxWidth().clickable(enabled=!hidden){inspect(card["name"]?.toString() ?: name)}.padding(vertical=10.dp)) {
        Text(name,modifier=Modifier.weight(1f));if(!hidden){Text((card["power"]?.toString()?.let{"$it/${card["toughness"]}"} ?: "")+if(card["tapped"]==true)" · tapped" else "",style=MaterialTheme.typography.bodySmall)}
    }
}
