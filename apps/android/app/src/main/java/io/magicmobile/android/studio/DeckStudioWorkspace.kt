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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
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
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import java.util.UUID

private val workspaceTabs = listOf("Cards", "Ideas", "Analysis", "Playtest")
private val workspaceLists = mapOf("Cards" to "deckStudio.cards.list", "Ideas" to "deckStudio.ideas.list",
    "Analysis" to "deckStudio.analysis.list", "Playtest" to "deckStudio.playtest.list")

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
    // One list for every tab: the header scrolls away above the pinned tabs.
    val listState = rememberLazyListState()
    var landedTab by remember { mutableStateOf(tab) }
    var tabsHeight by remember { mutableStateOf(68.dp) }
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
    val builder = remember(record?.id) { DeckStudioBuilderState() }
    // The book shows a deck as its cards' full art (Caleb, 2026-10-05); the list is one tap away.
    var cardLayout by AppPreferences.string("deckStudio.cards.layout.v1", "Grid")
    var tapHintSeen by AppPreferences.boolean("deckStudio.cards.tapHintSeen.v1", false)

    val draft = model.draft
    val deck = runCatching { draft.deck() }.getOrNull()
    val signature = if (deck != null && resolver != null) runCatching { DeckStudioDeckSignature.native(DeckStudioPlayProjection(deck).resolve(resolver)) }.getOrNull() else null
    fun inspect(name: String) { inspection = name }
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
        tab = "Cards"; query = ""; sectionFilter = ""; colorFilter = ""; showValidation = false
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
    val gridColumns = if (spread) maxOf(1, (configuration.screenWidthDp / 2 - Grimoire.foldInset.value.toInt() - 40 + 10) / 95) else deckStudioGridColumns()
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
        add(DeckStudioCardAction(DeckStudioPlayText.cardDetails, "info.circle") { inspect(row.cardName) })
        if (!model.readOnly) {
            add(DeckStudioCardAction(DeckStudioPlayText.addOne, "plus") { model.quantity(row.id, 1) })
            add(DeckStudioCardAction(DeckStudioPlayText.removeOne, "minus") { model.quantity(row.id, -1) })
            add(DeckStudioCardAction(DeckStudioPlayText.replaceCard, "arrow.triangle.2.circlepath") { replacement = row })
            add(DeckStudioCardAction(DeckStudioPlayText.moveTo, null,
                choices = DeckStudioPlayText.destinations.map { (section, title) -> title to { model.move(row.id, section) } }))
            add(DeckStudioCardAction(DeckStudioPlayText.removeRow, "trash", destructive = true) { model.remove(row.id) })
        }
    }
    val header: @Composable () -> Unit = {
        WorkspaceHeader(model, metadata, headerExpanded, { headerExpanded = !headerExpanded }) { DeckStudioPlayDeckButton(play, model, resolver) }
    }
    // A chapter change turns the page: forward for a later chapter, back for an earlier one.
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
    // The deck's chapters as ribbon markers at the head of the page.
    val tabs: @Composable () -> Unit = { GrimoireRibbons(workspaceTabs, tab) { chooseTab(it) } }
    val cardFilters: @Composable () -> Unit = {
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioSearchField(query, { query = it }, "Search this deck", radius = 12.dp, padding = 12.dp, clearLabel = "Clear deck search")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                StudioMenu({ deckFilterOptions(draft, sectionFilter, colorFilter, { sectionFilter = it }, { colorFilter = it }) { builder.listFilter = null } }) {
                    WorkspaceMenuLabel("Filter", if (sectionFilter.isEmpty() && colorFilter.isEmpty()) "line.3.horizontal.decrease" else "line.3.horizontal.decrease.circle.fill")
                }
                StudioMenu({ listOf("Type", "Role", "Section", "Mana value", "Color", "Name").map { MenuEntry.Item(it, checked = it == grouping) { grouping = it } } }) {
                    WorkspaceMenuLabel("Group", "square.grid.2x2")
                }
                StudioMenu({ listOf("Name", "Quantity", "Mana value").map { MenuEntry.Item(it, checked = it == sorting) { sorting = it } } }) {
                    WorkspaceMenuLabel("Sort", "arrow.up.arrow.down")
                }
                StudioIconButton(if (cardLayout == "Grid") "list.bullet" else "square.grid.2x2.fill", if (cardLayout == "Grid") DeckStudioPlayText.showAsList else DeckStudioPlayText.showAsGrid,
                    { cardLayout = if (cardLayout == "Grid") "List" else "Grid" }, Modifier.testTag("deckStudio.cards.layout"), size = 16.dp)
                if (!model.readOnly) StudioPlainButton(if (builder.selecting) "Done" else DeckStudioPlayText.select, builder::toggleSelecting,
                    Modifier.testTag("deckStudio.cards.select").semantics { contentDescription = if (builder.selecting) DeckStudioPlayText.doneSelecting else DeckStudioPlayText.selectCards },
                    style = StudioText.caption)
                StudioIconButton("arrow.uturn.backward", "Undo deck edit", { model.undo() }, enabled = model.history.canUndo && !model.readOnly, size = 16.dp)
                StudioIconButton("arrow.uturn.forward", "Redo deck edit", { model.redo() }, enabled = model.history.canRedo && !model.readOnly, size = 16.dp)
            }
            builder.listFilter?.let { DeckStudioIssueFilterRow(it) { builder.listFilter = null } }
        }
    }
    val preflightBar: @Composable () -> Unit = {
        DeckStudioPreflightBar(preflight, (builder.listFilter as? DeckStudioListFilter.QuickCheck)?.issue, ::setIssueFilter, ::chooseCommander)
    }
    val ideasSource: @Composable () -> Unit = {
        StudioSegmented(listOf("Combos", "EDHREC"), ideas, { ideas = it }, { it }, Modifier.padding(start = 20.dp, end = 20.dp, top = 4.dp))
    }
    // The combo panel's lookup, approval and details live outside the list, only while it is shown.
    val showCombos = tab == "Ideas" && ideas == "Combos"
    val comboPanel = remember(showCombos) { DeckStudioComboPanelState() }
    val comboInput = if (showCombos) remember(draft, resolver) { DeckStudioSpellbookInput.make(draft, resolver) } else null
    val density = LocalDensity.current
    val navigationBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

    StudioScreen(Modifier.grimoireSwipe(next = { turnChapter(1) }, previous = { turnChapter(-1) })) {
        Column(Modifier.fillMaxSize()) {
            // On a spread the middle of the bar is the fold: no title is drawn there.
            StudioNavBar(if (spread) "" else "Deck Studio", leading = {
                StudioGlassGroup { StudioGlassText("Done", { requestClose() }, label = "deckStudio.close") }
            }, trailing = {
                StudioGlassGroup {
                    if (model.readOnly) StudioGlassText("Edit a copy", { model.makeEditableCopy() })
                    else StudioGlassText("Save", { model.save() }, enabled = model.canSave, bold = true, label = "deckStudio.save")
                    StudioGlassIcon("tag", "Deck tags, notes and import receipt", { showOrganization = true }, enabled = model.record != null)
                    StudioMenu({
                        buildList {
                            // The same Play as the header, which compact layouts scroll away.
                            add(MenuEntry.Item(playAction.title, if (playAction.playing) "checkmark.circle" else "play.fill", enabled = playAction.enabled) {
                                play.play(model.playSource(), resolver, model.draft.name)
                            })
                            add(MenuEntry.Item("Validate & playtest", "checkmark.shield") { showValidation = true })
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
                    }) { Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis.circle", DeckStudioPalette.ink, 20.dp) } }
                }
            })
            // Every tab shares one scroll: the header leaves the screen while the tabs stay pinned.
            BoxWithConstraints(Modifier.weight(1f)) {
                // A short screen shows iOS's one-line header instead: name, card count and save state.
                val compactHeader = maxHeight <= 500.dp
                val tabsIndex = 1 + (if (headerExpanded && !compactHeader) 1 else 0) + (if (model.error != null) 1 else 0)
                // Ideas and Analysis fill at least the screen below the tabs, so the header can always
                // scroll away and a tab change always lands in the same place.
                val content = (maxHeight - tabsHeight).coerceAtLeast(0.dp)
                // A tab change lands on the pinned tabs, so the new tab starts at its top.
                LaunchedEffect(tab) {
                    if (tab != landedTab) { landedTab = tab; if (!spread) listState.scrollToItem(tabsIndex) }
                }
                // The parts of the workspace, shared by the single page (upright) and the two pages of a spread.
                val titleItems: LazyListScope.(Boolean) -> Unit = { compact ->
                    item(key = "header") {
                        if (compact) CompactWorkspaceHeader(model) else Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) { header() }
                    }
                    if (headerExpanded && !compact) item(key = "quickCheck") { Box(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp)) { preflightBar() } }
                    model.error?.let { message -> item(key = "error") {
                        DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp))
                    } }
                }
                val cardItems: LazyListScope.() -> Unit = {
                    item(key = "filters") { cardFilters() }
                    // Until the first tap on a card changes its count, the page says what a tap does.
                    if (cardLayout == "Grid" && !model.readOnly && !tapHintSeen && filteredRows.isNotEmpty()) item(key = "tapHint") {
                        Text("Tap a card's right side to add a copy, its left side to take one away. Hold a card to see it large.",
                            Modifier.padding(horizontal = 20.dp).padding(bottom = 4.dp).testTag("deckStudio.cards.tapHint"),
                            color = DeckStudioPalette.secondaryInk, style = StudioText.footnote.copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic))
                    }
                    if (draft.rows.isEmpty()) item(key = "empty") {
                        StudioContentUnavailable("A deck of possibilities", "plus.rectangle.on.rectangle", "Add your commander and cards. Incomplete drafts are welcome.")
                    } else if (filteredRows.isEmpty()) item(key = "nomatch") {
                        Column(Modifier.padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            StudioContentUnavailable("No matching cards", "line.3.horizontal.decrease", "Clear the search or filters to see the full draft.")
                            StudioButton("Clear search and filters", { query = ""; sectionFilter = ""; colorFilter = ""; builder.listFilter = null }, primary = false)
                        }
                    }
                    for ((group, rows) in sections) {
                        item(key = "group-$group") {
                            GrimoireSubheading(group, groupCount(group, rows), Modifier.padding(horizontal = 20.dp).padding(top = 8.dp).padding(vertical = 10.dp))
                        }
                        fun tap(row: NativeDeckRow) { if (builder.selecting) builder.toggle(row.id) else inspect(row.cardName) }
                        // Long-press: the large preview with the row's actions, as the iOS context menu; not while selecting.
                        fun longPress(row: NativeDeckRow) { if (!builder.selecting) builder.previewRow = row.id }
                        if (cardLayout == "Grid") items(rows.chunked(gridColumns), key = { "$group/grid/${it.first().id}" }) { chunk ->
                            DeckStudioCardGridRow(chunk, gridColumns) { row, modifier ->
                                DeckStudioCardGridTile(row, metadata?.card(row.cardName), preflight.issues(row.id), if (builder.selecting) row.id in builder.selection else null,
                                    tap = { tap(row) }, preview = { longPress(row) }, modifier = modifier,
                                    change = if (model.readOnly) null else { delta -> GameAudio.play(GameSound.UI_TICK); model.quantity(row.id, delta); tapHintSeen = true })
                            }
                        } else items(rows, key = { "$group/${it.id}" }) { row ->
                            Box(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                                CardRow(row, model, metadata, inspect = { tap(row) }, replace = { replacement = it }, issues = preflight.issues(row.id),
                                    selected = if (builder.selecting) row.id in builder.selection else null, preview = { longPress(row) })
                            }
                        }
                    }
                }
                val comboItems: LazyListScope.(Dp, @Composable () -> Unit) -> Unit = { minHeight, top ->
                    deckStudioComboItems(combos, comboPanel, comboInput, draft, metadata, resolver, model.readOnly, add = { name, section, approved ->
                        approved == DeckStudioSpellbookInput.make(model.draft, resolver) && resolver?.canonicalCardName(name) == name && model.add(name, section)
                    }, inspect = ::inspect, minHeight = minHeight, top = top)
                }
                val bottomBar: @Composable (Modifier) -> Unit = { modifier ->
                    // Quick Add with Add cards, or the bulk actions while selecting.
                    Box(modifier.fillMaxWidth().grimoirePaper().navigationBarsPadding().imePadding()
                        .padding(top = 8.dp, start = 20.dp, end = 20.dp, bottom = 12.dp)) {
                        if (builder.selecting) DeckStudioBulkBar(builder.liveSelection(draft).size, move = { section ->
                            val ids = builder.liveSelection(model.draft)
                            if (ids.isNotEmpty()) model.change { DeckStudioEditorOperations.moveRows(it, ids, section) }
                        }, setQuantity = { builder.showBulkQuantity = true }, remove = { builder.confirmBulkRemove = true },
                            selectAll = { builder.selection = filteredRows.map { it.id }.toSet() })
                        else DeckStudioQuickAddBar(metadata, model, openSearch = { showSearch = true })
                    }
                }
                val listBottom = if (tab != "Cards" || model.readOnly) 24.dp + navigationBottom else if (builder.selecting) 136.dp else 88.dp
                if (spread) {
                    // Each page has its own content and scrolls by itself; nothing runs across the fold
                    // (DeckStudioWorkspaceScreen.swift, spreadWorkspace).
                    //     Cards     the deck's title page                | the deck's cards
                    //     Ideas     combos                               | EDHREC
                    //     Analysis  the deck at a glance                 | roles
                    //     Playtest  the rules check and a sample hand    | game history
                    val pageHeight = maxHeight
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.weight(1f).padding(end = Grimoire.foldInset)) {
                            Box(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 6.dp)) { tabs() }
                            androidx.compose.runtime.key(tab) {
                                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp + navigationBottom)) {
                                    when (tab) {
                                        "Cards" -> {
                                            item(key = "title") {
                                                Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                                    WorkspaceHeader(model, metadata, true, {}) { DeckStudioPlayDeckButton(play, model, resolver) }
                                                    preflightBar()
                                                }
                                            }
                                            model.error?.let { message -> item(key = "error") {
                                                DeckStudioNotice("Check this draft", message, "exclamationmark.triangle", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp))
                                            } }
                                        }
                                        "Ideas" -> comboItems(0.dp) {}
                                        "Analysis" -> item(key = "glance") {
                                            Box(Modifier.padding(20.dp)) { DeckStudioAnalysisContent(draft, metadata, curveOnly = false, inspect = ::inspect) }
                                        }
                                        else -> {
                                            item(key = "validation") {
                                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp)) { DeckStudioValidationPanel(validation, deck, resolver, play = ::preparePlay) }
                                            }
                                            item(key = "sampleHand") {
                                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
                                                    DeckStudioSampleHandPanel(draft, metadata, inspect = ::inspect, preview = { builder.preview = it })
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Box(Modifier.weight(1f).padding(start = Grimoire.foldInset)) {
                            androidx.compose.runtime.key(tab) {
                                LazyColumn(Modifier.fillMaxSize().semantics { contentDescription = workspaceLists.getValue(tab) }, contentPadding = PaddingValues(bottom = listBottom)) {
                                    when (tab) {
                                        "Cards" -> cardItems()
                                        "Ideas" -> item(key = "edhrec") {
                                            DeckStudioEDHRECPanel(browser, DeckStudioDraftPresentation.commanders(draft), webHeight = (pageHeight - 120.dp).coerceAtLeast(220.dp))
                                        }
                                        "Analysis" -> item(key = "roles") {
                                            Box(Modifier.padding(20.dp)) { DeckStudioRoleInsightsView(draft, metadata, model.record?.id, inspect = ::inspect) }
                                        }
                                        else -> item(key = "history") {
                                            Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp)) {
                                                DeckStudioPlaytestInsightsView(signature, metadata) { game, _ -> historyReview = game to (signature == game.deck) }
                                            }
                                        }
                                    }
                                }
                            }
                            if (tab == "Cards" && !model.readOnly) bottomBar(Modifier.align(Alignment.BottomCenter))
                        }
                    }
                } else LazyColumn(Modifier.fillMaxSize().semantics { contentDescription = workspaceLists.getValue(tab) }, state = listState,
                    contentPadding = PaddingValues(bottom = listBottom)) {
                    titleItems(compactHeader)
                    stickyHeader(key = "tabs") {
                        Box(Modifier.fillMaxWidth().onSizeChanged { tabsHeight = with(density) { it.height.toDp() } }.grimoirePaper()
                            .padding(horizontal = 20.dp, vertical = 8.dp)) { tabs() }
                    }
                    when (tab) {
                        "Cards" -> cardItems()
                        "Ideas" -> if (ideas == "EDHREC") item(key = "edhrec") {
                            Column(Modifier.heightIn(min = content), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                ideasSource()
                                // Below the tabs: the source picker and the browser controls, then the page.
                                DeckStudioEDHRECPanel(browser, DeckStudioDraftPresentation.commanders(draft), webHeight = (content - 150.dp).coerceAtLeast(320.dp))
                            }
                        } else comboItems(content, ideasSource)
                        "Analysis" -> item(key = "analysis") {
                            Column(Modifier.heightIn(min = content).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                DeckStudioAnalysisContent(draft, metadata, curveOnly = false, inspect = ::inspect)
                                DeckStudioRoleInsightsView(draft, metadata, model.record?.id, inspect = ::inspect)
                            }
                        }
                        else -> {
                            item(key = "validation") {
                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp)) { DeckStudioValidationPanel(validation, deck, resolver, play = ::preparePlay) }
                            }
                            item(key = "history") {
                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
                                    DeckStudioPlaytestInsightsView(signature, metadata) { game, _ -> historyReview = game to (signature == game.deck) }
                                }
                            }
                            item(key = "sampleHand") {
                                Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
                                    DeckStudioSampleHandPanel(draft, metadata, inspect = ::inspect, preview = { builder.preview = it })
                                }
                            }
                        }
                    }
                }
                if (showCombos) DeckStudioComboPanel(combos, comboPanel, comboInput, resolver)
                if (!spread && tab == "Cards" && !model.readOnly) bottomBar(Modifier.align(Alignment.BottomCenter))
            }
        }
        if (builder.listCopied > 0) DeckStudioListCopiedBadge(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp))
        StudioCover(historyReview != null) {
            historyReview?.let { (game, exact) -> MatchHistoryDashboard(game, exact, metadata) { historyReview = null } }
        }
    }

    if (showSearch) BoardSheet({ showSearch = false }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioCardSearch(metadata, DeckStudioDraftPresentation.colors(draft, metadata), { name, section -> model.add(name, section) }, resolver, model) { showSearch = false }
    }
    inspection?.let { name ->
        BoardSheet({ inspection = null }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
            DeckStudioCardInspector(name, metadata?.card(name)) { inspection = null }
        }
    }
    if (showCommander) BoardSheet({ showCommander = false }, background = DeckStudioPalette.background, paper = true, skipPartiallyExpanded = true, sound = false) {
        DeckStudioReplacementPicker(metadata, commander = true, replace = { name, keepOld -> model.commander(name, keepOld) }) { showCommander = false }
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
    listOf("W", "U", "B", "R", "G", "C").forEach { value -> add(MenuEntry.Item(if (value == "C") "Colorless" else value, checked = color == value) { setColor(value) }) }
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

@Composable
private fun WorkspaceHeader(model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, expanded: Boolean, toggle: () -> Unit,
                            playButton: @Composable () -> Unit) {
    val draft = model.draft
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, tween(220), label = "headerChevron")
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { toggle() }.semantics { contentDescription = "Deck details" },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(draft.name.ifEmpty { "Untitled draft" }, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.headline, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(draft)), color = DeckStudioPalette.ink, style = StudioText.caption)
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
                        Text("${CardCountText.label(DeckStudioDraftPresentation.gameCount(draft))} · Commander", color = DeckStudioPalette.ink, style = StudioText.caption)
                    }
                    Text(model.saveLabel, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                    Box(Modifier.padding(top = 4.dp)) { playButton() }
                }
            }
        }
    }
}

/**
 * One card row with inline quick-check badges. In select mode (`selected` non-null) the whole row
 * toggles the selection; otherwise a long press shows the large preview with the card actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CardRow(row: NativeDeckRow, model: DeckStudioEditorModel, metadata: NativeDeckMetadataCatalogue?, inspect: (String) -> Unit, replace: (NativeDeckRow) -> Unit,
                    issues: List<DeckStudioPreflight.Issue> = emptyList(), selected: Boolean? = null, preview: () -> Unit = {}) {
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
            Box(Modifier.size(38.dp, 52.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(row.cardName, Modifier.fillMaxSize()) }
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
