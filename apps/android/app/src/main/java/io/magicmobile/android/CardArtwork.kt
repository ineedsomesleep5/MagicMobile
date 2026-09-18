package io.magicmobile.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong

/**
 * Card artwork on the same terms as the iOS build: opt-in, Scryfall only, bounded, and
 * cached on the device. Declining leaves every other feature working; rules text and deck
 * building never need the network.
 */
object Artwork {
    private const val PREFS = "magicmobile.artwork"
    private const val CONSENT_KEY = "magicmobile.deckArtworkNetworkEnabled"
    private const val MAX_BYTES = 2 * 1024 * 1024
    private val ALLOWED_HOSTS = setOf("api.scryfall.com", "cards.scryfall.io")
    private const val REQUEST_SPACING_MS = 120L

    private val memory = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    private val nextRequestAt = AtomicLong(0)

    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(CONSENT_KEY, false)

    fun setEnabled(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(CONSENT_KEY, value).apply()
    }

    private fun key(name: String): String =
        MessageDigest.getInstance("SHA-256").digest(name.toByteArray())
            .joinToString("") { "%02x".format(it) }.take(40)

    private fun cacheFile(context: Context, name: String) =
        File(File(context.cacheDir, "card-art").apply { mkdirs() }, key(name) + ".img")

    private fun decode(bytes: ByteArray): Bitmap? = runCatching {
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }.getOrNull()

    /** Returns null when artwork is unavailable; it never substitutes a different card. */
    suspend fun load(context: Context, name: String): Bitmap? = withContext(Dispatchers.IO) {
        if (name.isBlank() || name.length > 200) return@withContext null
        memory.get(name)?.let { return@withContext it }
        val file = cacheFile(context, name)
        if (file.isFile && file.length() in 1..MAX_BYTES.toLong()) {
            decode(file.readBytes())?.let { memory.put(name, it); return@withContext it }
        }
        if (!enabled(context)) return@withContext null
        val bytes = fetch(name) ?: return@withContext null
        runCatching { file.writeBytes(bytes) }
        decode(bytes)?.also { memory.put(name, it) }
    }

    private fun fetch(name: String): ByteArray? {
        // Space requests the way the iOS loader does; Scryfall asks callers not to burst.
        val now = System.currentTimeMillis()
        val due = nextRequestAt.getAndSet(maxOf(now, nextRequestAt.get()) + REQUEST_SPACING_MS)
        if (due > now) runCatching { Thread.sleep(minOf(due - now, 2000)) }

        val encoded = URLEncoder.encode(name, "UTF-8")
        val url = URL("https://api.scryfall.com/cards/named?exact=$encoded&format=image&version=normal")
        var connection: HttpURLConnection? = null
        return try {
            connection = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = true
                connectTimeout = 15000
                readTimeout = 20000
                setRequestProperty("User-Agent", "MagicMobile-Android/0.1 (artwork)")
                setRequestProperty("Accept", "image/jpeg,image/png;q=0.9")
            }
            if (connection.responseCode != 200) return null
            // Redirects are followed, so validate where we actually landed.
            if (connection.url.protocol != "https" || connection.url.host !in ALLOWED_HOSTS) return null
            if (connection.contentType?.substringBefore(';')?.trim() !in setOf("image/jpeg", "image/png")) return null
            if (connection.contentLength > MAX_BYTES) return null
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(16384)
            connection.inputStream.use { input ->
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (out.size() + read > MAX_BYTES) return null
                    out.write(buffer, 0, read)
                }
            }
            out.toByteArray().takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        } finally {
            connection?.disconnect()
        }
    }
}

@Composable
fun CardArtwork(name: String, modifier: Modifier = Modifier, placeholder: @Composable () -> Unit = {}) {
    val context = LocalContext.current
    val consent = Artwork.enabled(context)
    var bitmap by remember(name, consent) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(name, consent) { bitmap = runCatching { Artwork.load(context, name) }.getOrNull() }
    Box(modifier.background(Color(0xFFEDE7DC)), contentAlignment = Alignment.Center) {
        val image = bitmap
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null,
                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            placeholder()
        }
    }
}
