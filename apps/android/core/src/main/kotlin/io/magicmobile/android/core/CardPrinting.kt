package io.magicmobile.android.core

import io.magicmobile.android.studio.DeckList

/**
 * One printing of a card, picked for its artwork. It changes only which picture shows; the rules,
 * the engine's compiled printing and deck validation never read it. Port of CardPrinting.swift.
 */
class CardPrinting private constructor(
    /** Lowercase Scryfall set code ("cmm", "plst"). */
    val setCode: String,
    /** Collector number as printed ("400", "107m", "★1"). */
    val number: String,
) {
    /** The offline store's key and the memory key: "set/number". */
    val key: String get() = "$setCode/$number"
    /** How exports write it: "(CMM) 400". */
    val exportSuffix: String get() = "(${setCode.uppercase()}) $number"
    /** "CMM 400", for a caption. */
    val label: String get() = "${setCode.uppercase()} $number"

    /** Scryfall's card record for exactly this printing. */
    fun cardUrl(): String = "https://api.scryfall.com/cards/${encode(setCode)}/${encode(number)}"
    /** Scryfall's image route for exactly this printing. A double-faced card's other face is `face=back`. */
    fun imageUrl(version: String, back: Boolean = false): String =
        cardUrl() + "?format=image&version=$version" + if (back) "&face=back" else ""

    override fun equals(other: Any?) = other is CardPrinting && other.setCode == setCode && other.number == number
    override fun hashCode() = key.hashCode()
    override fun toString() = "CardPrinting($key)"

    companion object {
        /** Null unless both parts are ones the app can ask Scryfall for exactly. */
        fun of(set: String, number: String): CardPrinting? {
            val code = set.trim().lowercase()
            val value = number.trim()
            return if (isSetCode(code) && isNumber(value)) CardPrinting(code, value) else null
        }
        /** Letters and digits, 2 to 6 of them ("tmm3", "30a", "plst"). */
        fun isSetCode(value: String) = value.length in 2..6 && value.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' }
        /** Collector numbers carry letters, digits, hyphens and the star and dagger marks. */
        fun isNumber(value: String) = value.length in 1..16 && value.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '★' || it == '†' }

        /**
         * The suffix at the end of a deck-list line: "(CMM) 400" or "(cmm) 400". A set code with no number
         * does not name one printing, so it gives null.
         */
        fun parseSuffix(suffix: String): CardPrinting? {
            val text = suffix.trim { it == ' ' || it == '\t' }
            if (!text.startsWith("(")) return null
            val close = text.indexOf(')')
            if (close < 0) return null
            return of(text.substring(1, close), text.substring(close + 1))
        }

        private fun encode(value: String): String = java.net.URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    }
}

/**
 * Which printing's art a card shows. The player picks it per deck row in Deck Studio; everywhere a card is
 * drawn by name (the board, the opening hand, the inspector, profile and match history) the choice is found
 * here. The playing deck's choices come first, then those of the saved decks, the most recently saved deck
 * first. Port of CardArtChoices.swift.
 */
class CardArtChoices(private val reverseFaceLoader: (() -> Map<String, String>?)? = null) {
    class SavedDeck(val id: String, val deck: DeckList, val updated: Long)
    /** What to draw for a name: a printing, and whether the name is that card's reverse face. */
    data class Selection(val printing: CardPrinting, val back: Boolean)

    private val lock = Any()
    private var library: List<SavedDeck> = emptyList()
    private var selectedId: String? = null
    private var byName: Map<String, CardPrinting> = emptyMap()
    private var reverse: Map<String, String> = emptyMap()
    private var loadingReverse = false
    private val listeners = java.util.concurrent.CopyOnWriteArrayList<() -> Unit>()

    /** Called (on whatever thread changed it) when the choices a card name resolves to change. */
    fun addListener(listener: () -> Unit) { listeners += listener }

    fun setLibrary(decks: List<SavedDeck>) = commit { library = decks }
    /** The deck chosen for play, by the picker's id; a precon or included deck has no choices of its own. */
    fun select(deckId: String?) = commit { selectedId = deckId }
    fun update(decks: List<SavedDeck>, deckId: String?) = commit { library = decks; selectedId = deckId }

    private fun commit(change: () -> Unit) {
        var load = false
        val changed = synchronized(lock) {
            change()
            val changed = rebuild()
            load = byName.isNotEmpty() && reverse.isEmpty() && !loadingReverse && reverseFaceLoader != null
            if (load) loadingReverse = true
            changed
        }
        if (changed) listeners.forEach { it() }
        if (load) Thread {
            try { reverseFaceLoader?.invoke()?.let(::setReverseFaces) } finally { synchronized(lock) { loadingReverse = false } }
        }.apply { isDaemon = true }.start()
    }

    /** The reverse faces of double-faced cards, so a transformed permanent shows its own face of the chosen printing. */
    fun setReverseFaces(faces: Map<String, String>) {
        synchronized(lock) { reverse = faces.entries.associate { key(it.key) to key(it.value) } }
        listeners.forEach { it() }
    }
    val needsReverseFaces: Boolean get() = synchronized(lock) { reverse.isEmpty() && byName.isNotEmpty() }
    val isEmpty: Boolean get() = synchronized(lock) { byName.isEmpty() }

    fun printing(name: String): CardPrinting? = selection(name)?.printing

    fun selection(name: String): Selection? {
        val key = key(name)
        synchronized(lock) {
            byName[key]?.let { return Selection(it, false) }
            val front = reverse[key] ?: return null
            return byName[front]?.let { Selection(it, true) }
        }
    }

    /**
     * The choices of the decks, in priority order. A card the playing deck holds takes that deck's choice,
     * or its default art when none was made, whatever other decks chose. Caller holds the lock.
     */
    private fun rebuild(): Boolean {
        val ordered = library.sortedByDescending { it.updated }.toMutableList()
        selectedId?.let { id -> ordered.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.let { ordered.add(0, ordered.removeAt(it)) } }
        val next = LinkedHashMap<String, CardPrinting>()
        val decided = HashSet<String>()
        for ((position, saved) in ordered.withIndex()) {
            val playing = position == 0 && saved.id == selectedId
            val held = HashSet<String>()
            for (entry in listOfNotNull(saved.deck.commander) + saved.deck.entries) {
                val key = key(entry.cardName)
                if (key in decided) continue
                held += key
                val printing = entry.printing
                if (printing != null && key !in next) next[key] = printing
            }
            if (playing) decided += held else decided += held.filter { it in next }
        }
        val changed = next != byName
        byName = next
        return changed
    }

    companion object {
        /** A card name as the offline store keys it: trimmed, lower case. */
        fun key(name: String) = name.trim().lowercase()
    }
}
