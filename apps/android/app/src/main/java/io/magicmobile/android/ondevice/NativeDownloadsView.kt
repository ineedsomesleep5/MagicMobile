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
import kotlinx.coroutines.launch
import java.text.NumberFormat

/** One deck the downloads screen can target (NativeDownloadDeck). */
data class NativeDownloadDeck(val id: String, val name: String, val cardNames: List<String>) {
    companion object {
        fun of(id: String, deck: Deck) = NativeDownloadDeck(id, deck.name, deck.entries.map { it.name }.toSortedSet().toList())
    }
}

private val formRow = rgb(0.11, 0.11, 0.12)
private val secondary = Color.White.copy(alpha = 0.6f)

@Composable
private fun FormSection(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        header?.let { Text(it.uppercase(), Modifier.padding(start = 16.dp, bottom = 6.dp), color = secondary, style = sf(13f)) }
        Column(Modifier.fillMaxWidth().background(formRow, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 4.dp), content = content)
        footer?.let { Text(it, Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), color = secondary, style = sf(13f)) }
    }
}

@Composable
private fun RowDivider() = HorizontalDivider(thickness = 0.5.dp, color = Color.White.copy(alpha = 0.12f))

@Composable
private fun Labeled(title: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = Color.White, style = sf(17f))
        Text(value, Modifier.weight(1f), color = secondary, style = sf(17f), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}

@Composable
private fun PickerRow(title: String, value: String, enabled: Boolean, entries: () -> List<MenuEntry>, label: String) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, style = sf(17f), maxLines = 1, softWrap = false)
        Box(Modifier.weight(1f).padding(start = 12.dp), contentAlignment = Alignment.CenterEnd) { IosMenuPicker(value, entries, enabled = enabled, label = label) }
    }
}

