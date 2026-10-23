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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.game.ArenaBoxGeometry
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.game.CommanderBracket
import io.magicmobile.android.menus.ArenaArt
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaDeckBox
import io.magicmobile.android.menus.ArenaDeckBoxModel
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaNewDeckBox
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaPips
import io.magicmobile.android.menus.ArenaPlayButton
import io.magicmobile.android.menus.ArenaRoomBackdrop
import io.magicmobile.android.menus.ArenaSectionHeader
import io.magicmobile.android.menus.LocalArenaMenuBackdrop
import io.magicmobile.android.menus.arenaGlassPanel
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ranked.tint
import io.magicmobile.android.ondevice.OnDeviceSetupModel
import io.magicmobile.android.ondevice.OnDeviceSetupPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
 * DeckStudioRootView.swift: Arena's Decks page (decks-1), under the menu shell's top bar over the dimmed room. The filters
 * along the top, every deck as a deck box across the page (the first tap opens a box, a second opens the deck), and the chosen
 * deck on a strip along the foot with Edit Deck and Play. [open] opens a deck straight away (the setup screen's "Fix in Deck
 * Studio"). The editor and the importer are full-screen covers that draw their own dimmed room.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioRootView(setup: OnDeviceSetupModel, selectedDeckID: String, select: (String) -> Unit, preparePlay: () -> Unit, dismiss: () -> Unit,
                       open: DeckStudioOpen? = null, covered: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    DeckStudioServices.install(context)
    val library = setup.library
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf(DeckStudioLibraryQuery()) }
    var tags by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var favorites by remember { mutableStateOf<Set<String>>(emptySet()) }
    var favoritesReadable by remember { mutableStateOf(true) }
    var catalogue by remember { mutableStateOf<StudioCatalogue?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var route by remember { mutableStateOf<StudioRoute?>(null) }
    val stage = rememberGrimoireStage()
    fun turn(next: StudioRoute?) = stage.turnPage(forward = next != null) { route = next }
    var pendingDelete by remember { mutableStateOf<DeckLibraryRecord?>(null) }
    var showPreferences by remember { mutableStateOf(false) }
    var pendingFix by remember { mutableStateOf<DeckStudioOpen?>(null) }
    var openedFromSetup by remember { mutableStateOf<DeckStudioOpen?>(null) }
    var statuses by remember { mutableStateOf<Map<String, DeckStudioPlayStatus>>(emptyMap()) }
    /** The deck whose box stands open and whose details show on the strip (the playing deck until another is chosen). */
    var focused by rememberSaveable { mutableStateOf<String?>(null) }
    val currentSelection by rememberUpdatedState(selectedDeckID)
    val currentSelect by rememberUpdatedState(select)
    val play = remember {
        DeckStudioPlaySelection(scope, gameLive = { setup.needsLeave || setup.isBusy }, select = { currentSelect(it) }, selectedID = { currentSelection })
    }

    data class Entry(val record: DeckLibraryRecord, val included: Boolean) { val id get() = if (included) record.id else "local:${record.id}" }
    val records = library.decks.map { Entry(it, false) } + setup.precons.map { Entry(DeckLibraryRecord.included(it), true) }
    // A saved deck's bracket: the list check, raised by the player's own label (DeckBracketPreference).
    val bracketPrefs by io.magicmobile.android.ui.AppPreferences.string(io.magicmobile.android.game.DeckBracketPreference.KEY, "{}")
    fun deckBracket(id: String, record: DeckLibraryRecord): CommanderBracket {
        val played = record.entries.filter { it.section in setOf("deck", "main", "commander", "commanders") }.map { it.cardName }
        val minimum = setup.bracketRules.evaluate(listOfNotNull(record.commander?.cardName) + played).minimum
        val declared = runCatching {
            (kotlinx.serialization.json.Json.parseToJsonElement(bracketPrefs) as kotlinx.serialization.json.JsonObject)[id]
                ?.let { (it as kotlinx.serialization.json.JsonPrimitive).content.toIntOrNull() }?.let(CommanderBracket::of)
        }.getOrNull()
        return io.magicmobile.android.game.DeckBracketPreference.effective(minimum, declared)
    }
    fun bracket(entry: Entry): CommanderBracket = if (entry.included) CommanderBracket.CORE else deckBracket(entry.id, entry.record)
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
    val focusedID = ArenaDecksPage.focusedID(focused, selectedDeckID, records.map { it.id }, visible.map { it.id })
    val focusedEntry = records.firstOrNull { it.id == focusedID }

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
            if (focused == "local:${record.id}") focused = null
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
    // The editor and the importer cover the whole screen, the menu shell's top bar too: the shell steps aside meanwhile.
    val currentCovered by rememberUpdatedState(covered)
    LaunchedEffect(route != null) { currentCovered(route != null) }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { currentCovered(false) } }

    val metadata = catalogue?.metadata
    val resolver = catalogue?.resolver
    // Each box's status comes only from a stored result whose key matches the deck as it is now.
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
    fun needsFixes(id: String) = resolver != null && statuses[id] == DeckStudioPlayStatus.NEEDS_FIXES
    fun openEntry(entry: Entry) = turn(StudioRoute.Deck(entry.record, entry.included))
    fun openDeck(target: DeckStudioOpen) {
        val entry = records.firstOrNull { it.id == target.deckID } ?: return
        pendingFix = target.takeIf { it.cards.isNotEmpty() }
        openEntry(entry)
    }
    /** Fix deck: the open workspace filters its own cards; from the library it opens the deck first. */
    fun fix(target: DeckStudioOpen) { if (route is StudioRoute.Deck) pendingFix = target else openDeck(target) }
    LaunchedEffect(open, records.map { it.id }) {
        if (open == null || open == openedFromSetup || records.none { it.id == open.deckID }) return@LaunchedEffect
        openedFromSetup = open
        openDeck(open)
    }
    // Development fixture (MAGICMOBILE_UI_TEST_OPEN=deck): the playing deck's workspace.
    var fixtureHandled by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(records.map { it.id }) {
        if (fixtureHandled || io.magicmobile.android.ranked.SocialFixtures.openScreen != "deck") return@LaunchedEffect
        if (records.any { it.id == selectedDeckID }) { fixtureHandled = true; openDeck(DeckStudioOpen(selectedDeckID)) }
    }
    fun playEntry(entry: Entry) = play.play(DeckStudioPlaySelection.source(entry.id, entry.record.deckList), resolver, entry.record.name)
    fun actions(entry: Entry): List<MenuEntry> = listOf<MenuEntry>(MenuEntry.Section(entry.record.name)) +
        deckActions(context, entry.record, entry.included, playEnabled = resolver != null && !play.checking, play = { playEntry(entry) },
            open = { openEntry(entry) },
            duplicate = {
                try {
                    val copy = library.duplicateLocalDurably(entry.record, entry.record.name + " — Copy")
                    scope.launch(Dispatchers.IO) {
                        runCatching { DeckStudioServices.organization.duplicate(entry.record.id, copy.id) }
                            .onFailure { error = "Cards were copied, but their optional details could not be copied: ${it.message}" }
                    }
                    reloadTags(); turn(StudioRoute.Deck(copy, false))
                } catch (failure: Exception) { error = failure.message }
            }, delete = { pendingDelete = entry.record })

    GrimoirePages(stage) {
        Box(Modifier.fillMaxSize()) {
            BinderCover()
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val wide = maxWidth > maxHeight
                Column(Modifier.fillMaxSize().navigationBarsPadding().padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    LibraryBar(wide, query, { query = it }, importEnabled = resolver != null, import = { turn(StudioRoute.Importer) },
                        preferences = { showPreferences = true })
                    // Anything to tell the player: the library's notices and the artwork invitation.
                    (error ?: library.notice)?.let { DeckStudioNotice("Your library is preserved", it, "exclamationmark.triangle") }
                    catalogue?.error?.let { message ->
                        DeckStudioNotice("Card catalogue unavailable", message)
                        ArenaPillButton("Retry local catalogue", { catalogue = null; loadCatalogue() })
                    }
                    DeckStudioArtworkInvitation()
                    DeckShelf(Modifier.weight(1f).fillMaxWidth(), visible.size, focused = visible.indexOfFirst { it.id == focusedID }.takeIf { it >= 0 },
                        emptyTitle = if (query.text.isEmpty()) "Your next deck starts here" else "No matching decks",
                        create = { turn(StudioRoute.Deck(null, false)) }) { index, width ->
                        val entry = visible[index]
                        val chosen = entry.id == focusedID
                        val draft = remember(entry.record) { NativeDeckDraft.of(entry.record.deckList) }
                        var menu by remember { mutableStateOf(false) }
                        val model = ArenaDeckBoxModel(entry.id, entry.record.name, entry.record.commander?.cardName,
                            DeckStudioDraftPresentation.colors(draft, metadata) ?: emptyList(), bracket(entry).label,
                            ArenaDecksPage.tag(needsFixes(entry.id), entry.id == selectedDeckID))
                        Box(Modifier.testTag("deckStudio.deck.${entry.id}").semantics { if (chosen) selected = true }
                            // Arena's way: the first tap opens the box and shows the deck; a second opens it for editing.
                            .combinedClickable(remember { MutableInteractionSource() }, null, onLongClickLabel = "Deck actions", onLongClick = { menu = true }) {
                                when (ArenaDecksPage.tap(chosen)) {
                                    ArenaDecksPage.Tap.EDIT -> openEntry(entry)
                                    ArenaDecksPage.Tap.OPEN_BOX -> { GameAudio.play(GameSound.UI_TAP); focused = entry.id }
                                }
                            }) {
                            // The pencil only on the chosen box, so the others' names have the whole plate.
                            ArenaDeckBox(model, selected = chosen, width = width, edit = if (chosen) ({ openEntry(entry) }) else null)
                            io.magicmobile.android.board.BinderDropdown(menu, { menu = false }) {
                                io.magicmobile.android.board.BinderMenuEntries(if (menu) actions(entry) else emptyList()) { menu = false }
                            }
                        }
                    }
                    focusedEntry?.let { entry ->
                        val draft = remember(entry.record) { NativeDeckDraft.of(entry.record.deckList) }
                        DeckStrip(entry.id, entry.record.name, DeckStudioDraftPresentation.commanders(draft),
                            entry.record.commander?.cardName ?: "", DeckStudioDraftPresentation.colors(draft, metadata) ?: emptyList(), bracket(entry),
                            "${CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))} · ${if (entry.included) "Included" else "Your deck"}",
                            needsFixes(entry.id), wide, favorite = entry.id in favorites, toggleFavorite = { toggleFavorite(entry.id) }, actions = { actions(entry) },
                            playEnabled = resolver != null && !play.checking, edit = { openEntry(entry) }, play = { playEntry(entry) })
                    }
                }
            }
            // The editor and the importer: full-screen covers outside the shell, each drawing its own dimmed room.
            StudioCover(route != null, animated = false) {
                when (val current = route) {
                    is StudioRoute.Deck -> DeckStudioWorkspaceScreen(library, current.record, current.included, metadata, catalogue?.resolver,
                        play = play, close = { turn(null); reloadTags() }, fix = pendingFix, consumeFix = { pendingFix = null })
                    // A new import opens in its workspace, where Play is one tap away; the playing deck is unchanged.
                    StudioRoute.Importer -> DeckStudioImportScreen(library, catalogue?.resolver, metadata = metadata, didImport = { saved -> reloadTags(); turn(StudioRoute.Deck(saved, false)) },
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
        val message = if (selectedDeckID == "local:${record.id}") DeckStudioPlayText.deletePlaying(replacement) else "Included decks and source websites are never changed."
        ConfirmationDialog("Delete this local deck?", message,
            listOf(ConfirmationAction("Delete ${record.name}", destructive = true) { delete(record) }), light = true) { pendingDelete = null }
    }
}

/** The bar over the boxes: search, which decks, their order, Import and the artwork settings. */
@Composable
private fun LibraryBar(wide: Boolean, query: DeckStudioLibraryQuery, change: (DeckStudioLibraryQuery) -> Unit, importEnabled: Boolean, import: () -> Unit,
                       preferences: () -> Unit) {
    val artwork: @Composable () -> Unit = {
        BinderPlaque(icon = "photo.on.rectangle.angled", square = true, label = "Deck artwork and privacy", onClick = preferences)
    }
    val pills: @Composable () -> Unit = {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            StudioMenu({
                listOf<MenuEntry>(MenuEntry.Section("Show decks")) + DeckStudioLibraryQuery.Filter.entries.map { filter ->
                    MenuEntry.Item(filter.title, checked = filter == query.filter) { change(query.copy(filter = filter)) }
                }
            }, Modifier.testTag("deckStudio.library.filter")) {
                BinderPlaque(title = if (query.filter == DeckStudioLibraryQuery.Filter.ALL) "All decks" else query.filter.title, trailingIcon = "chevron.down")
            }
            StudioMenu({
                listOf<MenuEntry>(MenuEntry.Section("Sort decks")) + DeckStudioLibraryQuery.Sort.entries.map { sort ->
                    MenuEntry.Item(sort.title, checked = sort == query.sort) { change(query.copy(sort = sort)) }
                }
            }) { BinderPlaque(title = query.sort.title, trailingIcon = "chevron.down") }
            BinderPlaque(Modifier.testTag("deckStudio.import"), title = "Import", icon = "square.and.arrow.down", enabled = importEnabled, onClick = import)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (wide) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            BinderSearchField(query.text, { change(query.copy(text = it)) }, "Search decks", Modifier.widthIn(min = 210.dp, max = 300.dp),
                tag = "deckStudio.library.search")
            pills()
            Spacer(Modifier.weight(1f))
            artwork()
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                BinderSearchField(query.text, { change(query.copy(text = it)) }, "Search decks, commanders or tags", Modifier.weight(1f),
                    tag = "deckStudio.library.search")
                artwork()
            }
            pills()
        }
    }
}

