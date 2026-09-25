package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/** Port of MagicMobileOnDevice/EngineClient.swift. */
fun interface EngineTransport {
    suspend fun request(data: ByteArray): ByteArray
}

class EngineClient(private val transport: EngineTransport) {
    suspend fun call(operation: String, fields: Map<String, J> = emptyMap()): J {
        if (fields.containsKey("op") || fields.containsKey("protocol")) throw EngineError.InvalidMessage("Reserved request keys")
        val request = LinkedHashMap(fields).apply { put("protocol", JsonPrimitive(1)); put("op", JsonPrimitive(operation)) }
        val reply = EngineJson.decode(transport.request(EngineJson.encode(JsonObject(request))))
        val success = reply["ok"].bool
        if (reply["protocol"].integer != 1L || success == null) throw EngineError.InvalidMessage("Invalid engine response envelope")
        if (!success) {
            val error = reply["error"]
            val details = error["details"]
            if (details.obj != null) {
                throw EngineError.RejectionDetails(error["code"].string ?: "unknown",
                    error["message"].string ?: "Engine rejected request", details!!)
            }
            throw EngineError.Rejected(error["code"].string ?: "unknown", error["message"].string ?: "Engine rejected request")
        }
        return reply["result"] ?: throw EngineError.InvalidMessage("Missing result")
    }

    suspend fun capabilities(): J = call("capabilities")
    suspend fun create(configuration: J): J = call("create", mapOf("configuration" to configuration))

    suspend fun poll(matchID: String, seatID: String, after: Long = 0): MatchPoll {
        if (matchID.isEmpty() || seatID.isEmpty() || after < 0) throw EngineError.InvalidMessage("Invalid poll identity or revision")
        val value = call("poll", mapOf("matchId" to JsonPrimitive(matchID), "viewerId" to JsonPrimitive(seatID), "after" to JsonPrimitive(after)))
        val poll = MatchPoll(value)
        // Do not let a stale/misrouted response enter another match's presentation.
        if (poll.matchID != matchID || poll.seatID != seatID) throw EngineError.InvalidMessage("Poll response identity mismatch")
        return poll
    }

    suspend fun respond(matchID: String, seatID: String, prompt: EnginePrompt, answer: J, requestID: UUID = UUID.randomUUID()): J =
        call("respond", mapOf("matchId" to JsonPrimitive(matchID), "viewerId" to JsonPrimitive(seatID),
            "command" to prompt.command(answer, requestID)))

    /** The seat concedes. In a pod the game goes on and the seat keeps polling as a spectator. */
    suspend fun concede(matchID: String, seatID: String) {
        if (matchID.isEmpty() || seatID.isEmpty()) throw EngineError.InvalidMessage("Invalid concede identity")
        call("concede", mapOf("matchId" to JsonPrimitive(matchID), "viewerId" to JsonPrimitive(seatID)))
    }

    suspend fun destroy(matchID: String) { call("destroy", mapOf("matchId" to JsonPrimitive(matchID))) }
}

class EnginePrompt(value: J) {
    val id: String
    val revision: Long
    val kind: String
    val payload: J
    val submitted: Boolean
    val responseTypes: List<String>
    val minimum: Long
    val maximum: Long

    init {
        val id = value["promptId"].string
        val revision = value["revision"].integer
        val kind = value["kind"].string
        val payload = value["payload"]
        val submitted = value["submitted"].bool
        val types = value["responseTypes"].array
        val minimum = value["min"].integer
        val maximum = value["max"].integer
        if (id == null || revision == null || revision < 0 || kind == null || payload == null || submitted == null ||
            types == null || minimum == null || maximum == null) throw EngineError.InvalidMessage("Malformed engine prompt")
        if (id.isEmpty() || kind.isEmpty() || payload.obj == null || minimum > maximum || types.isEmpty() || types.size > 6) {
            throw EngineError.InvalidMessage("Invalid prompt structure or bounds")
        }
        this.id = id; this.revision = revision; this.kind = kind; this.payload = payload
        this.submitted = submitted; this.minimum = minimum; this.maximum = maximum
        responseTypes = types.map { it.string ?: throw EngineError.InvalidMessage("Response type must be a string") }
        val supported = setOf("boolean", "uuid", "string", "integer", "integers", "mana")
        if (responseTypes.toSet().size != responseTypes.size || !supported.containsAll(responseTypes)) {
            throw EngineError.InvalidMessage("Unknown or duplicate prompt response type")
        }
    }

    fun command(answer: J, requestID: UUID = UUID.randomUUID()): J = jsonObject(
        "requestId" to JsonPrimitive(requestID.toString().lowercase()), "promptId" to JsonPrimitive(id),
        "promptRevision" to JsonPrimitive(revision), "answer" to answer)

    override fun equals(other: Any?): Boolean = other is EnginePrompt && other.id == id && other.revision == revision &&
        other.kind == kind && other.payload == payload && other.submitted == submitted &&
        other.responseTypes == responseTypes && other.minimum == minimum && other.maximum == maximum
    override fun hashCode(): Int = id.hashCode() * 31 + revision.hashCode()

    companion object {
        fun answer(kind: String, value: J): J = jsonObject("kind" to JsonPrimitive(kind), "value" to value)
    }
}

class MatchPoll(value: J) {
    val raw: J = value
    val matchID: String
    val seatID: String
    val phase: String
    val revision: Long
    val prompt: EnginePrompt?
    val snapshot: J?
    val resyncRequired: Boolean

    init {
        val matchID = value["matchId"].string
        val seatID = value["viewerId"].string
        val revision = value["revision"].integer
        val phase = value["phase"].string
        val resync = value["resyncRequired"].bool
        if (matchID == null || seatID == null || revision == null || revision < 0 || phase == null || resync == null) {
            throw EngineError.InvalidMessage("Malformed match poll")
        }
        this.matchID = matchID; this.seatID = seatID; this.revision = revision; this.phase = phase; resyncRequired = resync
        snapshot = value["snapshot"].takeUnless { it is JsonNull }
        prompt = value["prompt"]?.takeUnless { it is JsonNull }?.let(::EnginePrompt)
    }

    override fun equals(other: Any?): Boolean = other is MatchPoll && other.raw == raw
    override fun hashCode(): Int = raw.hashCode()
}

/** Swift `[String]` built from a JSON array of strings, or null when any entry is not a string. */
internal fun JsonArray.strings(): List<String>? = map { it.string }.takeIf { all -> all.all { it != null } }?.map { it!! }
