package io.magicmobile.android.ondevice

import android.content.Context
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import io.magicmobile.android.Artwork
import io.magicmobile.android.ArtworkDownloadClient
import io.magicmobile.android.ArtworkDownloadService
import io.magicmobile.android.ArtworkQuality
import io.magicmobile.android.DownloadScan
import io.magicmobile.android.core.Deck
import io.magicmobile.android.game.DownloadReadout
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaCheckbox
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaOptionRow
import io.magicmobile.android.menus.ArenaPanelHeader
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaPlayButton
import io.magicmobile.android.menus.ArenaSegmented
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.launch
import java.text.NumberFormat

/** One deck the downloads screen can target (NativeDownloadDeck). `chosenArt` holds the printings whose art the player chose in it. */
data class NativeDownloadDeck(val id: String, val name: String, val cardNames: List<String>,
                              val chosenArt: List<io.magicmobile.android.ChosenArt> = emptyList()) {
    companion object {
        fun of(id: String, deck: Deck) = NativeDownloadDeck(id, deck.name, deck.entries.map { it.name }.toSortedSet().toList(),
            io.magicmobile.android.ChosenArt.choices(deck))
    }
}

/**
 * Port of NativeDownloadsView.swift: explicit artwork downloads, separate from the bundled rules engine and catalogue. Arena's
 * panel (Caleb, 2026-10-22): what is on this phone and the Download plaque first (a readout with Check on its line, a gold bar,
 * the state once), then what to download from diamond rows and a tab strip; the technical notes fold away at the foot.
 */
