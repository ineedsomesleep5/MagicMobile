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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import io.magicmobile.android.menus.arenaScrollFade
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// No Playtest chapter (Caleb, 2026-10-06): a game against the AI is the playtest; game history lives in the profile.
private val workspaceTabs = listOf("Cards", "Ideas", "Analysis")
private val workspaceLists = mapOf("Cards" to "deckStudio.cards.list", "Ideas" to "deckStudio.ideas.list",
    "Analysis" to "deckStudio.analysis.list")

/**
 * DeckStudioWorkspaceScreen.swift: one deck's cards, ideas, analysis and playtest. [play] is the
 * studio's shared Play controller; [fix] filters the Cards tab to the cards Play asked to fix.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeckStudioWorkspaceScreen(library: DeckLibraryStore, record: DeckLibraryRecord?, included: Boolean, metadata: NativeDeckMetadataCatalogue?,
                              resolver: OnDeviceDeckResolver?, play: DeckStudioPlaySelection, close: () -> Unit,
                              fix: DeckStudioOpen? = null, consumeFix: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val model = remember(record?.id, included) { DeckStudioEditorModel(library, record, included) }
    val combos = remember(record?.id) { DeckStudioComboModel(scope) }
    val browser = remember(record?.id) { DeckStudioEDHRECModel(scope) }
    val validation = remember(record?.id) { DeckStudioValidationState(scope) { model.sourceID } }
    var tab by rememberSaveable { mutableStateOf("Cards") }
    // One list for every chapter: the title plate scrolls away; the chapters stay on the index tabs.
    val listState = rememberLazyListState()
    var landedTab by remember { mutableStateOf(tab) }
    var headerExpanded by rememberSaveable { mutableStateOf(true) }
    var ideas by rememberSaveable { mutableStateOf("Combos") }
    var query by rememberSaveable { mutableStateOf("") }
    var grouping by rememberSaveable { mutableStateOf("Type") }
    var sorting by rememberSaveable { mutableStateOf("Name") }
    var sectionFilter by rememberSaveable { mutableStateOf("") }
    var colorFilter by rememberSaveable { mutableStateOf("") }
    // The binder's two shelves: the deck's own cards, or every card there is to add (Caleb, 2026-10-06).
    var shelf by rememberSaveable { mutableStateOf(BinderShelf.DECK) }
    // The rail's mana value coins, for both shelves; none lit shows every card.
    var manaFilter by remember { mutableStateOf(emptySet<Int>()) }
    var catalogueQuery by rememberSaveable { mutableStateOf("") }
    var catalogueType by rememberSaveable { mutableStateOf("") }
    var withinIdentity by rememberSaveable { mutableStateOf(true) }
    var showSearch by remember { mutableStateOf(false) }
    var showValidation by remember { mutableStateOf(false) }
    var showCommander by remember { mutableStateOf(false) }
    var showBasics by remember { mutableStateOf(false) }
    var replacement by remember { mutableStateOf<NativeDeckRow?>(null) }
    /** The row whose artwork is being chosen. */
    var artworkRow by remember { mutableStateOf<NativeDeckRow?>(null) }
    var inspection by remember { mutableStateOf<String?>(null) }
    /** The art the inspected card shows: a deck row passes its own printing; elsewhere the player's choice for the name. */
    var inspectionArt by remember { mutableStateOf<io.magicmobile.android.CardArtSelection>(io.magicmobile.android.CardArtSelection.Active) }
    // The sideways title plate's quick check, folded into a chip until tapped.
    var spreadQuickCheck by rememberSaveable { mutableStateOf(false) }
    var confirmClose by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var showArtworkPreferences by remember { mutableStateOf(false) }
    var showOrganization by remember { mutableStateOf(false) }
    val builder = remember(record?.id) { DeckStudioBuilderState() }
    // The book shows a deck as its cards' full art (Caleb, 2026-10-05); the list is one tap away.
    var cardLayout by AppPreferences.string("deckStudio.cards.layout.v1", "Grid")

    val draft = model.draft
    val deck = runCatching { draft.deck() }.getOrNull()
    val signature = if (deck != null && resolver != null) runCatching { DeckStudioDeckSignature.native(DeckStudioPlayProjection(deck).resolve(resolver)) }.getOrNull() else null
    fun inspect(name: String, art: io.magicmobile.android.CardArtSelection = io.magicmobile.android.CardArtSelection.Active) { inspection = name; inspectionArt = art }
    val canonical: (String) -> String? = { name -> resolver?.canonicalCardName(name) }
    /** The validation panel's Play this deck: the same flow as the header button, for this draft. */
    fun preparePlay(@Suppress("UNUSED_PARAMETER") playing: DeckList) {
        showValidation = false
        play.play(model.playSource(), resolver, model.draft.name)
    }
    // Fix deck: the Cards tab shows only the rows XMage named ("Showing only: Needs fixes" with Show all).
    // A card the list cannot find leaves the list whole.
    LaunchedEffect(fix) {
        val target = fix ?: return@LaunchedEffect
        tab = "Cards"; shelf = BinderShelf.DECK; query = ""; sectionFilter = ""; colorFilter = ""; manaFilter = emptySet(); showValidation = false
        builder.listFilter = DeckStudioListFilter.NeedsFixes(target.cards)
            .takeIf { target.cards.isNotEmpty() && DeckStudioPlayRules.fixRows(model.draft.rows, target.cards, canonical).isNotEmpty() }
        consumeFix()
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
    BackHandler(builder.selecting) { builder.endSelection() }

    // The live quick check; XMage stays authoritative when a game starts.
    val preflight = remember(draft, metadata, resolver) { DeckStudioPreflight(draft, metadata, resolver) }
    // A fixed issue clears its filter, so the list never stays filtered to nothing.
    LaunchedEffect(preflight) { builder.listFilter?.let { if (it.rows(preflight, draft, canonical).isEmpty()) builder.listFilter = null } }
    // Your own role reviews live with the Analysis tab's role insights.
    val roleKey = "deckStudio.roles.v1." + (model.record?.id ?: "new")
    var roleOverrides by remember { mutableStateOf<Map<String, Set<DeckStudioRole>>>(emptyMap()) }
    LaunchedEffect(roleKey, tab) {
        if (tab == "Cards") roleOverrides = runCatching { DeckStudioRolePreferences.load(roleKey, DeckStudioServices.defaults).overrides }.getOrDefault(emptyMap())
        else builder.endSelection()
    }
    // Commander-first new decks: a new, empty draft opens on the commander picker.
    LaunchedEffect(Unit) {
        if (builder.offeredCommanderFirst || model.record != null || model.readOnly || model.recovered || model.draft.rows.isNotEmpty()) return@LaunchedEffect
        builder.offeredCommanderFirst = true
        // Let the workspace finish presenting before the picker slides over it.
        kotlinx.coroutines.delay(350)
        if (model.draft.rows.isEmpty()) builder.showCommanderFirst = true
    }
    LaunchedEffect(builder.listCopied) { if (builder.listCopied > 0) { kotlinx.coroutines.delay(2000); builder.listCopied = 0 } }
    // Sideways the book lies open as a spread: two pages, each with its own content (GrimoireChrome).
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val spread = Grimoire.isSpread(configuration.screenWidthDp, configuration.screenHeightDp)
    // Cards at least 100 points wide, as on iOS: three across an upright phone's page. Sideways the cards fill the pane left of
    // the 330-point deck column (Arena's builder).
    val pageWidth = if (spread) configuration.screenWidthDp - DECK_COLUMN_WIDTH - 40
        else configuration.screenWidthDp - 14
    val gridColumns = maxOf(2, (pageWidth - 24 + 10) / 110)
    fun copyList(text: String) { copyDeckList(context, text); builder.listCopied += 1 }
    fun setIssueFilter(issue: DeckStudioPreflight.Issue?) { builder.listFilter = issue?.let(DeckStudioListFilter::QuickCheck); if (issue != null) tab = "Cards" }
    fun chooseCommander() { if (!model.readOnly) builder.showCommanderFirst = true }

    // Group, filter and sort exactly as the iOS workspace does.
    val flagged = builder.listFilter?.rows(preflight, draft, canonical)
    val filteredRows = draft.rows.filter { row ->
        val card = metadata?.card(row.cardName)
        (query.isEmpty() || row.cardName.contains(query, true) || card?.oracleText?.contains(query, true) == true) &&
            (sectionFilter.isEmpty() || DeckStudioDraftPresentation.section(row) == sectionFilter) &&
            (colorFilter.isEmpty() || if (colorFilter == "C") card?.colors?.isEmpty() == true else card?.colors?.contains(colorFilter) == true) &&
            BinderMana.matches(card?.manaValue, manaFilter) &&
            (flagged == null || row.id in flagged)
    }.sortedWith { a, b ->
        if (sorting == "Quantity" && a.quantity != b.quantity) return@sortedWith b.quantity.compareTo(a.quantity)
        if (sorting == "Mana value") {
            val left = metadata?.card(a.cardName)?.manaValue ?: Double.POSITIVE_INFINITY
            val right = metadata?.card(b.cardName)?.manaValue ?: Double.POSITIVE_INFINITY
            if (left != right) return@sortedWith left.compareTo(right)
        }
        if (a.cardName == b.cardName) a.id.toString().uppercase().compareTo(b.id.toString().uppercase()) else a.cardName.compareTo(b.cardName)
    }
    // Commanders first, then main-deck groups, then the other boards. A Role group lists a card under every role it has.
    val roles = if (grouping == "Role") remember(filteredRows, metadata, roleOverrides) {
        DeckStudioRoleGroups.membership(filteredRows.filter { DeckStudioDraftPresentation.section(it) == "deck" }, { metadata?.card(it) }, roleOverrides)
    } else emptyMap()
    fun groupKeys(row: NativeDeckRow): List<Pair<String, Double>> {
        val section = DeckStudioDraftPresentation.section(row)
        if (section == "commanders") return listOf("Commanders" to -1.0)
        if (section != "deck") return listOf(section.split(" ").joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.uppercase() } } to 2_000_000.0)
        val card = metadata?.card(row.cardName)
        return when (grouping) {
            "Role" -> (roles[row.id] ?: listOf(DeckStudioRoleGroups.other)).map { title ->
                title to DeckStudioRoleGroups.order.indexOf(title).let { if (it < 0) DeckStudioRoleGroups.order.size.toDouble() else it.toDouble() }
            }
            "Name", "Section" -> listOf("Main deck" to 1_000_001.0)
            "Mana value" -> listOf(card?.manaValue?.let { "Mana value ${if (it % 1.0 == 0.0) it.toLong().toString() else it.toString()}" to minOf(it, 1_000_000.0) }
                ?: ("Unknown mana value" to 1_000_001.0))
            "Color" -> listOf((card?.colors?.let { colors -> if (colors.isEmpty()) "Colorless" else listOf("W", "U", "B", "R", "G").filter { it in colors }.joinToString(" / ") }
                ?: "Unknown color") to 1_000_001.0)
            else -> listOf((card?.types?.let { types ->
                listOf("LAND", "CREATURE", "PLANESWALKER", "INSTANT", "SORCERY", "ARTIFACT", "ENCHANTMENT", "BATTLE").firstOrNull { it in types }
                    ?.lowercase()?.replaceFirstChar { it.uppercase() } ?: "Other types"
            } ?: "Unclassified") to 1_000_001.0)
        }
    }
    val sections: List<Pair<String, List<NativeDeckRow>>> = run {
        val grouped = LinkedHashMap<String, Pair<Double, MutableList<NativeDeckRow>>>()
        for (row in filteredRows) for ((title, order) in groupKeys(row)) grouped.getOrPut(title) { order to ArrayList() }.second += row
        grouped.entries.sortedWith { a, b -> if (a.value.first == b.value.first) a.key.compareTo(b.key) else a.value.first.compareTo(b.value.first) }
            .map { it.key to it.value.second }
    }
    /** Quantities, or unique cards for Role groups where one card can sit in several. */
    fun groupCount(title: String, rows: List<NativeDeckRow>): Int =
        if (grouping == "Role" && title in DeckStudioRoleGroups.order) DeckStudioRoleGroups.uniqueCards(rows) else rows.sumOf { it.quantity }

    val playAction = rememberDeckStudioPlayAction(play, model, resolver)
    /** Long-press actions shared by list rows and grid tiles (cardActions in DeckStudioWorkspaceScreen.swift). */
    fun cardActions(row: NativeDeckRow): List<DeckStudioCardAction> = buildList {
        add(DeckStudioCardAction(DeckStudioPlayText.cardDetails, "info.circle") { inspect(row.cardName, io.magicmobile.android.CardArtSelection.Exact(row.printing)) })
        if (!model.readOnly) {
            add(DeckStudioCardAction(DeckStudioPlayText.addOne, "plus") { model.quantity(row.id, 1) })
            add(DeckStudioCardAction(DeckStudioPlayText.removeOne, "minus") { model.quantity(row.id, -1) })
            add(DeckStudioCardAction(DeckStudioPlayText.chooseArtwork, "photo.on.rectangle") { artworkRow = row })
            add(DeckStudioCardAction(DeckStudioPlayText.replaceCard, "arrow.triangle.2.circlepath") { replacement = row })
            add(DeckStudioCardAction(DeckStudioPlayText.moveTo, null,
                choices = DeckStudioPlayText.destinations.map { (section, title) -> title to { model.move(row.id, section) } }))
            add(DeckStudioCardAction(DeckStudioPlayText.removeRow, "trash", destructive = true) { model.remove(row.id) })
        }
    }
    val preflightBar: @Composable () -> Unit = {
        DeckStudioPreflightBar(preflight, (builder.listFilter as? DeckStudioListFilter.QuickCheck)?.issue, ::setIssueFilter, ::chooseCommander)
    }
    // Upright the page has Play at its foot, so the title plate leaves it out.
    val header: @Composable () -> Unit = {
        WorkspaceHeader(model, metadata, headerExpanded, { headerExpanded = !headerExpanded }, preflightBar, playButton = null)
    }
    // A chapter change changes the page in place (the book's curl is off since Deck Studio became Arena's builder).
    val stage = LocalGrimoireStage.current
    fun chooseTab(destination: String) {
        if (destination == tab) return
        val forward = workspaceTabs.indexOf(destination) > workspaceTabs.indexOf(tab)
        if (stage != null) stage.turnPage(forward) { tab = destination } else tab = destination
    }
    /** A swipe turns to the next chapter or the one before; back past the first is the library's page again. */
    fun turnChapter(step: Int) {
        val index = workspaceTabs.indexOf(tab) + step
        if (index in workspaceTabs.indices) chooseTab(workspaceTabs[index]) else if (step < 0) requestClose()
    }
    // The deck's chapters as Arena's tab strip under the page's head (the judge, 2026-10-22: no side rail of tiles).
    val chapterStrip: @Composable () -> Unit = {
        io.magicmobile.android.menus.ArenaSegmented(workspaceTabs.map { it to it }, tab, { chooseTab(it) }, Modifier.padding(horizontal = 10.dp), stretch = true)
    }
    val deckShelf = shelf == BinderShelf.DECK || model.readOnly
    val commanderColors = DeckStudioDraftPresentation.colors(draft, metadata)
    // The tool bar: the shelf, the search, and the tools and mana values in one strip that runs on to the right.
    // compact (sideways): Arena's one filter line, the shelf switch as symbols, a short search, then the mana values and the
    // tools running on to the right (the judge, 2026-10-22, deckbuilder-1.png), so the cards keep the pane.
    val binderRail: @Composable (Boolean) -> Unit = { compactRail ->
        BinderRail(Modifier.padding(horizontal = 10.dp)) {
            val search: @Composable (Modifier) -> Unit = { fieldModifier ->
                if (deckShelf) BinderSearchField(query, { query = it }, if (compactRail) "Search" else "Search this deck", fieldModifier, tag = "deckStudio.cards.search", clearLabel = "Clear deck search")
                else BinderSearchField(catalogueQuery, { catalogueQuery = it }, if (compactRail) "Search" else "Search all cards", fieldModifier, tag = "deckStudio.catalogue.search", clearLabel = "Clear card search")
            }
            val filtersOn = colorFilter.isNotEmpty() || (if (deckShelf) sectionFilter.isNotEmpty() else catalogueType.isNotEmpty() || !withinIdentity)
            val groupEntries = { listOf("Type", "Role", "Section", "Mana value", "Color", "Name").map { MenuEntry.Item(it, checked = it == grouping) { grouping = it } } }
            val sortEntries = { listOf("Name", "Quantity", "Mana value").map { MenuEntry.Item(it, checked = it == sorting) { sorting = it } } }
            // Group, Sort, the layout and Select live in Filter's menu.
            val tools: @Composable () -> Unit = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StudioMenu({
                        buildList {
                            if (deckShelf) addAll(deckFilterOptions(draft, sectionFilter, colorFilter, { sectionFilter = it }, { colorFilter = it }) { manaFilter = emptySet(); builder.listFilter = null })
                            else addAll(catalogueFilterOptions(catalogueType, colorFilter, withinIdentity.takeIf { commanderColors != null }, { catalogueType = it }, { colorFilter = it },
                                { withinIdentity = it }) { manaFilter = emptySet() })
                            if (deckShelf) {
                                add(MenuEntry.Section("Group cards")); addAll(groupEntries())
                                add(MenuEntry.Section("Sort cards")); addAll(sortEntries())
                                add(MenuEntry.Divider)
                                add(MenuEntry.Item(if (cardLayout == "Grid") DeckStudioPlayText.showAsList else DeckStudioPlayText.showAsGrid,
                                    if (cardLayout == "Grid") "list.bullet" else "square.grid.3x2") { cardLayout = if (cardLayout == "Grid") "List" else "Grid" })
                                if (!model.readOnly) add(MenuEntry.Item(if (builder.selecting) DeckStudioPlayText.doneSelecting else DeckStudioPlayText.selectCards, "checkmark.circle") { builder.toggleSelecting() })
                            }
                        }
                    }, Modifier.testTag("deckStudio.cards.filter")) {
                        BinderPlaque(icon = if (filtersOn) "line.3.horizontal.decrease.circle.fill" else "line.3.horizontal.decrease", square = true, on = filtersOn,
                            label = "Filters, grouping and layout")
                    }
                    BinderPlaque(icon = "arrow.uturn.backward", square = true, enabled = model.history.canUndo && !model.readOnly, label = "Undo deck edit") { model.undo() }
                    BinderPlaque(icon = "arrow.uturn.forward", square = true, enabled = model.history.canRedo && !model.readOnly, label = "Redo deck edit") { model.redo() }
                }
            }
            val strip: @Composable (Modifier, Boolean) -> Unit = { stripModifier, manaFirst ->
                Row(stripModifier.fadeTrailing().horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (manaFirst) { BinderManaFilter(manaFilter, { manaFilter = it }, fill = false); tools() }
                    else { tools(); BinderManaFilter(manaFilter, { manaFilter = it }, fill = false) }
                }
            }
            if (compactRail) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!model.readOnly) BinderShelfSwitch(shelf, { shelf = it }, compact = true)
                search(Modifier.widthIn(min = 130.dp, max = 150.dp))
                // Mana values first, so 0 to 7+ all show; the tools run on after them.
                strip(Modifier.weight(1f), true)
            } else {
                if (!model.readOnly) BinderShelfSwitch(shelf, { shelf = it })
                search(Modifier)
                strip(Modifier.fillMaxWidth(), false)
            }
            if (deckShelf) builder.listFilter?.let { filter ->
                Box(Modifier.fillMaxWidth().grimoirePaper(DeckStudioPalette.surface, 0.2f, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp)) {
                    DeckStudioIssueFilterRow(filter) { builder.listFilter = null }
                }
            }
        }
    }
    // The All cards shelf: the local catalogue through the rail's search, coins, type and colour.
    var catalogue by remember { mutableStateOf<List<CardInfo>>(emptyList()) }
    var catalogueLoading by remember { mutableStateOf(false) }
    val catalogueIdentity = if (withinIdentity) commanderColors else null
    LaunchedEffect(shelf, catalogueQuery, catalogueType, colorFilter, manaFilter, catalogueIdentity, metadata) {
        val source = metadata
        if (shelf != BinderShelf.ALL || source == null) return@LaunchedEffect
        catalogueLoading = true
        kotlinx.coroutines.delay(150)
        catalogue = withContext(Dispatchers.Default) {
            binderCatalogue(source, catalogueQuery, catalogueType, colorFilter, manaFilter, catalogueIdentity)
        }
        catalogueLoading = false
    }
    val ideasSource: @Composable () -> Unit = {
        StudioSegmented(listOf("Combos", "EDHREC"), ideas, { ideas = it }, { it }, Modifier.padding(start = 20.dp, end = 20.dp, top = 4.dp))
    }
    // The combo panel's lookup, approval and details live outside the list, only while it is shown.
    val showCombos = tab == "Ideas" && ideas == "Combos"
    val comboPanel = remember(showCombos) { DeckStudioComboPanelState() }
    val comboInput = if (showCombos) remember(draft, resolver) { DeckStudioSpellbookInput.make(draft, resolver) } else null

    val doneButton: @Composable () -> Unit = { BinderStrapButton("Done", { requestClose() }, Modifier.testTag("deckStudio.close")) }
    // The page's head: Done as a dark pill, Save, then the deck's tags and everything else. `done` false: Done stands at the
    // foot instead, beside Play, as in Arena's builder.
    val head: @Composable (Boolean) -> Unit = { done ->
        Row(Modifier.fillMaxWidth().padding(start = 6.dp, end = 6.dp, top = 8.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (done) doneButton()
            Spacer(Modifier.weight(1f))
            if (model.readOnly) BinderPlaque(title = "Edit a copy") { model.makeEditableCopy() }
            else BinderPlaque(Modifier.testTag("deckStudio.save"), title = "Save", icon = "square.and.arrow.down", enabled = model.canSave) { model.save() }
            BinderPlaque(icon = "tag.fill", square = true, enabled = model.record != null, label = "Deck tags, notes and import receipt") { showOrganization = true }
            StudioMenu({
                buildList {
                    // The same Play as the title plate, which scrolls away.
                    add(MenuEntry.Item(playAction.title, if (playAction.playing) "checkmark.circle" else "play.fill", enabled = playAction.enabled) {
                        play.play(model.playSource(), resolver, model.draft.name)
                    })
                    add(MenuEntry.Item("Validate deck", "checkmark.shield") { showValidation = true })
                    add(MenuEntry.Item("Change primary commander", "crown", enabled = !model.readOnly && metadata != null) { showCommander = true })
                    add(MenuEntry.Item("Basic lands", "leaf", enabled = !model.readOnly) { showBasics = true })
                    add(MenuEntry.Item("Rename deck", "pencil", enabled = !model.readOnly) { showRename = true })
                    add(MenuEntry.Item("Artwork & privacy", "photo") { showArtworkPreferences = true })
                    val text = deck?.let { runCatching { DeckStudioTextExport.text(it) }.getOrNull() }
                    if (text != null) add(MenuEntry.Item("Export plain text", "doc.plaintext") { shareText(context, text) })
                    else add(MenuEntry.Label("Plain text unavailable · use JSON to preserve this draft"))
                    runCatching { draft.exportJSON() }.getOrNull()?.let { json -> add(MenuEntry.Item("Export native JSON", "square.and.arrow.up") { shareText(context, json) }) }
                    add(MenuEntry.Item(DeckStudioPlayText.editAsText, "doc.text", enabled = !model.readOnly) { builder.showTextEditor = true })
                    if (text != null) add(MenuEntry.Item(DeckStudioPlayText.copyList, "doc.on.doc") { copyList(text) })
                }
            }, Modifier.testTag("deckStudio.more")) { BinderPlaque(icon = "ellipsis", square = true, label = "More") }
        }
    }
    /**
     * One line of Arena's deck list: how many, the name and the cost on a pane that fades to the right, with a minus and a plus
     * at its end while the deck can be edited. A tap shows the card; holding it opens the large preview with its actions.
     */
    val deckListRow: @Composable (NativeDeckRow) -> Unit = { row ->
        Row(Modifier.fillMaxWidth().background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0.09f), Color.White.copy(alpha = 0.02f))),
            RoundedCornerShape(5.dp)), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).height(32.dp)
                .combinedClickable(onLongClick = { builder.previewRow = row.id }) { inspect(row.cardName, io.magicmobile.android.CardArtSelection.Exact(row.printing)) }
                .semantics(mergeDescendants = true) { contentDescription = "Inspect ${row.cardName}, quantity ${row.quantity}" }
                .padding(start = 8.dp, end = if (model.readOnly) 8.dp else 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${row.quantity}", Modifier.width(18.dp), color = io.magicmobile.android.menus.ArenaMenuStyle.gold,
                    style = sf(12f, SfWeight.bold).copy(fontFeatureSettings = "tnum", textAlign = androidx.compose.ui.text.style.TextAlign.End))
                Text(row.cardName, Modifier.weight(1f), color = io.magicmobile.android.menus.ArenaMenuStyle.text, style = sf(12.5f, SfWeight.semibold),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                metadata?.card(row.cardName)?.manaCost?.takeIf { it.isNotEmpty() }?.let { cost ->
                    NativeDeckManaCost(cost, Modifier.graphicsLayer { scaleX = 0.8f; scaleY = 0.8f; transformOrigin = androidx.compose.ui.graphics.TransformOrigin(1f, 0.5f) })
                }
            }
            if (!model.readOnly) for ((symbol, step, label) in listOf(Triple("minus", -1, "Remove one ${row.cardName}"), Triple("plus", 1, "Add one ${row.cardName}"))) {
                Box(Modifier.size(28.dp, 32.dp).clickable { GameAudio.play(GameSound.UI_TICK); model.quantity(row.id, step) }.semantics { contentDescription = label },
                    contentAlignment = Alignment.Center) { SfImage(symbol, io.magicmobile.android.menus.ArenaMenuStyle.gold, 10.dp) }
            }
        }
    }
    /** A heading over one type's lines in the deck list: gold capitals and the count. */
    val deckListHeading: @Composable (String, Int) -> Unit = { title, count ->
        Row(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 3.dp), verticalAlignment = Alignment.CenterVertically) {
            io.magicmobile.android.menus.ArenaCaps(title, 9.5f)
            Spacer(Modifier.weight(1f))
            Text("$count", color = DeckStudioPalette.secondaryInk, style = sf(11f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
        }
    }
    // The deck's own cards, as cards or as rows; a deck that can't be edited, unfiltered, is Arena's deck list (name bars by type).
    val deckItems: LazyListScope.() -> Unit = deckItems@{
        if (model.readOnly && builder.listFilter == null && query.isEmpty() && draft.rows.isNotEmpty()) {
            for ((group, rows) in sections) {
                item(key = "list-group-$group") { Box(Modifier.padding(horizontal = 12.dp)) { deckListHeading(group, groupCount(group, rows)) } }
                items(rows, key = { "list/$group/${it.id}" }) { row -> Box(Modifier.padding(horizontal = 12.dp, vertical = 1.dp)) { deckListRow(row) } }
            }
            return@deckItems
        }
        if (draft.rows.isEmpty()) item(key = "empty") {
            StudioContentUnavailable("A deck of possibilities", "plus.rectangle.on.rectangle", "Add your commander and cards. Incomplete drafts are welcome.")
        } else if (filteredRows.isEmpty()) item(key = "nomatch") {
            Column(Modifier.padding(horizontal = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                StudioContentUnavailable("No matching cards", "line.3.horizontal.decrease", "Clear the search or filters to see the full draft.")
                StudioButton("Clear search and filters", { query = ""; sectionFilter = ""; colorFilter = ""; manaFilter = emptySet(); builder.listFilter = null }, primary = false)
            }
        }
        for ((group, rows) in sections) {
            item(key = "group-$group") {
                GrimoireSubheading(group, groupCount(group, rows), Modifier.padding(horizontal = 14.dp).padding(top = 8.dp).padding(vertical = 10.dp))
            }
            fun tap(row: NativeDeckRow) { if (builder.selecting) builder.toggle(row.id) else inspect(row.cardName, io.magicmobile.android.CardArtSelection.Exact(row.printing)) }
            // Long-press: the large preview with the row's actions, as the iOS context menu; not while selecting.
            fun longPress(row: NativeDeckRow) { if (!builder.selecting) builder.previewRow = row.id }
            if (cardLayout == "Grid") items(rows.chunked(gridColumns), key = { "$group/grid/${it.first().id}" }) { chunk ->
                BinderSleeveRow(chunk, gridColumns) { row, modifier ->
                    BinderSleeve(row.cardName, row.quantity, metadata?.card(row.cardName), modifier, notes = preflight.issues(row.id).map { it.badge },
                        selected = if (builder.selecting) row.id in builder.selection else null, canEdit = !model.readOnly,
                        tapLabel = (if (builder.selecting) "" else "Inspect ") + "${row.cardName}, quantity ${row.quantity}",
                        art = io.magicmobile.android.CardArtSelection.Exact(row.printing),
                        add = { GameAudio.play(GameSound.UI_TICK); model.quantity(row.id, 1) },
                        remove = { GameAudio.play(GameSound.UI_TICK); model.quantity(row.id, -1) },
                        tap = { tap(row) }, preview = { longPress(row) })
                }
            } else items(rows, key = { "$group/${it.id}" }) { row ->
                Box(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
                    CardRow(row, model, metadata, inspect = { tap(row) }, replace = { replacement = it }, issues = preflight.issues(row.id),
                        selected = if (builder.selecting) row.id in builder.selection else null, preview = { longPress(row) },
                        chooseArt = { artworkRow = it })
                }
            }
        }
    }
    // Every card there is to add: the plus adds a copy to the main deck.
    val catalogueItems: LazyListScope.() -> Unit = {
        when {
            metadata == null -> item(key = "noCatalogue") {
                DeckStudioNotice("Local catalogue unavailable", "Close this editor and retry the catalogue from your library, or use Add cards to search online.",
                    modifier = Modifier.padding(horizontal = 14.dp))
            }
            catalogueLoading && catalogue.isEmpty() -> item(key = "searching") {
                Text("Searching local cards", Modifier.fillMaxWidth().padding(24.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
            catalogue.isEmpty() -> item(key = "noCards") {
                StudioContentUnavailable("No matching cards", "magnifyingglass", "Try another name, or tap a lit mana coin to turn it off.")
            }
        }
        items(catalogue.chunked(gridColumns), key = { "all/${it.first().name}" }) { chunk ->
            BinderSleeveRow(chunk, gridColumns) { card, modifier ->
                BinderSleeve(card.name, model.cardCount(card.name, "deck"), card, modifier,
                    notes = if (model.needsSingletonReview(card.name, card, "deck")) listOf("Already in playing deck, check the copy limit") else emptyList(),
                    canEdit = !model.readOnly, addLabel = "Add ${card.name} to deck", removeLabel = "Remove one ${card.name} from deck", tapLabel = "Inspect ${card.name}",
                    add = { GameAudio.play(GameSound.UI_TICK); model.add(card.name, "deck") },
                    remove = { GameAudio.play(GameSound.UI_TICK); model.removeOne(card.name, "deck") },
                    tap = { inspect(card.name) }, preview = { builder.preview = card.name })
            }
        }
        if (catalogue.isNotEmpty()) item(key = "catalogueCount") {
            Text(if (catalogue.size >= BINDER_CATALOGUE_LIMIT) "The first $BINDER_CATALOGUE_LIMIT cards · search or filter to narrow" else "${catalogue.size} cards",
                Modifier.fillMaxWidth().padding(8.dp), color = DeckStudioPalette.secondaryInk, style = StudioText.caption2,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
    val shelfItems: LazyListScope.() -> Unit = { if (deckShelf) deckItems() else catalogueItems() }
    val comboItems: LazyListScope.(Dp, @Composable () -> Unit) -> Unit = { minHeight, top ->
        deckStudioComboItems(combos, comboPanel, comboInput, draft, metadata, resolver, model.readOnly, add = { name, section, approved ->
            approved == DeckStudioSpellbookInput.make(model.draft, resolver) && resolver?.canonicalCardName(name) == name && model.add(name, section)
        }, inspect = ::inspect, minHeight = minHeight, top = top)
    }
    val bottomBar: @Composable (Modifier) -> Unit = { modifier ->
        // Quick Add with Add cards, or the bulk actions while selecting, floating over the foot of the page with the
        // cards running under it.
        Box(modifier.fillMaxWidth().pageFade().padding(top = 18.dp, start = 12.dp, end = 12.dp, bottom = 10.dp)) {
            if (builder.selecting) Box(Modifier.fillMaxWidth().shadow(4.dp, RoundedCornerShape(10.dp))
                .background(io.magicmobile.android.menus.ArenaGlass.bottom, RoundedCornerShape(10.dp))
                .border(1.dp, io.magicmobile.android.menus.ArenaGlass.hairline, RoundedCornerShape(10.dp)).padding(8.dp)) {
                DeckStudioBulkBar(builder.liveSelection(draft).size, move = { section ->
                    val ids = builder.liveSelection(model.draft)
                    if (ids.isNotEmpty()) model.change { DeckStudioEditorOperations.moveRows(it, ids, section) }
                }, setQuantity = { builder.showBulkQuantity = true }, remove = { builder.confirmBulkRemove = true },
                    selectAll = { builder.selection = filteredRows.map { it.id }.toSet() })
            }
            else DeckStudioQuickAddBar(metadata, model, openSearch = { showSearch = true }, binder = true)
        }
    }
    val listBottom = if (tab != "Cards" || model.readOnly) 24.dp else if (builder.selecting) 146.dp else 106.dp
    /** Done beside Play along a page's foot, as Arena's builder puts them (the judge, 2026-10-22, deckbuilder-1.png). */
    val donePlayBar: @Composable (Boolean) -> Unit = { shaded ->
        Row(Modifier.fillMaxWidth().then(if (shaded) Modifier.background(Color.Black.copy(alpha = 0.35f)) else Modifier)
            .drawBehind { drawRect(binderHairline(0.35f), size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx())) }
            .padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            doneButton()
            Box(Modifier.weight(1f)) { DeckStudioPlayDeckButton(play, model, resolver, compact = true) }
        }
    }
    /** The quick check folded into one chip: the count and what it found. A tap opens the details. */
    val quickCheckChip: @Composable () -> Unit = {
        Box(Modifier.defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) { spreadQuickCheck = !spreadQuickCheck }
            .semantics { contentDescription = "Quick check: ${preflight.summary}"; stateDescription = if (spreadQuickCheck) "Expanded" else "Collapsed" },
            contentAlignment = Alignment.Center) {
            BinderChip(if (preflight.issueCount == 0) "No issues" else "${preflight.issueCount} to check",
                icon = if (preflight.issueCount == 0) "checkmark.seal.fill" else "exclamationmark.triangle.fill", chosen = spreadQuickCheck)
        }
    }
    /**
     * The deck as Arena's list, sideways: its round commander art, name and quick check, the cards by type (count, name, cost),
     * the mana curve closing the list, and Done beside Play at its foot.
     */
    val deckColumn: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit = {
        Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 6.dp).testTag("deckStudio.deckHeader"),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(CircleShape).border(1.dp, io.magicmobile.android.menus.ArenaGlass.hairline, CircleShape)) {
                DeckStudioArtwork(DeckStudioDraftPresentation.commanders(draft).firstOrNull() ?: "", Modifier.fillMaxSize(), hero = true, colors = commanderColors,
                    art = io.magicmobile.android.CardArtSelection.Exact(DeckStudioDraftPresentation.commanderPrinting(draft)))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(draft.name.ifEmpty { "Untitled draft" }, Modifier.semantics { heading() }, color = DeckStudioPalette.ink, style = sf(16f, SfWeight.bold),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(DeckStudioDraftPresentation.commanders(draft).joinToString(" • "), color = DeckStudioPalette.secondaryInk, style = sf(11f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            quickCheckChip()
        }
        if (spreadQuickCheck) Box(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp)) { preflightBar() }
        LazyColumn(Modifier.weight(1f).fillMaxWidth().arenaScrollFade()
            .semantics { contentDescription = if (model.readOnly) "deckStudio.deckList" else "deckStudio.cards.list" },
            contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 20.dp)) {
            if (draft.rows.isEmpty()) item(key = "columnEmpty") {
                StudioContentUnavailable("A deck of possibilities", "plus.rectangle.on.rectangle", "Add your commander and cards from the left.")
            }
            for ((group, rows) in sections) {
                item(key = "column-group-$group") { deckListHeading(group, groupCount(group, rows)) }
                items(rows, key = { "column/$group/${it.id}" }) { row -> Box(Modifier.padding(vertical = 1.dp)) { deckListRow(row) } }
            }
            // The curve closes the list, so the list has the column's whole height (the judge, 2026-10-22).
            if (draft.rows.isNotEmpty()) item(key = "curve") {
                Column(Modifier.padding(top = 14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    io.magicmobile.android.menus.ArenaCaps("Mana curve", 9.5f)
                    DeckCurve(draft, metadata, Modifier.padding(horizontal = 4.dp))
                }
            }
        }
        donePlayBar(false)
    }
    /** A deck that can't be edited, sideways: every card in one flowing grid, as Arena's collection fills its side. */
    val readOnlyCards: LazyListScope.() -> Unit = {
        items(draft.rows.chunked(gridColumns), key = { "readonly/${it.first().id}" }) { chunk ->
            BinderSleeveRow(chunk, gridColumns) { row, modifier ->
                BinderSleeve(row.cardName, row.quantity, metadata?.card(row.cardName), modifier, canEdit = false,
                    tapLabel = "Inspect ${row.cardName}, quantity ${row.quantity}", art = io.magicmobile.android.CardArtSelection.Exact(row.printing),
                    add = {}, remove = {}, tap = { inspect(row.cardName, io.magicmobile.android.CardArtSelection.Exact(row.printing)) },
                    preview = { builder.previewRow = row.id })
            }
        }
    }

    // This screen's pages (the stage still knows them for a chapter swipe).
    val binderScreen = remember { Any() }
    Box(Modifier.fillMaxSize().grimoireSwipe(next = { turnChapter(1) }, previous = { turnChapter(-1) })) {
        BinderCover()
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding().padding(start = 4.dp, end = 6.dp, bottom = 2.dp)) {
            if (spread && tab == "Cards") {
                // Arena's deck builder held sideways (Caleb, 2026-10-22): the cards there are to add fill the left with their
                // search and filters, and the deck stands on the right as a list under its name, quick check and curve, with
                // Save at its head and Done beside Play at its foot. A deck that cannot be edited shows its own cards on the left.
                // Sideways the deck is always on the right, so the left is the collection; upright the page opens on the deck.
                DisposableEffect(Unit) {
                    if (!model.readOnly) shelf = BinderShelf.ALL
                    onDispose { shelf = BinderShelf.DECK }
                }
                Row(Modifier.fillMaxSize().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            Box(Modifier.padding(top = 8.dp)) { binderRail(true) }
                            LazyColumn(Modifier.weight(1f).fillMaxWidth().arenaScrollFade()
                                .semantics { contentDescription = if (model.readOnly) "deckStudio.cards.list" else "deckStudio.catalogue.list" },
                                contentPadding = PaddingValues(top = 12.dp, bottom = 22.dp)) {
                                if (model.readOnly) readOnlyCards() else shelfItems()
                            }
                        }
                    }
                    BinderPage(Modifier.width(DECK_COLUMN_WIDTH.dp).fillMaxHeight(), screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            head(false)
                            chapterStrip()
                            model.error?.let { message ->
                                DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp))
                            }
                            deckColumn()
                        }
                    }
                }
            } else if (spread) {
                // Ideas and Analysis sideways: two pages, each with its own content; nothing runs across the fold.
                //     Ideas     combos                 | EDHREC
                //     Analysis  the deck at a glance   | roles
                Row(Modifier.fillMaxSize().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), screen = binderScreen) {
                        Column(Modifier.fillMaxSize()) {
                            head(true)
                            chapterStrip()
                            model.error?.let { message ->
                                DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp))
                            }
                            androidx.compose.runtime.key(tab) {
                                LazyColumn(Modifier.weight(1f).fillMaxWidth().arenaScrollFade(), contentPadding = PaddingValues(bottom = 24.dp)) {
                                    when (tab) {
                                        "Ideas" -> comboItems(0.dp) {}
                                        else -> item(key = "glance") {
                                            Box(Modifier.padding(16.dp)) { DeckStudioAnalysisContent(draft, metadata, curveOnly = false, inspect = ::inspect) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    BinderPage(Modifier.weight(1f).fillMaxHeight(), screen = binderScreen) {
                        BoxWithConstraints(Modifier.fillMaxSize()) {
                            val pageHeight = maxHeight
                            androidx.compose.runtime.key(tab) {
                                LazyColumn(Modifier.fillMaxSize().arenaScrollFade().semantics { contentDescription = workspaceLists.getValue(tab) },
                                    contentPadding = PaddingValues(top = 10.dp, bottom = 24.dp)) {
                                    when (tab) {
                                        "Ideas" -> item(key = "edhrec") {
                                            DeckStudioEDHRECPanel(browser, DeckStudioDraftPresentation.commanders(draft), webHeight = (pageHeight - 120.dp).coerceAtLeast(220.dp))
                                        }
                                        else -> item(key = "roles") {
                                            Box(Modifier.padding(16.dp)) { DeckStudioRoleInsightsView(draft, metadata, model.record?.id, inspect = ::inspect) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Upright: one scrolling page, the tab strip under the head, and Done with Play in a bar along the foot.
                Spacer(Modifier.height(4.dp))
                BinderPage(Modifier.weight(1f).fillMaxWidth(), screen = binderScreen) {
                    Column(Modifier.fillMaxSize()) {
                        head(false)
                        chapterStrip()
                        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                            // A short page shows iOS's one-line header instead: name, card count and save state.
                            val compactHeader = maxHeight <= 500.dp
                            val chapterIndex = 1 + (if (model.error != null) 1 else 0)
                            // Ideas and Analysis fill at least the page, so the title plate can always
                            // scroll away and a chapter change always lands in the same place.
                            val content = maxHeight
                            // A chapter change lands on the chapter's own top, with the title plate scrolled away.
                            LaunchedEffect(tab) {
                                if (tab != landedTab) { landedTab = tab; listState.scrollToItem(chapterIndex) }
                            }
                            // The page fades at its foot rather than cutting a row of cards (the judge, 2026-10-22).
                            LazyColumn(Modifier.fillMaxSize().arenaScrollFade(if (model.readOnly) 36.dp else 0.dp)
                                .semantics { contentDescription = workspaceLists.getValue(tab) }, state = listState,
                                contentPadding = PaddingValues(bottom = listBottom)) {
                                item(key = "header") {
                                    if (compactHeader) CompactWorkspaceHeader(model) else Box(Modifier.padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 10.dp)) { header() }
                                }
                                model.error?.let { message -> item(key = "error") {
                                    DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 12.dp, end = 12.dp, bottom = 10.dp))
                                } }
                                when (tab) {
                                    "Cards" -> {
                                        item(key = "rail") { Box(Modifier.padding(top = 2.dp, bottom = 12.dp)) { binderRail(false) } }
                                        shelfItems()
                                    }
                                    "Ideas" -> if (ideas == "EDHREC") item(key = "edhrec") {
                                        Column(Modifier.heightIn(min = content), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                            ideasSource()
                                            // The source picker and the browser controls, then the page.
                                            DeckStudioEDHRECPanel(browser, DeckStudioDraftPresentation.commanders(draft), webHeight = (content - 150.dp).coerceAtLeast(320.dp))
                                        }
                                    } else comboItems(content, ideasSource)
                                    else -> item(key = "analysis") {
                                        Column(Modifier.heightIn(min = content).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                            DeckStudioAnalysisContent(draft, metadata, curveOnly = false, inspect = ::inspect)
                                            DeckStudioRoleInsightsView(draft, metadata, model.record?.id, inspect = ::inspect)
                                        }
                                    }
                                }
                            }
                            if (tab == "Cards" && !model.readOnly) bottomBar(Modifier.align(Alignment.BottomCenter))
                        }
                        donePlayBar(true)
                    }
                }
            }
        }
        if (showCombos) DeckStudioComboPanel(combos, comboPanel, comboInput, resolver)
        if (builder.listCopied > 0) DeckStudioListCopiedBadge(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp))
    }

    if (showSearch) BoardSheet({ showSearch = false }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioCardSearch(metadata, DeckStudioDraftPresentation.colors(draft, metadata), { name, section -> model.add(name, section) }, resolver, model) { showSearch = false }
    }
    inspection?.let { name ->
        BoardSheet({ inspection = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
            DeckStudioCardInspector(name, metadata?.card(name), art = inspectionArt) { inspection = null }
        }
    }
    if (showCommander) BoardSheet({ showCommander = false }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioReplacementPicker(metadata, commander = true, replace = { name, keepOld -> model.commander(name, keepOld) }) { showCommander = false }
    }
    artworkRow?.let { row ->
        BoardSheet({ artworkRow = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
            DeckStudioArtworkPicker(row.cardName, row.printing, choose = { model.setPrinting(row.id, it) }) { artworkRow = null }
        }
    }
    replacement?.let { row ->
        BoardSheet({ replacement = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
            DeckStudioReplacementPicker(metadata, commander = false, replace = { name, _ -> model.replace(row.id, name) },
                colors = DeckStudioDraftPresentation.colors(draft, metadata)) { replacement = null }
        }
    }
    if (builder.showCommanderFirst) BoardSheet({ builder.showCommanderFirst = false }, background = DeckStudioPalette.background, paper = true,
        skipPartiallyExpanded = true, sound = false) {
        DeckStudioCommanderFirstPicker(metadata, choose = { name ->
            model.change { DeckStudioEditorOperations.startWithCommander(it, name) }.also { if (it) builder.showCommanderFirst = false }
        }) { builder.showCommanderFirst = false }
    }
    if (builder.showTextEditor) BoardSheet({ builder.showTextEditor = false }, background = rgbLight, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioTextEditorSheet(draft, apply = { expected, next -> expected == model.draft && model.change { next } }) { builder.showTextEditor = false }
    }
    if (builder.showBulkQuantity) DeckStudioQuantityDialog(apply = { value ->
        val ids = builder.liveSelection(model.draft)
        val quantity = value.trim().toIntOrNull()?.takeIf { it in 1..2000 }
        if (quantity == null) model.error = DeckStudioPlayText.quantityError
        else if (ids.isNotEmpty()) model.change { DeckStudioEditorOperations.setQuantity(it, ids, quantity) }
    }) { builder.showBulkQuantity = false }
    if (builder.confirmBulkRemove) ConfirmationDialog(DeckStudioPlayText.removeSelectedTitle, DeckStudioPlayText.removeSelectedMessage,
        listOf(ConfirmationAction(DeckStudioPlayText.remove, destructive = true) {
        val ids = builder.liveSelection(model.draft)
        if (ids.isNotEmpty() && model.change { DeckStudioEditorOperations.removeRows(it, ids) }) builder.selection = emptySet()
    }), light = true) { builder.confirmBulkRemove = false }
    builder.preview?.let { name ->
        DeckStudioCardPreviewDialog(name, metadata?.card(name), listOf(DeckStudioCardAction(DeckStudioPlayText.cardDetails, "info.circle") { inspect(name) })) {
            builder.preview = null
        }
    }
    builder.previewRow?.let { id ->
        model.draft.rows.firstOrNull { it.id == id }?.let { row ->
            DeckStudioCardPreviewDialog(row.cardName, metadata?.card(row.cardName), cardActions(row)) { builder.previewRow = null }
        }
    }
    if (showBasics) BoardSheet({ showBasics = false }, background = rgbLight, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioBasicLandsSheet(draft, apply = { values, expected -> model.basics(values, expected) }) { showBasics = false }
    }
    if (showValidation) BoardSheet({ showValidation = false }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
        Column(Modifier.fillMaxWidth()) {
            StudioSheetBar("Validate & playtest", done = { showValidation = false })
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) { DeckStudioValidationPanel(validation, deck, resolver, play = ::preparePlay) }
        }
    }
    if (showRename) BoardSheet({ showRename = false }, background = rgbLight, paper = true, sound = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Rename deck", done = { showRename = false })
            Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 12.dp)) {
                StudioTextInput(draft.name, { model.rename(it) }, "Deck name", Modifier.fillMaxWidth())
            }
        }
    }
    if (showArtworkPreferences) BoardSheet({ showArtworkPreferences = false }, background = rgbLight, paper = true, sound = false) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            StudioSheetBar("Artwork & privacy", done = { showArtworkPreferences = false })
            Column(Modifier.padding(horizontal = 16.dp)) { NativeArtworkPreferenceRows() }
        }
    }
    if (showOrganization) model.record?.let { current ->
        BoardSheet({ showOrganization = false }, background = rgbLight, paper = true, skipPartiallyExpanded = true, sound = false) {
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

private fun deckFilterOptions(draft: NativeDeckDraft, section: String, color: String, setSection: (String) -> Unit, setColor: (String) -> Unit,
                              clearIssue: () -> Unit): List<MenuEntry> = buildList {
    add(MenuEntry.Section("Section"))
    add(MenuEntry.Item("All sections", checked = section.isEmpty()) { setSection("") })
    draft.rows.map(DeckStudioDraftPresentation::section).toSortedSet().forEach { value ->
        add(MenuEntry.Item(value.replaceFirstChar { it.uppercase() }, checked = section == value) { setSection(value) })
    }
    add(MenuEntry.Section("Card color"))
    add(MenuEntry.Item("Any color", checked = color.isEmpty()) { setColor("") })
    listOf("W" to "White", "U" to "Blue", "B" to "Black", "R" to "Red", "G" to "Green", "C" to "Colorless").forEach { (value, name) ->
        add(MenuEntry.Item(name, checked = color == value, mana = value) { setColor(value) })
    }
    add(MenuEntry.Divider)
    add(MenuEntry.Item("Clear filters") { setSection(""); setColor(""); clearIssue() })
}

/** A short screen's one-line header, as iOS shows below 500 points: name, card count and save state. */
@Composable
private fun CompactWorkspaceHeader(model: DeckStudioEditorModel) {
    val draft = model.draft
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(draft.name.ifEmpty { "Untitled draft" }, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.headline, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
        Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(draft)), color = DeckStudioPalette.ink, style = StudioText.caption)
        Text(model.saveLabel, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
    }
}

/** The deck's title plate: its name (which folds the plate away), who leads it, how full it is, Play and the quick check. */
@Composable
private fun WorkspaceHeader(model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, expanded: Boolean, toggle: () -> Unit,
                            quickCheck: @Composable () -> Unit, playButton: (@Composable () -> Unit)?) {
    val draft = model.draft
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, tween(220), label = "headerChevron")
    Column(Modifier.fillMaxWidth().binderPlate().padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { toggle() }
            .semantics(mergeDescendants = true) { contentDescription = "Deck details"; stateDescription = if (expanded) "Expanded" else "Collapsed" },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(draft.name.ifEmpty { "Untitled draft" }, Modifier.weight(1f), color = DeckStudioPalette.ink, style = sf(24f, SfWeight.bold, SfDesign.SERIF),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (!expanded) Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(draft)), color = DeckStudioPalette.ink, style = StudioText.caption)
            Box(Modifier.size(26.dp), contentAlignment = Alignment.Center) {
                SfImage("chevron.down", io.magicmobile.android.menus.ArenaMenuStyle.gold, 11.dp, Modifier.rotate(rotation))
            }
        }
        AnimatedVisibility(expanded, enter = expandVertically(tween(220)) + fadeIn(tween(220)), exit = shrinkVertically(tween(220)) + fadeOut(tween(160))) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    val frame = RoundedCornerShape(5.dp)
                    Box(Modifier.size(72.dp, 100.dp).shadow(4.dp, frame).clip(frame).border(1.dp, io.magicmobile.android.menus.ArenaGlass.hairline, frame)) {
                        DeckStudioArtwork(DeckStudioDraftPresentation.commanders(draft).firstOrNull() ?: "", Modifier.fillMaxSize(), art = io.magicmobile.android.CardArtSelection.Exact(DeckStudioDraftPresentation.commanderPrinting(draft)))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(DeckStudioDraftPresentation.commanders(draft).joinToString(" • "), color = DeckStudioPalette.secondaryInk, style = StudioText.caption, maxLines = 2)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            DeckStudioColorIdentity(DeckStudioDraftPresentation.colors(draft, metadata))
                            Text("${CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))} · Commander", color = DeckStudioPalette.ink, style = StudioText.caption)
                        }
                        // The quick check under the plate carries the count and its gauge (the judge, 2026-10-22: not twice);
                        // "Edit a copy" already says an included deck is read-only.
                        if (!model.readOnly) Text(model.saveLabel, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                        playButton?.let { Box(Modifier.padding(top = 2.dp)) { it() } }
                    }
                }
                quickCheck()
            }
        }
    }
}

