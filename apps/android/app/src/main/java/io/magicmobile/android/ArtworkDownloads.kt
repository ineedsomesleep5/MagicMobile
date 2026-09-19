package io.magicmobile.android

import android.content.Context
import android.app.Activity
import android.text.format.Formatter
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.core.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.coroutines.coroutineContext

private enum class DownloadScope(val label: String) {
    CATALOGUE("Full catalogue · recommended"),
    ALL_DECKS("All saved & included decks"),
    ONE_DECK("One deck"),
}

private data class DownloadProgress(val completed: Int, val total: Int, val status: String)
private data class DownloadScan(val cards:Int,val bytes:Long,val extraStored:Int,val extraTotal:Int,val coverageKnown:Boolean)

/** Explicit foreground downloads; completed images and safe token identities survive retries. */
private class ArtworkDownloadClient(private val context: Context) {
    private fun coverageFile(names:List<String>):java.io.File {
        val key=java.security.MessageDigest.getInstance("SHA-256").digest(names.joinToString("\n").toByteArray()).joinToString(""){"%02x".format(it)}
        return java.io.File(java.io.File(context.filesDir,"artwork-coverage").apply{mkdirs()},"$key.json")
    }
    suspend fun scan(names: List<String>, quality: ArtworkQuality,includeTokens:Boolean): DownloadScan = withContext(Dispatchers.IO) {
        val manifest=runCatching{val file=coverageFile(names);check(file.length() in 1..4*1024*1024);Wire.decode(file.readBytes())}.getOrNull()
        val extras=manifest?.array("faces").orEmpty().filterIsInstance<String>()+(if(includeTokens)manifest?.array("tokens").orEmpty().filterIsInstance<String>()else emptyList())
        val unavailable=if(includeTokens)manifest?.number("unavailable")?.toInt() ?: 0 else 0
        DownloadScan(names.count { Artwork.hasDownload(context, it, quality) },Artwork.storedDownloadBytes(context),
            extras.count{Artwork.hasDownload(context,it,quality)},extras.size+unavailable,
            manifest?.number("known")==names.size.toLong()&&(!includeTokens||manifest?.flag("includesTokens")==true))
    }
    private fun saveCoverage(names:List<String>,faces:Set<String>,tokens:Set<String>,known:Int,includeTokens:Boolean,unavailable:Int) {
        val file=android.util.AtomicFile(coverageFile(names));val bytes=Wire.encode(mapOf("faces" to faces.toList(),"tokens" to tokens.toList(),"known" to known,"includesTokens" to includeTokens,"unavailable" to unavailable))
        val output=file.startWrite();try{output.write(bytes);file.finishWrite(output)}catch(failure:Throwable){file.failWrite(output);throw failure}
    }
    suspend fun download(names: List<String>, quality: ArtworkQuality, includeTokens: Boolean,
        fullCatalogue:Boolean, progress: (DownloadProgress) -> Unit): List<String> = withContext(Dispatchers.IO) {
        val failures=mutableListOf<String>()
        var omittedFailures=0
        fun fail(name:String,failure:Throwable) {
            if(failure is CancellationException)throw failure
            if(failure.message.orEmpty().let{it.contains("requests are paused")||it.contains("free device space")||it.contains("storage reached")})throw failure
            if(failures.size<100)failures+="$name: ${failure.message ?: "unavailable"}" else omittedFailures++
        }
        suspend fun checkActive(){coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}}
        suspend fun image(record:ArtworkRecord,key:String) {
            checkActive()
            if(Artwork.hasDownload(context,key,quality))return
            val url=record.images[quality.imageVersion]?.let(::URL) ?: error("No artwork at this quality.")
            val data=ArtworkTransport.bytes(context,url,2*1024*1024,setOf("image/jpeg","image/png"))
            checkActive()
            check(Artwork.saveDownload(context,key,quality,data)){"Artwork did not meet ${quality.label.lowercase()} quality."}
        }
        val catalogue=if(fullCatalogue){progress(DownloadProgress(0,names.size,"Preparing bulk artwork catalogue…"));bulk()}else null
        val wantedTokens=linkedMapOf<String,ArtworkRecord?>()
        val nameSet=names.toSet()
        val faces=linkedSetOf<String>()
        var known=0
        var unavailableTokens=catalogue?.unavailableTokens?.size ?: 0
        if(includeTokens&&catalogue!=null) {
            catalogue.tokens.forEach{(id,record)->wantedTokens[id]=record}
            catalogue.unavailableTokens.forEach{fail("Token $it",IllegalStateException("Safe artwork metadata is unavailable."))}
        }
        if(catalogue!=null)names.forEach{name->catalogue.card(name)?.let{card->known++;card.faces.filter{it.images.isNotEmpty()&&it.name !in nameSet}.forEach{faces+=it.name}}}
        fun persistCoverage()=saveCoverage(names,faces,wantedTokens.keys.map{"token:$it"}.toSet(),known,includeTokens,unavailableTokens)
        persistCoverage()
        try {
        names.forEachIndexed{index,name->
            checkActive();progress(DownloadProgress(index,names.size,"Checking $name"))
            try {
                // Metadata is still needed on deck retries to discover faces and tokens.
                val card=if(catalogue!=null)catalogue.card(name) ?: error("No unambiguous catalogue artwork.") else metadata(URL("https://api.scryfall.com/cards/named?exact=${URLEncoder.encode(name,"UTF-8")}"))
                if(catalogue==null)known++
                card.faces.filter{it.images.isNotEmpty()&&it.name !in nameSet}.forEach{faces+=it.name}
                if(includeTokens&&catalogue==null)card.related.forEach{wantedTokens.putIfAbsent(it,null)}
                image(card.faces.firstOrNull{it.name.equals(name,true)&&it.images.isNotEmpty()} ?: card,name)
                card.faces.filter{it.images.isNotEmpty()}.forEach{face->image(face,face.name)}
            } catch(failure:Exception){fail(name,failure)}
        }
        if(includeTokens)wantedTokens.entries.forEachIndexed{index,(id,known)->
            checkActive();progress(DownloadProgress(names.size+index,names.size+wantedTokens.size,"Checking token artwork"))
            try {
                val record=known ?: metadata(URL("https://api.scryfall.com/cards/$id"))
                if(catalogue==null)record.faces.drop(1).filter{it.images.isNotEmpty()}.forEach{unavailableTokens++;fail(it.name,IllegalStateException("Alternate token face identity is unavailable."))}
                check(record.id==id&&record.token!=null){"Token metadata is unavailable."}
                checkActive();Artwork.saveToken(context,record)
                image(record,"token:$id")
            } catch(failure:Exception){fail("Token $id",failure)}
        }
        checkActive()
        progress(DownloadProgress(names.size+wantedTokens.size,names.size+wantedTokens.size,"Download check complete"))
        if(omittedFailures>0)failures+="$omittedFailures additional items are unavailable. Completed files were retained."
        failures
        } finally {persistCoverage()}
    }
    private suspend fun metadata(url:URL):ArtworkRecord {
        val data=ArtworkTransport.bytes(context,url,4*1024*1024,setOf("application/json"))
        return ArtworkCatalogue.decode(Wire.objectValue(io.magicmobile.core.Json.parseObject(data.toString(Charsets.UTF_8)))) ?: error("Invalid artwork metadata.")
    }
    private suspend fun bulk():ArtworkCatalogue {
        val directory=java.io.File(context.filesDir,"artwork-catalogue").apply{mkdirs()}
        val cache=java.io.File(directory,"oracle.gz")
        val job=coroutineContext
        fun parse(file:java.io.File):ArtworkCatalogue=file.inputStream().buffered(65536).use{raw->
            raw.mark(2);val gzip=raw.read()==0x1f&&raw.read()==0x8b;raw.reset()
            val input=if(gzip)java.util.zip.GZIPInputStream(raw,65536)else raw
            ArtworkCatalogue.parse(input){job.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}}
        }
        if(cache.isFile&&System.currentTimeMillis()-cache.lastModified() in 0..86_400_000) {
            try{return parse(cache)}catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){/* Replace invalid cache only after a valid download. */}
        }
        val metadata=ArtworkTransport.bytes(context,URL("https://api.scryfall.com/bulk-data"),2*1024*1024,setOf("application/json"))
        val root=Wire.objectValue(io.magicmobile.core.Json.parseObject(metadata.toString(Charsets.UTF_8)))
        val item=root.array("data").map(Wire::objectValue).firstOrNull{it.text("type")=="oracle_cards"} ?: error("Oracle catalogue is unavailable.")
        val url=URL(item.text("jsonl_download_uri") ?: item.text("download_uri") ?: error("Catalogue download is unavailable."))
        check(url.host=="data.scryfall.io"){"Unsupported catalogue address."}
        val temporary=java.io.File.createTempFile("oracle-",".partial",directory)
        try{
            temporary.outputStream().use{ArtworkTransport.transfer(context,url,250L*1024*1024,setOf("application/gzip","application/x-gzip","application/json","application/octet-stream"),it)}
            val parsed=parse(temporary);coroutineContext.ensureActive()
            java.nio.file.Files.move(temporary.toPath(),cache.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING,java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            return parsed
        }finally{temporary.delete()}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ArtworkDownloadsScreen(
    catalogue: Catalogue?,
    saved: List<SavedDeck>,
    included: List<Deck>,
    close: () -> Unit,
    notify: (String) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner=LocalLifecycleOwner.current
    val preferences = remember { context.getSharedPreferences("magicmobile.artwork", Context.MODE_PRIVATE) }
    val decks = remember(saved, included) {
        saved.map { it.id to it.deck } + included.mapIndexed { index, deck -> "included:$index" to deck }
    }
    val deckChoices=remember(decks){decks.mapIndexed{index,(_,deck)->"${deck.name} · ${index+1}"}}
    var scope by remember { mutableStateOf(DownloadScope.CATALOGUE) }
    var selectedDeck by remember(decks) { mutableStateOf(decks.firstOrNull()?.first.orEmpty()) }
    var quality by remember { mutableStateOf(ArtworkQuality.entries.firstOrNull { it.id == preferences.getString("downloadQuality", "standard") } ?: ArtworkQuality.STANDARD) }
    var includeTokens by remember { mutableStateOf(true) }
    var remoteArtwork by remember {mutableStateOf(Artwork.enabled(context))}
    var running by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(DownloadProgress(0, 0, "Choose what to keep offline.")) }
    var failures by remember {mutableStateOf<List<String>>(emptyList())}
    var showFailures by remember {mutableStateOf(false)}
    var extraCoverage by remember(scope,selectedDeck,quality,includeTokens) {mutableStateOf("Tokens and alternate faces · not checked")}
    var storedCount by remember { mutableIntStateOf(0) }
    var storedBytes by remember { mutableLongStateOf(Artwork.storedDownloadBytes(context)) }
    var confirmFull by remember { mutableStateOf(false) }
    val coroutine = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    val names = remember(scope, selectedDeck, catalogue, decks) {
        when (scope) {
            DownloadScope.CATALOGUE -> catalogue?.cards?.map { it.name }.orEmpty()
            DownloadScope.ALL_DECKS -> decks.flatMap { (_, deck) -> deck.entries.map { it.name } }
            DownloadScope.ONE_DECK -> decks.firstOrNull { it.first == selectedDeck }?.second?.entries?.map { it.name }.orEmpty()
        }.map(String::trim).filter(String::isNotEmpty).distinct().sorted()
    }
    fun scan() {
        scanning = true
        coroutine.launch {
            runCatching { ArtworkDownloadClient(context).scan(names, quality,includeTokens) }
                .onSuccess { result -> storedCount = result.cards; storedBytes = result.bytes
                    extraCoverage=(if(includeTokens)"Tokens and alternate faces" else "Alternate faces")+" · ${result.extraStored} / ${result.extraTotal}"+(if(result.coverageKnown)"" else " known; discovery incomplete")
                    progress = DownloadProgress(0, names.size, "Local artwork checked") }
                .onFailure { notify("Artwork check failed: ${it.message}") }
            scanning = false
        }
    }
    fun start() {
        if (running || names.isEmpty()) return
        failures=emptyList()
        showFailures=false
        running = true
        job = coroutine.launch {
            val result = runCatching {
                ArtworkDownloadClient(context).download(names, quality, includeTokens, scope==DownloadScope.CATALOGUE) { update -> progress = update }
            }
            running = false
            storedBytes = Artwork.storedDownloadBytes(context)
            result.onSuccess { downloadFailures ->
                failures=downloadFailures
                scan()
                notify(if (downloadFailures.isEmpty()) "Artwork download complete." else "Some artwork is unavailable. See Needs attention; existing files were kept.")
            }.onFailure { if (it !is CancellationException) notify("Artwork download stopped: ${it.message}") }
        }
    }
    DisposableEffect(Unit) { onDispose { job?.cancel() } }
    DisposableEffect(lifecycleOwner) {
        val observer=LifecycleEventObserver{_,event->if(event==Lifecycle.Event.ON_STOP){job?.cancel()}}
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose{lifecycleOwner.lifecycle.removeObserver(observer)}
    }
    DisposableEffect(running) {
        val window=(context as? Activity)?.window
        if(running)window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
    }
    Scaffold(
        topBar = { TopAppBar(title = { Text("Downloads") }, navigationIcon = { TextButton(onClick = close) { Text("Back") } }) },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Keep card artwork on this device", style = MaterialTheme.typography.headlineMedium)
            Text("The card catalogue and XMage rules engine are already included. Artwork is optional and comes from Scryfall.", style = MaterialTheme.typography.bodyMedium)
            Text("Artwork", style = MaterialTheme.typography.titleMedium)
            DownloadChoice("Download", scope.label, DownloadScope.entries.map { it.label }, !running && !scanning) { label -> scope = DownloadScope.entries.first { it.label == label }; storedCount=0 }
            if (scope == DownloadScope.ONE_DECK) DownloadChoice("Deck", deckChoices.getOrNull(decks.indexOfFirst{it.first==selectedDeck}) ?: "No decks", deckChoices, !running && !scanning) { label -> selectedDeck = decks[deckChoices.indexOf(label)].first;storedCount=0 }
            DownloadChoice("Image quality", quality.label, ArtworkQuality.entries.map { it.label }, !running && !scanning) { label ->
                quality = ArtworkQuality.entries.first { it.label == label }
                storedCount=0
                preferences.edit().putString("downloadQuality", quality.id).apply()
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Column(Modifier.weight(1f)) { Text("Include tokens"); Text("Full catalogue includes canonical tokens; decks include linked tokens.", style = MaterialTheme.typography.bodySmall) }; Switch(includeTokens, { includeTokens = it }, enabled = !running && !scanning) }
            HorizontalDivider()
            Text("On this device", style = MaterialTheme.typography.titleMedium)
            Text("Cards · $storedCount / ${names.size}")
            Text(extraCoverage,style=MaterialTheme.typography.bodySmall)
            Text("Stored · ${Formatter.formatFileSize(context, storedBytes)}")
            Text("Full download estimate · ≈ ${Formatter.formatFileSize(context, names.size.toLong() * quality.estimatedBytes)} plus tokens and alternate faces", style = MaterialTheme.typography.bodySmall)
            if (scanning) LinearProgressIndicator(Modifier.fillMaxWidth())
            OutlinedButton(onClick = ::scan, enabled = !running && !scanning && names.isNotEmpty(), modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Check for missing artwork") }
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Column(Modifier.weight(1f)){Text("Download card artwork");Text("Uses Scryfall. Online requests share your IP and card names, including your hand.",style=MaterialTheme.typography.bodySmall)};Switch(remoteArtwork,{enabled->remoteArtwork=enabled;Artwork.setEnabled(context,enabled);if(!enabled){job?.cancel()}})}
            if (running) {
                LinearProgressIndicator(progress = { if (progress.total == 0) 0f else progress.completed.toFloat() / progress.total }, modifier = Modifier.fillMaxWidth())
                Text(progress.status)
                OutlinedButton(onClick = { job?.cancel(); notify("Download paused. Completed files are kept.") }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Cancel download") }
            } else Button(onClick = { if (scope == DownloadScope.CATALOGUE) confirmFull = true else start() }, enabled = remoteArtwork && names.isNotEmpty() && !scanning, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("Download missing artwork") }
            if(failures.isNotEmpty()) {HorizontalDivider();TextButton(onClick={showFailures=!showFailures}){Text(if(showFailures)"Hide download details" else "Needs attention · show download details")};if(showFailures){failures.take(20).forEach{Text(it,style=MaterialTheme.typography.bodySmall)};if(failures.size>20)Text("Additional details omitted. Retry missing artwork to check remaining items.",style=MaterialTheme.typography.bodySmall)}}
            Text("Completed files stay on this device. Keep this screen open while downloading; reopen it to resume missing items. Unavailable or ambiguous art remains a labeled placeholder.", style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(24.dp))
        }
    }
    if (confirmFull) AlertDialog(
        onDismissRequest = { confirmFull = false },
        title = { Text("Download the full catalogue?") },
        text = { Text("Approximately ${Formatter.formatFileSize(context, names.size.toLong() * quality.estimatedBytes)}, plus tokens and alternate faces. This can take hours. Use Wi-Fi and keep this screen open.") },
        confirmButton = { TextButton(onClick = { confirmFull = false; start() }) { Text("Download · ${quality.label}") } },
        dismissButton = { TextButton(onClick = { confirmFull = false }) { Text("Cancel") } },
    )
}

@Composable
private fun DownloadChoice(label: String, selected: String, values: List<String>, enabled:Boolean=true, choose: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        OutlinedButton(onClick = { expanded = true }, enabled=enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("$label · $selected") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            values.forEach { value -> DropdownMenuItem(text = { Text(value) }, onClick = { expanded = false; choose(value) }) }
        }
    }
}
