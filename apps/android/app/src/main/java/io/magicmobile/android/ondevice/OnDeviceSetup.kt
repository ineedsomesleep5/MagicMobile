package io.magicmobile.android.ondevice

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.DeckStore
import io.magicmobile.android.SavedDeck
import io.magicmobile.android.core.Catalogue
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.PrintingIndex
import io.magicmobile.android.core.Wire
import io.magicmobile.android.core.array
import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineCheckpointResult
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineHealth
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.GameResumeIdentity
import io.magicmobile.android.game.GameResumeSettings
import io.magicmobile.android.game.GameResumeStore
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import io.magicmobile.android.studio.DeckList
import io.magicmobile.android.studio.DeckStudioCheckResult
import io.magicmobile.android.studio.DeckStudioPlayProjection
import io.magicmobile.android.studio.DeckStudioPlayRules
import io.magicmobile.android.studio.DeckStudioPlayText
import io.magicmobile.android.studio.DeckStudioServices
import io.magicmobile.android.studio.DeckStudioValidationReceipt
import io.magicmobile.android.studio.OnDeviceDeckResolver
import io.magicmobile.android.session.OnDeviceSession
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.LaunchEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.time.Instant
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** An included Commander precon (PreconCatalog.swift). */
data class PreconDeck(val id: String, val name: String, val deck: Deck) {
    val commander: String? get() = deck.commanderName
}

val Deck.commanderName: String? get() = entries.firstOrNull { it.section == "commanders" }?.name

/**
 * Port of OnDeviceSetupPreferences (OnDeviceAppConfiguration.swift). Only setup choices are
 * saved; never an engine handle, peer credential, hidden game state or a resumable match.
 */
object OnDeviceSetupPreferences {
    const val deckKey = "magicmobile.ondevice.selectedDeckID"
    const val aiDeckKey = "magicmobile.ondevice.aiPreconID"
    const val aiDeck2Key = "magicmobile.ondevice.aiPreconID2"
    const val aiDeck3Key = "magicmobile.ondevice.aiPreconID3"
    const val aiCountKey = "magicmobile.ondevice.aiOpponentCount"
    const val aiSkillKey = "magicmobile.ondevice.aiSkill"
    const val humanCountKey = "magicmobile.ondevice.humanPlayerCount"
    const val friendsKey = "magicmobile.ondevice.playWithFriends"
    const val startingPlayerModeKey = "magicmobile.ai.startingPlayerMode"
    const val playerNameKey = "magicmobile.playerDisplayName"
    const val onlineModeKey = "magicmobile.onlineMode"
    const val defaultDeckID = "precon:token-triumph"
    const val defaultAIDeckID = "grave-danger"

    fun normalizedAIDeckIDs(saved: List<String>, available: List<String>): List<String> {
        val fallback = if (defaultAIDeckID in available) defaultAIDeckID else available.firstOrNull() ?: ""
        val first = saved.firstOrNull()?.takeIf { it in available } ?: fallback
        return (0 until 3).map { index -> saved.getOrNull(index)?.takeIf { it in available } ?: first }
    }

    fun normalizedDeckID(saved: String, deckIDs: Set<String>): String =
        if (saved in deckIDs) saved else if (defaultDeckID in deckIDs) defaultDeckID else deckIDs.sorted().firstOrNull() ?: ""
}

/** The table features every cross-play phone must share (see RelayTable). */
const val RELAY_ADAPTER_VERSION = "ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1/chat-1"

/** Port of OnDeviceAppConfiguration.aiGameSeats. */
object OnDeviceAppConfiguration {
    fun aiGameSeats(name: String, humanDeck: J, aiDecks: List<J>, aiSkill: Int): List<J> {
        if (aiDecks.size !in 1..3) throw EngineError.InvalidMessage("Choose 1–3 AI opponents.")
        if (aiSkill !in 1..10) throw EngineError.InvalidMessage("Choose AI skill from 1–10.")
        return listOf<J>(JsonObject(mapOf("seatId" to JsonPrimitive("player1"), "name" to JsonPrimitive(name),
            "controller" to JsonPrimitive("human"), "deck" to humanDeck))) + aiDecks.mapIndexed { offset, deck ->
            val index = offset + 1
            JsonObject(mapOf("seatId" to JsonPrimitive("player${index + 1}"), "name" to JsonPrimitive("AI $index"),
                "controller" to JsonPrimitive("ai"), "deck" to deck, "aiSkill" to JsonPrimitive(aiSkill)))
        }
    }
}

