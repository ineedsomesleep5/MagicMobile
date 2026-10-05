package io.magicmobile.android.ondevice

import android.content.Context
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.Artwork
import io.magicmobile.android.ArtworkDownloadClient
import io.magicmobile.android.ArtworkDownloadService
import io.magicmobile.android.ArtworkQuality
import io.magicmobile.android.DownloadScan
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.core.Deck
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.IosAlert
import io.magicmobile.android.ui.IosMenuPicker
import io.magicmobile.android.ui.IosSheetHeader
import io.magicmobile.android.ui.IosToggle
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import androidx.compose.foundation.border
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import io.magicmobile.android.ranked.leatherCard
import io.magicmobile.android.ranked.parchmentCard
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernPicker
import io.magicmobile.android.ui.TavernPickerSection
import io.magicmobile.android.ui.TavernSheetBackground
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.TavernToggle
import io.magicmobile.android.ui.tavernTitleBar
import kotlinx.coroutines.launch
import java.text.NumberFormat

/** One deck the downloads screen can target (NativeDownloadDeck). */
data class NativeDownloadDeck(val id: String, val name: String, val cardNames: List<String>) {
    companion object {
        fun of(id: String, deck: Deck) = NativeDownloadDeck(id, deck.name, deck.entries.map { it.name }.toSortedSet().toList())
    }
}

private val parchment = TavernPalette.parchment
private val faded = TavernPalette.parchment.copy(alpha = 0.7f)
private val warning = rgb(1.0, 0.55, 0.45)

/** A leather card in brass with an engraved brass heading (TavernLeatherCard on iOS). */
@Composable
private fun FormSection(header: String? = null, footer: String? = null, parchmentCard: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Column(if (parchmentCard) Modifier.parchmentCard() else Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        header?.let { Text(it.uppercase(), Modifier.semantics { heading() }, color = TavernPalette.brass, style = sf(11f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f)) }
        content()
        footer?.let { Note(it) }
    }
}

@Composable
private fun Note(text: String) = Text(text, color = faded, style = sf(12f, design = SfDesign.SERIF))

@Composable
private fun Labeled(title: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = parchment, style = sf(15f, SfWeight.semibold, SfDesign.SERIF))
        Text(value, Modifier.weight(1f), color = parchment.copy(alpha = 0.85f), style = sf(14f, design = SfDesign.SERIF),
            textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}

@Composable
private fun FormButton(title: String, enabled: Boolean, label: String, kind: TavernButtonKind = TavernButtonKind.SECONDARY, onClick: () -> Unit) {
    TavernButton(onClick, Modifier.semantics { contentDescription = label }, kind = kind, fullWidth = true, enabled = enabled) { Text(title) }
}

/** A brass-rimmed groove filling with ember: a download's progress in the tavern. */
@Composable
private fun BrassProgressBar(fraction: Float) {
    val shape = RoundedCornerShape(50)
    Box(Modifier.fillMaxWidth().height(12.dp).background(Color.Black.copy(alpha = 0.5f), shape).border(1.5.dp, TavernPalette.brassLine, shape)
        .semantics { contentDescription = "Download progress ${(fraction.coerceIn(0f, 1f) * 100).toInt()}%" }) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0.04f, 1f)).height(12.dp)
            .background(Brush.verticalGradient(listOf(rgb(1.0, 0.62, 0.32), TavernPalette.ember)), shape))
    }
}

