package io.magicmobile.android

import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.Obj

internal fun defaultAiDecks(included:List<Deck>):List<Deck> =
    if(included.isEmpty()) emptyList() else List(3) { included[it % included.size] }

internal fun replaceAiDeck(current:List<Deck>,seat:Int,deck:Deck):List<Deck> {
    require(seat in current.indices)
    return current.toMutableList().also { it[seat]=deck }
}

internal fun activeAiDecks(current:List<Deck>,count:Int):List<Deck> {
    require(count in 1..3 && current.size>=count)
    return current.take(count)
}

internal fun localGameSeats(humanName:String,humanDeck:Obj,aiDecks:List<Obj>,aiSkill:Int):List<Obj> {
    require(humanName.isNotBlank() && aiDecks.size in 1..3 && aiSkill in 1..10)
    return listOf(mapOf("seatId" to "player-1","name" to humanName,"controller" to "human","deck" to humanDeck))+
        aiDecks.mapIndexed { index,deck -> mapOf("seatId" to "player-${index+2}","name" to "AI ${index+1}","controller" to "ai","deck" to deck,"aiSkill" to aiSkill) }
}
