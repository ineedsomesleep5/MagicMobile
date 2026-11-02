package io.magicmobile.android.game

import java.io.File

/** How asking the server for a badge went. */
sealed interface BadgeFetch {
    data class New(val bytes: ByteArray, val etag: String?) : BadgeFetch
    data object Unchanged : BadgeFetch
    /** The server doesn't have that file. */
    data object Missing : BadgeFetch
    /** Offline or a server error: try another time. */
    data object Failed : BadgeFetch
}

/**
 * Badge art kept on the phone, so a profile opens with its coins already there (BadgeArtStore.swift). Our art has a small copy
 * beside it (scripts/brand/award_small.sh); art from anywhere else is kept as it comes. The store asks the server again at most
 * every six hours, and a file it already has only comes down again if it changed, so new art still needs no build.
 */
class BadgeArtStore(private val folder: File?, private val fetch: suspend (url: String, etag: String?) -> BadgeFetch) {
    private fun art(key: String) = folder?.let { File(it, "$key.png") }
    private fun note(key: String) = folder?.let { File(it, "$key.note") }

    /** What the phone has, however old. */
    fun stored(url: String, small: Boolean = true): ByteArray? =
        art(key(url, small))?.takeIf { it.exists() }?.let { runCatching { it.readBytes() }.getOrNull() }

    /** Checks with the server unless it did lately, and tells whether the art changed. */
    suspend fun refresh(url: String, small: Boolean = true, now: Long = System.currentTimeMillis()): Boolean {
        val key = key(url, small)
        val note = note(key)?.takeIf { it.exists() }?.let { runCatching { it.readLines() }.getOrNull() }
        val have = art(key)?.exists() == true
        if (have && now - (note?.getOrNull(0)?.toLongOrNull() ?: 0L) < RECHECK_MS) return false
        val wanted = if (small) smallURL(url) else url
        var result = fetch(wanted, note?.getOrNull(1)?.takeIf { have && it.isNotEmpty() })
        if (result == BadgeFetch.Missing && wanted != url) result = fetch(url, null)
        if (result is BadgeFetch.New) {
            runCatching {
                folder?.mkdirs()
                val part = File(folder, "$key.part")
                part.writeBytes(result.bytes)
                art(key)?.let(part::renameTo)
                note(key)?.writeText("$now\n${result.etag.orEmpty()}")
            }
            return true
        }
        if (result == BadgeFetch.Unchanged) runCatching { note(key)?.writeText("$now\n${note?.getOrNull(1).orEmpty()}") }
        return false
    }

    companion object {
        const val RECHECK_MS = 6 * 60 * 60 * 1000L
        private const val AWARDS = "/design/awards/"

        fun smallURL(url: String): String = if (AWARDS in url && "${AWARDS}small/" !in url) url.replace(AWARDS, "${AWARDS}small/") else url

        /** A file name that stays the same from launch to launch (FNV-1a, as stableHash in Swift). */
        fun key(url: String, small: Boolean): String {
            var hash = -3750763034362895579L
            for (byte in (if (small) "small:$url" else url).toByteArray()) hash = (hash xor (byte.toLong() and 0xff)) * 1099511628211L
            return java.lang.Long.toHexString(hash)
        }
    }
}
