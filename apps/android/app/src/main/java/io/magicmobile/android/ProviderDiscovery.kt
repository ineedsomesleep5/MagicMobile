package io.magicmobile.android

import android.annotation.SuppressLint
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.util.AtomicFile
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.magicmobile.android.core.Catalogue
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.ProviderCard
import io.magicmobile.android.core.ProviderDiscovery
import io.magicmobile.android.core.ProviderKind
import io.magicmobile.android.core.ScryfallPage
import io.magicmobile.android.core.SpellbookCombo
import io.magicmobile.android.core.SpellbookGroup
import io.magicmobile.android.core.SpellbookInput
import io.magicmobile.android.core.SpellbookPage
import io.magicmobile.android.core.readBounded
import io.magicmobile.android.core.singleMissingResolvedCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URI
import java.io.File
import java.security.MessageDigest
import java.util.Date
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.coroutineContext

private enum class DiscoverySource(val title: String) { SCRYFALL("Scryfall"), SPELLBOOK("Combos"), EDHREC("EDHREC") }
private sealed interface ProviderApproval {
    data class Scryfall(val query: String, val page: Int) : ProviderApproval
    data class Spellbook(val input: SpellbookInput, val offset: Int) : ProviderApproval
    data class EdhrecCommander(val name: String) : ProviderApproval
    data object EdhrecBrowse : ProviderApproval
    data class External(val uri: URI) : ProviderApproval
}

private data class ProviderReply(val key: String, val bytes: ByteArray, val cached: Boolean, val fetchedAtMillis: Long)
private data class ProviderResult<T>(val value: T, val cached: Boolean, val fetchedAtMillis: Long)
private class ProviderFailure(message: String) : IllegalStateException(message)

/** Shared with artwork so every Scryfall surface observes one app-process request budget. */
internal object ScryfallRequestBudget {
    private const val SPACING_MILLIS = 120L
    private val nextRequestAt = AtomicLong(0)
    private val blockedUntil = AtomicLong(0)
    fun awaitTurn() {
        while (true) {
            val now = System.currentTimeMillis()
            val observed = nextRequestAt.get()
            val due = maxOf(now, observed, blockedUntil.get())
            if (due - now > 2_000) throw ProviderFailure("Scryfall requests are paused after a rate limit. Retry later; no request was sent.")
            if (!nextRequestAt.compareAndSet(observed, due + SPACING_MILLIS)) continue
            if (due > now) Thread.sleep(due - now)
            if (blockedUntil.get() > System.currentTimeMillis()) throw ProviderFailure("Scryfall requests are paused after a rate limit. Retry later; no request was sent.")
            return
        }
    }
    fun backOff(seconds: Int) {
        val until = System.currentTimeMillis() + seconds.coerceIn(1, 3_600) * 1_000L
        blockedUntil.updateAndGet { maxOf(it, until) }
        nextRequestAt.updateAndGet { maxOf(it, until) }
    }
}

/** Cache directory is backup-excluded. Keys bind method, exact URL, and SHA-256 of the POST body. */
private class ProviderDiskCache(context: Context) {
    private val directory = File(context.cacheDir, "provider-discovery-v1")
    fun read(key: String): ProviderReply? {
        val file = file(key)
        if (!file.isFile || file.length() !in 1..ProviderDiscovery.MAX_RESPONSE_BYTES.toLong()) return null
        return runCatching { ProviderReply(key, file.readBytes(), true, file.lastModified()) }.getOrNull()
    }
    fun write(key: String, bytes: ByteArray, fetchedAtMillis: Long) {
        if (bytes.isEmpty() || bytes.size > ProviderDiscovery.MAX_RESPONSE_BYTES) return
        runCatching {
            directory.mkdirs()
            val atomic = AtomicFile(file(key))
            val stream = atomic.startWrite()
            try { stream.write(bytes); atomic.finishWrite(stream) } catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
            atomic.baseFile.setLastModified(fetchedAtMillis)
            prune()
        }
    }
    fun clear() { directory.listFiles()?.forEach { it.delete() } }
    fun remove(key: String) { directory.listFiles()?.filter { it.name.startsWith("$key.json") }?.forEach { it.delete() } }
    private fun file(key: String) = File(directory, "$key.json")
    private fun prune() {
        val files = directory.listFiles()?.filter { it.extension == "json" }?.sortedByDescending { it.lastModified() } ?: return
        var bytes = 0L
        files.forEachIndexed { index, file ->
            bytes += file.length()
            if (index >= 12 || bytes > 24L * 1024 * 1024) file.delete()
        }
    }
}

