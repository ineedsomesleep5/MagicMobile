package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.isNull
import io.magicmobile.android.game.isUuid
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.util.UUID

private fun String.hasControl(): Boolean = any { Character.isISOControl(it) }

/**
 * Canonical playing cards, independent of title, row order and printings (DeckStudioRecordedGame.swift).
 * The engine identity is recorded separately; nothing is sent to a server.
 */
class DeckStudioDeckSignature(rows: List<Row>) {
    data class Row(val name: String, val count: Int, val section: String)
    class InvalidDeck : Exception("Invalid deck signature")

    val rows: List<Row>

    init {
        if (rows.size > 2000) throw InvalidDeck()
        val counts = sortedMapOf<String, java.util.SortedMap<String, Int>>()
        var total = 0
        for (row in rows) {
            if (row.section !in setOf("main", "commanders", "companions") || row.name.isEmpty() || row.name.utf8Size > 2000 ||
                row.name.hasControl() || row.count !in 1..2000 || row.count > 2000 - total) throw InvalidDeck()
            total += row.count
            counts.getOrPut(row.section) { sortedMapOf() }.merge(row.name, row.count, Int::plus)
        }
        this.rows = counts.flatMap { (section, names) -> names.map { (name, count) -> Row(name, count, section) } }
    }

    override fun equals(other: Any?) = other is DeckStudioDeckSignature && other.rows == rows
    override fun hashCode() = rows.hashCode()

    fun json(): JsonObject = JsonObject(mapOf("rows" to JsonArray(rows.map {
        JsonObject(sortedMapOf("count" to JsonPrimitive(it.count), "name" to JsonPrimitive(it.name), "section" to JsonPrimitive(it.section)))
    })))

    companion object {
        /** The engine deck configuration: main, commanders and companions. */
        fun native(value: J?): DeckStudioDeckSignature {
            val rows = ArrayList<Row>()
            for (section in listOf("main", "commanders", "companions")) {
                for (entry in value[section].array ?: throw InvalidDeck()) {
                    val name = entry["name"].string ?: throw InvalidDeck()
                    val count = entry["count"].integer?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE } ?: throw InvalidDeck()
                    rows += Row(name, count.toInt(), section)
                }
            }
            return DeckStudioDeckSignature(rows)
        }

        fun decode(value: J?): DeckStudioDeckSignature = DeckStudioDeckSignature((value["rows"].array ?: throw InvalidDeck()).map {
            Row(it["name"].string ?: throw InvalidDeck(), it["count"].integer?.toInt() ?: throw InvalidDeck(), it["section"].string ?: throw InvalidDeck())
        })
    }
}

