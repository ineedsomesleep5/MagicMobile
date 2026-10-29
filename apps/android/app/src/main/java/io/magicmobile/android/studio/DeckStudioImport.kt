package io.magicmobile.android.studio

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.readBounded
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.util.UUID
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer

/** The reviewed deck and its annotations, archived beside the library (DeckStudioImportReceipt). */
private object DeckStudioImportReceipt {
    fun store(preview: OnDeviceDeckLinkImporter.Preview, sourceURL: String?): File {
        val receipt = JsonObject(buildMap {
            put("schemaVersion", JsonPrimitive(1)); put("createdAt", JsonPrimitive(System.currentTimeMillis()))
            sourceURL?.let { put("sourceURL", JsonPrimitive(it)) }
            put("deck", preview.deck.json())
            put("annotations", JsonArray(preview.annotations.map { JsonObject(mapOf("line" to JsonPrimitive(it.line), "text" to JsonPrimitive(it.text))) }))
        })
        val data = receipt.toString().toByteArray(Charsets.UTF_8)
        if (data.size > 4 * 1024 * 1024) throw ResolutionError("Import receipt is too large. Your library has not changed.")
        val directory = DeckStudioServices.organization.receiptDirectory ?: throw ResolutionError("Import receipts are unavailable on this device.")
        directory.mkdirs()
        val file = File(directory, UUID.randomUUID().toString().uppercase() + ".json")
        file.writeBytes(data)
        return file
    }
}

/**
 * DeckStudioImportScreen.swift: paste, link or scan a decklist, review it, then save a draft.
 * [didImport] takes over after a save (the studio opens the new deck); [close] is Cancel.
 */
