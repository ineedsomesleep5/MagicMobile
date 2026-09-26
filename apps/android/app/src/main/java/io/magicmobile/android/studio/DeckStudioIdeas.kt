package io.magicmobile.android.studio

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.GameRulesText
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

fun openExternal(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/**
 * DeckStudioComboModel.swift: owned by the workspace so tab switches keep results. The network is
 * never started by opening the tab, a draft change or a cache read.
 */
class DeckStudioComboModel(private val scope: CoroutineScope, private val client: CommanderSpellbookClient = DeckStudioServices.spellbook) {
    var input by mutableStateOf<SpellbookDeck?>(null); private set
    var snapshot by mutableStateOf<SpellbookSnapshot?>(null); private set
    var loading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var cacheNote by mutableStateOf<String?>(null); private set
    private var token = UUID.randomUUID()
    private var job: Job? = null

    suspend fun setInput(deck: SpellbookDeck?) {
        if (input == deck) return
        cancel(); input = deck; snapshot = null; error = null; cacheNote = null
        val captured = token
        if (deck != null) {
            val stored = withContext(Dispatchers.IO) { runCatching { client.cached(deck) }.getOrNull() }
            if (stored != null && token == captured && input == deck) {
                snapshot = stored; cacheNote = "Previously saved lookup for this exact deck. The provider may have newer data."
            }
        }
    }

    fun analyze(approved: SpellbookDeck, more: Boolean = false) {
        if (input != approved || loading) return
        val previous = if (more) snapshot else null
        if (more && (previous?.deck != approved || previous.nextOffset == null)) return
        val captured = UUID.randomUUID(); token = captured
        loading = true; error = null
        job = scope.launch {
            try {
                val result = client.lookup(approved, previous)
                if (token != captured || input != approved) return@launch
                snapshot = result.snapshot; loading = false
                cacheNote = if (result.savedToDisk) "Saved on this device for offline review. Android may clear cached results." else "Available in this session; the disk cache could not be saved."
                job = null
            } catch (cancelled: CancellationException) {
                if (token == captured) { loading = false; job = null }
            } catch (failure: Exception) {
                if (token != captured || input != approved) return@launch
                error = (failure as? SpellbookError)?.message ?: SpellbookError.Unavailable.message
                loading = false; job = null
            }
        }
    }

    fun cancel() { token = UUID.randomUUID(); job?.cancel(); job = null; loading = false }

    fun clear() {
        cancel(); snapshot = null; cacheNote = null; error = null
        try { client.clearCache() } catch (failure: Exception) { error = "The local combo cache could not be fully removed. Your deck is unchanged." }
    }
}

/** DeckStudioComboPanel: documented interactions from Commander Spellbook, sent only after approval. */
@Composable
fun DeckStudioComboPanel(model: DeckStudioComboModel, draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?,
                         readOnly: Boolean, add: (String, String, SpellbookDeck) -> Boolean, inspect: (String) -> Unit) {
    val context = LocalContext.current
    val input = remember(draft, resolver) { DeckStudioSpellbookInput.make(draft, resolver) }
    val snapshot = model.snapshot?.takeIf { it.deck == input }
    var approval by remember { mutableStateOf<SpellbookDeck?>(null) }
    var selected by remember { mutableStateOf<SpellbookVariant?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(input) { feedback = null; model.setInput(input) }
    DisposableEffect(Unit) { onDispose { model.cancel() } }
    fun addCard(name: String, section: String, current: SpellbookSnapshot) {
        feedback = if (current.deck != input || !add(name, section, current.deck)) "The deck changed or the edit could not be saved. No automatic replacement was made."
        else "Added $name to ${if (section == "deck") "main deck" else "maybeboard"}. Undo is available in Cards."
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        StudioPanel {
            Text("Find your combos", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
            Text("Documented interactions from Commander Spellbook.", color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
            Text("Lookup shares your main-deck and commander names, quantities, and IP address with Commander Spellbook.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            StudioButton(if (snapshot == null) "Find combos" else "Refresh this deck’s combos", { approval = input },
                Modifier.semantics { contentDescription = "deckStudio.combos.lookup" }, icon = "sparkles", enabled = input != null && !model.loading)
            if (input == null) Text("Choose commander(s) and resolve main-deck card names before looking up combos. You can still edit and save your draft.",
                color = DeckStudioPalette.warning, style = StudioText.caption)
            StudioDisclosure("About these results", titleStyle = StudioText.caption) {
                Text("Other sections, deck title and private notes stay on this device. These are documented combos, not EDHREC recommendations or proof they will execute in your game.",
                    color = DeckStudioPalette.ink, style = StudioText.caption)
                StudioPlainButton("Commander Spellbook", { openExternal(context, "https://commanderspellbook.com/about/") }, style = StudioText.caption)
            }
        }
        if (model.loading) Row(verticalAlignment = Alignment.CenterVertically) {
            StudioProgress("Looking up combos…", Modifier.weight(1f)); StudioPlainButton("Cancel", { model.cancel() })
        }
        model.error?.let { DeckStudioNotice("Lookup unavailable", it, "wifi.exclamationmark") }
        feedback?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption) }
        if (snapshot != null) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${snapshot.loadedCount} results loaded", color = DeckStudioPalette.ink, style = StudioText.headline)
                Text("Commander Spellbook · ${formatDateTime(snapshot.fetchedAt)}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                model.cacheNote?.let { Text(it, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2) }
                if (snapshot.nextOffset != null) Text("More results exist. Counts below cover only the pages you have loaded.", color = DeckStudioPalette.ink, style = StudioText.caption)
            }
            ComboGroup(SpellbookGroup.INCLUDED, snapshot, draft, metadata, resolver, readOnly, inspect, { selected = it }) { name, section -> addCard(name, section, snapshot) }
            ComboGroup(SpellbookGroup.ALMOST_INCLUDED, snapshot, draft, metadata, resolver, readOnly, inspect, { selected = it }) { name, section -> addCard(name, section, snapshot) }
            if (SpellbookGroup.entries.filter { it.isOther }.any { snapshot.groups[it]?.isNotEmpty() == true }) {
                StudioDisclosure("Other possibilities — require deck changes") {
                    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        for (group in SpellbookGroup.entries.filter { it.isOther }) {
                            ComboGroup(group, snapshot, draft, metadata, resolver, readOnly, inspect, { selected = it }) { name, section -> addCard(name, section, snapshot) }
                        }
                    }
                }
            }
            if (snapshot.loadedCount == 0) DeckStudioNotice("No documented matches returned",
                "This does not prove the deck has no combos. New or undocumented interactions may not be in this database.")
            if (snapshot.nextOffset != null && snapshot.loadedCount < SpellbookAPI.maximumResults) {
                StudioButton("Load next page", { model.analyze(snapshot.deck, more = true) }, primary = false, enabled = !model.loading)
            } else if (snapshot.nextOffset != null) Text("Local result limit reached. Continue on Commander Spellbook’s website.", color = DeckStudioPalette.ink, style = StudioText.caption)
            StudioPlainButton("Clear saved combo lookups", { model.clear() }, destructive = true)
            Text("XMage remains the rules authority. Named pieces, color identity and provider legality alone do not establish mana, timing, zones or a winning line.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
        }
    }
    approval?.let { deck ->
        ConfirmationDialog("Send this deck to Commander Spellbook?", "This is an optional online lookup of the current main deck and commanders. It never changes your deck automatically.",
            listOf(ConfirmationAction("Send deck and find combos") {
                approval = null
                if (deck != input) feedback = "The deck changed. Review it before a new lookup." else model.analyze(deck)
            }), light = true) { approval = null }
    }
    selected?.let { variant ->
        BoardSheet({ selected = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            DeckStudioComboDetail(variant, { resolver?.canonicalCardName(it) ?: it }) { selected = null }
        }
    }
}

@Composable
private fun ComboGroup(group: SpellbookGroup, snapshot: SpellbookSnapshot, draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, resolver: OnDeviceDeckResolver?,
                       readOnly: Boolean, inspect: (String) -> Unit, details: (SpellbookVariant) -> Unit, addCard: (String, String) -> Unit) {
    val variants = snapshot.groups[group] ?: emptyList()
    if (variants.isEmpty()) return
    Text("${group.title} · ${variants.size}", color = DeckStudioPalette.ink, style = StudioText.headline)
    for (variant in variants) {
        val assessment = SpellbookAssessment.make(variant, group, snapshot.deck, DeckStudioDraftPresentation.colors(draft, metadata)) { resolver?.canonicalCardName(it) }
        StudioPanel {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (ingredient in variant.uses) {
                    val canonical = resolver?.canonicalCardName(ingredient.cardName) ?: ingredient.cardName
                    Column(Modifier.width(100.dp).clickable { inspect(canonical) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.size(100.dp, 140.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(canonical, Modifier.fillMaxSize()) }
                        Text(ingredient.cardName, color = DeckStudioPalette.ink, style = StudioText.caption)
                        Text("×${ingredient.quantity}", color = DeckStudioPalette.ink, style = StudioText.caption)
                    }
                }
            }
            for (effect in variant.produces) GameRulesText(effect.featureName, style = StudioText.subheadline.weight(SfWeight.semibold), color = DeckStudioPalette.ink)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                val (icon, title) = when (assessment.readiness) {
                    SpellbookAssessment.Readiness.NamedPiecesPresent -> "checkmark.circle" to "Named pieces present"
                    is SpellbookAssessment.Readiness.OneCardAway -> "plus.circle" to "One named card away"
                    SpellbookAssessment.Readiness.ReviewRequirements -> "info.circle" to "Requirements need review"
                }
                SfImage(icon, DeckStudioPalette.ink, 13.dp)
                Text(title, color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
            }
            StudioDisclosure("Deck requirements", titleStyle = StudioText.caption) {
                Text(assessment.explanation, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
            StudioPlainButton("Prerequisites and steps", { details(variant) }, icon = "list.bullet.rectangle")
            val readiness = assessment.readiness
            if (readiness is SpellbookAssessment.Readiness.OneCardAway && !readOnly) {
                StudioMenu({ listOf(MenuEntry.Item("Add to main deck") { addCard(readiness.name, "deck") }, MenuEntry.Item("Save to maybeboard") { addCard(readiness.name, "maybeboard") }) }) {
                    Row(Modifier.defaultMinSize(minHeight = 44.dp).semantics { contentDescription = "deckStudio.combos.addMissing" },
                        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("plus.circle", DeckStudioPalette.ink, 18.dp)
                        Text("Add ${readiness.name}", color = DeckStudioPalette.ink, style = StudioText.body)
                    }
                }
            }
        }
    }
}

@Composable
private fun DeckStudioComboDetail(variant: SpellbookVariant, canonicalName: (String) -> String, dismiss: () -> Unit) {
    val context = LocalContext.current
    fun zones(values: List<String>): String {
        val names = mapOf("B" to "Battlefield", "H" to "Hand", "G" to "Graveyard", "E" to "Exile", "L" to "Library", "C" to "Command zone")
        return values.joinToString(", ") { names[it] ?: it }
    }
    @Composable fun section(title: String, value: String) {
        if (value.isEmpty()) return
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, color = DeckStudioPalette.ink, style = StudioText.headline)
            GameRulesText(value, style = StudioText.subheadline, color = DeckStudioPalette.ink)
        }
    }
    Column(Modifier.fillMaxWidth().height(largeSheetHeight())) {
        StudioSheetBar("Combo details", done = dismiss)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 24.dp, end = 24.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text("Commander Spellbook", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            Row(Modifier.horizontalScroll(rememberScrollState()).semantics { contentDescription = "deckStudio.combo.cards" }, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (row in variant.uses) Column(Modifier.width(116.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(116.dp, 162.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(canonicalName(row.cardName), Modifier.fillMaxSize()) }
                    Text(row.cardName, color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
                }
            }
            Text("Before you begin", color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
            section("Mana", variant.manaNeeded)
            for (row in variant.uses) section("${row.quantity} × ${row.cardName}", listOf(zones(row.zoneLocations), if (row.mustBeCommander) "Must be your commander" else "",
                row.battlefieldCardState, row.exileCardState, row.graveyardCardState, row.libraryCardState).filter { it.isNotEmpty() }.joinToString("\n"))
            for (row in variant.requires) section("Flexible requirement: ${row.quantity} × ${row.templateName}", listOf(zones(row.zoneLocations),
                if (row.mustBeCommander) "Must be your commander" else "", row.battlefieldCardState, row.exileCardState, row.graveyardCardState, row.libraryCardState)
                .filter { it.isNotEmpty() }.joinToString("\n"))
            section("Prerequisites", variant.easyPrerequisites)
            section("Additional prerequisites", variant.notablePrerequisites)
            if (variant.description.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Steps", Modifier.semantics { contentDescription = "deckStudio.combo.steps" }, color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
                variant.description.split("\n").filter { it.isNotEmpty() }.forEachIndexed { index, step ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(26.dp).background(DeckStudioPalette.background, CircleShape), contentAlignment = Alignment.Center) {
                            Text("${index + 1}", color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.bold))
                        }
                        GameRulesText(step.replace(Regex("""^\s*\d+[.)]\s+"""), ""), Modifier.weight(1f), style = StudioText.subheadline, color = DeckStudioPalette.ink)
                    }
                }
            }
            section("Results", variant.produces.joinToString("\n") { it.featureName })
            if (variant.notes.isNotEmpty()) StudioDisclosure("Notes") { GameRulesText(variant.notes, style = StudioText.subheadline, color = DeckStudioPalette.ink) }
            Text("Provider Commander legality: ${variant.commanderLegal?.let { if (it) "legal" else "not legal" } ?: "unknown"}. This is not validation of your complete deck or execution in XMage.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            variant.websiteURL?.let { url -> StudioPlainButton("Read on Commander Spellbook", { openExternal(context, url) }) }
        }
    }
}

/**
 * DeckStudioEDHRECModel: one temporary browser per workspace. The site runs its own scripts; the
 * app injects none and never reads recommendations or submits the deck.
 */
class DeckStudioEDHRECModel(private val scope: CoroutineScope) {
    var webView by mutableStateOf<WebView?>(null); private set
    var loading by mutableStateOf(false); private set
    var resolving by mutableStateOf(false); private set
    var canBack by mutableStateOf(false); private set
    var canForward by mutableStateOf(false); private set
    var currentURL by mutableStateOf<String?>(null); private set
    var error by mutableStateOf<String?>(null)
    var externalURL by mutableStateOf<String?>(null)
    private var navigationToken = UUID.randomUUID()
    private var resolution: Job? = null
    private var timeout: Job? = null

    private fun cancelResolution() { resolution?.cancel(); resolution = null; resolving = false }

    @SuppressLint("SetJavaScriptEnabled")
    fun open(context: Context, url: String) {
        if (!DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url)) return
        cancelResolution()
        val view = webView ?: WebView(context).also { view ->
            view.settings.javaScriptEnabled = true
            view.settings.javaScriptCanOpenWindowsAutomatically = false
            view.settings.setSupportMultipleWindows(false)
            view.settings.mediaPlaybackRequiresUserGesture = true
            view.settings.allowFileAccess = false
            view.settings.allowContentAccess = false
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val target = request.url.toString()
                    if (!request.isForMainFrame) return false
                    if (DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(target)) return false
                    if (request.hasGesture() && DeckStudioEDHRECPolicy.allowsExternalBrowser(target)) externalURL = target
                    else error = "This navigation needs the full browser. Use Open in browser."
                    return true
                }
                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    loading = true; error = null; navigationToken = UUID.randomUUID(); val token = navigationToken
                    timeout?.cancel()
                    timeout = scope.launch {
                        delay(30_000)
                        if (loading && navigationToken == token) { pause(); error = "The page took too long to load. Retry or open it in your browser." }
                    }
                    update(view)
                }
                override fun onPageFinished(view: WebView, url: String?) { timeout?.cancel(); loading = false; update(view) }
                override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) { update(view) }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                    if (!request.isForMainFrame) return
                    timeout?.cancel(); loading = false; update(view)
                    error = "EDHREC could not load. Check your connection or open the page in your browser."
                }
            }
            webView = view
        }
        error = null
        view.loadUrl(url)
    }

    /** Only a deliberate tap asks Scryfall for the commander's public EDHREC link. */
    fun openCommander(context: Context, name: String) {
        cancelResolution()
        resolving = true; error = null
        resolution = scope.launch {
            try {
                val record = DeckStudioServices.scryfall.named(name, allowNetwork = true)
                val url = record?.card?.takeIf { card -> card.name == name || card.faces?.any { it.name == name } == true }?.edhrecURL
                    ?.takeIf(DeckStudioEDHRECPolicy::allowsEmbeddedNavigation) ?: throw DeckStudioScryfallError.InvalidResponse
                resolving = false; resolution = null; open(context, url)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) {
                resolving = false; resolution = null
                error = "Could not resolve this commander's EDHREC link. Browse EDHREC or copy the name instead. ${failure.message ?: ""}".trim()
            }
        }
    }

    private fun update(view: WebView) { currentURL = view.url; canBack = view.canGoBack(); canForward = view.canGoForward() }
    fun back() { cancelResolution(); if (canBack) webView?.goBack() }
    fun forward() { cancelResolution(); if (canForward) webView?.goForward() }
    fun reload() { cancelResolution(); error = null; webView?.reload() }
    fun pause() { cancelResolution(); timeout?.cancel(); webView?.stopLoading(); webView?.onPause(); loading = false }
    fun resume() { webView?.onResume() }

    /** Clears the temporary session: page, history and the site's cookies. */
    fun clear() {
        pause(); navigationToken = UUID.randomUUID()
        webView?.let { it.stopLoading(); it.clearHistory(); it.destroy() }
        runCatching { CookieManager.getInstance().removeAllCookies(null) }
        webView = null; currentURL = null; canBack = false; canForward = false; error = null; externalURL = null
    }
}