@Composable
private fun FormButton(title: String, enabled: Boolean, label: String, destructive: Boolean = false, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.CenterStart) {
        Text(title, color = (if (destructive) rgb(1.0, 0.27, 0.23) else BrandTheme.ember).copy(alpha = if (enabled) 1f else 0.35f), style = sf(17f))
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
            runCatching { ArtworkDownloadClient(context).scan(names, quality, downloadsTokens) }
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

    Column(Modifier.fillMaxWidth().height((LocalConfiguration.current.screenHeightDp - 56).dp)) {
        IosSheetHeader("Downloads", dismiss)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            FormSection("Artwork", if (downloadScope == "tokens") "Token-only downloads contain no ordinary card images." else "Full catalogue includes opponents’ cards too.") {
                val scopes = listOf("catalogue" to "Full catalogue · recommended", "tokens" to "All supported tokens", "decks" to "All saved & included decks", "deck" to "One deck")
                PickerRow("Download", scopes.first { it.first == downloadScope }.second, !running, {
                    scopes.map { (value, title) -> MenuEntry.Item(title, checked = value == downloadScope) { downloadScope = value } }
                }, "downloads.scope")
                if (downloadScope == "deck") {
                    RowDivider()
                    PickerRow("Deck", decks.firstOrNull { it.id == deckID }?.name ?: "No decks", !running, {
                        decks.map { deck -> MenuEntry.Item(deck.name, checked = deck.id == deckID) { savedDeck = deck.id } }
                    }, "downloads.deck")
                }
                RowDivider()
                PickerRow("Image quality", quality.label, !running, {
                    ArtworkQuality.entries.map { value -> MenuEntry.Item(value.label, checked = value == quality) { qualityID = value.id } }
                }, "downloads.quality")
                if (downloadScope != "tokens") {
                    RowDivider()
                    IosToggle(includeTokens, { if (!running) includeTokens = it }, tint = BrandTheme.ember) {
                        Text("Include tokens", color = Color.White, style = sf(17f))
                    }
                }
            }
            FormSection("On this device") {
                if (loadingCatalogue && downloadScope == "catalogue") ProgressRow("Reading the installed catalogue…")
                if (catalogueError != null && downloadScope == "catalogue") Text(catalogueError, Modifier.padding(vertical = 10.dp), color = rgb(1.0, 0.27, 0.23), style = sf(17f))
                if (downloadScope != "tokens") {
                    Labeled("Cards", if (scanPending || (downloadScope == "catalogue" && loadingCatalogue)) "Checking needed"
                        else "${number.format(current!!.cards + current.faceStored)} / ${number.format(names.size + current.faceTotal)}",
                        Modifier.semantics { contentDescription = "downloads.cards" })
                    RowDivider()
                }
                Labeled("Tokens", if (scanPending || current?.tokensKnown != true && downloadsTokens) "Checking needed"
                    else "${number.format(current!!.tokenStored)} / ${number.format(current.tokenTotal)}")
                RowDivider()
                if (scanning) { ProgressRow("Checking local files…"); RowDivider() }
                Labeled("Stored", Formatter.formatFileSize(context, current?.bytes ?: Artwork.storedDownloadBytes(context)))
                RowDivider()
                Labeled("Missing artwork", missingSummary)
                RowDivider()
                Labeled("Estimated additional download", estimate)
                Text("Approximate at ${quality.label.lowercase()} quality. Actual download and device storage vary with image sizes, metadata and images already stored.",
                    Modifier.padding(bottom = 8.dp), color = secondary, style = sf(12f))
                RowDivider()
                FormButton("Check for missing artwork", !running && !scanning, "downloads.check") { runScan() }
            }
            FormSection("Download", "You can play or leave the app while images download. Wi-Fi is recommended.") {
                IosToggle(remoteArtwork, { enabled -> Artwork.setEnabled(context, enabled); if (!enabled && running) ArtworkDownloadService.pause(context) }, tint = BrandTheme.ember,
                    modifier = Modifier.semantics { contentDescription = "nativeArtwork.downloads" }) {
                    Text("Download card artwork", color = Color.White, style = sf(17f))
                }
                Text("Uses Scryfall. Online requests share your IP and card names, including your hand.", Modifier.padding(bottom = 8.dp), color = secondary, style = sf(12f))
                RowDivider()
                val progress = downloadState.progress
                if (running) {
                    val preparing = progress.status.startsWith("Preparing") || progress.status.startsWith("Checking")
                    if (preparing) ProgressRow("Preparing image list…")
                    else LinearProgressIndicator({ if (progress.total == 0) 0f else progress.completed.toFloat() / progress.total },
                        Modifier.fillMaxWidth().padding(vertical = 12.dp), color = BrandTheme.ember, trackColor = Color.White.copy(alpha = 0.15f))
                    Text(progress.status, Modifier.padding(bottom = 8.dp).semantics { contentDescription = "downloads.status" }, color = Color.White, style = sf(16f))
                    RowDivider()
                    FormButton("Cancel download", true, "downloads.cancel") { ArtworkDownloadService.pause(context) }
                } else {
                    if (progress.total > 0 && progress.status.isNotEmpty()) {
                        Text(progress.status, Modifier.padding(vertical = 10.dp).semantics { contentDescription = "downloads.status" }, color = Color.White, style = sf(16f))
                        RowDivider()
                    }
                    FormButton("Download missing artwork", remoteArtwork && (names.isNotEmpty() || downloadScope == "tokens") && !scanning &&
                        !(downloadScope == "catalogue" && loadingCatalogue), "downloads.start") { if (fullCatalogue) confirmFull = true else startDownload() }
                    if (ArtworkDownloadService.hasPending(context)) {
                        RowDivider()
                        FormButton("Resume previous download", remoteArtwork, "downloads.resume") { runCatching { ArtworkDownloadService.resume(context) } }
                    }
                }
            }
            FormSection {
                MoreInfo(engineReady, catalogueError == null)
            }
            val failures = downloadState.failures
            if (failures.isNotEmpty()) FormSection("Needs attention") {
                failures.take(20).forEach { Text(it, Modifier.padding(vertical = 6.dp), color = Color.White, style = sf(16f)) }
                if (failures.size > 20) Text("And ${failures.size - 20} more issues. Check missing artwork below.", color = secondary, style = sf(12f))
                Text("Use Download missing artwork to retry. Already stored artwork is preserved.", Modifier.padding(vertical = 6.dp), color = secondary, style = sf(12f))
            }
            if (current != null && current.missingTokens.isNotEmpty()) FormSection {
                Disclosure("Missing tokens · ${number.format(current.missingTokens.size)}") {
                    current.missingTokens.take(20).forEach { Text("Token $it", color = Color.White, style = sf(17f)) }
                }
            }
            if (current != null && current.missingCards.isNotEmpty() && downloadScope != "tokens") FormSection {
                Disclosure("Missing cards · ${number.format(current.missingCards.size)}") {
                    current.missingCards.take(20).forEach { Text(it, color = Color.White, style = sf(17f)) }
                    if (current.missingCards.size > 20) Text("And ${current.missingCards.size - 20} more", color = secondary, style = sf(17f))
                }
            }
        }
    }
    if (confirmFull) IosAlert("Download missing artwork?",
        "$missingSummary ${if (discoveryIncomplete) "The additional download estimate needs checking." else "Estimated additional download: $estimate."} This is approximate; actual download and device storage vary. Images continue downloading while you play or leave the app. Wi-Fi is recommended.",
        listOf("Download missing images · ${quality.label}" to { confirmFull = false; startDownload() }), cancel = { confirmFull = false })
}

@Composable
private fun ProgressRow(title: String) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        CircularProgressIndicator(Modifier.size(18.dp), color = secondary, strokeWidth = 2.dp)
        Text(title, color = secondary, style = sf(17f))
    }
}

@Composable
private fun Disclosure(title: String, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), color = Color.White, style = sf(16f))
            SfImage(if (expanded) "chevron.down" else "chevron.right", BrandTheme.ember, 14.dp)
        }
        if (expanded) Column(Modifier.padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
private fun MoreInfo(engineReady: Boolean, catalogueIncluded: Boolean) {
    Disclosure("More info") {
        @Composable fun label(text: String, ok: Boolean) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(if (ok) "checkmark.circle" else "exclamationmark.circle", BrandTheme.ember, 17.dp)
            Text(text, color = Color.White, style = sf(16f))
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
        )) Text(text, color = Color.White, style = sf(16f))
    }
}
