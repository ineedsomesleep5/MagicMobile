package io.magicmobile.android.studio

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.readBounded
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
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

/** DeckStudioImportScreen.swift: paste, link or scan a decklist, review it, then save a draft. */
@Composable
fun DeckStudioImportScreen(library: DeckLibraryStore, resolver: OnDeviceDeckResolver?, didImport: (DeckLibraryRecord) -> Unit, close: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val validation = remember { DeckStudioValidationState(scope) }
    var method by remember { mutableStateOf("Paste") }
    var name by remember { mutableStateOf("Imported Commander Deck") }
    var text by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    var excludeSideboards by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<OnDeviceDeckLinkImporter.Preview?>(null) }
    var sourceURL by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var job by remember { mutableStateOf<Job?>(null) }
    var generation by remember { mutableStateOf(UUID.randomUUID()) }
    var scanNotice by remember { mutableStateOf<String?>(null) }
    var receipt by remember { mutableStateOf<File?>(null) }
    var saved by remember { mutableStateOf<DeckLibraryRecord?>(null) }

    fun invalidate() {
        if (saved != null) return
        generation = UUID.randomUUID(); job?.cancel(); busy = false; preview = null; receipt = null; validation.prepare(null)
    }
    fun cancel() { if (saving) return; job?.cancel(); validation.cancelPending(); close() }
    LaunchedEffect(text, name, link, method, excludeSideboards) { invalidate() }
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
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        invalidate(); error = null; busy = true
        val token = generation
        job = scope.launch {
            try {
                val recognized = DeckStudioOCR.recognize(context, uri)
                if (generation != token) return@launch
                text = recognized; method = "Paste"
                scanNotice = "OCR can misread quantities and card names. Correct the text, then choose Review decklist."
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (generation == token) error = failure.message }
            finally { if (generation == token) busy = false }
        }
    }
    fun beginPreview() {
        val resolver = resolver ?: return
        invalidate(); error = null; busy = true
        val token = generation; val input = text; val title = name; val url = link; val fromLink = method == "Link"; val exclude = excludeSideboards
        job = scope.launch {
            try {
                val importer = OnDeviceDeckLinkImporter(resolver)
                val result = when {
                    fromLink -> importer.preview(importer.importDeck(url, exclude, reviewOnly = true))
                    input.trim().startsWith("{") -> importer.preview(OnDeviceDeckEditing.importJSON(input))
                    else -> withContext(Dispatchers.Default) { importer.preview(input, title) }
                }
                if (generation != token) return@launch
                preview = result; sourceURL = if (fromLink) url else null
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (generation == token) error = failure.message }
            finally { if (generation == token) busy = false }
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
                }
                didImport(record); close()
            } catch (failure: Exception) {
                error = if (saved == null) failure.message
                else "The deck is saved and its full receipt is archived, but linking the details failed. Tap Finish import to retry without making another deck. ${failure.message ?: ""}".trim()
            } finally { busy = false; saving = false }
        }
    }

    StudioScreen {
        Column(Modifier.fillMaxSize().imePadding()) {
            StudioNavBar("Import deck", leading = { StudioGlassGroup { StudioGlassText("Cancel", ::cancel, enabled = !saving) } })
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text("Bring your deck.", color = DeckStudioPalette.ink, style = sf(34f, SfWeight.bold, tracking = -1f))
                Text("Paste, link, or scan a decklist. Review every card before saving.", color = DeckStudioPalette.secondaryInk, style = StudioText.body)
                StudioSegmented(listOf("Paste", "Link", "Scan"), method, { method = it }, { if (it == "Scan") "Scan image" else it }, enabled = !busy && saved == null)
                StudioPanel(spacing = 14.dp) {
                    val locked = busy || saved != null
                    when (method) {
                        "Paste" -> {
                            StudioRoundedField(name, { name = it }, "Deck name", Modifier.fillMaxWidth(), enabled = !locked)
                            Box(Modifier.fillMaxWidth().heightIn(min = 220.dp).background(Color.White, RoundedCornerShape(12.dp)).padding(10.dp)) {
                                StudioTextInput(text, { text = it }, "", Modifier.fillMaxWidth().heightIn(min = 200.dp).semantics { contentDescription = "Decklist text" },
                                    style = sf(17f, design = SfDesign.MONOSPACED), singleLine = false, enabled = !locked)
                            }
                            Text("Commander\n1 Your Commander\n\nDeck\n1 Sol Ring", color = DeckStudioPalette.secondaryInk, style = sf(12f, design = SfDesign.MONOSPACED))
                            StudioPlainButton("Open text or native JSON file", { filePicker.launch(arrayOf("text/plain", "application/json")) }, icon = "doc", enabled = !locked)
                        }
                        "Link" -> {
                            StudioRoundedField(link, { link = it }, "Public Archidekt or Moxfield deck URL", Modifier.fillMaxWidth(), keyboardType = KeyboardType.Uri, enabled = !locked)
                            StudioToggle("Exclude sideboard / maybeboard", excludeSideboards, { excludeSideboards = it }, enabled = !locked)
                            Text("Public links only, subject to provider access. This contacts the deck provider. No sign-in, bot-check bypass or scraping. When a provider is unavailable, paste its text export instead.",
                                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                            StudioPlainButton("Switch to pasted export", { method = "Paste" }, enabled = !locked)
                        }
                        else -> {
                            StudioPlainButton("Choose decklist photo or screenshot", { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                                Modifier.defaultMinSize(minHeight = 60.dp), icon = "text.viewfinder", enabled = !locked)
                            Text("Text recognition runs on this device. Images are not uploaded. Review and correct the recognized text before parsing; this is not a physical-card scanner.",
                                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                        }
                    }
                }
                scanNotice?.let { DeckStudioNotice("Check recognized text", it) }
                error?.let { DeckStudioNotice("Import needs attention", it, "exclamationmark.triangle") }
                if (busy) StudioProgress(if (saving) "Saving deck and import details…" else if (method == "Scan") "Reading image on this device…" else "Preparing review…")
                if (method != "Scan") StudioButton("Review decklist", ::beginPreview, Modifier.semantics { contentDescription = "deckStudio.import.review" },
                    enabled = !busy && resolver != null && saved == null && (if (method == "Link") link else text).isNotBlank())
                preview?.let { value ->
                    ImportReview(value)
                    DeckStudioValidationPanel(validation, value.deck, resolver)
                }
            }
            preview?.let { value ->
                Box(Modifier.fillMaxWidth().background(DeckStudioPalette.background).navigationBarsPadding().padding(16.dp)) {
                    StudioButton(if (saved == null) "Save reviewed draft" else "Finish import", { save(value) },
                        Modifier.fillMaxWidth().semantics { contentDescription = "deckStudio.import.confirm" }, enabled = !busy)
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
            Text(if (preview.unresolvedNames.isEmpty()) "Names resolved in the compiled catalogue" else "${preview.unresolvedNames.size} unresolved names retained",
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
                if (row.cardName in preview.unresolvedNames) Text("Unresolved; retained in draft", color = DeckStudioPalette.warning, style = StudioText.caption)
            }
        }
        if (preview.annotations.isNotEmpty()) {
            StudioDisclosure("${preview.annotations.size} source annotations") {
                preview.annotations.forEach { Text("Line ${it.line}: ${it.text}", color = DeckStudioPalette.ink, style = StudioText.caption) }
            }
            Text("An on-device import receipt preserves these annotations and the reviewed deck. Printing annotations do not change the compiled gameplay identity.",
                color = DeckStudioPalette.ink, style = StudioText.caption2)
        }
    }
}