/** A bounded review of seat-scoped public observations, not an engine replay. */
data class DeckStudioPublicTimeline(
    val samples: List<Sample> = emptyList(),
    val events: List<Event> = emptyList(),
    val samplesTruncated: Boolean = false,
    val eventsTruncated: Boolean = false,
) {
    data class Player(val id: String, val name: String, val life: Int, val battlefieldCount: Int)
    data class Sample(val revision: Int, val turn: Int, val observedAt: Long, val players: List<Player>)
    data class Event(
        val revision: Int, val turn: Int, val kind: Kind, val playerID: String?, val cardName: String?, val typeLine: String?,
        val outcome: String?, val amount: Int? = null, val phaseName: String? = null, val sourceEventRevision: Int? = null,
    ) {
        enum class Kind(val key: String) {
            BATTLEFIELD_APPEARANCE("battlefieldAppearance"), SPELL_ON_STACK("spellOnStack"), CAST("cast"), DAMAGE("damage"),
            LIFE_CHANGE("lifeChange"), TURN_STARTED("turnStarted"), PHASE("phase"), OUTCOME("outcome");
            companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
        }
    }

    class Invalid : Exception("Invalid timeline")

    fun validate(game: DeckStudioRecordedGame) {
        if (samples.size > maximumSamples || events.size > maximumEvents) throw Invalid()
        if (samples.isEmpty()) { if (events.isNotEmpty()) throw Invalid(); return }
        val viewer = game.viewerPlayerID ?: throw Invalid()
        var previousRevision = -1; var previousTurn = -1; var previousDate = game.startedAt
        var known = emptySet<String>()
        for (sample in samples) {
            val ids = sample.players.map { it.id }
            if (sample.revision <= previousRevision || sample.revision > game.lastRevision || sample.turn !in 0..1_000_000 ||
                sample.turn < previousTurn || sample.turn > game.observedTurn || sample.observedAt < previousDate || sample.observedAt > game.observedAt ||
                sample.players.size != game.aiOpponents + 1 || ids.toSet().size != ids.size || viewer !in ids ||
                !sample.players.all { isUuid(it.id) && validText(it.name, 128) && it.life in -1_000_000..1_000_000 && it.battlefieldCount in 0..2000 }) throw Invalid()
            if (known.isNotEmpty() && ids.toSet() != known) throw Invalid()
            known = ids.toSet(); previousRevision = sample.revision; previousTurn = sample.turn; previousDate = sample.observedAt
        }
        previousRevision = -1; previousTurn = -1
        var previousSource = -1; var sawOutcome = false
        for (event in events) {
            if (event.revision < previousRevision || event.revision < samples[0].revision || event.revision > game.lastRevision ||
                event.turn < previousTurn || event.turn > game.observedTurn || event.playerID?.let { it !in known } == true ||
                event.sourceEventRevision?.let { it < 0 || it > event.revision } == true) throw Invalid()
            event.sourceEventRevision?.let { if (it <= previousSource) throw Invalid(); previousSource = it }
            val ok = when (event.kind) {
                Event.Kind.BATTLEFIELD_APPEARANCE, Event.Kind.SPELL_ON_STACK -> event.cardName?.let { validText(it, 200) } == true &&
                    event.typeLine?.let { validText(it, 200) } != false && event.outcome == null && event.amount == null && event.phaseName == null
                Event.Kind.CAST -> event.playerID != null && event.cardName?.let { validText(it, 200) } == true && event.outcome == null &&
                    event.amount == null && event.phaseName == null && event.sourceEventRevision != null
                Event.Kind.DAMAGE -> event.playerID != null && event.cardName?.let { validText(it, 200) } == true && event.amount in 1..1_000_000 &&
                    event.outcome == null && event.phaseName == null && event.sourceEventRevision != null
                Event.Kind.LIFE_CHANGE -> event.playerID != null && event.cardName == null && event.typeLine == null && event.amount != null &&
                    event.amount != 0 && event.amount in -1_000_000..1_000_000 && event.outcome == null && event.phaseName == null && event.sourceEventRevision != null
                Event.Kind.TURN_STARTED -> event.playerID == null && event.cardName == null && event.typeLine == null && event.outcome == null &&
                    event.amount == null && event.phaseName == null && event.sourceEventRevision != null
                Event.Kind.PHASE -> event.playerID == null && event.cardName == null && event.typeLine == null && event.outcome == null &&
                    event.amount == null && event.phaseName in publicPhases && event.sourceEventRevision != null
                Event.Kind.OUTCOME -> (game.end == DeckStudioRecordedGame.End.COMPLETED && !sawOutcome && event.cardName == null && event.typeLine == null &&
                    event.amount == null && event.phaseName == null && event.outcome in setOf("won", "notWon", "unknown")).also { if (it) sawOutcome = true }
            }
            if (!ok) throw Invalid()
            previousRevision = event.revision; previousTurn = event.turn
        }
    }

    fun json(): JsonObject = JsonObject(mapOf(
        "samples" to JsonArray(samples.map { sample -> JsonObject(mapOf("revision" to JsonPrimitive(sample.revision), "turn" to JsonPrimitive(sample.turn),
            "observedAt" to JsonPrimitive(sample.observedAt), "players" to JsonArray(sample.players.map { player ->
                JsonObject(mapOf("id" to JsonPrimitive(player.id), "name" to JsonPrimitive(player.name), "life" to JsonPrimitive(player.life),
                    "battlefieldCount" to JsonPrimitive(player.battlefieldCount))) }))) }),
        "events" to JsonArray(events.map { event -> JsonObject(buildMap {
            put("revision", JsonPrimitive(event.revision)); put("turn", JsonPrimitive(event.turn)); put("kind", JsonPrimitive(event.kind.key))
            event.playerID?.let { put("playerID", JsonPrimitive(it)) }; event.cardName?.let { put("cardName", JsonPrimitive(it)) }
            event.typeLine?.let { put("typeLine", JsonPrimitive(it)) }; event.outcome?.let { put("outcome", JsonPrimitive(it)) }
            event.amount?.let { put("amount", JsonPrimitive(it)) }; event.phaseName?.let { put("phaseName", JsonPrimitive(it)) }
            event.sourceEventRevision?.let { put("sourceEventRevision", JsonPrimitive(it)) }
        }) }),
        "samplesTruncated" to JsonPrimitive(samplesTruncated), "eventsTruncated" to JsonPrimitive(eventsTruncated)))

    companion object {
        const val maximumSamples = 1_500
        const val maximumEvents = 2_000
        val publicPhases = setOf("UNTAP", "UPKEEP", "DRAW", "PRECOMBAT_MAIN", "BEGIN_COMBAT", "DECLARE_ATTACKERS", "DECLARE_BLOCKERS",
            "FIRST_COMBAT_DAMAGE", "COMBAT_DAMAGE", "END_COMBAT", "POSTCOMBAT_MAIN", "END_TURN", "CLEANUP")

        fun validText(text: String, maximum: Int): Boolean = text.isNotEmpty() && text.utf8Size <= maximum &&
            text.none { Character.isISOControl(it) || it.code in 0x202A..0x202E || it.code in 0x2066..0x2069 }

        fun decode(value: J?): DeckStudioPublicTimeline {
            fun int(value: J?) = value.integer?.toInt() ?: throw Invalid()
            fun optionalInt(value: J?) = if (value.isNull) null else int(value)
            fun optionalString(value: J?) = if (value.isNull) null else value.string ?: throw Invalid()
            return DeckStudioPublicTimeline(
                (value["samples"].array ?: throw Invalid()).map { sample -> Sample(int(sample["revision"]), int(sample["turn"]),
                    sample["observedAt"].integer ?: throw Invalid(), (sample["players"].array ?: throw Invalid()).map { player ->
                        Player(player["id"].string ?: throw Invalid(), player["name"].string ?: throw Invalid(), int(player["life"]), int(player["battlefieldCount"]))
                    }) },
                (value["events"].array ?: throw Invalid()).map { event -> Event(int(event["revision"]), int(event["turn"]),
                    Event.Kind.of(event["kind"].string) ?: throw Invalid(), optionalString(event["playerID"]), optionalString(event["cardName"]),
                    optionalString(event["typeLine"]), optionalString(event["outcome"]), optionalInt(event["amount"]), optionalString(event["phaseName"]),
                    optionalInt(event["sourceEventRevision"])) },
                value["samplesTruncated"].bool ?: throw Invalid(), value["eventsTruncated"].bool ?: throw Invalid())
        }
    }
}

