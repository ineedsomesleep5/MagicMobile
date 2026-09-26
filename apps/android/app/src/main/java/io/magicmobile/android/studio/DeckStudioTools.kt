package io.magicmobile.android.studio

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.GameRulesText
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import java.util.UUID
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
        try {
            results = withContext(Dispatchers.Default) {
                DeckStudioSearchSyntax.cards(catalogue, query, type, identity, setCode, lower, upper)
            }
            setError(null)
        } catch (invalid: DeckStudioSearchSyntax.Invalid) { setError(invalid.message) }
        loading = false
    }
    LazyColumn(Modifier.fillMaxWidth().semantics { contentDescription = "deckStudio.collection.list" }) {
        item {
            Column(Modifier.padding(horizontal = 20.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StudioRoundedField(query, { query = it }, "Card name or rules text", Modifier.weight(1f), onSubmit = {})
                    if (query.isNotEmpty()) StudioIconButton("xmark.circle.fill", "Clear collection search", { query = "" }, tint = DeckStudioPalette.secondaryInk)
                }
                Text(searchSyntaxHint, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
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

/**
 * DeckStudioReplacementPicker: replace one row, or the primary commander, from the exact catalogue.
 * A card replacement stays within the commander's colour identity once there is one.
 */
@Composable
fun DeckStudioReplacementPicker(metadata: NativeDeckMetadataCatalogue?, commander: Boolean, replace: (String, Boolean) -> Boolean,
                                colors: List<String>? = null, dismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var keepOld by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val identity = colors.takeUnless { commander }
    var results by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    LaunchedEffect(query, metadata, identity) {
        val catalogue = metadata ?: run { results = emptyList(); return@LaunchedEffect }
        if (query.isNotEmpty()) delay(120)
        // Identity search merges one pass per colour subset, so it runs off the main thread.
        results = withContext(Dispatchers.Default) {
            if (identity != null) DeckStudioCatalogueSearch.cards(catalogue, query, allowedIdentity = identity)
            else catalogue.search(NativeDeckMetadataCatalogue.SearchFilter(query = query), 80)
        }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StudioSheetBar(if (commander) "Change commander" else "Replace card", cancel = dismiss)
        StudioRoundedField(query, { query = it }, "Search exact catalogue cards", Modifier.padding(horizontal = 20.dp).fillMaxWidth())
        if (commander) {
            StudioToggle("Keep replaced commander in maybeboard", keepOld, { keepOld = it }, Modifier.padding(horizontal = 20.dp), style = StudioText.caption)
            Text("Replaces the primary commander only. Partners remain. One matching main-deck copy is promoted; XMage still checks commander eligibility and duplicates.",
                Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        } else {
            Text("Keeps the row's quantity, section and identity. Undo reverses the replacement.", Modifier.padding(horizontal = 20.dp),
                color = DeckStudioPalette.ink, style = StudioText.caption)
            if (identity != null) Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Within commander color identity", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                DeckStudioColorIdentity(identity, pipSize = 16.dp)
            }
        }
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

/** The Add cards local-search syntax, shown under the search field. */
const val searchSyntaxHint = "Search syntax: t:creature  o:draw  mv<=3  mv>=2  id:wu"

private val bulkDestinations = listOf("deck", "commanders", "companions", "sideboard", "maybeboard")

/** An undoable edit's toast; `generation` is the history generation the edit produced (null: nothing to undo). */
data class DeckStudioUndoToast(val message: String, val generation: UUID?, val id: UUID = UUID.randomUUID())

/**
 * Builder state for one open deck: Select mode, the quick-check filter and the builder sheets. One
 * holder keeps the shared workspace screen's own state untouched.
 */
class DeckStudioBuilderState {
    var selecting by mutableStateOf(false)
    var selection by mutableStateOf<Set<UUID>>(emptySet())
    var preflightFilter by mutableStateOf<DeckStudioPreflight.Kind?>(null)
    var showTextEditor by mutableStateOf(false)
    var showNewDeckCommander by mutableStateOf(false)
    var showSetQuantity by mutableStateOf(false)
    var preview by mutableStateOf<String?>(null)
    var toast by mutableStateOf<DeckStudioUndoToast?>(null)
    var newDeckPrompted = false

    fun toggle(id: UUID) { selection = if (id in selection) selection - id else selection + id }
    fun endSelection() { selecting = false; selection = emptySet() }
    fun announce(message: String, model: DeckStudioEditorModel?) { toast = DeckStudioUndoToast(message, model?.history?.generation) }

    /** One bulk action is one undo step, over the selected rows that still exist. */
    fun bulk(model: DeckStudioEditorModel, message: (Int) -> String, operation: (NativeDeckDraft, Set<UUID>) -> NativeDeckDraft): Boolean {
        val ids = selection.filter { id -> model.draft.rows.any { it.id == id } }.toSet()
        if (ids.isEmpty() || !model.change { operation(it, ids) }) return false
        announce(message(ids.size), model); endSelection()
        return true
    }
}

/** A dark toast above the bottom bar with Undo while that edit is still the latest one. */
@Composable
fun DeckStudioUndoToastView(toast: DeckStudioUndoToast, model: DeckStudioEditorModel, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    LaunchedEffect(toast.id) { delay(4000); dismiss() }
    val canUndo = toast.generation != null && model.history.generation == toast.generation && model.history.canUndo && !model.readOnly
    Row(modifier.fillMaxWidth().background(DeckStudioPalette.ink, RoundedCornerShape(14.dp)).padding(start = 16.dp, end = 4.dp)
        .defaultMinSize(minHeight = 48.dp).semantics { liveRegion = LiveRegionMode.Polite }, verticalAlignment = Alignment.CenterVertically) {
        Text(toast.message, Modifier.weight(1f).padding(vertical = 10.dp), color = Color.White, style = StudioText.subheadline, maxLines = 2)
        if (toast.generation != null) Box(Modifier.defaultMinSize(minWidth = 64.dp, minHeight = 44.dp).alpha(if (canUndo) 1f else 0.4f)
            .clickable(enabled = canUndo, role = Role.Button) { model.undo(); dismiss() }.semantics { contentDescription = "Undo: ${toast.message}" },
            contentAlignment = Alignment.Center) {
            Text("Undo", color = Color.White, style = StudioText.subheadline.weight(SfWeight.semibold))
        }
    }
}

/**
 * The live deck check under the workspace header: "97/100", then a chip per quick-check problem.
 * Tapping a chip filters the Cards list to those rows. It never blocks Play.
 */
@Composable
fun DeckStudioPreflightBar(check: DeckStudioPreflight, filter: DeckStudioPreflight.Kind?, select: (DeckStudioPreflight.Chip) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(14.dp)).padding(12.dp).testTag("deckStudio.preflight"),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("${check.count}/${check.target}", Modifier.semantics { contentDescription = "${CardCountText.label(check.count)} of ${check.target}" },
                color = if (check.count > check.target) DeckStudioPalette.warning else DeckStudioPalette.ink, style = StudioText.headline)
            Text(DeckStudioPreflight.label, Modifier.weight(1f), color = DeckStudioPalette.secondaryInk, style = StudioText.caption2, maxLines = 2)
        }
        Box(Modifier.fillMaxWidth().height(6.dp).background(DeckStudioPalette.separator, CircleShape)) {
            Box(Modifier.fillMaxWidth((check.count.toFloat() / check.target).coerceIn(0f, 1f)).height(6.dp)
                .background(if (check.count == check.target) DeckStudioPalette.success else DeckStudioPalette.accent, CircleShape))
        }
        if (check.chips.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (chip in check.chips) {
                val selected = filter == chip.kind
                Row(Modifier.defaultMinSize(minHeight = 44.dp).background(if (selected) DeckStudioPalette.ink else DeckStudioPalette.surfaceElevated, CircleShape)
                    .border(1.dp, if (selected) Color.Transparent else DeckStudioPalette.warning.copy(alpha = 0.45f), CircleShape).clip(CircleShape)
                    .clickable(role = Role.Button) { select(chip) }.padding(horizontal = 12.dp)
                    .semantics { contentDescription = chip.title + if (selected) ", showing these cards" else ""; stateDescription = if (selected) "Selected" else "" },
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfImage(if (chip.kind == DeckStudioPreflight.Kind.MISSING_COMMANDER) "crown" else "exclamationmark.triangle",
                        if (selected) Color.White else DeckStudioPalette.warning, 12.dp)
                    Text(chip.title, color = if (selected) Color.White else DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold), maxLines = 1)
                }
            }
        }
    }
}

/**
 * Quick Add above the Cards list: "2 Sol Ring" or "2x Sol Ring" with the top five local matches.
 * Cards go to Main unless Maybeboard is on; the keyboard stays open and each add can be undone.
 */
@Composable
fun DeckStudioQuickAddBar(metadata: NativeDeckMetadataCatalogue?, model: DeckStudioEditorModel, added: (String) -> Unit, modifier: Modifier = Modifier) {
    var text by remember { mutableStateOf("") }
    var maybeboard by rememberSaveable { mutableStateOf(false) }
    var suggestions by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var note by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(text, metadata) {
        val catalogue = metadata
        if (catalogue == null || text.isBlank()) { suggestions = emptyList(); return@LaunchedEffect }
        delay(120)
        suggestions = withContext(Dispatchers.Default) { DeckStudioQuickAdd.suggestions(catalogue, text) }
    }
    fun add(name: String, entry: DeckStudioQuickAdd.Entry) {
        val section = if (maybeboard) "maybeboard" else "deck"
        if (model.change { DeckStudioEditorOperations.addCopies(it, name, section, entry.quantity) }) {
            text = ""; suggestions = emptyList(); note = entry.note; error = null
            added("Added ${entry.quantity} $name" + if (maybeboard) " to maybeboard" else "")
        } else error = "Could not add $name. Check the draft's quantity limits."
    }
    fun submit() {
        val entry = try { DeckStudioQuickAdd.parse(text) } catch (invalid: DeckStudioQuickAdd.Invalid) { error = invalid.message; return } ?: return
        val catalogue = metadata ?: run { error = "The local card catalogue isn't loaded yet."; return }
        val name = DeckStudioQuickAdd.resolve(catalogue, entry) ?: run { error = "No card in the local catalogue matches “${entry.name}”."; return }
        add(name, entry)
    }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.weight(1f).defaultMinSize(minHeight = 44.dp).background(Color.White, RoundedCornerShape(12.dp)).padding(start = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SfImage("plus.circle.fill", DeckStudioPalette.ink, 18.dp)
                BasicTextField(text, { text = it; error = null; note = null }, Modifier.weight(1f).testTag("deckStudio.quickAdd").semantics { contentDescription = "Quick add a card" },
                    singleLine = true, textStyle = StudioText.body.copy(color = DeckStudioPalette.ink), cursorBrush = SolidColor(DeckStudioPalette.ink),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                    // Handling Done here (without clearing focus) keeps the keyboard open for the next card.
                    keyboardActions = KeyboardActions(onDone = { submit() }),
                    decorationBox = { inner ->
                        Box {
                            if (text.isEmpty()) Text("Quick add · 2 Sol Ring", color = DeckStudioPalette.secondaryInk.copy(alpha = 0.6f), style = StudioText.body, maxLines = 1)
                            inner()
                        }
                    })
                if (text.isNotEmpty()) StudioIconButton("xmark.circle.fill", "Clear quick add", { text = ""; error = null }, tint = DeckStudioPalette.secondaryInk, size = 17.dp)
            }
            Box(Modifier.defaultMinSize(minHeight = 44.dp).background(if (maybeboard) DeckStudioPalette.ink else DeckStudioPalette.surfaceElevated, RoundedCornerShape(12.dp))
                .border(1.dp, if (maybeboard) Color.Transparent else DeckStudioPalette.separator, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))
                .clickable { maybeboard = !maybeboard }.padding(horizontal = 10.dp)
                .semantics { role = Role.Switch; contentDescription = "Add to maybeboard"; stateDescription = if (maybeboard) "On" else "Off" },
                contentAlignment = Alignment.Center) {
                Text("Maybeboard", color = if (maybeboard) Color.White else DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
            }
        }
        if (text.isNotBlank()) for (card in suggestions) {
            val entry = runCatching { DeckStudioQuickAdd.parse(text) }.getOrNull()
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).background(DeckStudioPalette.surface, RoundedCornerShape(10.dp)).clip(RoundedCornerShape(10.dp))
                .clickable { entry?.let { add(card.name, it) } }.padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Add ${entry?.quantity ?: 1} ${card.name}" + if (maybeboard) " to maybeboard" else "" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                val existing = model.cardCount(card.name)
                if (existing > 0) Text("$existing in deck", color = DeckStudioPalette.success, style = StudioText.caption2)
                SfImage("plus", DeckStudioPalette.ink, 14.dp)
            }
        }
        error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
        note?.let { Text(it, color = DeckStudioPalette.secondaryInk, style = StudioText.caption) }
    }
}