@Composable
fun NativeDownloadsView(decks: List<NativeDownloadDeck>, selectedDeckID: String, engineReady: Boolean, catalogueNames: List<String>?, catalogueError: String?,
                        dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val number = remember { NumberFormat.getIntegerInstance() }
    var includeTokens by AppPreferences.boolean("magicmobile.artworkDownloadTokens", true)
    var downloadScope by AppPreferences.string("magicmobile.artworkDownloadScope", "catalogue")
    var qualityID by AppPreferences.string("magicmobile.artworkDownloadQuality", "standard")
    var savedDeck by AppPreferences.string("magicmobile.artworkDownloadDeck", selectedDeckID)
    val quality = ArtworkQuality.entries.firstOrNull { it.id == qualityID } ?: ArtworkQuality.STANDARD
    val deckID = if (decks.any { it.id == savedDeck }) savedDeck else decks.firstOrNull()?.id ?: ""
    val consentRevision = Artwork.consentRevision
    val remoteArtwork = remember(consentRevision) { Artwork.enabled(context) }
    val downloadState by ArtworkDownloadService.state.collectAsState()
    val running = downloadState.running
    var scanning by remember { mutableStateOf(false) }
    var scan by remember { mutableStateOf<DownloadScan?>(null) }
    var scanned by remember { mutableStateOf<String?>(null) }
    var confirmFull by remember { mutableStateOf(false) }
    var choosingDeck by remember { mutableStateOf(false) }
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    val loadingCatalogue = catalogueNames == null && catalogueError == null
    val names = when (downloadScope) {
        "catalogue" -> catalogueNames ?: emptyList()
        "tokens" -> emptyList()
        "decks" -> decks.flatMap { it.cardNames }.toSortedSet().toList()
        else -> decks.firstOrNull { it.id == deckID }?.cardNames ?: emptyList()
    }
    val downloadsTokens = includeTokens || downloadScope == "tokens"
    // The art chosen in Deck Studio always comes with a download of cards: this deck's for One deck, every saved deck's
    // otherwise (the full catalogue included), and none for tokens alone.
    val chosen = remember(downloadScope, deckID, decks) {
        val source = if (downloadScope == "tokens") emptyList() else if (downloadScope == "deck") decks.firstOrNull { it.id == deckID }?.chosenArt.orEmpty() else decks.flatMap { it.chosenArt }
        source.distinctBy { it.printing.key }
    }
    val selectionKey = "$downloadScope|$deckID|${quality.id}|${names.size}|$downloadsTokens|${chosen.joinToString(",") { it.printing.key }}"
    val scanPending = scanning || scan == null || scanned != selectionKey
    val current = scan
    val tokensOnly = downloadScope == "tokens"
    val missingCards = if (tokensOnly || current == null) 0 else current.missingCards.size
    val missingTokens = if (!downloadsTokens || current == null) 0 else current.missingTokens.size
    val discoveryIncomplete = scanPending || (downloadScope == "catalogue" && loadingCatalogue) || current?.coverageKnown != true
    val missingSummary = if (scanPending) "Checking needed to count missing artwork." else {
        val cards = "${number.format(missingCards)} card/face ${if (missingCards == 1) "image" else "images"}"
        val tokens = "${number.format(missingTokens)} token ${if (missingTokens == 1) "image" else "images"}"
        val count = if (tokensOnly) tokens else if (downloadsTokens) "$cards · $tokens" else cards
        if (discoveryIncomplete) "Found so far: $count. Checking needed for the remaining artwork." else "Missing: $count"
    }
    val estimateSize = Formatter.formatFileSize(context, (missingCards + missingTokens).toLong() * quality.estimatedBytes)
    val estimate = if (discoveryIncomplete) "Checking needed" else "≈ $estimateSize"
    val fullCatalogue = downloadScope == "catalogue" || tokensOnly
    val progress = downloadState.progress
    val preparing = scanning || progress.status.startsWith("Preparing") || progress.status.startsWith("Checking")

    fun runScan() {
        val key = selectionKey
        if (downloadScope == "catalogue" && loadingCatalogue) return
        scanning = true
        scope.launch {
            runCatching { ArtworkDownloadClient(context).scan(names, quality, downloadsTokens, fullCatalogue, chosen) }
                .onSuccess { scan = it; scanned = key }
            scanning = false
        }
    }
    fun startDownload() {
        if (running || (names.isEmpty() && !tokensOnly)) return
        val preferences = context.getSharedPreferences("magicmobile.artwork", Context.MODE_PRIVATE)
        if (android.os.Build.VERSION.SDK_INT >= 33 && !preferences.getBoolean("askedDownloadNotifications", false)) {
            preferences.edit().putBoolean("askedDownloadNotifications", true).apply()
            notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        scope.launch { runCatching { ArtworkDownloadService.start(context.applicationContext, names, quality, downloadsTokens, fullCatalogue, chosen) } }
    }
    LaunchedEffect(selectionKey, loadingCatalogue) { runScan() }
    LaunchedEffect(running) { if (!running) runScan() }

    val readout = DownloadReadout.readout(running, preparing, progress.completed, progress.total, tokensOnly,
        current?.let { it.cards + it.faceStored + it.printingStored } ?: 0, current?.let { names.size + it.faceTotal + it.printingTotal } ?: 0,
        current?.tokenStored ?: 0, current?.tokenTotal ?: 0, scanPending || (downloadScope == "catalogue" && loadingCatalogue))
    val stateLine = DownloadReadout.stateLine(running, preparing, progress.status, scanning, loadingCatalogue && downloadScope == "catalogue", scanPending,
        missingCards + missingTokens, discoveryIncomplete, estimateSize, quality.label)
    val storedBytes = current?.bytes ?: Artwork.storedDownloadBytes(context)
    val coverage = DownloadReadout.coverage(tokensOnly, scanPending, current?.tokensKnown == true, current?.tokenStored ?: 0, current?.tokenTotal ?: 0,
        storedBytes, Formatter.formatFileSize(context, storedBytes))

    Column(Modifier.fillMaxWidth()) {
        ArenaPanelHeader("Downloads", closeIdentifier = "downloads.close", close = dismiss)
        Column(Modifier.fillMaxWidth().arenaScrollFade(48.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                // First: what is on this phone, what is missing, the consent and the Download plaque.
                Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    // Check stands on the readout's line, not alone in a band of its own.
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(readout.count, Modifier.weight(1f).testTag("downloads.summary").semantics { heading() }, color = ArenaMenuStyle.text,
                            style = ArenaMenuStyle.font(22f, SfWeight.bold).copy(fontFeatureSettings = "tnum"), maxLines = 1)
                        ArenaPillButton("Check", { runScan() }, Modifier.semantics { contentDescription = "Check for missing artwork" },
                            enabled = !running && !scanning, identifier = "downloads.check")
                    }
                    readout.fraction?.let { DownloadProgressBar(it.toFloat(), gold = !running) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (scanning || (running && preparing) || (loadingCatalogue && downloadScope == "catalogue")) {
                            CircularProgressIndicator(Modifier.size(14.dp), color = ArenaMenuStyle.gold, strokeWidth = 2.dp)
                        }
                        if (stateLine.isNotEmpty()) Text(stateLine, Modifier.testTag("downloads.status"), color = ArenaMenuStyle.dim,
                            style = ArenaMenuStyle.font(12f, SfWeight.semibold))
                    }
                    if (coverage.isNotEmpty()) Text(coverage, Modifier.testTag("downloads.cards"), color = ArenaMenuStyle.dim,
                        style = ArenaMenuStyle.font(13f, SfWeight.medium).copy(fontFeatureSettings = "tnum"))
                    if (catalogueError != null && downloadScope == "catalogue") Text(catalogueError, color = ArenaMenuStyle.loss, style = ArenaMenuStyle.font(13f, SfWeight.medium))
                    // The consent, named for what it allows so it doesn't repeat the Download plaque under it; what it shares stays in
                    // view because it is the consent's terms, not help.
                    ArenaCheckbox("Online card art", remoteArtwork, { enabled -> Artwork.setEnabled(context, enabled); if (!enabled && running) ArtworkDownloadService.pause(context) },
                        subtitle = "Uses Scryfall. Online requests share your IP and card names, including your hand.", identifier = "nativeArtwork.downloads")
                    Text("Shares your IP and card names with Scryfall.", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11.5f, SfWeight.medium))
                    if (running) {
                        ArenaPlayButton("Cancel download", { ArtworkDownloadService.pause(context) }, Modifier.fillMaxWidth().height(46.dp), cancel = true,
                            fontSize = 16f, identifier = "downloads.cancel")
                    } else {
                        if (progress.total > 0 && progress.status.isNotEmpty() && stateLine != progress.status) Note(progress.status)
                        ArenaPlayButton("Download missing artwork", { if (fullCatalogue) confirmFull = true else startDownload() },
                            Modifier.fillMaxWidth().height(46.dp), fontSize = 17f, identifier = "downloads.start",
                            enabled = remoteArtwork && (names.isNotEmpty() || tokensOnly) && !scanning && !(downloadScope == "catalogue" && loadingCatalogue))
                        // Android keeps an interrupted download's list (its foreground service) to pick up again.
                        if (ArtworkDownloadService.hasPending(context)) {
                            ArenaPillButton("Resume previous download", { runCatching { ArtworkDownloadService.resume(context) } }, Modifier.align(Alignment.CenterHorizontally),
                                enabled = remoteArtwork, identifier = "downloads.resume")
                        }
                    }
                }
                // Then what to download: the scope as diamond rows, the deck when it is one deck, the quality as a tab strip.
                Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ArenaCaps("What to download")
                    Column {
                        DownloadReadout.scopes.forEach { (title, value) ->
                            ArenaOptionRow(title, { downloadScope = value; if (value != "deck") choosingDeck = false }, selected = downloadScope == value,
                                identifier = "downloads.scope.$value", enabled = !running)
                        }
                    }
                    if (downloadScope == "deck") {
                        ArenaOptionRow("Deck", { choosingDeck = !choosingDeck }, value = decks.firstOrNull { it.id == deckID }?.name ?: "—", chevron = true,
                            identifier = "downloads.deck", enabled = !running)
                        AnimatedVisibility(choosingDeck, enter = fadeIn(tween(180)), exit = fadeOut(tween(180))) {
                            Column(Modifier.heightIn(max = 220.dp).verticalScroll(rememberScrollState()).padding(start = 16.dp)) {
                                decks.forEach { deck ->
                                    ArenaOptionRow(deck.name, { savedDeck = deck.id; choosingDeck = false }, selected = deck.id == deckID,
                                        identifier = "downloads.deck.${deck.id}", enabled = !running)
                                }
                            }
                        }
                    }
                    ArenaCaps("Image quality", modifier = Modifier.padding(top = 4.dp))
                    ArenaSegmented(ArtworkQuality.entries.map { it.label to it }, quality, { if (!running) qualityID = it.id },
                        Modifier.fillMaxWidth().alpha(if (running) 0.5f else 1f), identifier = "downloads.quality", stretch = true)
                    if (!tokensOnly) ArenaCheckbox("Include tokens", includeTokens, { includeTokens = it }, enabled = !running)
                }
                val failures = downloadState.failures
                if (failures.isNotEmpty()) Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ArenaCaps("Needs attention")
                    failures.take(20).forEach { Text(it, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.medium)) }
                    if (failures.size > 20) Note("And ${failures.size - 20} more issues. Check missing artwork below.")
                }
                val hasMissingTokens = current != null && current.missingTokens.isNotEmpty()
                val hasMissingCards = current != null && current.missingCards.isNotEmpty() && !tokensOnly
                if (hasMissingTokens || hasMissingCards) Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (hasMissingTokens) Disclosure("Missing tokens · ${number.format(current!!.missingTokens.size)}") {
                        current.missingTokens.take(20).forEach { Text(it, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.medium)) }
                    }
                    if (hasMissingCards) Disclosure("Missing cards · ${number.format(current!!.missingCards.size)}") {
                        current.missingCards.take(20).forEach { Text(it, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.medium)) }
                        if (current.missingCards.size > 20) Note("And ${current.missingCards.size - 20} more")
                    }
                }
                Box(Modifier.arenaCard().testTag("downloads.info")) { MoreInfo(engineReady, catalogueError == null) }
            }
        }
    }
    // The confirmation is the tavern kit's dialog, which draws Arena's glass and buttons over the menus.
    if (confirmFull) CompositionLocalProvider(io.magicmobile.android.ui.LocalTavernBoard provides true) {
        io.magicmobile.android.board.ConfirmationDialog("Download missing artwork?",
            "$missingSummary ${if (discoveryIncomplete) "The additional download estimate needs checking." else "Estimated additional download: $estimate."} This is approximate; actual download and device storage vary. Images continue downloading while you play or leave the app. Wi-Fi is recommended.",
            listOf(io.magicmobile.android.board.ConfirmationAction("Download missing images · ${quality.label}") { confirmFull = false; startDownload() })) { confirmFull = false }
    }
}