/**
 * Port of OnDeviceSetupModel (OnDeviceRootView.swift): owns the native runtime for local
 * games and the rules for when a game may start, be answered or be closed.
 */
class OnDeviceSetupModel(private val context: Context, val session: OnDeviceSession, private val scope: CoroutineScope) {
    var identity by mutableStateOf<BuildIdentity?>(null); private set
    var catalogue by mutableStateOf<Catalogue?>(null); private set
    var precons by mutableStateOf<List<PreconDeck>>(emptyList()); private set
    /** The included bracket decks (ai-decks.json): AI opponents, and decks players may pick. */
    var bracketDecks by mutableStateOf<List<io.magicmobile.android.game.AIDeck>>(emptyList()); private set
    /** The Commander bracket card lists (commander-brackets.json). */
    var bracketRules by mutableStateOf(io.magicmobile.android.game.BracketRules.EMPTY); private set
    var localDecks by mutableStateOf<List<SavedDeck>>(emptyList()); private set
    var isBusy by mutableStateOf(false); private set
    var usingMultiplayer by mutableStateOf(false); private set
    var closeFailed by mutableStateOf(false); private set
    var runtimeOpen by mutableStateOf(false); private set
    var status by mutableStateOf("Preparing local decks"); private set
    var errorMessage by mutableStateOf<String?>(null)
    var feedback by mutableStateOf<String?>(null)
    /** Set while another transport (the cross-play relay) owns the current table. */
    var multiplayer by mutableStateOf<TableConnection?>(null); private set
    val store = DeckStore(context)
    /** Save/resume for solo games: the launch prompt, the live game's sidecar and the in-progress marker. */
    val resume = GameResumeController(resumeStore(context), BuildConfig.VERSION_CODE.toString(), resumeIO)
    private val runtime = OnDeviceRuntimeManager()
    private var aiClient: EngineClient? = null
    private var aiMatchID: String? = null
    private var sceneActive = true
    private var preparing = false
    private var catalogueLoad: kotlinx.coroutines.Deferred<Catalogue>? = null
    private var printings: PrintingIndex? = null
    /** The offline deck resolver: game start and Deck Studio resolve the same play projection. */
    var deckResolver by mutableStateOf<OnDeviceDeckResolver?>(null); private set
    /** A deck XMage rejected at Start (deck ID and stored result), for the issues sheet. */
    var deckIssues by mutableStateOf<Pair<String, DeckStudioCheckResult>?>(null)

    init { DeckStudioServices.install(context) }

    val needsLeave: Boolean get() = usingMultiplayer || runtimeOpen || session.matchID != null || multiplayer?.needsCleanup == true
    val canUseSession: Boolean get() = sceneActive && (!usingMultiplayer || multiplayer?.let { it.isConnected && !it.isSuspended } == true)
    val liveStatus: String get() {
        val table = multiplayer
        if (usingMultiplayer && table != null && (!table.isConnected || table.isSuspended)) return table.status
        return feedback ?: session.status
    }

    fun deck(id: String): Deck? = precons.firstOrNull { "precon:${it.id}" == id }?.deck
        ?: bracketDecks.firstOrNull { it.playerDeckID == id }?.deck ?: localDecks.firstOrNull { "local:${it.id}" == id }?.deck
    val deckIDs: Set<String> get() = (precons.map { "precon:${it.id}" } + bracketDecks.map { it.playerDeckID } + localDecks.map { "local:${it.id}" }).toSet()
    /** Every AI deck: the precons (Core) and the bracket decks. */
    val aiPool: List<io.magicmobile.android.game.AIDeck> get() = io.magicmobile.android.ranked.aiPool(precons, bracketDecks)

