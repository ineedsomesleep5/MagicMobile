package io.magicmobile.android.studio

import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ondevice.OnDeviceSetupModel
import io.magicmobile.android.ondevice.OnDeviceSetupPreferences
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.statusBarsPadding
import io.magicmobile.android.ui.tavernFill

/** Shares text through the system share sheet (SwiftUI ShareLink). */
fun shareText(context: Context, text: String) {
    val intent = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
    context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** The studio's metadata and resolver, loaded once off the main thread. */
class StudioCatalogue(val metadata: NativeDeckMetadataCatalogue?, val resolver: OnDeviceDeckResolver?, val error: String?)

private sealed class StudioRoute {
    data class Deck(val record: DeckLibraryRecord?, val included: Boolean) : StudioRoute()
    object Importer : StudioRoute()
}

/**
 * DeckStudioRootView.swift: the collection and editor share a quiet, artwork-led workshop. [open]
 * opens a deck straight away (the setup screen's "Fix in Deck Studio").
 */
@Composable
fun DeckStudioRootView(setup: OnDeviceSetupModel, selectedDeckID: String, select: (String) -> Unit, preparePlay: () -> Unit, dismiss: () -> Unit,
                       open: DeckStudioOpen? = null) {
    val context = LocalContext.current
    DeckStudioServices.install(context)
    val library = setup.library
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf(DeckStudioLibraryQuery()) }
    var grid by AppPreferences.boolean("deckStudio.library.grid.v1", true)
    var tags by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var favorites by remember { mutableStateOf<Set<String>>(emptySet()) }
    var favoritesReadable by remember { mutableStateOf(true) }
    var catalogue by remember { mutableStateOf<StudioCatalogue?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var route by remember { mutableStateOf<StudioRoute?>(null) }
    // Moving between the library and a deck or the importer turns the page of the book.
    val stage = rememberGrimoireStage()
    val spread = androidx.compose.ui.platform.LocalConfiguration.current.let { Grimoire.isSpread(it.screenWidthDp, it.screenHeightDp) }
    fun turn(next: StudioRoute?) = stage.turnPage(forward = next != null) { route = next }
    var pendingDelete by remember { mutableStateOf<DeckLibraryRecord?>(null) }
    var showPreferences by remember { mutableStateOf(false) }
    var pendingFix by remember { mutableStateOf<DeckStudioOpen?>(null) }
    var openedFromSetup by remember { mutableStateOf<DeckStudioOpen?>(null) }
    var statuses by remember { mutableStateOf<Map<String, DeckStudioPlayStatus>>(emptyMap()) }
    val currentSelection by rememberUpdatedState(selectedDeckID)
    val currentSelect by rememberUpdatedState(select)
    val play = remember {
        DeckStudioPlaySelection(scope, gameLive = { setup.needsLeave || setup.isBusy }, select = { currentSelect(it) }, selectedID = { currentSelection })
    }

    data class Entry(val record: DeckLibraryRecord, val included: Boolean) { val id get() = if (included) record.id else "local:${record.id}" }
    val records = library.decks.map { Entry(it, false) } + setup.precons.map { Entry(DeckLibraryRecord.included(it), true) }
    // A saved deck's bracket: the list check, raised by the player's own label (DeckBracketPreference).
    val bracketPrefs by io.magicmobile.android.ui.AppPreferences.string(io.magicmobile.android.game.DeckBracketPreference.KEY, "{}")
    fun deckBracket(id: String, record: DeckLibraryRecord): io.magicmobile.android.game.CommanderBracket {
        val played = record.entries.filter { it.section in setOf("deck", "main", "commander", "commanders") }.map { it.cardName }
        val minimum = setup.bracketRules.evaluate(listOfNotNull(record.commander?.cardName) + played).minimum
        val declared = runCatching {
            (kotlinx.serialization.json.Json.parseToJsonElement(bracketPrefs) as kotlinx.serialization.json.JsonObject)[id]
                ?.let { (it as kotlinx.serialization.json.JsonPrimitive).content.toIntOrNull() }?.let(io.magicmobile.android.game.CommanderBracket::of)
        }.getOrNull()
        return io.magicmobile.android.game.DeckBracketPreference.effective(minimum, declared)
    }
    fun reloadTags() { scope.launch { tags = withContext(Dispatchers.IO) { DeckStudioServices.organization.tagIndex(records.map { it.record.id }) } } }
    val visible = run {
        val items = records.map { value ->
            DeckStudioShelfItem(value.id, value.record.name, DeckStudioDraftPresentation.commanders(NativeDeckDraft.of(value.record.deckList)),
                tags[value.record.id] ?: emptyList(), if (value.included) DeckStudioShelfItem.Origin.INCLUDED else DeckStudioShelfItem.Origin.LOCAL,
                if (value.included) null else value.record.updatedAt)
        }
        val byID = records.associateBy { it.id }
        query.apply(items, favorites).mapNotNull { byID[it.id] }
    }

    fun saveFavorites() {
        if (!favoritesReadable) return
        runCatching { DeckLibraryStore.saveFavorites(favorites) }.onFailure { error = it.message }
    }
    fun toggleFavorite(id: String) {
        if (!favoritesReadable) { error = "Unreadable favorite preferences are preserved; no changes were written."; return }
        favorites = if (id in favorites) favorites - id else if (favorites.size < 4000) favorites + id else favorites
        saveFavorites()
    }
    fun delete(record: DeckLibraryRecord) {
        try {
            library.deleteLocalDurably(record.id, record.revision)
            NativeDeckDraftRecovery.clearRecord(record.id, DeckStudioServices.defaults)
            tags = tags - record.id
            scope.launch(Dispatchers.IO) {
                runCatching { DeckStudioServices.organization.delete(record.id) }
                    .onFailure { error = "Deck cards were deleted, but optional local details could not be removed: ${it.message}" }
            }
            favorites = favorites - "local:${record.id}"; saveFavorites()
            scope.launch(Dispatchers.IO) { runCatching { DeckStudioServices.checkResults.remove("local:${record.id}") } }
            if (selectedDeckID == "local:${record.id}") select(OnDeviceSetupPreferences.defaultDeckID)
        } catch (failure: Exception) { error = failure.message }
        pendingDelete = null
    }
    fun loadCatalogue() {
        scope.launch {
            catalogue = try {
                while (setup.printingIndex == null && setup.errorMessage == null) kotlinx.coroutines.delay(100)
                val index = setup.printingIndex ?: throw IllegalStateException(setup.errorMessage ?: "The local card catalogue could not load.")
                val loaded = setup.awaitCatalogue()
                val metadata = withContext(Dispatchers.Default) { NativeDeckMetadataCatalogue(loaded) }
                StudioCatalogue(metadata, setup.deckResolver ?: OnDeviceDeckResolver(index), null)
            } catch (failure: Exception) { StudioCatalogue(null, null, failure.message ?: "The local card catalogue could not load.") }
        }
    }

    LaunchedEffect(Unit) {
        DeckStudioValidationService.gameLive = { setup.needsLeave || setup.isBusy }
        withContext(Dispatchers.IO) { runCatching { DeckLibraryStore.migrateBuild7Details(setup.localDecks) } }
        DeckLibraryStore.loadFavorites().onSuccess { favorites = it }.onFailure {
            favoritesReadable = false; error = "Favorite preferences could not load. They have been preserved; your decks are unchanged."
        }
        loadCatalogue()
        reloadTags()
    }
    LaunchedEffect(library.decks.map { it.id }) { reloadTags() }
    BackHandler(route == null) { dismiss() }
    LightSystemBars()

    val metadata = catalogue?.metadata
    val resolver = catalogue?.resolver
    // Each tile's status comes only from a stored result whose key matches the deck as it is now.
    val checkRevision = DeckStudioServices.checkRevision
    LaunchedEffect(records.map { it.id to it.record.revision }, resolver, checkRevision) {
        val current = resolver ?: return@LaunchedEffect
        val decks = records.map { it.id to it.record.deckList }
        statuses = withContext(Dispatchers.Default) {
            decks.associate { (id, deck) ->
                id to runCatching { DeckStudioPlayRules.status(id, deck, current, DeckStudioServices.appBuild, DeckStudioServices.checkResults) }
                    .getOrDefault(DeckStudioPlayStatus.NOT_CHECKED)
            }
        }
    }
    fun openDeck(target: DeckStudioOpen) {
        val entry = records.firstOrNull { it.id == target.deckID } ?: return
        pendingFix = target.takeIf { it.cards.isNotEmpty() }
        turn(StudioRoute.Deck(entry.record, entry.included))
    }
    /** Fix deck: the open workspace filters its own cards; from the library it opens the deck first. */
    fun fix(target: DeckStudioOpen) { if (route is StudioRoute.Deck) pendingFix = target else openDeck(target) }
    LaunchedEffect(open, records.map { it.id }) {
        if (open == null || open == openedFromSetup || records.none { it.id == open.deckID }) return@LaunchedEffect
        openedFromSetup = open
        openDeck(open)
    }
    fun playRecord(entry: Entry) = play.play(DeckStudioPlaySelection.source(entry.id, entry.record.deckList), resolver, entry.record.name)
    GrimoirePages(stage) {
      // The library is the binder's first page (concept B, 2026-10-06): its head on the leather, the page below.
      // This screen's pages, for page turns that move only the paper (GrimoireStage).
      val binderScreen = remember { Any() }
      Box(Modifier.fillMaxSize().binderCover()) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(start = 4.dp, end = 4.dp, bottom = 2.dp)) {
            val head: @Composable () -> Unit = {
                BinderHead("Done", dismiss, title = "Deck Studio", strapTag = "deckStudio.library.close") {
                    BinderPlaque(icon = "slider.horizontal.3", square = true, label = "Deck artwork and privacy") { showPreferences = true }
                }
            }
            // The parts of the library, shared by the single page (upright) and the two pages of a spread.
            val nowPlaying: @Composable (Modifier) -> Unit = { modifier ->
                records.firstOrNull { it.id == selectedDeckID }?.let { playing ->
                    DeckStudioNowPlayingStrip(playing.record.name, statuses[playing.id], { turn(StudioRoute.Deck(playing.record, playing.included)) }, modifier)
                }
            }
            val intro: @Composable () -> Unit = {
                Column(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    LibraryHeader(onCreate = { turn(StudioRoute.Deck(null, false)) }, onImport = { turn(StudioRoute.Importer) },
                        importEnabled = catalogue?.resolver != null)
                    DeckStudioArtworkInvitation()
                    (error ?: library.notice)?.let { DeckStudioNotice("Your library is preserved", it, "exclamationmark.triangle") }
                    catalogue?.error?.let { message ->
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            DeckStudioNotice("Card catalogue unavailable", message)
                            StudioPlainButton("Retry local catalogue", { catalogue = null; loadCatalogue() })
                        }
                    }
                    LibraryFilters(query) { query = it }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${visible.size} decks", color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
                        Spacer(Modifier.weight(1f))
                        StudioMenu({
                            DeckStudioLibraryQuery.Sort.entries.map { sort ->
                                MenuEntry.Item(sort.title, checked = sort == query.sort) { query = query.copy(sort = sort) }
                            }
                        }) { BinderPlaque(title = query.sort.title, icon = "arrow.up.arrow.down") }
                        BinderPlaque(icon = if (grid) "list.bullet" else "square.grid.2x2", square = true, label = if (grid) "Show deck list" else "Show deck grid") { grid = !grid }
                    }
                    if (visible.isEmpty()) StudioContentUnavailable(if (query.text.isEmpty()) "Your next deck starts here" else "No matching decks",
                        "rectangle.stack", "Create a deck, import a list, or change your filters.")
                }
            }
            val shelf: androidx.compose.foundation.lazy.grid.LazyGridScope.() -> Unit = {
                items(visible, key = { it.id }) { value ->
                    DeckTile(value.record, value.included, value.id == selectedDeckID, statuses[value.id], grid, metadata, tags[value.record.id] ?: emptyList(),
                        bracket = if (value.included) io.magicmobile.android.game.CommanderBracket.CORE else deckBracket(value.id, value.record),
                        showTags = tags.values.any { it.isNotEmpty() }, favorite = value.id in favorites,
                        open = { turn(StudioRoute.Deck(value.record, value.included)) }, toggleFavorite = { toggleFavorite(value.id) },
                        actions = {
                            deckActions(context, value.record, value.included, playEnabled = resolver != null && !play.checking, play = { playRecord(value) },
                                open = { turn(StudioRoute.Deck(value.record, value.included)) },
                                duplicate = {
                                    try {
                                        val copy = library.duplicateLocalDurably(value.record, value.record.name + " — Copy")
                                        scope.launch(Dispatchers.IO) {
                                            runCatching { DeckStudioServices.organization.duplicate(value.record.id, copy.id) }
                                                .onFailure { error = "Cards were copied, but their optional details could not be copied: ${it.message}" }
                                        }
                                        reloadTags(); turn(StudioRoute.Deck(copy, false))
                                    } catch (failure: Exception) { error = failure.message }
                                }, delete = { pendingDelete = value.record })
                        })
                }
            }
            if (spread) {
                // Sideways the binder lies open as a spread: the library's heading and filters are the left page,
                // the decks the right, and each scrolls by itself. Nothing runs across the fold.
                // The head is written on the left page, so both pages are the same height (Caleb, 2026-10-06).
                Row(Modifier.fillMaxSize().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), gutterStart = false, screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            head()
                            nowPlaying(Modifier.padding(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 4.dp))
                            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 40.dp)) { intro() }
                        }
                    }
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), gutterStart = true, screen = binderScreen) {
                        LazyVerticalGrid(if (grid) GridCells.Adaptive(160.dp) else GridCells.Fixed(1), Modifier.fillMaxSize(),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 40.dp),
                            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = shelf)
                    }
                }
            } else {
                Spacer(Modifier.height(4.dp))
                BinderPage(Modifier.weight(1f).fillMaxWidth(), gutterStart = true, screen = binderScreen) {
                    Column(Modifier.fillMaxSize()) {
                        head()
                        nowPlaying(Modifier.padding(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 4.dp).widthIn(max = 960.dp))
                        LazyVerticalGrid(if (grid) GridCells.Adaptive(160.dp) else GridCells.Fixed(1), Modifier.fillMaxSize().widthIn(max = 1000.dp),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 40.dp),
                            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            item(span = { GridItemSpan(maxLineSpan) }) { intro() }
                            shelf()
                        }
                    }
                }
            }
        }
        // Each of these is the next page of the book: leaving turns back to this one.
        StudioCover(route != null, animated = false) {
            when (val current = route) {
                is StudioRoute.Deck -> DeckStudioWorkspaceScreen(library, current.record, current.included, metadata, catalogue?.resolver,
                    play = play, close = { turn(null); reloadTags() }, fix = pendingFix, consumeFix = { pendingFix = null })
                // A new import opens in its workspace, where Play is one tap away; the playing deck is unchanged.
                StudioRoute.Importer -> DeckStudioImportScreen(library, catalogue?.resolver, didImport = { saved -> reloadTags(); turn(StudioRoute.Deck(saved, false)) },
                    close = { turn(null); reloadTags() })
                null -> {}
            }
        }
        DeckStudioPlayBanner(play, setUpGame = { route = null; dismiss(); preparePlay() }, Modifier.align(Alignment.BottomCenter))
      }
    }
    DeckStudioPlaySheets(play, fix = ::fix)
    if (showPreferences) BoardSheet({ showPreferences = false }, background = rgbLight, paper = true, skipPartiallyExpanded = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Artwork & privacy", done = { showPreferences = false })
            Column(Modifier.padding(horizontal = 16.dp)) { NativeArtworkPreferenceRows() }
        }
    }
    pendingDelete?.let { record ->
        val replacement = setup.precons.firstOrNull { "precon:${it.id}" == OnDeviceSetupPreferences.defaultDeckID }?.name ?: "The default deck"
        val message = listOfNotNull(DeckStudioPlayText.deletePlaying(replacement).takeIf { selectedDeckID == "local:${record.id}" },
            "Included decks and source websites are never changed.").joinToString(" ")
        ConfirmationDialog("Delete this local deck?", message,
            listOf(ConfirmationAction("Delete ${record.name}", destructive = true) { delete(record) }), light = true) { pendingDelete = null }
    }
}

