package io.magicmobile.android.game

import java.net.URI

/**
 * Join links for a cross-play table (TableJoinLink in TableChat.swift). The site's /join/CODE page
 * opens the app (a verified app link when installed) or offers the download; magicmobile://join/CODE
 * opens the app directly. parity/chat-cases.json checks both platforms.
 */
object TableJoinLink {
    const val HOST = "magicmobile-downloads.vercel.app"
    const val SCHEME = "magicmobile"
    /** The relay's table-code alphabet (no 0/O, 1/I). */
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    fun url(code: String): String? = normalized(code)?.let { "https://$HOST/join/$it" }

    fun normalized(raw: String): String? = raw.uppercase().takeIf { code -> code.length == 6 && code.all { it in ALPHABET } }

    /** The table code in a join link, or null for any other link. */
    fun code(link: String): String? {
        val uri = runCatching { URI(link) }.getOrNull() ?: return null
        val parts = (uri.rawPath ?: "").split("/").filter { it.isNotEmpty() }
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()
        if (scheme == SCHEME && host == "join" && parts.size == 1) return normalized(parts[0])
        if (scheme == "https" && host == HOST && parts.size == 2 && parts[0] == "join") return normalized(parts[1])
        return null
    }
}
