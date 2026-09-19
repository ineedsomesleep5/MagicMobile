package io.magicmobile.android.core

/** Whole-deck operations: callers retain one undo entry for each completed action. */
object DeckEditing {
    val basics = listOf("Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes")

    fun setBasics(deck: Deck, quantities: Map<String, Int>): Deck {
        require(quantities.keys == basics.toSet() && quantities.values.all { it in 0..2000 })
        val retained = deck.entries.filterNot { it.section == "deck" && it.name in basics }
        return deck.copy(entries = retained + basics.mapNotNull { name ->
            quantities.getValue(name).takeIf { it > 0 }?.let { CardEntry(name, it, "deck") }
        })
    }

    fun replace(deck: Deck, index: Int, name: String): Deck = deck.copy(entries = deck.entries.toMutableList().apply {
        set(index, get(index).copy(name = name))
    })

    fun move(deck: Deck, index: Int, section: String): Deck {
        require(section in setOf("deck", "commanders", "companions", "sideboard", "maybeboard"))
        return deck.copy(entries = deck.entries.toMutableList().apply { set(index, get(index).copy(section = section)) })
    }
}