    fun prepare() {
        if (identity != null || preparing) return
        preparing = true
        scope.launch {
            try {
                // Decks first: the menu shows the selected deck at once, while the card catalogue loads.
                val decks = withContext(Dispatchers.IO) {
                    val included = Wire.decode(context.assets.open("precons.json").use { it.readBytes() }).array("decks").map { raw ->
                        val row = Wire.objectValue(raw)
                        PreconDeck(Wire.string(row["id"]), Wire.string(row["name"]), Deck.decode(row))
                    }
                    included to runCatching { store.all() }
                }
                precons = decks.first
                withContext(Dispatchers.IO) {
                    runCatching { io.magicmobile.android.game.AIDeckPool.parse(context.assets.open("ai-decks.json").use { it.readBytes().decodeToString() }) } to
                        runCatching { io.magicmobile.android.game.BracketRules.parse(context.assets.open("commander-brackets.json").use { it.readBytes().decodeToString() }) }
                }.let { (aiDecks, rules) -> aiDecks.onSuccess { bracketDecks = it }; rules.onSuccess { bracketRules = it } }
                decks.second.onSuccess { localDecks = it }.onFailure { errorMessage = "Saved decks could not be read: ${it.message}" }
                // The compact printing index names the build and resolves decks; the full catalogue
                // (rules text and metadata for 30,000 cards) loads only for screens that need it.
                val started = System.nanoTime()
                val index = withContext(Dispatchers.IO) { PrintingIndex(context.assets.open("printings.tsv")) }
                android.util.Log.i("MagicMobile", "Printing index loaded in ${(System.nanoTime() - started) / 1_000_000} ms")
                printings = index
                deckResolver = withContext(Dispatchers.Default) { OnDeviceDeckResolver(index) }
                val built = BuildIdentity(index.upstreamCommit, index.catalogueHash,
                    "ondevice-0.1/app-${BuildConfig.VERSION_NAME}/build-${BuildConfig.RELEASE_BUILD}/rollstep-2/room-1/concede-1/emote-1")
                identity = built
                status = "Choose your deck and players."
                // A saved game is offered (or explained) once the build it must match is known.
                resume.checkAtLaunch(GameResumeIdentity.engine(built))
            } catch (error: Throwable) {
                errorMessage = error.message ?: "The local card catalogue could not be loaded."; status = "Local setup unavailable"
            } finally { preparing = false }
        }
    }

    /** The compact printing index, once `prepare()` has loaded it. */
    val printingIndex: PrintingIndex? get() = printings

    /** Deck Studio's library store: saved decks stay in this model's deck store. */
    val library: io.magicmobile.android.studio.DeckLibraryStore by lazy {
        io.magicmobile.android.studio.DeckLibraryStore(store) { saved -> localDecks = saved }
    }

    /** The full catalogue, loading it on first use. */
    suspend fun awaitCatalogue(): Catalogue {
        catalogue?.let { return it }
        loadCatalogue()
        return catalogueLoad?.await() ?: catalogue ?: throw EngineError.InvalidMessage("The local card catalogue could not be loaded.")
    }

    fun reloadLocalDecks() {
        scope.launch { runCatching { withContext(Dispatchers.IO) { store.all() } }.onSuccess { localDecks = it } }
    }

    /**
     * The engine deck for every game start (AI, hosting, joining, match room): Deck Studio's play
     * projection, so sideboard and maybeboard stay out and a stored check's request matches exactly.
     */
    fun resolve(deck: Deck): J {
        val resolver = deckResolver ?: throw EngineError.InvalidMessage("The local card catalogue is still loading.")
        return try { DeckStudioPlayProjection(DeckList.fromStored(deck)).resolve(resolver) }
        catch (error: EngineError) { throw error }
        catch (error: Exception) { throw EngineError.InvalidMessage(error.message ?: "This deck cannot be played.") }
    }

    /** The full catalogue (rules text and metadata), loaded once on first use. */
    fun loadCatalogue() {
        if (catalogue != null || catalogueLoad != null) return
        catalogueLoad = scope.async(Dispatchers.Default) { Catalogue(context.assets.open("catalogue.jsonl")) }.also { load ->
            scope.launch { runCatching { load.await() }.onSuccess { catalogue = it }.onFailure { errorMessage = it.message; catalogueLoad = null } }
        }
    }

