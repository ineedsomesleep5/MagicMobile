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
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.GameRulesText
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
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
        io.magicmobile.android.board.BoardSheet({ inspection = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
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
    // The deck's cards and the search results share one layout choice (the Cards toolbar's toggle).
    val cardLayout by io.magicmobile.android.ui.AppPreferences.string("deckStudio.cards.layout.v1", "Grid")
    // Sleeves at least 100 points wide.
    val gridColumns = maxOf(2, (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp - 40 + 10) / 110)
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
            DeckStudioBuilderSearch.cards(catalogue, query, type, identity, setCode, lower, upper)
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
                Text(DeckStudioPlayText.searchHint, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                // On by default once the deck has a commander, and visible so the limit is never a surprise.
                if (colors != null) StudioToggle(DeckStudioPlayText.withinIdentity, constrainIdentity, { constrainIdentity = it }, style = StudioText.caption)
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
        fun addOne(card: CardInfo) {
            if (add(card.name, section)) { setFeedback("Added ${card.name} to $section"); setError(null) }
            else { setFeedback(null); setError("Could not add this card. Check the draft quantity or section limits.") }
        }
        fun removeOne(card: CardInfo) {
            val before = model.cardCount(card.name, section)
            model.removeOne(card.name, section)
            if (model.cardCount(card.name, section) < before) { setFeedback("Removed one ${card.name} from $section"); setError(null) }
            else { setFeedback(null); setError("Could not remove this card; check the draft.") }
        }
        // The results in sleeves, like the deck's own cards (Caleb, 2026-10-05 and 2026-10-06): the plus (or the
        // card's right half) adds a copy; once the deck holds it the minus (or the left half) takes one away.
        if (cardLayout == "Grid") items(results.chunked(gridColumns), key = { "grid/${it.first().name}" }) { chunk ->
            BinderSleeveRow(chunk, gridColumns, Modifier.padding(horizontal = 8.dp)) { card, modifier ->
                BinderSleeve(card.name, model.cardCount(card.name, section), card, modifier,
                    notes = if (model.needsSingletonReview(card.name, card, section)) listOf("Already in playing deck, check the copy limit") else emptyList(),
                    addLabel = "Add ${card.name} to $section", removeLabel = "Remove one ${card.name} from $section", tapLabel = "Inspect ${card.name}",
                    add = { io.magicmobile.android.ui.GameAudio.play(io.magicmobile.android.ui.GameSound.UI_TICK); addOne(card) },
                    remove = { io.magicmobile.android.ui.GameAudio.play(io.magicmobile.android.ui.GameSound.UI_TICK); removeOne(card) },
                    tap = { inspect(card) }, preview = { inspect(card) })
            }
        } else items(results, key = { it.name }) { card ->
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
        io.magicmobile.android.board.BoardSheet({ selected = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
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
 * A replacement stays within the commander's color identity unless the player turns that off.
 */
@Composable
fun DeckStudioReplacementPicker(metadata: NativeDeckMetadataCatalogue?, commander: Boolean, replace: (String, Boolean) -> Boolean,
                                colors: List<String>? = null, dismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var keepOld by remember { mutableStateOf(true) }
    var constrainIdentity by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val identity = if (!commander && constrainIdentity) colors else null
    var results by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    LaunchedEffect(query, metadata, identity) {
        val catalogue = metadata ?: run { results = emptyList(); return@LaunchedEffect }
        if (query.isNotEmpty()) delay(120)
        // Identity-limited searches scan several identity buckets, so they run off the main thread.
        results = withContext(Dispatchers.Default) { DeckStudioBuilderSearch.cards(catalogue, query, allowedIdentity = identity) }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StudioSheetBar(if (commander) "Change commander" else "Replace card", cancel = dismiss)
        StudioRoundedField(query, { query = it }, "Search exact catalogue cards", Modifier.padding(horizontal = 20.dp).fillMaxWidth())
        if (!commander && colors != null) {
            StudioToggle(DeckStudioPlayText.withinIdentity, constrainIdentity, { constrainIdentity = it }, Modifier.padding(horizontal = 20.dp), style = StudioText.caption)
        }
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
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp)) {
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
        Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        footer?.let { Text(it, Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), color = DeckStudioPalette.secondaryInk, style = sf(13f)) }
    }
}

/**
 * Builder state for one open deck: Select mode, the quick-check filter and the builder sheets. One
 * holder keeps the shared workspace screen's own state untouched.
 */
class DeckStudioBuilderState {
    var selecting by mutableStateOf(false)
    var selection by mutableStateOf<Set<UUID>>(emptySet())
    /** A quick-check chip or Fix deck narrows the Cards list. */
    var listFilter by mutableStateOf<DeckStudioListFilter?>(null)
    var showTextEditor by mutableStateOf(false)
    var showCommanderFirst by mutableStateOf(false)
    var offeredCommanderFirst = false
    var showBulkQuantity by mutableStateOf(false)
    var confirmBulkRemove by mutableStateOf(false)
    var preview by mutableStateOf<String?>(null)
    /** A long-pressed row: the large preview with the row's card actions. */
    var previewRow by mutableStateOf<UUID?>(null)
    var listCopied by mutableStateOf(0)

    fun toggleSelecting() { selecting = !selecting; selection = emptySet() }
    fun endSelection() { selecting = false; selection = emptySet() }
    fun toggle(id: UUID) { selection = if (id in selection) selection - id else selection + id }
    /** The selection that still exists in the draft. */
    fun liveSelection(draft: NativeDeckDraft): Set<UUID> = selection.intersect(draft.rows.map { it.id }.toSet())
}

/** Live quick check on the title plate: the brass gauge and leather chips. Tapping a row issue filters the Cards list. */
@Composable
fun DeckStudioPreflightBar(preflight: DeckStudioPreflight, filter: DeckStudioPreflight.Issue?, setFilter: (DeckStudioPreflight.Issue?) -> Unit,
                           chooseCommander: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().testTag("deckStudio.quickCheck"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Ruled off from the plate above it rather than boxed.
        GrimoireRule()
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("${preflight.count}/${DeckStudioPreflight.targetCount}",
                Modifier.semantics { contentDescription = "${CardCountText.label(preflight.count)} of ${DeckStudioPreflight.targetCount}" },
                color = DeckStudioPalette.ink, style = sf(17f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
            Text(preflight.summary, color = if (preflight.issueCount == 0) DeckStudioPalette.success else DeckStudioPalette.warning,
                style = sf(13f, SfWeight.semibold))
        }
        BinderGauge(preflight.count, Modifier.clearAndSetSemantics {}, target = DeckStudioPreflight.targetCount, showsCount = false)
        if (preflight.activeIssues.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (issue in preflight.activeIssues) {
                val selected = filter == issue
                Box(Modifier.defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) {
                    if (issue == DeckStudioPreflight.Issue.MISSING_COMMANDER) chooseCommander() else setFilter(if (selected) null else issue)
                }.semantics {
                    contentDescription = if (issue == DeckStudioPreflight.Issue.MISSING_COMMANDER) issue.title else "${issue.title}, ${CardCountText.label(preflight.rows(issue).size)}"
                    stateDescription = if (issue == DeckStudioPreflight.Issue.MISSING_COMMANDER) "Choose a commander" else if (selected) "Shows every card again" else "Shows only these cards"
                    this.selected = selected
                }, contentAlignment = Alignment.Center) {
                    BinderChip(preflight.chipTitle(issue), icon = if (issue == DeckStudioPreflight.Issue.MISSING_COMMANDER) "crown" else "exclamationmark.triangle",
                        chosen = selected)
                }
            }
        }
        Text(DeckStudioPreflight.caption, color = DeckStudioPalette.secondaryInk, style = sf(12f))
    }
}

/** Under the Cards toolbar while a quick-check chip or Fix deck filters the list. */
@Composable
fun DeckStudioIssueFilterRow(filter: DeckStudioListFilter, showAll: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        SfImage("exclamationmark.triangle", DeckStudioPalette.warning, 13.dp)
        Text(filter.title, Modifier.weight(1f), color = DeckStudioPalette.warning, style = StudioText.caption.weight(SfWeight.semibold))
        StudioPlainButton(DeckStudioPlayText.showAll, showAll, Modifier.testTag("deckStudio.cards.showAll"), style = StudioText.caption.weight(SfWeight.semibold))
    }
}

private data class QuickAddToast(val message: String, val generation: UUID)

/**
 * Persistent Quick Add beside Add cards: type "2x Sol Ring", pick from the top five local matches,
 * and keep typing. Each add can be undone from its toast.
 */
@Composable
fun DeckStudioQuickAddBar(metadata: NativeDeckMetadataCatalogue?, model: DeckStudioEditorModel, openSearch: () -> Unit, modifier: Modifier = Modifier,
                          binder: Boolean = false) {
    // At the foot of a binder page, on leather: parchment lettering, a dark well to write in and brass plaques.
    val hintInk = if (binder) io.magicmobile.android.ui.TavernPalette.parchment.copy(alpha = 0.85f) else DeckStudioPalette.secondaryInk
    var text by remember { mutableStateOf("") }
    var maybeboard by rememberSaveable { mutableStateOf(false) }
    var suggestions by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var note by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var toast by remember { mutableStateOf<QuickAddToast?>(null) }
    var focused by remember { mutableStateOf(false) }
    val parsed = DeckStudioQuickAdd.parse(text) { metadata?.card(it) != null }
    LaunchedEffect(parsed?.name, metadata) {
        val catalogue = metadata; val name = parsed?.name
        if (catalogue == null || name == null) { suggestions = emptyList(); return@LaunchedEffect }
        delay(100)
        suggestions = withContext(Dispatchers.Default) { DeckStudioBuilderSearch.nameSuggestions(catalogue, name, 5) }
    }
    LaunchedEffect(toast) { val shown = toast ?: return@LaunchedEffect; delay(4000); if (toast == shown) toast = null }
    fun commit(chosen: CardInfo?) {
        if (text.isBlank()) return
        val entry = parsed ?: run { error = DeckStudioPlayText.quickAddNeedsName; return }
        val catalogue = metadata ?: run { error = DeckStudioPlayText.catalogueLoading; return }
        val card = chosen ?: catalogue.card(entry.name) ?: DeckStudioBuilderSearch.nameSuggestions(catalogue, entry.name, 1).firstOrNull()
            ?: run { error = DeckStudioPlayText.noCardNamed(entry.name); return }
        val board = if (maybeboard) "maybeboard" else "deck"
        if (model.change { DeckStudioEditorOperations.addCopies(it, card.name, board, entry.quantity) }) {
            toast = QuickAddToast(DeckStudioPlayText.added(entry.quantity, card.name, maybeboard), model.history.generation)
            note = entry.note; error = null; text = ""; suggestions = emptyList()
        } else error = DeckStudioPlayText.quickAddFailed
    }
    val shape = RoundedCornerShape(DeckStudioMetrics.controlRadius)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (focused && suggestions.isNotEmpty()) Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(12.dp))
            .border(1.dp, DeckStudioPalette.separator, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))) {
            suggestions.forEachIndexed { index, card ->
                Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { commit(card) }.padding(horizontal = 12.dp)
                    .clearAndSetSemantics { contentDescription = "Quick add ${parsed?.quantity ?: 1} ${card.name}" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(card.name, Modifier.weight(1f, fill = false), color = DeckStudioPalette.ink, style = StudioText.subheadline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.weight(1f))
                    Text(card.typeLine ?: "", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (index < suggestions.size - 1) HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
            }
        }
        when {
            error != null -> Text(error ?: "", color = if (binder) rgb(1.0, 0.62, 0.5) else DeckStudioPalette.danger, style = StudioText.caption)
            note != null -> Text(note ?: "", color = hintInk, style = StudioText.caption)
            focused && text.isEmpty() -> Text(DeckStudioPlayText.quickAddHint, color = hintInk, style = StudioText.caption)
        }
        toast?.let { shown ->
            Row(Modifier.fillMaxWidth().background(DeckStudioPalette.ink, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp)
                .semantics { liveRegion = LiveRegionMode.Polite }, verticalAlignment = Alignment.CenterVertically) {
                Text(shown.message, Modifier.weight(1f), color = DeckStudioPalette.surfaceElevated, style = StudioText.caption.weight(SfWeight.semibold), maxLines = 2)
                val canUndo = model.history.generation == shown.generation
                Box(Modifier.defaultMinSize(minWidth = 44.dp, minHeight = 44.dp).alpha(if (canUndo) 1f else 0.4f)
                    .clickable(enabled = canUndo, role = Role.Button) { model.undo(); toast = null }.testTag("deckStudio.quickAdd.undo"),
                    contentAlignment = Alignment.Center) {
                    Text(DeckStudioPlayText.undo, color = DeckStudioPalette.surfaceElevated, style = StudioText.caption.weight(SfWeight.semibold))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val fieldInk = if (binder) io.magicmobile.android.ui.TavernPalette.parchment else DeckStudioPalette.ink
            Row(Modifier.weight(1f).defaultMinSize(minHeight = DeckStudioMetrics.controlHeight)
                .background(if (binder) Color.Black.copy(alpha = 0.5f) else DeckStudioPalette.surfaceElevated, shape)
                .border(1.dp, if (binder) Binder.brassLight.copy(alpha = 0.3f) else DeckStudioPalette.separator, shape).padding(start = 10.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SfImage("magnifyingglass", if (binder) Binder.brassLight else DeckStudioPalette.secondaryInk, 15.dp)
                BasicTextField(text, { text = it; if (it.isNotEmpty()) { error = null; note = null } },
                    Modifier.weight(1f).onFocusChanged { focused = it.isFocused }.testTag("deckStudio.quickAdd").semantics { contentDescription = "Quick add" },
                    singleLine = true, textStyle = StudioText.body.copy(color = fieldInk), cursorBrush = SolidColor(if (binder) Binder.brassLight else DeckStudioPalette.ink),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                    // Handling Done here, without clearing focus, keeps the keyboard up for the next card.
                    keyboardActions = KeyboardActions(onDone = { commit(null) }),
                    decorationBox = { inner ->
                        Box {
                            if (text.isEmpty()) Text(DeckStudioPlayText.quickAdd, color = if (binder) fieldInk.copy(alpha = 0.5f) else DeckStudioPalette.secondaryInk.copy(alpha = 0.6f),
                                style = StudioText.body, maxLines = 1)
                            inner()
                        }
                    })
                if (text.isNotEmpty()) StudioIconButton("xmark.circle.fill", "Clear quick add", { text = "" }, tint = if (binder) fieldInk.copy(alpha = 0.7f) else DeckStudioPalette.secondaryInk, size = 16.dp)
            }
            if (binder) {
                BinderPlaque(Modifier.testTag("deckStudio.quickAdd.maybeboard"), title = if (maybeboard) DeckStudioPlayText.quickAddMaybe else DeckStudioPlayText.quickAddMain,
                    on = maybeboard, label = DeckStudioPlayText.quickAddMaybeboard + if (maybeboard) ", on" else ", off") { maybeboard = !maybeboard }
                BinderPlaque(Modifier.testTag("deckStudio.addCards"), title = DeckStudioPlayText.addCards, icon = "plus") { openSearch() }
            } else {
            Box(Modifier.defaultMinSize(minWidth = 52.dp, minHeight = DeckStudioMetrics.controlHeight)
                .background(if (maybeboard) DeckStudioPalette.accent else DeckStudioPalette.surfaceElevated, shape)
                .border(1.dp, if (maybeboard) Color.Transparent else DeckStudioPalette.separator, shape).clip(shape)
                .clickable { maybeboard = !maybeboard }.padding(horizontal = 8.dp).testTag("deckStudio.quickAdd.maybeboard")
                .semantics { role = Role.Switch; contentDescription = DeckStudioPlayText.quickAddMaybeboard; stateDescription = if (maybeboard) "On" else "Off" },
                contentAlignment = Alignment.Center) {
                Text(if (maybeboard) DeckStudioPlayText.quickAddMaybe else DeckStudioPlayText.quickAddMain, color = if (maybeboard) DeckStudioPalette.surfaceElevated else DeckStudioPalette.ink,
                    style = StudioText.caption.weight(SfWeight.semibold))
            }
            Row(Modifier.defaultMinSize(minHeight = DeckStudioMetrics.controlHeight).background(DeckStudioPalette.ink, shape).clip(shape)
                .clickable(role = Role.Button) { openSearch() }.padding(horizontal = 12.dp).semantics { contentDescription = "deckStudio.addCards" },
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("plus", DeckStudioPalette.surfaceElevated, 14.dp)
                Text(DeckStudioPlayText.addCards, color = DeckStudioPalette.surfaceElevated, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 1)
            }
            }
        }
    }
}

/** Bottom bar for multi-select. Each action is one undo step. "considering" rows count as maybeboard, so it is not offered separately. */
@Composable
fun DeckStudioBulkBar(count: Int, move: (String) -> Unit, setQuantity: () -> Unit, remove: () -> Unit, selectAll: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().testTag("deckStudio.bulkBar"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(DeckStudioPlayText.selected(count), Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            StudioPlainButton(DeckStudioPlayText.selectAll, selectAll, style = StudioText.subheadline)
        }
        Row(Modifier.fillMaxWidth().alpha(if (count == 0) 0.45f else 1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StudioMenu({ bulkDestinations.map { (section, title) -> MenuEntry.Item(title) { move(section) } } }, Modifier.weight(1f), enabled = count > 0) {
                BulkAction(DeckStudioPlayText.moveTo, "arrow.forward", DeckStudioPalette.ink)
            }
            BulkAction(DeckStudioPlayText.setQuantity, "number", DeckStudioPalette.ink, Modifier.weight(1f).clickable(enabled = count > 0, role = Role.Button) { setQuantity() })
            BulkAction(DeckStudioPlayText.remove, "trash", DeckStudioPalette.danger, Modifier.weight(1f).clickable(enabled = count > 0, role = Role.Button) { remove() })
        }
    }
}

val bulkDestinations = DeckStudioPlayText.destinations

@Composable
private fun BulkAction(title: String, icon: String, tint: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(DeckStudioMetrics.controlRadius)
    Column(modifier.fillMaxWidth().defaultMinSize(minHeight = DeckStudioMetrics.controlHeight).background(DeckStudioPalette.surfaceElevated, shape)
        .border(1.dp, DeckStudioPalette.separator, shape).padding(vertical = 6.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
        SfImage(icon, tint, 16.dp)
        Text(title, color = tint, style = StudioText.caption.weight(SfWeight.semibold), maxLines = 1)
    }
}

/** Bulk Set quantity: every selected card gets this quantity, from 1 to 2,000. */
@Composable
fun DeckStudioQuantityDialog(apply: (String) -> Unit, dismiss: () -> Unit) {
    var value by remember { mutableStateOf("") }
    Dialog(dismiss) {
        Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(14.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(DeckStudioPlayText.setQuantity, color = DeckStudioPalette.ink, style = StudioText.headline)
            Text(DeckStudioPlayText.quantityMessage, color = DeckStudioPalette.secondaryInk, style = StudioText.footnote)
            StudioRoundedField(value, { value = it.filter(Char::isDigit).take(4) }, "Quantity", Modifier.fillMaxWidth(), keyboardType = KeyboardType.Number)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.End)) {
                StudioPlainButton("Cancel", dismiss)
                StudioPlainButton("Apply", { apply(value); dismiss() }, style = StudioText.body.weight(SfWeight.semibold))
            }
        }
    }
}

/**
 * Edit as text: the deck in the plain-text export format, reviewed as added and removed cards before
 * it is applied as one undo step.
 */
@Composable
fun DeckStudioTextEditorSheet(draft: NativeDeckDraft, apply: (NativeDeckDraft, NativeDeckDraft) -> Boolean, dismiss: () -> Unit) {
    val original = remember { draft }
    val initial = remember {
        if (original.rows.isEmpty()) "" else runCatching {
            DeckStudioTextExport.text(original.copy(name = original.name.ifBlank { "Draft" }).deck())
        }.getOrNull()
    }
    var text by rememberSaveable { mutableStateOf(initial ?: "") }
    var review by remember { mutableStateOf<Triple<NativeDeckDraft, DeckStudioTextDiff, List<String>>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding()) {
        val current = review
        when {
            initial == null -> {
                StudioSheetBar(DeckStudioPlayText.editAsText, cancel = dismiss)
                DeckStudioNotice("Plain text can't hold this draft", "It has custom sections or card names the text format can't keep. Edit it card by card, or export native JSON.",
                    "exclamationmark.triangle", Modifier.padding(20.dp))
            }
            current != null -> {
                StudioSheetBar(DeckStudioPlayText.editAsText, done = {
                    if (apply(original, current.first)) dismiss()
                    else error = "The deck changed while you were editing, or this list exceeds its limits. Nothing was applied."
                }, doneTitle = DeckStudioPlayText.applyChanges, doneEnabled = !current.second.isEmpty, cancel = { review = null; error = null }, cancelTitle = DeckStudioPlayText.keepEditing)
                Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    if (current.second.isEmpty) Text(DeckStudioPlayText.noChanges, color = DeckStudioPalette.ink, style = StudioText.subheadline)
                    if (current.second.added.isNotEmpty()) FormSection(DeckStudioPlayText.diffAdded) {
                        current.second.added.forEach { Text(it.label, color = DeckStudioPalette.success, style = StudioText.subheadline) }
                    }
                    if (current.second.removed.isNotEmpty()) FormSection(DeckStudioPlayText.diffRemoved) {
                        current.second.removed.forEach { Text(it.label, color = DeckStudioPalette.danger, style = StudioText.subheadline) }
                    }
                    if (current.third.isNotEmpty()) FormSection("Notes") { current.third.forEach { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption) } }
                    error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                }
            }
            else -> {
                StudioSheetBar(DeckStudioPlayText.editAsText, done = {
                    try {
                        val (parsed, notes) = DeckStudioTextDiff.draft(text, original)
                        review = Triple(parsed, DeckStudioTextDiff.between(original, parsed), notes); error = null
                    } catch (failure: Exception) { error = failure.message }
                }, doneTitle = DeckStudioPlayText.reviewChanges, cancel = dismiss)
                Column(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(DeckStudioPlayText.textEditorHint,
                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    BasicTextField(text, { text = it }, Modifier.fillMaxWidth().weight(1f).background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(12.dp))
                        .padding(8.dp).testTag("deckStudio.textEditor").semantics { contentDescription = "Deck list text" },
                        textStyle = StudioText.callout.copy(color = DeckStudioPalette.ink, fontFamily = FontFamily.Monospace), cursorBrush = SolidColor(DeckStudioPalette.ink),
                        // Exact card names are case-sensitive, so the keyboard must not recapitalize them.
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
                    error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                }
            }
        }
    }
}

/** Commander-first new decks: a new draft opens on this picker. Skip keeps an empty draft. */
@Composable
fun DeckStudioCommanderFirstPicker(metadata: NativeDeckMetadataCatalogue?, choose: (String) -> Boolean, skip: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(query, metadata) {
        val catalogue = metadata ?: return@LaunchedEffect
        delay(120)
        results = withContext(Dispatchers.Default) { DeckStudioBuilderSearch.commanders(catalogue, query, 60) }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).imePadding()) {
        StudioSheetBar(DeckStudioPlayText.chooseCommander, cancel = skip, cancelTitle = DeckStudioPlayText.skip)
        LazyColumn(Modifier.fillMaxWidth().testTag("deckStudio.commanderFirst"), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 32.dp)) {
            item {
                Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(DeckStudioPlayText.commanderFirstTitle, color = DeckStudioPalette.ink, style = StudioText.headline)
                    Text(DeckStudioPlayText.commanderFirstCaption,
                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    StudioRoundedField(query, { query = it; error = null }, DeckStudioPlayText.searchCommanders, Modifier.fillMaxWidth().testTag("deckStudio.commanderFirst.search"))
                    error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
                }
            }
            if (metadata == null) item {
                DeckStudioNotice("Local catalogue unavailable", "Skip for now and add a commander from Add cards once the catalogue loads.", modifier = Modifier.padding(20.dp))
            } else if (results.isEmpty() && query.isNotEmpty()) item {
                StudioContentUnavailable("No matching commanders", "crown", "Try another name.")
            }
            items(results, key = { it.name }) { card ->
                Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface).clickable {
                    if (!choose(card.name)) error = "This commander could not be added. The draft is unchanged."
                }.defaultMinSize(minHeight = 44.dp).padding(horizontal = 20.dp, vertical = 6.dp).clearAndSetSemantics { contentDescription = "Choose ${card.name} as commander" },
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp, 56.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxSize()) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                        Text(card.typeLine ?: "Type unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                    DeckStudioColorIdentity(card.colorIdentity)
                }
                HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
            }
        }
    }
}

/** "List copied": a brief capsule at the top of the workspace. */
@Composable
fun DeckStudioListCopiedBadge(modifier: Modifier = Modifier) {
    Row(modifier.defaultMinSize(minHeight = 40.dp).background(DeckStudioPalette.ink, CircleShape).padding(horizontal = 14.dp)
        .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }, horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        SfImage("checkmark", DeckStudioPalette.surfaceElevated, 14.dp)
        Text(DeckStudioPlayText.listCopied, color = DeckStudioPalette.surfaceElevated, style = StudioText.subheadline.weight(SfWeight.semibold))
    }
}

/** Copy list: the plain-text export (Commander / Deck / Sideboard / Maybeboard headings) that Archidekt and Moxfield import. */
fun copyDeckList(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("Deck list", text))
}
