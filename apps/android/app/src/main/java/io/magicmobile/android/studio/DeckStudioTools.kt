package io.magicmobile.android.studio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.GameRulesText
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val destinations = listOf("deck" to "Main deck", "commanders" to "Commander(s)", "maybeboard" to "Maybeboard", "sideboard" to "Sideboard",
    "companions" to "Companion")

/** The sheet height a large-detent iOS sheet leaves below the status bar. */
@Composable
fun largeSheetHeight() = (LocalConfiguration.current.screenHeightDp - 56).dp

/** DeckStudioCardSearch.swift: the local catalogue or an online Scryfall reference search. */
@Composable
fun DeckStudioCardSearch(metadata: NativeDeckMetadataCatalogue?, colors: List<String>?, add: (String, String) -> Boolean, resolver: OnDeviceDeckResolver?,
                         model: DeckStudioEditorModel, dismiss: () -> Unit) {
    var source by remember { mutableStateOf("Local") }
    var section by remember { mutableStateOf("deck") }
    var feedback by remember { mutableStateOf<String?>(null) }
    var addError by remember { mutableStateOf<String?>(null) }
    var inspection by remember { mutableStateOf<CardInfo?>(null) }
    LaunchedEffect(section) { feedback = null; addError = null }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding()) {
        StudioSheetBar("Add cards", done = dismiss)
        StudioSegmented(listOf("Local", "Online"), source, { source = it }, { if (it == "Local") "Local catalogue" else "Scryfall — online" },
            Modifier.padding(horizontal = 20.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.Center) {
            StudioMenuPicker(destinations.first { it.first == section }.second, { destinations.map { (value, title) -> MenuEntry.Item(title, checked = value == section) { section = value } } })
        }
        if (source == "Online") DeckStudioOnlineSearch(resolver, section, add, model)
        else LocalCardSearch(metadata, colors, section, add, model, feedback, addError, { feedback = it }, { addError = it }) { inspection = it }
    }
    inspection?.let { card ->
        io.magicmobile.android.board.BoardSheet({ inspection = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            DeckStudioCardInspector(card.name, card) { inspection = null }
        }
    }
}

@Composable
private fun LocalCardSearch(metadata: NativeDeckMetadataCatalogue?, colors: List<String>?, section: String, add: (String, String) -> Boolean,
                            model: DeckStudioEditorModel, feedback: String?, addError: String?, setFeedback: (String?) -> Unit, setError: (String?) -> Unit,
                            inspect: (CardInfo) -> Unit) {
    var query by remember { mutableStateOf("") }
    var type by remember { mutableStateOf("") }
    var setCode by remember { mutableStateOf("") }
    var minMV by remember { mutableStateOf("") }
    var maxMV by remember { mutableStateOf("") }
    var constrainIdentity by remember { mutableStateOf(true) }
    var results by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    val identity = if (constrainIdentity) colors else null
    LaunchedEffect(query, type, identity, setCode, minMV, maxMV, metadata) {
        val catalogue = metadata ?: return@LaunchedEffect
        loading = true; results = emptyList(); setFeedback(null); setError(null)
        val lower = if (minMV.isEmpty()) null else minMV.toDoubleOrNull()
        val upper = if (maxMV.isEmpty()) null else maxMV.toDoubleOrNull()
        if ((minMV.isNotEmpty() && lower == null) || (maxMV.isNotEmpty() && upper == null) || (lower != null && (!lower.isFinite() || lower < 0)) ||
            (upper != null && (!upper.isFinite() || upper < 0)) || (lower != null && upper != null && lower > upper)) {
            setError("Use a nonnegative mana-value range with the minimum no greater than the maximum."); loading = false; return@LaunchedEffect
        }
        delay(150)
        results = withContext(Dispatchers.Default) {
            DeckStudioCatalogueSearch.cards(catalogue, query, type, identity, setCode, lower, upper)
        }
        loading = false; setError(null)
    }
    LazyColumn(Modifier.fillMaxWidth().semantics { contentDescription = "deckStudio.collection.list" }) {
        item {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StudioRoundedField(query, { query = it }, "Card name or rules text", Modifier.weight(1f), onSubmit = {})
                    if (query.isNotEmpty()) StudioIconButton("xmark.circle.fill", "Clear collection search", { query = "" }, tint = DeckStudioPalette.secondaryInk)
                }
                StudioDisclosure("Filters", titleStyle = StudioText.caption) {
                    Column(Modifier.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Type", Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.body)
                            StudioMenuPicker(type.ifEmpty { "All types" }, {
                                listOf(MenuEntry.Item("All types", checked = type.isEmpty()) { type = "" }) +
                                    listOf("Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle").map { MenuEntry.Item(it, checked = type == it) { type = it } }
                            })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StudioRoundedField(minMV, { minMV = it }, "Min MV", Modifier.weight(1f), keyboardType = KeyboardType.Decimal)
                            StudioRoundedField(maxMV, { maxMV = it }, "Max MV", Modifier.weight(1f), keyboardType = KeyboardType.Decimal)
                            StudioRoundedField(setCode, { setCode = it }, "Set code", Modifier.weight(1f), capitalization = KeyboardCapitalization.Characters)
                        }
                        if (colors != null) StudioToggle("Within commander color identity", constrainIdentity, { constrainIdentity = it }, style = StudioText.caption)
                        StudioPlainButton("Reset filters", { type = ""; minMV = ""; maxMV = ""; setCode = ""; constrainIdentity = true })
                    }
                }
                DeckStudioArtworkInvitation()
                addError?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                feedback?.let { Text(it, color = DeckStudioPalette.success, style = StudioText.caption) }
            }
        }
        if (loading) item { StudioProgress("Searching local cards") }
        if (metadata == null) item {
            DeckStudioNotice("Local catalogue unavailable", "Close this editor and retry the catalogue from your library, or use online search for reference.",
                modifier = Modifier.padding(20.dp))
        } else if (!loading && results.isEmpty()) item { StudioContentUnavailable("No matching cards", "magnifyingglass", "Try another name or reset the filters.") }
        items(results, key = { it.name }) { card ->
            Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(52.dp, 73.dp).clip(RoundedCornerShape(6.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxWidth().fillMaxHeight()) }
                    Column(Modifier.weight(1f).clickable { inspect(card) }.semantics { contentDescription = "Inspect ${card.name}" },
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                        Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                        card.manaCost?.let { NativeDeckManaCost(it) }
                        val total = model.cardCount(card.name)
                        if (total > 0) Text("$total in deck · ${model.cardCount(card.name, section)} here", color = DeckStudioPalette.success, style = StudioText.caption2)
                        if (model.needsSingletonReview(card.name, card, section)) {
                            Text("Already in playing deck · check copy limit", color = DeckStudioPalette.warning, style = StudioText.caption2)
                        }
                    }
                    Column {
                        if (model.cardCount(card.name, section) > 0) StudioIconButton("minus.circle", "Remove one ${card.name} from $section", {
                            val before = model.cardCount(card.name, section)
                            model.removeOne(card.name, section)
                            if (model.cardCount(card.name, section) < before) { setFeedback("Removed one ${card.name} from $section"); setError(null) }
                            else { setFeedback(null); setError("Could not remove this card; check the draft.") }
                        })
                        StudioIconButton("plus.circle.fill", "Add ${card.name} to $section", {
                            if (add(card.name, section)) { setFeedback("Added ${card.name} to $section"); setError(null) }
                            else { setFeedback(null); setError("Could not add this card. Check the draft quantity or section limits.") }
                        }, size = 26.dp)
                    }
                }
                HorizontalDivider(Modifier.padding(start = 84.dp), thickness = 0.5.dp, color = DeckStudioPalette.separator)
            }
        }
        item {
            Text("${results.size} matches${if (results.size == 80) " · refine search for more" else ""} · validate before playing",
                Modifier.padding(20.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
        }
    }
}

