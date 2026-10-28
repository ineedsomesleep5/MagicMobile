package io.magicmobile.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.util.LruCache
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.studio.CardArtLocal
import io.magicmobile.android.studio.CardArtSync
import org.json.JSONArray
import java.io.File
import java.security.MessageDigest
import java.util.Locale

/**
 * Pictures the player chose for cards (Deck Studio, "Use my own picture"): one per card name, synced to the player's
 * other phones and browsers (CardArtSync, docs/CARD_ART_SYNC.md), and worn as the whole card face wherever the card
 * shows. A picture is usually a card of its own (name, cost, rules drawn on it), so nothing of the printed card shows
 * through. Opponents see the card's usual art. CustomCardArt.swift.
 */
object CustomCardArt {
    /** Changes whenever any card's picture is set or removed; card views reload on it. */
    var revision by mutableIntStateOf(0)
        private set
    /** Told when the player removes a card's picture here (the sync sends the removal). */
    var onRemoved: ((String) -> Unit)? = null
    /** Saved pictures are scaled to at most this long edge: sharper than any card on screen, small on disk. */
    private const val MAXIMUM_EDGE = 1200
    /** A card's width over its height (63 × 88 mm). */
    private const val CARD_ASPECT = 63f / 88f
    private val pictures = LruCache<String, Bitmap>(16)
    private val composed = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    /** Card key to its picture's SHA-256, once worked out. */
    private val hashes = mutableMapOf<String, String>()

    /** The card a picture belongs to, the same on every platform: the front face's name, trimmed, in lower case. */
    fun cardKey(name: String): String = name.split(" // ").first().trim().lowercase(Locale.ROOT)

    private fun directory(context: Context) = File(context.applicationContext.filesDir, "custom-card-art")
    private fun file(context: Context, key: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(directory(context), "$hash.jpg")
    }
    private fun indexFile(context: Context) = File(directory(context), "index.json")

    fun has(context: Context, name: String): Boolean = file(context, cardKey(name)).isFile

    /** Saves a picture for the card from the photo picker's uri, scaled down and kept as JPEG. */
    fun save(context: Context, name: String, uri: Uri): Boolean {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return false
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAXIMUM_EDGE) sample *= 2
        val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            ?: return false
        val scale = minOf(1f, MAXIMUM_EDGE.toFloat() / maxOf(decoded.width, decoded.height))
        val picture = if (scale < 1f) Bitmap.createScaledBitmap(decoded, (decoded.width * scale).toInt().coerceAtLeast(1),
            (decoded.height * scale).toInt().coerceAtLeast(1), true) else decoded
        val bytes = java.io.ByteArrayOutputStream().also { picture.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
        return runCatching { write(context, cardKey(name), bytes) }.isSuccess
    }

    fun remove(context: Context, name: String) {
        val key = cardKey(name)
        delete(context, key)
        onRemoved?.invoke(key)
    }

    @Synchronized private fun write(context: Context, key: String, bytes: ByteArray) {
        val target = file(context, key)
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, target.name + ".part")
        temporary.writeBytes(bytes)
        check(temporary.renameTo(target))
        hashes[key] = CardArtSync.pictureHash(bytes)
        saveIndex(context, index(context) + key)
        changed()
    }

    @Synchronized private fun delete(context: Context, key: String) {
        file(context, key).delete()
        hashes.remove(key)
        saveIndex(context, index(context) - key)
        changed()
    }

    /** The card keys with a picture (file names are hashes, so the keys are kept beside them). */
    private fun index(context: Context): Set<String> = runCatching {
        val array = JSONArray(indexFile(context).readText())
        (0 until array.length()).map { array.getString(it) }.toSet()
    }.getOrDefault(emptySet())

    private fun saveIndex(context: Context, keys: Set<String>) {
        directory(context).mkdirs()
        indexFile(context).writeText(JSONArray(keys.sorted()).toString())
    }

    private fun changed() { pictures.evictAll(); composed.evictAll(); revision++ }

    /** This phone's pictures for the sync (CardArtSync). */
    fun local(context: Context): CardArtLocal = object : CardArtLocal {
        val app: Context = context.applicationContext
        override fun keys(): List<String> = synchronized(CustomCardArt) { index(app).filter { file(app, it).isFile }.sorted() }
        override fun hash(cardKey: String): String? = synchronized(CustomCardArt) {
            hashes[cardKey] ?: bytes(cardKey)?.let { CardArtSync.pictureHash(it).also { hash -> hashes[cardKey] = hash } }
        }
        override fun bytes(cardKey: String): ByteArray? = file(app, cardKey).takeIf { it.isFile }?.readBytes()
        override fun store(cardKey: String, bytes: ByteArray) = write(app, cardKey, bytes)
        override fun remove(cardKey: String) = delete(app, cardKey)
    }

    /** The card image as the card's picture, or the card image itself when it has none. Off the main thread. */
    fun overlay(context: Context, name: String, card: Bitmap): Bitmap {
        val file = file(context, cardKey(name))
        if (!file.isFile) return card
        val cacheKey = "${cardKey(name)}|${file.lastModified()}|${System.identityHashCode(card)}"
        composed.get(cacheKey)?.let { return it }
        val picture = pictures.get(file.path + file.lastModified())
            ?: BitmapFactory.decodeFile(file.path)?.also { pictures.put(file.path + file.lastModified(), it) } ?: return card
        return compose(card, picture).also { composed.put(cacheKey, it) }
    }

    /**
     * The picture worn as the whole card: the largest card-shaped window in its middle, drawn at the card image's size.
     * The art crop (artworkIllustrationCrop's window) then comes from the picture's own art box.
     */
    internal fun compose(card: Bitmap, picture: Bitmap): Bitmap {
        val result = Bitmap.createBitmap(card.width, card.height, Bitmap.Config.ARGB_8888)
        val faceWidth = minOf(picture.width.toFloat(), picture.height * CARD_ASPECT)
        val faceHeight = faceWidth / CARD_ASPECT
        val left = ((picture.width - faceWidth) / 2).toInt(); val top = ((picture.height - faceHeight) / 2).toInt()
        Canvas(result).drawBitmap(picture, Rect(left, top, left + faceWidth.toInt(), top + faceHeight.toInt()),
            Rect(0, 0, card.width, card.height), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        return result
    }
}
