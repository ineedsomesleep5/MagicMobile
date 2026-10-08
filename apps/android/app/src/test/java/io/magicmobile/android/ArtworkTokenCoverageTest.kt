package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

/**
 * Every token and emblem a catalogue card points to is in what a download fetches, a double-faced token's back is
 * downloaded with it, and chosen art is saved and requested by exact printing. TokenDownloadCoverageTests.swift and
 * CardArtChoicesTests.swift follow the same cases.
 */
class ArtworkTokenCoverageTest {
    private val soldier="00000000-0000-0000-0000-000000000001"
    private val otherSoldierPrinting="00000000-0000-0000-0000-000000000002"
    private val incubator="00000000-0000-0000-0000-000000000003"
    private val emblem="00000000-0000-0000-0000-000000000004"
    private val vampire="00000000-0000-0000-0000-000000000005"
    private val absent="00000000-0000-0000-0000-000000000006"
    private fun images(path:String)=mapOf("small" to "https://cards.scryfall.io/small/$path.jpg","normal" to "https://cards.scryfall.io/normal/$path.jpg","large" to "https://cards.scryfall.io/large/$path.jpg")
    private fun part(id:String,name:String,component:String,type:String):Obj=mapOf("id" to id,"name" to name,"component" to component,"type_line" to type)
    private fun token(id:String,name:String,type:String,power:String?="1",toughness:String?="1",colors:List<String> = listOf("W"),layout:String="token"):Obj =
        mapOf("id" to id,"name" to name,"layout" to layout,"type_line" to type,"oracle_text" to "","colors" to colors,"image_uris" to images(name.lowercase().replace(' ','-')+"-"+id.takeLast(2))) +
            listOfNotNull(power?.let{"power" to it},toughness?.let{"toughness" to it})
    private fun catalogue(rows:List<Obj>)=ArtworkCatalogue.parse(ByteArrayInputStream(rows.joinToString("\n"){String(Wire.encode(it))}.toByteArray()))
    private val maker=mapOf("layout" to "normal","type_line" to "Creature")
    private fun fixture()=catalogue(listOf(
        // 1: the token itself is in the bulk.
        maker+mapOf("id" to "10000000-0000-0000-0000-000000000001","name" to "Maker One","all_parts" to listOf(part(soldier,"Soldier","token","Token Creature — Soldier"))),
        token(soldier,"Soldier","Token Creature — Soldier"),
        // 2: the card points at another printing of a token the bulk holds under a different ID.
        maker+mapOf("id" to "10000000-0000-0000-0000-000000000002","name" to "Maker Two","all_parts" to listOf(part(otherSoldierPrinting,"Soldier","token","Token Creature — Soldier"))),
        // 3: a double-faced token: both faces are downloadable.
        maker+mapOf("id" to "10000000-0000-0000-0000-000000000003","name" to "Maker Three","all_parts" to listOf(part(incubator,"Incubator // Phyrexian","token","Token Artifact — Incubator // Token Artifact Creature — Phyrexian"))),
        mapOf("id" to incubator,"name" to "Incubator // Phyrexian","layout" to "double_faced_token","type_line" to "Token Artifact — Incubator // Token Artifact Creature — Phyrexian",
            "card_faces" to listOf(
                mapOf("name" to "Incubator","type_line" to "Token Artifact — Incubator","oracle_text" to "{2}: Transform this artifact.","colors" to emptyList<String>(),"image_uris" to images("incubator-front")),
                mapOf("name" to "Phyrexian","type_line" to "Token Artifact Creature — Phyrexian","oracle_text" to "","power" to "0","toughness" to "0","colors" to emptyList<String>(),"image_uris" to images("incubator-back")))),
        // 4: an emblem, which Scryfall links as a combo piece, not as a token.
        maker+mapOf("id" to "10000000-0000-0000-0000-000000000004","name" to "Maker Four","type_line" to "Legendary Planeswalker — Sorin","all_parts" to listOf(
            part(vampire,"Vampire","token","Token Creature — Vampire"),part("20000000-0000-0000-0000-000000000001","Maker Four","combo_piece","Legendary Planeswalker — Sorin"),
            part(emblem,"Maker Four Emblem","combo_piece","Emblem — Sorin"))),
        token(vampire,"Vampire","Token Creature — Vampire",colors=listOf("B")),
        mapOf("id" to emblem,"name" to "Maker Four Emblem","layout" to "emblem","type_line" to "Emblem — Sorin","oracle_text" to "Creatures you control get +1/+0.","colors" to emptyList<String>(),"image_uris" to images("emblem")),
        // 5: a token that is neither in the bulk nor like any token in it, beside a meld part that is no token.
        maker+mapOf("id" to "10000000-0000-0000-0000-000000000005","name" to "Maker Five","all_parts" to listOf(
            part(absent,"Shard Golem","token","Token Artifact Creature — Golem"),part("20000000-0000-0000-0000-000000000002","Meld Half","meld_part","Legendary Creature — Eldrazi")))))