@Composable
fun DeckStudioImportScreen(library: DeckLibraryStore, resolver: OnDeviceDeckResolver?, metadata: NativeDeckMetadataCatalogue? = null,
                          didImport: (DeckLibraryRecord) -> Unit, close: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val validation = remember { DeckStudioValidationState(scope) }
    var method by remember { mutableStateOf("Paste") }
    var name by remember { mutableStateOf("Imported Commander Deck") }
    var text by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    // On by default: a link's maybeboard is left out rather than failing the whole import (10 of 60 popular Archidekt decks have one).
    var excludeSideboards by remember { mutableStateOf(true) }
    var preview by remember { mutableStateOf<OnDeviceDeckLinkImporter.Preview?>(null) }
    var sourceURL by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var job by remember { mutableStateOf<Job?>(null) }
    var generation by remember { mutableStateOf(UUID.randomUUID()) }
    var receipt by remember { mutableStateOf<File?>(null) }
    var saved by remember { mutableStateOf<DeckLibraryRecord?>(null) }
    // Commander first: the card the player picks leads the import even when the list doesn't mark it.
    var commander by remember { mutableStateOf<String?>(null) }
    var commanderQuery by remember { mutableStateOf("") }
    var commanderSuggestions by remember { mutableStateOf<List<io.magicmobile.android.core.CardInfo>>(emptyList()) }
    // Archidekt account: a username's public decks, picked with checkmarks.
    var archidektUser by remember { mutableStateOf("") }
    var archidektDecks by remember { mutableStateOf<List<OnDeviceDeckLinkImporter.ArchidektDeckSummary>>(emptyList()) }
    var archidektPage by remember { mutableStateOf(0) }
    var archidektHasMore by remember { mutableStateOf(false) }
    var archidektSearched by remember { mutableStateOf(false) }
    var listing by remember { mutableStateOf(false) }
    var listJob by remember { mutableStateOf<Job?>(null) }
    var picked by remember { mutableStateOf<Set<Long>>(emptySet()) }
    // Several picked decks are saved one by one: each deck's outcome, in order (null while waiting, "" when saved).
    var batch by remember { mutableStateOf<List<Pair<String, String?>>>(emptyList()) }
    var batchDone by remember { mutableStateOf(false) }
    val pickedDecks = archidektDecks.filter { it.id in picked }
    val isBatch = method == "Account" && picked.size > 1

    fun invalidate() {
        if (saved != null) return
        generation = UUID.randomUUID(); job?.cancel(); busy = false; preview = null; receipt = null; validation.prepare(null)
    }
    fun cancel() { if (saving) return; job?.cancel(); validation.cancelPending(); close() }
    LaunchedEffect(text, name, link, method, excludeSideboards, commander, picked) { invalidate() }
    // Most Archidekt decks keep a maybeboard; a whole account would otherwise stop at each one.
    LaunchedEffect(method) { if (method == "Account") excludeSideboards = true }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { listJob?.cancel() } }
    fun findArchidektDecks(more: Boolean) {
        val resolver = resolver ?: return
        if (busy || listing) return
        val user = archidektUser; val page = if (more) archidektPage + 1 else 1
        error = null; listing = true
        if (!more) { archidektDecks = emptyList(); picked = emptySet(); archidektSearched = false }
        listJob = scope.launch {
            try {
                val found = OnDeviceDeckLinkImporter(resolver).archidektDecks(user, page)
                val known = archidektDecks.map { it.id }.toSet()
                archidektDecks = archidektDecks + found.decks.filter { it.id !in known }
                archidektPage = page; archidektHasMore = found.hasMore; archidektSearched = true
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.message }
            finally { listing = false }
        }
    }
    LaunchedEffect(commanderQuery, metadata) {
        val query = commanderQuery.trim()
        val catalogue = metadata
        if (catalogue == null || query.isEmpty()) { commanderSuggestions = emptyList(); return@LaunchedEffect }
        kotlinx.coroutines.delay(120)
        commanderSuggestions = withContext(Dispatchers.Default) { DeckStudioBuilderSearch.commanders(catalogue, query, 6) }
    }
    fun chooseCommander(card: String) { commander = card; commanderQuery = ""; commanderSuggestions = emptyList() }
    BackHandler { cancel() }

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val value = withContext(Dispatchers.IO) {
                    val bytes = context.contentResolver.openInputStream(uri)?.use { readBounded(it, OnDeviceDeckLinkImporter.maximumBytes + 1) }
                        ?: throw ResolutionError("Choose a UTF-8 deck file of at most 2 MiB.")
                    if (bytes.size > OnDeviceDeckLinkImporter.maximumBytes) throw ResolutionError("Choose a UTF-8 deck file of at most 2 MiB.")
                    io.magicmobile.android.core.DeckTextImport.strictUTF8(bytes)
                }
                val displayName = runCatching {
                    context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    }
                }.getOrNull()
                text = value; displayName?.substringBeforeLast('.')?.takeIf { it.isNotBlank() }?.let { name = it }; method = "Paste"
            } catch (failure: Exception) { error = failure.message }
        }
    }
    fun beginPreview() {
        val resolver = resolver ?: return
        invalidate(); error = null; busy = true
        val token = generation; val input = text; val title = name; val fromLink = method == "Link" || method == "Account"; val exclude = excludeSideboards; val lead = commander
        val url = if (method == "Account") pickedDecks.firstOrNull()?.link ?: "" else link
        job = scope.launch {
            try {
                val importer = OnDeviceDeckLinkImporter(resolver)
                val parsed = when {
                    fromLink -> importer.preview(importer.importDeck(url, exclude, reviewOnly = true))
                    input.trim().startsWith("{") -> importer.preview(OnDeviceDeckEditing.importJSON(input))
                    else -> withContext(Dispatchers.Default) { importer.preview(input, title) }
                }
                val result = if (lead != null) importer.preview(parsed, lead) else parsed
                if (generation != token) return@launch
                preview = result; sourceURL = if (fromLink) url else null
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (generation == token) error = failure.message }
            finally { if (generation == token) busy = false }
        }
    }
    /** Saves each picked deck as a draft, one at a time, and lists what happened to each. */
    fun importPicked() {
        val resolver = resolver ?: return
        if (busy) return
        val decks = pickedDecks; val exclude = excludeSideboards
        invalidate(); error = null; busy = true; saving = true
        batch = decks.map { it.name to null }
        job = scope.launch {
            val importer = OnDeviceDeckLinkImporter(resolver)
            try {
                decks.forEachIndexed { index, deck ->
                    val outcome = try {
                        val value = importer.preview(importer.importDeck(deck.link, exclude, reviewOnly = true))
                        val file = withContext(Dispatchers.IO) { DeckStudioImportReceipt.store(value, deck.link) }
                        val record = library.addLocalDurably(value.deck, deck.link)
                        withContext(Dispatchers.IO) { DeckStudioServices.organization.retainImport(record.id, emptyList(), deck.link, file.name) }
                        ""
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: Exception) { failure.message ?: "This deck could not be imported." }
                    batch = batch.toMutableList().also { it[index] = deck.name to outcome }
                }
            } finally { busy = false; saving = false; batchDone = true }
        }
    }
    fun save(value: OnDeviceDeckLinkImporter.Preview) {
        if (busy) return
        busy = true; saving = true; error = null
        job = scope.launch {
            try {
                if (receipt == null) receipt = withContext(Dispatchers.IO) { DeckStudioImportReceipt.store(value, sourceURL) }
                if (saved == null) saved = library.addLocalDurably(value.deck, sourceURL)
                val record = saved ?: return@launch
                val file = receipt ?: return@launch
                withContext(Dispatchers.IO) {
                    DeckStudioServices.organization.retainImport(record.id, value.annotations.map { "Line ${it.line}: ${it.text}" }, sourceURL, file.name)
                    // A check made during review applies to the saved deck: the same playing cards.
                    validation.receipt?.let { checked -> runCatching { DeckStudioServices.checkResults.record(DeckStudioCheckResult.of("local:${record.id}", checked)) } }
                }
                // The studio opens the saved deck's workspace next; importing never changes the playing deck.
                didImport(record)
            } catch (failure: Exception) {
                error = if (saved == null) failure.message
                else "The deck is saved and its full receipt is archived, but linking the details failed. Tap Finish import to retry without making another deck. ${failure.message ?: ""}".trim()
            } finally { busy = false; saving = false }
        }
    }

    // The parts of the importer, shared by the single page (upright) and the two pages of a spread.
    val entry: @Composable () -> Unit = {
        StudioSegmented(listOf("Paste", "Link", "Account"), method, { method = it },
            { if (it == "Account") "Archidekt" else it }, enabled = !busy && saved == null && batch.isEmpty())
        // Type a commander's name and pick it from the suggestions, as on Archidekt.
        if (!isBatch && batch.isEmpty()) StudioPanel(spacing = 10.dp) {
            val locked = busy || saved != null
            Text("Commander", color = DeckStudioPalette.ink, style = StudioText.headline)
            val chosen = commander
            if (chosen != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp, 56.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(chosen, Modifier.fillMaxSize()) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(chosen, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
                        Text("Leads the deck, even if the list marks another card or none.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                    StudioPlainButton("Change", { commander = null; commanderQuery = "" },
                        Modifier.semantics { contentDescription = "deckStudio.import.commander.change" }, enabled = !locked)
                }
            } else {
                StudioRoundedField(commanderQuery, { commanderQuery = it }, "Type a commander's name",
                    Modifier.fillMaxWidth().testTag("deckStudio.import.commander.search"), enabled = !locked,
                    onSubmit = { commanderSuggestions.firstOrNull()?.let { chooseCommander(it.name) } })
                if (metadata == null && commanderQuery.isNotBlank()) Text("The card catalogue is still loading.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                else if (commanderSuggestions.isEmpty() && commanderQuery.isNotBlank())
                    Text("No legendary creature or commander matches \"${commanderQuery.trim()}\".", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                for (card in commanderSuggestions) {
                    Row(Modifier.fillMaxWidth().clickable(enabled = !locked) { chooseCommander(card.name) }.defaultMinSize(minHeight = 44.dp)
                        .clearAndSetSemantics { contentDescription = "Choose ${card.name} as commander" },
                        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(32.dp, 44.dp).clip(RoundedCornerShape(4.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxSize()) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                            Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption, maxLines = 1)
                        }
                        DeckStudioColorIdentity(card.colorIdentity)
                    }
                }
            }
        }
        StudioPanel(spacing = 14.dp) {
            val locked = busy || saved != null
            when (method) {
                "Paste" -> {
                    StudioRoundedField(name, { name = it }, "Deck name", Modifier.fillMaxWidth(), enabled = !locked)
                    Box(Modifier.fillMaxWidth().heightIn(min = 220.dp).grimoireField(RoundedCornerShape(12.dp)).padding(10.dp)) {
                        StudioTextInput(text, { text = it }, "", Modifier.fillMaxWidth().heightIn(min = 200.dp).semantics { contentDescription = "Decklist text" },
                            style = sf(17f, design = SfDesign.MONOSPACED), singleLine = false, enabled = !locked)
                    }
                    Text("Commander\n1 Your Commander\n\nDeck\n1 Sol Ring", color = DeckStudioPalette.secondaryInk, style = sf(12f, design = SfDesign.MONOSPACED))
                    StudioPlainButton("Open text or native JSON file", { filePicker.launch(arrayOf("text/plain", "application/json")) }, icon = "doc", enabled = !locked)
                }
                "Link" -> {
                    StudioRoundedField(link, { link = it }, "Public Archidekt or Moxfield deck URL", Modifier.fillMaxWidth(), keyboardType = KeyboardType.Uri, enabled = !locked)
                    StudioToggle("Exclude sideboard / maybeboard", excludeSideboards, { excludeSideboards = it }, enabled = !locked)
                    StudioPlainButton("Switch to pasted export", { method = "Paste" }, enabled = !locked)
                }
                "Account" -> {
                    // An Archidekt username's public decks. Pick one to review it, or several to save them all as drafts.
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        StudioRoundedField(archidektUser, { archidektUser = it }, "Archidekt username",
                            Modifier.weight(1f).testTag("deckStudio.import.archidekt.username"), enabled = !locked, onSubmit = { findArchidektDecks(false) })
                        StudioButton("Find decks", { findArchidektDecks(false) }, primary = false,
                            enabled = !locked && !listing && archidektUser.isNotBlank(), compactText = true)
                    }
                    StudioToggle("Exclude sideboard / maybeboard", excludeSideboards, { excludeSideboards = it }, enabled = !locked)
                    Text("Lists the public decks on that Archidekt account. No sign-in: private and unlisted decks don't appear, so make them public or paste their text export. This contacts Archidekt.",
                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    if (listing) StudioProgress("Asking Archidekt…")
                    if (archidektSearched && archidektDecks.isEmpty() && !listing)
                        Text("No public decks found for \"${archidektUser.trim()}\".", color = DeckStudioPalette.ink, style = StudioText.callout)
                    if (archidektDecks.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${archidektDecks.size} public decks · ${picked.size} picked", Modifier.weight(1f), color = DeckStudioPalette.ink,
                                style = StudioText.subheadline.weight(SfWeight.semibold))
                            StudioPlainButton(if (picked.size == archidektDecks.size) "Clear" else "Pick all", {
                                picked = if (picked.size == archidektDecks.size) emptySet() else archidektDecks.map { it.id }.toSet()
                            }, enabled = !locked)
                        }
                        for (deck in archidektDecks) {
                            val on = deck.id in picked
                            Row(Modifier.fillMaxWidth().clickable(enabled = !locked) { picked = if (on) picked - deck.id else picked + deck.id }
                                .defaultMinSize(minHeight = 44.dp).semantics(mergeDescendants = true) { selected = on }
                                .testTag("deckStudio.import.archidekt.deck.${deck.id}"),
                                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                SfImage(if (on) "checkmark.circle.fill" else "circle", DeckStudioPalette.ink, 22.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(deck.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                                    Text(listOfNotNull(deck.size?.let { "$it cards" }, deck.updatedDay?.let { "updated $it" }).joinToString(" · "),
                                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                                }
                            }
                        }
                        if (archidektHasMore) StudioPlainButton("Show more decks", { findArchidektDecks(true) }, enabled = !locked && !listing)
                        if (isBatch) Text("Several decks are saved as drafts straight away. Open each one in your library to review it and pick its commander.",
                            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                }
            }
        }
        error?.let { DeckStudioNotice("Import needs attention", it, "exclamationmark.triangle") }
        if (busy) StudioProgress(if (saving) "Saving deck and import details…" else "Preparing review…")
        if (batch.isNotEmpty()) StudioPanel(spacing = 8.dp) {
            Text(if (batchDone) "Import finished" else "Importing decks…", color = DeckStudioPalette.ink, style = StudioText.headline)
            for ((deckName, outcome) in batch) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
                    SfImage(when { outcome == null -> "clock"; outcome.isEmpty() -> "checkmark.circle"; else -> "exclamationmark.triangle" }, DeckStudioPalette.ink, 17.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(deckName, color = DeckStudioPalette.ink, style = StudioText.subheadline)
                        if (!outcome.isNullOrEmpty()) Text(outcome, color = DeckStudioPalette.warning, style = StudioText.caption)
                    }
                }
            }
        }
        if (method == "Account") {
            if (batchDone) StudioButton("Done", ::cancel, Modifier.semantics { contentDescription = "deckStudio.import.batchDone" })
            else if (picked.isNotEmpty()) StudioButton(if (isBatch) "Import ${picked.size} decks" else "Review deck", if (isBatch) ::importPicked else ::beginPreview,
                Modifier.semantics { contentDescription = "deckStudio.import.review" }, enabled = !busy && resolver != null && saved == null && batch.isEmpty())
        } else StudioButton("Review decklist", ::beginPreview, Modifier.semantics { contentDescription = "deckStudio.import.review" },
            enabled = !busy && resolver != null && saved == null && (if (method == "Link") link else text).isNotBlank())
    }
    val reviewed: @Composable () -> Unit = {
        preview?.let { value ->
            ImportReview(value)
            DeckStudioValidationPanel(validation, value.deck, resolver)
        }
    }
    val confirm: @Composable () -> Unit = {
        preview?.let { value ->
            Box(Modifier.fillMaxWidth().grimoirePaper().navigationBarsPadding().padding(16.dp)) {
                StudioButton(if (saved == null) "Save reviewed draft" else "Finish import", { save(value) },
                    Modifier.fillMaxWidth().semantics { contentDescription = "deckStudio.import.confirm" }, enabled = !busy)
            }
        }
    }
    val spread = androidx.compose.ui.platform.LocalConfiguration.current.let { Grimoire.isSpread(it.screenWidthDp, it.screenHeightDp) }
    // A glass page over the dimmed room, Cancel as a dark pill at its head.
    val binderScreen = remember { Any() }
    Box(Modifier.fillMaxSize()) {
        BinderCover()
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding().padding(start = 4.dp, end = 4.dp, bottom = 2.dp)) {
            val head: @Composable () -> Unit = {
                BinderHead("Cancel", ::cancel, title = "Import deck", strapTag = "deckStudio.import.cancel", strapEnabled = !saving)
            }
            if (spread) {
                // The list goes in on the left page and is reviewed on the right; nothing runs across the fold.
                // The head is written on the left page, so both pages are the same height.
                Row(Modifier.weight(1f).padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), gutterStart = false, screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            head()
                            Column(Modifier.weight(1f).arenaScrollFade().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) { entry() }
                        }
                    }
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), gutterStart = true, screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            Column(Modifier.weight(1f).arenaScrollFade().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                                reviewed()
                            }
                            confirm()
                        }
                    }
                }
            } else {
                Spacer(Modifier.height(4.dp))
                BinderPage(Modifier.weight(1f).fillMaxWidth(), gutterStart = true, screen = binderScreen) {
                    Column(Modifier.fillMaxSize()) {
                        head()
                        Column(Modifier.weight(1f).arenaScrollFade().verticalScroll(rememberScrollState()).padding(16.dp).widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            entry()
                            reviewed()
                        }
                        confirm()
                    }
                }
            }
        }
    }
}

