package io.magicmobile.android.core

import java.io.ByteArrayInputStream

private var providerChecks = 0
private fun verifyProvider(value: Boolean, label: String) {
    providerChecks++
    check(value) { label }
}
private fun rejectsProvider(label: String, block: () -> Unit) {
    providerChecks++
    try { block() } catch (_: Exception) { return }
    error("Expected rejection: $label")
}

fun main() {
    val search = ProviderDiscovery.scryfallSearchUri("Sol Ring & type:artifact")
    verifyProvider(search.scheme == "https" && search.host == "api.scryfall.com" &&
        search.rawQuery == "q=Sol%20Ring%20%26%20type%3Aartifact&unique=cards&page=1", "Scryfall query is encoded")
    rejectsProvider("Scryfall page is bounded") { ProviderDiscovery.scryfallSearchUri("card", 11) }
    rejectsProvider("provider credentials") {
        ProviderDiscovery.requireProviderUri(java.net.URI("https://name:secret@api.scryfall.com/cards/search"), ProviderKind.SCRYFALL)
    }
    rejectsProvider("cross-host Spellbook pagination") {
        ProviderDiscovery.nextSpellbookOffset("https://attacker.invalid/find-my-combos?limit=100&offset=100", 0)
    }
    rejectsProvider("replayed Spellbook page") {
        ProviderDiscovery.nextSpellbookOffset("https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=0", 0)
    }
    verifyProvider(ProviderDiscovery.nextSpellbookOffset(
        "https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=100", 0) == 100,
        "exact Spellbook pagination accepted")

    val scryfall = ProviderDiscovery.parseScryfallPage(
        """{"object":"list","has_more":true,"data":[{"object":"card","id":"00000000-0000-0000-0000-000000000001","name":"Sol Ring","mana_cost":"{1}","type_line":"Artifact","oracle_text":"{T}: Add {C}{C}.","related_uris":{"edhrec":"https://edhrec.com/cards/sol-ring"},"legalities":{"commander":"legal"},"scryfall_uri":"https://scryfall.com/card/cmm/396/sol-ring","card_faces":[{"name":"Sol Ring front","mana_cost":"{1}","type_line":"Artifact","oracle_text":"{T}: Add {C}{C}."}]}]}""".toByteArray(),
        "Sol Ring", 1,
    )
    verifyProvider(scryfall.hasMore && scryfall.cards.single().name == "Sol Ring" &&
        scryfall.cards.single().edhrecUrl == "https://edhrec.com/cards/sol-ring" &&
        scryfall.cards.single().faces.single().name=="Sol Ring front" && scryfall.cards.single().commanderLegality=="legal" &&
        scryfall.cards.single().scryfallUrl=="https://scryfall.com/card/cmm/396/sol-ring", "bounded Scryfall result parsed")
    rejectsProvider("Scryfall arbitrary EDHREC link") {
        ProviderDiscovery.parseScryfallCard(
            """{"object":"card","id":"00000000-0000-0000-0000-000000000001","name":"Sol Ring","related_uris":{"edhrec":"https://attacker.invalid/steal"}}""".toByteArray())
    }

    val catalogue = Catalogue(ByteArrayInputStream(
        """
        {"catalogueHash":"0000000000000000000000000000000000000000000000000000000000000000","upstreamCommit":"0000000000000000000000000000000000000000","sourceMetadataSHA256":"0000000000000000000000000000000000000000000000000000000000000000","nameAliases":{"Leader // Back":"Leader"}}
        {"name":"Leader","setCode":"TST","collectorNumber":"1","typeLine":"Legendary Creature","oracleText":"","colorIdentity":["U"]}
        {"name":"Sol Ring","setCode":"TST","collectorNumber":"2","typeLine":"Artifact","oracleText":"","colorIdentity":[]}
        {"name":"Missing Piece","setCode":"TST","collectorNumber":"3","typeLine":"Artifact","oracleText":"","colorIdentity":[]}
        """.trimIndent().toByteArray()
    ))
    val deck = Deck("Private title", listOf(
        CardEntry("Leader // Back", 1, "commanders"),
        CardEntry("Sol Ring", 1, "deck"),
        CardEntry("Private Maybe", 1, "maybeboard"),
    ))
    val input = SpellbookInput.from(deck, catalogue)
    val body = input.body.toString(Charsets.UTF_8)
    verifyProvider(input.commanders.single().card == "Leader" && "Private title" !in body &&
        "Private Maybe" !in body, "only canonical main and commander rows are shared")
    rejectsProvider("unresolved shared card") {
        SpellbookInput.from(deck.copy(entries = deck.entries + CardEntry("Unknown", 1)), catalogue)
    }

    val page = ProviderDiscovery.parseSpellbookPage(
        """
        {"count":1,"next":"https://backend.commanderspellbook.com/find-my-combos?limit=100&offset=100","results":{"identity":"U","included":[],"includedByChangingCommanders":[],"almostIncluded":[{"id":"safe_combo","uses":[{"card":{"id":1,"name":"Sol Ring"},"quantity":1,"mustBeCommander":false,"zoneLocations":["B"],"battlefieldCardState":"Untapped","exileCardState":"","libraryCardState":"","graveyardCardState":""},{"card":{"id":2,"name":"Missing Piece"},"quantity":1,"mustBeCommander":false}],"requires":[],"produces":[{"feature":{"name":"A documented result"},"quantity":1}],"identity":"U","status":"OK","spoiler":false,"legalities":{"commander":true},"description":"Tap Sol Ring.\nResolve the effect.","easyPrerequisites":"Priority","notablePrerequisites":"","manaNeeded":"{1}","notes":"Documented line."}],"almostIncludedByAddingColors":[],"almostIncludedByChangingCommanders":[],"almostIncludedByAddingColorsAndChangingCommanders":[]}}
        """.trimIndent().toByteArray(), 0,
    )
    val combo = page.groups.getValue(SpellbookGroup.ALMOST_INCLUDED).single()
    verifyProvider(page.nextOffset == 100 && combo.singleMissingResolvedCard(input, catalogue) == "Missing Piece",
        "one resolved missing card can be offered deliberately")
    verifyProvider(combo.ingredients.first().zoneLocations==listOf("B")&&combo.ingredients.first().battlefieldCardState=="Untapped"&&
        combo.description.lines().size==2&&combo.easyPrerequisites=="Priority"&&combo.manaNeeded=="{1}"&&combo.notes=="Documented line.",
        "combo prerequisites and exact ordered steps are retained")
    verifyProvider(combo.websiteUri.toString() == "https://commanderspellbook.com/combo/safe_combo/", "combo URL is derived from safe id")

    rejectsProvider("duplicate combo identity across groups") {
        ProviderDiscovery.parseSpellbookPage(
            """{"results":{"identity":"","included":[{"id":"same","uses":[{"card":{"id":1,"name":"Sol Ring"},"quantity":1,"mustBeCommander":false}],"requires":[],"produces":[],"identity":"","status":"OK","spoiler":false,"legalities":{"commander":true}}],"includedByChangingCommanders":[],"almostIncluded":[{"id":"same","uses":[{"card":{"id":1,"name":"Sol Ring"},"quantity":1,"mustBeCommander":false}],"requires":[],"produces":[],"identity":"","status":"OK","spoiler":false,"legalities":{"commander":true}}],"almostIncludedByAddingColors":[],"almostIncludedByChangingCommanders":[],"almostIncludedByAddingColorsAndChangingCommanders":[]}}""".toByteArray(), 0)
    }
    println("PASS: $providerChecks Android provider assertions")
}