    @Test fun emblemsLinkedAsComboPiecesCountAsTokensButMeldAndComboPiecesDoNot() {
        assertTrue(isTokenPart("token",null))
        assertTrue(isTokenPart("combo_piece","Emblem — Sorin"))
        assertTrue(isTokenPart("meld_result","Token Creature — Eldrazi"))
        assertFalse(isTokenPart("combo_piece","Legendary Planeswalker — Sorin"))
        assertFalse(isTokenPart("meld_part","Legendary Creature — Eldrazi"))
        assertFalse(isTokenPart("combo_piece",null))
        assertEquals(listOf("Vampire","Maker Four Emblem"),fixture().card("Maker Four")!!.related.map{it.name})
    }

    @Test fun everyFaceAndEmblemIsDownloadableAndOnlyTheUnresolvedReferencedTokenIsMissing() {
        val catalogue=fixture()
        assertEquals(setOf("Soldier","Incubator","Phyrexian","Vampire","Maker Four Emblem"),catalogue.tokens.values.mapNotNull{it.token?.name}.toSet())
        assertEquals(setOf(soldier,incubator,"$incubator:back",vampire,emblem),catalogue.tokens.keys)
        assertEquals(listOf(absent),catalogue.referencedTokensWithoutDownload().map{it.id})
        assertEquals("Shard Golem",catalogue.referencedTokensWithoutDownload().single().name)
        assertTrue(catalogue.unavailableTokens.isEmpty())
    }

    /** The test that fails when a catalogue card points to a token a download would skip. */
    @Test fun afterAResolveEveryTokenAnyCardPointsToIsInTheDownloadSet() {
        val catalogue=fixture()
        catalogue.tokens.putAll(catalogue(listOf(token(absent,"Shard Golem","Token Artifact Creature — Golem","2","2",emptyList()))).tokens)
        assertEquals(emptyList<ArtworkPart>(),catalogue.referencedTokensWithoutDownload())
        for(name in listOf("Maker One","Maker Two","Maker Three","Maker Four","Maker Five")) for(related in catalogue.card(name)!!.related) {
            val front=related.name.substringBefore(" // ")
            val covered=related.id in catalogue.tokens||catalogue.tokens.values.any{ArtworkTokenIdentity.tokenNameKey(it.token!!.name)==ArtworkTokenIdentity.tokenNameKey(front)}
            assertTrue("$name points to ${related.name}, which no download would fetch",covered)
        }
        assertTrue(absent in catalogue.tokens)
    }

    @Test fun aTokenScryfallDoesNotReturnStaysReportedAsMissing() {
        val catalogue=fixture()
        catalogue.tokens.putAll(catalogue(listOf(maker+mapOf("id" to "10000000-0000-0000-0000-000000000009","name" to "Unrelated"))).tokens)
        assertEquals(listOf("Shard Golem"),catalogue.referencedTokensWithoutDownload().map{it.name})
    }

    @Test fun aDoubleFacedTokensBackHasItsOwnIdentityKeyAndSurvivesBeingSaved() {
        val back=fixture().tokens["$incubator:back"]!!
        assertEquals("Phyrexian",back.token!!.name)
        assertEquals("Token Artifact Creature — Phyrexian",back.token!!.typeLine)
        assertEquals(images("incubator-back")["normal"],back.images["normal"])
        // Saved in a .token file and read again, it keeps its ":back" key and identity.
        val restored=ArtworkCatalogue.decode(back.json())!!
        assertEquals("$incubator:back",restored.id)
        assertEquals(back.token!!.normalized(),restored.token!!.normalized())
        // The front matches its own identity, not the back's.
        assertEquals("Incubator",fixture().tokens[incubator]!!.token!!.name)
    }

    @Test fun aMatchedFrontFaceBringsItsBackFaceIntoADeckDownload() {
        val records=fixture().tokens.values
        val selected=selectDiscoveredTokens(records,listOf(TokenRules.Request("Incubator")))
        assertEquals(listOf(incubator,"$incubator:back"),selected.map{it.id})
        // Matching only the back asks for just the back.
        assertEquals(listOf("$incubator:back"),selectDiscoveredTokens(records,listOf(TokenRules.Request("Phyrexian"))).map{it.id})
    }

