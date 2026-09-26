package io.magicmobile.android.ondevice

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.board.GameEmote
import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.EngineTransport
import io.magicmobile.android.game.HostRouter
import io.magicmobile.android.game.J
import io.magicmobile.android.game.PeerFrame
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.isUuid
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import io.magicmobile.android.session.OnDeviceHostRetryPolicy
import io.magicmobile.android.session.OnDeviceTableLink
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.Normalizer
import java.util.Locale
import java.util.UUID

/** iOS encodes UUIDs uppercase (`uuidString`); every UUID this table sends does too. */
private val UUID.wire: String get() = toString().uppercase()
private fun uuidOrNull(value: String?): UUID? = value?.takeIf(::isUuid)?.let(UUID::fromString)
private fun text(value: String) = JsonPrimitive(value)
private fun number(value: Long) = JsonPrimitive(value)
private fun obj(vararg fields: Pair<String, J>) = JsonObject(linkedMapOf(*fields))

/** Swift CharacterSet.controlCharacters: general categories Cc and Cf. */
private fun String.hasControlCharacters(): Boolean = codePoints().anyMatch { cp ->
    val type = Character.getType(cp)
    type == Character.CONTROL.toInt() || type == Character.FORMAT.toInt()
}

/** Case- and diacritic-insensitive comparison key (Foundation's folding options). */
private fun String.foldedKey(): String =
    Normalizer.normalize(this, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)

private val String.characterCount: Int get() = codePointCount(0, length)

data class AISeatDescriptor(val deck: J, val skill: Int)

/** Port of OnDeviceMultiplayerLobby: peer IDs come only from the transport, never from packet fields. */
class OnDeviceMultiplayerLobby(peerIDs: List<String>, val localPeerID: String, aiSeats: List<AISeatDescriptor> = emptyList()) {
    sealed class HandshakeFailure(message: String) : Exception(message) {
        object DifferentBuild : HandshakeFailure("Players have different MagicMobile builds. Update every device to the same build and try again.")
        object DifferentSettings : HandshakeFailure("The host’s AI settings changed or a peer did not confirm them. Start a new match.")
    }

    val peerIDs: List<String> = peerIDs.sorted()
    var aiSettings: J; private set
    var acceptedHostSettings: Boolean; private set
    val hostID: String get() = peerIDs[0]
    val submissions = LinkedHashMap<String, J>()
    val isReady: Boolean get() = submissions.size == peerIDs.size

    init {
        if (peerIDs.size !in 2..4 || peerIDs.toSet().size != peerIDs.size || peerIDs.any { it.isEmpty() || it.toByteArray().size > 256 } ||
            localPeerID !in peerIDs) throw EngineError.InvalidMessage("A table needs 2–4 distinct connected players.")
        aiSettings = makeAISettings(aiSeats, peerIDs.size)
        acceptedHostSettings = localPeerID == this.peerIDs[0]
    }

    fun seatID(authenticatedPeerID: String): String {
        val index = peerIDs.indexOf(authenticatedPeerID)
        if (index < 0) throw EngineError.UnboundPeer
        return "player${index + 1}"
    }

    fun verifyHandshake(value: J, from: String, identity: BuildIdentity, epoch: UUID?): UUID {
        seatID(from)
        val fields = value.obj ?: throw EngineError.IncompatibleBuild
        val type = fields["type"].string
        if (type !in setOf("offer", "submission", "start")) throw EngineError.IncompatibleBuild
        val keys = when (type) {
            "submission" -> setOf("type", "epoch", "build", "roster", "aiSettings", "player")
            "start" -> setOf("type", "epoch", "build", "roster", "aiSettings", "matchId", "seatNames", "roll")
            else -> setOf("type", "epoch", "build", "roster", "aiSettings")
        }
        val incomingEpoch = uuidOrNull(fields["epoch"].string)
        if (fields.keys != keys || fields["roster"] != JsonArray(peerIDs.map(::text)) || incomingEpoch == null ||
            !(epoch?.let { it == incomingEpoch } ?: (type == "offer"))) throw EngineError.IncompatibleBuild
        if (type == "submission") {
            if (localPeerID != hostID || from == hostID) throw EngineError.UnboundPeer
        } else if (localPeerID == hostID || from != hostID) throw EngineError.UnboundPeer
        val build = fields["build"].obj
        if (build == null || build.keys != setOf("protocolVersion", "upstreamCommit", "catalogueHash", "adapterVersion") ||
            build["protocolVersion"].integer == null || build["upstreamCommit"].string == null || build["catalogueHash"].string == null ||
            build["adapterVersion"].string == null) throw EngineError.IncompatibleBuild
        val proposedSettings = fields["aiSettings"] ?: throw EngineError.IncompatibleBuild
        validateAISettings(proposedSettings, peerIDs.size)
        if (type == "submission") validateSubmission(fields["player"] ?: throw EngineError.IncompatibleBuild)
        else if (type == "start") {
            if (uuidOrNull(fields["matchId"].string) == null) throw EngineError.IncompatibleBuild
            val names = validatedSeatNames(fields["seatNames"], peerIDs.size + (proposedSettings["seats"].array?.size ?: 0))
            OnDeviceStartingRoll.decode(fields["roll"] ?: throw EngineError.IncompatibleBuild, (1..names.size).map { "player$it" })
        }
        // Only a well-formed handshake from the expected peer and epoch may end the lobby with a mismatch explanation.
        if (fields["build"] != identity.json) throw HandshakeFailure.DifferentBuild
        if (type != "offer" || acceptedHostSettings) {
            if (!acceptedHostSettings || proposedSettings != aiSettings) throw HandshakeFailure.DifferentSettings
        }
        return incomingEpoch
    }

    fun acceptHostOffer(value: J) {
        val settings = value["aiSettings"]
        if (localPeerID == hostID || settings == null) throw EngineError.UnboundPeer
        if (acceptedHostSettings && settings != aiSettings) throw HandshakeFailure.DifferentSettings
        aiSettings = settings; acceptedHostSettings = true
    }

    val hostAISeatSummary: String get() {
        val seats = aiSettings["seats"].array
        if (seats.isNullOrEmpty()) return "Host chose no AI seats."
        val details = seats.mapIndexed { index, seat ->
            val title = seat["deck"]["name"].string?.trim().orEmpty()
            "AI ${index + 1}: ${if (title.isNotEmpty() && !title.hasControlCharacters()) title else "selected deck"}, skill ${seat["skill"].integer ?: 0}"
        }
        return "Host chose ${seats.size} AI seat${if (seats.size == 1) "" else "s"}: ${details.joinToString("; ")}."
    }

    /** Complete once every connected human has submitted a deck. */
    val seatNames: Map<String, String> get() {
        if (!isReady) return emptyMap()
        val humans = peerIDs.mapIndexedNotNull { index, peer -> submissions[peer]?.get("name").string?.let { "player${index + 1}" to it } }
        if (humans.size != peerIDs.size) return emptyMap()
        val bots = (aiSettings["seats"].array ?: emptyList()).indices.map { index -> "player${peerIDs.size + index + 1}" to "AI ${index + 1}" }
        return uniqueSeatNames(humans + bots)
    }

    fun commanderNames(submission: J?): List<String> = Companion.commanderNames(submission)