    /** `settings` are the setup choices kept with a checkpoint, so a resumed game can rebuild its menu state and Rematch. */
    suspend fun startAI(name: String, deck: Deck, aiDecks: List<Deck>, aiSkill: Int = 2, settings: GameResumeSettings? = null, deckID: String? = null) {
        val identity = identity ?: return
        if (isBusy || needsLeave) return
        isBusy = true; errorMessage = null; feedback = null; status = "Starting XMage"
        // A new game replaces any saved one.
        resume.discard()
        var humanDeck: J? = null
        try {
            val playerName = playerName(name)
            val resolvedDeck = resolve(deck)
            humanDeck = resolvedDeck
            val opponentDecks = aiDecks.map(::resolve)
            val seats = OnDeviceAppConfiguration.aiGameSeats(playerName, resolvedDeck, opponentDecks, aiSkill)
            val client = runtime.makeClient(identity)
            runtimeOpen = runtime.isOpen
            aiClient = client
            // The checkpoint field goes only to an engine that advertises saveResume.
            val capabilities = runtime.capabilities
            val base = JsonObject(mapOf("seats" to JsonArray(seats)))
            val checkpoint = resume.checkpointFor(capabilities, seats)
            val created = runtime.create(client, checkpoint?.let { JsonObject(base + ("checkpoint" to it)) } ?: base)
            runtimeOpen = runtime.isOpen
            val matchID = created["matchId"].string?.takeIf { it.isNotEmpty() }
                ?: throw EngineError.InvalidMessage("XMage did not return a match ID. Close the runtime before trying again.")
            aiMatchID = matchID
            resume.gameStarted(base, checkpoint, capabilities, "player1", deck.name, settings)
            updateSessionForeground()
            session.attach(client, matchID, "player1", allowsSeatScopedAutoYield = true, observe = resume::observe, close = { closeAI() })
            status = "Game started"
            if (deckID != null) recordStartCheck(deckID, resolvedDeck, null)
        } catch (error: Throwable) {
            val request = humanDeck
            if (deckID != null && request != null && error is EngineError.RejectionDetails && error.code == "invalid_deck") recordStartCheck(deckID, request, error)
            errorMessage = error.message ?: error.javaClass.simpleName
            runtimeOpen = runtime.isOpen
            if (!runtime.isOpen && aiMatchID == null) aiClient = null
            status = if (needsLeave) "Game startup interrupted. Refresh or leave before starting again." else "Unable to start local game"
        } finally { isBusy = false }
    }

    /**
     * XMage checks every seat's deck when it creates a game, so Start stores that answer for the
     * player's deck like a Deck Studio check (DeckStudioPlayRules.storesStartResult): a pass always,
     * a rejection unless this exact deck already passed or it names a card outside this deck.
     */
    private fun recordStartCheck(deckID: String, request: J, rejection: EngineError.RejectionDetails?) {
        val resolver = deckResolver ?: return
        val text = String(EngineJson.encode(request), Charsets.UTF_8)
        val build = DeckStudioServices.appBuild
        val receipt = if (rejection == null) DeckStudioValidationReceipt(text, resolver.upstreamCommit, resolver.catalogueHash, build,
            System.currentTimeMillis(), true, emptyList(), DeckStudioPlayText.startPassed)
        else runCatching { DeckStudioValidationReceipt.rejection(rejection.details, rejection.text, text, resolver.upstreamCommit, resolver.catalogueHash, build) }.getOrNull() ?: return
        val result = DeckStudioCheckResult.of(deckID, receipt)
        val names = listOf("main", "commanders", "companions").flatMap { request[it].array ?: emptyList() }.mapNotNull { it["name"].string }
        val passed = !result.valid && runCatching { DeckStudioServices.checkResults.result(result.key)?.valid == true }.getOrDefault(false)
        if (!DeckStudioPlayRules.storesStartResult(result.valid, DeckStudioPlayRules.issueCards(result), names, passed)) return
        if (!result.valid) deckIssues = deckID to result
        scope.launch(Dispatchers.IO) { runCatching { DeckStudioServices.checkResults.record(result) } }
    }