/** NativeDownloadsView.swift: explicit artwork downloads, separate from the bundled rules engine and catalogue. */
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
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    val loadingCatalogue = catalogueNames == null && catalogueError == null
    val names = when (downloadScope) {
        "catalogue" -> catalogueNames ?: emptyList()
        "tokens" -> emptyList()
        "decks" -> decks.flatMap { it.cardNames }.toSortedSet().toList()
        else -> decks.firstOrNull { it.id == deckID }?.cardNames ?: emptyList()
    }
    val downloadsTokens = includeTokens || downloadScope == "tokens"
    val selectionKey = "$downloadScope|$deckID|${quality.id}|${names.size}|$downloadsTokens"
    val scanPending = scanning || scan == null || scanned != selectionKey
    val current = scan
    val missingCards = if (downloadScope == "tokens" || current == null) 0 else current.missingCards.size
    val missingTokens = if (!downloadsTokens || current == null) 0 else current.missingTokens.size
    val discoveryIncomplete = scanPending || (downloadScope == "catalogue" && loadingCatalogue) || current?.coverageKnown != true
    val missingSummary = if (scanPending) "Checking needed to count missing artwork." else {
        val cards = "${number.format(missingCards)} card/face ${if (missingCards == 1) "image" else "images"}"
        val tokens = "${number.format(missingTokens)} token ${if (missingTokens == 1) "image" else "images"}"
        val count = if (downloadScope == "tokens") tokens else if (downloadsTokens) "$cards · $tokens" else cards
        if (discoveryIncomplete) "Found so far: $count. Checking needed for the remaining artwork." else "Missing: $count"
    }
    val estimate = if (discoveryIncomplete) "Checking needed" else "≈ ${Formatter.formatFileSize(context, (missingCards + missingTokens).toLong() * quality.estimatedBytes)}"
    val fullCatalogue = downloadScope == "catalogue" || downloadScope == "tokens"

    fun runScan() {
        val key = selectionKey
        if (downloadScope == "catalogue" && loadingCatalogue) return
        scanning = true
        scope.launch {
            runCatching { ArtworkDownloadClient(context).scan(names, quality, downloadsTokens, fullCatalogue) }
                .onSuccess { scan = it; scanned = key }
            scanning = false
        }
    }
    fun startDownload() {
        if (running || (names.isEmpty() && downloadScope != "tokens")) return
        val preferences = context.getSharedPreferences("magicmobile.artwork", Context.MODE_PRIVATE)
        if (android.os.Build.VERSION.SDK_INT >= 33 && !preferences.getBoolean("askedDownloadNotifications", false)) {
            preferences.edit().putBoolean("askedDownloadNotifications", true).apply()
            notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        scope.launch { runCatching { ArtworkDownloadService.start(context.applicationContext, names, quality, downloadsTokens, fullCatalogue) } }
    }
    LaunchedEffect(selectionKey, loadingCatalogue) { runScan() }
    LaunchedEffect(running) { if (!running) runScan() }

    // The tavern's own page (Caleb, 2026-10-04): leather title bar with the wax-seal close, leather cards in brass,
    // parchment pickers and plaque buttons; no system form chrome.
    CompositionLocalProvider(io.magicmobile.android.ui.LocalTavernBoard provides true) {
    Box(Modifier.fillMaxWidth().height((LocalConfiguration.current.screenHeightDp - 56).dp)) {
    TavernSheetBackground(Modifier.matchParentSize())
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 6.dp).fillMaxWidth().tavernTitleBar(), verticalAlignment = Alignment.CenterVertically) {
            TavernPanelTitle("Downloads", Modifier.weight(1f).semantics { heading() }.testTag("downloads.title"))
            TavernSealButton(dismiss, Modifier.testTag("downloads.close"), contentDescription = "Done")
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            FormSection("Artwork", if (downloadScope == "tokens") "Token-only downloads contain no ordinary card images." else "Full catalogue includes opponents’ cards too.") {
                val scopes = listOf("Full catalogue · recommended" to "catalogue", "All supported tokens" to "tokens", "All saved & included decks" to "decks", "One deck" to "deck")
                TavernPicker("Download", downloadScope, listOf(TavernPickerSection(null, scopes)), { downloadScope = it }, Modifier.testTag("downloads.scope"), enabled = !running)
                if (downloadScope == "deck") {
                    TavernPicker("Deck", deckID, listOf(TavernPickerSection(null, decks.map { it.name to it.id })), { savedDeck = it },
                        Modifier.testTag("downloads.deck"), enabled = !running)
                }
                TavernPicker("Image quality", quality, listOf(TavernPickerSection(null, ArtworkQuality.entries.map { it.label to it })), { qualityID = it.id },
                    Modifier.testTag("downloads.quality"), enabled = !running)
                if (downloadScope != "tokens") TavernToggle("Include tokens", includeTokens, { if (!running) includeTokens = it })
            }
            FormSection("On this device") {
                if (loadingCatalogue && downloadScope == "catalogue") ProgressRow("Reading the installed catalogue…")
                if (catalogueError != null && downloadScope == "catalogue") Text(catalogueError, color = warning, style = sf(14f, design = SfDesign.SERIF))
                if (downloadScope != "tokens") {
                    Labeled("Cards", if (scanPending || (downloadScope == "catalogue" && loadingCatalogue)) "Checking needed"
                        else "${number.format(current!!.cards + current.faceStored)} / ${number.format(names.size + current.faceTotal)}",
                        Modifier.testTag("downloads.cards"))
                }
                Labeled("Tokens", if (scanPending || current?.tokensKnown != true && downloadsTokens) "Checking needed"
                    else "${number.format(current!!.tokenStored)} / ${number.format(current.tokenTotal)}")
                if (scanning) ProgressRow("Checking local files…")
                Labeled("Stored", Formatter.formatFileSize(context, current?.bytes ?: Artwork.storedDownloadBytes(context)))
                Labeled("Missing artwork", missingSummary)
                Labeled("Estimated additional download", estimate)
                Note("Approximate at ${quality.label.lowercase()} quality. Actual download and device storage vary with image sizes, metadata and images already stored.")
                FormButton("Check for missing artwork", !running && !scanning, "downloads.check") { runScan() }
            }
            FormSection("Download", "You can play or leave the app while images download. Wi-Fi is recommended.") {
                TavernToggle("Download card artwork", remoteArtwork,
                    { enabled -> Artwork.setEnabled(context, enabled); if (!enabled && running) ArtworkDownloadService.pause(context) },
                    Modifier.semantics { contentDescription = "nativeArtwork.downloads" },
                    subtitle = "Uses Scryfall. Online requests share your IP and card names, including your hand.")
                val progress = downloadState.progress
                if (running) {
                    val preparing = progress.status.startsWith("Preparing") || progress.status.startsWith("Checking")
                    if (preparing) ProgressRow("Preparing image list…")
                    else BrassProgressBar(if (progress.total == 0) 0f else progress.completed.toFloat() / progress.total)
                    Text(progress.status, Modifier.testTag("downloads.status"), color = parchment, style = sf(14f, design = SfDesign.SERIF))
                    FormButton("Cancel download", true, "downloads.cancel", TavernButtonKind.DANGER) { ArtworkDownloadService.pause(context) }
                } else {
                    if (progress.total > 0 && progress.status.isNotEmpty()) {
                        Text(progress.status, Modifier.testTag("downloads.status"), color = parchment, style = sf(14f, design = SfDesign.SERIF))
                    }
                    FormButton("Download missing artwork", remoteArtwork && (names.isNotEmpty() || downloadScope == "tokens") && !scanning &&
                        !(downloadScope == "catalogue" && loadingCatalogue), "downloads.start", TavernButtonKind.PRIMARY) { if (fullCatalogue) confirmFull = true else startDownload() }
                    if (ArtworkDownloadService.hasPending(context)) {
                        FormButton("Resume previous download", remoteArtwork, "downloads.resume") { runCatching { ArtworkDownloadService.resume(context) } }
                    }
                }
            }
            FormSection {
                MoreInfo(engineReady, catalogueError == null)
            }
            val failures = downloadState.failures
            if (failures.isNotEmpty()) FormSection("Needs attention", parchmentCard = true) {
                failures.take(20).forEach { Text(it, color = TavernPalette.ink, style = sf(14f, design = SfDesign.SERIF)) }
                if (failures.size > 20) Text("And ${failures.size - 20} more issues. Check missing artwork below.", color = TavernPalette.ink.copy(alpha = 0.7f), style = sf(12f, design = SfDesign.SERIF))
                Text("Use Download missing artwork to retry. Already stored artwork is preserved.", color = TavernPalette.ink.copy(alpha = 0.7f), style = sf(12f, design = SfDesign.SERIF))
            }
            if (current != null && current.missingTokens.isNotEmpty()) FormSection {
                Disclosure("Missing tokens · ${number.format(current.missingTokens.size)}") {
                    current.missingTokens.take(20).forEach { Text("Token $it", color = parchment, style = sf(13f, design = SfDesign.SERIF)) }
                }
            }
            if (current != null && current.missingCards.isNotEmpty() && downloadScope != "tokens") FormSection {
                Disclosure("Missing cards · ${number.format(current.missingCards.size)}") {
                    current.missingCards.take(20).forEach { Text(it, color = parchment, style = sf(13f, design = SfDesign.SERIF)) }
                    if (current.missingCards.size > 20) Note("And ${current.missingCards.size - 20} more")
                }
            }
        }
    }
    }
    if (confirmFull) io.magicmobile.android.board.ConfirmationDialog("Download missing artwork?",
        "$missingSummary ${if (discoveryIncomplete) "The additional download estimate needs checking." else "Estimated additional download: $estimate."} This is approximate; actual download and device storage vary. Images continue downloading while you play or leave the app. Wi-Fi is recommended.",
        listOf(io.magicmobile.android.board.ConfirmationAction("Download missing images · ${quality.label}") { confirmFull = false; startDownload() })) { confirmFull = false }
    }
}