/** DeckStudioOnlineSearch: only the query goes to Scryfall; unsupported cards are reference, not play. */
@Composable
private fun DeckStudioOnlineSearch(resolver: OnDeviceDeckResolver?, destination: String, add: (String, String) -> Boolean, model: DeckStudioEditorModel) {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<DeckStudioScryfallPage?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var job by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var selected by remember { mutableStateOf<DeckStudioScryfallCard?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }
    fun cancel() { job?.cancel(); job = null; busy = false }
    fun search(page: Int) {
        cancel(); val captured = query
        busy = true; error = null
        job = scope.launch {
            try {
                val value = DeckStudioServices.scryfall.search(captured, page, allowNetwork = true)
                if (query == captured) { result = value; busy = false }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { busy = false; error = failure.message }
        }
    }
    LaunchedEffect(query) { cancel(); result = null; feedback = null }
    LaunchedEffect(destination) { feedback = null }
    LazyColumn(Modifier.fillMaxWidth()) {
        item {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Online Scryfall search", color = DeckStudioPalette.ink, style = StudioText.headline)
                StudioDisclosure("About online search", titleStyle = StudioText.caption) {
                    Text("Only your search query is sent to Scryfall. Cards not supported by the installed engine are available for reference, not play.",
                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StudioRoundedField(query, { query = it }, "Name or Scryfall query", Modifier.weight(1f), onSubmit = { if (!busy && query.isNotBlank()) search(1) })
                    StudioPlainButton("Search", { search(1) }, enabled = !busy && query.isNotBlank())
                }
                DeckStudioArtworkInvitation()
                if (busy) Row(verticalAlignment = Alignment.CenterVertically) { StudioProgress("Searching…", Modifier.weight(1f)); StudioPlainButton("Cancel", ::cancel) }
                error?.let { Text(it, color = DeckStudioPalette.warning, style = StudioText.caption) }
                feedback?.let { Text(it, color = DeckStudioPalette.success, style = StudioText.caption) }
            }
        }
        result?.let { page ->
            item {
                Text("Page ${page.page} · ${if (page.cached) "cached" else "fetched"} ${formatDateTime(page.fetchedAt)}", Modifier.padding(horizontal = 20.dp),
                    color = DeckStudioPalette.ink, style = StudioText.caption2)
            }
            items(page.cards, key = { it.id }) { card ->
                val name = resolver?.canonicalCardName(card.name)
                Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface).padding(horizontal = 20.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(52.dp, 73.dp).clip(RoundedCornerShape(6.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxWidth().fillMaxHeight()) }
                    Column(Modifier.weight(1f).clickable { selected = card }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                        Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                        if (name != null && model.cardCount(name) > 0) Text("${model.cardCount(name)} in deck · ${model.cardCount(name, destination)} here",
                            color = DeckStudioPalette.success, style = StudioText.caption2)
                        if (name == null) Text("Not playable in this engine build", color = DeckStudioPalette.warning, style = StudioText.caption2)
                    }
                    if (name != null) Column {
                        if (model.cardCount(name, destination) > 0) StudioIconButton("minus.circle", "Remove one $name from $destination", {
                            val before = model.cardCount(name, destination)
                            model.removeOne(name, destination)
                            if (model.cardCount(name, destination) < before) { feedback = "Removed one $name from $destination"; error = null }
                            else { feedback = null; error = "Could not remove this card; check the draft." }
                        })
                        StudioIconButton("plus.circle.fill", "Add $name to $destination", {
                            if (add(name, destination)) { feedback = "Added $name to $destination"; error = null }
                            else { feedback = null; error = "Could not add this card; check the draft." }
                        }, size = 26.dp)
                    }
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
                    if (page.page > 1) StudioPlainButton("Previous page", { search(page.page - 1) }, enabled = !busy)
                    Spacer(Modifier.weight(1f))
                    if (page.hasMore && page.page < 10) StudioPlainButton("Next page", { search(page.page + 1) }, enabled = !busy)
                }
            }
        }
    }
    selected?.let { card ->
        io.magicmobile.android.board.BoardSheet({ selected = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            Column(Modifier.fillMaxWidth()) {
                StudioSheetBar("Card reference", done = { selected = null })
                Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) { DeckStudioScryfallReference(card.name, card) }
            }
        }
    }
}