/** Select mode's bottom bar: Move to…, Set quantity and Remove, each one undo step. */
@Composable
fun DeckStudioBulkBar(count: Int, move: (String) -> Unit, setQuantity: () -> Unit, remove: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("${CardCountText.label(count)} selected", color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StudioMenu({ bulkDestinations.map { value -> MenuEntry.Item(value.replaceFirstChar { it.uppercase() }) { move(value) } } }, Modifier.weight(1f), enabled = count > 0) {
                Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = DeckStudioMetrics.controlHeight).alpha(if (count > 0) 1f else 0.45f)
                    .background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(DeckStudioMetrics.controlRadius))
                    .border(1.dp, DeckStudioPalette.separator, RoundedCornerShape(DeckStudioMetrics.controlRadius)), contentAlignment = Alignment.Center) {
                    Text("Move to…", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 1)
                }
            }
            StudioButton("Set quantity", setQuantity, Modifier.weight(1f), primary = false, enabled = count > 0, compactText = true)
            StudioButton("Remove", remove, Modifier.weight(1f).semantics { contentDescription = "Remove selected cards" }, primary = false, enabled = count > 0,
                icon = "trash", compactText = true)
        }
    }
}

/** Bulk Set quantity: every selected row gets exactly this many copies. */
@Composable
fun DeckStudioSetQuantitySheet(count: Int, apply: (Int) -> Boolean, dismiss: () -> Unit) {
    var value by remember { mutableStateOf(1) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
        StudioSheetBar("Set quantity", done = { if (apply(value)) dismiss() else error = "Nothing was changed. The draft changed or this exceeds its 2,000-card limit." },
            doneTitle = "Apply", cancel = dismiss)
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Each of the ${CardCountText.label(count)} selected gets exactly this many copies. Undo reverses all of them.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            StudioStepper("Copies: $value", value, 1..2000, { value = it; error = null })
            error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
        }
    }
}

