package io.magicmobile.android.studio

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import java.util.UUID

private val workspaceTabs = listOf("Cards", "Ideas", "Analysis", "Playtest")

/** DeckStudioWorkspaceScreen.swift: one deck's cards, ideas, analysis and playtest. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioWorkspaceScreen(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Boolean, metadata: NativeDeckMetadataCatalogue?,
                              resolver: OnDeviceDeckResolver?, selectForPlay: (String) -> Unit, close: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val model = remember(record?.id, included) { DeckStudioEditorModel(library, record, included) }
    val combos = remember(record?.id) { DeckStudioComboModel(scope) }
    val browser = remember(record?.id) { DeckStudioEDHRECModel(scope) }
    val validation = remember(record?.id) { DeckStudioValidationState(scope) }
    var tab by rememberSaveable { mutableStateOf("Cards") }
    var headerExpanded by rememberSaveable { mutableStateOf(true) }
    var ideas by rememberSaveable { mutableStateOf("Combos") }
    var query by rememberSaveable { mutableStateOf("") }
    var grouping by rememberSaveable { mutableStateOf("Type") }
    var sorting by rememberSaveable { mutableStateOf("Name") }
    var sectionFilter by rememberSaveable { mutableStateOf("") }
    var colorFilter by rememberSaveable { mutableStateOf("") }
    var showSearch by remember { mutableStateOf(false) }
    var showValidation by remember { mutableStateOf(false) }
    var showCommander by remember { mutableStateOf(false) }
    var showBasics by remember { mutableStateOf(false) }
    var replacement by remember { mutableStateOf<NativeDeckRow?>(null) }
    var inspection by remember { mutableStateOf<String?>(null) }
    var historyReview by remember { mutableStateOf<Pair<DeckStudioRecordedGame, Boolean>?>(null) }
    var confirmClose by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var showArtworkPreferences by remember { mutableStateOf(false) }
    var showOrganization by remember { mutableStateOf(false) }

    val draft = model.draft
    val deck = runCatching { draft.deck() }.getOrNull()
    val signature = if (deck != null && resolver != null) runCatching { DeckStudioDeckSignature.native(DeckStudioPlayProjection(deck).resolve(resolver)) }.getOrNull() else null
    val currentValidationPassed = run {
        val receipt = validation.receipt ?: return@run false
        if (deck == null || resolver == null) return@run false
        val request = runCatching { DeckStudioPlayProjection(deck).request(resolver) }.getOrNull() ?: return@run false
        receipt.valid && receipt.matches(request, resolver.upstreamCommit, resolver.catalogueHash, DeckStudioServices.appBuild)
    }
    fun inspect(name: String) { inspection = name }
    fun preparePlay(playing: DeckList) {
        if (resolver == null || !currentValidationPassed) return
        val selection = model.preparePlayable(playing, resolver) ?: return
        showValidation = false; selectForPlay(selection)
    }
    fun pauseServices() { model.persistRecovery(); browser.pause(); combos.cancel(); validation.cancelPending() }
    fun requestClose() { if (model.isDirty) confirmClose = true else { pauseServices(); close() } }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, model) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) pauseServices() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); pauseServices() }
    }
    LaunchedEffect(tab, ideas) { if (tab != "Ideas" || ideas != "EDHREC") browser.pause() }
    BackHandler { requestClose() }

    // Group, filter and sort exactly as the iOS workspace does.
    val filteredRows = draft.rows.filter { row ->
        val card = metadata?.card(row.cardName)
        (query.isEmpty() || row.cardName.contains(query, true) || card?.oracleText?.contains(query, true) == true) &&
            (sectionFilter.isEmpty() || DeckStudioDraftPresentation.section(row) == sectionFilter) &&
            (colorFilter.isEmpty() || if (colorFilter == "C") card?.colors?.isEmpty() == true else card?.colors?.contains(colorFilter) == true)
    }.sortedWith { a, b ->
        if (sorting == "Quantity" && a.quantity != b.quantity) return@sortedWith b.quantity.compareTo(a.quantity)
        if (sorting == "Mana value") {
            val left = metadata?.card(a.cardName)?.manaValue ?: Double.POSITIVE_INFINITY
            val right = metadata?.card(b.cardName)?.manaValue ?: Double.POSITIVE_INFINITY
            if (left != right) return@sortedWith left.compareTo(right)
        }
        if (a.cardName == b.cardName) a.id.toString().uppercase().compareTo(b.id.toString().uppercase()) else a.cardName.compareTo(b.cardName)
    }
    fun groupName(row: NativeDeckRow): String {
        val section = DeckStudioDraftPresentation.section(row)
        if (section != "deck") return section.replaceFirstChar { it.uppercase() }
        val card = metadata?.card(row.cardName)
        return when (grouping) {
            "Name", "Section" -> "Main deck"
            "Mana value" -> card?.manaValue?.let { "Mana value ${if (it % 1.0 == 0.0) it.toLong().toString() else it.toString()}" } ?: "Unknown mana value"
            "Color" -> card?.colors?.let { colors -> if (colors.isEmpty()) "Colorless" else listOf("W", "U", "B", "R", "G").filter { it in colors }.joinToString(" / ") } ?: "Unknown color"
            else -> {
                val types = card?.types ?: return "Unclassified"
                listOf("LAND", "CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "BATTLE").firstOrNull { it in types }
                    ?.lowercase()?.replaceFirstChar { it.uppercase() } ?: "Other types"
            }
        }
    }
    fun groupOrder(name: String): Double {
        if (name == "Commanders") return -1.0
        if (name.startsWith("Mana value ")) name.removePrefix("Mana value ").toDoubleOrNull()?.let { return minOf(it, 1_000_000.0) }
        return 1_000_001.0
    }
    val groups = filteredRows.map(::groupName).toSet().sortedWith { a, b ->
        val left = groupOrder(a); val right = groupOrder(b); if (left == right) a.compareTo(b) else left.compareTo(right)
    }

    val header: @Composable () -> Unit = {
        WorkspaceHeader(model, metadata, headerExpanded, { headerExpanded = !headerExpanded }, currentValidationPassed) { showValidation = true }
    }
    val tabs: @Composable () -> Unit = {
        Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(14.dp)).padding(4.dp)
            .semantics { contentDescription = "Deck workspace" }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (destination in workspaceTabs) {
                val selected = tab == destination
                Box(Modifier.weight(1f).defaultMinSize(minHeight = 44.dp).background(if (selected) DeckStudioPalette.ink else Color.Transparent, RoundedCornerShape(10.dp))
                    .clip(RoundedCornerShape(10.dp)).clickable { tab = destination }, contentAlignment = Alignment.Center) {
                    Text(destination, color = if (selected) DeckStudioPalette.surface else DeckStudioPalette.secondaryInk, style = StudioText.subheadline.weight(SfWeight.semibold),
                        maxLines = 1)
                }
            }
        }
    }
    val cardFilters: @Composable () -> Unit = {
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioSearchField(query, { query = it }, "Search this deck", radius = 12.dp, padding = 12.dp, clearLabel = "Clear deck search")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                StudioMenu({ deckFilterOptions(draft, sectionFilter, colorFilter, { sectionFilter = it }, { colorFilter = it }) }) {
                    WorkspaceMenuLabel("Filter", if (sectionFilter.isEmpty() && colorFilter.isEmpty()) "line.3.horizontal.decrease" else "line.3.horizontal.decrease.circle.fill")
                }
                StudioMenu({ listOf("Type", "Section", "Mana value", "Color", "Name").map { MenuEntry.Item(it, checked = it == grouping) { grouping = it } } }) {
                    WorkspaceMenuLabel("Group", "square.grid.2x2")
                }
                StudioMenu({ listOf("Name", "Quantity", "Mana value").map { MenuEntry.Item(it, checked = it == sorting) { sorting = it } } }) {
                    WorkspaceMenuLabel("Sort", "arrow.up.arrow.down")
                }
                StudioIconButton("arrow.uturn.backward", "Undo deck edit", { model.undo() }, enabled = model.history.canUndo && !model.readOnly, size = 16.dp)
                StudioIconButton("arrow.uturn.forward", "Redo deck edit", { model.redo() }, enabled = model.history.canRedo && !model.readOnly, size = 16.dp)
            }
        }
    }

    StudioScreen {
        Column(Modifier.fillMaxSize()) {
            StudioNavBar("Deck Studio", leading = {
                StudioGlassGroup { StudioGlassText("Done", { requestClose() }, label = "deckStudio.close") }
            }, trailing = {
                StudioGlassGroup {
                    if (model.readOnly) StudioGlassText("Edit a copy", { model.makeEditableCopy() })
                    else StudioGlassText("Save", { model.save() }, enabled = model.canSave, bold = true, label = "deckStudio.save")
                    StudioGlassIcon("tag", "Deck tags, notes and import receipt", { showOrganization = true }, enabled = model.record != null)
                    StudioMenu({
                        buildList {
                            add(MenuEntry.Item("Validate & playtest", "checkmark.shield") { showValidation = true })
                            add(MenuEntry.Item("Change primary commander", "crown", enabled = !model.readOnly && metadata != null) { showCommander = true })
                            add(MenuEntry.Item("Basic lands", "leaf", enabled = !model.readOnly) { showBasics = true })
                            add(MenuEntry.Item("Rename deck", "pencil", enabled = !model.readOnly) { showRename = true })
                            add(MenuEntry.Item("Artwork & privacy", "photo") { showArtworkPreferences = true })
                            val text = deck?.let { runCatching { DeckStudioTextExport.text(it) }.getOrNull() }
                            if (text != null) add(MenuEntry.Item("Export plain text", "doc.plaintext") { shareText(context, text) })
                            else add(MenuEntry.Label("Plain text unavailable · use JSON to preserve this draft"))
                            runCatching { draft.exportJSON() }.getOrNull()?.let { json -> add(MenuEntry.Item("Export native JSON", "square.and.arrow.up") { shareText(context, json) }) }
                        }
                    }) { Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis.circle", DeckStudioPalette.ink, 20.dp) } }
                }
            })
            if (tab == "Cards" || tab == "Playtest") {
                // Cards and Playtest share one scroll: the header leaves the screen while the tabs stay pinned.
                Box(Modifier.weight(1f)) {
                    LazyColumn(Modifier.fillMaxSize().semantics { contentDescription = if (tab == "Cards") "deckStudio.cards.list" else "deckStudio.playtest.list" },
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = if (tab == "Cards" && !model.readOnly) 88.dp else 24.dp)) {
                        item(key = "header") { Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) { header() } }
                        model.error?.let { message -> item(key = "error") {
                            DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp))
                        } }
                        stickyHeader(key = "tabs") { Box(Modifier.fillMaxWidth().background(DeckStudioPalette.background).padding(horizontal = 20.dp, vertical = 8.dp)) { tabs() } }
                        if (tab == "Cards") {
                            item(key = "filters") { cardFilters() }
                            if (draft.rows.isEmpty()) item(key = "empty") {
                                StudioContentUnavailable("A deck of possibilities", "plus.rectangle.on.rectangle", "Add your commander and cards. Incomplete drafts are welcome.")
                            } else if (filteredRows.isEmpty()) item(key = "nomatch") {
                                Column(Modifier.padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                    StudioContentUnavailable("No matching cards", "line.3.horizontal.decrease", "Clear the search or filters to see the full draft.")
                                    StudioButton("Clear search and filters", { query = ""; sectionFilter = ""; colorFilter = "" }, primary = false)
                                }
                            }
                            for (group in groups) {
                                val rows = filteredRows.filter { groupName(it) == group }
                                item(key = "group-$group") {
                                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(group, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
                                        Text("${rows.sumOf { it.quantity }}", color = DeckStudioPalette.ink, style = StudioText.caption)
                                    }
                                }
                                items(rows, key = { it.id.toString() }) { row ->
                                    Box(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                                        CardRow(row, model, metadata, inspect = ::inspect, replace = { replacement = it })
                                    }
                                }
                            }
                        } else {
                            item(key = "validation") {
                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp)) { DeckStudioValidationPanel(validation, deck, resolver, play = ::preparePlay) }
                            }
                            item(key = "history") {
                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
                                    DeckStudioPlaytestInsightsView(signature, metadata) { game, _ -> historyReview = game to (signature == game.deck) }
                                }
                            }
                        }
                    }
                    if (tab == "Cards" && !model.readOnly) {
                        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(DeckStudioPalette.background).navigationBarsPadding()
                            .padding(top = 8.dp, start = 20.dp, end = 20.dp, bottom = 12.dp)) {
                            StudioButton("Add cards", { showSearch = true }, Modifier.fillMaxWidth().semantics { contentDescription = "deckStudio.addCards" }, icon = "plus")
                        }
                    }
                }
            } else {
                Column(Modifier.weight(1f)) {
                    Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) { header() }
                    model.error?.let { DeckStudioNotice("Check this draft", it, "exclamationmark.triangle", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp)) }
                    Box(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 12.dp)) { tabs() }
                    if (tab == "Ideas") {
                        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            StudioSegmented(listOf("Combos", "EDHREC"), ideas, { ideas = it }, { it }, Modifier.padding(horizontal = 20.dp))
                            if (ideas == "EDHREC") DeckStudioEDHRECPanel(browser, DeckStudioDraftPresentation.commanders(draft))
                            else DeckStudioComboPanel(combos, draft, metadata, resolver, model.readOnly, add = { name, section, approved ->
                                approved == DeckStudioSpellbookInput.make(model.draft, resolver) && resolver?.canonicalCardName(name) == name && model.add(name, section)
                            }, inspect = ::inspect)
                        }
                    } else {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(),
                            verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            DeckStudioAnalysisContent(draft, metadata, curveOnly = false, inspect = ::inspect)
                            DeckStudioRoleInsightsView(draft, metadata, model.record?.id, inspect = ::inspect)
                        }
                    }
                }
            }
        }
        StudioCover(historyReview != null) {
            historyReview?.let { (game, exact) -> MatchHistoryDashboard(game, exact, metadata) { historyReview = null } }
        }
    }

    if (showSearch) BoardSheet({ showSearch = false }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
        DeckStudioCardSearch(metadata, DeckStudioDraftPresentation.colors(draft, metadata), { name, section -> model.add(name, section) }, resolver, model) { showSearch = false }
    }
    inspection?.let { name ->
        BoardSheet({ inspection = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            DeckStudioCardInspector(name, metadata?.card(name)) { inspection = null }
        }
    }
    if (showCommander) BoardSheet({ showCommander = false }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
        DeckStudioReplacementPicker(metadata, commander = true, replace = { name, keepOld -> model.commander(name, keepOld) }) { showCommander = false }
    }
    replacement?.let { row ->
        BoardSheet({ replacement = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            DeckStudioReplacementPicker(metadata, commander = false, replace = { name, _ -> model.replace(row.id, name) }) { replacement = null }
        }
    }
    if (showBasics) BoardSheet({ showBasics = false }, background = rgbLight, skipPartiallyExpanded = true, sound = false) {
        DeckStudioBasicLandsSheet(draft, apply = { values, expected -> model.basics(values, expected) }) { showBasics = false }
    }
    if (showValidation) BoardSheet({ showValidation = false }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
        Column(Modifier.fillMaxWidth()) {
            StudioSheetBar("Validate & playtest", done = { showValidation = false })
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) { DeckStudioValidationPanel(validation, deck, resolver, play = ::preparePlay) }
        }
    }
    if (showRename) BoardSheet({ showRename = false }, background = rgbLight, sound = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Rename deck", done = { showRename = false })
            Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 12.dp)) {
                StudioTextInput(draft.name, { model.rename(it) }, "Deck name", Modifier.fillMaxWidth())
            }
        }
    }
    if (showArtworkPreferences) BoardSheet({ showArtworkPreferences = false }, background = rgbLight, sound = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Artwork & privacy", done = { showArtworkPreferences = false })
            Column(Modifier.padding(horizontal = 16.dp)) { NativeArtworkPreferenceRows() }
        }
    }
    if (showOrganization) model.record?.let { current ->
        BoardSheet({ showOrganization = false }, background = rgbLight, skipPartiallyExpanded = true, sound = false) {
            DeckStudioOrganizationSheet(current.id, draft.name) { showOrganization = false }
        }
    }
    if (confirmClose) ConfirmationDialog("Save your changes?",
        if (model.recoveryBlocked) "Recovery is paused to preserve unreadable data. Save this deck before closing to keep your edits, or cancel to continue editing."
        else "Your existing saved deck is unchanged until you save. An incomplete deck can remain a local draft.",
        buildList {
            if (model.canSave) add(ConfirmationAction("Save and close") { if (model.save() != null) { pauseServices(); close() } })
            if (!model.recoveryBlocked) add(ConfirmationAction("Keep recovery draft and close") { if (model.persistRecovery()) { pauseServices(); close() } })
            add(ConfirmationAction("Discard unsaved changes and close", destructive = true) { model.discardUnsavedChanges(); pauseServices(); close() })
        }, light = true) { confirmClose = false }
}

@Composable
private fun WorkspaceMenuLabel(title: String, icon: String) {
    Row(Modifier.defaultMinSize(minHeight = 44.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(icon, DeckStudioPalette.ink, 14.dp)
        Text(title, color = DeckStudioPalette.ink, style = StudioText.caption)
    }
}

private fun deckFilterOptions(draft: NativeDeckDraft, section: String, color: String, setSection: (String) -> Unit, setColor: (String) -> Unit): List<MenuEntry> = buildList {
    add(MenuEntry.Section("Section"))
    add(MenuEntry.Item("All sections", checked = section.isEmpty()) { setSection("") })
    draft.rows.map(DeckStudioDraftPresentation::section).toSortedSet().forEach { value ->
        add(MenuEntry.Item(value.replaceFirstChar { it.uppercase() }, checked = section == value) { setSection(value) })
    }
    add(MenuEntry.Section("Card color"))
    add(MenuEntry.Item("Any color", checked = color.isEmpty()) { setColor("") })
    listOf("W", "U", "B", "R", "G", "C").forEach { value -> add(MenuEntry.Item(if (value == "C") "Colorless" else value, checked = color == value) { setColor(value) }) }
    add(MenuEntry.Divider)
    add(MenuEntry.Item("Clear filters") { setSection(""); setColor("") })
}

@Composable
private fun WorkspaceHeader(model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, expanded: Boolean, toggle: () -> Unit,
                            validated: Boolean, validate: () -> Unit) {
    val draft = model.draft
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, tween(220), label = "headerChevron")
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { toggle() }.semantics { contentDescription = "Deck details" },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(draft.name.ifEmpty { "Untitled draft" }, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.headline, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            Text("${DeckStudioDraftPresentation.gameCount(draft)} cards", color = DeckStudioPalette.ink, style = StudioText.caption)
            SfImage("chevron.down", DeckStudioPalette.ink, 15.dp, Modifier.rotate(rotation))
        }
        AnimatedVisibility(expanded, enter = expandVertically(tween(220)) + fadeIn(tween(220)), exit = shrinkVertically(tween(220)) + fadeOut(tween(160))) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(68.dp, 96.dp).shadow(8.dp, RoundedCornerShape(6.dp), ambientColor = DeckStudioPalette.ink.copy(alpha = 0.12f),
                    spotColor = DeckStudioPalette.ink.copy(alpha = 0.12f)).clip(RoundedCornerShape(6.dp))) {
                    DeckStudioArtwork(DeckStudioDraftPresentation.commanders(draft).firstOrNull() ?: "", Modifier.fillMaxSize())
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(draft.name.ifEmpty { "Untitled draft" }, color = DeckStudioPalette.ink, style = sf(22f, SfWeight.bold, tracking = -0.5f), maxLines = 2,
                        overflow = TextOverflow.Ellipsis)
                    Text(DeckStudioDraftPresentation.commanders(draft).joinToString(" • "), color = DeckStudioPalette.secondaryInk, style = StudioText.caption, maxLines = 2)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        DeckStudioColorIdentity(DeckStudioDraftPresentation.colors(draft, metadata))
                        Text("${DeckStudioDraftPresentation.gameCount(draft)} cards · Commander", color = DeckStudioPalette.ink, style = StudioText.caption)
                    }
                    Text(model.saveLabel, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                    Row(Modifier.defaultMinSize(minHeight = 44.dp).clickable { validate() }, horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        SfImage(if (validated) "checkmark.shield.fill" else "checkmark.shield", DeckStudioPalette.ink, 13.dp)
                        Text(if (validated) "Validated · playtest" else "Validate & playtest", color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
                    }
                }
            }
        }
    }
}

@Composable
private fun CardRow(row: NativeDeckRow, model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, inspect: (String) -> Unit, replace: (NativeDeckRow) -> Unit) {
    Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).defaultMinSize(minHeight = 52.dp).clickable { inspect(row.cardName) }
            .semantics { contentDescription = "Inspect ${row.cardName}, quantity ${row.quantity}" },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(38.dp, 52.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(row.cardName, Modifier.fillMaxSize()) }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(row.cardName, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                val card = metadata?.card(row.cardName)
                when {
                    card == null -> Text("Unknown card · tap to review", color = DeckStudioPalette.warning, style = StudioText.caption2)
                    !card.manaCost.isNullOrEmpty() -> NativeDeckManaCost(card.manaCost)
                    else -> Text(card.typeLine ?: "Card", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!model.readOnly) StudioIconButton("minus", "Remove one ${row.cardName}", { model.quantity(row.id, -1) }, size = 16.dp)
            Text("${row.quantity}", Modifier.widthIn(min = 20.dp), color = DeckStudioPalette.ink, style = StudioText.subheadline,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            if (!model.readOnly) {
                StudioIconButton("plus", "Add one ${row.cardName}", { model.quantity(row.id, 1) }, size = 16.dp)
                StudioMenu({
                    buildList {
                        add(MenuEntry.Item("Replace card", "arrow.triangle.2.circlepath") { replace(row) })
                        add(MenuEntry.Section("Move to…"))
                        listOf("deck", "commanders", "companions", "sideboard", "maybeboard").forEach { destination ->
                            add(MenuEntry.Item(destination.replaceFirstChar { it.uppercase() }) { model.move(row.id, destination) })
                        }
                        add(MenuEntry.Divider)
                        add(MenuEntry.Item("Remove row", "trash", destructive = true) { model.remove(row.id) })
                    }
                }) {
                    Box(Modifier.size(44.dp).semantics { contentDescription = "More options for ${row.cardName}" }, contentAlignment = Alignment.Center) {
                        SfImage("ellipsis", DeckStudioPalette.ink, 16.dp)
                    }
                }
            }
        }
    }
}
