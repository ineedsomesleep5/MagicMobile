package io.magicmobile.android.core

import java.io.ByteArrayInputStream
import java.util.UUID

private var deckStudioChecks = 0
private fun verifyDeckStudio(value: Boolean, label: String) {
    deckStudioChecks++
    check(value) { label }
}
private fun rejectsDeckStudio(label: String, block: () -> Unit) {
    deckStudioChecks++
    try { block() } catch (_: Exception) { return }
    error("Expected rejection: $label")
}

fun main() {
    val organization = DeckOrganization.create(listOf(" Control ", "contrôl", "Budget"), "Private note")
    verifyDeckStudio(organization.tags == listOf("Control", "Budget"), "tags normalized and deduplicated")
    rejectsDeckStudio("organization bounds") { DeckOrganization.create(List(25) { "tag-$it" }) }

    val catalogue = Catalogue(ByteArrayInputStream(
        """
        {"catalogueHash":"0000000000000000000000000000000000000000000000000000000000000000","upstreamCommit":"0000000000000000000000000000000000000000","sourceMetadataSHA256":"0000000000000000000000000000000000000000000000000000000000000000","nameAliases":{"Leader // Back":"Leader"}}
        {"name":"Leader","setCode":"TST","collectorNumber":"1","typeLine":"Legendary Creature","oracleText":"","manaCost":"{2}{U}","colorIdentity":["U"],"colors":["U"],"manaValue":3,"roles":["cardFlow"],"types":["CREATURE"]}
        {"name":"Island","setCode":"TST","collectorNumber":"2","typeLine":"Basic Land","oracleText":"","manaCost":null,"colorIdentity":[],"colors":[],"manaValue":0,"roles":[],"types":["LAND"]}
        {"name":"Answer","setCode":"TST","collectorNumber":"3","typeLine":"Instant","oracleText":"","manaCost":"{W}{U}","colorIdentity":["W","U"],"colors":["W","U"],"manaValue":2.5,"roles":["interaction","protection"],"types":["INSTANT"]}
        """.trimIndent().toByteArray()
    ))
    val deck = Deck("Parity", listOf(
        CardEntry("Leader // Back", 1, "commanders"),
        CardEntry("Island", 2), CardEntry("Answer", 2), CardEntry("Missing", 1),
        CardEntry("Idea", 1, "maybeboard"),
    ))
    val analysis = DeckAnalyzer.analyze(deck, catalogue)
    verifyDeckStudio(analysis.mainCardCount == 5 && analysis.excludedCardCount == 2, "main section is isolated")
    verifyDeckStudio(analysis.landCount == 2 && analysis.manaCurve == mapOf(2.5 to 2) &&
        analysis.manaCurveBins[2] == 2, "exact mana values and display buckets stay distinct")
    verifyDeckStudio(analysis.printedColorCounts["W"] == 2 && analysis.printedColorCounts["U"] == 2, "printed colors overlap")
    verifyDeckStudio(analysis.knownColorlessCount == 2 && analysis.unknownColorCount == 1, "known colorless differs from unknown")
    verifyDeckStudio(analysis.roles.getValue(DeckRole.INTERACTION).count == 2, "curated roles are quantity weighted")
    verifyDeckStudio(analysis.commanderColorIdentity == setOf("U"), "commander alias resolves identity")
    verifyDeckStudio(analysis.unknownNames == listOf("Missing"), "unresolved names remain explicit")

    rejectsDeckStudio("playing identity requires resolved names") { DeckSignature.from(deck, catalogue) }
    val resolvedDeck = deck.copy(entries = deck.entries.filterNot { it.name == "Missing" })
    val signature = DeckSignature.from(resolvedDeck, catalogue)
    verifyDeckStudio(signature.cards.map { it.section } == listOf(
        PlayingSection.MAIN, PlayingSection.MAIN, PlayingSection.COMMANDERS,
    ), "playing identity is canonical")
    val started = 1_000L
    fun summary(id: String, at: Long = started) = PlaytestSummary(
        id = id, matchId = UUID.randomUUID().toString(), seatId = "human",
        deck = signature, title = deck.name, engineUpstream = "xmage", catalogueHash = "test",
        appBuild = "1", aiOpponents = 1, startedAtMillis = at, observedAtMillis = at + 1,
        finishedAtMillis = at + 1, end = PlaytestEnd.COMPLETED, highestObservedTurn = 3,
        commanderCasts = mapOf("Leader" to 1), won = null, lastRevision = 4,
        viewerPlayerId = UUID.randomUUID().toString(),
    )
    val first = summary(UUID.randomUUID().toString())
    verifyDeckStudio(PlaytestHistory.create().record(first).forDeck(signature) == listOf(first), "history matches exact playing cards")
    val bounded = (0..100).fold(PlaytestHistory.create()) { history, index ->
        history.record(summary(UUID.randomUUID().toString(), started + index))
    }
    verifyDeckStudio(bounded.summaries.size == 100 && bounded.summaries.first().startedAtMillis == started + 100, "history remains bounded and newest first")
    rejectsDeckStudio("win is not inferred for interruption") { first.copy(end = PlaytestEnd.INTERRUPTED, won = false) }
    val landDeck = Deck("Lands", listOf(CardEntry("Island", 2), CardEntry("Island", 1), CardEntry("Island", 4, "maybeboard"), CardEntry("Leader", 1, "commanders")))
    val lands = DeckEditing.setBasics(landDeck, DeckEditing.basics.associateWith { if(it == "Island") 8 else 0 })
    verifyDeckStudio(lands.entries.filter { it.section == "deck" } == listOf(CardEntry("Island", 8)) && lands.entries.contains(CardEntry("Island", 4, "maybeboard")), "basic land operation consolidates main only and preserves other boards")
    verifyDeckStudio(DeckEditing.replace(landDeck, 0, "Plains").entries[0] == CardEntry("Plains", 2), "replacement preserves count and board")
    rejectsDeckStudio("basic lands total bound") { DeckEditing.setBasics(landDeck, DeckEditing.basics.associateWith { 2000 }) }
    val link = DeckLinkImport.source("https://archidekt.com/decks/123/my-deck")
    verifyDeckStudio(link.endpoint == "https://archidekt.com/api/decks/123/", "provider endpoint built from checked ID")
    rejectsDeckStudio("arbitrary host") { DeckLinkImport.source("https://example.com/decks/123") }
    rejectsDeckStudio("credentials") { DeckLinkImport.source("https://secret@archidekt.com/decks/123") }
    rejectsDeckStudio("encoded path") { DeckLinkImport.source("https://archidekt.com/decks/%31") }
    val publicDeck: Obj = mapOf("id" to 123, "private" to false, "unlisted" to false, "name" to "Public deck", "categories" to listOf(mapOf("name" to "Maybeboard", "includedInDeck" to false)), "cards" to listOf(mapOf("quantity" to 2, "categories" to listOf("Maybeboard"), "card" to mapOf("oracleCard" to mapOf("name" to "Island")))))
    verifyDeckStudio(DeckLinkImport.decode(link,publicDeck).entries == listOf(CardEntry("Island",2,"maybeboard")), "provider excluded cards preserved for review")
    rejectsDeckStudio("private provider response") { DeckLinkImport.decode(link,publicDeck + ("private" to true)) }
    rejectsDeckStudio("mismatched provider ID") { DeckLinkImport.decode(link,publicDeck + ("id" to 124)) }
    val moxfield = DeckLinkImport.source("https://moxfield.com/decks/abcdefghijklmnopqrstuv")
    val moxDeck: Obj = mapOf("name" to "Mox", "publicId" to moxfield.id, "visibility" to "public", "boards" to mapOf("commanders" to mapOf("cards" to mapOf("1" to mapOf("quantity" to 1, "card" to mapOf("name" to "Leader"))))))
    verifyDeckStudio(DeckLinkImport.decode(moxfield,moxDeck).entries.single() == CardEntry("Leader",1,"commanders"), "Moxfield board mapping retains commander")
    rejectsDeckStudio("unknown nonempty Moxfield board") { DeckLinkImport.decode(moxfield,moxDeck + ("boards" to mapOf("unknown" to mapOf("cards" to mapOf("1" to mapOf("quantity" to 1, "card" to mapOf("name" to "Leader"))))))) }
    val decorated=DeckTextImport.preview("Decorated","1 Leader (TST) 123 *F* [Commander{top}]\n// Lands\n8 Island (TST) 2")
    verifyDeckStudio(decorated.deck.entries==listOf(CardEntry("Leader",1,"commanders"),CardEntry("Island",8))&&decorated.annotations.size==5,"printing foil category and grouping are retained as review annotations")
    rejectsDeckStudio("conflicting decorated section") {DeckTextImport.preview("Conflict","Sideboard\n1 Leader [Commander]")}
    rejectsDeckStudio("malformed suffix") {DeckTextImport.preview("Malformed","1 Island [Oops")}
    val custom=Deck("Custom board",listOf(CardEntry("Island",1,"future board")))
    verifyDeckStudio(DeckTextImport.preview("Ignored",io.magicmobile.core.Json.write(mapOf("format" to "magicmobile-deck-v1","deck" to custom.json()))).deck==custom,"JSON export preserves arbitrary section names exactly")
    val iosJSON="""{"name":"iOS source","commander":{"cardName":"Leader","quantity":1,"section":"commander"},"entries":[{"cardName":"Partner","quantity":1,"section":"commanders"},{"cardName":"Island","quantity":95,"section":"main"},{"cardName":"Friend","quantity":1,"section":"companions"},{"cardName":"Answer","quantity":2,"section":"sideboard"},{"cardName":"Idea","quantity":3,"section":"maybeboard"},{"cardName":"Odd (Name)","quantity":4,"section":"custom board"}]}"""
    val iosPreview=DeckTextImport.preview("Ignored",iosJSON)
    verifyDeckStudio(iosPreview.deck.name=="iOS source"&&iosPreview.deck.entries.map{it.quantity}==listOf(1,1,95,1,2,3,4)&&iosPreview.deck.entries.map{it.section}==listOf("commanders","commanders","deck","companions","sideboard","maybeboard","custom board"),"iOS primary partner all boards and quantities preserved")
    verifyDeckStudio(iosPreview.originalText==iosJSON&&iosPreview.annotations.size==2,"iOS aliases explicitly annotated with original JSON retained")
    verifyDeckStudio(DeckTextImport.preview("Ignored",DeckTextImport.exportJSON(iosPreview.deck)).deck==iosPreview.deck,"iOS-compatible export reimports all rows without loss")
    verifyDeckStudio(DeckTextImport.preview("Ignored",io.magicmobile.core.Json.write(custom.json())).deck==custom,"legacy bare Android JSON preserved")
    verifyDeckStudio(DeckTextImport.preview("Ignored","""{"name":"Empty iOS","entries":[]}""").deck.entries.isEmpty(),"iOS omitted nil commander and empty entries accepted")
    rejectsDeckStudio("malformed iOS quantity") {DeckTextImport.preview("Ignored",iosJSON.replace("\"quantity\":95","\"quantity\":1.5"))}
    rejectsDeckStudio("mixed JSON row schemas") {DeckTextImport.preview("Ignored",iosJSON.replace("\"cardName\":\"Island\"","\"name\":\"Island\""))}
    rejectsDeckStudio("unknown root JSON fields") {DeckTextImport.preview("Ignored","""{"name":"Extra","entries":[],"mystery":true}""")}
    rejectsDeckStudio("unknown card JSON fields") {DeckTextImport.preview("Ignored","""{"name":"Extra","entries":[{"name":"Island","quantity":1,"section":"deck","foil":true}]}""")}
    rejectsDeckStudio("unsupported JSON version") {DeckTextImport.preview("Ignored","""{"format":"magicmobile-deck-v2","deck":{"name":"Future","entries":[]}}""")}
    rejectsDeckStudio("lossy plain text custom board") {DeckTextImport.exportText(custom)}
    rejectsDeckStudio("lossy plain text decorated name") {DeckTextImport.exportText(Deck("Decorated name",listOf(CardEntry("Card (SET) 1",1))))}
    verifyDeckStudio(DeckTextImport.preview("Lands",DeckTextImport.exportText(landDeck)).deck==landDeck,"plain text standard boards preserve all rows")
    val partnered=Deck("Partners",listOf(CardEntry("Old",1,"commanders"),CardEntry("Partner",1,"commanders"),CardEntry("New",3),CardEntry("Idea",1,"maybeboard")))
    val promoted=DeckEditing.replaceCommander(partnered,"New",true)
    verifyDeckStudio(promoted.entries==listOf(CardEntry("New",1,"commanders"),CardEntry("Partner",1,"commanders"),CardEntry("New",2),CardEntry("Idea",1,"maybeboard"),CardEntry("Old",1,"maybeboard")),"commander promotion keeps partner and old commander and moves exactly one main copy")
    verifyDeckStudio(DeckEditing.replaceCommander(promoted,"New",true)==promoted,"same commander selection is a no-op")
    verifyDeckStudio(DeckEditing.replaceCommander(partnered,"New",false).entries.none{it.name=="Old"},"old commander optional removal")
    val full=Deck("Full",listOf(CardEntry("Old",1,"commanders"),CardEntry("Island",1999)))
    rejectsDeckStudio("commander transaction rejects overflow without changing input"){DeckEditing.replaceCommander(full,"New",true)}
    verifyDeckStudio(full.entries.first().name=="Old"&&full.entries.sumOf{it.quantity}==2000,"failed commander edit preserves original")
    verifyDeckStudio(DeckEditing.boards.all{board->DeckEditing.move(partnered,2,board).entries[2]==CardEntry("New",3,board)},"all five destination boards preserve names and quantities")
    val searchCards=(0..100).map{catalogue.find("Answer")!!.copy(name="A off-color $it")}+catalogue.find("Leader")!!.copy(name="Z match",setCodes=listOf("ALT"),manaValue=3.5)+catalogue.find("Island")!!
    verifyDeckStudio(DeckCatalogueSearch.search(searchCards,type="Creature",setCode="alt",minimum=3.0,maximum=4.0,allowedIdentity=setOf("U"),limit=1).single().name=="Z match","type set mana and identity filters apply before limit")
    verifyDeckStudio(DeckCatalogueSearch.search(searchCards,allowedIdentity=emptySet()).map{it.name}==listOf("Island"),"colorless commander identity excludes colored cards")
    verifyDeckStudio(DeckCatalogueSearch.search(listOf(catalogue.find("Island")!!.copy(identity=null)),allowedIdentity=emptySet()).isEmpty(),"unknown identity never assumed colorless")
    rejectsDeckStudio("reversed mana filter"){DeckCatalogueSearch.search(searchCards,minimum=4.0,maximum=3.0)}
    verifyDeckStudio(DeckCatalogueSearch.search(listOf(catalogue.find("Leader")!!.copy(rules="Draw a card")),query="draw").size==1,"rules-text local search")
    val legacyAliases=Deck("Legacy aliases",listOf(CardEntry("Leader",1," CoMmAnDeR "),CardEntry("Island",3," MAINBOARD "),CardEntry("Answer",2,"main"),CardEntry("Answer",1," Companion "),CardEntry("Island",1," Considering "),CardEntry("Island",1," My CUSTOM Board ")))
    val canonicalAliases=Deck.decode(legacyAliases.json())
    verifyDeckStudio(canonicalAliases.entries.map{it.section}==listOf("commanders","deck","deck","companions","maybeboard"," My CUSTOM Board "),"persisted legacy known aliases normalize while custom section is verbatim")
    val androidAliasSource=io.magicmobile.core.Json.write(mapOf("format" to "magicmobile-deck-v1","deck" to legacyAliases.json()))
    val androidAliasPreview=DeckTextImport.preview("Ignored",androidAliasSource)
    verifyDeckStudio(androidAliasPreview.deck==canonicalAliases&&androidAliasPreview.annotations.size==5&&androidAliasPreview.originalText==androidAliasSource,"Android envelope aliases are annotated with full original source")
    verifyDeckStudio(DeckTextImport.preview("Ignored",io.magicmobile.core.Json.write(legacyAliases.json())).deck==canonicalAliases,"bare Android JSON normalizes same aliases")
    val iosAliasSource=DeckTextImport.exportJSON(legacyAliases)
    verifyDeckStudio(DeckTextImport.preview("Ignored",iosAliasSource).deck==canonicalAliases,"iOS schema normalizes exactly the same aliases")
    rejectsDeckStudio("unknown play section is never silently excluded") { catalogue.resolve(canonicalAliases,true) }
    val playableAliases=canonicalAliases.copy(entries=canonicalAliases.entries.filter{it.section in DeckEditing.boards})
    val resolvedAliases=catalogue.resolve(playableAliases,true)
    verifyDeckStudio(resolvedAliases.array("main").map{Wire.objectValue(it).text("name")}==listOf("Island","Answer")&&resolvedAliases.array("commanders").size==1&&resolvedAliases.array("companions").size==1,"persisted aliases reach intended native playing sections")
    verifyDeckStudio(DeckSignature.from(canonicalAliases,catalogue).cards.sumOf{it.quantity}==7,"signature retains canonical main commander and companion quantities")
    val replacedAliases=DeckEditing.replaceCommander(canonicalAliases,"Answer",true)
    verifyDeckStudio(replacedAliases.entries.first()==CardEntry("Answer",1,"commanders")&&replacedAliases.entries.any{it==CardEntry("Answer",1,"deck")}&&replacedAliases.entries.any{it==CardEntry("Leader",1,"maybeboard")},"commander replacement operates correctly after persisted alias decode")
    val utf8Text="1 Éowyn, Shieldmaiden"
    verifyDeckStudio(DeckTextImport.strictUTF8(utf8Text.toByteArray())==utf8Text,"valid multilingual UTF-8 stays exact")
    rejectsDeckStudio("malformed UTF-8 cannot silently replace card bytes"){DeckTextImport.strictUTF8(byteArrayOf(0x31,0x20,0xC3.toByte(),0x28))}
    rejectsDeckStudio("truncated UTF-8 cannot silently replace card bytes"){DeckTextImport.strictUTF8(byteArrayOf(0xF0.toByte(),0x9F.toByte()))}
    verifyDeckStudio(DeckTextImport.preview("Ignored",DeckTextImport.strictUTF8(("\uFEFF"+iosJSON).toByteArray())).deck==iosPreview.deck,"UTF-8 BOM JSON imports without altering receipt source")
    println("PASS: $deckStudioChecks Android Deck Studio core assertions")
}
