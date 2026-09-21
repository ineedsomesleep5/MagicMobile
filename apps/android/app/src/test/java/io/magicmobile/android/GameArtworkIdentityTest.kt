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

    @Test fun copiedTokenUsesVisibleCopyIdentityAndCurrentStats() {
        val copy=token+mapOf("displayName" to "Copied Soldier", "power" to "3", "toughness" to "3")
        assertEquals(ArtworkTokenIdentity("Copied Soldier","Token Creature — Soldier","Vigilance","3","3",setOf("W")),
            gameArtworkTokenIdentity(copy))
        assertNull(gameArtworkTokenIdentity(copy+mapOf("faceDown" to true)))
    }

    @Test fun projectedTemplateSelectsArtWithoutReplacingLiveRulesOrStats() {
        val template=mapOf("name" to "Soldier","superTypes" to listOf("TOKEN"),"cardTypes" to listOf("CREATURE"),
            "subTypes" to listOf("SOLDIER"),"rules" to "", "power" to "1","toughness" to "1",
            "color" to token["color"])
        val live=token+mapOf("displayName" to "Soldier","rules" to listOf("Vigilance","Flying"),"power" to "3","toughness" to "3","tokenArtwork" to template)
        assertEquals(ArtworkTokenIdentity("Soldier","Token Creature — Soldier","","1","1",setOf("W")),gameArtworkTokenIdentity(live))
        assertEquals("3",live["power"])
        assertEquals(listOf("Vigilance","Flying"),live["rules"])
        assertNull(gameArtworkTokenIdentity(live+mapOf("faceDown" to true)))
        assertNull(gameArtworkTokenIdentity(live+mapOf("isToken" to false)))
        assertNull(gameArtworkTokenIdentity(live+mapOf("tokenArtwork" to (template+mapOf("name" to "Other")))))
        assertNull(gameArtworkTokenIdentity(live+mapOf("tokenArtwork" to emptyMap<String,Any>())))
        assertNull(gameArtworkTokenIdentity(live+mapOf("tokenArtwork" to "invalid")))
    }

    @Test fun explicitCopySourceUsesSourceArtEvenWithChangedStats() {
        val copy=token+mapOf("name" to "The Scarab God","displayName" to "The Scarab God","power" to "4","toughness" to "4","copySourceArtworkName" to "The Scarab God")
        assertEquals("The Scarab God",gameArtworkSourceName(copy))
        assertNull(gameArtworkSourceName(copy+mapOf("copySourceArtworkName" to "Other card")))
        assertNull(gameArtworkSourceName(copy+mapOf("faceDown" to true)))
    }
}
