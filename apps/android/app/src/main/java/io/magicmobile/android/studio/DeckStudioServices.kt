package io.magicmobile.android.studio

import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.core.readBounded
import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.EngineTransport
import io.magicmobile.android.game.J
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import io.magicmobile.android.ondevice.OnDeviceRuntimeManager
import io.magicmobile.android.ui.AppPreferences
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Deck Studio's small string payloads live in the app's preferences, as UserDefaults on iOS. */
class AndroidStudioDefaults(private val prefs: () -> SharedPreferences?) : StudioDefaults {
    override fun string(key: String): String? = runCatching { prefs()?.getString(key, null) }.getOrNull()
    override fun set(key: String, value: String) { prefs()?.edit()?.putString(key, value)?.apply() }
    override fun remove(key: String) { prefs()?.edit()?.remove(key)?.apply() }
    override fun keys(): Set<String> = prefs()?.all?.keys ?: emptySet()
}

/** One place for the studio's stores, shared by the library, workspace and game recording. */
object DeckStudioServices {
    lateinit var appContext: Context; private set
    val defaults: StudioDefaults = AndroidStudioDefaults { AppPreferences.raw() }
    val organization: DeckStudioOrganizationStore by lazy {
        DeckStudioOrganizationStore(File(appContext.filesDir, "MagicMobile-DeckDetails"), File(appContext.filesDir, "MagicMobile/DeckStudio/ImportReceipts"))
    }
    val playtests: DeckStudioPlaytestStore by lazy {
        DeckStudioPlaytestStore(File(appContext.filesDir, "MagicMobile-Playtests/summaries-v1.json"), defaults)
    }
    val spellbook by lazy { CommanderSpellbookClient(File(appContext.cacheDir, "MagicMobile-Spellbook-v1")) }
    val scryfall by lazy { DeckStudioScryfallClient(File(appContext.cacheDir, "DeckStudio-Scryfall-v1")) }
    val appBuild: String get() = BuildConfig.VERSION_CODE.toString()

    fun install(context: Context) { if (!::appContext.isInitialized) appContext = context.applicationContext }
}

/** Bounded HTTPS: no cookies, redirects or retries; exact URL, JSON type and size (SpellbookURLSessionTransport). */
object StudioHTTP {
    class HttpFailure(val status: Int, val retryAfter: Int?) : Exception("HTTP $status")
    class TooLarge : Exception("Response too large")
    class Unexpected : Exception("Unexpected response")

    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()

    suspend fun request(url: String, maximumBytes: Int, body: String? = null, userAgent: String = "MagicMobile-DeckStudio/2.0"): String = withContext(Dispatchers.IO) {
        val expected = url.toHttpUrl()
        val builder = Request.Builder().url(expected).header("Accept", "application/json").header("User-Agent", userAgent)
        if (body != null) builder.post(body.toRequestBody("application/json".toMediaType()))
        val call = client.newCall(builder.build())
        val job = coroutineContext[Job]
        val registration = job?.invokeOnCompletion { if (it != null) call.cancel() }
        try {
            call.execute().use { response ->
                if (response.request.url != expected) throw Unexpected()
                if (response.code == 429) throw HttpFailure(429, response.header("Retry-After")?.toIntOrNull())
                if (response.code != 200) throw HttpFailure(response.code, null)
                val type = response.body?.contentType()?.let { "${it.type}/${it.subtype}".lowercase() }
                if (type != "application/json") throw Unexpected()
                val length = response.body?.contentLength() ?: -1
                if (length > maximumBytes) throw TooLarge()
                val stream = response.body?.byteStream() ?: throw Unexpected()
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(16_384)
                while (true) {
                    coroutineContext.ensureActive()
                    val count = stream.read(buffer); if (count < 0) break
                    if (out.size() + count > maximumBytes) throw TooLarge()
                    out.write(buffer, 0, count)
                }
                String(out.toByteArray(), Charsets.UTF_8)
            }
        } finally { registration?.dispose() }
    }
}

/**
 * A transparent observer of successful local-native responses (DeckStudioRecordingTransport.swift).
 * It never changes requests, replies, retries, errors or seat routing, and is not installed on peers.
 */