fun formatDateTime(millis: Long): String =
    java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(java.util.Date(millis))

/** DeckStudioCardInspector: bundled metadata offline, an optional Scryfall reference online. */
@Composable
fun DeckStudioCardInspector(name: String, metadata: CardInfo?, dismiss: () -> Unit) {
    Column(Modifier.fillMaxWidth().height(largeSheetHeight())) {
        StudioSheetBar("", done = dismiss)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 24.dp, end = 24.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                io.magicmobile.android.CardArtwork(name, Modifier.widthIn(max = 340.dp).fillMaxWidth().heightIn(min = 120.dp, max = 420.dp)
                    .clip(RoundedCornerShape(14.dp))) {
                    DeckStudioNotice(name, "Artwork is optional. Card text remains available offline.", "rectangle.portrait", Modifier.padding(12.dp))
                }
            }
            Text(name, color = DeckStudioPalette.ink, style = sf(28f, SfWeight.bold))
            DeckStudioArtworkInvitation()
            Text(metadata?.typeLine ?: "Type not in the loaded catalogue", color = DeckStudioPalette.ink, style = StudioText.headline)
            metadata?.manaCost?.let { NativeDeckManaCost(it) }
            GameRulesText(metadata?.oracleText ?: "Text unavailable in the bundled metadata.", cardName = name, style = StudioText.body, color = DeckStudioPalette.ink)
            Text("Bundled selected-printing metadata. Rules and legality follow the installed XMage version.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            DeckStudioScryfallReference(name)
        }
    }
}