/** No redirects, cookies, credentials, background retries, or provider-controlled pagination. */
private class AndroidProviderClient(context: Context) {
    private val disk = ProviderDiskCache(context.applicationContext)
    private val cache = object : LinkedHashMap<String, ProviderReply>(8, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ProviderReply>?): Boolean = size > 8
    }
    private val lock = Any()
    private var spellbookNextMillis = 0L

    suspend fun searchScryfall(query: String, page: Int): ProviderResult<ScryfallPage> = withContext(Dispatchers.IO) {
        val uri = ProviderDiscovery.scryfallSearchUri(query, page)
        var response = request(uri, ProviderKind.SCRYFALL)
        coroutineContext.ensureActive()
        val parsed = runCatching { ProviderDiscovery.parseScryfallPage(response.bytes, query, page) }.getOrElse { failure ->
            if (!response.cached) throw failure
            forget(response); response = request(uri, ProviderKind.SCRYFALL, allowCache = false)
            ProviderDiscovery.parseScryfallPage(response.bytes, query, page)
        }
        remember(response)
        ProviderResult(parsed, response.cached, response.fetchedAtMillis)
    }

    suspend fun namedScryfall(name: String): ProviderResult<ProviderCard> = withContext(Dispatchers.IO) {
        val uri = ProviderDiscovery.scryfallNamedUri(name)
        var response = request(uri, ProviderKind.SCRYFALL)
        coroutineContext.ensureActive()
        val parsed = runCatching { ProviderDiscovery.parseScryfallCard(response.bytes) }.getOrElse { failure ->
            if (!response.cached) throw failure
            forget(response); response = request(uri, ProviderKind.SCRYFALL, allowCache = false)
            ProviderDiscovery.parseScryfallCard(response.bytes)
        }
        remember(response)
        ProviderResult(parsed, response.cached, response.fetchedAtMillis)
    }

    suspend fun spellbook(input: SpellbookInput, offset: Int): ProviderResult<SpellbookPage> = withContext(Dispatchers.IO) {
        val body = input.body.also { require(it.size <= ProviderDiscovery.MAX_RESPONSE_BYTES) }
        val uri = ProviderDiscovery.spellbookUri(offset)
        var response = request(uri, ProviderKind.SPELLBOOK, body)
        coroutineContext.ensureActive()
        val parsed = runCatching { ProviderDiscovery.parseSpellbookPage(response.bytes, offset) }.getOrElse { failure ->
            if (!response.cached) throw failure
            forget(response); response = request(uri, ProviderKind.SPELLBOOK, body, allowCache = false)
            ProviderDiscovery.parseSpellbookPage(response.bytes, offset)
        }
        remember(response)
        ProviderResult(parsed, response.cached, response.fetchedAtMillis)
    }

    fun clearSaved() { synchronized(lock) { cache.clear() }; disk.clear() }

    private fun request(uri: URI, kind: ProviderKind, body: ByteArray? = null, allowCache: Boolean = true): ProviderReply {
        ProviderDiscovery.requireProviderUri(uri, kind)
        val key = cacheKey(uri, body)
        if (allowCache) {
            synchronized(lock) { cache[key]?.let { return it.copy(bytes = it.bytes.copyOf(), cached = true) } }
            disk.read(key)?.let { found -> synchronized(lock) { cache[key] = found }; return found }
        }
        reserve(kind)
        var connection: HttpURLConnection? = null
        try {
            connection = (uri.toURL().openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 20_000
                readTimeout = 20_000
                useCaches = false
                setRequestProperty("Accept", "application/json")
                setRequestProperty("User-Agent", "MagicMobile-Android/0.1")
                if (body != null) {
                    requestMethod = "POST"
                    doOutput = true
                    setFixedLengthStreamingMode(body.size)
                    setRequestProperty("Content-Type", "application/json")
                }
            }
            if (body != null) connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            if (status == 429) {
                val seconds = connection.getHeaderField("Retry-After")?.toIntOrNull()?.coerceIn(1, 3_600) ?: 60
                synchronized(lock) {
                    if (kind == ProviderKind.SCRYFALL) ScryfallRequestBudget.backOff(seconds)
                    else spellbookNextMillis = System.currentTimeMillis() + seconds * 1_000L
                }
                throw ProviderFailure("$kind asked clients to wait. Retry in about $seconds seconds; no automatic retry was sent.")
            }
            if (status == 404) throw ProviderFailure("No matching provider results were found. Your deck is unchanged.")
            if (status != 200) throw ProviderFailure("The provider returned HTTP $status. Your deck is unchanged.")
            val returned = connection.url.toURI()
            ProviderDiscovery.requireProviderUri(returned, kind)
            require(returned == uri) { "Provider redirects are not followed" }
            val type = connection.contentType?.substringBefore(';')?.trim()?.lowercase()
            require(type == "application/json") { "Provider did not return JSON" }
            require(connection.contentLengthLong <= ProviderDiscovery.MAX_RESPONSE_BYTES) { "Provider response is too large" }
            val bytes = connection.inputStream.use { readBounded(it, ProviderDiscovery.MAX_RESPONSE_BYTES) }
            val fetchedAt = System.currentTimeMillis()
            return ProviderReply(key, bytes, false, fetchedAt)
        } catch (failure: ProviderFailure) {
            throw failure
        } catch (failure: Exception) {
            throw ProviderFailure(failure.message?.take(300) ?: "Provider is unavailable or offline. Local editing still works.")
        } finally {
            connection?.disconnect()
        }
    }

    private fun reserve(kind: ProviderKind) {
        if (kind == ProviderKind.SCRYFALL) { ScryfallRequestBudget.awaitTurn(); return }
        synchronized(lock) {
            val now = System.currentTimeMillis()
            if (spellbookNextMillis > now) {
                val wait = ((spellbookNextMillis - now + 999) / 1_000).coerceAtLeast(1)
                throw ProviderFailure("Please wait $wait seconds before another provider request. No request was sent.")
            }
            spellbookNextMillis = now + 2_000
        }
    }

    private fun remember(reply: ProviderReply) {
        if (reply.cached) return
        synchronized(lock) { cache[reply.key] = reply }
        disk.write(reply.key, reply.bytes, reply.fetchedAtMillis)
    }

    private fun forget(reply: ProviderReply) {
        synchronized(lock) { cache.remove(reply.key) }
        disk.remove(reply.key)
    }

    private fun cacheKey(uri: URI, body: ByteArray?): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update((if (body == null) "GET\n" else "POST\n").toByteArray())
        digest.update(uri.toASCIIString().toByteArray())
        digest.update(byteArrayOf(0))
        if (body != null) digest.update(body)
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