    /** Host → guests: who has readied up and their commanders. */
    fun readyPacket(epoch: UUID): J {
        if (localPeerID != hostID) throw EngineError.UnboundPeer
        val players = peerIDs.mapNotNull { peer ->
            submissions[peer]?.let { obj("id" to text(peer), "commanders" to JsonArray(commanderNames(it).map(::text))) }
        }
        return obj("type" to text("ready"), "epoch" to text(epoch.wire), "players" to JsonArray(players))
    }

    fun acceptReadyPacket(value: J, from: String): Map<String, List<String>> {
        val fields = value.obj
        val players = fields?.get("players").array
        if (localPeerID == hostID || from != hostID || fields == null || fields.keys != setOf("type", "epoch", "players") ||
            players == null || players.size > peerIDs.size) throw EngineError.UnboundPeer
        val result = LinkedHashMap<String, List<String>>()
        for (player in players) {
            val row = player.obj
            val id = row?.get("id").string
            val commanders = row?.get("commanders").array
            if (row == null || row.keys != setOf("id", "commanders") || id == null || id !in peerIDs || result.containsKey(id) ||
                commanders == null || commanders.size > 4) throw EngineError.UnboundPeer
            val names = commanders.mapNotNull { it.string }
            if (names.size != commanders.size || !names.all { it.isNotEmpty() && it.characterCount <= 200 && !it.hasControlCharacters() }) {
                throw EngineError.UnboundPeer
            }
            result[id] = names
        }
        return result
    }

    fun submit(value: J, from: String) {
        seatID(from)
        validateSubmission(value)
        submissions[from]?.let { if (it != value) throw EngineError.InvalidMessage("A player changed their submitted lobby deck.") }
        submissions[from] = value
    }

    fun configuration(): J {
        if (localPeerID != hostID || !isReady) throw EngineError.InvalidMessage("The host is waiting for every player’s deck.")
        val names = seatNames
        val aiSeats = aiSettings["seats"].array ?: throw EngineError.IncompatibleBuild
        if (names.size != peerIDs.size + aiSeats.size) throw EngineError.UnboundPeer
        val humans = peerIDs.map { peer ->
            val deck = submissions[peer]?.get("deck") ?: throw EngineError.UnboundPeer
            val seat = seatID(peer)
            obj("seatId" to text(seat), "controller" to text("human"), "name" to text(names[seat] ?: throw EngineError.UnboundPeer), "deck" to deck)
        }
        val ais = aiSeats.mapIndexed { index, seat ->
            val deck = seat["deck"] ?: throw EngineError.IncompatibleBuild
            val skill = seat["skill"] ?: throw EngineError.IncompatibleBuild
            val seatID = "player${peerIDs.size + index + 1}"
            obj("seatId" to text(seatID), "controller" to text("ai"), "name" to text(names[seatID] ?: throw EngineError.UnboundPeer),
                "deck" to deck, "aiSkill" to skill)
        }
        return obj("seats" to JsonArray(humans + ais))
    }

    companion object {
        fun makeAISettings(seats: List<AISeatDescriptor>, humanCount: Int): J {
            val value = obj("count" to number(seats.size.toLong()),
                "seats" to JsonArray(seats.map { obj("deck" to it.deck, "skill" to number(it.skill.toLong())) }))
            validateAISettings(value, humanCount)
            return value
        }

        fun validateAISettings(value: J, humanCount: Int) {
            val fields = value.obj
            val count = fields?.get("count").integer
            val seats = fields?.get("seats").array
            if (fields == null || fields.keys != setOf("count", "seats") || count == null || seats == null || count != seats.size.toLong() ||
                humanCount !in 2..4 || humanCount + seats.size > 4) {
                throw EngineError.InvalidMessage("A table needs 2–4 total human and AI seats, with AI skill from 1–10.")
            }
            for (seat in seats) {
                val row = seat.obj
                val deck = row?.get("deck"); val skill = row?.get("skill").integer
                if (row == null || row.keys != setOf("deck", "skill") || deck == null || skill == null || skill !in 1L..10L) {
                    throw EngineError.InvalidMessage("Invalid AI seat deck or skill.")
                }
                validateSubmission(obj("name" to text("AI"), "deck" to deck))
            }
        }

        private fun uniqueSeatNames(seats: List<Pair<String, String>>): Map<String, String> {
            val trimmed = seats.map { it.second.trim() }
            val counts = trimmed.groupingBy { it.foldedKey() }.eachCount()
            fun suffixed(name: String, seatID: String): String {
                val suffix = " ($seatID)"
                val points = name.codePoints().toArray()
                return String(points, 0, minOf(points.size, 40 - suffix.length)).trim() + suffix
            }
            var names = seats.mapIndexed { index, seat -> if ((counts[trimmed[index].foldedKey()] ?: 0) > 1) suffixed(trimmed[index], seat.first) else trimmed[index] }
            if (names.map { it.foldedKey() }.toSet().size != names.size) names = seats.mapIndexed { index, seat -> suffixed(trimmed[index], seat.first) }
            return seats.map { it.first }.zip(names).toMap()
        }

        fun validatedSeatNames(value: J?, totalSeats: Int): Map<String, String> {
            val fields = value.obj
            if (fields == null || fields.size != totalSeats || fields.keys != (1..totalSeats).map { "player$it" }.toSet()) throw EngineError.IncompatibleBuild
            val seen = HashSet<String>()
            val result = LinkedHashMap<String, String>()
            for ((seatID, nameValue) in fields) {
                val name = nameValue.string
                if (name == null || name.isEmpty() || name != name.trim() || name.characterCount > 40 || name.hasControlCharacters()) {
                    throw EngineError.IncompatibleBuild
                }
                if (!seen.add(name.foldedKey())) throw EngineError.IncompatibleBuild
                result[seatID] = name
            }
            return result
        }

        fun validateSubmission(value: J) {
            val fields = value.obj
            val name = fields?.get("name").string
            val deck = fields?.get("deck").obj
            val main = deck?.get("main").array
            val commanders = deck?.get("commanders").array
            if (EngineJson.encode(value).size > 64 * 1024 || fields == null || fields.keys != setOf("name", "deck") || name == null ||
                name.isBlank() || name.characterCount > 40 || name.hasControlCharacters() || deck == null ||
                !setOf("name", "main", "commanders", "companions").containsAll(deck.keys) || main == null || commanders == null) {
                throw EngineError.InvalidMessage("Invalid player name or resolved deck. Names must contain 1–40 characters.")
            }
            deck["name"]?.let { if (it.string == null || it.string!!.characterCount > 200) throw EngineError.InvalidMessage("Invalid deck name.") }
            deck["companions"]?.let { if (it.array == null) throw EngineError.InvalidMessage("Invalid companion list.") }
            // Resource bounds only; XMage owns Commander legality, including special deck sizes.
            val rows = main + commanders + (deck["companions"].array ?: emptyList())
            if (rows.size > 2000) throw EngineError.MessageTooLarge
            var total = 0L
            for (row in rows) {
                val entry = row.obj
                val count = entry?.get("count").integer
                val set = entry?.get("setCode").string
                val number = entry?.get("collectorNumber").string
                if (entry == null || !setOf("name", "setCode", "collectorNumber", "count").containsAll(entry.keys) || count == null ||
                    count !in 1L..2000L || set.isNullOrEmpty() || set.toByteArray().size > 64 || number.isNullOrEmpty() || number.toByteArray().size > 64) {
                    throw EngineError.InvalidMessage("Deck must contain resolved compiled printings.")
                }
                entry["name"]?.let { if (it.string == null || it.string!!.toByteArray().size > 512) throw EngineError.InvalidMessage("Invalid printing name.") }
                total += count
                if (total > 2000) throw EngineError.MessageTooLarge
            }
        }

        fun commanderNames(submission: J?): List<String> = (submission?.get("deck")?.get("commanders").array ?: emptyList())
            .mapNotNull { it["name"].string }.filter { it.isNotEmpty() && it.characterCount <= 200 && !it.hasControlCharacters() }
    }
}