    @Test fun tokenSearchResultsIncludeDoubleFacedTokensWithBothFaces() {
        val row=mapOf("id" to incubator,"name" to "Incubator // Phyrexian","layout" to "double_faced_token","type_line" to "Token Artifact — Incubator // Token Artifact Creature — Phyrexian",
            "card_faces" to listOf(
                mapOf("name" to "Incubator","type_line" to "Token Artifact — Incubator","oracle_text" to "","colors" to emptyList<String>(),"image_uris" to images("f")),
                mapOf("name" to "Phyrexian","type_line" to "Token Artifact Creature — Phyrexian","oracle_text" to "","power" to "0","toughness" to "0","colors" to emptyList<String>(),"image_uris" to images("b"))))
        val ordinary=token(soldier,"Soldier","Token Creature — Soldier")
        val other=maker+mapOf("id" to vampire,"name" to "Not a token")
        val (records,more)=tokenSearchPage(mapOf("object" to "list","has_more" to false,"data" to listOf(row,ordinary,other)))
        assertFalse(more)
        assertEquals(listOf(incubator,"$incubator:back",soldier),records.map{it.id})
    }

    @Test fun chosenArtIsSavedAndRequestedByExactPrinting() {
        val cmm=CardPrinting.of("cmm","400")!!
        assertEquals("print:cmm/400",printingArtKey(cmm))
        assertEquals("print:cmm/400:back",printingArtKey(cmm,true))
        assertNotEquals(printingArtKey(cmm),"Sol Ring")
        assertEquals("print:cmm/400",printingArtKey(CardArtChoices.Selection(cmm,false)))
        // A saved download of the printing refreshes the view that chose it, and the default art stays the fallback.
        assertTrue(artworkDownloadMatches("print:cmm/400","Sol Ring",false,null,null,"print:cmm/400"))
        assertTrue(artworkDownloadMatches("Sol Ring","Sol Ring",false,null,null,"print:cmm/400"))
        assertFalse(artworkDownloadMatches("print:c21/263","Sol Ring",false,null,null,"print:cmm/400"))
        assertFalse(artworkDownloadMatches("print:cmm/400","Sol Ring",true,null,null,"print:cmm/400"))
        // The picture of a double-faced printing: its front, or its reverse face.
        val delver=ArtworkCatalogue.decode(mapOf("id" to soldier,"name" to "Delver of Secrets // Insectile Aberration","layout" to "transform",
            "card_faces" to listOf(mapOf("name" to "Delver of Secrets","image_uris" to images("front")),mapOf("name" to "Insectile Aberration","image_uris" to images("back")))))!!
        assertEquals(images("front")["large"],printingImage(delver,false,"large"))
        assertEquals(images("back")["large"],printingImage(delver,true,"large"))
        assertEquals(images("back")["normal"],printingBackFace(delver)!!.images["normal"])
        val single=ArtworkCatalogue.decode(mapOf("id" to soldier,"name" to "Sol Ring","layout" to "normal","image_uris" to images("ring")))!!
        assertNull(printingImage(single,true,"large"))
        assertNull(printingBackFace(single))
    }

    @Test fun chosenArtInADeckListsEachPrintingOnceCommanderFirst() {
        val a=CardPrinting.of("cmm","400")!!;val b=CardPrinting.of("c21","1")!!
        val deck=Deck("Art",listOf(CardEntry("Sol Ring",1,"deck",a),CardEntry("Sol Ring",1,"sideboard",a),CardEntry("Forest",20,"deck"),CardEntry("Atraxa",1,"commanders",b)))
        assertEquals(listOf("Atraxa · C21 1","Sol Ring · CMM 400"),ChosenArt.choices(deck).map{it.label})
        assertEquals("CMM 400",ChosenArt("",a).label)
    }

    @Test fun downloadRequestsKeepTheChosenArtAndOlderOnesStillRestore() {
        val a=CardPrinting.of("cmm","400")!!
        val request=ArtworkDownloadRequest(listOf("Sol Ring"),ArtworkQuality.STANDARD,true,false,listOf(ChosenArt("Sol Ring",a),ChosenArt("Delver",CardPrinting.of("isd","51")!!)))
        assertEquals(request,ArtworkDownloadRequest.decode(request.encode()))
        val old=Wire.decode(request.encode())-"chosen"
        assertEquals(emptyList<ChosenArt>(),ArtworkDownloadRequest.decode(Wire.encode(old)).chosen)
        val valid=Wire.decode(request.encode())
        listOf(valid+("chosen" to "x"),valid+("chosen" to listOf("cmm/400")),valid+("chosen" to listOf(mapOf("name" to "A","printing" to "../1"))),
            valid+("chosen" to listOf(mapOf("name" to "A","printing" to "cmm/400"),mapOf("name" to "B","printing" to "cmm/400")))).forEach{
            assertTrue(runCatching{ArtworkDownloadRequest.decode(Wire.encode(it))}.isFailure)
        }
        // A deck's chosen art alone is enough to download.
        val artOnly=ArtworkDownloadRequest(emptyList(),ArtworkQuality.STANDARD,false,false,listOf(ChosenArt("Sol Ring",a)))
        assertEquals(artOnly,ArtworkDownloadRequest.decode(artOnly.encode()))
    }
}