/** One AI match as this phone observed it; times in milliseconds since the epoch. */
data class DeckStudioRecordedGame(
    val id: UUID,
    val matchID: String,
    val seatID: String,
    val deck: DeckStudioDeckSignature,
    val title: String,
    val upstream: String,
    val catalogue: String,
    val appBuild: String,
    val aiOpponents: Int,
    val startedAt: Long,
    val observedAt: Long,
    val finishedAt: Long? = null,
    val end: End = End.IN_PROGRESS,
    val observedTurn: Int = 0,
    /** Native commander watcher counts; never inferred from hand or stack movements. */
    val commandZoneCasts: Map<String, Int> = emptyMap(),
    val won: Boolean? = null,
    val lastRevision: Int = -1,
    val viewerPlayerID: String? = null,
    /** Public, seat-scoped player names and public commander card names only. */
    val opponents: List<Opponent>? = null,
    /** Present only for matches started with the separate detailed-history choice. */
    val timeline: DeckStudioPublicTimeline? = null,
) {
    enum class End(val key: String) {
        IN_PROGRESS("inProgress"), COMPLETED("completed"), LEFT("left"), INTERRUPTED("interrupted"), ENGINE_FAILED("engineFailed");
        companion object { fun of(key: String?) = entries.firstOrNull { it.key == key } }
    }
    data class Opponent(val playerID: String, val name: String, val commanders: List<String>)
    class Invalid : Exception("Invalid recorded game")

    val elapsedSeconds: Double get() = maxOf(0.0, ((finishedAt ?: observedAt) - startedAt) / 1000.0)

    fun validate() {
        val valid = isUuid(matchID) && seatID.isNotEmpty() && seatID.utf8Size <= 128 && title.utf8Size <= 512 && upstream.utf8Size <= 128 &&
            catalogue.utf8Size <= 256 && appBuild.utf8Size <= 128 && aiOpponents in 1..3 && observedTurn in 0..1_000_000 &&
            observedAt >= startedAt && observedAt - startedAt <= 31_536_000_000L &&
            (finishedAt?.let { it >= startedAt && it <= observedAt } ?: true) && lastRevision >= -1 && (viewerPlayerID?.let(::isUuid) ?: true) &&
            (opponents?.let { list -> list.size <= aiOpponents && list.map { it.playerID }.toSet().size == list.size && list.all { opponent ->
                isUuid(opponent.playerID) && opponent.playerID != viewerPlayerID && opponent.name.isNotEmpty() && opponent.name.utf8Size <= 128 &&
                    !opponent.name.hasControl() && opponent.commanders.size <= 12 &&
                    opponent.commanders.all { it.isNotEmpty() && it.utf8Size <= 200 && !it.hasControl() } } } ?: true) &&
            upstream.isNotEmpty() && catalogue.isNotEmpty() && appBuild.isNotEmpty() && commandZoneCasts.size <= 12 &&
            commandZoneCasts.all { (name, count) -> deck.rows.any { it.section == "commanders" && it.name == name } && count in 0..1_000_000 } &&
            (end == End.COMPLETED || won == null) && ((end == End.IN_PROGRESS) == (finishedAt == null))
        if (!valid) throw Invalid()
        timeline?.validate(this)
    }

    fun json(): JsonObject = JsonObject(buildMap {
        put("id", JsonPrimitive(id.toString().uppercase())); put("matchID", JsonPrimitive(matchID)); put("seatID", JsonPrimitive(seatID))
        put("deck", deck.json()); put("title", JsonPrimitive(title)); put("upstream", JsonPrimitive(upstream)); put("catalogue", JsonPrimitive(catalogue))
        put("appBuild", JsonPrimitive(appBuild)); put("aiOpponents", JsonPrimitive(aiOpponents)); put("startedAt", JsonPrimitive(startedAt))
        put("observedAt", JsonPrimitive(observedAt)); finishedAt?.let { put("finishedAt", JsonPrimitive(it)) }; put("end", JsonPrimitive(end.key))
        put("observedTurn", JsonPrimitive(observedTurn)); put("commandZoneCasts", JsonObject(commandZoneCasts.mapValues { JsonPrimitive(it.value) }))
        won?.let { put("won", JsonPrimitive(it)) }; put("lastRevision", JsonPrimitive(lastRevision))
        viewerPlayerID?.let { put("viewerPlayerID", JsonPrimitive(it)) }
        opponents?.let { list -> put("opponents", JsonArray(list.map { JsonObject(mapOf("playerID" to JsonPrimitive(it.playerID),
            "name" to JsonPrimitive(it.name), "commanders" to JsonArray(it.commanders.map(::JsonPrimitive)))) })) }
        timeline?.let { put("timeline", it.json()) }
    })

    companion object {
        fun decode(value: J?): DeckStudioRecordedGame {
            fun long(key: String) = value[key].integer ?: throw Invalid()
            fun string(key: String) = value[key].string ?: throw Invalid()
            val id = string("id").takeIf(::isUuid) ?: throw Invalid()
            return DeckStudioRecordedGame(UUID.fromString(id), string("matchID"), string("seatID"), DeckStudioDeckSignature.decode(value["deck"]),
                string("title"), string("upstream"), string("catalogue"), string("appBuild"), long("aiOpponents").toInt(), long("startedAt"),
                long("observedAt"), if (value["finishedAt"].isNull) null else long("finishedAt"), End.of(value["end"].string) ?: throw Invalid(),
                long("observedTurn").toInt(), (value["commandZoneCasts"].obj ?: throw Invalid()).mapValues { (it.value.integer ?: throw Invalid()).toInt() },
                if (value["won"].isNull) null else value["won"].bool ?: throw Invalid(), long("lastRevision").toInt(),
                if (value["viewerPlayerID"].isNull) null else string("viewerPlayerID"),
                value["opponents"]?.takeIf { it !is JsonNull }?.let { list -> (list.array ?: throw Invalid()).map { row ->
                    Opponent(row["playerID"].string ?: throw Invalid(), row["name"].string ?: throw Invalid(),
                        (row["commanders"].array ?: throw Invalid()).map { it.string ?: throw Invalid() }) } },
                value["timeline"]?.takeIf { it !is JsonNull }?.let(DeckStudioPublicTimeline::decode))
        }
    }
}