@Composable
private fun Note(text: String) = Text(text, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))

/** A download's progress: gold for what is stored (Arena's progress bars), ember for a download under way. */
@Composable
private fun DownloadProgressBar(fraction: Float, gold: Boolean) {
    val shown by animateFloatAsState(fraction.coerceIn(0f, 1f), tween(if (BoardMotionFlags.reduceMotion) 0 else 300), label = "downloadBar")
    Box(Modifier.fillMaxWidth().height(12.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape)
        .border(1.5.dp, ArenaMenuStyle.gold.copy(alpha = 0.6f), CircleShape)
        .semantics {
            contentDescription = "Download progress"; stateDescription = "${(shown * 100).toInt()}%"
            progressBarRangeInfo = ProgressBarRangeInfo(shown, 0f..1f)
        }) {
        Box(Modifier.fillMaxWidth(shown.coerceAtLeast(0.04f)).height(12.dp)
            .background(Brush.verticalGradient(if (gold) listOf(rgb(1.0, 0.88, 0.56), ArenaMenuStyle.gold) else listOf(rgb(1.0, 0.62, 0.32), ArenaMenuStyle.ember)), CircleShape))
    }
}

/** A section that opens and closes under a gold chevron (TavernDisclosure), in place of the system disclosure group. */
@Composable
private fun Disclosure(title: String, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val turn by animateFloatAsState(if (expanded) 180f else 0f, tween(if (BoardMotionFlags.reduceMotion) 0 else 200), label = "disclosure")
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        BrandPressable({ expanded = !expanded }, Modifier.fillMaxWidth().semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" }) {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold))
                Spacer(Modifier.size(8.dp))
                SfImage("chevron.down", ArenaMenuStyle.gold, 12.dp, Modifier.rotate(turn))
            }
        }
        if (expanded) Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