class DeckStudioRecordingTransport(private val base: EngineTransport, private val store: DeckStudioPlaytestStore = DeckStudioServices.playtests,
                                   private val appBuild: String = DeckStudioServices.appBuild) : EngineTransport {
    private val lock = Mutex()
    private var admission: DeckStudioPlaytestStore.Admission? = null
    private val accumulator = DeckStudioPlaytestAccumulator()
    private var lastSaved = 0L

    override suspend fun request(data: ByteArray): ByteArray {
        val request = runCatching { EngineJson.decode(data) }.getOrNull()
        val op = request["op"].string
        if (op == "create" && admission == null) admission = runCatching { store.admission() }.getOrNull()
        val reply = base.request(data)
        val admission = admission
        if (admission != null && admission.enabled && request != null) {
            runCatching {
                lock.withLock {
                    val now = System.currentTimeMillis()
                    val detailed = admission.detailedEnabled && store.detailedEnabled()
                    val response = EngineJson.decode(reply)
                    if (accumulator.observe(request, response, true, appBuild, now, detailed) { io.magicmobile.android.core.Decisions.plain(it) }) {
                        val game = accumulator.game
                        if (game != null && (op == "create" || game.end != DeckStudioRecordedGame.End.IN_PROGRESS || now - lastSaved >= 15_000)) {
                            withContext(Dispatchers.IO) { store.record(game, admission) }
                            lastSaved = now
                        }
                    }
                }
            }
        }
        return reply
    }

    suspend fun runtimeClosed() {
        val admission = admission ?: return
        val value = lock.withLock { accumulator.close(System.currentTimeMillis()) } ?: return
        withContext(Dispatchers.IO) { runCatching { store.record(value, admission) } }
    }
}

/** Kept alive for cleanup retries; never validates by starting a sacrificial game (DeckStudioValidationService.swift). */
object DeckStudioValidationService {
    var busy by mutableStateOf(false); private set
    var cleanupRequired by mutableStateOf(false); private set
    private val runtime = OnDeviceRuntimeManager()

    suspend fun validate(deck: J, resolver: OnDeviceDeckResolver): DeckStudioValidationReceipt {
        if (busy || cleanupRequired || runtime.isOpen) throw EngineError.InvalidMessage("Wait for validation or retry its cleanup before checking another deck")
        busy = true
        try {
            val identity = BuildIdentity(resolver.upstreamCommit, resolver.catalogueHash)
            val request = String(EngineJson.encode(deck), Charsets.UTF_8)
            val result = runCatching {
                coroutineContext.ensureActive()
                val client = runtime.makeClient(identity, observePlaytests = false)
                if (runtime.capabilities["deckValidation"].bool != true) {
                    throw EngineError.InvalidMessage("Update MagicMobile to validate this deck. Your draft is saved separately and has not been marked legal.")
                }
                coroutineContext.ensureActive()
                try {
                    val report = client.call("validateDeck", mapOf("deck" to deck))
                    DeckStudioValidationReceipt.success(report, request, resolver.upstreamCommit, resolver.catalogueHash, DeckStudioServices.appBuild)
                } catch (error: EngineError.RejectionDetails) {
                    if (error.code != "invalid_deck") throw error
                    DeckStudioValidationReceipt.rejection(error.details, error.text, request, resolver.upstreamCommit, resolver.catalogueHash, DeckStudioServices.appBuild)
                }
            }
            try { runtime.close(); cleanupRequired = false }
            catch (error: Exception) {
                cleanupRequired = runtime.isOpen
                throw EngineError.InvalidMessage("The rules engine is still closing. Tap Finish closing before trying again. Your deck is unchanged.")
            }
            coroutineContext.ensureActive()
            return result.getOrThrow()
        } finally { busy = false }
    }

    suspend fun retryCleanup() {
        if (busy) throw EngineError.InvalidMessage("Wait for the current validation operation")
        busy = true
        try { runtime.close(); cleanupRequired = runtime.isOpen } finally { busy = false }
    }
}

/** DeckStudioValidationState.swift: one pending check per draft request. */
class DeckStudioValidationState(private val scope: CoroutineScope) {
    var receipt by mutableStateOf<DeckStudioValidationReceipt?>(null); private set
    var checking by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    private var request: String? = null
    private var token = UUID.randomUUID()
    private var job: Job? = null

    fun prepare(deck: J?) {
        val data = deck?.let { runCatching { String(EngineJson.encode(it), Charsets.UTF_8) }.getOrNull() }
        if (data == request) return
        cancelPending(); request = data; receipt = null; error = null
    }

    fun cancelPending() { token = UUID.randomUUID(); job?.cancel(); job = null; checking = false }