/** How wide the deck column stands sideways, in dp (Arena's builder). */
private const val DECK_COLUMN_WIDTH = 330

/**
 * Arena's small mana curve under the deck list: the main deck's nonland cards by mana value, 0 to 7+ (core ArenaDeckCurve).
 * TalkBack reads it as one value.
 */
@Composable
private fun DeckCurve(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, modifier: Modifier = Modifier) {
    val bins = remember(draft, metadata) {
        ArenaDeckCurve.bins(draft.rows.filter { DeckStudioDraftPresentation.section(it) == "deck" }.mapNotNull { row ->
            val card = metadata?.card(row.cardName) ?: return@mapNotNull null
            val types = card.types ?: return@mapNotNull null
            ArenaDeckCurve.Line(row.quantity, card.manaValue, "LAND" in types)
        })
    }
    Row(modifier.fillMaxWidth().height(58.dp).clearAndSetSemantics {
        contentDescription = "Mana curve"
        stateDescription = (0 until 8).joinToString(", ") { "${if (it == 7) "7 or more" else "$it"}: ${bins[it]}" }
    }, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
        for (bin in 0 until 8) {
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("${bins[bin]}", Modifier.alpha(if (bins[bin] == 0) 0f else 1f), color = io.magicmobile.android.menus.ArenaMenuStyle.dim,
                    style = sf(8.5f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
                Box(Modifier.fillMaxWidth().height(ArenaDeckCurve.height(bins[bin], bins).dp)
                    .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(io.magicmobile.android.menus.ArenaMenuStyle.gold,
                        io.magicmobile.android.menus.ArenaMenuStyle.gold.copy(alpha = 0.45f))), RoundedCornerShape(2.dp)))
                Text(if (bin == 7) "7+" else "$bin", color = io.magicmobile.android.menus.ArenaMenuStyle.text.copy(alpha = 0.8f), style = sf(9f, SfWeight.heavy))
            }
        }
    }
}