/**
 * Drop-in Deck Studio provider surface. Only [onAddResolvedCard] mutates caller state.
 * The callback should perform the editor's normal transaction and return false if the deck changed.
 */
@Composable
fun ProviderDiscoveryPanel(
    deck: Deck,
    catalogue: Catalogue,
    readOnly: Boolean = false,
    onAddResolvedCard: (name: String, section: String) -> Boolean,
) {
    val context = LocalContext.current
    val currentDeck by rememberUpdatedState(deck)
    val client = remember { AndroidProviderClient(context.applicationContext) }
    val scope = rememberCoroutineScope()
    var source by remember { mutableStateOf(DiscoverySource.SCRYFALL) }
    var approval by remember { mutableStateOf<ProviderApproval?>(null) }
    var activeJob by remember { mutableStateOf<Job?>(null) }
    var requestGeneration by remember { mutableStateOf(0L) }
    var loading by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var scryfall by remember { mutableStateOf<ScryfallPage?>(null) }
    var combos by remember(deck) { mutableStateOf<SpellbookPage?>(null) }
    var edhrecPage by remember { mutableStateOf<URI?>(null) }
    val spellbookInput = remember(deck, catalogue) { runCatching { SpellbookInput.from(deck, catalogue) }.getOrNull() }

    fun openExternal(uri: URI) {
        runCatching {
            ProviderDiscovery.requireExternalHttps(uri)
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString())))
        }.onFailure { message = "No safe browser is available for this HTTPS link." }
    }
    fun runApproved(action: ProviderApproval) {
        activeJob?.cancel()
        requestGeneration += 1
        val generation = requestGeneration
        loading = true
        message = null
        activeJob = scope.launch {
            runCatching {
                when (action) {
                    is ProviderApproval.Scryfall -> {
                        val (page, cached, fetchedAt) = client.searchScryfall(action.query, action.page)
                        coroutineContext.ensureActive()
                        scryfall = if (action.page == 1) page else {
                            val old = scryfall?.takeIf { it.query == page.query && it.page + 1 == page.page }
                                ?: error("Search changed before the next page returned")
                            require((old.cards.map { it.id }.toSet() intersect page.cards.map { it.id }.toSet()).isEmpty())
                            page.copy(cards = old.cards + page.cards)
                        }
                        message = if (cached) "Loaded saved Scryfall results from ${Date(fetchedAt)}." else "Scryfall results loaded. Nothing was added automatically."
                    }
                    is ProviderApproval.Spellbook -> {
                        val latest = SpellbookInput.from(currentDeck, catalogue)
                        require(latest == action.input) { "The deck changed. Review it before sending a lookup." }
                        val (page, cached, fetchedAt) = client.spellbook(action.input, action.offset)
                        coroutineContext.ensureActive()
                        combos = if (action.offset == 0) page else {
                            val old = combos ?: error("Previous results are no longer available")
                            require(old.nextOffset == action.offset)
                            val oldIds = old.groups.values.flatten().map { it.id }.toSet()
                            require((oldIds intersect page.groups.values.flatten().map { it.id }.toSet()).isEmpty())
                            val merged = SpellbookGroup.entries.associateWith { old.groups[it].orEmpty() + page.groups[it].orEmpty() }
                            page.copy(groups = merged)
                        }
                        message = if (cached) "Loaded saved Spellbook results from ${Date(fetchedAt)}." else "Commander Spellbook results loaded. XMage remains the rules authority."
                    }
                    is ProviderApproval.EdhrecCommander -> {
                        val (card, cached, fetchedAt) = client.namedScryfall(action.name)
                        coroutineContext.ensureActive()
                        val uri = card.edhrecUrl?.let(::URI) ?: error("Scryfall did not provide an EDHREC page for this commander")
                        ProviderDiscovery.requireProviderUri(uri, ProviderKind.EDHREC)
                        edhrecPage = uri
                        message = if (cached) "Resolved the saved public commander link from ${Date(fetchedAt)}." else "Opened the public commander page. No deck was sent."
                    }
                    ProviderApproval.EdhrecBrowse -> edhrecPage = URI("https://edhrec.com/commanders")
                    is ProviderApproval.External -> openExternal(action.uri)
                }
            }.onFailure { failure ->
                if (failure !is kotlinx.coroutines.CancellationException) message = failure.message ?: "Provider lookup failed. Your deck is unchanged."
            }
            if (requestGeneration == generation) loading = false
        }
    }
    DisposableEffect(Unit) { onDispose { activeJob?.cancel() } }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Explore ideas", style = MaterialTheme.typography.titleLarge)
        Text("Online tools are optional. Every request needs a deliberate tap and never changes your deck automatically.", style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DiscoverySource.entries.forEach { value ->
                FilterChip(selected = source == value, onClick = { source = value; message = null }, label = { Text(value.title) })
            }
        }
        message?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        TextButton(onClick = {
            activeJob?.cancel(); requestGeneration += 1; loading = false
            client.clearSaved(); scryfall = null; combos = null; message = "Saved provider results cleared."
        }, enabled = !loading) { Text("Clear saved provider results") }
        when (source) {
            DiscoverySource.SCRYFALL -> ScryfallProviderContent(query, { query = it.take(1_024) }, scryfall, loading, readOnly,
                search = { approval = ProviderApproval.Scryfall(query, 1) },
                more = { page -> approval = ProviderApproval.Scryfall(page.query, page.page + 1) },
                open = { approval = ProviderApproval.External(it) },
                add = { name, section ->
                    val canonical = catalogue.find(name)?.name
                    if (canonical == null) { message = "$name is not in this build’s XMage catalogue, so it was not added."; false }
                    else onAddResolvedCard(canonical, section).also { message = if (it) "Added $canonical. Undo is available in Cards." else "The deck changed or the edit could not be saved." }
                })
            DiscoverySource.SPELLBOOK -> SpellbookProviderContent(spellbookInput, combos, catalogue, loading, readOnly,
                lookup = { input, offset -> approval = ProviderApproval.Spellbook(input, offset) },
                add = { name, section -> onAddResolvedCard(name, section).also { message = if (it) "Added $name. Undo is available in Cards." else "The deck changed or the edit could not be saved." } },
                open = { approval = ProviderApproval.External(it) })
            DiscoverySource.EDHREC -> EdhrecProviderContent(deck, catalogue, loading, edhrecPage,
                commander = { approval = ProviderApproval.EdhrecCommander(it) },
                browse = { approval = ProviderApproval.EdhrecBrowse },
                close = { edhrecPage = null },
                external = { approval = ProviderApproval.External(it) })
        }
    }

    approval?.let { pending ->
        val disclosure = when (pending) {
            is ProviderApproval.Scryfall -> "Scryfall will receive this search text and your network address. Your deck title, notes, and decklist stay on this device."
            is ProviderApproval.Spellbook -> "Commander Spellbook will receive resolved main-deck and commander names, quantities, and your network address. Other sections, title, and private notes stay here."
            is ProviderApproval.EdhrecCommander -> "Scryfall will receive the commander name to resolve its public EDHREC link. EDHREC and your browser will then receive normal page requests and your network address. No deck is sent."
            ProviderApproval.EdhrecBrowse -> "This opens the public EDHREC website in a temporary in-app session. MagicMobile does not read recommendations, fill forms, or send your deck."
            is ProviderApproval.External -> "This leaves the current provider for another HTTPS website in your browser. MagicMobile does not attach your deck or private notes."
        }
        AlertDialog(onDismissRequest = { approval = null }, title = { Text("Continue online?") }, text = { Text(disclosure) },
            confirmButton = { Button(onClick = { approval = null; runApproved(pending) }) { Text("Continue") } },
            dismissButton = { TextButton(onClick = { approval = null }) { Text("Cancel") } })
    }
}