/**
 * Observes successful native envelopes only. It never fabricates missing casts, draws,
 * mulligans, missed land drops or a game outcome from a disconnect.
 */
class DeckStudioPlaytestAccumulator {
    var game: DeckStudioRecordedGame? = null; private set
    private val recorder = DeckStudioPublicTimelineRecorder()
    private var detailRevoked = false

    fun observe(request: J, response: J, enabled: Boolean, appBuild: String, now: Long, detailedEnabled: Boolean = false,
                sanitizeLog: ((String) -> String)? = null): Boolean {
        if (!enabled || request["protocol"].integer != 1L || response["protocol"].integer != 1L || response["ok"].bool != true) return false
        val result = response["result"].obj ?: return false
        val op = request["op"].string ?: return false
        if (op == "create") {
            if (game != null) return false
            val seats = request["configuration"]["seats"].array?.takeIf { it.size in 2..4 } ?: return false
            fun controller(seat: J) = seat["controller"].string ?: "human"
            if (!seats.all { controller(it) in setOf("human", "ai") } || seats.count { controller(it) == "human" } != 1) return false
            val human = seats.first { controller(it) == "human" }
            val seat = human["seatId"].string?.takeIf { it.isNotEmpty() } ?: return false
            val deck = human["deck"].obj ?: return false
            val signature = runCatching { DeckStudioDeckSignature.native(JsonObject(deck)) }.getOrNull() ?: return false
            val match = result["matchId"].string?.takeIf(::isUuid) ?: return false
            val engine = result["engine"]
            if (engine["engine"].string != "xmage" || engine["execution"].string != "native-aot") return false
            val upstream = engine["upstream"].string ?: return false
            val catalogue = engine["catalogueHash"].string ?: return false
            var created = DeckStudioRecordedGame(UUID.randomUUID(), match, seat, signature, (deck["name"].string ?: "Commander deck").take(128),
                upstream, catalogue, appBuild, seats.size - 1, now, now)
            if (detailedEnabled) created = created.copy(timeline = DeckStudioPublicTimeline())
            if (runCatching { created.validate() }.isFailure) return false
            game = created
            return true
        }
        var current = game ?: return false
        if (current.end != DeckStudioRecordedGame.End.IN_PROGRESS || request["matchId"].string != current.matchID) return false
        if (!detailedEnabled) { detailRevoked = true; current = current.copy(timeline = null) }
        if (op == "destroy") {
            if (result["destroyed"].bool != true) return false
            val finished = maxOf(now, current.observedAt)
            current = current.copy(end = DeckStudioRecordedGame.End.LEFT, finishedAt = finished, observedAt = finished)
            if (runCatching { current.validate() }.isFailure) return false
            game = current; return true
        }
        val revision = result["revision"].integer?.toInt()
        val phase = result["phase"].string
        if (op != "poll" || request["viewerId"].string != current.seatID || result["matchId"].string != current.matchID ||
            result["viewerId"].string != current.seatID || revision == null || revision < 0 || revision <= current.lastRevision ||
            phase !in setOf("starting", "running", "ended", "failed", "closed")) return false
        // Reject a mismatched inner view before advancing the recorded revision.
        val raw = result["snapshot"]
        fun matchingView(root: J?): Boolean {
            val viewer = root["enginePlayerId"].string
            return root["schema"].string == "xmage-gameview-v1" && isUuid(viewer) && (current.viewerPlayerID == null || current.viewerPlayerID == viewer) &&
                root["gameView"]["myPlayerId"].string == viewer
        }
        if (raw != null && raw !is JsonNull && !matchingView(raw)) return false
        current = current.copy(lastRevision = revision, observedAt = maxOf(now, current.observedAt))
        if (raw != null && raw !is JsonNull && matchingView(raw)) {
            val viewer = raw["enginePlayerId"].string!!
            val view = raw["gameView"]
            current = current.copy(viewerPlayerID = viewer)
            val players = view["players"].array
            if (players != null && players.size in 2..4 && players.any { it["playerId"].string == viewer } && players.all { isUuid(it["playerId"].string) }) {
                val publicCommanders = raw["commanders"].obj ?: emptyMap()
                val opponents = players.mapNotNull { player ->
                    val id = player["playerId"].string ?: return@mapNotNull null
                    val name = player["name"].string
                    if (id == viewer || name.isNullOrEmpty() || name.utf8Size > 128 || name.hasControl()) return@mapNotNull null
                    val names = publicCommanders.toSortedMap().values.mapNotNull { info ->
                        if (info["ownerPlayerId"].string != id) return@mapNotNull null
                        info["name"].string?.takeIf { it.isNotEmpty() && it.utf8Size <= 200 && !it.hasControl() }
                    }
                    DeckStudioRecordedGame.Opponent(id, name, names)
                }
                if (opponents.size == current.aiOpponents && opponents.all { it.commanders.size <= 12 }) current = current.copy(opponents = opponents)
            }
            view["turn"].integer?.toInt()?.takeIf { it in 0..1_000_000 }?.let { current = current.copy(observedTurn = maxOf(current.observedTurn, it)) }
            raw["commanders"].obj?.takeIf { it.size <= 12 }?.let { commanders ->
                val casts = current.commandZoneCasts.toMutableMap()
                for (info in commanders.values) {
                    if (info["ownerPlayerId"].string != viewer) continue
                    val name = info["name"].string ?: continue
                    if (current.deck.rows.none { it.section == "commanders" && it.name == name }) continue
                    val count = info["castsFromCommandZone"].integer?.toInt()?.takeIf { it in 0..1_000_000 } ?: continue
                    casts[name] = maxOf(casts[name] ?: 0, count)
                }
                current = current.copy(commandZoneCasts = casts)
            }
            val outcome = raw["outcome"]
            if (phase != "failed" && phase != "closed" && outcome["ended"].bool == true) {
                current = current.copy(end = DeckStudioRecordedGame.End.COMPLETED, finishedAt = current.observedAt)
                val winners = outcome["winnerPlayerIds"].array?.map { it.string }
                if (winners != null && winners.all { isUuid(it) }) current = current.copy(won = if (winners.isEmpty()) null else viewer in winners)
            }
        }
        if (current.end == DeckStudioRecordedGame.End.IN_PROGRESS) {
            val end = when (phase) { "failed" -> DeckStudioRecordedGame.End.ENGINE_FAILED; "closed" -> DeckStudioRecordedGame.End.INTERRUPTED
                "ended" -> DeckStudioRecordedGame.End.COMPLETED; else -> null }
            if (end != null) current = current.copy(end = end, finishedAt = current.observedAt)
        }
        if (!detailRevoked && detailedEnabled && current.timeline != null) {
            current = recorder.observe(result, current, current.observedAt, sanitizeLog)
            current = recorder.finish(current)
        }
        if (runCatching { current.validate() }.isFailure) return false
        game = current; return true
    }