/** The grouped-form background of a light sheet (systemGroupedBackground). */
/** A sheet over the studio: a loose leaf of the book's paper (it was the system's grouped grey). */
val rgbLight: Color = DeckStudioPalette.surface

/** A light sheet's bar: centred title and a trailing Done (or custom) action. */
@Composable
fun StudioSheetBar(title: String, done: (() -> Unit)? = null, doneTitle: String = "Done", doneEnabled: Boolean = true,
                   cancel: (() -> Unit)? = null, cancelTitle: String = "Cancel") {
    // A loose leaf's head in the book's own hand (BinderLeafHead on iOS): the title on the parchment over an inked
    // rule, with brass plaques for its actions, never the system's bar (Caleb, 2026-10-06).
    Column(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.widthIn(min = 90.dp), contentAlignment = Alignment.CenterStart) { cancel?.let { BinderPlaque(title = cancelTitle, onClick = it) } }
            Text(title, Modifier.weight(1f).semantics { heading() }, color = DeckStudioPalette.ink, style = sf(19f, SfWeight.bold),
                maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Box(Modifier.widthIn(min = 90.dp), contentAlignment = Alignment.CenterEnd) { done?.let { BinderPlaque(title = doneTitle, enabled = doneEnabled, onClick = it) } }
        }
        GrimoireRule(Modifier.fillMaxWidth())
    }
}

