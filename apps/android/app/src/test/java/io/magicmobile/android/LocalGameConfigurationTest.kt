package io.magicmobile.android

import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.Deck
import org.junit.Assert.assertEquals
import org.junit.Test

class LocalGameConfigurationTest {
    private fun deck(name:String)=Deck(name,listOf(CardEntry("Forest",100)))

    @Test fun preservesIndependentSeatChoicesWhenAiCountChanges() {
        val included=listOf(deck("One"),deck("Two"),deck("Three"),deck("Four"))
        var selected=defaultAiDecks(included)
        selected=replaceAiDeck(selected,2,included[3])

        assertEquals(listOf("One"),activeAiDecks(selected,1).map(Deck::name))
        assertEquals(listOf("One","Two","Four"),activeAiDecks(selected,3).map(Deck::name))
    }

    @Test fun assignsEachResolvedDeckToItsOwnEngineSeat() {
        val human=mapOf("deck" to "human")
        val opponents=listOf(mapOf("deck" to "one"),mapOf("deck" to "two"),mapOf("deck" to "three"))
        val seats=localGameSeats("Caleb",human,opponents,4)

        assertEquals(listOf("player-1","player-2","player-3","player-4"),seats.map {it["seatId"]})
        assertEquals(listOf("Caleb","AI 1","AI 2","AI 3"),seats.map {it["name"]})
        assertEquals(listOf(human)+opponents,seats.map {it["deck"]})
        assertEquals(listOf(null,4,4,4),seats.map {it["aiSkill"]})
    }
}
