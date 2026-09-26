package io.magicmobile.android.studio

import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Play's user-facing words. iOS (DeckStudioPlaySelection.swift) uses the same strings. */
object DeckStudioPlayText {
    const val play = "Play this deck"
    const val saveAndPlay = "Save & play"
    const val playing = "Playing"
    const val playingButton = "✓ Playing"
    const val playingLabel = "This is your playing deck"
    const val fixDeck = "Fix deck"
    const val notNow = "Not now"
    const val setUpGame = "Set up game"
    const val cannotPlayTitle = "Can't play this deck yet"
    const val checkingTitle = "Checking your deck"
    const val gameLive = "Leave your current game to change decks."
    const val catalogueLoading = "The local card catalogue is still loading."
    const val setupReady = "Ready · checked on this device"
    const val setupNotChecked = "Not checked — Start will check it"
    const val setupNeedsFixes = "Needs fixes · Fix in Deck Studio"

    fun checking(name: String) = "XMage is checking $name against the Commander rules on this device."
    fun nowPlaying(name: String) = "Now playing $name"
    fun nowPlayingStrip(name: String, status: DeckStudioPlayStatus?) = "Now playing: $name" + (status?.let { " · ${it.title}" } ?: "")
    fun issues(count: Int) = if (count == 1) "1 issue" else "$count issues"
    fun issuesBlockPlay(count: Int) = if (count == 1) "1 rule issue blocks play" else "$count rule issues block play"
    fun excluded(count: Int) = "Sideboard and maybeboard stay out of play (${CardCountText.label(count)})."
    fun deletePlaying(replacement: String) = "This is your playing deck. $replacement will be selected instead."
    fun setupStatus(status: DeckStudioPlayStatus) = when (status) {
        DeckStudioPlayStatus.READY -> setupReady
        DeckStudioPlayStatus.NEEDS_FIXES -> setupNeedsFixes
        DeckStudioPlayStatus.NOT_CHECKED -> setupNotChecked
    }
}

/** The rules Play shares on every screen. */
object DeckStudioPlayRules {
    /** A library record's playing-deck ID: precons keep theirs, local decks are "local:<id>". */
    fun selectionID(recordID: String): String = if (recordID.startsWith("precon:")) recordID else "local:$recordID"

    /**
     * Play always selects the source deck, never a copy. Precons and other read-only decks play as
     * they are; a new or changed draft is saved first, and a failed save stops Play.
     */
    fun sourceID(recordID: String?, readOnly: Boolean, needsSave: Boolean, save: () -> String?): String? = when {
        readOnly -> recordID?.let(::selectionID)
        needsSave || recordID == null -> save()?.let(::selectionID)
        else -> selectionID(recordID)
    }

    /** The exact request XMage checks and plays: the play projection, resolved offline. */
    fun request(deck: DeckList, resolver: OnDeviceDeckResolver): String = DeckStudioPlayProjection(deck).request(resolver)

    fun key(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver, appBuild: String): DeckStudioCheckKey? =
        runCatching { DeckStudioCheckKey.of(deckID, request(deck, resolver), resolver.upstreamCommit, resolver.catalogueHash, appBuild) }.getOrNull()

    /** A deck that cannot be resolved offline needs fixes; otherwise its stored result decides. */
    fun status(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver, appBuild: String, results: DeckStudioReceiptStore): DeckStudioPlayStatus {
        val key = key(deckID, deck, resolver, appBuild) ?: return DeckStudioPlayStatus.NEEDS_FIXES
        return results.status(key)
    }

    /** Rows the offline resolver cannot play: unknown names and sections, and cards split between playing sections. */
    fun unplayableCards(deck: DeckList, resolver: OnDeviceDeckResolver): List<String> {
        val playing = setOf("main", "deck", "commander", "commanders", "companion", "companions")
        val excluded = setOf("sideboard", "maybeboard", "considering")
        val rows = listOfNotNull(deck.commander?.let { it.copy(section = "commanders") }) + deck.entries
        val cards = LinkedHashSet<String>()
        val sections = HashMap<String, MutableSet<String>>()
        for (row in rows) {
            val section = row.section.trim().lowercase()
            if (section in excluded) continue
            if (section !in playing || resolver.canonicalCardName(row.cardName) == null) { cards += row.cardName; continue }
            sections.getOrPut(resolver.canonicalCardName(row.cardName)!!) { HashSet() } += DeckStudioDraftPresentation.normalizedSection(section)
        }
        rows.filter { row -> sections[resolver.canonicalCardName(row.cardName) ?: ""]?.let { it.size > 1 } == true }.forEach { cards += it.cardName }
        return cards.toList()
    }