/**
 * A full-screen cover over the studio (SwiftUI fullScreenCover). It slides up, unless it is a page of the
 * spell book: then it is simply there, and GrimoireStage turns a page over the change.
 */
@Composable
fun StudioCover(visible: Boolean, animated: Boolean = true, content: @Composable () -> Unit) {
    val page = Modifier.fillMaxSize().grimoirePaper().clickable(remember { MutableInteractionSource() }, null) {}
    if (!animated) { if (visible) Box(page) { content() }; return }
    AnimatedVisibility(visible, enter = slideInVertically(androidx.compose.animation.core.tween(320)) { it } + fadeIn(),
        exit = slideOutVertically(androidx.compose.animation.core.tween(260)) { it } + fadeOut()) {
        Box(page) { content() }
    }
}

@Composable
private fun LibraryHeader(onCreate: () -> Unit, onImport: () -> Unit, importEnabled: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GrimoireHeading("Your collection", "My Decks", "Find your next move.")
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DeckStudioEmberButton("Create deck", onCreate, Modifier.weight(1f).testTag("deckStudio.create"), icon = "plus")
            BinderPlaque(Modifier.weight(1f).testTag("deckStudio.import"), title = "Import", icon = "square.and.arrow.down", enabled = importEnabled) { onImport() }
        }
    }
}

