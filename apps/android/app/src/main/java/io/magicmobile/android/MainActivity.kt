package io.magicmobile.android

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.platform.LocalConfiguration
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
private data class EditorRequest(val deck:Deck,val original:SavedDeck?=null,val draftID:String=original?.id ?: java.util.UUID.randomUUID().toString(),val receipt:ImportReceipt?=null)
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MagicApp(model:AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    var importing by remember { mutableStateOf(false) }
    var importingLink by remember { mutableStateOf(false) }
    var importPreview by remember { mutableStateOf<DeckTextPreview?>(null) }
    var play by remember { mutableStateOf<Deck?>(null) }
    var inspect by remember { mutableStateOf<String?>(null) }
    var organize by remember { mutableStateOf<SavedDeck?>(null) }
    var delete by remember { mutableStateOf<SavedDeck?>(null) }
    var libraryQuery by remember { mutableStateOf("") }
    var favoritesOnly by remember { mutableStateOf(false) }
    var librarySort by remember { mutableStateOf("Favorites first") }
    val context=LocalContext.current
    val libraryPreferences=remember{context.getSharedPreferences("magicmobile.library",android.content.Context.MODE_PRIVATE)}
    var libraryGrid by remember{mutableStateOf(libraryPreferences.getBoolean("grid",true))}
    var appearance by remember{mutableStateOf(libraryPreferences.getString("appearance","System")?.takeIf{it in setOf("System","Light","Dark")} ?: "System")}
    val configuration=LocalConfiguration.current
    val libraryColumns=if(libraryGrid&&configuration.fontScale<1.3f)(configuration.screenWidthDp/180).coerceIn(1,3) else 1
    val drafts=remember {DeckDraftStore(context)}
    var draftRefresh by remember {mutableIntStateOf(0)}
    val draftRead=remember(editor,draftRefresh){runCatching{drafts.all()}}
    val draftRecords=draftRead.getOrDefault(emptyList())
    val fileImport=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {uri->
        if(uri!=null)runCatching {
            val bytes=context.contentResolver.openInputStream(uri)?.use {readBounded(it,2*1024*1024)} ?: error("Unable to open that file")
            DeckTextImport.preview("Imported Commander deck",bytes.toString(Charsets.UTF_8))
        }.onSuccess {importPreview=it}.onFailure {model.error(it.message ?: "Unable to import that file")}
    }
    val dark=appearance=="Dark"||(appearance=="System"&&isSystemInDarkTheme())
    val colors=if(dark)darkColorScheme(primary=Color(0xFFB7D6C8),background=Night,surface=Color(0xFF1C2823),onBackground=Parchment,onSurface=Parchment) else lightColorScheme(primary=Ink,background=Cream,surface=Color(0xFFFFFCF6),onBackground=Ink,onSurface=Ink)
    MaterialTheme(colorScheme=colors) {
        Scaffold(topBar={TopAppBar(title={Text("MagicMobile",fontFamily=FontFamily.Serif)},actions={Text("Android alpha",style=MaterialTheme.typography.labelSmall,modifier=Modifier.padding(12.dp))})}) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).background(MaterialTheme.colorScheme.background)) {
                if(!BuildConfig.NATIVE_ENGINE) Text("DIAGNOSTIC BUILD · No native engine. Deck editing only; cannot play.",color=MaterialTheme.colorScheme.error,modifier=Modifier.padding(12.dp))
                if(state.error != null) Card(Modifier.fillMaxWidth().padding(12.dp)) { Column(Modifier.padding(12.dp)) { Text(state.error!!);Row {if(state.closing&&!state.playing)TextButton(onClick=model::close){Text("Retry engine cleanup")};TextButton(onClick={model.error(null)}){Text("Dismiss")}}} }
                when {
                    state.playing -> GameScreen(model,state) { inspect=it }
                    editor!=null -> DeckEditor(model,state,editor!!.deck,editor!!.original,editor!!.draftID,editor!!.receipt,{editor=null;draftRefresh++},{play=it})
                    !state.loaded -> { LinearProgressIndicator(Modifier.fillMaxWidth());Text(state.status,modifier=Modifier.padding(20.dp)) }
                    else -> LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                        item { Text("My Decks",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif);Text("Build. Refine. Play.",style=MaterialTheme.typography.bodyMedium) }
                        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onClick={editor=EditorRequest(Deck("New Commander deck",emptyList()))}){Text("Create deck")};OutlinedButton(onClick={importing=true}){Text("Paste")};OutlinedButton(onClick={fileImport.launch(arrayOf("text/plain","text/*","application/octet-stream"))}){Text("Import file")}} }
                        item { OutlinedTextField(value=libraryQuery,onValueChange={libraryQuery=it.take(200)},label={Text("Search decks, commanders, or tags")},modifier=Modifier.fillMaxWidth()) }
                        item {TextButton(onClick={importingLink=true}){Text("Import public deck link")}}
                        item {DeckPhotoImportButton{deck,receipt->editor=EditorRequest(deck,receipt=receipt);model.recover(deck)}}
                        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){FilterChip(selected=favoritesOnly,onClick={favoritesOnly=!favoritesOnly},label={Text("Favorites")});TextButton(onClick={librarySort=if(librarySort=="Favorites first")"Name" else "Favorites first"}){Text("Sort: $librarySort")}};TextButton(onClick={libraryGrid=!libraryGrid;libraryPreferences.edit().putBoolean("grid",libraryGrid).apply()}){Text(if(libraryGrid)"Show list" else "Show grid")} }
                        if(state.recovered!=null) item { OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)){Text("Recovered draft: ${state.recovered!!.name}");Row { TextButton(onClick={editor=EditorRequest(state.recovered!!)}){Text("Open as copy")};TextButton(onClick={model.discardRecovery()}){Text("Discard recovery")}}} } }
                        val savedDecks=state.decks.filter { saved->(!favoritesOnly||saved.favorite)&&(libraryQuery.isBlank() || listOf(saved.deck.name,saved.tags.joinToString(" "),saved.deck.entries.filter {it.section=="commanders"}.joinToString(" "){it.name}).any {it.contains(libraryQuery,true)}) }.sortedWith(compareBy<SavedDeck>{if(librarySort=="Favorites first"&&it.favorite)0 else 1}.thenBy{it.deck.name.lowercase()})
                        if(savedDecks.isEmpty())item{Text("No saved decks match. Create a deck or change your filters.")}
                        if(draftRecords.isNotEmpty())item{Text("Unfinished drafts",style=MaterialTheme.typography.titleMedium)}
                        if(draftRead.isFailure)item{Text("A draft could not be read. Draft files are preserved on this device.",color=MaterialTheme.colorScheme.error)}
                        items(draftRecords,key={"draft-${it.id}"}){record->OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(record.deck.name);Row{TextButton(onClick={val original=state.decks.firstOrNull{it.id==(record.savedID?:record.id)&&it.revision==record.baseRevision};editor=EditorRequest(record.deck,original,record.id)}){Text(if(state.decks.any{it.id==(record.savedID?:record.id)&&it.revision==record.baseRevision})"Resume draft" else "Open draft as copy")};TextButton(onClick={runCatching{if(state.decks.none{it.id==record.id})ReceiptStore(context).delete(record.id);drafts.delete(record.id)}.onFailure{model.error("Unable to discard draft: ${it.message}")};draftRefresh++}){Text("Discard draft")}}}}}
                        items(savedDecks.chunked(libraryColumns),key={"saved-row-${it.first().id}"}) { group -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){group.forEach{saved->Box(Modifier.weight(1f)){DeckTile(saved.deck,"Saved on this device",saved,{editor=EditorRequest(saved.deck,saved)},{play=saved.deck},{organize=saved},{model.duplicate(saved)},{delete=saved},compact=libraryColumns>1)}};repeat(libraryColumns-group.size){Spacer(Modifier.weight(1f))}} }
                        item { Text("Included Commander decks",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif) }
                        val precons=state.precons.filter { deck->!favoritesOnly&&(libraryQuery.isBlank() || deck.name.contains(libraryQuery,true) || deck.entries.any {it.section=="commanders" && it.name.contains(libraryQuery,true)}) }
                        items(precons.chunked(libraryColumns),key={"precon-row-${it.first().name}"}) { group -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){group.forEach{deck->Box(Modifier.weight(1f)){DeckTile(deck,"Included · edit a local copy",null,{editor=EditorRequest(deck)},{play=deck},{},{},{},compact=libraryColumns>1)}};repeat(libraryColumns-group.size){Spacer(Modifier.weight(1f))}} }
                        item { HorizontalDivider();Text("Private playtest history",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)
                            Row(verticalAlignment=Alignment.CenterVertically){Switch(checked=state.recordingEnabled,onCheckedChange=model::setRecording);Spacer(Modifier.width(10.dp));Column{Text(if(state.recordingEnabled)"Recording summaries" else "Recording off");Text("Device-only, bounded to 100 games; no hands or opponent decklists.",style=MaterialTheme.typography.bodySmall)}}
                            if(state.playtests.isEmpty())Text("No recorded playtests.",style=MaterialTheme.typography.bodySmall)
                        }
                        items(state.playtests.take(12),key={it.id}) { row->OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(row.deckName,style=MaterialTheme.typography.titleMedium);Text("${row.end.replace('_',' ')} · highest observed turn ${row.highestTurn} · AI skill ${row.aiSkill}",style=MaterialTheme.typography.bodySmall);if(row.commanderCasts.isNotEmpty())Text(row.commanderCasts.entries.joinToString {"${it.key}: ${it.value} cast(s)"},style=MaterialTheme.typography.bodySmall)}} }
                        if(state.playtests.isNotEmpty())item{PlaytestHistoryActions(model::clearPlaytests)}
                        item {Text("Appearance",style=MaterialTheme.typography.titleMedium);Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){listOf("System","Light","Dark").forEach{mode->FilterChip(selected=appearance==mode,onClick={appearance=mode;libraryPreferences.edit().putString("appearance",mode).apply()},label={Text(mode)})}}}
                        item { ArtworkConsentRow() }
                        item { Text(state.status,style=MaterialTheme.typography.bodySmall);Text("Games run locally with the packaged XMage engine. No external computer or account. Cross-device multiplayer is not in this Android alpha.",style=MaterialTheme.typography.bodySmall) }
                    }
                }
            }
        }
        if(importing) ImportDialog({importing=false}) { preview -> importing=false;importPreview=preview }
        importPreview?.let {preview->DeckImportPreviewDialog(preview,{importPreview=null}){editor=EditorRequest(preview.deck,receipt=ImportReceipt("Text import",preview.originalText,preview.annotations,preview.deck));model.recover(preview.deck);importPreview=null}}
        if(importingLink)DeckLinkDialog({importingLink=false}){deck,source->importingLink=false;editor=EditorRequest(deck,receipt=ImportReceipt(source,"",emptyList(),deck));model.recover(deck)}
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
@Composable private fun DeckTile(deck:Deck,subtitle:String,saved:SavedDeck?,edit:()->Unit,play:()->Unit,organize:()->Unit,duplicate:()->Unit,delete:()->Unit,compact:Boolean=false) {
    var menu by remember{mutableStateOf(false)}
    Card(Modifier.fillMaxWidth()){Column(Modifier.padding(if(compact)12.dp else 18.dp)){Text(deck.name,style=if(compact)MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)
        Text(deck.entries.filter { it.section=="commanders" }.joinToString(" + "){it.name},style=MaterialTheme.typography.bodyMedium)
        Text("${if(saved?.favorite==true)"★ · " else ""}${deck.entries.sumOf { it.quantity }} cards · $subtitle",style=MaterialTheme.typography.bodySmall)
        if(!saved?.tags.isNullOrEmpty())Text(saved!!.tags.joinToString(" · "),style=MaterialTheme.typography.labelSmall)
        if(compact){TextButton(onClick=edit){Text("Open deck")};Box{TextButton(onClick={menu=true}){Text("Deck actions")};DropdownMenu(expanded=menu,onDismissRequest={menu=false}){DropdownMenuItem(text={Text("Playtest")},onClick={menu=false;play()});if(saved!=null){DropdownMenuItem(text={Text("Organize")},onClick={menu=false;organize()});DropdownMenuItem(text={Text("Copy")},onClick={menu=false;duplicate()});DropdownMenuItem(text={Text("Delete")},onClick={menu=false;delete()})}}}}
        else{Row {TextButton(onClick=edit){Text("Open")};TextButton(onClick=play){Text("Playtest")}}
        if(saved!=null)Row {TextButton(onClick=organize){Text("Organize")};TextButton(onClick=duplicate){Text("Copy")};TextButton(onClick=delete){Text("Delete")}}}}}
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
@Composable private fun ImportDialog(close:()->Unit,import:(DeckTextPreview)->Unit) {
    var name by remember {mutableStateOf("Imported Commander deck")};var text by remember {mutableStateOf("")};var error by remember {mutableStateOf<String?>(null)}
    AlertDialog(onDismissRequest=close,title={Text("Paste a decklist")},text={Column(Modifier.verticalScroll(rememberScrollState())) {
        OutlinedTextField(value=name,onValueChange={name=it.take(300)},label={Text("Deck name")})
        OutlinedTextField(value=text,onValueChange={if(it.length<200000)text=it},label={Text("Commander\n1 Card Name\n\nDeck\n1 Sol Ring")},modifier=Modifier.heightIn(min=240.dp))
        Text("Export plain card names and counts from Archidekt or ManaBox. Unrecognized rows are reported, never silently dropped. Name support and Commander legality are checked separately.",style=MaterialTheme.typography.bodySmall)
        error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
    }},confirmButton={TextButton(onClick={try{import(DeckTextImport.preview(name,text))}catch(e:Exception){error=e.message}}){Text("Review draft")}},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}
@Composable private fun DeckEditor(model:AppModel,state:ScreenState,initial:Deck,original:SavedDeck?,draftID:String,incomingReceipt:ImportReceipt?,close:()->Unit,play:(Deck)->Unit) {
    val draftStore=remember{DeckDraftStore(model.getApplication())}
    val receipts=remember{ReceiptStore(model.getApplication())}
    val receiptRead=remember(draftID){runCatching{incomingReceipt?.also{receipts.write(draftID,it)} ?: receipts.read(draftID)}}
    var showReceipt by remember{mutableStateOf(false)}
    var showInsights by remember{mutableStateOf(false)}
    val restoration=remember(draftID){runCatching{draftStore.read(draftID)}}
    var draft by remember(initial,original){mutableStateOf(restoration.getOrNull()?.takeIf{it.baseRevision==original?.revision}?.deck ?: initial)}
    var saveTarget by remember(draftID){mutableStateOf(original)}
    var saveInFlight by remember(draftID){mutableStateOf(false)}
    var undo by remember(initial){mutableStateOf(emptyList<Deck>())};var redo by remember(initial){mutableStateOf(emptyList<Deck>())}
    var search by remember {mutableStateOf("")};var results by remember {mutableStateOf(emptyList<CardInfo>())}
    var section by remember {mutableStateOf("deck")};var message by remember {mutableStateOf<String?>(null)}
    var exclude by remember {mutableStateOf(false)}
    var title by remember(initial){mutableStateOf(initial.name)}
    var basics by remember {mutableStateOf(false)}
    var cardDetail by remember {mutableStateOf<String?>(null)}
    var replacing by remember {mutableStateOf<Int?>(null)}
    var rowFilter by remember {mutableStateOf("")}
    var rowSort by remember {mutableStateOf("Name")}
    var grouping by remember {mutableStateOf("Board")}
    val context=LocalContext.current
    var exportContent by remember{mutableStateOf("")}
    fun exportResult(uri:Uri?){if(uri!=null)runCatching{context.contentResolver.openOutputStream(uri)?.use{it.write(exportContent.toByteArray())}?:error("Unable to open selected file")}.onSuccess{message="Deck exported."}.onFailure{message="Export failed: ${it.message}"}}
    val exportJSON=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json"),::exportResult)
    val exportText=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain"),::exportResult)
    BackHandler(enabled=saveInFlight){}
    fun change(next:Deck){undo=(undo+draft).takeLast(50);redo=emptyList();draft=next;title=next.name;replacing=null;model.invalidateValidation();model.recover(next)}
    LaunchedEffect(initial,original?.revision){model.invalidateValidation()}
    LaunchedEffect(draft){title=draft.name;replacing=null}
    val draftWritable=restoration.isSuccess&&(original==null||restoration.getOrNull()==null||restoration.getOrNull()?.baseRevision==original.revision)
    var persistedDraft by remember(draftID){mutableStateOf<Deck?>(null)}
    SideEffect{if(persistedDraft!=draft)runCatching{check(draftWritable){"An older or unreadable draft is preserved. Return to the library and open it as a copy before saving this deck."};draftStore.write(draftID,saveTarget?.revision,draft,saveTarget?.id);persistedDraft=draft}.onFailure{message=it.message}}
    LaunchedEffect(search){results=withContext(Dispatchers.Default){model.catalogue?.search(search).orEmpty()}}
    val analysis=remember(draft,model.catalogue){model.catalogue?.let {DeckAnalyzer.analyze(draft,it)}}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        item {Text("Deck Studio",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif)
            OutlinedTextField(value=title,onValueChange={title=it.take(300)},label={Text("Deck name")},modifier=Modifier.fillMaxWidth())
            Row {TextButton(enabled=title.isNotBlank(),onClick={change(draft.copy(name=title))}){Text("Rename")};TextButton(enabled=!saveInFlight,onClick={model.recover(draft);close()}){Text("Back · keep draft")}}
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(enabled=draftWritable&&receiptRead.isSuccess&&!state.busy&&!saveInFlight,onClick={
                if(!saveInFlight){saveInFlight=true;val submitted=draft;model.save(submitted,saveTarget,onFailure={Handler(Looper.getMainLooper()).post{saveInFlight=false}}){saved->
                    val copied=runCatching{receipts.copy(draftID,saved.id)}
                    Handler(Looper.getMainLooper()).post {
                        saveTarget=saved
                        if(copied.isSuccess&&draft==submitted){
                            val cleaned=runCatching{draftStore.delete(draftID);if(draftID!=saved.id)receipts.delete(draftID)}
                            if(cleaned.isSuccess)close() else{persistedDraft=null;message="Deck saved. Draft cleanup failed; retry Save to finish cleanup."}
                        }else{
                            persistedDraft=null;runCatching{draftStore.write(draftID,saved.revision,draft,saved.id)}
                            message=if(copied.isFailure)"Deck saved, but its source receipt could not be copied. Retry Save to update this same deck; the draft and receipt are preserved." else "Saved. Your newer edits remain in this draft."
                        }
                        saveInFlight=false
                    }
                }}
            }){Text(if(saveInFlight)"Saving…" else "Save deck")};OutlinedButton(enabled=!saveInFlight,onClick={play(draft)}){Text("Playtest")};OutlinedButton(enabled=BuildConfig.NATIVE_ENGINE&&!state.busy&&!saveInFlight,onClick={model.validate(draft,exclude)}){Text("Validate")}}
            if(receiptRead.getOrNull()!=null)TextButton(onClick={showReceipt=true}){Text("Import source & annotations")}
            TextButton(onClick={exportContent=io.magicmobile.core.Json.write(mapOf("format" to "magicmobile-deck-v1","deck" to draft.json()));exportJSON.launch("magicmobile-deck.json")}){Text("Export deck JSON")}
            if(receiptRead.isFailure)Text("Import receipt could not be read or saved. Source files are preserved.",color=MaterialTheme.colorScheme.error)
            Row{TextButton(enabled=undo.isNotEmpty(),onClick={redo=redo+draft;draft=undo.last();undo=undo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Undo")};TextButton(enabled=redo.isNotEmpty(),onClick={undo=undo+draft;draft=redo.last();redo=redo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Redo")};TextButton(onClick={exportContent=draft.export();exportText.launch("magicmobile-deck.txt")}){Text("Export text")}}
            if(draft.entries.any {it.section !in setOf("deck","commanders","companions")})Row(verticalAlignment=Alignment.CenterVertically){Checkbox(checked=exclude,onCheckedChange={exclude=it;model.invalidateValidation()});Text("Validate without other boards")}
            state.validation?.takeIf {model.validationApplies(draft,exclude)}?.let {report->Text(report.summary,color=if(report.valid)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error);report.issues.take(20).forEach{Text("• ${it.cardName?.let {name->"$name: "}.orEmpty()}${it.message}",style=MaterialTheme.typography.bodySmall)}}
            message?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        }
        item {OutlinedTextField(value=search,onValueChange={search=it.take(200)},label={Text("Add cards · name or rules text")},modifier=Modifier.fillMaxWidth())
            if(replacing!=null)Row {Text("Choose a replacement for ${draft.entries.getOrNull(replacing!!)?.name.orEmpty()}",modifier=Modifier.weight(1f));TextButton(onClick={replacing=null}){Text("Cancel")}}
            Row {listOf("deck","commanders","maybeboard").forEach{target->FilterChip(selected=section==target,onClick={section=target},label={Text(target)})}}}
        items(results,key={"search-${it.name}"}) { card -> OutlinedCard(Modifier.fillMaxWidth()){Row(Modifier.padding(10.dp),verticalAlignment=Alignment.CenterVertically){CardArtwork(card.name,Modifier.size(38.dp,52.dp).clip(RoundedCornerShape(4.dp)).clickable{cardDetail=card.name}){Text(card.name.take(1),style=MaterialTheme.typography.labelSmall)};Spacer(Modifier.width(10.dp));Column(Modifier.weight(1f).clickable{cardDetail=card.name}){Text(card.name);Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){ManaCost(card.cost);Text(card.type.orEmpty(),style=MaterialTheme.typography.bodySmall)}};TextButton(onClick={try{change(replacing?.let {DeckEditing.replace(draft,it,card.name)} ?: draft.copy(entries=draft.entries+CardEntry(card.name,1,section)));message=null}catch(e:Exception){message=e.message}}){Text(if(replacing!=null)"Replace" else "+ Add")}}} }
        if(search.isNotBlank())item{Text("Local compiled catalogue · up to 80 results",style=MaterialTheme.typography.bodySmall)}
        analysis?.let { facts->item {OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){
            Text("Deck analysis",style=MaterialTheme.typography.titleMedium)
            TextButton(onClick={showInsights=true}){Text("Roles, targets & draw probabilities")}
            Text("${facts.mainCardCount} main cards · ${facts.landCount} lands · average nonland mana ${facts.averageNonlandManaValue?.let {String.format(Locale.US,"%.2f",it)} ?: "unknown"}")
            Text("Curve 0–7+: "+facts.manaCurveBins.entries.joinToString(" · "){"${it.key}${if(it.key==7)"+" else ""}: ${it.value}"},style=MaterialTheme.typography.bodySmall)
            val roles=facts.roles.filterValues {it.count>0};if(roles.isNotEmpty())Text(roles.entries.joinToString(" · "){"${it.key.name.lowercase().replace('_',' ')} ${it.value.count}"},style=MaterialTheme.typography.bodySmall)
            if(facts.unknownNameCount>0)Text("${facts.unknownNameCount} unresolved card(s): ${facts.unknownNames.take(8).joinToString()}",color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)
            Text("Catalogue facts only—not a power score, mana-source estimate, simulation, or legality result.",style=MaterialTheme.typography.labelSmall)
        }}}}
        item {OutlinedTextField(value=rowFilter,onValueChange={rowFilter=it.take(200)},label={Text("Filter cards in this deck")},modifier=Modifier.fillMaxWidth());Row{TextButton(onClick={basics=true}){Text("Basic lands")};TextButton(onClick={rowSort=if(rowSort=="Name")"Mana" else "Name"}){Text("Sort: $rowSort")};TextButton(onClick={grouping=if(grouping=="Board")"Type" else "Board"}){Text("Group: $grouping")}}}
        draft.entries.withIndex().filter {it.value.name.contains(rowFilter,true)}.sortedWith(compareBy<IndexedValue<CardEntry>>{if(rowSort=="Mana")model.catalogue?.find(it.value.name)?.manaValue ?: Double.MAX_VALUE else 0.0}.thenBy{it.value.name.lowercase()}).groupBy{row->row.value.section+if(grouping=="Type")" · "+(model.catalogue?.find(row.value.name)?.types?.firstOrNull()?.lowercase() ?: "unknown") else ""}.forEach { (section,rows) ->
            item(key="header-$section"){Text("${section.replaceFirstChar{it.uppercase()}} · ${rows.sumOf {it.value.quantity}}",style=MaterialTheme.typography.titleMedium)}
            items(rows,key={"row-${it.index}"}) { (index,row) -> Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(row.name,modifier=Modifier.clickable{cardDetail=row.name});model.catalogue?.find(row.name).let { info -> if(info?.cost != null) ManaCost(info.cost) else Text(if(info==null) "Unresolved in local catalogue" else info.type.orEmpty(),style=MaterialTheme.typography.bodySmall) }
                Row {TextButton(onClick={try{change(draft.change(index,-1))}catch(e:Exception){message=e.message}}){Text("−")};Text("${row.quantity}",modifier=Modifier.padding(12.dp));TextButton(onClick={try{change(draft.change(index,1))}catch(e:Exception){message=e.message}}){Text("+")}
                    TextButton(onClick={val destination=if(row.section=="commanders")"deck" else "commanders";change(DeckEditing.move(draft,index,destination))}){Text(if(row.section=="commanders")"To main" else "Commander")}}
                Row{TextButton(onClick={replacing=index;search=row.name}){Text("Replace")};TextButton(onClick={change(DeckEditing.move(draft,index,if(row.section=="maybeboard")"deck" else "maybeboard"))}){Text(if(row.section=="maybeboard")"To main" else "Maybeboard")};TextButton(onClick={change(draft.copy(entries=draft.entries.filterIndexed{i,_->i!=index}))}){Text("Remove")}}
            }} }
        }
        item {model.catalogue?.let {catalogue->ProviderDiscoveryPanel(draft,catalogue,readOnly=!draftWritable){name,target->try{change(draft.copy(entries=draft.entries+CardEntry(name,1,target)));true}catch(error:Exception){message=error.message;false}}}}
    }
    if(basics)BasicLandsDialog(draft,{basics=false},::change)
    cardDetail?.let {CatalogueCardDialog(it,model.catalogue){cardDetail=null}}
    if(showReceipt)receiptRead.getOrNull()?.let{receipt->ImportReceiptDialog(receipt,{showReceipt=false})}
    if(showInsights)model.catalogue?.let{DeckInsightsDialog(draft,it,saveTarget?.id){showInsights=false}}
}
