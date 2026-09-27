package io.magicmobile.android.studio

import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.J
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Deck Studio's player-facing wording for Play and the builder: one source on Android. iOS
 * (DeckStudioPlayText in DeckStudioPlaySelection.swift) holds the same strings, and both platforms'
 * parity tests read them from core/src/test/resources/parity/deck-studio-cases.json.
 */
object DeckStudioPlayText {
    // Play
    const val play = "Play this deck"
    const val saveAndPlay = "Save & play"
    const val playing = "Playing"
    const val playingAccessibility = "This is your playing deck"
    const val ready = "Ready"
    const val needsFixes = "Needs fixes"
    const val notChecked = "Not checked"
    const val fixDeck = "Fix deck"
    const val notNow = "Not now"
    const val setUpGame = "Set up game"
    const val cannotPlayTitle = "Can't play this deck yet"
    const val checkingTitle = "Checking your deck"
    const val checkingProgress = "Checking Commander rules…"
    const val gameLive = "Leave your current game to change decks."
    const val catalogueLoading = "The local card catalogue is still loading."
    const val setupReady = "Ready · checked on this device"
    const val setupNotChecked = "Not checked — Start will check it"
    const val setupNeedsFixes = "Needs fixes · Fix in Deck Studio"
    const val panelCaption = "Check the Commander rules on this device, then play this deck."
    const val showAll = "Show all"
    /** A stored pass from a game XMage created. */
    const val startPassed = "Passed the installed XMage Commander validator"
    // Card actions (long-press on a row or tile)
    const val cardDetails = "Card details"
    const val addOne = "Add one"
    const val removeOne = "Remove one"
    const val replaceCard = "Replace card"
    const val moveTo = "Move to…"
    const val removeRow = "Remove row"
    /** Move to… destinations: board and title. "considering" counts as maybeboard. */
    val destinations = listOf("deck" to "Main deck", "commanders" to "Commanders", "companions" to "Companions", "sideboard" to "Sideboard",
        "maybeboard" to "Maybeboard")
    // Select mode
    const val select = "Select"
    const val selectCards = "Select cards"
    const val doneSelecting = "Done selecting"
    const val selectAll = "Select all"
    const val setQuantity = "Set quantity"
    const val remove = "Remove"
    const val removeSelectedTitle = "Remove the selected cards?"
    const val removeSelectedMessage = "Undo brings them back."
    const val quantityMessage = "Every selected card gets this quantity, from 1 to 2,000."
    const val quantityError = "Use a quantity from 1 to 2,000. Nothing was changed."
    const val showAsGrid = "Show as grid"
    const val showAsList = "Show as list"
    // Quick Add
    const val quickAdd = "Quick add"
    const val quickAddMain = "Main"
    const val quickAddMaybe = "Maybe"
    const val quickAddMaybeboard = "Add to maybeboard"
    const val addCards = "Add cards"
    const val quickAddHint = "Type a card name, or a count first, like 2x Sol Ring. Return adds the top match."
    const val quickAddNeedsName = "Type a card name, like 2x Sol Ring."
    const val quickAddFailed = "Could not add this card. Check the draft's size limits."
    const val undo = "Undo"
    // Edit as text
    const val editAsText = "Edit as text"
    const val copyList = "Copy list"
    const val listCopied = "List copied"
    const val reviewChanges = "Review changes"
    const val applyChanges = "Apply changes"
    const val keepEditing = "Keep editing"
    const val diffAdded = "Added"
    const val diffRemoved = "Removed"
    const val noChanges = "No changes to apply."
    const val textEditorHint = "One card per line, like 1 Sol Ring, under Commander, Deck, Companion, Sideboard or Maybeboard headings."
    // Commander-first new decks
    const val chooseCommander = "Choose a commander"
    const val skip = "Skip"
    const val commanderFirstTitle = "Start with your commander"
    const val commanderFirstCaption = "Legendary creatures and cards that say they can be your commander. The deck takes its name until you rename it."
    const val searchCommanders = "Search commanders"
    // Search
    const val searchHint = "Filters work too: t:creature, o:draw, mv<=3, id:wu"
    const val withinIdentity = "Within commander color identity"
    // Sample hand
    const val sampleHand = "Sample hand"
    const val sampleHandCaption = "Draw seven from your main deck. Commanders stay in the command zone, and sideboard and maybeboard cards stay out."
    const val sampleHandEmpty = "Add main-deck cards to draw a sample hand."
    const val draw7 = "Draw 7"
    const val newHand = "New hand"
    const val mulligan = "Mulligan"
    const val draw = "Draw"

    fun checking(name: String) = "XMage is checking $name against the Commander rules on this device."
    fun nowPlaying(name: String) = "Now playing $name"
    fun nowPlayingStrip(name: String, status: DeckStudioPlayStatus?) = "Now playing: $name" + (status?.let { " · ${it.title}" } ?: "")
    fun issues(count: Int) = if (count == 1) "1 issue" else "$count issues"
    fun issuesBlockPlay(count: Int) = if (count == 1) "1 rule issue blocks play" else "$count rule issues block play"
    fun notShown(count: Int) = "${issues(count)} not shown"
    fun excluded(count: Int) = "Sideboard and maybeboard stay out of play (${CardCountText.label(count)})."
    fun deletePlaying(replacement: String) = "This is your playing deck. $replacement will be selected instead."
    fun showingOnly(label: String) = "Showing only: $label"
    fun selected(count: Int) = "$count selected"
    fun added(quantity: Int, name: String, maybeboard: Boolean) = "Added $quantity × $name" + if (maybeboard) " to maybeboard" else ""
    fun noCardNamed(name: String) = "No card named “$name” in this app’s catalogue."
    fun handCounts(hand: Int, library: Int) = "${CardCountText.label(hand)} in hand · ${CardCountText.label(library)} in library"
    fun setupStatus(status: DeckStudioPlayStatus) = when (status) {
        DeckStudioPlayStatus.READY -> setupReady
        DeckStudioPlayStatus.NEEDS_FIXES -> setupNeedsFixes
        DeckStudioPlayStatus.NOT_CHECKED -> setupNotChecked
    }
}