@Composable
private fun LibraryFilters(query: DeckStudioLibraryQuery, change: (DeckStudioLibraryQuery) -> Unit) {
    // The binder's brass rail, as on a deck's Cards page: the search, and the shelves as chips.
    BinderRail {
        BinderSearchField(query.text, { change(query.copy(text = it)) }, "Search decks, commanders or tags", tag = "deckStudio.library.search")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (filter in DeckStudioLibraryQuery.Filter.entries) {
                val selected = query.filter == filter
                Box(Modifier.defaultMinSize(minHeight = 44.dp).clickable(role = Role.Tab) { change(query.copy(filter = filter)) }
                    .semantics { this.selected = selected }, contentAlignment = Alignment.Center) {
                    Box(Modifier.height(36.dp)
                        .then(if (selected) Modifier.tavernFill(io.magicmobile.android.ui.TavernMaterial.EMBER, CircleShape) else Modifier.background(Color.Black.copy(alpha = 0.4f), CircleShape))
                        .border(1.dp, if (selected) Binder.brassLight.copy(alpha = 0.7f) else io.magicmobile.android.ui.TavernPalette.brass.copy(alpha = 0.5f), CircleShape)
                        .padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                        Text(filter.title, color = if (selected) Binder.emberText else io.magicmobile.android.ui.TavernPalette.parchment.copy(alpha = 0.75f),
                            style = sf(14f, SfWeight.bold))
                    }
                }
            }
        }
    }
}

