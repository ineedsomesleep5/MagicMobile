package io.magicmobile.android

import android.net.Uri
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.core.view.WindowCompat
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
    private val onDevice: io.magicmobile.android.ondevice.OnDeviceViewModel by viewModels()
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState);enableEdgeToEdge()
        val extras=DesignPreview.extras(intent)
        io.magicmobile.android.ui.LaunchEnvironment.load(this,extras)
        // UI previews and tests use their own preferences, like iOS's MAGICMOBILE_UI_TEST_PREFERENCES suite.
        io.magicmobile.android.ui.AppPreferences.init(this,extras["MAGICMOBILE_UI_TEST_PREFERENCES"]?.let{"magicmobile.preferences.$it"} ?: "magicmobile.preferences")
        io.magicmobile.android.ui.GameAudio.init(this)
        // Menus and the board are always dark, like the iOS app.
        WindowCompat.getInsetsController(window,window.decorView).apply{isAppearanceLightStatusBars=false;isAppearanceLightNavigationBars=false}
        io.magicmobile.android.studio.DeckStudioServices.install(this)
        if(DesignPreview.active) setContent { DesignPreviewHost() }
        else setContent { io.magicmobile.android.ondevice.OnDeviceRoot(onDevice) }
    }
}
private enum class AppPage(val title:String){HOME("MagicMobile"),DECKS("Deck Studio"),DOWNLOADS("Downloads"),SETTINGS("Settings"),UPDATES("Updates"),ONLINE("Online play")}
private data class EditorRequest(val deck:Deck,val original:SavedDeck?=null,val draftID:String=original?.id ?: java.util.UUID.randomUUID().toString(),val receipt:ImportReceipt?=null)
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MagicApp(model:AppModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val onlineState by model.online.collectAsStateWithLifecycle()
    var editor by remember { mutableStateOf<EditorRequest?>(null) }
    var importing by remember { mutableStateOf(false) }
    var importingLink by remember { mutableStateOf(false) }
    var importPreview by remember { mutableStateOf<DeckTextPreview?>(null) }
    var play by remember { mutableStateOf<Deck?>(null) }
    var inspect by remember { mutableStateOf<String?>(null) }
    var organize by remember { mutableStateOf<SavedDeck?>(null) }
    var delete by remember { mutableStateOf<SavedDeck?>(null) }
    var libraryQuery by remember { mutableStateOf("") }
    var libraryScope by remember { mutableStateOf("All") }
    var librarySort by remember { mutableStateOf("Recently edited") }
    var page by rememberSaveable { mutableStateOf(AppPage.HOME) }
    val context=LocalContext.current
    val libraryPreferences=remember{context.getSharedPreferences("magicmobile.library",android.content.Context.MODE_PRIVATE)}
    var libraryGrid by remember{mutableStateOf(libraryPreferences.getBoolean("grid",true))}
    var appearance by remember{mutableStateOf(libraryPreferences.getString("appearance","System")?.takeIf{it in setOf("System","Light","Dark")} ?: "System")}
    var selectedDeckKey by remember{mutableStateOf(libraryPreferences.getString("selectedDeck",null))}
    fun selectDeck(key:String){selectedDeckKey=key;libraryPreferences.edit().putString("selectedDeck",key).apply()}
    val configuration=LocalConfiguration.current
    val libraryColumns=if(libraryGrid&&configuration.fontScale<1.3f)(configuration.screenWidthDp/180).coerceIn(1,3) else 1
    val drafts=remember {DeckDraftStore(context)}
    var draftRefresh by remember {mutableIntStateOf(0)}
    val draftRead=remember(editor,draftRefresh){runCatching{drafts.all()}}
    val draftRecords=draftRead.getOrDefault(emptyList())
    val fileImport=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) {uri->
        if(uri!=null)runCatching {
            val bytes=context.contentResolver.openInputStream(uri)?.use {readBounded(it,2*1024*1024)} ?: error("Unable to open that file")
            DeckTextImport.preview("Imported Commander deck",DeckTextImport.strictUTF8(bytes))
        }.onSuccess {importPreview=it}.onFailure {model.error(it.message ?: "Unable to import that file")}
    }
    val forcedDark=editor==null&&(state.playing||page==AppPage.HOME)
    val dark=forcedDark||(editor==null&&(appearance=="Dark"||(appearance=="System"&&isSystemInDarkTheme())))
    val view=LocalView.current
    val darkChrome=dark
    SideEffect{(view.context as? android.app.Activity)?.let{activity->WindowCompat.getInsetsController(activity.window,view).apply{isAppearanceLightStatusBars=!darkChrome;isAppearanceLightNavigationBars=!darkChrome}}}
    val colors=if(dark)darkColorScheme(primary=Color(0xFFB7D6C8),background=Night,surface=Color(0xFF1C2823),onBackground=Parchment,onSurface=Parchment) else lightColorScheme(primary=Ink,background=Cream,surface=Color(0xFFFFFCF6),onBackground=Ink,onSurface=Ink)
    MaterialTheme(colorScheme=colors) {
        val snackbar=remember{SnackbarHostState()}
        LaunchedEffect(state.error){state.error?.let{message->val action=snackbar.showSnackbar(message.take(400),actionLabel=if(state.closing)"Retry" else null,withDismissAction=true);model.error(null);if(action==SnackbarResult.ActionPerformed)model.close()}}
        BackHandler(enabled=editor==null&&!state.playing&&page!=AppPage.HOME){page=AppPage.HOME}
        BackHandler(enabled=editor!=null){if(!state.busy){editor?.deck?.let(model::recover);editor=null;draftRefresh++}}
        Scaffold(
            snackbarHost={SnackbarHost(snackbar)},
            contentWindowInsets=WindowInsets.safeDrawing,
            containerColor=if(editor==null&&!state.playing&&page==AppPage.HOME)Night else MaterialTheme.colorScheme.background,
            topBar={if(editor==null&&!state.playing&&page!=AppPage.HOME&&page!=AppPage.DOWNLOADS)TopAppBar(
                title={Text(page.title,fontFamily=FontFamily.Serif)},
                navigationIcon={TextButton(onClick={page=AppPage.HOME}){Text("Back")}},
            )}
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).background(MaterialTheme.colorScheme.background)) {
                if(!BuildConfig.NATIVE_ENGINE) Text("DIAGNOSTIC BUILD · No native engine. Deck editing only; cannot play.",color=MaterialTheme.colorScheme.error,modifier=Modifier.padding(12.dp))
                when {
                    state.playing -> GameScreen(model,state) { inspect=it }
                    editor!=null -> DeckEditor(model,state,editor!!.deck,editor!!.original,editor!!.draftID,editor!!.receipt,{editor=null;draftRefresh++},{play=it})
                    !state.loaded -> { LinearProgressIndicator(Modifier.fillMaxWidth());Text(state.status,modifier=Modifier.padding(20.dp)) }
                    page==AppPage.HOME -> HomeScreen(
                        featured=state.decks.firstOrNull{it.id==selectedDeckKey}?.deck ?: state.precons.firstOrNull{"included:${it.name}"==selectedDeckKey} ?: state.decks.firstOrNull()?.deck ?: state.precons.firstOrNull(),
                        play={play=it},decks={page=AppPage.DECKS},downloads={page=AppPage.DOWNLOADS},settings={page=AppPage.SETTINGS},updates={page=AppPage.UPDATES},online={page=AppPage.ONLINE},
                    )
                    page==AppPage.DOWNLOADS -> ArtworkDownloadsScreen(model.catalogue,state.decks,state.precons,{page=AppPage.HOME}){message->model.error(message)}
                    page==AppPage.SETTINGS -> SettingsScreen(appearance,{mode->appearance=mode;libraryPreferences.edit().putString("appearance",mode).apply()},state,model)
                    page==AppPage.UPDATES -> UpdatesScreen()
                    page==AppPage.ONLINE -> OnlineScreen(model,state)
                    else -> LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                        item { Text("My Decks",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif);Text("Build. Refine. Play.",style=MaterialTheme.typography.bodyMedium) }
                        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onClick={editor=EditorRequest(Deck("New Commander deck",emptyList()))}){Text("Create deck")};OutlinedButton(onClick={importing=true}){Text("Paste")};OutlinedButton(onClick={fileImport.launch(arrayOf("application/json","text/plain","text/*","application/octet-stream"))}){Text("Import file")}} }
                        item { OutlinedTextField(value=libraryQuery,onValueChange={libraryQuery=it.take(200)},label={Text("Search decks, commanders, or tags")},modifier=Modifier.fillMaxWidth()) }
                        item {TextButton(onClick={importingLink=true}){Text("Import public deck link")}}
                        item {DeckPhotoImportButton{deck,receipt->editor=EditorRequest(deck,receipt=receipt);model.recover(deck)}}
                        item {DeckChoice("Library",libraryScope,listOf("All","Favorites","My decks","Included")){libraryScope=it};DeckChoice("Sort",librarySort,listOf("Recently edited","Name","Commander")){librarySort=it};TextButton(onClick={libraryGrid=!libraryGrid;libraryPreferences.edit().putBoolean("grid",libraryGrid).apply()}){Text(if(libraryGrid)"Show list" else "Show grid")} }
                        if(state.recovered!=null) item { OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)){Text("Recovered draft: ${state.recovered!!.name}");Row { TextButton(onClick={editor=EditorRequest(state.recovered!!)}){Text("Open as copy")};TextButton(onClick={model.discardRecovery()}){Text("Discard recovery")}}} } }
                        val savedDecks=state.decks.filter { saved->libraryScope!="Included"&&(libraryScope!="Favorites"||saved.favorite)&&(libraryQuery.isBlank() || listOf(saved.deck.name,saved.tags.joinToString(" "),saved.deck.entries.filter {it.section=="commanders"}.joinToString(" "){it.name}).any {it.contains(libraryQuery,true)}) }.let { rows->when(librarySort){"Recently edited"->rows.sortedByDescending(SavedDeck::modifiedAtMillis);"Commander"->rows.sortedWith(compareBy<SavedDeck>{it.deck.entries.firstOrNull{row->row.section=="commanders"}?.name?.lowercase().orEmpty()}.thenBy{it.deck.name.lowercase()});else->rows.sortedBy{it.deck.name.lowercase()}} }
                        if(savedDecks.isEmpty()&&libraryScope!="Included")item{Text("No saved decks match. Create a deck or change your filters.")}
                        if(draftRecords.isNotEmpty())item{Text("Unfinished drafts",style=MaterialTheme.typography.titleMedium)}
                        if(draftRead.isFailure)item{Text("A draft could not be read. Draft files are preserved on this device.",color=MaterialTheme.colorScheme.error)}
                        items(draftRecords,key={"draft-${it.id}"}){record->OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(record.deck.name);Row{TextButton(onClick={val original=state.decks.firstOrNull{it.id==(record.savedID?:record.id)&&it.revision==record.baseRevision};editor=EditorRequest(record.deck,original,record.id)}){Text(if(state.decks.any{it.id==(record.savedID?:record.id)&&it.revision==record.baseRevision})"Resume draft" else "Open draft as copy")};TextButton(onClick={runCatching{if(state.decks.none{it.id==record.id})ReceiptStore(context).delete(record.id);drafts.delete(record.id)}.onFailure{model.error("Unable to discard draft: ${it.message}")};draftRefresh++}){Text("Discard draft")}}}}}
                        items(savedDecks.chunked(libraryColumns),key={"saved-row-${it.first().id}"}) { group -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){group.forEach{saved->Box(Modifier.weight(1f)){DeckTile(saved.deck,"Saved on this device",saved,{selectDeck(saved.id);editor=EditorRequest(saved.deck,saved)},{selectDeck(saved.id);play=saved.deck},{organize=saved},{model.duplicate(saved)},{delete=saved},selected=selectedDeckKey==saved.id,compact=libraryColumns>1,catalogue=model.catalogue)}};repeat(libraryColumns-group.size){Spacer(Modifier.weight(1f))}} }
                        val precons=state.precons.filter { deck->libraryScope in setOf("All","Included")&&(libraryQuery.isBlank() || deck.name.contains(libraryQuery,true) || deck.entries.any {it.section=="commanders" && it.name.contains(libraryQuery,true)}) }.let { rows->if(librarySort=="Commander")rows.sortedWith(compareBy<Deck>{it.entries.firstOrNull{row->row.section=="commanders"}?.name?.lowercase().orEmpty()}.thenBy{it.name.lowercase()}) else rows.sortedBy{it.name.lowercase()} }
                        if(precons.isNotEmpty())item { Text("Included Commander decks",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif) }
                        if(precons.isEmpty()&&libraryScope=="Included")item{Text("No included decks match your search.")}
                        items(precons.chunked(libraryColumns),key={"precon-row-${it.first().name}"}) { group -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){group.forEach{deck->val key="included:${deck.name}";Box(Modifier.weight(1f)){DeckTile(deck,"Included · edit a local copy",null,{selectDeck(key);editor=EditorRequest(deck)},{selectDeck(key);play=deck},{},{},{},selected=selectedDeckKey==key,compact=libraryColumns>1,catalogue=model.catalogue)}};repeat(libraryColumns-group.size){Spacer(Modifier.weight(1f))}} }
                        item {TextButton(onClick={page=AppPage.SETTINGS},modifier=Modifier.fillMaxWidth()){Text("Appearance, playtest history & privacy")}}
                    }
                }
            }
        }
        if(state.onlineGame&&onlineState.userId==null)OnlineSignInRecovery(model,onlineState)
        if(importing) ImportDialog({importing=false}) { preview -> importing=false;importPreview=preview }
        importPreview?.let {preview->DeckImportPreviewDialog(preview,{importPreview=null}){editor=EditorRequest(preview.deck,receipt=ImportReceipt("Text import",preview.originalText,preview.annotations,preview.deck));model.recover(preview.deck);importPreview=null}}
        if(importingLink)DeckLinkDialog({importingLink=false}){deck,source->importingLink=false;editor=EditorRequest(deck,receipt=ImportReceipt(source,"",emptyList(),deck));model.recover(deck)}
        if(play!=null) {
            val deck=play!!;val preferences=remember {context.getSharedPreferences("magicmobile.play",android.content.Context.MODE_PRIVATE)}
            var ai by remember { mutableIntStateOf(1) };var aiSkill by remember { mutableIntStateOf(preferences.getInt("aiSkill",2).coerceIn(1,10)) };var exclude by remember { mutableStateOf(false) }
            var playerName by remember {mutableStateOf(preferences.getString("playerName","You")?.take(24) ?: "You")}
            var opponents by remember(deck,state.precons) {mutableStateOf(defaultAiDecks(state.precons))}
            // Read the collected receipt here, not only the model's unobserved
            // StateFlow value: this scope must recompose when validation finishes.
            val validated=state.validation?.let{model.validationMatches(deck,exclude)}==true
            ModalBottomSheet(onDismissRequest={if(!state.busy)play=null}) {Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal=24.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                Text("Start local Commander",style=MaterialTheme.typography.headlineSmall)
                ArtworkConsentRow()
                Text(deck.name,style=MaterialTheme.typography.titleMedium,maxLines=2,overflow=TextOverflow.Ellipsis);Text("XMage validates the deck while starting. Parsing alone is not Commander legality.")
                OutlinedTextField(value=playerName,onValueChange={playerName=it.filterNot(Char::isISOControl).take(24);preferences.edit().putString("playerName",playerName).apply()},label={Text("Player name")},singleLine=true,modifier=Modifier.fillMaxWidth())
                Row {TextButton(onClick={ai=(ai-1).coerceAtLeast(1)}){Text("−")};Text("$ai AI opponent(s)",modifier=Modifier.padding(12.dp));TextButton(onClick={ai=(ai+1).coerceAtMost(3)}){Text("+")}}
                Text("AI skill · $aiSkill");Slider(value=aiSkill.toFloat(),onValueChange={aiSkill=it.toInt().coerceIn(1,10);preferences.edit().putInt("aiSkill",aiSkill).apply()},valueRange=1f..10f,steps=8)
                if(state.precons.isNotEmpty()) {
                    Text("Choose an included deck for each AI seat.",style=MaterialTheme.typography.bodySmall)
                    repeat(ai) {seat->
                        DeckChoice("AI ${seat+1} deck",opponents[seat].name,state.precons.map(Deck::name)){name->opponents=replaceAiDeck(opponents,seat,state.precons.first {it.name==name})}
                    }
                }
                if(deck.entries.any { it.section !in setOf("deck","commanders","companions") })Row {Checkbox(checked=exclude,onCheckedChange={exclude=it;model.invalidateValidation()});Text("Exclude other boards from this game only. Keep source draft intact.")}
                state.validation?.takeIf{model.validationApplies(deck,exclude)}?.let{report->Text(if(report.valid)"Commander validation passed for this exact deck and engine." else report.summary,color=if(report.valid)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall);report.issues.take(8).forEach{Text(it.message,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)}}
                if(state.validation==null)Text("Validate this exact playing deck before starting.",style=MaterialTheme.typography.bodySmall)
                if(state.busy){LinearProgressIndicator(Modifier.fillMaxWidth());Text(state.status,style=MaterialTheme.typography.bodySmall)}
                Text("This alpha has no durable game resume after Android kills the process.",style=MaterialTheme.typography.bodySmall)
                if(validated)Button(enabled=!state.busy && opponents.size>=ai&&playerName.trim().isNotEmpty(),onClick={model.start(deck,activeAiDecks(opponents,ai),exclude,aiSkill,playerName);play=null},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)){Text("Start local game")}
                else Button(enabled=BuildConfig.NATIVE_ENGINE&&!state.busy,onClick={model.validate(deck,exclude)},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)){Text("Validate deck")}
                TextButton(onClick={play=null},enabled=!state.busy,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){Text("Cancel")}
                Spacer(Modifier.height(12.dp))
            }}
        }
        organize?.let { saved->OrganizationDialog(saved,{organize=null}) {favorite,tags,notes->model.organize(saved,favorite,tags,notes);organize=null} }
        delete?.let {saved->AlertDialog(onDismissRequest={delete=null},title={Text("Delete ${saved.deck.name}?")},text={Text("This removes the local deck. Playtest summaries are retained until you clear their separate history.")},confirmButton={TextButton(onClick={model.delete(saved);delete=null}){Text("Delete")}},dismissButton={TextButton(onClick={delete=null}){Text("Cancel")}})}
        if(inspect!=null) {
            val card=model.catalogue?.find(inspect!!)
            AlertDialog(onDismissRequest={inspect=null},title={Text(inspect!!)},text={Column(Modifier.verticalScroll(rememberScrollState())) {CardArtwork(inspect!!,Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(10.dp))){ArtworkHint()};Spacer(Modifier.height(10.dp));ManaCost(card?.cost,size=20);Text(card?.type.orEmpty());ManaText(Decisions.plain(card?.rules ?: "No local metadata for this object."))}},confirmButton={TextButton(onClick={inspect=null}){Text("Done")}})
        }
    }
}
@Composable private fun HomeScreen(featured:Deck?,play:(Deck)->Unit,decks:()->Unit,downloads:()->Unit,settings:()->Unit,updates:()->Unit,online:()->Unit) {
    BoxWithConstraints(Modifier.fillMaxSize().background(Night)) {
        val wide=maxWidth>=700.dp
        if(wide)Row(Modifier.fillMaxSize().padding(40.dp),horizontalArrangement=Arrangement.spacedBy(36.dp),verticalAlignment=Alignment.CenterVertically) {
            Column(Modifier.weight(.9f).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(14.dp)){HomeHeading();HomeNavigation(featured,play,decks,downloads,settings,updates,online,wide=true)}
            Column(Modifier.weight(1.1f).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)){HomeDeck(featured)}
        } else Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            Spacer(Modifier.height(22.dp));HomeHeading();HomeDeck(featured);HomeNavigation(featured,play,decks,downloads,settings,updates,online,wide=false);Spacer(Modifier.height(28.dp))
        }
    }
}
@Composable private fun HomeHeading(){Text("MAGICMOBILE",style=MaterialTheme.typography.headlineLarge,fontFamily=FontFamily.Serif,color=Parchment);Text("Your next great game.",style=MaterialTheme.typography.titleMedium,color=Parchment.copy(alpha=.78f))}
@Composable private fun HomeDeck(featured:Deck?){featured?.let{deck->CardArtwork(deck.entries.firstOrNull{it.section=="commanders"}?.name.orEmpty(),Modifier.fillMaxWidth().heightIn(min=220.dp,max=360.dp).clip(RoundedCornerShape(16.dp))){ArtworkCoverPlaceholder()};Text(deck.name,style=MaterialTheme.typography.headlineSmall,fontFamily=FontFamily.Serif,color=Parchment,maxLines=2,overflow=TextOverflow.Ellipsis);Text(deck.entries.filter{it.section=="commanders"}.joinToString(" + "){it.name},style=MaterialTheme.typography.bodyMedium,color=Parchment.copy(alpha=.75f),maxLines=2,overflow=TextOverflow.Ellipsis)}?:Text("Create or import a Commander deck to begin.",color=Parchment)}
@Composable private fun HomeNavigation(featured:Deck?,play:(Deck)->Unit,decks:()->Unit,downloads:()->Unit,settings:()->Unit,updates:()->Unit,online:()->Unit,wide:Boolean){
    featured?.let{Button(onClick={play(it)},modifier=Modifier.fillMaxWidth().heightIn(min=56.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFFB95435),contentColor=Color.White)){Text("Play Commander")}}
    OutlinedButton(onClick=decks,modifier=Modifier.fillMaxWidth().heightIn(min=52.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=Parchment)){Text("Decks")}
    OutlinedButton(onClick=online,modifier=Modifier.fillMaxWidth().heightIn(min=52.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=Parchment)){Text("Online play")}
    val button:@Composable (String,()->Unit,Modifier)->Unit={label,action,modifier->OutlinedButton(onClick=action,modifier=modifier.heightIn(min=48.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=Parchment)){Text(label)}}
    if(wide){button("Settings",settings,Modifier.fillMaxWidth());button("Updates",updates,Modifier.fillMaxWidth());button("Downloads",downloads,Modifier.fillMaxWidth())}
    else Column(Modifier.fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(8.dp)){button("Settings",settings,Modifier.fillMaxWidth());button("Updates",updates,Modifier.fillMaxWidth());button("Downloads",downloads,Modifier.fillMaxWidth())}
    Text(if(BuildConfig.ONLINE_SERVER_URL.isBlank())"Commander · Offline AI · Online play coming soon" else "Commander · Offline AI and online tables",style=MaterialTheme.typography.labelSmall,color=Parchment.copy(alpha=.62f))
}
@Composable private fun SettingsScreen(appearance:String,setAppearance:(String)->Unit,state:ScreenState,model:AppModel) {
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item {Text("Appearance",style=MaterialTheme.typography.titleLarge);Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){listOf("System","Light","Dark").forEach{mode->FilterChip(selected=appearance==mode,onClick={setAppearance(mode)},label={Text(mode)})}}}
        item {ArtworkConsentRow()}
        item {BattlefieldThemeSelector()}
        item {HorizontalDivider();Text("Private playtest history",style=MaterialTheme.typography.titleLarge);Row(verticalAlignment=Alignment.CenterVertically){Switch(state.recordingEnabled,model::setRecording);Spacer(Modifier.width(10.dp));Column{Text(if(state.recordingEnabled)"Recording summaries" else "Recording off");Text("Device-only, up to 100 games. Retains public opponent names and commanders; never hands or opponent decklists.",style=MaterialTheme.typography.bodySmall)}}}
        item {MatchHistoryDashboard(state.playtests,model::clearPlaytests)}
        item {HorizontalDivider();Text(state.status,style=MaterialTheme.typography.bodySmall);Text(if(BuildConfig.ONLINE_SERVER_URL.isBlank())"AI games run locally without an account. Cross-platform online play is coming soon." else "AI games run locally without an account. Online tables use your MagicMobile account and the match server.",style=MaterialTheme.typography.bodySmall)}
    }
}
@Composable private fun UpdatesScreen() {
    val context=LocalContext.current
    Column(Modifier.fillMaxSize().padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        Text("MagicMobile ${BuildConfig.VERSION_NAME} · release build ${BuildConfig.RELEASE_BUILD}",style=MaterialTheme.typography.headlineSmall)
        Text("Android and iOS share this product version and release build. Each platform has its own signed artifact.")
        Button(onClick={runCatching{context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://github.com/ineedsomesleep5/MagicMobile/releases"))) }},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)){Text("Open release downloads")}
        Text("Updates are installed from the signed Android APK release. Your local decks remain on this device when the signing identity and version upgrade path match.",style=MaterialTheme.typography.bodySmall)
    }
}
@Composable private fun DeckTile(deck:Deck,subtitle:String,saved:SavedDeck?,edit:()->Unit,play:()->Unit,organize:()->Unit,duplicate:()->Unit,delete:()->Unit,selected:Boolean=false,compact:Boolean=false,catalogue:Catalogue?=null) {
    var menu by remember{mutableStateOf(false)}
    Card(Modifier.fillMaxWidth()){Column{CardArtwork(deck.entries.firstOrNull{it.section=="commanders"}?.name.orEmpty(),Modifier.fillMaxWidth().height(if(compact)142.dp else 210.dp),artOnly=true){ArtworkCoverPlaceholder()}
        Column(Modifier.padding(if(compact)12.dp else 18.dp)){Text(deck.name,style=if(compact)MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif,minLines=2,maxLines=2,overflow=TextOverflow.Ellipsis)
        Text(deck.entries.filter { it.section=="commanders" }.joinToString(" + "){it.name},style=MaterialTheme.typography.bodyMedium,minLines=2,maxLines=2,overflow=TextOverflow.Ellipsis)
        val identities=deck.entries.filter{it.section=="commanders"}.map{catalogue?.find(it.name)?.identity}
        Row(Modifier.height(28.dp),horizontalArrangement=Arrangement.spacedBy(4.dp),verticalAlignment=Alignment.CenterVertically){if(identities.isNotEmpty() && identities.all{it!=null}){val colors=identities.flatMap{it.orEmpty()}.toSet();listOf("W","U","B","R","G").filter{it in colors}.ifEmpty{listOf("C")}.forEach{ManaSymbol(it,22)}}else Text("Identity unknown",style=MaterialTheme.typography.labelSmall)}
        Text("${if(saved?.favorite==true)"★ · " else ""}${deck.entries.sumOf { it.quantity }} cards · $subtitle",style=MaterialTheme.typography.bodySmall,minLines=2,maxLines=2,overflow=TextOverflow.Ellipsis)
        Text(if(selected)"Selected for the lobby" else "",style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.primary)
        Text(saved?.tags.orEmpty().joinToString(" · "),style=MaterialTheme.typography.labelSmall,maxLines=1,overflow=TextOverflow.Ellipsis)
        if(compact){TextButton(onClick=edit){Text("Open deck")};Box{TextButton(onClick={menu=true}){Text("Deck actions")};DropdownMenu(expanded=menu,onDismissRequest={menu=false}){DropdownMenuItem(text={Text("Playtest")},onClick={menu=false;play()});if(saved!=null){DropdownMenuItem(text={Text("Organize")},onClick={menu=false;organize()});DropdownMenuItem(text={Text("Copy")},onClick={menu=false;duplicate()});DropdownMenuItem(text={Text("Delete")},onClick={menu=false;delete()})}}}}
        else{Row {TextButton(onClick=edit){Text("Open")};TextButton(onClick=play){Text("Playtest")}}
        if(saved!=null)Row {TextButton(onClick=organize){Text("Organize")};TextButton(onClick=duplicate){Text("Copy")};TextButton(onClick=delete){Text("Delete")}}}}}}
}
@Composable private fun ArtworkCoverPlaceholder() {
    Column(Modifier.fillMaxSize().padding(16.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
        Box(Modifier.size(38.dp,52.dp).border(2.dp,Ink.copy(alpha=.6f),RoundedCornerShape(6.dp)).semantics{contentDescription="Card artwork placeholder"},contentAlignment=Alignment.Center){Text("✦",style=MaterialTheme.typography.titleMedium,color=Ink)}
        Spacer(Modifier.height(8.dp))
        Text("Artwork not downloaded",style=MaterialTheme.typography.labelMedium,color=Ink,textAlign=androidx.compose.ui.text.style.TextAlign.Center,maxLines=2)
    }
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
    var commanderReplacement by remember {mutableStateOf(false)}
    var searchType by remember {mutableStateOf("")}
    var searchSet by remember {mutableStateOf("")}
    var minimumMana by remember {mutableStateOf("")}
    var maximumMana by remember {mutableStateOf("")}
    var constrainIdentity by remember {mutableStateOf(true)}
    var searchError by remember {mutableStateOf<String?>(null)}
    var browseCatalogue by remember {mutableStateOf(false)}
    var cardDetail by remember {mutableStateOf<String?>(null)}
    var replacing by remember {mutableStateOf<Int?>(null)}
    var rowFilter by remember {mutableStateOf("")}
    var rowSort by remember {mutableStateOf("Name")}
    var grouping by remember {mutableStateOf("Type")}
    var workspace by remember(draftID){mutableStateOf("Cards")}
    val workspaceScroll=rememberLazyListState()
    LaunchedEffect(workspace){workspaceScroll.scrollToItem(0)}
    var rowColor by remember {mutableStateOf("")}
    var rowBoard by remember {mutableStateOf("")}
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
    val commanderIdentity=remember(draft,model.catalogue){draft.entries.filter{it.section=="commanders"}.takeIf{it.isNotEmpty()}?.map{model.catalogue?.find(it.name)?.identity}?.takeIf{identities->identities.all{it!=null}}?.flatMap{it.orEmpty()}?.toSet()}
    LaunchedEffect(search,searchType,searchSet,minimumMana,maximumMana,constrainIdentity,commanderIdentity,browseCatalogue){
        runCatching{
            if(!browseCatalogue&&listOf(search,searchType,searchSet,minimumMana,maximumMana).all{it.isBlank()})return@runCatching emptyList<CardInfo>()
            val minimum=minimumMana.trim().takeIf{it.isNotEmpty()}?.let{it.toDoubleOrNull()?:error("Enter a valid minimum mana value.")}
            val maximum=maximumMana.trim().takeIf{it.isNotEmpty()}?.let{it.toDoubleOrNull()?:error("Enter a valid maximum mana value.")}
            withContext(Dispatchers.Default){DeckCatalogueSearch.search(model.catalogue?.cards.orEmpty(),search,searchType,searchSet,minimum,maximum,commanderIdentity.takeIf{constrainIdentity})}
        }.onSuccess{results=it;searchError=null}.onFailure{if(it is kotlinx.coroutines.CancellationException)throw it;results=emptyList();searchError=it.message}
    }
    val analysis=remember(draft,model.catalogue){model.catalogue?.let {DeckAnalyzer.analyze(draft,it)}}
    fun groupName(row:CardEntry):String {
        if(row.section!="deck")return row.section.replaceFirstChar(Char::uppercase)
        val card=model.catalogue?.find(row.name)
        return when(grouping){
            "Name","Section"->"Main deck"
            "Mana value"->card?.manaValue?.let{value->"Mana value "+if(value%1.0==0.0)value.toLong().toString() else value.toString()} ?: "Unknown mana value"
            "Color"->card?.colors?.let{colors->if(colors.isEmpty())"Colorless" else listOf("W","U","B","R","G").filter(colors::contains).joinToString(" / ")} ?: "Unknown color"
            else->card?.types?.let{types->listOf("LAND","CREATURE","PLANESWALKER","INSTANT","SORCERY","ARTIFACT","ENCHANTMENT","BATTLE").firstOrNull(types::contains)?.lowercase()?.replaceFirstChar(Char::uppercase) ?: "Other types"} ?: "Unclassified"
        }
    }
    Column(Modifier.fillMaxSize()) {
    DeckChoice("Workspace",workspace,listOf("Cards","Ideas","Analysis","Playtest")){workspace=it}
    LazyColumn(Modifier.weight(1f),state=workspaceScroll,contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
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
            TextButton(onClick={runCatching{DeckTextImport.exportJSON(draft)}.onSuccess{exportContent=it;exportJSON.launch("magicmobile-deck.json")}.onFailure{message=it.message}}){Text("Export deck JSON")}
            if(receiptRead.isFailure)Text("Import receipt could not be read or saved. Source files are preserved.",color=MaterialTheme.colorScheme.error)
            Row{TextButton(enabled=undo.isNotEmpty(),onClick={redo=redo+draft;draft=undo.last();undo=undo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Undo")};TextButton(enabled=redo.isNotEmpty(),onClick={undo=undo+draft;draft=redo.last();redo=redo.dropLast(1);model.invalidateValidation();model.recover(draft)}){Text("Redo")};TextButton(onClick={runCatching{DeckTextImport.exportText(draft)}.onSuccess{exportContent=it;exportText.launch("magicmobile-deck.txt")}.onFailure{message=it.message}}){Text("Export text")}}
            if(draft.entries.any {it.section !in setOf("deck","commanders","companions")})Row(verticalAlignment=Alignment.CenterVertically){Checkbox(checked=exclude,onCheckedChange={exclude=it;model.invalidateValidation()});Text("Validate without other boards")}
            state.validation?.takeIf {model.validationApplies(draft,exclude)}?.let {report->Text(report.summary,color=if(report.valid)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error);report.issues.take(20).forEach{Text("• ${it.cardName?.let {name->"$name: "}.orEmpty()}${it.message}",style=MaterialTheme.typography.bodySmall)}}
            message?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        }
        if(workspace=="Cards") {
        item {OutlinedTextField(value=search,onValueChange={search=it.take(200)},label={Text("Add cards · name or rules text")},modifier=Modifier.fillMaxWidth())
            if(replacing!=null)Row {Text("Choose a replacement for ${draft.entries.getOrNull(replacing!!)?.name.orEmpty()}",modifier=Modifier.weight(1f));TextButton(onClick={replacing=null}){Text("Cancel")}}
            DeckChoice("Add to",section,DeckEditing.boards){section=it}
            DeckChoice("Type",searchType,listOf("","Creature","Artifact","Enchantment","Instant","Sorcery","Land","Planeswalker","Battle")){searchType=it}
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){OutlinedTextField(value=minimumMana,onValueChange={minimumMana=it.take(12)},label={Text("Min MV")},modifier=Modifier.weight(1f));OutlinedTextField(value=maximumMana,onValueChange={maximumMana=it.take(12)},label={Text("Max MV")},modifier=Modifier.weight(1f));OutlinedTextField(value=searchSet,onValueChange={searchSet=it.take(16)},label={Text("Set code")},modifier=Modifier.weight(1f))}
            if(commanderIdentity!=null)Row{Checkbox(checked=constrainIdentity,onCheckedChange={constrainIdentity=it});Text("Within commander color identity")}
            Row{TextButton(onClick={searchType="";searchSet="";minimumMana="";maximumMana="";constrainIdentity=true}){Text("Reset filters")};TextButton(onClick={browseCatalogue=!browseCatalogue}){Text(if(browseCatalogue)"Hide unfiltered cards" else "Browse all cards")}}
            searchError?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        }
        items(results,key={"search-${it.name}"}) { card -> OutlinedCard(Modifier.fillMaxWidth()){Row(Modifier.padding(10.dp),verticalAlignment=Alignment.CenterVertically){CardArtwork(card.name,Modifier.size(38.dp,52.dp).clip(RoundedCornerShape(4.dp)).clickable{cardDetail=card.name}){Text(card.name.take(1),style=MaterialTheme.typography.labelSmall)};Spacer(Modifier.width(10.dp));Column(Modifier.weight(1f).clickable{cardDetail=card.name}){Text(card.name);Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){ManaCost(card.cost);Text(card.type.orEmpty(),style=MaterialTheme.typography.bodySmall)}};TextButton(onClick={try{change(replacing?.let {DeckEditing.replace(draft,it,card.name)} ?: draft.copy(entries=draft.entries+CardEntry(card.name,1,section)));message=null}catch(e:Exception){message=e.message}}){Text(if(replacing!=null)"Replace" else "+ Add")}}} }
        if(search.isNotBlank())item{Text("Local compiled catalogue · up to 80 results",style=MaterialTheme.typography.bodySmall)}
        }
        if(workspace=="Analysis")analysis?.let { facts->item {OutlinedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){
            Text("Deck analysis",style=MaterialTheme.typography.titleMedium)
            TextButton(onClick={showInsights=true}){Text("Roles, targets & draw probabilities")}
            Text("${facts.mainCardCount} main cards · ${facts.landCount} lands · average nonland mana ${facts.averageNonlandManaValue?.let {String.format(Locale.US,"%.2f",it)} ?: "unknown"}")
            Text("Curve 0–7+: "+facts.manaCurveBins.entries.joinToString(" · "){"${it.key}${if(it.key==7)"+" else ""}: ${it.value}"},style=MaterialTheme.typography.bodySmall)
            val roles=facts.roles.filterValues {it.count>0};if(roles.isNotEmpty())Text(roles.entries.joinToString(" · "){"${it.key.name.lowercase().replace('_',' ')} ${it.value.count}"},style=MaterialTheme.typography.bodySmall)
            if(facts.unknownNameCount>0)Text("${facts.unknownNameCount} unresolved card(s): ${facts.unknownNames.take(8).joinToString()}",color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)
            Text("Catalogue facts only—not a power score, mana-source estimate, simulation, or legality result.",style=MaterialTheme.typography.labelSmall)
        }}}}
        if(workspace=="Cards") {
        item {OutlinedTextField(value=rowFilter,onValueChange={rowFilter=it.take(200)},label={Text("Filter deck · name or rules")},modifier=Modifier.fillMaxWidth());Row{TextButton(onClick={basics=true}){Text("Basic lands")};TextButton(onClick={commanderReplacement=true}){Text("Change commander")}}
            DeckChoice("Sort",rowSort,listOf("Name","Mana","Quantity")){rowSort=it};DeckChoice("Group",grouping,listOf("Type","Section","Mana value","Color","Name")){grouping=it}
            DeckChoice("Board",rowBoard,listOf("")+draft.entries.map{it.section}.distinct()){rowBoard=it};DeckChoice("Color",rowColor,listOf("","W","U","B","R","G","C")){rowColor=it}
        }
        draft.entries.withIndex().filter {row->val card=model.catalogue?.find(row.value.name);(row.value.name.contains(rowFilter,true)||card?.rules?.contains(rowFilter,true)==true)&&(rowBoard.isEmpty()||row.value.section==rowBoard)&&(rowColor.isEmpty()||if(rowColor=="C")card?.colors?.isEmpty()==true else card?.colors?.contains(rowColor)==true)}.sortedWith(compareBy<IndexedValue<CardEntry>>{when(rowSort){"Mana"->model.catalogue?.find(it.value.name)?.manaValue ?: Double.MAX_VALUE;"Quantity"->-it.value.quantity.toDouble();else->0.0}}.thenBy{it.value.name.lowercase()}).groupBy{row->groupName(row.value)}.toList().sortedWith(compareBy<Pair<String,List<IndexedValue<CardEntry>>>>{(name,_)->when{ name=="Commanders"->-1.0;name.startsWith("Mana value ")->name.removePrefix("Mana value ").toDoubleOrNull()?.coerceAtMost(1_000_000.0) ?: 1_000_001.0;else->1_000_001.0}}.thenBy{it.first}).forEach { (section,rows) ->
            item(key="header-$section"){Text("${section.replaceFirstChar{it.uppercase()}} · ${rows.sumOf {it.value.quantity}}",style=MaterialTheme.typography.titleMedium)}
            items(rows,key={"row-${it.index}"}) { (index,row) -> Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text(row.name,modifier=Modifier.fillMaxWidth().clickable{cardDetail=row.name},maxLines=2,overflow=TextOverflow.Ellipsis);model.catalogue?.find(row.name).let { info -> if(info?.cost != null) ManaCost(info.cost) else Text(if(info==null) "Unresolved in local catalogue" else info.type.orEmpty(),style=MaterialTheme.typography.bodySmall,maxLines=2,overflow=TextOverflow.Ellipsis) }
                Row {TextButton(onClick={try{change(draft.change(index,-1))}catch(e:Exception){message=e.message}}){Text("−")};Text("${row.quantity}",modifier=Modifier.padding(12.dp));TextButton(onClick={try{change(draft.change(index,1))}catch(e:Exception){message=e.message}}){Text("+")}
                    DeckChoice("Move",row.section,DeckEditing.boards){destination->change(DeckEditing.move(draft,index,destination))}}
                Row{TextButton(onClick={replacing=index;search=row.name}){Text("Replace")};TextButton(onClick={change(DeckEditing.move(draft,index,if(row.section=="maybeboard")"deck" else "maybeboard"))}){Text(if(row.section=="maybeboard")"To main" else "Maybeboard")};TextButton(onClick={change(draft.copy(entries=draft.entries.filterIndexed{i,_->i!=index}))}){Text("Remove")}}
            }} }
        }
        }
        if(workspace=="Ideas")item {model.catalogue?.let {catalogue->ProviderDiscoveryPanel(draft,catalogue,readOnly=!draftWritable){name,target->try{change(draft.copy(entries=draft.entries+CardEntry(name,1,target)));true}catch(error:Exception){message=error.message;false}}}}
        if(workspace=="Playtest")item {model.catalogue?.let {catalogue->DeckPlaytestInsights(draft,catalogue,state.playtests,state.recordingEnabled,model::setRecording)}}
    }
    }
    if(basics)BasicLandsDialog(draft,{basics=false},::change)
    if(commanderReplacement)model.catalogue?.let{catalogue->CommanderReplacementDialog(draft,catalogue,{commanderReplacement=false}){expected,name,keepOld->if(draft!=expected)false else runCatching{change(DeckEditing.replaceCommander(draft,name,keepOld));true}.getOrElse{message=it.message;false}}}
    cardDetail?.let {CatalogueCardDialog(it,model.catalogue){cardDetail=null}}
    if(showReceipt)receiptRead.getOrNull()?.let{receipt->ImportReceiptDialog(receipt,{showReceipt=false})}
    if(showInsights)model.catalogue?.let{DeckInsightsDialog(draft,it,saveTarget?.id){showInsights=false}}
}