    fun close(now: Long): DeckStudioRecordedGame? {
        val value = game
        if (value != null && value.end == DeckStudioRecordedGame.End.IN_PROGRESS) {
            val finished = maxOf(now, value.observedAt)
            val closed = value.copy(end = DeckStudioRecordedGame.End.INTERRUPTED, finishedAt = finished, observedAt = finished)
            if (runCatching { closed.validate() }.isSuccess) game = closed
        }
        return game
    }
}

/** Keeps object IDs only in memory for deduplication; the saved timeline holds names and counts. */
class DeckStudioPublicTimelineRecorder {
    private var battlefieldIDs: Set<String>? = null
    private var stackIDs: Set<String>? = null
    private var lastMessageRevision = -1
    private var knownPublicCards: Set<String> = emptySet()

    fun observe(result: Map<String, J>, game: DeckStudioRecordedGame, now: Long, sanitizeLog: ((String) -> String)?): DeckStudioRecordedGame {
        var timeline = game.timeline ?: return game
        val root = result["snapshot"]
        val viewer = root["enginePlayerId"].string
        val view = root["gameView"]
        val turn = view["turn"].integer?.toInt()
        val rawPlayers = view["players"].array
        val revision = result["revision"].integer?.toInt()
        if (root["schema"].string != "xmage-gameview-v1" || viewer == null || viewer != game.viewerPlayerID || view["myPlayerId"].string != viewer ||
            turn == null || turn !in 0..1_000_000 || rawPlayers == null || rawPlayers.size != game.aiOpponents + 1 || revision == null || revision < 0) return game
        val players = ArrayList<DeckStudioPublicTimeline.Player>()
        val currentBoard = HashSet<String>()
        val appearances = ArrayList<Triple<String, String, String?>>()
        val visibleNames = knownPublicCards.toMutableSet()
        val resync = result["resyncRequired"].bool == true
        var eventsTruncated = timeline.eventsTruncated || resync
        for (player in rawPlayers) {
            val id = player["playerId"].string?.takeIf(::isUuid) ?: return game
            val name = player["name"].string?.takeIf { DeckStudioPublicTimeline.validText(it, 128) } ?: return game
            val life = player["life"].integer?.toInt()?.takeIf { it in -1_000_000..1_000_000 } ?: return game
            val board = publicObjects(player["battlefield"])?.takeIf { it.size <= 2000 } ?: return game
            players += DeckStudioPublicTimeline.Player(id, name, life, board.size)
            for ((objectID, obj) in board) {
                currentBoard += objectID
                val card = visibleCard(obj)
                if (!resync && battlefieldIDs != null && objectID !in battlefieldIDs!! && card != null) appearances += Triple(id, card.first, card.second)
                if (card != null) visibleNames += card.first
            }
        }
        if (players.map { it.id }.toSet().size != players.size || players.none { it.id == viewer } ||
            (timeline.samples.isNotEmpty() && players.map { it.id }.toSet() != timeline.samples[0].players.map { it.id }.toSet())) return game
        // A SPELL on the public stack is not evidence of who cast it.
        val stackObjects = publicObjects(view["stack"])?.takeIf { it.size <= 128 } ?: return game
        val currentStack = HashSet<String>()
        val stackAppearances = ArrayList<Pair<String, String?>>()
        for ((id, obj) in stackObjects) {
            currentStack += id
            val source = obj["sourceCard"]?.let { visibleCard(it) }
            if (!resync && stackIDs != null && id !in stackIDs!! && obj["mageObjectType"].string == "SPELL" && source != null) stackAppearances += source
            if (source != null) visibleNames += source.first
        }
        visibleNames += game.opponents?.flatMap { it.commanders } ?: emptyList()
        root["commanders"].obj?.values?.forEach { info -> info["name"].string?.takeIf { DeckStudioPublicTimeline.validText(it, 200) }?.let { visibleNames += it } }
        val notices = sanitizeLog?.let { publicNotices(result, turn, revision, players, visibleNames, it) } ?: emptyList()
        val hasNewEvents = appearances.isNotEmpty() || stackAppearances.isNotEmpty() || notices.isNotEmpty()
        var samples = timeline.samples
        var samplesTruncated = timeline.samplesTruncated
        if (samples.lastOrNull()?.players != players || samples.lastOrNull()?.turn != turn || hasNewEvents) {
            samples = samples + DeckStudioPublicTimeline.Sample(revision, turn, now, players)
            if (samples.size > DeckStudioPublicTimeline.maximumSamples) { samples = samples.drop(1); samplesTruncated = true }
        }
        var events = timeline.events
        events = events + appearances.sortedBy { it.second }.map { (id, name, type) ->
            DeckStudioPublicTimeline.Event(revision, turn, DeckStudioPublicTimeline.Event.Kind.BATTLEFIELD_APPEARANCE, id, name, type, null) }
        events = events + stackAppearances.sortedBy { it.first }.map { (name, type) ->
            DeckStudioPublicTimeline.Event(revision, turn, DeckStudioPublicTimeline.Event.Kind.SPELL_ON_STACK, null, name, type, null) }
        events = events + notices
        if (events.size > DeckStudioPublicTimeline.maximumEvents) { events = events.takeLast(DeckStudioPublicTimeline.maximumEvents); eventsTruncated = true }
        samples.firstOrNull()?.revision?.let { oldest ->
            val kept = events.filter { it.revision >= oldest }
            if (kept.size < events.size) eventsTruncated = true
            events = kept
        }
        timeline = timeline.copy(samples = samples, events = events, samplesTruncated = samplesTruncated, eventsTruncated = eventsTruncated)
        battlefieldIDs = currentBoard; stackIDs = currentStack; knownPublicCards = visibleNames
        return game.copy(timeline = timeline)
    }