@Composable
fun DeckStudioEDHRECPanel(model: DeckStudioEDHRECModel, commanders: List<String>) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    val names = commanders.toSortedSet().toList()
    LaunchedEffect(commanders) { copied = false; model.pause() }
    DisposableEffect(Unit) { model.resume(); onDispose { model.pause() } }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("EDHREC — web", Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            StudioMenu({ names.map { name -> MenuEntry.Item(name) { model.openCommander(context, name) } } +
                MenuEntry.Item("Browse on EDHREC") { model.open(context, DeckStudioEDHRECPolicy.browseURL) } }) {
                Box(Modifier.defaultMinSize(minHeight = 44.dp), contentAlignment = Alignment.Center) { Text("Commanders", color = DeckStudioPalette.ink, style = StudioText.body) }
            }
            StudioIconButton("trash", "Clear temporary browser session", { model.clear() })
        }
        if (model.resolving) Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            StudioProgress("Resolving public link via Scryfall…", Modifier.weight(1f)); StudioPlainButton("Cancel", { model.pause() })
        }
        model.error?.let { Text(it, Modifier.padding(horizontal = 20.dp), color = DeckStudioPalette.ink, style = StudioText.caption) }
        val view = model.webView
        if (view != null) {
            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                StudioIconButton("chevron.left", "Previous web page", { model.back() }, enabled = model.canBack)
                StudioIconButton("chevron.right", "Next web page", { model.forward() }, enabled = model.canForward)
                StudioIconButton("arrow.clockwise", "Reload EDHREC", { model.reload() })
                Spacer(Modifier.weight(1f))
                StudioPlainButton("Browser", { openExternal(context, model.currentURL ?: DeckStudioEDHRECPolicy.browseURL) }, icon = "arrow.up.right.square")
            }
            if (model.loading) StudioProgress("Loading EDHREC…")
            AndroidView({ view.also { (it.parent as? android.view.ViewGroup)?.removeView(it) } }, Modifier.fillMaxWidth().weight(1f))
        } else {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Explore another perspective.", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
                Text("Browse the actual EDHREC website, then return to Cards without losing your draft. MagicMobile does not read recommendations, fill forms, or submit your deck.",
                    color = DeckStudioPalette.ink, style = StudioText.body)
                Text("Commander buttons use Scryfall's public card link: Scryfall receives that name, then EDHREC and its providers receive browser requests and your IP. Website cookies stay in this temporary session. Anything you choose to paste/submit on the website is handled by that website.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                for (name in names) StudioButton("Browse $name", { model.openCommander(context, name) }, enabled = !model.resolving)
                if (commanders.size > 1) Text("These open individual card/commander pages. Use EDHREC's pairing controls for combined recommendations.",
                    color = DeckStudioPalette.ink, style = StudioText.caption)
                if (commanders.isNotEmpty()) StudioPlainButton(if (copied) "Commander names copied" else "Copy commander names", {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("Commanders", commanders.joinToString("\n")))
                    copied = true
                }, icon = "doc.on.doc")
                StudioButton("Browse commanders on EDHREC", { model.open(context, DeckStudioEDHRECPolicy.browseURL) }, primary = false)
                StudioButton("Open EDHREC's Recs tool", { model.open(context, DeckStudioEDHRECPolicy.recsURL) }, primary = false)
            }
        }
    }
    model.externalURL?.let { url ->
        ConfirmationDialog("Open external website?", "You're leaving EDHREC. MagicMobile does not automatically attach your deck to this request.",
            listOf(ConfirmationAction("Open ${Uri.parse(url).host ?: "website"} in your browser") { model.externalURL = null; openExternal(context, url) }),
            light = true) { model.externalURL = null }
    }
}

