package io.magicmobile.android.game

/**
 * Table chat's text rules (TableChat.swift). parity/chat-cases.json checks both platforms.
 */
object TableChatText {
    /** Unicode code points in one message. */
    const val MAX_CODE_POINTS = 200

    /**
     * One line of chat: control characters, tabs and line breaks become spaces, runs of spaces
     * collapse, and the result is trimmed and capped. Nothing is left: nothing is sent.
     */
    fun sanitize(raw: String): String? {
        val out = StringBuilder()
        var pendingSpace = false
        var index = 0
        while (index < raw.length) {
            val codePoint = raw.codePointAt(index)
            index += Character.charCount(codePoint)
            when (Character.getType(codePoint).toByte()) {
                Character.CONTROL, Character.SPACE_SEPARATOR, Character.LINE_SEPARATOR, Character.PARAGRAPH_SEPARATOR ->
                    pendingSpace = out.isNotEmpty()
                else -> {
                    if (pendingSpace) { out.append(' '); pendingSpace = false }
                    out.appendCodePoint(codePoint)
                }
            }
        }
        val text = out.toString()
        val capped = if (text.codePointCount(0, text.length) > MAX_CODE_POINTS) text.substring(0, text.offsetByCodePoints(0, MAX_CODE_POINTS)) else text
        val trimmed = capped.removeSuffix(" ")
        return trimmed.ifEmpty { null }
    }

    fun codePoints(text: String): Int = text.codePointCount(0, text.length)
}

/**
 * Masks strong language in received chat, keeping each word's first letter ("s***"). Only whole
 * words of ASCII letters are checked, so card names such as Cockatrice are left alone.
 */
object TableChatFilter {
    val words = setOf(
        "ass", "asshole", "bastard", "bitch", "bollocks", "chink", "cock", "cunt", "dick", "dickhead",
        "fag", "faggot", "fuck", "kike", "motherfucker", "nigga", "nigger", "prick", "pussy", "retard",
        "shit", "slut", "spic", "twat", "wanker", "whore",
    )
    /** Words that start with these are masked whatever follows ("fucking", "shitty"). */
    val stems = listOf("bitch", "cunt", "fagg", "fuck", "motherf", "nigg", "retard", "shit", "slut", "twat", "wank", "whore")
    val suffixes = listOf("s", "es", "ed", "er", "ers", "ing", "y")

    fun isBlocked(word: String): Boolean {
        val lower = word.lowercase()
        if (lower in words || stems.any { lower.startsWith(it) }) return true
        return suffixes.any { lower.endsWith(it) && lower.dropLast(it.length) in words }
    }

    fun filtered(text: String): String {
        val result = StringBuilder()
        val word = StringBuilder()
        fun flush() {
            if (word.isNotEmpty() && isBlocked(word.toString())) result.append(word[0]).append("*".repeat(word.length - 1))
            else result.append(word)
            word.clear()
        }
        for (char in text) {
            if (char in 'a'..'z' || char in 'A'..'Z') word.append(char) else { flush(); result.append(char) }
        }
        flush()
        return result.toString()
    }
}