    fun finish(game: DeckStudioRecordedGame): DeckStudioRecordedGame {
        val timeline = game.timeline ?: return game
        if (game.end != DeckStudioRecordedGame.End.COMPLETED || timeline.samples.isEmpty() ||
            timeline.events.any { it.kind == DeckStudioPublicTimeline.Event.Kind.OUTCOME }) return game
        var events = timeline.events + DeckStudioPublicTimeline.Event(game.lastRevision, game.observedTurn, DeckStudioPublicTimeline.Event.Kind.OUTCOME,
            null, null, null, game.won?.let { if (it) "won" else "notWon" } ?: "unknown")
        var truncated = timeline.eventsTruncated
        if (events.size > DeckStudioPublicTimeline.maximumEvents) { events = events.takeLast(DeckStudioPublicTimeline.maximumEvents); truncated = true }
        return game.copy(timeline = timeline.copy(events = events, eventsTruncated = truncated))
    }

    private fun publicNotices(result: Map<String, J>, turn: Int, revision: Int, players: List<DeckStudioPublicTimeline.Player>,
                              knownCards: Set<String>, sanitize: (String) -> String): List<DeckStudioPublicTimeline.Event> {
        val raw = result["events"] ?: return emptyList()
        val events = raw.array?.takeIf { it.size <= 128 } ?: return emptyList()
        var previous = -1
        val pending = ArrayList<Pair<Int, String>>()
        for (event in events) {
            val eventRevision = event["revision"].integer?.toInt() ?: return emptyList()
            val kind = event["kind"].string ?: return emptyList()
            if (eventRevision <= previous || eventRevision > revision) return emptyList()
            previous = eventRevision
            if (kind != "message" || eventRevision <= lastMessageRevision) continue
            val message = event["body"]["message"].string?.takeIf { it.utf8Size <= 4096 } ?: return emptyList()
            pending += eventRevision to message
        }
        lastMessageRevision = maxOf(lastMessageRevision, previous)
        val names = players.groupBy { it.name }.filterValues { it.size == 1 }.mapValues { it.value[0].id }
        val view = result["snapshot"]["gameView"]
        return pending.mapNotNull { (eventRevision, message) ->
            val sanitized = sanitize(message)
            val clean = if (sanitized.endsWith(".")) sanitized.dropLast(1) else sanitized
            if (clean.isEmpty() || clean.utf8Size > 512 || '\n' in clean) return@mapNotNull null
            fun make(kind: DeckStudioPublicTimeline.Event.Kind, playerID: String? = null, cardName: String? = null, amount: Int? = null, phaseName: String? = null) =
                DeckStudioPublicTimeline.Event(revision, turn, kind, playerID, cardName, null, null, amount, phaseName, eventRevision)
            castPattern.matchEntire(clean)?.groupValues?.let { fields ->
                val player = names[fields[1]]
                if (player != null && fields[2] in knownCards) return@mapNotNull make(DeckStudioPublicTimeline.Event.Kind.CAST, playerID = player, cardName = fields[2])
            }
            damagePattern.matchEntire(clean)?.groupValues?.let { fields ->
                val target = names[fields[3]]; val amount = fields[2].toIntOrNull()
                if (fields[1] in knownCards && target != null && amount != null && amount in 1..1_000_000) {
                    return@mapNotNull make(DeckStudioPublicTimeline.Event.Kind.DAMAGE, playerID = target, cardName = fields[1], amount = amount)
                }
            }
            lifePattern.matchEntire(clean)?.groupValues?.let { fields ->
                val player = names[fields[1]]; val magnitude = fields[3].toIntOrNull()
                if (player != null && magnitude != null && magnitude in 1..1_000_000) {
                    return@mapNotNull make(DeckStudioPublicTimeline.Event.Kind.LIFE_CHANGE, playerID = player, amount = if (fields[2] == "loses") -magnitude else magnitude)
                }
            }
            turnPattern.matchEntire(clean)?.groupValues?.let { fields ->
                if (fields[1].toIntOrNull() == turn) return@mapNotNull make(DeckStudioPublicTimeline.Event.Kind.TURN_STARTED)
            }
            phasePattern.matchEntire(clean)?.groupValues?.let { fields ->
                if (fields[1] in DeckStudioPublicTimeline.publicPhases && (fields[1] == view["step"].string || fields[1] == view["phase"].string)) {
                    return@mapNotNull make(DeckStudioPublicTimeline.Event.Kind.PHASE, phaseName = fields[1])
                }
            }
            null
        }
    }

