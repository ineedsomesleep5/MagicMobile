package io.magicmobile.android

import org.junit.Assert.*
import org.junit.Test

class ArtworkRefreshTest {
    private fun zombie(id:String,layout:String="token")=ArtworkCatalogue.decode(mapOf(
        "id" to id,"name" to "Zombie","layout" to layout,"type_line" to "Token Creature — Zombie",
        "oracle_text" to "","power" to "2","toughness" to "2","colors" to listOf("B"),
        "image_uris" to mapOf("normal" to "https://cards.scryfall.io/test.jpg")))!!

    @Test fun equivalentPrintingsChooseStoredImageDeterministically() {
        val first=zombie("00000000-0000-0000-0000-000000000101")
        val second=zombie("00000000-0000-0000-0000-000000000102")
        val identity=ArtworkTokenIdentity("Zombie Token","Token Creature — Zombie","","2","2",setOf("B"))
        assertEquals(second,selectEquivalentToken(listOf(first,second),identity){it.id==second.id})
        assertEquals(first,selectEquivalentToken(listOf(second,first),identity){true})
        assertNull(selectEquivalentToken(listOf(first,second),identity.copy(power="4")){true})
    }

    @Test fun tokenSearchReadsBoundedFlatPagesAndRejectsMalformedResponses() {
        val flat=mapOf("id" to "00000000-0000-0000-0000-000000000101","name" to "Zombie","layout" to "token",
            "type_line" to "Token Creature — Zombie","power" to "2","toughness" to "2","colors" to listOf("B"),
            "image_uris" to mapOf("normal" to "https://cards.scryfall.io/test.jpg"))
        val page=mapOf("object" to "list","has_more" to true,"data" to listOf(flat+mapOf("layout" to "double_faced_token"),flat))
        val (records,more)=tokenSearchPage(page)
        assertTrue(more)
        assertEquals(1,records.size)
        assertEquals(ArtworkTokenIdentity("Zombie","Token Creature — Zombie","","2","2",setOf("B")),records.single().token)
        assertTrue(runCatching{tokenSearchPage(page-"has_more")}.isFailure)
        assertTrue(runCatching{tokenSearchPage(page+mapOf("data" to List(201){flat}))}.isFailure)
    }

    @Test fun failedLookupCooldownExpiresAndNamesStayExact() {
        assertFalse(tokenLookupAllowed(1000,1001,300000))
        assertTrue(tokenLookupAllowed(1000,301000,300000))
        assertTrue(tokenLookupAllowed(1000,999,300000))
        assertTrue(safeTokenSearchName("Zombie"))
        assertFalse(safeTokenSearchName("Zombie\" t:card"))
        assertFalse(safeTokenSearchName("Zombie\\"))
    }
    @Test fun upstreamTokenSuffixMatchesOnlyCompleteTokenIdentity() {
        val visible=ArtworkTokenIdentity("Cat Beast Token","Token Creature — Cat Beast","","4","4",setOf("G"))
        val printing=visible.copy(name="Cat Beast")
        assertTrue(artworkDownloadMatches("token:123","Cat Beast Token",true,visible,printing))
        assertFalse(artworkDownloadMatches("token:123","Cat Beast Token",true,visible,printing.copy(colors=setOf("W"))))
        assertFalse(artworkDownloadMatches("Cat Beast","Cat Beast Token",true,visible,printing))
    }
    @Test fun vanillaTokenWithoutOracleTextStillHasSafeIdentity() {
        val record=ArtworkCatalogue.decode(mapOf("id" to "00000000-0000-0000-0000-000000000123","name" to "Zombie",
            "layout" to "token","type_line" to "Token Creature — Zombie","power" to "2","toughness" to "2",
            "colors" to listOf("B"),"image_uris" to mapOf("normal" to "https://cards.scryfall.io/test.jpg")))
        assertEquals(ArtworkTokenIdentity("Zombie","Token Creature — Zombie","","2","2",setOf("B")),record?.token)
    }
    private val soldier=ArtworkTokenIdentity("Soldier","Token Creature — Soldier","","1","1",setOf("W"))
    @Test fun savedImageRefreshesOnlyMatchingDisplayedCard() {
        assertTrue(artworkDownloadMatches("Island","Island",false,null,null))
        assertFalse(artworkDownloadMatches("Swamp","Island",false,null,null))
        assertFalse(artworkDownloadMatches("token:123","Soldier",false,null,null))
    }
    @Test fun tokenRefreshRequiresFullIdentityNotGenericName() {
        assertTrue(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier.copy(power="2",toughness="2")))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,null,soldier))
        assertFalse(artworkDownloadMatches("Soldier","Soldier",true,soldier,soldier))
    }
}
