package io.magicmobile.android.studio

import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ondevice.OnDeviceSetupModel
import io.magicmobile.android.ondevice.OnDeviceSetupPreferences
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

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

/** DeckStudioRootView.swift: the collection and editor share a quiet, artwork-led workshop. */
@Composable
fun DeckStudioRootView(setup: OnDeviceSetupModel, selectedDeckID: String, select: (String) -> Unit, preparePlay: () -> Unit, dismiss: () -> Unit) {
    val context = LocalContext.current
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
    var pendingDelete by remember { mutableStateOf<DeckLibraryRecord?>(null) }
    var showPreferences by remember { mutableStateOf(false) }

    data class Entry(val record: DeckLibraryRecord, val included: Boolean) { val id get() = if (included) record.id else "local:${record.id}" }
    val records = library.decks.map { Entry(it, false) } + setup.precons.map { Entry(DeckLibraryRecord.included(it), true) }
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
                StudioCatalogue(metadata, OnDeviceDeckResolver(index), null)
            } catch (failure: Exception) { StudioCatalogue(null, null, failure.message ?: "The local card catalogue could not load.") }
        }
    }

    LaunchedEffect(Unit) {
        DeckStudioServices.install(context)
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
    StudioScreen {
        Column(Modifier.fillMaxSize()) {
            StudioNavBar("Deck Studio", leading = {
                StudioGlassGroup { StudioGlassText("Done", dismiss) }
            }, trailing = {
                StudioGlassGroup { StudioGlassIcon("slider.horizontal.3", "Deck artwork and privacy", { showPreferences = true }) }
            })
            LazyVerticalGrid(if (grid) GridCells.Adaptive(160.dp) else GridCells.Fixed(1), Modifier.fillMaxSize().widthIn(max = 1000.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 40.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        LibraryHeader(onCreate = { route = StudioRoute.Deck(null, false) }, onImport = { route = StudioRoute.Importer },
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
                            }) {
                                Row(Modifier.defaultMinSize(minHeight = 44.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    SfImage("arrow.up.arrow.down", DeckStudioPalette.ink, 16.dp)
                                    Text(query.sort.title, color = DeckStudioPalette.ink, style = StudioText.subheadline)
                                }
                            }
                            StudioIconButton(if (grid) "list.bullet" else "square.grid.2x2", if (grid) "Show deck list" else "Show deck grid", { grid = !grid })
                        }
                        if (visible.isEmpty()) StudioContentUnavailable(if (query.text.isEmpty()) "Your next deck starts here" else "No matching decks",
                            "rectangle.stack", "Create a deck, import a list, or change your filters.")
                    }
                }
                items(visible, key = { it.id }) { value ->
                    DeckTile(value.record, value.included, value.id == selectedDeckID, grid, metadata, tags[value.record.id] ?: emptyList(),
                        showTags = tags.values.any { it.isNotEmpty() }, favorite = value.id in favorites,
                        open = { route = StudioRoute.Deck(value.record, value.included) }, toggleFavorite = { toggleFavorite(value.id) },
                        actions = {
                            deckActions(context, value.record, value.included, open = { route = StudioRoute.Deck(value.record, value.included) },
                                duplicate = {
                                    try {
                                        val copy = library.duplicateLocalDurably(value.record, value.record.name + " — Copy")
                                        scope.launch(Dispatchers.IO) {
                                            runCatching { DeckStudioServices.organization.duplicate(value.record.id, copy.id) }
                                                .onFailure { error = "Cards were copied, but their optional details could not be copied: ${it.message}" }
                                        }
                                        reloadTags(); route = StudioRoute.Deck(copy, false)
                                    } catch (failure: Exception) { error = failure.message }
                                }, delete = { pendingDelete = value.record })
                        })
                }
            }
        }
        StudioCover(route != null) {
            when (val current = route) {
                is StudioRoute.Deck -> DeckStudioWorkspaceScreen(library, current.record, current.included, metadata, catalogue?.resolver,
                    selectForPlay = { id -> select(id); route = null; dismiss(); preparePlay() }, close = { route = null; reloadTags() })
                StudioRoute.Importer -> DeckStudioImportScreen(library, catalogue?.resolver, didImport = { saved -> select("local:${saved.id}") },
                    close = { route = null; reloadTags() })
                null -> {}
            }
        }
    }
    if (showPreferences) BoardSheet({ showPreferences = false }, background = rgbLight, skipPartiallyExpanded = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Artwork & privacy", done = { showPreferences = false })
            Column(Modifier.padding(horizontal = 16.dp)) { NativeArtworkPreferenceRows() }
        }
    }
    pendingDelete?.let { record ->
        ConfirmationDialog("Delete this local deck?", "Included decks and source websites are never changed.",
            listOf(ConfirmationAction("Delete ${record.name}", destructive = true) { delete(record) }), light = true) { pendingDelete = null }
    }
}

