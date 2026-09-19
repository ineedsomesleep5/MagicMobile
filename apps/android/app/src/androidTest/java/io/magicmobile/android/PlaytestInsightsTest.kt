package io.magicmobile.android

import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import io.magicmobile.android.core.*
import io.magicmobile.core.Json
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class PlaytestInsightsTest {
    @Test fun selectedDeckExportExcludesOtherAndLegacyGames() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val root=File(context.cacheDir,"playtest-insights-${UUID.randomUUID()}").apply{mkdirs()}
        val isolated=object:ContextWrapper(context){override fun getNoBackupFilesDir()=root}
        val signature=DeckSignature.canonical(listOf(PlayingCard("Island",10,PlayingSection.MAIN),PlayingCard("Example Commander",1,PlayingSection.COMMANDERS)))
        fun game(quantity:Int?,end:String="completed",won:Boolean?=true):Obj=mapOf(
            "id" to UUID.randomUUID().toString(),"matchId" to UUID.randomUUID().toString(),"deckName" to "Private test deck",
            "deck" to quantity?.let{listOf(mapOf("name" to "Island","quantity" to it,"section" to "MAIN"),mapOf("name" to "Example Commander","quantity" to 1,"section" to "COMMANDERS"))},
            "commanderNames" to listOf("Example Commander"),"aiOpponents" to 1,"aiSkill" to 2,
            "upstream" to "verified-upstream","catalogueHash" to "verified-catalogue","appBuild" to "1.2",
            "startedAt" to 1000,"observedAt" to 121000,"finishedAt" to 121000,"highestTurn" to 4,
            "commanderCasts" to mapOf("Example Commander" to 1),"end" to end,"won" to won,
            "lastRevision" to 12,"viewerPlayerId" to null,
        )
        val file=File(root,"playtests-v1.json")
        try {
            file.writeText(Json.write(mapOf("schema" to 3,"games" to listOf(game(10),game(9),game(null)))))
            val store=PlaytestStore(isolated)
            assertEquals(3,store.all().size)
            assertEquals(1,store.forDeck(signature).size)
            val exported=Wire.decode(store.exportJson(signature).toByteArray()).array("games")
            assertEquals(1,exported.size)
            val row=Wire.objectValue(exported.single())
            assertEquals(10L,Wire.objectValue(row.array("deck").first()).number("quantity"))
            assertEquals("Won",store.forDeck(signature).single().resultLabel())
            assertFalse(row.containsKey("hands"));assertFalse(row.containsKey("opponentDecks"))
            file.writeText(Json.write(mapOf("schema" to 3,"games" to listOf(game(10,"interrupted",null)))))
            assertEquals("Interrupted",store.forDeck(signature).single().resultLabel())
            file.writeText("corrupt source evidence")
            assertTrue(runCatching{store.exportJson(signature)}.isFailure)
            assertEquals("corrupt source evidence",file.readText())
        } finally {file.delete();root.delete()}
    }
}
