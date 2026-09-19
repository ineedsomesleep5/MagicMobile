package io.magicmobile.android.core

/** Whole-deck operations: callers retain one undo entry for each completed action. */
object DeckEditing {
    val boards=listOf("deck","commanders","companions","sideboard","maybeboard")
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

    fun replaceCommander(deck:Deck,name:String,keepOld:Boolean):Deck {
        val rows=deck.entries.toMutableList()
        val primary=rows.indexOfFirst{it.section=="commanders"}
        if(primary>=0&&rows[primary].name==name)return deck
        if(primary>=0){val old=rows[primary];rows[primary]=CardEntry(name,1,"commanders");if(keepOld)rows+=old.copy(section="maybeboard")}
        else rows.add(0,CardEntry(name,1,"commanders"))
        val main=rows.indexOfFirst{it.section=="deck"&&it.name==name}
        if(main>=0){val row=rows[main];if(row.quantity==1)rows.removeAt(main)else rows[main]=row.copy(quantity=row.quantity-1)}
        return deck.copy(entries=rows)
    }

    fun move(deck: Deck, index: Int, section: String): Deck {
        require(section in setOf("deck", "commanders", "companions", "sideboard", "maybeboard"))
        return deck.copy(entries = deck.entries.toMutableList().apply { set(index, get(index).copy(section = section)) })
    }
}