/**
 * Every deck as a deck box (the first cell makes a new deck), rows apart by an open lid's rise. The chosen box comes fully into
 * view, lid and all, as Arena scrolls to it; on arrival a playing deck past the first row rests just above the strip.
 */
@Composable
private fun DeckShelf(modifier: Modifier, count: Int, focused: Int?, emptyTitle: String, create: () -> Unit,
                      box: @Composable (index: Int, width: Dp) -> Unit) {
    BoxWithConstraints(modifier) {
        // Sideways the page is short: the boxes shrink until a whole box, name plate included, fits above the strip.
        val grid = ArenaDecksPage.grid(maxWidth.value - 8f, maxHeight.value)
        val width = grid.boxWidth.dp
        val geometry = ArenaBoxGeometry(grid.boxWidth)
        val rise = (geometry.rise * 1.5f).dp
        val rowHeight = (geometry.boxHeight + geometry.plateHeight - geometry.plateOverlap).dp
        val list = rememberLazyListState()
        val viewport = maxHeight
        val density = LocalDensity.current
        val scope = rememberCoroutineScope()
        // Item 0 is the heading, then the empty page (when nothing shows), then the rows.
        val firstRow = if (count == 0) 2 else 1
        fun scrollTo(index: Int, anchor: Float, animated: Boolean) {
            val row = ArenaDecksPage.row(ArenaDecksPage.cell(index), grid.columns)
            // The row's foot rests at `anchor` of the page's height, never under the foot's scroll fade (28), so its name plates show.
            val offset = with(density) { -(minOf(viewport * anchor, viewport - 32.dp) - rowHeight - rise).roundToPx() }
            scope.launch { runCatching { if (animated) list.animateScrollToItem(firstRow + row, offset) else list.scrollToItem(firstRow + row, offset) } }
        }
        var arrived by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(focused) {
            val index = focused ?: return@LaunchedEffect
            if (!arrived) {
                arrived = true
                if (!ArenaDecksPage.scrollsOnArrival(index, grid.columns)) return@LaunchedEffect
                kotlinx.coroutines.delay(300)
                scrollTo(index, 0.94f, animated = false)
            } else scrollTo(index, 0.62f, animated = true)
        }
        val rows = ArenaDecksPage.rows(count, grid.columns)
        LazyColumn(Modifier.fillMaxSize().arenaScrollFade(28.dp, 14.dp).testTag("deckStudio.library.grid"), state = list) {
            item(key = "heading") { ArenaSectionHeader("My Decks", count = count) }
            if (count == 0) item(key = "empty") { BinderEmptyLeaf(emptyTitle, "rectangle.stack", "Create a deck, import a list, or change your filters.") }
            items(rows, key = { "row-$it" }) { row ->
                // Only a box open in the first row needs room above it.
                val top = if (row == 0) (if (ArenaDecksPage.firstRowOpen(focused, grid.columns)) rise + 10.dp else 8.dp) else rise + 10.dp
                Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = top, bottom = if (row == rows - 1) 16.dp else 0.dp),
                    horizontalArrangement = Arrangement.spacedBy(ArenaDecksPage.GAP.dp), verticalAlignment = Alignment.Top) {
                    for (column in 0 until grid.columns) {
                        val cell = row * grid.columns + column
                        Box(Modifier.width(width)) {
                            when {
                                cell == 0 -> Box(Modifier.testTag("deckStudio.create").semantics { contentDescription = "Create deck" }
                                    .clickable(remember { MutableInteractionSource() }, null) { GameAudio.play(GameSound.UI_OPEN); create() }) {
                                    ArenaNewDeckBox(width = width)
                                }
                                cell - 1 < count -> box(cell - 1, width)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A deck's bracket as Arena's small glass tag with the bracket's jewel. */
@Composable
private fun ArenaBracketTag(bracket: CommanderBracket, identifier: String) {
    BinderTag("B${bracket.level}", Modifier.testTag(identifier).clearAndSetSemantics { contentDescription = bracket.title }, accent = bracket.tint)
}

/**
 * The chosen deck along the foot of the page: its art, name and pips, its bracket and check, the favourite star and ⋯, then
 * Edit Deck and Play. Sideways it is one row (Arena's decks-1, so the boxes keep the page); upright two.
 */
@Composable
private fun DeckStrip(id: String, name: String, commanders: List<String>, commander: String, colors: List<String>, bracket: CommanderBracket, summary: String,
                      needsFixes: Boolean, wide: Boolean, favorite: Boolean, toggleFavorite: () -> Unit, actions: () -> List<MenuEntry>,
                      playEnabled: Boolean, edit: () -> Unit, play: () -> Unit) {
    val tools: @Composable () -> Unit = {
        Row {
            BinderCoin(if (favorite) "star.fill" else "star", if (favorite) "Unfavorite $name" else "Favorite $name", lit = favorite, onClick = toggleFavorite)
            StudioMenu(actions) { BinderCoin("ellipsis", "Options for $name") }
        }
    }
    val editButton: @Composable (Modifier) -> Unit = { modifier ->
        ArenaButton(edit, modifier, ArenaButtonKind.SECONDARY, compact = true, fullWidth = !wide, label = "Edit Deck", identifier = "deckStudio.edit") {
            ArenaButtonText("Edit Deck")
        }
    }
    val playButton: @Composable (Modifier) -> Unit = { modifier ->
        ArenaPlayButton("Play", play, modifier.height(44.dp), fontSize = 18f, enabled = playEnabled, identifier = "deckStudio.library.play")
    }
    val art: @Composable () -> Unit = {
        val shape = RoundedCornerShape(8.dp)
        ArenaArt(commander, colors, Modifier.size(if (wide) 40.dp else 52.dp, if (wide) 40.dp else 64.dp).clip(shape).border(0.9.dp, ArenaGlass.hairline, shape))
    }
    Column(Modifier.fillMaxWidth().arenaGlassPanel(14.dp, 0.92f).testTag("deckStudio.detail").padding(horizontal = 12.dp, vertical = if (wide) 4.dp else 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (wide) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                art()
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(name, Modifier.semantics { heading() }, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        ArenaPips(colors, 13.dp)
                        ArenaBracketTag(bracket, "deckStudio.bracket.$id")
                        if (needsFixes) DeckStudioPlayStatusChip(DeckStudioPlayStatus.NEEDS_FIXES)
                    }
                }
                tools()
                editButton(Modifier.width(120.dp))
                playButton(Modifier.width(150.dp))
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                art()
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(name, Modifier.semantics { heading() }, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(16f, SfWeight.bold),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(commanders.joinToString(" • "), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11.5f, SfWeight.medium).copy(fontStyle = FontStyle.Italic),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        ArenaPips(colors, 14.dp)
                        ArenaBracketTag(bracket, "deckStudio.bracket.$id")
                        Text(summary, Modifier.weight(1f, fill = false), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium), maxLines = 1,
                            overflow = TextOverflow.Ellipsis)
                        if (needsFixes) DeckStudioPlayStatusChip(DeckStudioPlayStatus.NEEDS_FIXES)
                    }
                }
                tools()
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                editButton(Modifier.weight(1f))
                playButton(Modifier.weight(1f))
            }
        }
    }
}

/** The background of a sheet over the studio: a loose pane of Arena's glass. */
val rgbLight: Color = DeckStudioPalette.surface

/** A sheet's head (BinderLeafHead on iOS): the title in large type with its actions as pills, over a gold hairline. */
@Composable
fun StudioSheetBar(title: String, done: (() -> Unit)? = null, doneTitle: String = "Done", doneEnabled: Boolean = true,
                   cancel: (() -> Unit)? = null, cancelTitle: String = "Cancel") {
    Row(Modifier.fillMaxWidth().background(ArenaGlass.top.copy(alpha = 0.97f))
        .drawBehind { drawRect(binderHairline(0.6f), androidx.compose.ui.geometry.Offset(0f, size.height - 1.dp.toPx()), androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx())) }
        .padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.widthIn(min = 90.dp), contentAlignment = Alignment.CenterStart) { cancel?.let { BinderPlaque(title = cancelTitle, onClick = it) } }
        Text(title, Modifier.weight(1f).semantics { heading() }, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(20f, SfWeight.bold),
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Box(Modifier.widthIn(min = 90.dp), contentAlignment = Alignment.CenterEnd) { done?.let { BinderPlaque(title = doneTitle, enabled = doneEnabled, onClick = it) } }
    }
}

/**
 * A full-screen cover over the studio (SwiftUI fullScreenCover), outside the menu shell: it draws its own dimmed room, so the
 * screens inside it leave theirs out. It slides up unless [animated] is false.
 */
@Composable
fun StudioCover(visible: Boolean, animated: Boolean = true, content: @Composable () -> Unit) {
    val page: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize().background(Color.Black).clickable(remember { MutableInteractionSource() }, null) {}) {
            ArenaRoomBackdrop(0.45f)
            CompositionLocalProvider(LocalArenaMenuBackdrop provides true) { content() }
        }
    }
    if (!animated) { if (visible) page(); return }
    AnimatedVisibility(visible, enter = slideInVertically(androidx.compose.animation.core.tween(320)) { it } + fadeIn(),
        exit = slideOutVertically(androidx.compose.animation.core.tween(260)) { it } + fadeOut()) { page() }
}

