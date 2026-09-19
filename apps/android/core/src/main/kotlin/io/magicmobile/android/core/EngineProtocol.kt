package io.magicmobile.android.core

import io.magicmobile.core.Json
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.UUID

/** Exact protocol values; labels are never reused as commands. No Android dependencies. */
typealias Obj = Map<String, Any?>
class EngineFault(val code: String, message: String) : IllegalStateException(message)
object Wire {
    const val LIMIT = 4 * 1024 * 1024
    fun objectValue(value: Any?): Obj {
        if (value !is Map<*, *> || value.keys.any { it !is String }) throw EngineFault("bad_response", "Expected an object")
        @Suppress("UNCHECKED_CAST") return value as Obj
    }
    fun list(value: Any?): List<Any?> = value as? List<*> ?: throw EngineFault("bad_response", "Expected an array")
    fun string(value: Any?): String = value as? String ?: throw EngineFault("bad_response", "Expected a string")
    fun integer(value: Any?): Long = try { Json.integer(value) } catch (_: RuntimeException) { throw EngineFault("bad_response", "Expected an exact integer") }
    fun encode(value: Obj): ByteArray = Json.write(value).toByteArray(Charsets.UTF_8).also { require(it.size <= LIMIT) }
    fun decode(bytes: ByteArray): Obj {
        require(bytes.size <= LIMIT) { "Response exceeds limit" }
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        return objectValue(Json.parseObject(text))
    }
    fun result(bytes: ByteArray): Obj {
        val envelope = decode(bytes)
        if (integer(envelope["protocol"]) != 1L) throw EngineFault("protocol_mismatch", "Engine protocol is incompatible")
        when (envelope["ok"]) {
            true -> return objectValue(envelope["result"])
            false -> { val error = objectValue(envelope["error"])
                throw EngineFault(string(error["code"]), string(error["message"]).take(2000)) }
            else -> throw EngineFault("bad_response", "Missing success status")
        }
    }
    fun request(op: String, vararg fields: Pair<String, Any?>): ByteArray =
        encode(linkedMapOf("protocol" to 1, "op" to op, *fields))
    fun uuid(value: String): Boolean = runCatching { UUID.fromString(value).toString().equals(value, ignoreCase = true) }.getOrDefault(false)
}
fun Obj.obj(key: String): Obj? = this[key]?.let(Wire::objectValue)
fun Obj.array(key: String): List<Any?> = this[key]?.let(Wire::list) ?: emptyList()
fun Obj.text(key: String): String? = this[key] as? String
fun Obj.flag(key: String): Boolean = this[key] == true
fun Obj.number(key: String): Long? = this[key]?.let { runCatching { Wire.integer(it) }.getOrNull() }

data class Decision(val id: String, val revision: Long, val kind: String, val payload: Obj,
                    val responseTypes: Set<String>, val submitted: Boolean, val minimum: Long?, val maximum: Long?) {
    companion object {
        fun parse(value: Obj): Decision {
            val id = Wire.string(value["promptId"]); val revision = Wire.integer(value["revision"])
            val kind = Wire.string(value["kind"]); val types = Wire.list(value["responseTypes"]).map(Wire::string)
            require(id.isNotBlank() && revision >= 0 && kind.isNotBlank() && types.isNotEmpty() && types.toSet().size == types.size)
            require(types.all { it in setOf("boolean", "uuid", "string", "integer", "integers", "mana") })
            val min = value["min"]?.let(Wire::integer); val max = value["max"]?.let(Wire::integer)
            require(min == null || max == null || min <= max)
            require(value["submitted"] == null || value["submitted"] is Boolean)
            return Decision(id, revision, kind, Wire.objectValue(value["payload"]), types.toSet(), value["submitted"] == true, min, max)
        }
    }
    fun answer(type: String, value: Any?): Obj {
        require(!submitted && type in responseTypes) { "This prompt does not accept that response" }
        when(type) {
            "boolean" -> require(value is Boolean)
            "uuid" -> require(value is String && Wire.uuid(value))
            "string" -> require(value is String && value.length <= 8192 || value == null && kind == "CHOOSE_CHOICE" && payload.flag("specialEnabled") && payload.flag("specialCanBeEmpty"))
            "integer" -> { val n = Wire.integer(value); require(n in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()); require(minimum == null || n >= minimum); require(maximum == null || n <= maximum) }
            "integers" -> { val values = Wire.list(value).map(Wire::integer); require(values.size <= 1000 && values.all { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() });
                val allocations = payload.array("allocations").map(Wire::objectValue)
                require(values.size == allocations.size)
                values.zip(allocations).forEach { (n,row) -> require(n >= Wire.integer(row["min"]) && n <= Wire.integer(row["max"])) }
                val sum = values.sum(); require(minimum == null || sum >= minimum); require(maximum == null || sum <= maximum) }
            "mana" -> { val obj = Wire.objectValue(value); require(obj.keys == setOf("playerId", "manaType")); require(obj["playerId"] == payload["manaPlayerId"] && obj["playerId"] is String);
                require(obj["manaType"] in setOf("WHITE", "BLUE", "BLACK", "RED", "GREEN", "COLORLESS", "GENERIC")) }
        }
        return mapOf("kind" to type, "value" to value)
    }
    fun command(answer: Obj, requestId: String = UUID.randomUUID().toString()): Obj = mapOf(
        "requestId" to requestId, "promptId" to id, "promptRevision" to revision, "answer" to answer)
}

