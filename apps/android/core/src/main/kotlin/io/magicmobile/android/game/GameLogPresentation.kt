package io.magicmobile.android.game

import java.util.UUID

/**
 * Port of apps/ios/MagicMobile/GameLogPresentation.swift (logic only; the composables live in
 * the app). Display-only interpretation of an already authorized log message. Never queries
 * cards, retains messages, emits events, or uses an HTML renderer.
 */
data class GameLogPresentation(val spans: List<Span>) {
    enum class Role { ACTION, PLAYER, CARD }

    /** Identity and label already disclosed by this log entry. Not lookup authorization. */
    data class CardReference(val objectID: UUID, val name: String)

    data class Span(val text: String, val role: Role, val bold: Boolean, val italic: Boolean, val cardReference: CardReference? = null)

    val plainText: String get() = spans.joinToString("") { it.text }

    /** Links are generated locally per span; never trust an href from the message. */
    fun inspectionURL(index: Int): String? = if (index in spans.indices && spans[index].cardReference != null) "magicmobile-log://inspect/$index" else null

    fun cardReference(url: String): CardReference? {
        val index = url.substringAfterLast('/').toIntOrNull() ?: return null
        if (index !in spans.indices || inspectionURL(index) != url) return null
        return spans[index].cardReference
    }

    private data class Style(val role: Role = Role.ACTION, val bold: Boolean = false, val italic: Boolean = false)
    private class Frame(val name: String, val previous: Style, val objectID: UUID?, val start: Int)