/** The rules Play shares on every screen (DeckStudioPlayRules in DeckStudioPlaySelection.swift). */
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
    fun unplayableCards(deck: DeckList, resolver: OnDeviceDeckResolver): List<String> = unplayableCards(deck, resolver::canonicalCardName)

    fun unplayableCards(deck: DeckList, canonical: (String) -> String?): List<String> {
        val playing = setOf("main", "deck", "commander", "commanders", "companion", "companions")
        val excluded = setOf("sideboard", "maybeboard", "considering")
        val rows = listOfNotNull(deck.commander?.let { it.copy(section = "commanders") }) + deck.entries
        val cards = LinkedHashSet<String>()
        val sections = HashMap<String, MutableSet<String>>()
        for (row in rows) {
            val section = row.section.trim().lowercase()
            if (section in excluded) continue
            val name = canonical(row.cardName)
            if (section !in playing || name == null) { cards += row.cardName; continue }
            sections.getOrPut(name) { HashSet() } += DeckStudioDraftPresentation.normalizedSection(section)
        }
        rows.filter { row -> sections[canonical(row.cardName) ?: ""]?.let { it.size > 1 } == true }.forEach { cards += it.cardName }
        return cards.toList()
    }

    /**
     * Whether Start's answer is stored for the player's deck. A pass always is. A rejection is not
     * when this exact deck already passed, or when an issue names a card outside the player's deck
     * (it came from another seat's deck).
     */
    fun storesStartResult(valid: Boolean, issueCards: List<String>, deckCards: Collection<String>, alreadyPassed: Boolean): Boolean {
        if (valid) return true
        if (alreadyPassed) return false
        val names = deckCards.map(::key).toSet()
        return issueCards.all { key(it) in names }
    }

    /** Fix deck: the rows XMage named, matched by canonical name and ignoring case. Sideboard and maybeboard rows are out of play. */
    fun fixRows(rows: List<NativeDeckRow>, cards: List<String>, canonical: (String) -> String?): Set<java.util.UUID> {
        fun name(value: String) = key(canonical(value) ?: value)
        val wanted = cards.map(::name).toSet()
        return rows.filter { DeckStudioDraftPresentation.section(it) !in setOf("sideboard", "maybeboard") && name(it.cardName) in wanted }.mapTo(LinkedHashSet()) { it.id }
    }

    /** The cards XMage named, in first-seen order, for Fix deck's filter. */
    fun issueCards(result: DeckStudioCheckResult): List<String> =
        result.issues.mapNotNull { it.cardName?.trim()?.takeIf(String::isNotEmpty) }.distinct()

    /** A group's title: XMage's group, else its issue type in words, else "Commander rules". */
    fun groupTitle(issue: DeckStudioValidationReceipt.Issue): String {
        issue.group?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val words = issue.type.replace("_", " ").lowercase()
        return if (words.isEmpty()) "Commander rules" else words.replaceFirstChar { it.uppercase() }
    }

    /** Issues grouped as XMage grouped them, in the order it reported them. */
    fun groupedIssues(issues: List<DeckStudioValidationReceipt.Issue>): List<Pair<String, List<DeckStudioValidationReceipt.Issue>>> =
        issues.groupBy(::groupTitle).toList()

    private fun key(name: String) = name.trim().lowercase()
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

    /** Steps 1–4, without the engine. Nothing is saved while the catalogue is still loading. */
    fun start(source: Source, gameLive: Boolean, resolver: OnDeviceDeckResolver?, name: String = ""): Step {
        if (gameLive) return Step.Done(Outcome.GameLive)
        if (resolver == null) return Step.Done(Outcome.CannotPlay(null, name, DeckStudioPlayText.catalogueLoading, emptyList()))
        val prepared = source.prepare().getOrElse { failure ->
            return Step.Done(Outcome.CannotPlay(null, name, failure.message ?: "Save this deck before playing it.", emptyList()))
        }
        val deckName = prepared.deck.name
        val projection: DeckStudioPlayProjection
        val request: J
        try {
            projection = DeckStudioPlayProjection(prepared.deck)
            request = projection.resolve(resolver)
        } catch (failure: Exception) {
            val cards = runCatching { DeckStudioPlayRules.unplayableCards(prepared.deck, resolver) }.getOrDefault(emptyList())
            return Step.Done(Outcome.CannotPlay(prepared.deckID, deckName, failure.message ?: "This deck cannot be played.", cards))
        }
        val excluded = projection.excluded.sumOf { it.quantity }
        val key = DeckStudioCheckKey.of(prepared.deckID, String(EngineJson.encode(request), Charsets.UTF_8), resolver.upstreamCommit, resolver.catalogueHash, appBuild)
        // The same request, engine, catalogue and build always gets the same answer, passed or failed.
        results.result(key)?.let { stored ->
            return Step.Done(if (stored.valid) Outcome.Playing(prepared.deckID, deckName, excluded, checkedNow = false) else Outcome.Blocked(prepared.deckID, deckName, stored))
        }
        return Step.Check(prepared.deckID, deckName, request, excluded)
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