private fun MoreInfo(engineReady: Boolean, catalogueIncluded: Boolean) {
    Disclosure("More info") {
        @Composable fun label(text: String, ok: Boolean) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (ok) "checkmark.seal.fill" else "exclamationmark.circle", if (ok) ArenaMenuStyle.gold else ArenaMenuStyle.loss, 15.dp)
            Text(text, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.medium))
        }
        label(if (engineReady) "Local engine ready" else "Local engine not ready", engineReady)
        label(if (catalogueIncluded) "Card catalogue included" else "Card catalogue unavailable", catalogueIncluded)
        label("Mana symbols included", true)
        for (text in listOf(
            "These downloads supply artwork for decks and games. Rules and the supported card catalogue are already included; artwork is optional.",
            "Compact saves space. Standard balances clarity and size. High gives the sharpest inspection images. Higher-quality files already stored count toward lower-quality coverage.",
            "Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates use currently discovered missing images; more faces or tokens may be found while preparing. Actual download and storage vary. Check for missing artwork after app updates.",
            "Art you chose in Deck Studio is saved as its own image beside the card’s default one, so a card shows the printing you picked even offline. It comes with every download of cards.",
            "Full and token-only downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.",
            "Compact is fastest. Downloads use several direct image transfers at once and remember completed files. Android shows a notification while it downloads; closing the app from recents may pause transfers until you reopen it. The initial image-list preparation may need the app open on a slow connection.",
            "Storage is capped at 20 GB, with 1 GB of free space reserved. Unavailable or ambiguous token art remains a labeled placeholder. Use Download missing artwork to retry interruptions.",
        )) Note(text)
    }
}