    private fun publicObjects(value: J?): List<Pair<String, J>>? {
        val objects: List<J> = value.obj?.values?.toList() ?: value.array ?: return null
        val ids = HashSet<String>()
        return objects.map { obj ->
            val id = obj["id"].string?.takeIf { isUuid(it) && ids.add(it) } ?: return null
            id to obj
        }
    }

    private fun visibleCard(obj: J): Pair<String, String?>? {
        if (obj["hideInfo"].bool == true || obj["faceDown"].bool == true) return null
        val name = (obj["displayName"] ?: obj["name"]).string?.takeIf { DeckStudioPublicTimeline.validText(it, 200) } ?: return null
        val types = (obj["cardTypes"].array ?: emptyList()).mapNotNull { it.string }.take(4)
        val type = if (types.isEmpty()) null else types.joinToString(" ").split(" ").joinToString(" ") { word ->
            word.lowercase().replaceFirstChar { it.uppercase() } }
        return name to type?.takeIf { DeckStudioPublicTimeline.validText(it, 200) }
    }

    companion object {
        private val castPattern = Regex("""^(.{1,128}) casts (.{1,200})$""")
        private val damagePattern = Regex("""^(.{1,200}) deals ([0-9]{1,7}) damage to (.{1,128})$""")
        private val lifePattern = Regex("""^(.{1,128}) (loses|gains) ([0-9]{1,7}) life$""")
        private val turnPattern = Regex("""^TURN ([0-9]{1,7})$""")
        private val phasePattern = Regex("""^PHASE: ([A-Z_]{3,32})$""")
    }
}