/** DeckStudioReplacementPicker: replace one row, or the primary commander, from the exact catalogue. */
@Composable
fun DeckStudioReplacementPicker(metadata: NativeDeckMetadataCatalogue?, commander: Boolean, replace: (String, Boolean) -> Boolean, dismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var keepOld by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val results = remember(query, metadata) { metadata?.search(NativeDeckMetadataCatalogue.SearchFilter(query = query), 80) ?: emptyList() }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StudioSheetBar(if (commander) "Change commander" else "Replace card", cancel = dismiss)
        StudioRoundedField(query, { query = it }, "Search exact catalogue cards", Modifier.padding(horizontal = 20.dp).fillMaxWidth())
        if (commander) {
            StudioToggle("Keep replaced commander in maybeboard", keepOld, { keepOld = it }, Modifier.padding(horizontal = 20.dp), style = StudioText.caption)
            Text("Replaces the primary commander only. Partners remain. One matching main-deck copy is promoted; XMage still checks commander eligibility and duplicates.",
                Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        } else Text("Keeps the row's quantity, section and identity. Undo reverses the replacement.", Modifier.padding(horizontal = 20.dp),
            color = DeckStudioPalette.ink, style = StudioText.caption)
        error?.let { Text(it, Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.danger, style = StudioText.caption) }
        LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 16.dp).clip(RoundedCornerShape(10.dp))) {
            items(results, key = { it.name }) { card ->
                Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface).clickable {
                    if (replace(card.name, keepOld)) dismiss() else error = "The draft changed or this edit exceeds its limits. No partial edit was committed."
                }.defaultMinSize(minHeight = 44.dp).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline)
                    Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                }
                HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
            }
        }
    }
}

/** DeckStudioBasicLandsSheet: a deliberate main-deck edit, not an automatic mana-base recommendation. */
@Composable
fun DeckStudioBasicLandsSheet(draft: NativeDeckDraft, apply: (Map<String, Int>, NativeDeckDraft) -> Boolean, dismiss: () -> Unit) {
    var values by remember { mutableStateOf(NativeDeckDraft.basicLandNames.associateWith { draft.basicLandCount(it) }) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
        Box(Modifier.fillMaxWidth()) {
            StudioSheetBar("Basic lands", done = { if (apply(values, draft)) dismiss() else error = "The draft changed or these counts exceed its limits. Nothing was partially applied." },
                doneTitle = "Apply", cancel = dismiss)
        }
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text("Set main-deck basic-land counts. Other sections, snow basics and nonbasic lands stay unchanged. This is your edit, not an automatic mana-base recommendation.",
                Modifier.padding(vertical = 8.dp), color = DeckStudioPalette.ink, style = StudioText.caption)
            for (name in NativeDeckDraft.basicLandNames) {
                HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
                StudioStepper("$name: ${values[name] ?: 0}", values[name] ?: 0, 0..2000, { values = values + (name to it) })
            }
            error?.let { Text(it, Modifier.padding(vertical = 8.dp), color = DeckStudioPalette.danger, style = StudioText.caption) }
        }
    }
}