/**
 * A host request that got no answer in time (OnDeviceHostUnavailable in OnDeviceMultiplayer.swift).
 * The request may still run on the host, so only polls and hello, which change nothing, are retried.
 */
class OnDeviceHostUnavailable : Exception("The host did not answer in time. Keep every player’s app in the foreground.")

/**
 * Host → guest: "the game moved to `revision`; poll when you can." Tiny, idempotent and safe to
 * drop: a guest that misses one still polls on its heartbeat, and nothing ever queues for it.
 */
object OnDeviceRevisionNotice {
    fun packet(epoch: UUID, revision: Long): J = obj("type" to text("revision"), "epoch" to text(epoch.wire), "revision" to number(revision))

    /** The announced revision of a notice whose epoch the caller already checked. */
    fun revision(value: J): Long {
        val fields = value.obj
        val raw = fields?.get("revision")
        val revision = if (raw is JsonPrimitive && !raw.isString) raw.integer else null
        if (fields == null || fields.keys != setOf("type", "epoch", "revision") || fields["type"].string != "revision" ||
            revision == null || revision < 0) throw EngineError.InvalidMessage("Invalid revision notice.")
        return revision
    }
}

/**
 * Port of OnDeviceRemoteEngineTransport: a guest's engine is the host's, reached through
 * request/reply packets bound to the host's peer ID, the epoch and each request's sequence.
 */
class OnDeviceRemoteEngineTransport(private val hostID: String, private val matchID: String, private val seatID: String, private val epoch: UUID,
                                    private val scope: CoroutineScope, private val timeoutMillis: Long = 15_000,
                                    private val send: (ByteArray, String) -> Unit) : EngineTransport {
    private class Pending(val sequence: Long, val result: CompletableDeferred<J>)
    private var sequence = 0L
    private val pending = HashMap<UUID, Pending>()
    private var closed = false
    private var ready = false

    suspend fun hello(identity: BuildIdentity) {
        val result = exchange("hello", identity.json)
        if (result["seatId"].string != seatID || result["build"] != identity.json) throw EngineError.IncompatibleBuild
        ready = true
    }

    override suspend fun request(data: ByteArray): ByteArray {
        if (!ready || closed) throw EngineError.InvalidMessage("Multiplayer connection is not ready.")
        val fields = EngineJson.decode(data).obj
        val operation = fields?.get("op").string
        if (fields == null || fields["protocol"].integer != 1L || fields["matchId"].string != matchID || fields["viewerId"].string != seatID ||
            operation == null) throw EngineError.UnboundPeer
        val payload: J = when (operation) {
            "poll" -> {
                val after = fields["after"].integer
                if (fields.keys != setOf("protocol", "op", "matchId", "viewerId", "after") || after == null || after < 0) throw EngineError.InvalidMessage("Invalid remote poll.")
                obj("after" to number(after))
            }
            "respond" -> {
                if (fields.keys != setOf("protocol", "op", "matchId", "viewerId", "command")) throw EngineError.InvalidMessage("Invalid remote response.")
                fields["command"] ?: throw EngineError.InvalidMessage("Invalid remote response.")
            }
            // The host's router concedes only this peer's bound seat.
            "concede" -> {
                if (fields.keys != setOf("protocol", "op", "matchId", "viewerId")) throw EngineError.InvalidMessage("Invalid remote concede.")
                JsonObject(emptyMap())
            }
            else -> throw EngineError.InvalidMessage("Only the host may create or close the native match.")
        }
        val result = exchange(operation, payload)
        if (operation == "poll" && (result["matchId"].string != matchID || result["viewerId"].string != seatID)) throw EngineError.UnboundPeer
        return EngineJson.encode(obj("protocol" to number(1), "ok" to JsonPrimitive(true), "result" to result))
    }

    private suspend fun exchange(operation: String, payload: J): J {
        if (closed || pending.size >= 4) throw EngineError.InvalidMessage("Multiplayer connection is closed or busy.")
        sequence += 1
        val number = sequence; val id = UUID.randomUUID()
        val data = EngineJson.encode(obj("type" to text("request"), "id" to text(id.wire), "epoch" to text(epoch.wire),
            "sequence" to number(number), "operation" to text(operation), "payload" to payload))
        val result = CompletableDeferred<J>()
        pending[id] = Pending(number, result)
        try {
            send(data, hostID)
            return withTimeout(timeoutMillis) { result.await() }
        } catch (timeout: kotlinx.coroutines.TimeoutCancellationException) {
            throw OnDeviceHostUnavailable()
        } finally { pending.remove(id) }
    }

    fun receive(value: J, from: String) {
        if (from != hostID) throw EngineError.UnboundPeer
        val fields = value.obj
        val id = uuidOrNull(fields?.get("id").string)
        val sequence = fields?.get("sequence").integer
        if (fields == null || fields.keys != setOf("type", "id", "epoch", "sequence", "result", "error") || fields["type"].string != "reply" ||
            uuidOrNull(fields["epoch"].string) != epoch || id == null || sequence == null || sequence <= 0) throw EngineError.IncompatibleBuild
        val request = pending[id]
        if (request == null || request.sequence != sequence) throw EngineError.ReplayedMessage
        val error = fields["error"]
        when {
            error.obj != null -> {
                val message = error["message"].string
                if (error.obj!!.keys != setOf("code", "message") || error["code"].string != "busy" || message == null ||
                    message.toByteArray().size > 1024 || fields["result"] !is JsonNull) throw EngineError.InvalidMessage("Invalid remote transport error.")
                // Busy keeps the session's pending command and requestId: the original may still execute.
                request.result.completeExceptionally(EngineError.InvalidMessage(message))
            }
            error.string != null -> {
                if (error.string!!.toByteArray().size > 1024 || fields["result"] !is JsonNull) throw EngineError.InvalidMessage("Invalid remote error.")
                request.result.completeExceptionally(EngineError.Rejected("host_rejected", error.string!!))
            }
            else -> {
                val result = fields["result"]
                if (error !is JsonNull || result == null) throw EngineError.InvalidMessage("Invalid remote result.")
                EngineJson.validated(result)
                request.result.complete(result)
            }
        }
    }

    fun close() {
        closed = true; ready = false
        pending.values.forEach { it.result.completeExceptionally(CancellationException("closed")) }
        pending.clear()
    }
}

