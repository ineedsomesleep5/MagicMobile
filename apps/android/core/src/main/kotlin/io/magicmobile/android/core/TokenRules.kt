package io.magicmobile.android.core

/**
 * The tokens a deck makes, read from its cards' rules text, for offline token-art downloads.
 * Port of NativeTokenRules (NativeAssetDownloads.swift); parity/token-cases.json checks both.
 */
object TokenRules {
    /** Tokens so many cards make that deck downloads always include them. */
    val commonTokenNames = listOf("Food", "Treasure", "Clue", "Blood", "Map", "Powerstone", "Incubator", "Junk", "Gold", "Shard")

    /** power/toughness only when printed as numbers ("1/1"; X/X leaves both null); colors null when unnamed, empty for colorless. */
    data class Request(val name: String, val power: String? = null, val toughness: String? = null, val colors: List<String>? = null)

    private const val WORD = "[A-Z][A-Za-z'\\-]*"
    private const val COLOR = "(?:white|blue|black|red|green|colorless)"
    // "[1/1] [green] Squirrel [creature] token(s)", including lists such as "a Clue, Food, or Treasure token".
    private val described = Regex("(?<![A-Za-z0-9/+])(?:([0-9X*]+)/([0-9X*]+) )?(?:($COLOR(?:(?:,? and |, )$COLOR)*) )?" +
        "($WORD(?: $WORD)*(?:(?:,? or |,? and |, )$WORD(?: $WORD)*)*) " +
        "(?:(?i:legendary|snow|artifact|enchantment|land|creature|planeswalker) )*tokens?(?![A-Za-z])")
    // "... token named Kobolds of Kher Keep".
    private val named = Regex("(?<![A-Za-z])tokens? named ($WORD(?: (?:(?:of|the) )*$WORD)*)")
    private val separator = Regex(",? or |,? and |, ")
    private val creates = Regex("(?i)\\bcreates?\\b")
    private val colorWord = Regex("white|blue|black|red|green")
    private val letters = mapOf("white" to "W", "blue" to "U", "black" to "B", "red" to "R", "green" to "G")
    /** Capitalized words that start a sentence or describe a token rather than name one. */
    private val stopWords = setOf(
        "A", "An", "The", "Each", "Every", "Another", "Other", "Target", "That", "This", "Those", "These", "All", "Any", "No",
        "If", "When", "Whenever", "As", "At", "For", "Then", "Until", "Up", "Create", "Creates", "Put", "Sacrifice", "Exile",
        "Return", "Destroy", "Copy", "Tap", "Untap", "Choose", "Nontoken", "Token", "Tokens", "X", "You", "Your", "Its", "Their",
        "Attacking", "Blocking", "Tapped", "Untapped", "Creature", "Artifact", "Enchantment", "Land", "Snow", "Legendary",
        "Nonland", "Noncreature")

    /**
     * A token without a printed size or color counts only in a sentence that creates it, so
     * "Whenever a Zombie token you control attacks" adds nothing. Reminder text counts too:
     * "Investigate (Create a Clue token ...)" makes a Clue.
     */
    fun requests(rules: String): List<Request> {
        val text = rules.replace(Regex("<[^>]*>"), " ").replace(Regex("&[A-Za-z]+;|&#[0-9]+;"), " ").replace(Regex("[ \\t]+"), " ")
        val found = mutableListOf<Pair<Int, Request>>()
        for (match in described.findAll(text)) {
            if (text.startsWith(" named ", match.range.last + 1)) continue
            val power = match.groups[1]?.value
            val toughness = match.groups[2]?.value
            val colors = match.groups[3]?.value
            val numeric = listOf(power, toughness).all { it != null && it.isNotEmpty() && it.all { c -> c in '0'..'9' } }
            if (power == null && colors == null) {
                val clause = text.substring(0, match.range.first).split('.', '\n').last()
                if (!creates.containsMatchIn(clause)) continue
            }
            val colorSet = colors?.let { words ->
                if (words == "colorless") emptyList() else {
                    val named = colorWord.findAll(words).map { letters.getValue(it.value) }.toSet()
                    listOf("W", "U", "B", "R", "G").filter(named::contains)
                }
            }
            for (piece in match.groups[4]!!.value.split(separator)) {
                val words = piece.split(" ").dropWhile { it in stopWords }
                if (words.isEmpty()) continue
                found += match.range.first to Request(words.joinToString(" "), if (numeric) power else null, if (numeric) toughness else null, colorSet)
            }
        }
        for (match in named.findAll(text)) found += match.groups[1]!!.range.first to Request(match.groups[1]!!.value)
        val seen = HashSet<Request>()
        return found.withIndex().sortedWith(compareBy({ it.value.first }, { it.index })).map { it.value.second }
            .filter { seen.add(it.copy(name = it.name.lowercase())) }
    }
}