@Composable
private fun ScryfallProviderContent(
    query: String,
    update: (String) -> Unit,
    page: ScryfallPage?,
    loading: Boolean,
    readOnly: Boolean,
    search: () -> Unit,
    more: (ScryfallPage) -> Unit,
    open: (URI) -> Unit,
    add: (String, String) -> Boolean,
) {
    var selected by remember(page?.query) { mutableStateOf<ProviderCard?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Search Scryfall’s public card reference. Results must also exist in the installed XMage catalogue before they can be added.", style = MaterialTheme.typography.bodySmall)
        OutlinedTextField(value = query, onValueChange = update, label = { Text("Card search") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Button(onClick = search, enabled = query.isNotBlank() && !loading) { Text(if (loading) "Searching…" else "Search Scryfall") }
        page?.cards.orEmpty().forEach { card ->
            OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(card.name, style = MaterialTheme.typography.titleMedium)
                Text(listOfNotNull(card.manaCost, card.typeLine).joinToString(" · "), style = MaterialTheme.typography.bodySmall)
                card.oracleText?.let { Text(it, maxLines = 5, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall) }
                TextButton(onClick = { selected = card }) { Text("Read full reference") }
                if (!readOnly) Row { TextButton(onClick = { add(card.name, "deck") }) { Text("Add to main") }; TextButton(onClick = { add(card.name, "maybeboard") }) { Text("Maybeboard") } }
            } }
        }
        if (page?.hasMore == true && page.page < 10) OutlinedButton(onClick = { more(page) }, enabled = !loading) { Text("Load next page") }
    }
    selected?.let { card ->
        AlertDialog(onDismissRequest = { selected = null }, title = { Text(card.name) }, text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Scryfall reference · from these search results. Current text and legality may differ from the installed XMage version; this never changes the rules engine.", style = MaterialTheme.typography.bodySmall)
                CardArtwork(card.name,Modifier.fillMaxWidth().height(240.dp)) { Text("Artwork unavailable",style=MaterialTheme.typography.labelSmall) }
                card.manaCost?.let { ManaCost(it) }
                card.typeLine?.let { Text(it, style = MaterialTheme.typography.titleSmall) }
                if (card.faces.isEmpty()) card.oracleText?.let { Text(it) }
                card.faces.forEach { face ->
                    HorizontalDivider()
                    Text(face.name, style = MaterialTheme.typography.titleMedium)
                    face.manaCost?.let { ManaCost(it) }
                    face.typeLine?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                    face.oracleText?.let { Text(it) }
                }
                card.commanderLegality?.let { Text("Scryfall Commander status: $it", style = MaterialTheme.typography.bodySmall) }
                card.scryfallUrl?.let { url -> TextButton(onClick = { selected = null; open(URI(url)) }) { Text("View on Scryfall") } }
            }
        }, confirmButton = { TextButton(onClick = { selected = null }) { Text("Done") } })
    }
}