    /**
     * Attaches the session to a table another transport owns (the host's engine or a relay endpoint).
     * [deck] is the local player's playing deck, locked once the game starts.
     */
    suspend fun attachTable(table: TableConnection, deckID: String? = null, deck: Deck? = null) {
        val endpoint = table.endpoint ?: return
        if (isBusy || session.matchID != null) return
        isBusy = true
        try {
            multiplayer = table; usingMultiplayer = true
            // Tables never checkpoint; the marker explains a game lost when the app closed.
            resume.tableStarted()
            updateSessionForeground()
            session.attach(endpoint.client, endpoint.matchID, endpoint.seatID, allowsSeatScopedAutoYield = true, table = endpoint.table,
                observe = resume::observe, close = { table.leave() })
            status = "Match connected"
            // Only the host's engine created this game, so only the host's deck check is local.
            if (endpoint.isHost && deckID != null && deck != null) runCatching { recordStartCheck(deckID, resolve(deck), null) }
        } catch (error: Throwable) { errorMessage = error.message } finally { isBusy = false }
    }

    fun beginTable(table: TableConnection) { multiplayer = table; usingMultiplayer = true; errorMessage = null; feedback = null; updateSessionForeground() }

    /**
     * Cross-play tables share one identity on iPhone and Android: the same protocol, rules source,
     * card registry and table features. App build numbers differ between platforms, so they are left out.
     */
    val relayIdentity: BuildIdentity? get() = identity?.let { BuildIdentity(it.upstreamCommit, it.catalogueHash, RELAY_ADAPTER_VERSION) }

    /** Opens a relay table that this phone hosts: `humans` players plus any AI seats. */
    suspend fun hostOnline(name: String, deck: Deck, humans: Int, aiDecks: List<Deck>, aiSkill: Int) {
        val identity = relayIdentity ?: return
        if (isBusy || needsLeave) return
        isBusy = true; errorMessage = null; feedback = null; status = "Opening a table"
        resume.discard()
        val table = RelayTable(identity, scope, makeHostEngine = { openHostEngine() }, closeHostEngine = { closeHostEngine() })
        try {
            val playerName = playerName(name)
            val aiSeats = aiDecks.map { AISeatDescriptor(resolve(it), aiSkill) }
            beginTable(table)
            table.host(humans, playerName, resolve(deck), aiSeats)
            status = "Table open"
        } catch (error: Throwable) {
            errorMessage = error.message ?: "Could not open a table."
            if (multiplayer === table && table.tableCode == null) { multiplayer = null; usingMultiplayer = false }
            status = "Choose your deck and players."
        } finally { isBusy = false }
    }

    /** Joins another player's relay table by its code. */
    fun joinOnline(code: String, name: String, deck: Deck) {
        val identity = relayIdentity ?: return
        if (isBusy || needsLeave) return
        errorMessage = null; feedback = null
        resume.discard()
        val table = RelayTable(identity, scope, makeHostEngine = { openHostEngine() }, closeHostEngine = { closeHostEngine() })
        try {
            val playerName = playerName(name)
            val resolved = resolve(deck)
            beginTable(table)
            table.join(code, playerName, resolved)
        } catch (error: Throwable) {
            errorMessage = error.message ?: "Could not join that table."
            if (multiplayer === table && table.tableCode == null) { multiplayer = null; usingMultiplayer = false }
        }
    }

    /** Match room: confirm the currently selected deck and ready up. */
    fun readyForMatch(name: String, deck: Deck) {
        val table = multiplayer as? RelayTable ?: return
        try { table.markReady(playerName(name), resolve(deck)) } catch (error: Throwable) { errorMessage = error.message }
    }

    fun setSceneActive(active: Boolean) {
        sceneActive = active
        multiplayer?.setForeground(active)
        updateSessionForeground()
    }

    fun updateSessionForeground() = session.setForeground(canUseSession)

    /** The online table code being typed, or opened from an invite link. */
    var relayJoinCode by mutableStateOf("")

    suspend fun perform(reportingBusy: Boolean = false, operation: suspend () -> Unit) {
        if (isBusy || session.isWorking || !canUseSession) {
            // A dropped tap is intentional; a dropped automatic reply must not look like progress.
            if (reportingBusy) errorMessage = "The game was busy. Choose again to continue."
            return
        }
        errorMessage = null; feedback = null
        try { operation() } catch (error: Throwable) { errorMessage = error.message ?: error.javaClass.simpleName }
    }