    companion object {
        // Tokenize before decoding so encoded angle brackets remain literal text.
        private val tokens = Regex("(?s)<!--.*?(?:-->|$)|</?([A-Za-z][A-Za-z0-9:-]*)\\b(?:[^<>\"']|\"[^\"]*\"|'[^']*')*>|&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);|<(?i:font)\\s+[^<>]*$")
        private val attributes = Regex("(?i)\\s+([a-z][a-z0-9_-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))")
        // Matches mage.util.GameLog's log palette, not arbitrary CSS or tooltip colours.
        private val cardColors = setOf("#90ee90", "#ff6347", "#87cefa", "#696969", "#f0e68c", "#daa520", "#b0c4de")
        private val suppressed = setOf("script", "style", "iframe", "object", "svg", "math", "head", "template")
        private val blocks = setOf("br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr")

        operator fun invoke(rawSource: String): GameLogPresentation {
            // Apply the entity decoder's control policy to literal input too, before tokenization.
            val source = buildString {
                var i = 0
                while (i < rawSource.length) {
                    val cp = rawSource.codePointAt(i)
                    if (!((cp < 32 && cp !in listOf(9, 10, 13)) || cp in 127..159 || cp in 0x202A..0x202E || cp in 0x2066..0x2069)) appendCodePoint(cp)
                    i += Character.charCount(cp)
                }
            }
            val result = mutableListOf<Span>()
            var style = Style()
            val frames = mutableListOf<Frame>()
            val hidden = mutableListOf<String>()
            var pendingCardID: String? = null
            var cursor = 0
            var textBuffer = StringBuilder()

            fun append(value: String) {
                if (hidden.isNotEmpty() || value.isEmpty()) return
                var text = value
                pendingCardID?.let { id ->
                    // Only a UUID-matching suffix directly after a named card is metadata.
                    val pattern = Regex("^[ \\t]*\\[" + Regex.escape(id) + "\\](?=[\\s.,;:!?()]|$)", RegexOption.IGNORE_CASE)
                    pattern.find(text)?.let { text = text.removeRange(it.range) }
                    pendingCardID = null
                }
                if (text.isEmpty()) return
                result += Span(text, style.role, style.bold, style.italic)
            }

            for (match in tokens.findAll(source)) {
                textBuffer.append(source, cursor, match.range.first)
                cursor = match.range.last + 1
                val token = match.value
                if (token.startsWith("&")) {
                    // Reuse the prompt decoder's entity policy; whitespace entities are handled here.
                    textBuffer.append(entity(token))
                    continue
                }
                append(textBuffer.toString())
                textBuffer = StringBuilder()
                if (token.startsWith("<!--")) continue
                // A truncated font opening tag must not expose its private attributes.
                val nameGroup = match.groups[1] ?: continue
                val name = nameGroup.value.lowercase()
                val closing = token.startsWith("</")
                if (suppressed.contains(name)) {
                    if (closing) {
                        // Closing an ancestor also closes its malformed/unclosed children.
                        val index = hidden.lastIndexOf(name)
                        if (index >= 0) while (hidden.size > index) hidden.removeAt(hidden.size - 1)
                    } else if (!token.endsWith("/>") || name !in setOf("svg", "math")) {
                        // HTML containers are not void elements, even with a slash.
                        hidden += name
                    }
                    continue
                }
                if (hidden.isNotEmpty()) continue
                if (blocks.contains(name)) { append("\n"); continue }
                if (name == "img") { append(EngineDisplayText.text(token)); continue } // canonical mana alt only
                if (name !in setOf("font", "i", "b")) continue
                if (closing) {
                    val index = frames.indexOfLast { it.name == name }
                    if (index < 0) continue
                    val frame = frames[index]
                    val label = result.drop(frame.start).joinToString("") { it.text }.trim()
                    style = frame.previous
                    while (frames.size > index) frames.removeAt(frames.size - 1)
                    val id = frame.objectID
                    if (id != null && label.isNotEmpty() && label.any { it.isLetter() } && !label.startsWith("[")) {
                        pendingCardID = id.toString().take(3)
                        if (label.lowercase() !in setOf("hidden card", "face-down card", "face down card", "card details unavailable")) {
                            for (position in frame.start until result.size) {
                                if (result[position].cardReference == null) result[position] = result[position].copy(cardReference = CardReference(id, label))
                            }
                        }
                    }
                } else if (!token.endsWith("/>")) {
                    val attrs = readAttributes(token)
                    val id = attrs["object_id"]?.takeIf(::isUuid)?.let(UUID::fromString)
                    frames += Frame(name, style, if (name == "font") id else null, result.size)
                    if (name == "b") style = style.copy(bold = true)
                    if (name == "i") style = style.copy(italic = true)
                    if (name == "font") {
                        val color = attrs["color"]?.lowercase() ?: ""
                        if (id != null || cardColors.contains(color)) style = style.copy(role = Role.CARD)
                        else if (color == "#20b2aa") style = style.copy(role = Role.PLAYER)
                    }
                }
            }
            append(textBuffer.toString() + source.substring(cursor))
            return GameLogPresentation(result)
        }

        private fun readAttributes(tag: String): Map<String, String> {
            val values = HashMap<String, String>()
            val duplicates = mutableSetOf<String>()
            for (match in attributes.findAll(tag)) {
                val key = match.groupValues[1].lowercase()
                val value = (2..4).firstNotNullOfOrNull { match.groups[it]?.value } ?: continue
                if (values.containsKey(key)) duplicates += key
                values[key] = value
            }
            duplicates.forEach { values.remove(it) }
            return values
        }

        private val unicodeWhitespace = setOf(9, 10, 11, 12, 13, 32, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000) + (0x2000..0x200A)

        private fun entity(token: String): String {
            if (token == "&nbsp;") return " "
            if (token.startsWith("&#")) {
                val body = token.drop(2).dropLast(1)
                val hex = body.startsWith("x") || body.startsWith("X")
                val value = (if (hex) body.drop(1) else body).toLongOrNull(if (hex) 16 else 10)
                if (value != null) {
                    if (value == 160L) return " "
                    if (value <= 0x10FFFF && value.toInt() in unicodeWhitespace && value.toInt() !in listOf(11, 12, 133)) return String(Character.toChars(value.toInt()))
                }
            }
            return EngineDisplayText.text(token)
        }
    }
}

/** Rules use the same inert tokenizer, but decode escaped markup to plain text. Self references are substituted last. */
class GameRulesPresentation(source: String, cardName: String? = null, isHidden: Boolean = false) {
    val plainText: String