/** The last tenth of a strip that runs on to the right fades out, so a cut pill never rests on a hard edge. */
private fun Modifier.fadeTrailing(): Modifier = graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        drawRect(androidx.compose.ui.graphics.Brush.horizontalGradient(0.9f to Color.Black, 1f to Color.Transparent),
            blendMode = androidx.compose.ui.graphics.BlendMode.DstIn)
    }

/** Under the floating Quick Add: the page's paper fading in from clear, so the cards slip under it. */
private fun Modifier.pageFade(): Modifier = drawBehind {
    drawRect(androidx.compose.ui.graphics.Brush.verticalGradient(0f to Color.Transparent, 0.35f to DeckStudioPalette.background.copy(alpha = 0.88f),
        1f to DeckStudioPalette.background))
}

/** The most sleeves the All cards shelf shows; more is a sign to narrow the search. */
private const val BINDER_CATALOGUE_LIMIT = 120

/**
 * DeckStudioBinderCatalogue.swift: the catalogue search with the coins and colour applied. The coins can pick
 * values that are not next to each other (1 and 5), so the search asks for the whole span and keeps the chosen ones.
 */
private fun binderCatalogue(metadata: NativeDeckMetadataCatalogue, query: String, type: String, color: String, mana: Set<Int>,
                            identity: List<String>?): List<CardInfo> {
    val low = mana.minOrNull()?.toDouble()
    val high = if (mana.isEmpty() || 7 in mana) null else mana.max() + 0.99
    return DeckStudioCatalogueSearch.cards(metadata, query, type, identity, minimumManaValue = low, maximumManaValue = high, limit = 2000)
        .asSequence()
        .filter { card -> BinderMana.matches(card.manaValue, mana) && (color.isEmpty() || if (color == "C") card.colors?.isEmpty() == true else card.colors?.contains(color) == true) }
        .take(BINDER_CATALOGUE_LIMIT).toList()
}