/** DeckStudioScryfallReference: optional online reference; it never changes the rules engine. */
@Composable
fun DeckStudioScryfallReference(name: String, initialCard: DeckStudioScryfallCard? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var value by remember(name) { mutableStateOf<DeckStudioScryfallClient.CachedCard?>(null) }
    var error by remember(name) { mutableStateOf<String?>(null) }
    var busy by remember(name) { mutableStateOf(false) }
    var job by remember { mutableStateOf<Job?>(null) }
    fun lookup(network: Boolean) {
        job?.cancel(); busy = network; error = null
        job = scope.launch {
            try { value = DeckStudioServices.scryfall.named(name, allowNetwork = network, refresh = network) ?: value; busy = false }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { busy = false; error = failure.message }
        }
    }
    LaunchedEffect(name) { lookup(false) }
    DisposableEffect(name) { onDispose { job?.cancel() } }
    StudioPanel {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("globe", DeckStudioPalette.ink, 17.dp)
            Text("Scryfall reference", color = DeckStudioPalette.ink, style = StudioText.headline)
        }
        Text("Optional online reference. Scryfall receives this card name and your IP address. Its current text/legality may differ from the installed XMage version; it never changes the rules engine.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        val card = value?.card ?: initialCard
        if (card != null) {
            Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            value?.let { Text("${if (it.cached) "Cached" else "Fetched"} ${formatDateTime(it.fetchedAt)}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2) }
                ?: Text("From the selected Scryfall search result", color = DeckStudioPalette.ink, style = StudioText.caption2)
            card.manaCost?.let { NativeDeckManaCost(it) }
            card.oracleText?.let { GameRulesText(it, cardName = card.name, style = StudioText.subheadline, color = DeckStudioPalette.ink) }
            for (face in card.faces ?: emptyList()) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(face.name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
                face.oracleText?.let { GameRulesText(it, cardName = face.name, style = StudioText.subheadline, color = DeckStudioPalette.ink) }
            }
            card.legalities?.get("commander")?.let { Text("Scryfall Commander status: $it", color = DeckStudioPalette.ink, style = StudioText.caption) }
            card.websiteURL?.let { url -> StudioPlainButton("View on Scryfall", { openExternal(context, url) }) }
        }
        error?.let { Text(it, color = DeckStudioPalette.warning, style = StudioText.caption) }
        if (busy) {
            StudioProgress("Looking up reference…")
            StudioPlainButton("Cancel", { job?.cancel(); busy = false })
        } else StudioButton(if (value == null) "Look up on Scryfall" else "Refresh Scryfall reference", { lookup(true) }, primary = false)
    }
}