    /** The cards XMage named, for Fix deck's filter. */
    fun issueCards(result: DeckStudioCheckResult): List<String> =
        result.issues.mapNotNull { it.cardName?.takeIf(String::isNotBlank) }.distinct()

    /** Issues grouped as XMage grouped them, in the order it reported them. */
    fun groupedIssues(issues: List<DeckStudioValidationReceipt.Issue>): List<Pair<String, List<DeckStudioValidationReceipt.Issue>>> =
        issues.groupBy { issue -> issue.group?.takeIf(String::isNotBlank) ?: issue.type }.toList()
}

/**
 * The shared "Play this deck" flow (DeckStudioPlaySelection.swift): the library tile, the workspace
 * header and the validation panel all start it. It never runs while a game or match room is live,
 * saves a new or changed draft first, resolves the play projection offline (sideboard, maybeboard
 * and considering cards stay out), reuses a matching stored result, otherwise asks XMage, and stores
 * that answer whether it passes or fails. Only a pass selects the deck, and always the source deck.
 */
class DeckStudioPlayFlow(
    private val results: DeckStudioReceiptStore,
    private val appBuild: String,
    private val validate: suspend (J, OnDeviceDeckResolver) -> DeckStudioValidationReceipt,
) {
    data class Prepared(val deckID: String, val deck: DeckList)

    /** A library record or an open draft. [prepare] saves a new or changed draft first. */
    fun interface Source { fun prepare(): Result<Prepared> }

    sealed class Outcome {
        object GameLive : Outcome()
        data class CannotPlay(val deckID: String?, val name: String, val message: String, val cards: List<String>) : Outcome()
        data class Playing(val deckID: String, val name: String, val excludedCards: Int, val checkedNow: Boolean) : Outcome()
        data class Blocked(val deckID: String, val name: String, val result: DeckStudioCheckResult) : Outcome()
        data class CheckFailed(val deckID: String, val name: String, val message: String) : Outcome()
    }

    sealed class Step {
        data class Done(val outcome: Outcome) : Step()
        data class Check(val deckID: String, val name: String, val request: J, val excludedCards: Int) : Step()
    }

    /** Steps 1–4, without the engine. */
    fun start(source: Source, gameLive: Boolean, resolver: OnDeviceDeckResolver?): Step {
        if (gameLive) return Step.Done(Outcome.GameLive)
        val prepared = source.prepare().getOrElse { failure ->
            return Step.Done(Outcome.CannotPlay(null, "", failure.message ?: "Save this deck before playing it.", emptyList()))
        }
        val name = prepared.deck.name
        if (resolver == null) return Step.Done(Outcome.CannotPlay(prepared.deckID, name, DeckStudioPlayText.catalogueLoading, emptyList()))
        val projection: DeckStudioPlayProjection
        val request: J
        try {
            projection = DeckStudioPlayProjection(prepared.deck)
            request = projection.resolve(resolver)
        } catch (failure: Exception) {
            val cards = runCatching { DeckStudioPlayRules.unplayableCards(prepared.deck, resolver) }.getOrDefault(emptyList())
            return Step.Done(Outcome.CannotPlay(prepared.deckID, name, failure.message ?: "This deck cannot be played.", cards))
        }
        val excluded = projection.excluded.sumOf { it.quantity }
        val key = DeckStudioCheckKey.of(prepared.deckID, String(EngineJson.encode(request), Charsets.UTF_8), resolver.upstreamCommit, resolver.catalogueHash, appBuild)
        if (results.result(key)?.valid == true) return Step.Done(Outcome.Playing(prepared.deckID, name, excluded, checkedNow = false))
        return Step.Check(prepared.deckID, name, request, excluded)
    }

    /** Step 5: XMage checks the deck on this device; the result is stored either way. */
    suspend fun check(step: Step.Check, resolver: OnDeviceDeckResolver): Outcome {
        val receipt = try { validate(step.request, resolver) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { return Outcome.CheckFailed(step.deckID, step.name, failure.message ?: "XMage could not check this deck.") }
        val result = DeckStudioCheckResult.of(step.deckID, receipt)
        withContext(Dispatchers.IO) { results.record(result) }
        return if (result.valid) Outcome.Playing(step.deckID, step.name, step.excludedCards, checkedNow = true)
        else Outcome.Blocked(step.deckID, step.name, result)
    }

    suspend fun play(source: Source, gameLive: Boolean, resolver: OnDeviceDeckResolver?, checking: (String) -> Unit = {}): Outcome =
        when (val step = start(source, gameLive, resolver)) {
            is Step.Done -> step.outcome
            is Step.Check -> { checking(step.name); check(step, resolver!!) }
        }
}