/** The All cards shelf's Filter menu: type, colour and whether to keep to the commander's colours. */
private fun catalogueFilterOptions(type: String, color: String, withinIdentity: Boolean?, setType: (String) -> Unit, setColor: (String) -> Unit,
                                   setWithin: (Boolean) -> Unit, clearCoins: () -> Unit): List<MenuEntry> = buildList {
    add(MenuEntry.Section("Card type"))
    add(MenuEntry.Item("All types", checked = type.isEmpty()) { setType("") })
    listOf("Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle").forEach { value ->
        add(MenuEntry.Item(value, checked = type == value) { setType(value) })
    }
    add(MenuEntry.Section("Card color"))
    add(MenuEntry.Item("Any color", checked = color.isEmpty()) { setColor("") })
    listOf("W" to "White", "U" to "Blue", "B" to "Black", "R" to "Red", "G" to "Green", "C" to "Colorless").forEach { (value, name) ->
        add(MenuEntry.Item(name, checked = color == value, mana = value) { setColor(value) })
    }
    if (withinIdentity != null) {
        add(MenuEntry.Divider)
        add(MenuEntry.Item(DeckStudioPlayText.withinIdentity, checked = withinIdentity) { setWithin(!withinIdentity) })
    }
    add(MenuEntry.Divider)
    add(MenuEntry.Item("Clear filters") { setType(""); setColor(""); setWithin(true); clearCoins() })
}