    fun validate(deck: J, resolver: OnDeviceDeckResolver) {
        prepare(deck)
        if (checking) return
        val captured = UUID.randomUUID(); token = captured; checking = true; receipt = null; error = null
        job = scope.launch {
            try {
                val value = DeckStudioValidationService.validate(deck, resolver)
                if (token != captured) return@launch
                receipt = value; checking = false; job = null
            } catch (cancelled: CancellationException) {
                if (token == captured) { checking = false; job = null }
            } catch (failure: Exception) {
                if (token != captured) return@launch
                checking = false; job = null; error = failure.message
            }
        }
    }
}

/** Commander Spellbook: every network request needs an explicit user action. Cache reads never send a deck. */
class CommanderSpellbookClient(private val directory: File?) {
    data class Lookup(val snapshot: SpellbookSnapshot, val savedToDisk: Boolean)

    private val memory = LinkedHashMap<String, SpellbookSnapshot>()
    private var nextAllowed = 0L
    private var requesting = false
    private var cacheGeneration = 0L

    @Synchronized fun cached(deck: SpellbookDeck): SpellbookSnapshot? {
        val key = deck.encoded()
        memory[key]?.let { return it }
        val file = cacheFile(key) ?: return null
        if (!file.isFile || file.length() > maximumCacheBytes) return null
        val snapshot = runCatching { SpellbookSnapshot.decode(Json.parseToJsonElement(file.readText())).also { it.validate(deck) } }.getOrNull() ?: return null
        remember(snapshot, key)
        return snapshot
    }

    @Synchronized fun clearCache() {
        cacheGeneration += 1
        memory.clear()
        directory?.listFiles()?.filter { it.name.startsWith("lookup-") && it.name.endsWith(".json") }?.forEach { it.delete() }
    }

    suspend fun lookup(deck: SpellbookDeck, previous: SpellbookSnapshot? = null): Lookup {
        val generation: Long
        val offset: Int
        synchronized(this) {
            if (requesting) throw SpellbookError.RateLimited(2)
            val wait = nextAllowed - System.currentTimeMillis()
            if (wait > 0) throw SpellbookError.RateLimited(maxOf(1, ((wait + 999) / 1000).toInt()))
            if (SpellbookDeck(deck.main, deck.commanders) != deck) throw SpellbookError.InvalidDeck
            offset = if (previous != null) {
                previous.validate(deck)
                val next = previous.nextOffset
                if (previous.loadedCount >= SpellbookAPI.maximumResults || next == null || next in previous.offsets) throw SpellbookError.TooManyResults
                next
            } else 0
            generation = cacheGeneration
            requesting = true; nextAllowed = System.currentTimeMillis() + 2000
        }
        try {
            val text = try { StudioHTTP.request(SpellbookAPI.pageURL(offset), SpellbookAPI.maximumResponseBytes, deck.encoded()) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: StudioHTTP.HttpFailure) {
                if (failure.status == 429) {
                    val seconds = (failure.retryAfter ?: 60).coerceIn(1, 3600)
                    synchronized(this) { nextAllowed = System.currentTimeMillis() + seconds * 1000L }
                    throw SpellbookError.RateLimited(seconds)
                }
                throw SpellbookError.HttpStatus(failure.status)
            }
            catch (failure: StudioHTTP.TooLarge) { throw SpellbookError.ResponseTooLarge }
            catch (failure: StudioHTTP.Unexpected) { throw SpellbookError.InvalidResponse }
            catch (failure: Exception) { throw SpellbookError.Unavailable }
            coroutineContext.ensureActive()
            val page = SpellbookPage.decode(text)
            val next = SpellbookAPI.nextOffset(page.next, offset)
            val snapshot = SpellbookSnapshot.merged(deck, previous, page, offset, next, System.currentTimeMillis())
            synchronized(this) {
                // A clear or cancellation during the request must not repopulate the cache.
                if (generation != cacheGeneration) throw CancellationException("Cache cleared")
                val key = deck.encoded()
                remember(snapshot, key)
                return Lookup(snapshot, store(snapshot, key))
            }
        } finally { synchronized(this) { requesting = false } }
    }

    private fun remember(snapshot: SpellbookSnapshot, key: String) {
        memory[key] = snapshot
        while (memory.size > 8) memory.minByOrNull { it.value.fetchedAt }?.key?.let(memory::remove) ?: break
    }

    private fun cacheFile(key: String): File? {
        var hash = -0x340d631b7bdddcdbL
        for (byte in key.toByteArray(Charsets.UTF_8)) hash = (hash xor (byte.toLong() and 0xff)) * 1099511628211L
        return directory?.let { File(it, "lookup-${java.lang.Long.toUnsignedString(hash, 16)}.json") }
    }