    init {
        plainText = if (isHidden) "" else {
            val text = normalized(source, maximumBytes)
            if (text == null) unavailableText else {
                val name = cardName?.let { normalized(it, 512) }?.takeIf { it.isNotEmpty() } ?: "This card"
                val replacements = text.split("{this}").size - 1
                // Bound expansion before allocating repeated self-reference replacements.
                if (utf8(text) + replacements * (utf8(name) - 6) > maximumBytes) unavailableText
                else text.replace("{this}", name).trim()
            }
        }
    }

    override fun equals(other: Any?): Boolean = other is GameRulesPresentation && other.plainText == plainText
    override fun hashCode(): Int = plainText.hashCode()

    companion object {
        const val maximumBytes = 32 * 1024
        const val maximumNormalizationPasses = 8
        const val unavailableText = "Rules unavailable."
        private fun utf8(value: String): Int = value.toByteArray(Charsets.UTF_8).size

        private fun normalized(source: String, maximumBytes: Int): String? {
            if (utf8(source) > maximumBytes) return null
            var text = source
            repeat(maximumNormalizationPasses) {
                val next = GameLogPresentation(text).plainText
                if (utf8(next) > maximumBytes) return null
                if (next == text) return next
                text = next
            }
            // Never return partially decoded tags or hidden-region contents at the limit.
            return null
        }
    }
}

/** Only accepts the already normalized, privacy-filtered rules presentation. */
class GameRulesSymbols(rules: GameRulesPresentation) {
    data class Fragment(val literal: String, val code: String? = null, val spoken: String? = null)

    val fragments: List<Fragment>

    val accessibilityText: String get() = fragments.joinToString("") { f -> f.spoken?.let { " $it " } ?: f.literal }
        .replace(Regex("[ \\t]+"), " ").trim()

    init {
        val text = rules.plainText
        val parts = mutableListOf<Fragment>()
        var cursor = 0
        var count = 0
        for (match in tokens.findAll(text)) {
            val code = match.groupValues[1].uppercase()
            val spoken = spoken(code) ?: continue
            if (match.range.first > cursor) parts += Fragment(text.substring(cursor, match.range.first))
            parts += Fragment(match.value, code, spoken)
            cursor = match.range.last + 1; count += 1
            if (count == maximumSymbols) break
        }
        if (cursor < text.length) parts += Fragment(text.substring(cursor))
        fragments = parts
    }

    companion object {
        const val maximumSymbols = 256
        private val tokens = Regex("\\{([A-Za-z0-9/]{1,12})\\}")
        private val colors = mapOf("W" to "white", "U" to "blue", "B" to "black", "R" to "red", "G" to "green", "C" to "colorless")

        fun spoken(code: String): String? {
            colors[code]?.let { return "$it mana" }
            when (code) {
                "T" -> return "tap"; "Q" -> return "untap"; "S" -> return "snow mana"
                "X", "Y", "Z" -> return "$code generic mana"
            }
            if (code.length <= 3 && code.all { it in '0'..'9' }) code.toIntOrNull()?.let { return "$it generic mana" }
            val parts = code.split("/")
            if (parts.size == 2) {
                val first = colors[parts[0]]; val second = colors[parts[1]]
                if (first != null && second != null && parts[0] != parts[1]) return "$first or $second mana"
                if (parts[0] == "2" && second != null) return "two generic or $second mana"
                if (first != null && parts[1] == "P") return "$first mana or two life"
            }
            if (parts.size == 3 && parts[2] == "P") {
                val first = colors[parts[0]]; val second = colors[parts[1]]
                if (first != null && second != null && parts[0] != parts[1]) return "$first or $second mana or two life"
            }
            return null
        }
    }
}

/** Prompt and button text without XMage's short object-ID suffixes ("Black Market Connections [4cb]"). */
object PromptDisplayText {
    private val objectID = Regex("[ \\t]*\\[(?=[0-9a-f]*[0-9])[0-9a-f]{3,8}\\]")
    fun clean(text: String): String = if (!text.contains("[")) text else objectID.replace(text, "")
}