/** Port of OnDeviceHostRequestDispatcher: one in-order drain per peer; queued + active share a limit of four. */
class OnDeviceHostRequestDispatcher(private val router: HostRouter, private val epoch: UUID, private val peerIDs: Set<String>,
                                    private val scope: CoroutineScope, private val send: (J, String) -> Unit,
                                    private val onError: (String) -> Unit) {
    private class Request(val id: UUID, val frame: PeerFrame)
    private val queues = HashMap<String, ArrayDeque<Request>>()
    private val pending = HashMap<String, MutableSet<UUID>>()
    private val workers = HashMap<String, Job>()
    private var closed = false

    fun receive(value: J, peer: String) {
        if (closed || peer !in peerIDs) throw EngineError.UnboundPeer
        val fields = value.obj
        val id = uuidOrNull(fields?.get("id").string)
        val sequence = fields?.get("sequence").integer
        val operation = fields?.get("operation").string
        val payload = fields?.get("payload")
        if (fields == null || fields.keys != setOf("type", "epoch", "id", "sequence", "operation", "payload") || fields["type"].string != "request" ||
            uuidOrNull(fields["epoch"].string) != epoch || id == null || sequence == null || sequence <= 0 || operation == null || payload == null) {
            throw EngineError.InvalidMessage("Invalid host request.")
        }
        val request = Request(id, PeerFrame(epoch, sequence, operation, payload))
        if (pending[peer]?.contains(id) == true) throw EngineError.ReplayedMessage
        if ((pending[peer]?.size ?: 0) >= 4) {
            reply(request, peer, JsonNull, obj("code" to text("busy"), "message" to text("The host is busy. Retry the same action.")))
            return
        }
        pending.getOrPut(peer) { HashSet() }.add(id)
        queues.getOrPut(peer) { ArrayDeque() }.addLast(request)
        if (workers[peer]?.isActive != true) {
            // The main dispatcher runs a new coroutine at once: register it before it can finish.
            val worker = scope.launch(start = CoroutineStart.LAZY) { drain(peer) }
            workers[peer] = worker
            worker.start()
        }
    }

    private suspend fun drain(peer: String) {
        val self = currentCoroutineContext()[Job]
        try {
            while (!closed) {
                val request = queues[peer]?.removeFirstOrNull() ?: break
                var result: J = JsonNull; var error: J = JsonNull
                try { result = router.handle(request.frame, peer) }
                catch (cancel: CancellationException) { throw cancel }
                catch (failure: Throwable) { error = text((failure.message ?: failure.javaClass.simpleName).take(240)) }
                if (closed) return
                reply(request, peer, result, error)
                pending[peer]?.remove(request.id)
            }
        } finally { if (workers[peer] === self) { workers.remove(peer); pending.remove(peer); queues.remove(peer) } }
    }

    private fun reply(request: Request, peer: String, result: J, error: J) {
        try {
            send(obj("type" to text("reply"), "epoch" to text(epoch.wire), "id" to text(request.id.wire),
                "sequence" to number(request.frame.sequence), "result" to result, "error" to error), peer)
        } catch (failure: Throwable) { onError(failure.message ?: "Could not answer a player.") }
    }

    fun cancel() { closed = true; queues.clear(); workers.values.forEach { it.cancel() } }
}

/** What the apps say to the cross-play relay besides packets (services/table-relay/README.md). */
object RelayWire {
    /** Offered on every table socket; the relay answers with it. */
    const val SOCKET_PROTOCOL = "magicmobile.1"

    /** The host key or resume token travels as a subprotocol, so it never appears in the socket URL. */
    fun socketProtocols(hostKey: String?, resume: String?): List<String> =
        listOf(SOCKET_PROTOCOL) + listOfNotNull(hostKey?.let { "magicmobile.key.$it" }, resume?.let { "magicmobile.resume.$it" })

    /** What to show when the relay does not open a table: its own message, else a plain one. */
    fun createFailureMessage(status: Int?, message: String?): String =
        message?.trim()?.takeIf { it.isNotEmpty() }
            ?: if (status == 429) "You opened several tables in the last minute. Wait a minute, then try again."
            else "The table service could not open a table. Try again."

    /** The host turns a joiner away; the relay honors it only while the table is still filling. */
    fun removeFrame(peerID: String): String = JsonObject(mapOf("id" to JsonPrimitive(peerID), "t" to JsonPrimitive("remove"))).toString()
}

/** A relay table that is still filling: who has joined, in seat order. */
data class RelayWaitingSeat(val id: String, val name: String, val connected: Boolean, val isHost: Boolean, val isLocal: Boolean,
                            /** Only the host may remove a joiner, and only until the table is full: then every phone opens the match room. */
                            val removable: Boolean) {
    companion object {
        fun seats(peers: List<RelayPeer>, localPeerID: String?, full: Boolean): List<RelayWaitingSeat> {
            val sorted = peers.sortedBy { it.id }
            val hostID = sorted.firstOrNull()?.id ?: return emptyList()
            return sorted.map { peer ->
                RelayWaitingSeat(peer.id, peer.name, peer.connected, isHost = peer.id == hostID, isLocal = peer.id == localPeerID,
                    removable = localPeerID == hostID && !full && peer.id != hostID)
            }
        }
    }
}

/**
 * Port of OnDeviceMultiplayer over the relay: iPhones and Android phones meet at a table code.
 * The host's phone runs XMage; everyone else polls and answers it through the relay.
 */