/**
 * Edit as text: the whole deck in the plain-text export format. "Review changes" lists the cards
 * added and removed; applying is one undo step.
 */
@Composable
fun DeckStudioTextEditorSheet(draft: NativeDeckDraft, apply: (DeckStudioTextEdit.Review, NativeDeckDraft) -> Boolean, copy: (String) -> Unit, dismiss: () -> Unit) {
    val original = remember { draft }
    val initial = remember { runCatching { DeckStudioTextEdit.text(original) } }
    var text by rememberSaveable { mutableStateOf(initial.getOrNull() ?: "") }
    var review by remember { mutableStateOf<DeckStudioTextEdit.Review?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var copied by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding()) {
        val current = review
        if (current == null) {
            StudioSheetBar("Edit as text", done = {
                try { review = DeckStudioTextEdit.review(original, text); error = null } catch (failure: Exception) { error = failure.message ?: "Check the list and try again." }
            }, doneTitle = "Review changes", doneEnabled = initial.isSuccess, cancel = dismiss)
            if (initial.isFailure) DeckStudioNotice("Plain text unavailable", "Use JSON export to preserve this draft's custom sections. Your deck is unchanged.",
                "exclamationmark.triangle", Modifier.padding(20.dp))
            else Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("One card per line, like 2 Sol Ring, under Commander, Deck, Companion, Sideboard or Maybeboard.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                BasicTextField(text, { text = it; error = null; copied = false }, Modifier.fillMaxWidth().heightIn(min = 320.dp).background(Color.White, RoundedCornerShape(12.dp))
                    .padding(12.dp).testTag("deckStudio.textEditor").semantics { contentDescription = "Deck list text" },
                    textStyle = StudioText.body.copy(color = DeckStudioPalette.ink), cursorBrush = SolidColor(DeckStudioPalette.ink),
                    // Exact card names are case-sensitive, so the keyboard must not recapitalize them.
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
                StudioPlainButton(if (copied) "List copied" else "Copy list", { copy(text); copied = true }, icon = if (copied) "checkmark" else "doc.on.doc")
            }
        } else {
            StudioSheetBar("Review changes", done = {
                if (apply(current, original)) dismiss() else error = "Nothing was applied. The deck changed while you were editing, or the list exceeds its limits."
            }, doneTitle = "Apply", doneEnabled = !current.isEmpty, cancel = { review = null; error = null }, cancelTitle = "Edit")
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                if (current.isEmpty) StudioContentUnavailable("No changes", "checkmark.circle", "The list matches your deck.")
                if (current.ignoredLines > 0) Text("Printings, tags and custom headings in the text are ignored.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                if (current.added.isNotEmpty()) FormSection("Added · ${CardCountText.label(current.added.sumOf { it.quantity })}") {
                    for (change in current.added) Text("+${change.quantity} ${change.name} · ${DeckStudioTextEdit.boardTitle(change.board)}",
                        color = DeckStudioPalette.success, style = StudioText.subheadline)
                }
                if (current.removed.isNotEmpty()) FormSection("Removed · ${CardCountText.label(current.removed.sumOf { it.quantity })}") {
                    for (change in current.removed) Text("−${change.quantity} ${change.name} · ${DeckStudioTextEdit.boardTitle(change.board)}",
                        color = DeckStudioPalette.danger, style = StudioText.subheadline)
                }
                if (!current.isEmpty) Text("Applying is one edit: Undo reverses all of it.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
        }
    }
}

/**
 * Commander-first new decks: legendary creatures and cards whose text says they can be your
 * commander. Skipping leaves an empty draft.
 */
@Composable
fun DeckStudioCommanderPicker(metadata: NativeDeckMetadataCatalogue, pick: (String) -> Boolean, skip: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(query, metadata) {
        if (query.isNotEmpty()) delay(120)
        results = withContext(Dispatchers.Default) { DeckStudioCommanderSearch.candidates(metadata, query) }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StudioSheetBar("Choose a commander", cancel = skip, cancelTitle = "Skip")
        StudioSearchField(query, { query = it; error = null }, "Search commanders", Modifier.padding(horizontal = 20.dp), radius = 12.dp, padding = 12.dp,
            clearLabel = "Clear commander search")
        Text("Legendary creatures and cards that say they can be your commander. Your deck takes its name; rename it anytime.",
            Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        error?.let { Text(it, Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.danger, style = StudioText.caption) }
        LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 16.dp).clip(RoundedCornerShape(10.dp)).testTag("deckStudio.commanderPicker")) {
            items(results, key = { it.name }) { card ->
                Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface).clickable {
                    if (!pick(card.name)) error = "This commander could not be added. Your draft is unchanged."
                }.defaultMinSize(minHeight = 44.dp).padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(38.dp, 52.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxWidth().fillMaxHeight()) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                        Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                    DeckStudioColorIdentity(card.colorIdentity, pipSize = 16.dp)
                }
                HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
            }
        }
    }
}

/** Copy list: the plain-text export (Commander / Deck / Sideboard / Maybeboard headings) that Archidekt and Moxfield import. */
fun copyDeckList(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("Deck list", text))
}