@Composable
private fun ImportReview(preview: OnDeviceDeckLinkImporter.Preview) {
    val draft = remember(preview) { NativeDeckDraft.of(preview.deck) }
    StudioPanel {
        Text(preview.deck.name, color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("checkmark.circle", DeckStudioPalette.ink, 17.dp)
            Text("Parsed · syntax accepted", color = DeckStudioPalette.ink, style = StudioText.body)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (preview.unresolvedNames.isEmpty()) "checkmark.circle" else "exclamationmark.triangle", DeckStudioPalette.ink, 17.dp)
            Text(if (preview.unresolvedNames.isEmpty()) "Every card found"
                else "${preview.unresolvedNames.size} not in MagicMobile yet: ${preview.unresolvedNames.take(4).joinToString(", ")}${if (preview.unresolvedNames.size > 4) "…" else ""}",
                color = DeckStudioPalette.ink, style = StudioText.body)
        }
        Text("${DeckStudioDraftPresentation.gameCount(draft)} main + commander cards; ${preview.deck.totalCards} across all imported sections.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Text("Parsing and name resolution do not certify Commander legality. Check with XMage below, or save an unfinished draft and continue editing. Validation never silently discards other boards.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        StudioDisclosure("Review cards and sections") {
            for (row in draft.rows) {
                Row {
                    Text("${row.quantity}× ${row.cardName}", Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.body)
                    Text(DeckStudioDraftPresentation.section(row), color = DeckStudioPalette.ink, style = StudioText.caption)
                }
                if (row.cardName in preview.unresolvedNames) Text("Not in MagicMobile yet; kept in the draft", color = DeckStudioPalette.warning, style = StudioText.caption)
            }
        }
        if (preview.annotations.isNotEmpty()) {
            StudioDisclosure("${preview.annotations.size} source annotations") {
                preview.annotations.forEach { Text("Line ${it.line}: ${it.text}", color = DeckStudioPalette.ink, style = StudioText.caption) }
            }
            Text("An on-device import receipt preserves these annotations and the reviewed deck. A printing written as (SET) number is kept as that card's chosen artwork; it does not change the compiled gameplay identity.",
                color = DeckStudioPalette.ink, style = StudioText.caption2)
        }
    }
}