    /** Waits up to 3 seconds for the current response and its refresh to finish. */
    suspend fun waitUntilSessionIdle() {
        repeat(150) { if (!isBusy && !session.isWorking) return; delay(20) }
    }

    /**
     * The player leaves the game: its saved checkpoint goes too, including anything the engine
     * wrote while it was closing. `close` alone (the app closing) keeps a resumable game.
     */
    suspend fun leave(): Boolean {
        if (isBusy || session.isWorking) return false
        resume.discard()
        return close().also { closed -> if (closed) resume.discard() }
    }

    /** The ON_STOP save while the player is away, and the last cancel sent on coming back (a new request waits for it). */
    private var backgroundSave: Job? = null
    private var cancellingSave: Job? = null

    /**
     * The live solo game's engine, for saving when the player leaves. Its calls go straight to the
     * client: the runtime's open() guard would close the runtime on a failure. The controller asks
     * only an engine with `checkpointOnDemand`.
     */
    private fun saveEngine(): GameResumeController.SaveEngine? {
        val client = aiClient ?: return null
        val matchID = aiMatchID ?: return null
        return object : GameResumeController.SaveEngine {
            override suspend fun checkpoint(waitMillis: Int): EngineCheckpointResult = client.checkpoint(matchID, waitMillis).also { result ->
                if (result is EngineCheckpointResult.Saved) android.util.Log.i("MagicMobile",
                    "Game saved on leaving: ${result.checkpoint.bytes} bytes in ${result.checkpoint.writeMillis ?: "?"} ms")
            }
            override suspend fun cancel() = client.cancelCheckpoint(matchID)
        }
    }

    /** ON_PAUSE: the player may be leaving, perhaps to close the app from Recents. Records when, and arms a save at the engine's next safe point. */
    fun armSaveForLeaving() {
        if (!resume.backgrounded() || !resume.savesOnDemand) return
        val engine = saveEngine() ?: return
        val previous = cancellingSave
        scope.launch { previous?.join(); resume.armSave(engine) }
    }

    /** ON_STOP: records when the player left, then asks the engine to save for at most 5 seconds. */
    fun saveForBackground() {
        if (!resume.backgrounded() || !resume.savesOnDemand) return
        val engine = saveEngine() ?: return
        backgroundSave?.cancel()
        val previous = cancellingSave
        backgroundSave = scope.launch { previous?.join(); resume.saveForBackground(engine) }
    }

    /** ON_START and ON_RESUME: back in the app. The background save stops, the engine's armed request is cancelled and the save made on leaving is used up. */
    fun returnedToApp() {
        backgroundSave?.cancel(); backgroundSave = null
        if (!resume.foregrounded()) return
        val engine = saveEngine() ?: return
        val previous = cancellingSave
        cancellingSave = scope.launch { previous?.join(); runCatching { engine.cancel() } }
    }

    /** Resume: restore the saved solo game in a fresh engine and open its board. A failure closes it and stays on the menu. */
    suspend fun resumeGame() {
        val identity = identity ?: return
        if (isBusy || needsLeave) return
        val sidecar = resume.accept() ?: return
        isBusy = true; errorMessage = null; feedback = null; status = "Resuming your game"
        val engine = object : GameResumeController.ResumeEngine {
            override suspend fun open(): EngineClient = runtime.makeClient(identity).also { aiClient = it; runtimeOpen = runtime.isOpen }
            override val capabilities: J? get() = runtime.capabilities
            override suspend fun restore(client: EngineClient, path: String): J = runtime.restore(client, path).also { runtimeOpen = runtime.isOpen }
            override suspend fun attach(client: EngineClient, matchID: String, seatID: String) {
                aiMatchID = matchID
                updateSessionForeground()
                session.attach(client, matchID, seatID, allowsSeatScopedAutoYield = true, observe = resume::observe, close = { closeAI() })
            }
            override suspend fun cleanup() {
                try { if (session.matchID != null) session.close() else if (runtime.isOpen) closeAI() }
                finally {
                    runtimeOpen = runtime.isOpen
                    if (!runtime.isOpen) { aiClient = null; aiMatchID = null }
                }
            }
        }
        try { status = if (resume.resume(sidecar, engine)) "Game resumed" else "Choose your deck and players." }
        finally { isBusy = false; runtimeOpen = runtime.isOpen }
    }