@Composable
private fun ProgressRow(title: String) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        CircularProgressIndicator(Modifier.size(18.dp), color = TavernPalette.brass, strokeWidth = 2.dp)
        Text(title, color = parchment, style = sf(14f, design = SfDesign.SERIF))
    }
}

@Composable
private fun Disclosure(title: String, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), color = parchment, style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
            SfImage(if (expanded) "chevron.up" else "chevron.down", TavernPalette.brass, 14.dp)
        }
        if (expanded) Column(Modifier.padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
private fun MoreInfo(engineReady: Boolean, catalogueIncluded: Boolean) {
    Disclosure("More info") {
        @Composable fun label(text: String, ok: Boolean) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (ok) "checkmark.seal.fill" else "exclamationmark.circle", if (ok) TavernPalette.brass else warning, 17.dp)
            Text(text, color = parchment, style = sf(14f, design = SfDesign.SERIF))
        }
        label(if (engineReady) "Local engine ready" else "Local engine not ready", engineReady)
        label(if (catalogueIncluded) "Card catalogue included" else "Card catalogue unavailable", catalogueIncluded)
        label("Mana symbols included", true)
        for (text in listOf(
            "These downloads supply artwork for decks and games. Rules and the supported card catalogue are already included; artwork is optional.",
            "Compact saves space. Standard balances clarity and size. High gives the sharpest inspection images. Higher-quality files already stored count toward lower-quality coverage.",
            "Full catalogue covers this build’s supported cards, not every printing. Alternate faces are checked during download. Estimates use currently discovered missing images; more faces or tokens may be found while preparing. Actual download and storage vary. Check for missing artwork after app updates.",
            "Full and token-only downloads use Scryfall’s bulk image index. Deck and on-demand requests share card names and your IP address. Stored artwork works offline.",
            "Compact is fastest. Downloads use several direct image transfers at once and remember completed files. Android shows a notification while it downloads; closing the app from recents may pause transfers until you reopen it. The initial image-list preparation may need the app open on a slow connection.",
            "Storage is capped at 20 GB, with 1 GB of free space reserved. Unavailable or ambiguous token art remains a labeled placeholder. Use Download missing artwork to retry interruptions.",
        )) Note(text)
    }
}