private fun deckActions(context: Context, record: DeckLibraryRecord, included: Boolean, playEnabled: Boolean, play: () -> Unit, open: () -> Unit,
                        duplicate: () -> Unit, delete: () -> Unit): List<MenuEntry> {
    val json = runCatching { OnDeviceDeckEditing.exportJSON(record.deckList) }.getOrNull()
    val text = runCatching { DeckStudioTextExport.text(record.deckList) }.getOrNull()
    return buildList {
        add(MenuEntry.Item(DeckStudioPlayText.play, "play.fill", enabled = playEnabled) { play() })
        add(MenuEntry.Item("Open deck", "pencil") { open() })
        add(MenuEntry.Item("Duplicate locally", "doc.on.doc") { duplicate() })
        add(MenuEntry.Divider)
        json?.let { add(MenuEntry.Item("Export native JSON", "square.and.arrow.up") { shareText(context, it) }) }
        if (text != null) add(MenuEntry.Item("Export plain text", "doc.plaintext") { shareText(context, text) })
        else add(MenuEntry.Label("Plain text unavailable · use JSON to preserve this draft"))
        if (!included && !record.isCloudBacked) {
            add(MenuEntry.Divider)
            add(MenuEntry.Item("Delete local deck", "trash", destructive = true) { delete() })
        }
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