    suspend fun close(): Boolean {
        if (isBusy || session.isWorking) return false
        isBusy = true; status = "Closing game"; errorMessage = null
        try {
            when {
                session.matchID != null -> session.close()
                usingMultiplayer -> multiplayer?.leave()
                else -> closeAI()
            }
            if (runtime.isOpen) runtime.close()
            runtimeOpen = runtime.isOpen
            multiplayer = null; usingMultiplayer = false; closeFailed = false; feedback = null
            status = "Game closed"; updateSessionForeground()
            return true
        } catch (error: Throwable) {
            runtimeOpen = runtime.isOpen
            closeFailed = true; errorMessage = error.message
            status = "Closing failed. Retry closing to release the current game."
            return false
        } finally { isBusy = false }
    }

    private suspend fun closeAI() {
        val client = aiClient; val matchID = aiMatchID
        if (client != null && matchID != null) { runtime.closeMatch(client, matchID); aiMatchID = null } else runtime.close()
        runtimeOpen = runtime.isOpen
        aiClient = null
    }

    /** A host's engine for a cross-play table; the table closes it when the match ends. */
    suspend fun openHostEngine(): EngineClient {
        val identity = identity ?: throw EngineError.InvalidMessage("The local card catalogue is still loading.")
        return runtime.makeClient(identity).also { runtimeOpen = runtime.isOpen }
    }

    suspend fun closeHostEngine() { runtime.close(); runtimeOpen = runtime.isOpen }

    suspend fun createHostMatch(client: EngineClient, configuration: J): J = runtime.create(client, configuration).also { runtimeOpen = runtime.isOpen }

    fun localHealth(): EngineHealth {
        val table = multiplayer
        val connected = if (usingMultiplayer) table?.let { it.isConnected && !it.isSuspended } == true else runtime.isOpen
        val reason = if (usingMultiplayer) "Table connection: ${table?.status ?: "unavailable"}"
            else "Local runtime ${if (runtime.isOpen) "open" else "closed"}; capabilities ${if (runtime.capabilities == null) "unavailable" else "loaded"}."
        return EngineHealth(if (connected) "ok" else "unavailable", reason, Instant.now().toString(), null)
    }

    suspend fun diagnosticReport(): String? = runCatching { runtime.diagnosticReport() }.getOrNull()

    /** Deletes the engine's own copy of its latest report (OnDeviceSetupModel.clearDiagnostics on iOS). */
    suspend fun clearDiagnostics() = runtime.clearDiagnostics()

    companion object {
        fun playerName(raw: String): String {
            val name = raw.trim()
            if (name.codePointCount(0, name.length) !in 1..24 || name.any { Character.isISOControl(it) }) {
                throw EngineError.InvalidMessage("Enter a player name with 1–24 characters and no line breaks.")
            }
            return name
        }

        val savedPlayerName get() = AppPreferences.string(OnDeviceSetupPreferences.playerNameKey, "")

        /** Resume files are written in this order, off the main thread. */
        private val resumeIO: Executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "MagicMobileResume").apply { isDaemon = true } }

        /**
         * noBackupFilesDir/resume: never backed up, since a checkpoint holds every hand and library.
         * UI tests get their own folder and design previews none, so neither touches a real saved game.
         */
        fun resumeStore(context: Context): GameResumeStore? = when {
            io.magicmobile.android.DesignPreview.active -> null
            LaunchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] != null -> GameResumeStore(File(context.noBackupFilesDir, "resume-ui-test"))
            else -> GameResumeStore(File(context.noBackupFilesDir, "resume"))
        }
    }
}

/** A table whose engine lives elsewhere: the relay host's phone, or this phone hosting for others. */
interface TableConnection {
    /** [table] goes to `OnDeviceSession.attach(table = …)`: revision notices and "Waiting for <host>…". */
    class Endpoint(val client: EngineClient, val matchID: String, val seatID: String, val isHost: Boolean,
                   val table: io.magicmobile.android.session.OnDeviceTableLink? = null)
    val endpoint: Endpoint?
    val isConnected: Boolean
    val isSuspended: Boolean
    val needsCleanup: Boolean
    val status: String
    fun setForeground(active: Boolean)
    suspend fun leave()
}