    private fun store(snapshot: SpellbookSnapshot, key: String): Boolean = runCatching {
        val directory = directory ?: return false
        val data = snapshot.json().toString().toByteArray(Charsets.UTF_8)
        if (data.size > maximumCacheBytes) return false
        directory.mkdirs()
        val file = cacheFile(key) ?: return false
        val temporary = File(directory, file.name + ".tmp"); temporary.writeBytes(data)
        if (!temporary.renameTo(file)) { temporary.delete(); return false }
        directory.listFiles()?.filter { it.name.startsWith("lookup-") && it.name.endsWith(".json") }?.sortedByDescending { it.lastModified() }
            ?.drop(8)?.forEach { it.delete() }
        true
    }.getOrDefault(false)

    companion object { const val maximumCacheBytes = 8 * 1024 * 1024 }
}

/** Scryfall reference lookups: paced, never retried automatically, cached on the device. */
class DeckStudioScryfallClient(private val directory: File?) {
    data class CachedCard(val card: DeckStudioScryfallCard, val fetchedAt: Long, val cached: Boolean)
    private data class Entry(val key: String, val date: Long, val data: String)

    private val lock = Mutex()
    private val cache = LinkedHashMap<String, Entry>()
    private var generation = UUID.randomUUID()

    suspend fun named(name: String, allowNetwork: Boolean, refresh: Boolean = false): CachedCard? {
        val entry = data(DeckStudioScryfallRequests.url(name), allowNetwork, refresh) ?: return null
        return try { CachedCard(DeckStudioScryfallRequests.decodeCard(entry.first.data), entry.first.date, entry.second) }
        catch (error: Exception) { throw DeckStudioScryfallError.InvalidResponse }
    }

    suspend fun search(query: String, page: Int = 1, allowNetwork: Boolean, refresh: Boolean = false): DeckStudioScryfallPage? {
        val entry = data(DeckStudioScryfallRequests.url(query, page), allowNetwork, refresh) ?: return null
        val (cards, more) = try { DeckStudioScryfallRequests.decodeList(entry.first.data) } catch (error: Exception) { throw DeckStudioScryfallError.InvalidResponse }
        return DeckStudioScryfallPage(cards, more, page, query, entry.first.date, entry.second)
    }

    private suspend fun data(url: String, allowNetwork: Boolean, refresh: Boolean): Pair<Entry, Boolean>? {
        coroutineContext.ensureActive()
        if (!refresh) read(url)?.let { return it to true }
        if (!allowNetwork) return null
        val token = generation
        return lock.withLock {
            if (token != generation) throw CancellationException("Cleared")
            if (!refresh) read(url)?.let { return@withLock it to true }
            ScryfallBudget.reserve()
            val text = try { StudioHTTP.request(url, 4 * 1024 * 1024) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: StudioHTTP.HttpFailure) {
                if (failure.status == 429) { ScryfallBudget.backOff((failure.retryAfter ?: 30).toLong()); throw DeckStudioScryfallError.RateLimited }
                throw DeckStudioScryfallError.Http(failure.status)
            }
            catch (failure: StudioHTTP.TooLarge) { throw DeckStudioScryfallError.TooLarge }
            catch (failure: Exception) { throw DeckStudioScryfallError.Unavailable }
            coroutineContext.ensureActive()
            if (token != generation) throw CancellationException("Cleared")
            if (url.contains("/cards/named")) DeckStudioScryfallRequests.decodeCard(text) else DeckStudioScryfallRequests.decodeList(text)
            val entry = Entry(url, System.currentTimeMillis(), text)
            cache[url] = entry
            if (cache.size > 4) cache.minByOrNull { it.value.date }?.key?.let(cache::remove)
            store(entry)
            entry to false
        }
    }

    private fun file(key: String): File? {
        var hash = -0x340d631b7bdddcdbL
        for (byte in key.toByteArray(Charsets.UTF_8)) hash = (hash xor (byte.toLong() and 0xff)) * 1099511628211L
        return directory?.let { File(it, "response-${java.lang.Long.toUnsignedString(hash, 16)}.json") }
    }

    private fun read(key: String): Entry? {
        cache[key]?.let { return it }
        val file = file(key)?.takeIf { it.isFile && it.length() <= 6 * 1024 * 1024 } ?: return null
        return runCatching {
            val value = Json.parseToJsonElement(file.readText())
            val entry = Entry(value["key"].string!!, (value["date"] as kotlinx.serialization.json.JsonPrimitive).content.toLong(), value["data"].string!!)
            entry.takeIf { it.key == key && it.data.length <= 4 * 1024 * 1024 }
        }.getOrNull()
    }

