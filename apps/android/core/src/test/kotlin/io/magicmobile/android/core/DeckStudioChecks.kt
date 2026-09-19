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
    println("PASS: $deckStudioChecks Android Deck Studio core assertions")
}