/** The grouped-form background of a light sheet (systemGroupedBackground). */
val rgbLight: Color = io.magicmobile.android.ui.rgb(0.95, 0.95, 0.97)

/** A light sheet's bar: centred title and a trailing Done (or custom) action. */
@Composable
fun StudioSheetBar(title: String, done: (() -> Unit)? = null, doneTitle: String = "Done", doneEnabled: Boolean = true,
                   cancel: (() -> Unit)? = null, cancelTitle: String = "Cancel") {
    Box(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 16.dp)) {
        cancel?.let { Box(Modifier.align(Alignment.CenterStart)) { StudioGlassGroup { StudioGlassText(cancelTitle, it) } } }
        Text(title, Modifier.align(Alignment.Center).widthIn(max = 220.dp), color = DeckStudioPalette.ink, style = sf(17f, SfWeight.semibold),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        done?.let {
            Box(Modifier.align(Alignment.CenterEnd).height(44.dp).alpha(if (doneEnabled) 1f else 0.4f).background(DeckStudioPalette.ink, CircleShape)
                .clickable(enabled = doneEnabled) { it() }.padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                Text(doneTitle, color = Color.White, style = sf(17f, SfWeight.semibold))
            }
        }
    }
}

/** A full-screen cover sliding up over the studio (SwiftUI fullScreenCover). */
@Composable
fun StudioCover(visible: Boolean, content: @Composable () -> Unit) {
    AnimatedVisibility(visible, enter = slideInVertically(androidx.compose.animation.core.tween(320)) { it } + fadeIn(),
        exit = slideOutVertically(androidx.compose.animation.core.tween(260)) { it } + fadeOut()) {
        Box(Modifier.fillMaxSize().background(DeckStudioPalette.background).clickable(remember { MutableInteractionSource() }, null) {}) { content() }
    }
}

@Composable
private fun LibraryHeader(onCreate: () -> Unit, onImport: () -> Unit, importEnabled: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("YOUR COLLECTION", color = DeckStudioPalette.secondaryInk, style = sf(12f, SfWeight.semibold, tracking = 1.8f))
        Text("My Decks", color = DeckStudioPalette.ink, style = sf(34f, SfWeight.bold, tracking = -1f))
        Text("Find your next move.", color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StudioButton("Create deck", onCreate, Modifier.weight(1f).semantics { contentDescription = "deckStudio.create" }, icon = "plus")
            StudioButton("Import", onImport, Modifier.weight(1f).semantics { contentDescription = "deckStudio.import" }, primary = false,
                icon = "square.and.arrow.down", enabled = importEnabled)
        }
    }
}

@Composable
private fun LibraryFilters(query: DeckStudioLibraryQuery, change: (DeckStudioLibraryQuery) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StudioSearchField(query.text, { change(query.copy(text = it)) }, "Search decks, commanders or tags")
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (filter in DeckStudioLibraryQuery.Filter.entries) {
                val selected = query.filter == filter
                Box(Modifier.defaultMinSize(minHeight = 44.dp).background(if (selected) DeckStudioPalette.ink else DeckStudioPalette.surface, CircleShape)
                    .clip(CircleShape).clickable { change(query.copy(filter = filter)) }.padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text(filter.title, color = if (selected) Color.White else DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                }
            }
        }
    }
}

