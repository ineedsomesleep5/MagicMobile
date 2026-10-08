package io.magicmobile.android.studio

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.CardPrinting
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

/**
 * Choosing the artwork of one card in a deck: every printing Scryfall lists for the card, as sleeves on the book's
 * page, newest first. The choice belongs to the deck row. It shows in the deck, on the board and in exports
 * ("1 Sol Ring (CMM) 400"), and it never changes the card's rules or the deck's check. DeckStudioArtworkPicker.swift.
 * `choose(null)` returns the card to its default artwork.
 */
@Composable
fun DeckStudioArtworkPicker(name: String, current: CardPrinting?, choose: (CardPrinting?) -> Boolean, dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val (remote, setRemote) = rememberArtworkConsent()
    var printings by remember { mutableStateOf<List<ScryfallPrinting>>(emptyList()) }
    var page by remember { mutableStateOf(0) }
    var hasMore by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun load(next: Int) {
        if (busy) return
        val url = DeckStudioPrintings.requestUrl(name, next)
        if (url == null) { error = "This card's name can't be searched for printings. It keeps its default artwork."; loaded = true; return }
        busy = true; error = null
        scope.launch {
            try {
                val bytes = io.magicmobile.android.ArtworkTransport.bytes(context, URL(url), 4 * 1024 * 1024, setOf("application/json"))
                val result = withContext(Dispatchers.Default) { DeckStudioPrintings.parse(bytes.toString(Charsets.UTF_8), next) }
                val known = printings.map { it.id }.toSet()
                printings = if (next == 1) result.printings else printings + result.printings.filter { it.id !in known }
                page = result.page; hasMore = result.hasMore && result.page < 10; loaded = true
            } catch (cancelled: CancellationException) { throw cancelled
            } catch (failure: Exception) {
                error = if (failure.message == "Scryfall returned 404.") "No matching cards were found on Scryfall." else failure.message ?: "Scryfall is unavailable or offline."
            } finally { busy = false }
        }
    }
    LaunchedEffect(remote) { if (remote && !loaded) load(1) }

    Column(Modifier.fillMaxWidth().height(largeSheetHeight()).testTag("deckStudio.artwork.picker")) {
        StudioSheetBar("Choose artwork", done = dismiss)
        if (!remote) Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Header(name, current, choose, dismiss)
            BinderNote("Online card images are off",
                "Choosing artwork asks Scryfall for this card's printings. It receives the card name and your IP address, and nothing else. Saved images keep working offline.",
                icon = "photo.on.rectangle.angled")
            BinderPlaque(Modifier.testTag("deckStudio.artwork.enable"), title = "Turn on") { setRemote(true) }
        } else LazyVerticalGrid(GridCells.Adaptive(104.dp), Modifier.fillMaxSize().padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Header(name, current, choose, dismiss)
                    error?.let {
                        BinderNote("Printings unavailable", it, icon = "exclamationmark.triangle")
                        if (DeckStudioPrintings.isSearchable(name)) BinderPlaque(title = "Try again") { load(maxOf(1, page + if (printings.isEmpty()) 0 else 1)) }
                    }
                    if (printings.isEmpty() && busy) Text("Looking up printings…", color = DeckStudioPalette.secondaryInk, style = sf(14f, design = SfDesign.SERIF))
                }
            }
            items(printings, key = { it.id }) { PrintingTile(it, current) { printing -> if (choose(printing)) dismiss() } }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Box(Modifier.fillMaxWidth().padding(bottom = 24.dp), contentAlignment = Alignment.Center) {
                    when {
                        hasMore -> BinderPlaque(Modifier.testTag("deckStudio.artwork.more"), title = if (busy) "Loading…" else "More printings", enabled = !busy) { load(page + 1) }
                        loaded && error == null && printings.isNotEmpty() ->
                            Text("${printings.size} printing${if (printings.size == 1) "" else "s"}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(name: String, current: CardPrinting?, choose: (CardPrinting?) -> Boolean, dismiss: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(name, color = DeckStudioPalette.ink, style = sf(22f, SfWeight.bold, SfDesign.SERIF))
        Text(current?.let { "Showing ${it.label}" } ?: "Showing the default artwork", Modifier.testTag("deckStudio.artwork.current"),
            color = DeckStudioPalette.secondaryInk, style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
        Text("The art you pick is saved with this card in this deck. It shows in the deck, on the board and in exports, and never changes the card's rules.",
            color = DeckStudioPalette.secondaryInk, style = sf(13f, design = SfDesign.SERIF))
        if (current != null) BinderPlaque(Modifier.testTag("deckStudio.artwork.default"), title = "Use the default artwork") { if (choose(null)) dismiss() }
    }
}

@Composable
private fun PrintingTile(item: ScryfallPrinting, current: CardPrinting?, choose: (CardPrinting) -> Unit) {
    val printing = item.printing
    val chosen = printing != null && printing == current
    val shape = RoundedCornerShape(DeckStudioMetrics.cardRadius)
    Column(Modifier.then(if (printing != null) Modifier.clickable(role = Role.Button) { GameAudio.play(GameSound.UI_TICK); choose(printing) } else Modifier)
        .semantics(mergeDescendants = true) {
            contentDescription = "${item.setName}, ${printing?.label ?: item.collectorNumber}"
            role = Role.Button
            selected = chosen
        }, verticalArrangement = Arrangement.spacedBy(5.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().aspectRatio(63f / 88f).shadow(3.dp, shape).clip(shape)
            .border(if (chosen) 3.dp else 1.dp, if (chosen) DeckStudioPalette.accent else DeckStudioPalette.separator, shape)) {
            PrintingThumbnail(item.thumbnail)
            if (chosen) Box(Modifier.align(Alignment.TopEnd).padding(5.dp).background(DeckStudioPalette.surfaceElevated, CircleShape)) {
                SfImage("checkmark.circle.fill", DeckStudioPalette.accent, 22.dp)
            }
        }
        Text(printing?.label ?: item.set.uppercase(), color = DeckStudioPalette.ink, style = sf(12f, SfWeight.heavy, SfDesign.SERIF), maxLines = 1)
        Text(item.caption, color = DeckStudioPalette.secondaryInk, style = sf(10f, design = SfDesign.SERIF), maxLines = 2,
            overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** Small pictures held while the picker is open: a scrolled-back grid does not fetch them again. */
private val thumbnails = object : LruCache<String, Bitmap>(8 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap) = value.byteCount
}

/** A printing's small picture from Scryfall's image host (no API budget); a plain blank while it loads. */
@Composable
private fun PrintingThumbnail(url: String?) {
    val context = LocalContext.current
    var bitmap by remember(url) { mutableStateOf(url?.let { thumbnails.get(it) }) }
    var failed by remember(url) { mutableStateOf(url == null) }
    LaunchedEffect(url) {
        if (url == null || bitmap != null) return@LaunchedEffect
        try {
            val bytes = io.magicmobile.android.ArtworkTransport.bytes(context, URL(url), 2 * 1024 * 1024, setOf("image/jpeg", "image/png"))
            val decoded = withContext(Dispatchers.Default) {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth in 1..1024 && bounds.outHeight in 1..1024) BitmapFactory.decodeByteArray(bytes, 0, bytes.size) else null
            }
            if (decoded != null) { thumbnails.put(url, decoded); bitmap = decoded } else failed = true
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { failed = true }
    }
    Box(Modifier.fillMaxSize().background(DeckStudioPalette.surfaceElevated), contentAlignment = Alignment.Center) {
        val image = bitmap
        if (image != null) Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        else SfImage(if (failed) "photo" else "rectangle.portrait", DeckStudioPalette.secondaryInk.copy(alpha = 0.5f), 22.dp)
    }
}