/** DeckStudioOrganizationView.swift: private tags, notes and the original import receipt. */
@Composable
fun DeckStudioOrganizationSheet(recordID: String, title: String, dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var history by remember { mutableStateOf<DeckStudioEditHistory<DeckStudioOrganization>?>(null) }
    var revision by remember { mutableStateOf(0) }
    var newTag by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var discardConfirmation by remember { mutableStateOf(false) }
    val isDirty = history?.isDirty == true
    LaunchedEffect(recordID) {
        busy = true
        try {
            val loaded = withContext(Dispatchers.IO) { DeckStudioServices.organization.load(recordID) }
            history = DeckStudioEditHistory(loaded.value); revision = loaded.revision; error = null
        } catch (failure: Exception) { error = failure.message } finally { busy = false }
    }
    fun edit(mutate: (DeckStudioOrganization) -> DeckStudioOrganization) {
        val current = history ?: return
        if (busy) return
        try { history = current.edited { mutate(it).validated() }; error = null } catch (failure: Exception) { error = failure.message }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding()) {
        StudioSheetBar(title.ifEmpty { "Deck details" }, done = {
            val current = history ?: return@StudioSheetBar
            scope.launch {
                busy = true
                try {
                    val saved = withContext(Dispatchers.IO) { DeckStudioServices.organization.save(current.value, recordID, revision) }
                    history = DeckStudioEditHistory(saved.value); revision = saved.revision; error = null
                    dismiss()
                } catch (failure: Exception) { error = failure.message } finally { busy = false }
            }
        }, doneTitle = "Save", doneEnabled = history != null && !busy, cancel = { if (isDirty) discardConfirmation = true else dismiss() }, cancelTitle = "Close")
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            error?.let { FormSection { Text(it, color = DeckStudioPalette.danger, style = StudioText.body) } }
            val value = history?.value
            if (value != null) {
                FormSection("Tags", "Tags are searchable in My Decks. Up to 24 tags; they never change card sections or Commander legality.") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StudioTextInput(newTag, { newTag = it }, "Add a tag", Modifier.weight(1f))
                        StudioPlainButton("Add", {
                            val trimmed = newTag.trim(); edit { it.copy(tags = it.tags + trimmed) }; if (error == null) newTag = ""
                        }, enabled = newTag.isNotBlank() && !busy)
                    }
                    for (tag in value.tags) {
                        HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(tag, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.body)
                            StudioIconButton("minus.circle", "Remove tag $tag", { edit { it.copy(tags = it.tags.filter { t -> t != tag }) } }, tint = DeckStudioPalette.danger)
                        }
                    }
                }
                FormSection("Building notes", "Stored on this device, excluded from backups. Nothing is sent to Scryfall, EDHREC or Commander Spellbook.") {
                    StudioTextInput(value.notes, { text -> edit { it.copy(notes = text) } }, "", Modifier.fillMaxWidth().heightIn(min = 180.dp)
                        .semantics { contentDescription = "Private deck-building notes" }, singleLine = false)
                }
                FormSection {
                    Row {
                        StudioPlainButton("Undo", { history = history?.undone() }, icon = "arrow.uturn.backward", enabled = history?.canUndo == true && !busy)
                        Spacer(Modifier.weight(1f))
                        StudioPlainButton("Redo", { history = history?.redone() }, icon = "arrow.uturn.forward", enabled = history?.canRedo == true && !busy)
                    }
                    Text(if (isDirty) "Unsaved details" else "Saved details", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                }
                if (value.importAnnotations.isNotEmpty() || value.importedFrom != null || value.importReceiptFile != null) {
                    FormSection("Import receipt", "These describe the original import. They are preserved as reference, not kept in sync with later card edits or interpreted as card legality.") {
                        value.importedFrom?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption) }
                        StudioDisclosure("Original import annotations (${value.importAnnotationCount ?: value.importAnnotations.size})") {
                            value.importAnnotations.forEach { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption) }
                            if (value.importAnnotations.isEmpty() && (value.importAnnotationCount ?: 0) > 0) {
                                Text("This large annotation list is preserved in the full original receipt below.", color = DeckStudioPalette.ink, style = StudioText.caption)
                            }
                        }
                        DeckStudioServices.organization.receiptFile(value)?.let { file ->
                            if (file.exists()) StudioPlainButton("Export full original import receipt", { shareText(context, file.readText()) }, icon = "doc.text")
                            else Text("The original receipt file is unavailable on this device; any inline annotations above are still retained.",
                                color = DeckStudioPalette.warning, style = StudioText.caption)
                        }
                    }
                }
                StudioPlainButton("Export these details", { shareText(context, value.json().toString()) }, icon = "square.and.arrow.up")
            } else if (busy) StudioProgress("Loading local details…")
        }
    }
    if (discardConfirmation) ConfirmationDialog("Discard unsaved deck details?", "Previously saved notes, tags, import receipts and deck cards are unchanged.",
        listOf(ConfirmationAction("Discard changes", destructive = true) { dismiss() }), light = true) { discardConfirmation = false }
}

/** An inset-grouped Form section in the light appearance. */
@Composable
fun FormSection(header: String? = null, footer: String? = null, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        header?.let { Text(it.uppercase(), Modifier.padding(start = 16.dp, bottom = 6.dp), color = DeckStudioPalette.secondaryInk, style = sf(13f)) }
        Column(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        footer?.let { Text(it, Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), color = DeckStudioPalette.secondaryInk, style = sf(13f)) }
    }
}
