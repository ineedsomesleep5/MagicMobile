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
    private fun token(id:Int,name:String,type:String,rules:String,power:String?,colors:List<String>)=ArtworkCatalogue.decode(mapOf(
        "id" to "00000000-0000-0000-0000-%012d".format(id),"name" to name,"layout" to "token","type_line" to type,
        "oracle_text" to rules,"power" to power,"toughness" to power,"colors" to colors,
        "image_uris" to mapOf("normal" to "https://cards.scryfall.io/normal/$id.jpg")))!!

    @Test fun compactTokenDownloadsCountAsStored() {
        val files=setOf(artworkDownloadFileName("token:abc",ArtworkQuality.COMPACT))
        assertEquals(ArtworkQuality.COMPACT,TOKEN_DOWNLOAD_QUALITY)
        assertTrue(listedArtworkDownload(files,"token:abc",TOKEN_DOWNLOAD_QUALITY))
        assertFalse(listedArtworkDownload(files,"token:abc",ArtworkQuality.STANDARD))
        assertTrue(listedArtworkDownload(setOf(artworkDownloadFileName("token:abc",ArtworkQuality.HIGH)),"token:abc",TOKEN_DOWNLOAD_QUALITY))
    }
    @Test fun engineFoodWordingAndZeroStatsMatchScryfallFood() {
        val food=token(1,"Food","Token Artifact — Food","{2}, {T}, Sacrifice this token: You gain 3 life.",null,emptyList())
        for(rules in listOf("{2}, {T}, Sacrifice Food Token: You gain 3 life.","{2}, {T}, Sacrifice this artifact: You gain 3 life.","{2}, {T}, Sacrifice Food: You gain 3 life."))
            assertEquals(rules,food,selectEquivalentToken(listOf(food),ArtworkTokenIdentity("Food Token","Artifact — Food",rules,"0","0",emptySet())){true})
        assertNull(selectEquivalentToken(listOf(food),ArtworkTokenIdentity("Food Token","Artifact — Food","{2}, {T}, Sacrifice a Food Token: You gain 3 life.","0","0",emptySet())){true})
        assertNull(selectEquivalentToken(listOf(food),ArtworkTokenIdentity("Food Token","Artifact — Food","{2}, {T}, Sacrifice Food Token: Draw a card.","0","0",emptySet())){true})
        val zombie=token(2,"Zombie","Token Creature — Zombie","","2",listOf("B"))
        assertNull("A creature's 0/0 is a real size",selectEquivalentToken(listOf(zombie),ArtworkTokenIdentity("Zombie Token","Creature — Zombie","","0","0",setOf("B"))){true})
    }
    @Test fun offlineFallbackUsesTheOnlyDownloadedTokenWithTheSameIdentity() {
        val squirrel=token(1,"Squirrel","Token Creature — Squirrel","","1",listOf("G"))
        fun visible(rules:String,power:String="1",colors:Set<String> = setOf("G"))=ArtworkTokenIdentity("Squirrel Token","Creature — Squirrel",rules,power,"1",colors)
        assertNull("online keeps the exact match",selectEquivalentToken(listOf(squirrel),visible("Forestwalk")){true})
        assertEquals(squirrel,looseEquivalentToken(listOf(squirrel),visible("Forestwalk")){true})
        assertNull("a different printed P/T is a different token",looseEquivalentToken(listOf(squirrel),visible("Forestwalk","2")){true})
        assertNull("a different color is a different token",looseEquivalentToken(listOf(squirrel),visible("Forestwalk",colors=setOf("B"))){true})
        assertNull("needs a stored image",looseEquivalentToken(listOf(squirrel),visible("Forestwalk")){false})
        val flier=token(2,"Squirrel","Token Creature — Squirrel","Flying","1",listOf("G"))
        assertNull("two different downloads stay ambiguous",looseEquivalentToken(listOf(squirrel,flier),visible("Trample")){true})
        val treasure=token(3,"Treasure","Token Artifact — Treasure","{T}, Sacrifice this token: Add one mana of any color.",null,emptyList())
        assertEquals(treasure,looseEquivalentToken(listOf(treasure),ArtworkTokenIdentity("Treasure Token","Artifact — Treasure","{T}, Sacrifice Treasure: Add {C}.","0","0",emptySet())){true})
    }
    @Test fun rulesTextFindsChatterfangSquirrelsFoodAndTheCommonList() {
        assertEquals(listOf(io.magicmobile.android.core.TokenRules.Request("Squirrel","1","1",listOf("G"))),
            io.magicmobile.android.core.TokenRules.requests("If one or more tokens would be created under your control, those tokens plus that many 1/1 green Squirrel creature tokens are created instead."))
        assertEquals(listOf("Food","Treasure"),io.magicmobile.android.core.TokenRules.requests("Landfall — Whenever a land you control enters, create a Food token or a Treasure token.").map{it.name})
        assertEquals(listOf("Food","Treasure","Clue","Blood","Map","Powerstone","Incubator","Junk","Gold","Shard"),io.magicmobile.android.core.TokenRules.commonTokenNames)
    }
    @Test fun discoveredTokensMatchStatedStatsAndKeepOnePrintingPerIdentity() {
        val squirrel=token(2,"Squirrel","Token Creature — Squirrel","","1",listOf("G"))
        val reprint=token(1,"Squirrel","Token Creature — Squirrel","","1",listOf("G"))
        val big=token(3,"Squirrel","Token Creature — Squirrel","","2",listOf("G"))
        val food=token(4,"Food","Token Artifact — Food","{2}, {T}, Sacrifice this token: You gain 3 life.",null,emptyList())
        val bare=token(5,"Food","Token","",null,emptyList())
        val requests=listOf(io.magicmobile.android.core.TokenRules.Request("Squirrel","1","1",listOf("G")),io.magicmobile.android.core.TokenRules.Request("Food"))
        assertEquals(listOf(reprint,food),selectDiscoveredTokens(listOf(squirrel,reprint,big,food,bare),requests))
        assertEquals(2,selectDiscoveredTokens(listOf(squirrel,reprint,big),listOf(io.magicmobile.android.core.TokenRules.Request("Squirrel"))).size)
    }
    @Test fun tokenSearchesBatchTenExactNames() {
        val queries=tokenSearchQueries((0 until 12).map{"Name$it"}+listOf("Bad\" Name","Name0 Token"))
        assertEquals(listOf("t:token ("+(0 until 10).joinToString(" or "){"!\"Name$it\""}+")","t:token (!\"Name10\" or !\"Name11\")"),queries)
    }
    @Test fun liveSavedEquivalentTokenCountsAsStored() {
        val wanted=token(1,"Squirrel","Token Creature — Squirrel","","1",listOf("G"))
        val live=token(2,"Squirrel","Token Creature — Squirrel","","1",listOf("G"))
        val other=token(3,"Zombie","Token Creature — Zombie","","2",listOf("B"))
        val records=listOf(wanted,live,other).associateBy{it.id}
        val keys=listOf("token:${wanted.id}","token:${other.id}")
        assertEquals(setOf("token:${wanted.id}"),storedTokenKeys(keys,records){it=="token:${live.id}"})
        assertEquals(emptySet<String>(),storedTokenKeys(keys,records){false})
    }
    @Test fun opponentSelectionAndTokenSourcesMatchSetup() {
        val available=listOf("token-triumph","grave-danger","other")
        assertEquals(listOf("grave-danger"),selectedOpponentIDs(null,listOf(null,null,null),available))
        assertEquals(listOf("other","other","token-triumph"),selectedOpponentIDs(3,listOf("other","","token-triumph"),available))
        assertEquals(listOf("other"),selectedOpponentIDs(9,listOf("other"),available).distinct())
        assertEquals(tokenSourcesKey(listOf("b","a")),tokenSourcesKey(listOf("a","b","a")))
        assertEquals("deck-extras-v1:a,b",tokenSourcesKey(listOf("b","a")))
    }
    @Test fun tokenRefreshRequiresFullIdentityNotGenericName() {
        assertTrue(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier.copy(power="2",toughness="2")))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,null,soldier))
        assertFalse(artworkDownloadMatches("Soldier","Soldier",true,soldier,soldier))
    }
}
