package io.magicmobile.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GameArtworkIdentityTest {
    private val token=mapOf<String,Any?>(
        "name" to "Soldier",
        "isToken" to true,
        "superTypes" to listOf("TOKEN"),
        "cardTypes" to listOf("CREATURE"),
        "subTypes" to listOf("SOLDIER"),
        "rules" to listOf("Vigilance"),
        "power" to "1",
        "toughness" to "1",
        "color" to mapOf("white" to true,"blue" to false,"black" to false,"red" to false,"green" to false),
    )

    @Test fun completeVisibleTokenIdentityIsRetained() {
        assertEquals(ArtworkTokenIdentity("Soldier","Token Creature — Soldier","Vigilance","1","1",setOf("W")),
            gameArtworkTokenIdentity(token))
    }

    @Test fun incompleteOrHiddenIdentityNeverFallsBackByName() {
        assertNull(gameArtworkTokenIdentity(token+("color" to mapOf("white" to true))))
        assertNull(gameArtworkTokenIdentity(token+("hideInfo" to true)))
        assertNull(gameArtworkTokenIdentity(token-("isToken")))
    }
}