/** Device-local summaries with separately opted-in, bounded public timelines. Storage failure never fails play. */
class DeckStudioPlaytestStore(private val file: File?, private val defaults: StudioDefaults) {
    data class Admission(val enabled: Boolean, val detailedEnabled: Boolean, val generation: UUID)

    private var generation = UUID.randomUUID()
    private var loaded = false
    private var games: List<DeckStudioRecordedGame> = emptyList()
    var failure: String? = null; private set

    private fun flag(key: String) = defaults.string(key) == "true"

    @Synchronized fun admission() = Admission(flag(enabledKey), flag(detailedEnabledKey), generation)
    @Synchronized fun detailedEnabled() = flag(enabledKey) && flag(detailedEnabledKey)
    @Synchronized fun setDetailedEnabled(enabled: Boolean) = defaults.set(detailedEnabledKey, enabled.toString())
    @Synchronized fun setEnabled(enabled: Boolean) {
        defaults.set(enabledKey, enabled.toString())
        if (!enabled) { defaults.set(detailedEnabledKey, "false"); generation = UUID.randomUUID() }
    }
    @Synchronized fun summaries(): List<DeckStudioRecordedGame> { load(); return games }

    @Synchronized fun record(value: DeckStudioRecordedGame, admission: Admission): Boolean {
        if (!admission.enabled || admission.generation != generation || !flag(enabledKey)) return false
        return try {
            load()
            var allowed = value
            if (allowed.timeline == null || !admission.detailedEnabled || !flag(detailedEnabledKey)) {
                // Opting out stops collection now; it does not erase detail already saved for this match.
                allowed = allowed.copy(timeline = games.firstOrNull { it.id == value.id }?.timeline)
            }
            allowed.validate()
            var next = (games.filter { it.id != allowed.id } + allowed).sortedByDescending { it.startedAt }.take(maximumGames)
            while (encoded(next).size > maximumBytes && next.size > 1) next = next.dropLast(1)
            write(next); games = next; failure = null
            true
        } catch (error: Exception) {
            failure = "Playtest summary storage is unavailable. Existing data is preserved; gameplay is unaffected."
            false
        }
    }

    @Synchronized fun clear() {
        generation = UUID.randomUUID()
        file?.takeIf { it.exists() }?.delete()
        games = emptyList(); loaded = true; failure = null
    }

    private fun load() {
        if (loaded) return
        val file = file ?: throw IllegalStateException("unavailable")
        if (!file.exists()) { loaded = true; return }
        if (file.length() > maximumBytes) throw IllegalStateException("invalid")
        val payload = Json.parseToJsonElement(file.readText())
        val rows = payload["games"].array ?: throw IllegalStateException("invalid")
        if (payload["schema"].integer != 1L || rows.size > maximumGames) throw IllegalStateException("invalid")
        val decoded = rows.map(DeckStudioRecordedGame::decode)
        if (decoded.map { it.id }.toSet().size != decoded.size) throw IllegalStateException("invalid")
        decoded.forEach { it.validate() }
        games = decoded.map { if (it.end == DeckStudioRecordedGame.End.IN_PROGRESS) it.copy(end = DeckStudioRecordedGame.End.INTERRUPTED, finishedAt = it.observedAt) else it }
        loaded = true
    }

    private fun encoded(values: List<DeckStudioRecordedGame>): ByteArray =
        JsonObject(mapOf("schema" to JsonPrimitive(1), "games" to JsonArray(values.map { it.json() }))).toString().toByteArray(Charsets.UTF_8)

    private fun write(values: List<DeckStudioRecordedGame>) {
        val file = file ?: throw IllegalStateException("unavailable")
        val data = encoded(values)
        if (data.size > maximumBytes) throw IllegalStateException("invalid")
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, file.name + ".tmp")
        temporary.writeBytes(data)
        if (!temporary.renameTo(file)) { temporary.delete(); throw IllegalStateException("unavailable") }
    }

    companion object {
        const val enabledKey = "magicmobile.playtestSummaries.enabled"
        const val detailedEnabledKey = "magicmobile.playtestPublicTimeline.enabled"
        const val maximumBytes = 8 * 1024 * 1024
        const val maximumGames = 100
    }
}

/** A JSON helper for places that store plain string payloads. */
internal fun parseJson(text: String): JsonElement = Json.parseToJsonElement(text)