data class GamePoll(val matchId: String, val viewerId: String, val revision: Long, val phase: String,
                    val snapshot: Obj?, val decision: Decision?, val resync: Boolean, val events: List<Obj>, val failure: Obj?) {
    companion object {
        fun parse(value: Obj, match: String, viewer: String): GamePoll {
            require(value["matchId"] == match && value["viewerId"] == viewer) { "Wrong match or viewer" }
            val revision = Wire.integer(value["revision"]); require(revision >= 0)
            val phase = Wire.string(value["phase"]); require(phase in setOf("starting", "running", "ended", "failed", "closed"))
            val snapshot = value.obj("snapshot")
            snapshot?.let { val id = Wire.string(it["enginePlayerId"]); require(Wire.uuid(id));
                require(it.obj("gameView")?.get("myPlayerId") == id) { "Invalid private-view identity" } }
            val decision = value.obj("prompt")?.let(Decision::parse)
            require(decision == null || decision.revision <= revision)
            val events = value.array("events").map(Wire::objectValue); require(events.size <= 2000)
            return GamePoll(match, viewer, revision, phase, snapshot, decision, value.flag("resyncRequired"), events, value.obj("failure"))
        }
    }
}

/** Guards publication independently of the transport executor. */
class PollState(val match: String, val viewer: String) {
    var current: GamePoll? = null; private set
    var pending: Obj? = null; private set
    var terminal = false; private set
    private var submittedIdentity: Pair<String, Long>? = null
    fun prepare(type: String, value: Any?): Obj {
        check(!terminal && pending == null)
        val prompt = current?.decision ?: error("No decision")
        check(submittedIdentity != prompt.id to prompt.revision)
        return prompt.command(prompt.answer(type, value)).also { pending = it }
    }
    fun acknowledged() {
        pending?.let { submittedIdentity = Wire.string(it["promptId"]) to Wire.integer(it["promptRevision"]) }
        pending = null
    }
    fun rejected() { pending = null }
    fun publish(poll: GamePoll): Boolean {
        require(poll.matchId == match && poll.viewerId == viewer)
        if (terminal) return false
        val previous = current
        if (previous != null && poll.revision < previous.revision && !poll.resync) return false
        val identity = poll.decision?.let { it.id to it.revision }
        if (identity != submittedIdentity && (previous == null || poll.revision > previous.revision || poll.resync)) submittedIdentity = null
        val safe = if (identity != null && identity == submittedIdentity) poll.copy(decision = poll.decision.copy(submitted = true)) else poll
        if (pending != null && (poll.phase in setOf("ended", "failed", "closed") || identity != current?.decision?.let { it.id to it.revision } && (previous == null || poll.revision > previous.revision))) pending = null
        current = if (poll.phase == "closed") safe.copy(snapshot = null, decision = null, events = emptyList()) else safe
        terminal = poll.phase in setOf("ended", "failed", "closed")
        return true
    }
}