class RelayTable(private val identity: BuildIdentity, private val scope: CoroutineScope,
                 private val makeHostEngine: suspend () -> EngineClient,
                 private val closeHostEngine: suspend (EngineClient) -> Unit) : TableConnection {
    data class MatchRoom(val players: List<Player>, val localReady: Boolean, val aiSummary: String?) {
        data class Player(val id: String, val name: String, val isHost: Boolean, val isLocal: Boolean, val isReady: Boolean, val commanders: List<String>)
    }

    override var endpoint by mutableStateOf<TableConnection.Endpoint?>(null); private set
    override var status by mutableStateOf("Host a table or join one with its code."); private set
    override var isConnected by mutableStateOf(false); private set
    override var isSuspended by mutableStateOf(false); private set
    override var needsCleanup by mutableStateOf(false); private set
    var hostAISeatSummary by mutableStateOf<String?>(null); private set
    var seatNames by mutableStateOf<Map<String, String>>(emptyMap()); private set
    var startingRoll by mutableStateOf<OnDeviceStartingRoll?>(null); private set
    var rollRevealedCount by mutableStateOf(0); private set
    var hasRolled by mutableStateOf(false); private set
    var rollStatus by mutableStateOf(""); private set
    var room by mutableStateOf<MatchRoom?>(null); private set
    /** The code to share while players join, and how many seats are taken. */
    var tableCode by mutableStateOf<String?>(null); private set
    var seatsTaken by mutableStateOf(0); private set
    var seatsWanted by mutableStateOf(0); private set
    /** Who has joined a table that is still filling; empty once the match room opens. */
    var waitingSeats by mutableStateOf<List<RelayWaitingSeat>>(emptyList()); private set
    var isHosting by mutableStateOf(false); private set
    var isFailed by mutableStateOf(false); private set
    /** A player's quick-chat line: their table name and a fixed emote, never free text. */
    var onEmote: ((String, GameEmote) -> Unit)? = null

    private var relay: RelayTransport? = null
    private var remote: OnDeviceRemoteEngineTransport? = null
    /** This seat's link to its session: the host announces revisions, a guest hears them. */
    private var tableLink: OnDeviceTableLink? = null
    private var router: HostRouter? = null
    private var lobby: OnDeviceMultiplayerLobby? = null
    private var submission: J? = null
    private var epoch: UUID? = null
    private var hostEngine: EngineClient? = null
    private var nativeMatchID: String? = null
    private var startup: Job? = null
    private var hostDispatcher: OnDeviceHostRequestDispatcher? = null
    private var lobbyTimer: Job? = null
    private var rollTimer: Job? = null
    private val suspendedPeers = HashSet<String>()
    /** Players whose connection to the relay dropped; they may still resume their seat. */
    private val relayAwayPeers = HashSet<String>()
    private var presenceSequence = 0L
    private var suspensionRevision = 0L
    private val peerPresenceSequences = HashMap<String, Long>()
    private var requestedAISeats: List<AISeatDescriptor> = emptyList()
    private var closing = false
    private var generation = UUID.randomUUID()
    private var localReady = false
    private var playerNames = HashMap<String, String>()
    private var reportedReady: Map<String, List<String>> = emptyMap()
    private var rollProgress: OnDeviceStartingRollProgress? = null
    private val lastEmoteFrom = HashMap<String, Long>()

    val isHost: Boolean get() = lobby?.let { it.localPeerID == it.hostID } ?: isHosting
    val localSeatID: String? get() = endpoint?.seatID
    val nextRollSeatID: String? get() = rollProgress?.nextSeatID

    /** Opens a table on the relay: this phone hosts `humans` players plus any AI seats. */
    suspend fun host(humans: Int, name: String, deck: J, aiSeats: List<AISeatDescriptor>) {
        if (relay != null || endpoint != null || closing) throw EngineError.InvalidMessage("Leave the current table before opening another.")
        val value = obj("name" to text(name.trim()), "deck" to deck)
        OnDeviceMultiplayerLobby.validateSubmission(value)
        OnDeviceMultiplayerLobby.makeAISettings(aiSeats, humans)
        submission = value; requestedAISeats = aiSeats; isFailed = false; generation = UUID.randomUUID()
        isHosting = true; seatsWanted = humans
        status = "Opening a table…"
        val transport = RelayTransport()
        relay = transport
        val (code, key) = try { transport.createTable(humans) } catch (error: Throwable) { relay = null; isHosting = false; throw error }
        tableCode = code
        attach(transport)
        transport.connect(code, name.trim(), hostKey = key)
        status = "Share code $code. Waiting for players…"
    }

    /** Joins a table by its code; the host's AI choices apply once the table fills. */
    fun join(code: String, name: String, deck: J) {
        if (relay != null || endpoint != null || closing) throw EngineError.InvalidMessage("Leave the current table before joining another.")
        val clean = code.trim().uppercase()
        if (!Regex("^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$").matches(clean)) throw EngineError.InvalidMessage("Table codes have six letters and numbers.")
        val value = obj("name" to text(name.trim()), "deck" to deck)
        OnDeviceMultiplayerLobby.validateSubmission(value)
        submission = value; requestedAISeats = emptyList(); isFailed = false; generation = UUID.randomUUID(); isHosting = false
        val transport = RelayTransport()
        relay = transport
        tableCode = clean
        attach(transport)
        transport.connect(clean, name.trim())
        status = "Joining table $clean…"
    }

    private fun attach(transport: RelayTransport) {
        val token = generation
        transport.onRoster = { peers, full ->
            if (generation == token && !isFailed && !closing) {
                seatsTaken = peers.size
                seatsWanted = transport.seats.takeIf { it > 0 } ?: maxOf(seatsWanted, peers.size)
                peers.forEach { playerNames[it.id] = it.name }
                waitingSeats = if (lobby == null && !full) RelayWaitingSeat.seats(peers, transport.localPeerID, full) else emptyList()
                val lobby = lobby
                if (lobby == null && full) startLobby(peers.map { it.id })
                else if (lobby == null) status = "Share code ${tableCode ?: ""}. Waiting for players (${peers.size}/$seatsWanted)…"
                else {
                    // A dropped phone pauses the match like a backgrounded app, until it returns or the relay gives up on it.
                    // Before the match starts, the lobby's repeating offer already covers a brief drop.
                    val away = peers.filter { !it.connected && it.id != lobby.localPeerID }.map { it.id }.toSet()
                    if (away != relayAwayPeers) { relayAwayPeers.clear(); relayAwayPeers.addAll(away); if (endpoint != null) updateSuspension() }
                }
            }
        }
        transport.onPacket = { packet, peer ->
            if (generation == token && !isFailed && !closing) {
                try { receive(packet, peer) }
                catch (failure: OnDeviceMultiplayerLobby.HandshakeFailure) {
                    if (failure is OnDeviceMultiplayerLobby.HandshakeFailure.DifferentSettings) {
                        val lobby = lobby; val epoch = epoch
                        if (lobby != null && lobby.localPeerID == lobby.hostID && epoch != null) runCatching { broadcast(settingsRejection(epoch.wire)) }
                        else runCatching { EngineJson.decode(packet)["epoch"].string?.let { send(settingsRejection(it), peer) } }
                    }
                    fail(failure.message ?: "Players have different settings.")
                } catch (_: Throwable) { /* Reject malformed, stale or unauthorized packets without ending the match. */ }
            }
        }
        transport.onDisconnect = { peer ->
            if (generation == token && !closing && peer != transport.localPeerID) {
                fail(if (lobby?.hostID == peer || (lobby == null && peer.startsWith("p1-"))) "The host left this table."
                    else "A player left. This match cannot continue. Leave and start a new match.")
            }
        }
        transport.onError = { message -> if (generation == token && !closing) fail(message) }
        transport.onConnectionChanged = { connected ->
            if (generation == token && !closing && !isFailed && lobby != null && endpoint != null) {
                if (connected) status = "Connected. Every player must keep the app in the foreground."
                else status = "Reconnecting to the table…"
            }
        }
    }

    /**
     * The host turns a joiner away while the table is still filling. The relay confirms it with a
     * roster without that player; it ignores a removal once the table is full.
     */
    fun removeFromTable(peerID: String) {
        if (lobby != null || isFailed || closing || waitingSeats.none { it.id == peerID && it.removable }) return
        relay?.remove(peerID)
    }

    private fun startLobby(peerIDs: List<String>) {
        val transport = relay ?: return
        val localID = transport.localPeerID ?: return
        try {
            val roster = OnDeviceMultiplayerLobby(peerIDs, localID, requestedAISeats)
            if (roster.hostID == localID) epoch = UUID.randomUUID()
            lobby = roster
            localReady = false; reportedReady = emptyMap()
            playerNames[localID] = transport.peers.firstOrNull { it.id == localID }?.name ?: "You"
            updateRoom()
            hostAISeatSummary = if (roster.hostID == localID) roster.hostAISeatSummary else null
            status = "Match room: choose your deck, then tap Ready. The game starts when everyone is."
            val token = generation
            lobbyTimer = scope.launch {
                // Repeat the host offer while players ready up; late joiners learn who is ready.
                repeat(600) {
                    if (generation != token || isFailed || endpoint != null) return@launch
                    val current = lobby
                    if (startup == null && current?.hostID == localID) {
                        try { broadcast(lobbyPacket("offer")); broadcastReadyRoster() }
                        catch (error: Throwable) { fail(error.message ?: "Could not reach the other players."); return@launch }
                    }
                    delay(1000)
                }
                fail("The table timed out before everyone was ready. Leave and open a new table.")
            }
        } catch (error: Throwable) { fail(error.message ?: "Could not start the table.") }
    }

    private fun lobbyPacket(type: String): JsonObject {
        val lobby = lobby ?: throw EngineError.IncompatibleBuild
        val epoch = epoch ?: throw EngineError.IncompatibleBuild
        return obj("type" to text(type), "epoch" to text(epoch.wire), "build" to identity.json,
            "roster" to JsonArray(lobby.peerIDs.map(::text)), "aiSettings" to lobby.aiSettings)
    }

    private fun receive(data: ByteArray, peer: String) {
        val lobby = lobby ?: throw EngineError.UnboundPeer
        lobby.seatID(peer)
        val value = EngineJson.decode(data)
        val fields = value.obj ?: throw EngineError.InvalidMessage("Invalid multiplayer packet.")
        val type = fields["type"].string ?: throw EngineError.InvalidMessage("Invalid multiplayer packet.")
        if (type == "offer" || type == "submission" || type == "start") {
            val incomingEpoch = lobby.verifyHandshake(value, peer, identity, epoch)
            when (type) {
                "offer" -> {
                    val submission = submission ?: throw EngineError.UnboundPeer
                    lobby.acceptHostOffer(value)
                    hostAISeatSummary = lobby.hostAISeatSummary
                    epoch = incomingEpoch
                    updateRoom()
                    if (remote == null && localReady) sendSubmission(submission, peer)
                }
                "submission" -> {
                    lobby.submit(fields["player"] ?: throw EngineError.UnboundPeer, peer)
                    broadcastReadyRoster()
                    updateRoom()
                    if (lobby.isReady && startup == null && hostEngine == null) startHost()
                }
                else -> {
                    val matchID = fields["matchId"].string?.takeIf(::isUuid) ?: throw EngineError.UnboundPeer
                    if (remote != null) return
                    val names = OnDeviceMultiplayerLobby.validatedSeatNames(fields["seatNames"],
                        lobby.peerIDs.size + (lobby.aiSettings["seats"].array?.size ?: 0))
                    val seats = (1..names.size).map { "player$it" }
                    val result = OnDeviceStartingRoll.decode(fields["roll"] ?: throw EngineError.IncompatibleBuild, seats)
                    seatNames = names
                    startingRoll = result
                    rollProgress = OnDeviceStartingRollProgress(result, (1..lobby.peerIDs.size).map { "player$it" }.toSet())
                    rollRevealedCount = 0
                    startClient(matchID, incomingEpoch)
                }
            }
            return
        }
        val epoch = epoch
        if (epoch == null || uuidOrNull(fields["epoch"].string) != epoch) throw EngineError.IncompatibleBuild
        when (type) {
            "request" -> {
                val dispatcher = hostDispatcher
                if (lobby.localPeerID != lobby.hostID || dispatcher == null) throw EngineError.UnboundPeer
                debugLog("guest request ${fields["operation"].string} from $peer")
                dispatcher.receive(value, peer)
            }
            "reply" -> (remote ?: throw EngineError.UnboundPeer).receive(value, peer)
            "revision" -> {
                val link = tableLink
                if (peer != lobby.hostID || lobby.localPeerID == lobby.hostID || link == null) throw EngineError.UnboundPeer
                link.noticed(OnDeviceRevisionNotice.revision(value))
            }
            "rollStep" -> {
                val index = fields["index"].integer
                if (fields.keys != setOf("type", "epoch", "index") || lobby.localPeerID != lobby.hostID || nativeMatchID == null ||
                    index == null || index < 0 || index > Int.MAX_VALUE) throw EngineError.UnboundPeer
                advanceHumanRoll(peer, index.toInt())
            }
            "rollAdvance" -> {
                val index = fields["index"].integer
                val progress = rollProgress
                if (fields.keys != setOf("type", "epoch", "index") || peer != lobby.hostID || lobby.localPeerID == lobby.hostID ||
                    index == null || index < 0 || index > Int.MAX_VALUE || progress == null) throw EngineError.UnboundPeer
                progress.acceptHostAdvance(index.toInt())
                rollRevealedCount = progress.revealedCount
                hasRolled = false
                updateRollStatus()
            }
            "ready" -> { reportedReady = lobby.acceptReadyPacket(value, peer); updateRoom() }
            "presence" -> {
                val sequence = fields["sequence"].integer
                val suspended = fields["suspended"].bool
                if (fields.keys != setOf("type", "epoch", "sequence", "suspended") || sequence == null ||
                    sequence <= (peerPresenceSequences[peer] ?: 0) || suspended == null) throw EngineError.ReplayedMessage
                if (lobby.localPeerID != lobby.hostID && peer != lobby.hostID) throw EngineError.UnboundPeer
                peerPresenceSequences[peer] = sequence
                if (suspended) suspendedPeers.add(peer) else suspendedPeers.remove(peer)
                updateSuspension()
            }
            "emote" -> {
                val emote = GameEmote.of(fields["emote"].string)
                if (fields.keys != setOf("type", "epoch", "emote") || (nativeMatchID == null && remote == null) || emote == null) {
                    throw EngineError.InvalidMessage("Invalid emote.")
                }
                // Cosmetic only: a flood from one player is dropped, never an error.
                val now = System.currentTimeMillis()
                lastEmoteFrom[peer]?.let { if (now - it < 1500) return }
                lastEmoteFrom[peer] = now
                (seatNames[lobby.seatID(peer)] ?: playerNames[peer])?.let { onEmote?.invoke(it, emote) }
            }
            "end" -> {
                if (fields.keys != setOf("type", "epoch")) throw EngineError.InvalidMessage("Invalid match ending.")
                fail(if (peer == lobby.hostID) "The host ended this match." else "A player left. Start a new match to play again.")
            }
            "reject" -> {
                if (fields.keys != setOf("type", "epoch", "reason") || fields["reason"].string != "aiSettings" ||
                    (peer != lobby.hostID && lobby.localPeerID != lobby.hostID)) throw EngineError.UnboundPeer
                if (lobby.localPeerID == lobby.hostID) runCatching { broadcast(settingsRejection(epoch.wire)) }
                fail(OnDeviceMultiplayerLobby.HandshakeFailure.DifferentSettings.message ?: "")
            }
            else -> throw EngineError.InvalidMessage("Unknown multiplayer packet.")
        }
    }

    /** A human tap advances only that seat; the host broadcasts the next visible step to everyone. */
    fun rollStartingPlayer() {
        val lobby = lobby; val epoch = epoch; val endpoint = endpoint; val progress = rollProgress
        if (lobby == null || epoch == null || endpoint == null || progress == null || !isConnected || isSuspended ||
            progress.nextSeatID != endpoint.seatID) throw EngineError.InvalidMessage("Wait for your turn to roll.")
        if (hasRolled) return
        if (lobby.localPeerID == lobby.hostID) advanceHumanRoll(lobby.localPeerID, progress.revealedCount)
        else {
            send(obj("type" to text("rollStep"), "epoch" to text(epoch.wire), "index" to number(progress.revealedCount.toLong())), lobby.hostID)
            hasRolled = true
            rollStatus = "Sharing your roll with everyone…"
        }
    }

    private fun advanceHumanRoll(peer: String, index: Int) {
        val lobby = lobby; val progress = rollProgress
        if (lobby == null || lobby.localPeerID != lobby.hostID || progress == null || index != progress.revealedCount) throw EngineError.ReplayedMessage
        progress.advance(lobby.seatID(peer), automated = false)
        shareRollAdvance(index)
        rollRevealedCount = progress.revealedCount
        updateRollStatus()
    }

    /** Called by the host's roll presentation after the previous die settles. */
    fun advanceAISeatIfNeeded() {
        val lobby = lobby; val progress = rollProgress
        if (lobby == null || lobby.localPeerID != lobby.hostID || !isConnected || isSuspended || progress == null) return
        val seatID = progress.nextSeatID ?: return
        if (seatID in progress.humanSeatIDs) return
        val index = progress.advance(seatID, automated = true)
        shareRollAdvance(index)
        rollRevealedCount = progress.revealedCount
        updateRollStatus()
    }

    private fun shareRollAdvance(index: Int) {
        val epoch = epoch ?: throw EngineError.UnboundPeer
        broadcast(obj("type" to text("rollAdvance"), "epoch" to text(epoch.wire), "index" to number(index.toLong())))
    }

    private fun updateRollStatus() {
        val next = rollProgress?.nextSeatID
        if (next != null) {
            rollStatus = "Waiting for ${seatNames[next] ?: "the next player"} to roll."
            if (isConnected) beginRollTimer()
        } else { rollStatus = "Starting player decided by D20."; rollTimer?.cancel(); rollTimer = null }
    }

    private fun beginRollTimer() {
        rollTimer?.cancel()
        val token = generation
        rollTimer = scope.launch {
            delay(300_000)
            if (generation == token && isConnected && rollProgress?.isComplete == false) fail("Starting roll timed out. Leave and start a new match.")
        }
    }

    /** Quick chat to every other player in the running match. */
    fun sendEmote(emote: GameEmote) {
        val epoch = epoch ?: return
        if (nativeMatchID == null && remote == null) return
        runCatching { broadcast(obj("type" to text("emote"), "epoch" to text(epoch.wire), "emote" to text(emote.rawValue))) }
    }

    /** The local player confirms a deck in the match room. */
    fun markReady(name: String, deck: J) {
        val lobby = lobby ?: return
        if (localReady || isFailed || closing || endpoint != null) return
        val value = obj("name" to text(name.trim()), "deck" to deck)
        OnDeviceMultiplayerLobby.validateSubmission(value)
        submission = value
        localReady = true
        if (lobby.localPeerID == lobby.hostID) {
            lobby.submit(value, lobby.localPeerID)
            broadcastReadyRoster()
            if (lobby.isReady && startup == null && hostEngine == null) startHost()
        } else if (epoch != null && lobby.acceptedHostSettings) sendSubmission(value, lobby.hostID)
        status = if (lobby.localPeerID == lobby.hostID || epoch != null) "Ready. Waiting for the other players…" else "Ready. Waiting for the host…"
        updateRoom()
    }

    private fun sendSubmission(value: J, peer: String) {
        send(JsonObject(lobbyPacket("submission") + ("player" to value)), peer)
    }

    private fun broadcastReadyRoster() {
        val lobby = lobby ?: return
        val epoch = epoch ?: return
        if (lobby.localPeerID != lobby.hostID) return
        broadcast(lobby.readyPacket(epoch))
    }

    private fun updateRoom() {
        val lobby = lobby
        if (lobby == null || endpoint != null || isFailed) { room = null; return }
        val isHost = lobby.localPeerID == lobby.hostID
        val players = lobby.peerIDs.map { peer ->
            val local = peer == lobby.localPeerID
            val submitted = lobby.submissions[peer]
            val ready = if (isHost) submitted != null else if (local) localReady else reportedReady[peer] != null
            val commanders = submitted?.let(lobby::commanderNames)
                ?: if (local) lobby.commanderNames(if (localReady) submission else null) else reportedReady[peer] ?: emptyList()
            MatchRoom.Player(peer, if (local) "You" else playerNames[peer] ?: "Player", peer == lobby.hostID, local, ready, commanders)
        }
        room = MatchRoom(players, localReady, hostAISeatSummary)
    }

    private fun startHost() {
        val lobby = lobby ?: return
        val epoch = epoch ?: return
        val token = generation
        startup = scope.launch {
            try {
                val engine = makeHostEngine()
                hostEngine = engine; needsCleanup = true
                val created = engine.create(lobby.configuration())
                val matchID = created["matchId"].string?.takeIf(::isUuid) ?: throw EngineError.InvalidMessage("The native engine returned an invalid match.")
                nativeMatchID = matchID
                val router = HostRouter(engine, matchID, identity, epoch)
                for (peer in lobby.peerIDs) if (peer != lobby.hostID) router.bind(peer, lobby.seatID(peer))
                if (generation != token || isFailed || closing) return@launch
                this@RelayTable.router = router
                hostDispatcher = OnDeviceHostRequestDispatcher(router, epoch, lobby.peerIDs.filter { it != lobby.hostID }.toSet(), scope,
                    send = { value, peer -> if (generation == token && !isFailed && !closing) send(value, peer) },
                    onError = { message -> if (generation == token && !closing) fail(message) })
                suspensionRevision += 1
                router.setSuspended(suspendedPeers.isNotEmpty() || relayAwayPeers.isNotEmpty(), suspensionRevision)
                if (generation != token || isFailed || closing) return@launch
                val names = lobby.seatNames
                val packetNames = JsonObject(names.mapValues { text(it.value) })
                OnDeviceMultiplayerLobby.validatedSeatNames(packetNames, lobby.peerIDs.size + (lobby.aiSettings["seats"].array?.size ?: 0))
                val seats = (1..names.size).map { "player$it" }
                val result = OnDeviceStartingRoll.generate(seats)
                broadcast(JsonObject(lobbyPacket("start") + mapOf("matchId" to text(matchID), "seatNames" to packetNames,
                    "roll" to result.encoded(seats))))
                seatNames = names
                startingRoll = result
                rollProgress = OnDeviceStartingRollProgress(result, (1..lobby.peerIDs.size).map { "player$it" }.toSet())
                rollRevealedCount = 0
                val hostSeat = lobby.seatID(lobby.localPeerID)
                val link = OnDeviceTableLink(OnDeviceTableLink.Role.HOST, names[hostSeat] ?: "")
                link.announce = { revision -> announceRevision(revision, token) }
                tableLink = link
                endpoint = TableConnection.Endpoint(engine, matchID, hostSeat, isHost = true, table = link)
                room = null
                isConnected = true
                updateRollStatus()
                lobbyTimer?.cancel(); status = "Connected as host. Every player must keep the app in the foreground."
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Throwable) { fail(error.message ?: "Could not start the match.") }
        }
    }

    private fun startClient(matchID: String, epoch: UUID) {
        val lobby = lobby ?: throw EngineError.UnboundPeer
        val relay = relay ?: throw EngineError.UnboundPeer
        val seatID = lobby.seatID(lobby.localPeerID)
        val remote = OnDeviceRemoteEngineTransport(lobby.hostID, matchID, seatID, epoch, scope) { data, peer -> relay.send(data, peer) }
        this.remote = remote
        val link = OnDeviceTableLink(OnDeviceTableLink.Role.GUEST, seatNames[lobby.seatID(lobby.hostID)] ?: playerNames[lobby.hostID] ?: "")
        tableLink = link
        val token = generation
        startup = scope.launch {
            try {
                // Hello changes nothing on the host, so a lost answer is simply asked again.
                val retries = OnDeviceHostRetryPolicy()
                while (true) {
                    try { remote.hello(identity); break }
                    catch (error: OnDeviceHostUnavailable) {
                        val backoff = retries.delayAfter(error)
                        if (backoff == null || generation != token || isFailed || closing) throw error
                        status = link.waitingStatus
                        delay(backoff)
                    }
                }
                if (generation != token || isFailed || closing) return@launch
                endpoint = TableConnection.Endpoint(EngineClient(remote), matchID, seatID, isHost = false, table = link)
                room = null
                isConnected = true
                updateRollStatus()
                lobbyTimer?.cancel(); status = "Connected. Every player must keep the app in the foreground."
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Throwable) { fail(error.message ?: "Could not reach the host.") }
        }
    }

    override fun setForeground(active: Boolean) {
        val lobby = lobby ?: return
        if (isFailed || closing) return
        if (endpoint == null) return
        if (active) suspendedPeers.remove(lobby.localPeerID) else suspendedPeers.add(lobby.localPeerID)
        updateSuspension()
        if (lobby.localPeerID != lobby.hostID) sendPresence(!active, lobby.hostID)
    }

    private fun updateSuspension() {
        val lobby = lobby ?: return
        if (isFailed || closing) return
        val paused = suspendedPeers.isNotEmpty() || relayAwayPeers.isNotEmpty()
        isSuspended = paused
        status = if (relayAwayPeers.isNotEmpty()) {
            // The relay says who dropped; they may still come back within its grace period.
            val names = relayAwayPeers.sorted().map { peer ->
                runCatching { seatNames[lobby.seatID(peer)] }.getOrNull() ?: playerNames[peer] ?: "a player"
            }
            "Waiting for ${names.joinToString(", ")}…"
        } else if (paused) "Match paused. Every player must return to the foreground." else "Connected. Every player must keep the app in the foreground."
        if (lobby.localPeerID == lobby.hostID) {
            suspensionRevision += 1
            val revision = suspensionRevision
            router?.let { router -> scope.launch { router.setSuspended(paused, revision) } }
            lobby.peerIDs.filter { it != lobby.hostID }.forEach { sendPresence(paused, it) }
        }
    }

    /**
     * Tells each connected guest that the game moved on. Best effort: a guest that misses a notice
     * polls on its heartbeat, so a failed send never ends the match.
     */
    private fun announceRevision(revision: Long, token: UUID) {
        val lobby = lobby ?: return
        val epoch = epoch ?: return
        if (generation != token || isFailed || closing || lobby.localPeerID != lobby.hostID) return
        val notice = OnDeviceRevisionNotice.packet(epoch, revision)
        debugLog("host notice revision $revision")
        for (peer in lobby.peerIDs) if (peer != lobby.hostID && peer !in relayAwayPeers) runCatching { send(notice, peer) }
    }

    /** Debug builds only: lets a cross-play check count table traffic (`adb logcat -s MagicMobileTable`). */
    private fun debugLog(message: String) {
        if (io.magicmobile.android.BuildConfig.DEBUG) android.util.Log.d("MagicMobileTable", message)
    }

    private fun sendPresence(suspended: Boolean, peer: String) {
        val epoch = epoch ?: return
        presenceSequence += 1
        try {
            send(obj("type" to text("presence"), "epoch" to text(epoch.wire), "sequence" to number(presenceSequence),
                "suspended" to JsonPrimitive(suspended)), peer)
        } catch (error: Throwable) { /* The relay resumes the seat; presence repeats with the next change. */ }
    }

    /** A failed native destroy or close keeps the endpoint and engine so Leave can be retried. */
    override suspend fun leave() {
        if (closing) throw EngineError.InvalidMessage("Match shutdown is already in progress.")
        closing = true
        isConnected = false
        try {
            lobbyTimer?.cancel(); startup?.cancel(); remote?.close(); hostDispatcher?.cancel()
            epoch?.let { runCatching { broadcast(obj("type" to text("end"), "epoch" to text(it.wire))) } }
            relay?.disconnect()
            startup = null
            try {
                hostEngine?.let { engine ->
                    nativeMatchID?.let { engine.destroy(it); nativeMatchID = null }
                    closeHostEngine(engine)
                }
            } catch (error: Throwable) {
                status = "Native match shutdown failed. Try Leave again: ${error.message}"
                throw error
            }
            generation = UUID.randomUUID(); hostEngine = null; needsCleanup = false; endpoint = null; hostAISeatSummary = null; seatNames = emptyMap()
            rollTimer?.cancel(); rollTimer = null
            startingRoll = null; rollProgress = null; rollRevealedCount = 0; hasRolled = false; rollStatus = ""
            remote = null; tableLink = null; router = null; hostDispatcher = null; relay = null; lobby = null; epoch = null; submission = null; requestedAISeats = emptyList()
            suspendedPeers.clear(); relayAwayPeers.clear(); peerPresenceSequences.clear(); presenceSequence = 0; suspensionRevision = 0
            room = null; localReady = false; reportedReady = emptyMap(); playerNames.clear()
            tableCode = null; seatsTaken = 0; seatsWanted = 0; waitingSeats = emptyList(); isHosting = false
            isFailed = false; isSuspended = false; status = "Match closed."
        } finally { closing = false }
    }

    private fun fail(message: String) {
        if (isFailed) return
        isFailed = true; isConnected = false; status = message; seatNames = emptyMap(); room = null; waitingSeats = emptyList()
        rollTimer?.cancel(); rollTimer = null
        startingRoll = null; rollProgress = null; rollRevealedCount = 0; hasRolled = false; rollStatus = ""
        lobbyTimer?.cancel(); startup?.cancel(); remote?.close(); hostDispatcher?.cancel()
        epoch?.let { runCatching { broadcast(obj("type" to text("end"), "epoch" to text(it.wire))) } }
        relay?.let { it.onPacket = null; it.onRoster = null; it.onDisconnect = null; it.onError = null; it.disconnect() }
        // The UI keeps the endpoint and retries Leave if native teardown is busy.
    }

    private fun send(value: J, peer: String) {
        val relay = relay ?: throw EngineError.UnboundPeer
        relay.send(EngineJson.encode(value), peer)
    }

    private fun broadcast(value: J) {
        val lobby = lobby ?: return
        for (peer in lobby.peerIDs) if (peer != lobby.localPeerID) send(value, peer)
    }

    private fun settingsRejection(epoch: String): J = obj("type" to text("reject"), "epoch" to text(epoch), "reason" to text("aiSettings"))
}
