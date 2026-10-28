package io.magicmobile.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.util.LruCache
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.security.MessageDigest
import java.util.Locale

/**
 * Pictures the player chose for cards (Deck Studio, "Use my own picture"): kept on this device only, one per card name,
 * and drawn over the card's art box wherever the card shows, so its name, cost and rules stay the real card's. Opponents
 * see the card's usual art. CustomCardArt.swift.
 */
object CustomCardArt {
    /** Changes whenever any card's picture is set or removed; card views reload on it. */
    var revision by mutableIntStateOf(0)
        private set
    /** Saved pictures are scaled to at most this long edge: sharper than any card on screen, small on disk. */
    private const val MAXIMUM_EDGE = 1200
    private val pictures = LruCache<String, Bitmap>(16)
    private val composed = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    private fun directory(context: Context) = File(context.applicationContext.filesDir, "custom-card-art")
    private fun key(name: String) = name.trim().lowercase(Locale.ROOT)
    private fun file(context: Context, name: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(key(name).toByteArray()).joinToString("") { "%02x".format(it) }
        return File(directory(context), "$hash.jpg")
    }

    fun has(context: Context, name: String): Boolean = file(context, name).isFile

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
        val target = file(context, name)
        target.parentFile?.mkdirs()
        val written = runCatching {
            val temporary = File(target.parentFile, target.name + ".part")
            temporary.outputStream().use { picture.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            check(temporary.renameTo(target))
        }.isSuccess
        if (written) changed()
        return written
    }

    fun remove(context: Context, name: String) {
        file(context, name).delete()
        changed()
    }

    private fun changed() { pictures.evictAll(); composed.evictAll(); revision++ }

    /** The card image with the card's picture over its art box, or the card image itself when it has none. Off the main thread. */
    fun overlay(context: Context, name: String, card: Bitmap): Bitmap {
        val file = file(context, name)
        if (!file.isFile) return card
        val cacheKey = "${key(name)}|${file.lastModified()}|${System.identityHashCode(card)}"
        composed.get(cacheKey)?.let { return it }
        val picture = pictures.get(file.path + file.lastModified())
            ?: BitmapFactory.decodeFile(file.path)?.also { pictures.put(file.path + file.lastModified(), it) } ?: return card
        return compose(card, picture).also { composed.put(cacheKey, it) }
    }

    /** The art box is the window artworkIllustrationCrop starts from; the picture fills it, centred. */
    internal fun compose(card: Bitmap, picture: Bitmap): Bitmap {
        val result = card.copy(Bitmap.Config.ARGB_8888, true)
        val box = RectF(card.width * .08f, card.height * .145f, card.width * .92f, card.height * .53f)
        val scale = maxOf(box.width() / picture.width, box.height() / picture.height)
        val sourceWidth = box.width() / scale; val sourceHeight = box.height() / scale
        val left = (picture.width - sourceWidth) / 2; val top = (picture.height - sourceHeight) / 2
        Canvas(result).drawBitmap(picture, Rect(left.toInt(), top.toInt(), (left + sourceWidth).toInt(), (top + sourceHeight).toInt()),
            box, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        return result
    }
}