    private fun store(entry: Entry) {
        val directory = directory ?: return
        runCatching {
            directory.mkdirs()
            val file = file(entry.key) ?: return
            file.writeText(JsonObject(mapOf("schema" to kotlinx.serialization.json.JsonPrimitive(1), "key" to kotlinx.serialization.json.JsonPrimitive(entry.key),
                "date" to kotlinx.serialization.json.JsonPrimitive(entry.date), "data" to kotlinx.serialization.json.JsonPrimitive(entry.data))).toString())
            directory.listFiles()?.filter { it.name.startsWith("response-") }?.sortedByDescending { it.lastModified() }?.drop(12)?.forEach { it.delete() }
        }
    }

    /** Shared request spacing: at most one request every 0.55 s, and a back-off after a rate limit. */
    private object ScryfallBudget {
        private var next = 0L
        private var blocked = 0L
        suspend fun reserve() {
            while (true) {
                coroutineContext.ensureActive()
                val now = android.os.SystemClock.elapsedRealtime()
                if (now < blocked) throw DeckStudioScryfallError.RateLimited
                if (now >= next) { next = now + 550; return }
                delay(minOf(1000L, next - now))
            }
        }
        fun backOff(seconds: Long) { blocked = maxOf(blocked, android.os.SystemClock.elapsedRealtime() + seconds.coerceIn(30, 3600) * 1000) }
    }
}

/** The link importer's network half: public provider endpoints, no cookies or redirects. */
suspend fun OnDeviceDeckLinkImporter.importDeck(url: String, excludeSideboards: Boolean = false, reviewOnly: Boolean = false): DeckList {
    val source = OnDeviceDeckLinkImporter.source(url)
    val text = try { StudioHTTP.request(source.endpoint, OnDeviceDeckLinkImporter.maximumBytes, userAgent = "MagicMobile-DeckImport/1.0") }
    catch (cancelled: CancellationException) { throw cancelled }
    catch (failure: StudioHTTP.HttpFailure) {
        throw OnDeviceDeckLinkImporter.ImportError("Provider unavailable (HTTP ${failure.status}); private decks, authentication, redirects and bot checks are not supported.")
    }
    catch (failure: StudioHTTP.TooLarge) { throw OnDeviceDeckLinkImporter.ImportError("Provider response exceeds 2 MiB.") }
    catch (failure: StudioHTTP.Unexpected) { throw OnDeviceDeckLinkImporter.ImportError("Provider response is oversized or is not JSON.") }
    catch (failure: Exception) { throw OnDeviceDeckLinkImporter.ImportError("Provider unavailable, timed out, or returned an unsupported response.") }
    return decode(text, source, excludeSideboards, reviewOnly)
}

/** On-device text recognition for a decklist photo. The image never leaves the phone. */
object DeckStudioOCR {
    suspend fun recognize(context: Context, uri: Uri): String = withContext(Dispatchers.IO) {
        val bytes = context.contentResolver.openInputStream(uri)?.use { readBounded(it, 20 * 1024 * 1024) }
            ?: throw ResolutionError("Could not read the chosen image.")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth !in 1..20_000 || bounds.outHeight !in 1..20_000 || bounds.outWidth.toLong() * bounds.outHeight > 80_000_000L) {
            throw ResolutionError("The image is unsupported or too large to read safely.")
        }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 3000) sample *= 2
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw ResolutionError("The image is unsupported or too large to read safely.")
        val exif = runCatching { ExifInterface(bytes.inputStream()) }.getOrNull()
        val transform = Matrix().apply { if (exif?.isFlipped == true) postScale(-1f, 1f); postRotate((exif?.rotationDegrees ?: 0).toFloat()) }
        val oriented = android.graphics.Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true)
        if (oriented !== bitmap) bitmap.recycle()
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val text = suspendCancellableCoroutine<String> { continuation ->
            recognizer.process(InputImage.fromBitmap(oriented, 0))
                .addOnSuccessListener { result -> if (continuation.isActive) continuation.resume(result.text) }
                .addOnFailureListener { failure -> if (continuation.isActive) continuation.resumeWithException(failure) }
                .addOnCompleteListener { recognizer.close(); oriented.recycle() }
        }
        if (text.isBlank() || text.toByteArray().size > OnDeviceDeckLinkImporter.maximumBytes) {
            throw ResolutionError("No usable decklist text was found. Try a clearer image or paste an export.")
        }
        text
    }
}

/** A long-lived scope for store writes that must finish after a screen closes. */
internal val studioScope: CoroutineScope = MainScope()