@Composable
private fun SpellbookProviderContent(
    input: SpellbookInput?,
    page: SpellbookPage?,
    catalogue: Catalogue,
    loading: Boolean,
    readOnly: Boolean,
    lookup: (SpellbookInput, Int) -> Unit,
    add: (String, String) -> Boolean,
    open: (URI) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Documented interactions from Commander Spellbook.", style = MaterialTheme.typography.bodySmall)
        Button(onClick = { input?.let { lookup(it, 0) } }, enabled = input != null && !loading) { Text(if (loading) "Looking up…" else "Find combos") }
        if (input == null) Text("Resolve every main-deck card and choose a commander before looking up combos.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        page?.let { result ->
            Text("${result.loadedCount} results loaded", style = MaterialTheme.typography.titleMedium)
            SpellbookGroup.entries.forEach { group ->
                val rows = result.groups[group].orEmpty()
                if (rows.isNotEmpty()) {
                    Text("${group.title} · ${rows.size}", style = MaterialTheme.typography.titleSmall)
                    rows.forEach { combo -> SpellbookComboCard(combo, input, catalogue, readOnly, add, open) }
                }
            }
            result.nextOffset?.let { offset ->
                if (result.loadedCount < ProviderDiscovery.SPELLBOOK_MAX_RESULTS) OutlinedButton(onClick = { input?.let { lookup(it, offset) } }, enabled = !loading) { Text("Load next page") }
            }
            DeckExplanation("About these results", "XMage remains the rules authority. Named pieces, provider legality and color identity do not establish mana, zones, timing or a winning line.")
        }
    }
}