private fun deckActions(context: Context, record: DeckLibraryRecord, included: Boolean, open: () -> Unit, duplicate: () -> Unit, delete: () -> Unit): List<MenuEntry> {
    val json = runCatching { OnDeviceDeckEditing.exportJSON(record.deckList) }.getOrNull()
    val text = runCatching { DeckStudioTextExport.text(record.deckList) }.getOrNull()
    return buildList {
        add(MenuEntry.Item("Open deck", "pencil") { open() })
        add(MenuEntry.Item("Duplicate locally", "doc.on.doc") { duplicate() })
        json?.let { add(MenuEntry.Item("Export native JSON", "square.and.arrow.up") { shareText(context, it) }) }
        if (text != null) add(MenuEntry.Item("Export plain text", "doc.plaintext") { shareText(context, text) })
        else add(MenuEntry.Label("Plain text unavailable · use JSON to preserve this draft"))
        if (!included && !record.isCloudBacked) add(MenuEntry.Item("Delete local deck", "trash", destructive = true) { delete() })
    }
}

@Composable
private fun DeckTile(record: DeckLibraryRecord, included: Boolean, selected: Boolean, grid: Boolean, metadata: NativeDeckMetadataCatalogue?,
                     tags: List<String>, showTags: Boolean, favorite: Boolean, open: () -> Unit, toggleFavorite: () -> Unit, actions: () -> List<MenuEntry>) {
    val draft = remember(record) { NativeDeckDraft.of(record.deckList) }
    val colors = DeckStudioDraftPresentation.colors(draft, metadata)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(20.dp)
    Column(Modifier.fillMaxWidth().shadow(12.dp, shape, ambientColor = DeckStudioPalette.ink.copy(alpha = 0.04f), spotColor = DeckStudioPalette.ink.copy(alpha = 0.06f))
        .background(DeckStudioPalette.surface, shape).clip(shape)) {
        Column(Modifier.fillMaxWidth().scale(if (pressed) 0.985f else 1f).alpha(if (pressed) 0.86f else 1f)
            .clickable(interaction, null) { open() }.semantics { contentDescription = "deckStudio.deck.${if (included) record.id else "local:${record.id}"}" },
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.fillMaxWidth().height(if (grid) 164.dp else 130.dp).clip(RoundedCornerShape(0.dp))) {
                DeckStudioArtwork(record.commander?.cardName ?: "", Modifier.fillMaxSize(), hero = true, colors = colors)
                if (selected) Row(Modifier.padding(10.dp).background(DeckStudioPalette.ink, CircleShape).padding(horizontal = 10.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfImage("checkmark.circle.fill", Color.White, 12.dp)
                    Text("Selected", color = Color.White, style = StudioText.caption2.weight(SfWeight.semibold))
                }
            }
            DeckStudioTileDetails(record.name, DeckStudioDraftPresentation.commanders(draft).joinToString(" • "), colors, tags, showTags,
                "${DeckStudioDraftPresentation.gameCount(draft)} cards · ${if (included) "Included" else "Local draft"}",
                Modifier.padding(start = 14.dp, end = 14.dp, bottom = 10.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (included) "Make it your own" else DateFormat.getDateInstance(DateFormat.LONG).format(Date(record.updatedAt)),
                Modifier.weight(1f), color = DeckStudioPalette.secondaryInk, style = StudioText.caption2, minLines = 2, maxLines = 2)
            StudioIconButton(if (favorite) "star.fill" else "star", if (favorite) "Unfavorite ${record.name}" else "Favorite ${record.name}", toggleFavorite)
            StudioMenu(actions) {
                Box(Modifier.size(44.dp).semantics { contentDescription = "Options for ${record.name}" }, contentAlignment = Alignment.Center) {
                    SfImage("ellipsis.circle", DeckStudioPalette.ink, 20.dp)
                }
            }
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