/**
 * One card row with inline quick-check badges. In select mode (`selected` non-null) the whole row
 * toggles the selection; otherwise a long press shows the large preview with the card actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CardRow(row: NativeDeckRow, model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, inspect: (String) -> Unit, replace: (NativeDeckRow) -> Unit,
                    issues: List<DeckStudioPreflight.Issue> = emptyList(), selected: Boolean? = null, preview: () -> Unit = {},
                    chooseArt: (NativeDeckRow) -> Unit = {}) {
    val selecting = selected != null
    Row(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).defaultMinSize(minHeight = 52.dp).combinedClickable(onLongClick = preview) { inspect(row.cardName) }
            .semantics {
                contentDescription = (if (selecting) "" else "Inspect ") + "${row.cardName}, quantity ${row.quantity}"
                if (selected != null) this.selected = selected
            },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (selected != null) SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) DeckStudioPalette.accent else DeckStudioPalette.secondaryInk, 22.dp)
            Box(Modifier.size(38.dp, 52.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(row.cardName, Modifier.fillMaxSize(), art = io.magicmobile.android.CardArtSelection.Exact(row.printing)) }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(row.cardName, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                val card = metadata?.card(row.cardName)
                when {
                    card == null -> Text("Unknown card · tap to review", color = DeckStudioPalette.warning, style = StudioText.caption2)
                    !card.manaCost.isNullOrEmpty() -> NativeDeckManaCost(card.manaCost)
                    else -> Text(card.typeLine ?: "Card", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                }
                DeckStudioIssueBadges(issues)
            }
        }
        if (!selecting) Row(verticalAlignment = Alignment.CenterVertically) {
            if (!model.readOnly) StudioIconButton("minus", "Remove one ${row.cardName}", { model.quantity(row.id, -1) }, size = 16.dp)
            Text("${row.quantity}", Modifier.widthIn(min = 20.dp), color = DeckStudioPalette.ink, style = StudioText.subheadline,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            if (!model.readOnly) {
                StudioIconButton("plus", "Add one ${row.cardName}", { model.quantity(row.id, 1) }, size = 16.dp)
                StudioMenu({
                    buildList {
                        add(MenuEntry.Item(DeckStudioPlayText.chooseArtwork, "photo.on.rectangle") { chooseArt(row) })
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
        } else Text("${row.quantity}", Modifier.widthIn(min = 20.dp).padding(end = 8.dp), color = DeckStudioPalette.ink, style = StudioText.subheadline)
    }
}