private fun deckActions(context: Context, record: DeckLibraryRecord, included: Boolean, playEnabled: Boolean, play: () -> Unit, open: () -> Unit,
                        duplicate: () -> Unit, delete: () -> Unit): List<MenuEntry> {
    val json = runCatching { OnDeviceDeckEditing.exportJSON(record.deckList) }.getOrNull()
    val text = runCatching { DeckStudioTextExport.text(record.deckList) }.getOrNull()
    return buildList {
        add(MenuEntry.Item(DeckStudioPlayText.play, "play.fill", enabled = playEnabled) { play() })
        add(MenuEntry.Item("Open deck", "pencil") { open() })
        add(MenuEntry.Item("Duplicate locally", "doc.on.doc") { duplicate() })
        json?.let { add(MenuEntry.Item("Export native JSON", "square.and.arrow.up") { shareText(context, it) }) }
        if (text != null) add(MenuEntry.Item("Export plain text", "doc.plaintext") { shareText(context, text) })
        else add(MenuEntry.Label("Plain text unavailable · use JSON to preserve this draft"))
        if (!included && !record.isCloudBacked) add(MenuEntry.Item("Delete local deck", "trash", destructive = true) { delete() })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DeckTile(record: DeckLibraryRecord, included: Boolean, selected: Boolean, status: DeckStudioPlayStatus?, grid: Boolean, metadata: NativeDeckMetadataCatalogue?,
                     tags: List<String>, bracket: io.magicmobile.android.game.CommanderBracket?, showTags: Boolean, favorite: Boolean, open: () -> Unit, toggleFavorite: () -> Unit, actions: () -> List<MenuEntry>) {
    val draft = remember(record) { NativeDeckDraft.of(record.deckList) }
    val colors = DeckStudioDraftPresentation.colors(draft, metadata)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    var contextMenu by remember { mutableStateOf(false) }
    // Each deck is a little book on the page: a plate in a brass edge with book-corner protectors.
    Column(Modifier.fillMaxWidth().binderPlate(BinderCornerStyle.BOOK)) {
        // Long-press opens the same deck actions as the ⋯ button, like the iOS tile's context menu.
        Column(Modifier.fillMaxWidth().scale(if (pressed) 0.985f else 1f).alpha(if (pressed) 0.86f else 1f)
            .combinedClickable(interaction, null, onLongClickLabel = "Deck actions", onLongClick = { contextMenu = true }) { open() }
            .semantics { contentDescription = "deckStudio.deck.${if (included) record.id else "local:${record.id}"}" },
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.fillMaxWidth().height(if (grid) 164.dp else 130.dp).clip(RoundedCornerShape(0.dp))) {
                DeckStudioArtwork(record.commander?.cardName ?: "", Modifier.fillMaxSize(), hero = true, colors = colors,
                    art = io.magicmobile.android.CardArtSelection.Exact(record.commander?.printing))
                if (selected) DeckStudioPlayingBadge(Modifier.padding(10.dp))
                // The deck's Commander bracket (game/Ranked.kt).
                bracket?.let { Box(Modifier.align(Alignment.TopEnd).padding(10.dp)) { io.magicmobile.android.ranked.BracketTag(it, short = true) } }
                // Only a deck that needs fixes says so on its tile (Caleb, 2026-10-03).
                status?.takeIf { it == io.magicmobile.android.studio.DeckStudioPlayStatus.NEEDS_FIXES }?.let { DeckStudioPlayStatusChip(it, Modifier.align(Alignment.BottomStart).padding(10.dp)) }
                DeckTileContextMenu(contextMenu, { contextMenu = false }, actions)
            }
            DeckStudioTileDetails(record.name, DeckStudioDraftPresentation.commanders(draft).joinToString(" • "), colors, tags, showTags,
                "${CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))} · ${if (included) "Included" else "Local draft"}",
                Modifier.padding(start = 14.dp, end = 14.dp, bottom = 10.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (included) "Make it your own" else DateFormat.getDateInstance(DateFormat.LONG).format(Date(record.updatedAt)),
                Modifier.weight(1f), color = DeckStudioPalette.secondaryInk, style = sf(11f), minLines = 2, maxLines = 2)
            // Brass coins: the favourite star (lit with ember once chosen) and the deck's options.
            BinderCoin(if (favorite) "star.fill" else "star", if (favorite) "Unfavorite ${record.name}" else "Favorite ${record.name}", lit = favorite,
                onClick = toggleFavorite)
            StudioMenu(actions) { BinderCoin("ellipsis", "Options for ${record.name}") }
        }
    }
}

/** The tile's long-press menu: the ⋯ menu's entries in the binder's own drop-down. */
@Composable
private fun DeckTileContextMenu(expanded: Boolean, dismiss: () -> Unit, entries: () -> List<MenuEntry>) {
    io.magicmobile.android.board.BinderDropdown(expanded, dismiss) {
        io.magicmobile.android.board.BinderMenuEntries(if (expanded) entries() else emptyList(), dismiss)
    }
}

/** Each metadata slot reserves its lines, so tiles in a row stay aligned. */
@Composable
fun DeckStudioTileDetails(name: String, commanders: String, colors: List<String>?, tags: List<String>, showTags: Boolean, summary: String,
                          modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(name, color = DeckStudioPalette.ink, style = StudioText.headline, minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(commanders.ifEmpty { " " }, color = DeckStudioPalette.secondaryInk, style = StudioText.caption, minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis)
        DeckStudioColorIdentity(colors)
        if (showTags) Text(tags.joinToString(" · ").ifEmpty { " " }, color = DeckStudioPalette.accent, style = StudioText.caption2, minLines = 2, maxLines = 2,
            overflow = TextOverflow.Ellipsis)
        Text(summary, color = DeckStudioPalette.secondaryInk, style = StudioText.caption, minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** A fixed-height pad under content that scrolls behind a bottom inset. */
@Composable
fun BottomSpacer(height: Dp = 24.dp) = Spacer(Modifier.navigationBarsPadding().height(height))

/** Deck Studio is light (`.preferredColorScheme(.light)`): dark status and navigation bar icons while it shows. */
@Composable
fun LightSystemBars() {
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(view) {
        val window = (view.context as? android.app.Activity)?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        val status = controller?.isAppearanceLightStatusBars; val navigation = controller?.isAppearanceLightNavigationBars
        controller?.isAppearanceLightStatusBars = true; controller?.isAppearanceLightNavigationBars = true
        onDispose { status?.let { controller.isAppearanceLightStatusBars = it }; navigation?.let { controller.isAppearanceLightNavigationBars = it } }
    }
}