@Composable
private fun SpellbookComboCard(
    combo: SpellbookCombo,
    input: SpellbookInput?,
    catalogue: Catalogue,
    readOnly: Boolean,
    add: (String, String) -> Boolean,
    open: (URI) -> Unit,
) {
    OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            combo.ingredients.forEach { ingredient ->
                Column(Modifier.width(100.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    CardArtwork(catalogue.find(ingredient.name)?.name ?: ingredient.name, Modifier.width(100.dp).height(140.dp)) {
                        Text("Artwork unavailable", style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(6.dp))
                    }
                    Text(ingredient.name, style = MaterialTheme.typography.labelLarge)
                    Text("×${ingredient.quantity}", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        combo.produces.take(4).forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
        val missing = input?.let { combo.singleMissingResolvedCard(it, catalogue) }
        Text(if (missing == null) "Review requirements" else "One resolved card away: $missing", style = MaterialTheme.typography.bodySmall)
        var expanded by remember(combo.id) { mutableStateOf(false) }
        TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Hide prerequisites and steps" else "Prerequisites and steps") }
        if (expanded) {
            Text("Before you begin", style = MaterialTheme.typography.titleSmall)
            if (combo.manaNeeded.isNotBlank()) Text("Mana: ${combo.manaNeeded}")
            combo.ingredients.forEach { ingredient ->
                val zones = ingredient.zoneLocations.map { zone -> mapOf("B" to "Battlefield", "H" to "Hand", "G" to "Graveyard", "E" to "Exile", "L" to "Library", "C" to "Command zone")[zone] ?: zone }
                Text("${ingredient.quantity} × ${ingredient.name}", style = MaterialTheme.typography.labelLarge)
                val requirements = zones + listOfNotNull(if (ingredient.mustBeCommander) "Must be your commander" else null) +
                    listOf(ingredient.battlefieldCardState, ingredient.exileCardState, ingredient.libraryCardState, ingredient.graveyardCardState).filter { it.isNotBlank() }
                if (requirements.isNotEmpty()) Text(requirements.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
            }
            if (combo.easyPrerequisites.isNotBlank()) { Text("Prerequisites",style=MaterialTheme.typography.labelLarge);Text(combo.easyPrerequisites) }
            if (combo.notablePrerequisites.isNotBlank()) { Text("Additional prerequisites",style=MaterialTheme.typography.labelLarge);Text(combo.notablePrerequisites) }
            combo.requirements.forEach { requirement ->
                Text("Flexible requirement: ${requirement.quantity} × ${requirement.name}", style = MaterialTheme.typography.labelLarge)
                val zones = requirement.zoneLocations.map { zone -> mapOf("B" to "Battlefield", "H" to "Hand", "G" to "Graveyard", "E" to "Exile", "L" to "Library", "C" to "Command zone")[zone] ?: zone }
                val details = zones + listOfNotNull(if (requirement.mustBeCommander) "Must be your commander" else null) +
                    listOf(requirement.battlefieldCardState, requirement.exileCardState, requirement.libraryCardState, requirement.graveyardCardState).filter { it.isNotBlank() }
                if (details.isNotEmpty()) Text(details.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
            }
            if (combo.description.isNotBlank()) {
                Text("Steps", style = MaterialTheme.typography.titleSmall)
                combo.description.lines().filter { it.isNotBlank() }.forEachIndexed { index, step ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("${index + 1}.", style = MaterialTheme.typography.labelLarge)
                        Text(step.replaceFirst(Regex("^\\s*\\d+[.)]\\s+"), ""), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            } else Text("Steps are available on Commander Spellbook.", style = MaterialTheme.typography.bodySmall)
            Text("Results", style = MaterialTheme.typography.titleSmall)
            combo.produces.forEach { Text(it) }
            if (combo.notes.isNotBlank()) DeckExplanation("Notes", combo.notes)
        }
        Row { TextButton(onClick = { open(combo.websiteUri) }) { Text("Details ↗") }
            if (missing != null && !readOnly) { Spacer(Modifier.width(8.dp)); TextButton(onClick = { add(missing, "deck") }) { Text("Add to main") }; TextButton(onClick = { add(missing, "maybeboard") }) { Text("Maybeboard") } }
        }
    } }
}

@Composable
private fun EdhrecProviderContent(
    deck: Deck,
    catalogue: Catalogue,
    loading: Boolean,
    page: URI?,
    commander: (String) -> Unit,
    browse: () -> Unit,
    close: () -> Unit,
    external: (URI) -> Unit,
) {
    val commanders = deck.entries.filter { it.section == "commanders" }.mapNotNull { catalogue.find(it.name)?.name }.distinct()
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Open the actual EDHREC website without uploading your deck. Commander buttons ask Scryfall for that card’s public EDHREC link; MagicMobile does not invent slugs or scrape recommendations.", style = MaterialTheme.typography.bodySmall)
        if (page == null) {
            commanders.forEach { name -> OutlinedButton(onClick = { commander(name) }, enabled = !loading, modifier = Modifier.fillMaxWidth()) { Text("Open $name on EDHREC") } }
            OutlinedButton(onClick = browse, enabled = !loading) { Text("Browse commanders on EDHREC") }
        } else {
            SafeEdhrecBrowser(page, close, external)
        }
        HorizontalDivider()
        Text("Use EDHREC’s own partner and recommendation controls on the website. Anything you choose to paste or submit there is handled by that website.", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(2.dp))
    }
}

/** Temporary, allowlisted website session. It never inspects DOM content or injects scripts. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun SafeEdhrecBrowser(initial: URI, close: () -> Unit, external: (URI) -> Unit) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var current by remember(initial) { mutableStateOf(initial) }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        TextButton(onClick = { webView?.takeIf { it.canGoBack() }?.goBack() }) { Text("Back") }
        TextButton(onClick = { webView?.reload() }) { Text("Reload") }
        TextButton(onClick = { external(current) }) { Text("Browser ↗") }
        TextButton(onClick = close) { Text("Clear session") }
    }
    AndroidView(factory = { context ->
        WebView(context).apply {
            webView = this
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.cacheMode = WebSettings.LOAD_NO_CACHE
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = runCatching { URI(request.url.toString()) }.getOrNull() ?: return true
                    return if (runCatching { ProviderDiscovery.requireProviderUri(uri, ProviderKind.EDHREC) }.isSuccess) {
                        current = uri
                        false
                    } else {
                        if (request.hasGesture() && runCatching { ProviderDiscovery.requireExternalHttps(uri) }.isSuccess) external(uri)
                        true
                    }
                }
            }
            loadUrl(initial.toString())
        }
    }, update = { view ->
        if (view.url == null) view.loadUrl(initial.toString())
    }, modifier = Modifier.fillMaxWidth().heightIn(min = 420.dp, max = 680.dp))
    DisposableEffect(Unit) {
        onDispose {
            webView?.run { stopLoading(); clearHistory(); clearCache(true); loadUrl("about:blank"); destroy() }
            webView = null
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        }
    }
}
