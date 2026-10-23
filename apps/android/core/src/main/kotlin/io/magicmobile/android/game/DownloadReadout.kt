package io.magicmobile.android.game

import java.util.Locale

/*
 * The words at the head of Downloads (NativeDownloadsView.swift `readout`, `stateLine`, `coverage`): one count with its gold
 * bar ("0 of 31,959 stored"), the state once in small type under it, then the tokens and the space taken. Never a sentence
 * that contradicts the count, and nothing said while it is still being counted.
 */
object DownloadReadout {
    data class Readout(val count: String, val fraction: Double?)

    private fun n(value: Int): String = String.format(Locale.US, "%,d", value)

    /** How many images this phone holds of how many, or how far a download has come. */
    fun readout(running: Boolean, preparing: Boolean, completed: Int, total: Int, tokensOnly: Boolean, cardStored: Int, cardTotal: Int,
                tokenStored: Int, tokenTotal: Int, scanPending: Boolean): Readout {
        if (running && !preparing) return Readout("${n(completed)} of ${n(total)} downloaded", completed.toDouble() / maxOf(1, total))
        val stored = if (tokensOnly) tokenStored else cardStored
        val all = if (tokensOnly) tokenTotal else cardTotal
        if (all <= 0 || scanPending) return Readout("Artwork on this phone", null)
        return Readout("${n(stored)} of ${n(all)} stored", stored.toDouble() / all)
    }

    /** Where things stand, once. Empty while it is still counting (the spinner says so). `estimate` is the size without its "≈ ". */
    fun stateLine(running: Boolean, preparing: Boolean, status: String, scanning: Boolean, readingCatalogue: Boolean, scanPending: Boolean,
                  missing: Int, discoveryIncomplete: Boolean, estimate: String, qualityLabel: String): String = when {
        running -> if (preparing) "Preparing image list…" else status
        scanning -> "Checking local files…"
        readingCatalogue -> "Reading the installed catalogue…"
        scanPending -> "Checking needed"
        missing == 0 && !discoveryIncomplete -> "All artwork stored"
        discoveryIncomplete -> ""
        else -> "${n(missing)} missing · about $estimate at ${qualityLabel.lowercase()} quality"
    }

    /** The rest of what this phone holds: the tokens (beside cards) and the space it takes; nothing stored is not worth a line. */
    fun coverage(tokensOnly: Boolean, scanPending: Boolean, tokensKnown: Boolean, tokenStored: Int, tokenTotal: Int, storedBytes: Long,
                 storedText: String): String {
        val parts = mutableListOf<String>()
        if (!tokensOnly && !scanPending && tokensKnown && tokenTotal > 0) parts += "Tokens ${n(tokenStored)} of ${n(tokenTotal)}"
        if (storedBytes > 0) parts += "$storedText on this phone"
        return parts.joinToString(" · ")
    }

    /** The scopes, each by its name alone. */
    val scopes: List<Pair<String, String>> = listOf("Full catalogue" to "catalogue", "Tokens only" to "tokens", "All my decks" to "decks", "One deck" to "deck")
}
