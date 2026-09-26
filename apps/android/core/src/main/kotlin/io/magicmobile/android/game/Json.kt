package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull
import java.util.UUID

/**
 * Port of packages/ondevice-engine/swift/Sources/MagicMobileOnDevice/JSONValue.swift.
 * The engine speaks plain JSON; these helpers read it exactly like the Swift JSONValue:
 * a string is never a number or boolean, and a number is an integer only when exact.
 */
typealias J = JsonElement

val J?.string: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
val J?.integer: Long? get() = (this as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.let { p ->
    p.longOrNull ?: p.content.toDoubleOrNull()?.takeIf { it % 1.0 == 0.0 && it >= Long.MIN_VALUE && it <= Long.MAX_VALUE }?.toLong()
}
val J?.bool: Boolean? get() = (this as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.booleanOrNull
val J?.array: List<J>? get() = this as? JsonArray
val J?.obj: Map<String, J>? get() = this as? JsonObject
val J?.isNull: Boolean get() = this == null || this is JsonNull
operator fun J?.get(key: String): J? = (this as? JsonObject)?.get(key)

fun jsonOf(value: String?): J = value?.let(::JsonPrimitive) ?: JsonNull
fun jsonOf(value: Long?): J = value?.let(::JsonPrimitive) ?: JsonNull
fun jsonOf(value: Int?): J = value?.let(::JsonPrimitive) ?: JsonNull
fun jsonOf(value: Boolean?): J = value?.let(::JsonPrimitive) ?: JsonNull
fun jsonArray(values: List<J>): J = JsonArray(values)
fun jsonObject(vararg fields: Pair<String, J>): JsonObject = JsonObject(linkedMapOf(*fields))
fun jsonObject(fields: Map<String, J>): JsonObject = JsonObject(fields)

/** Swift `JSONValue.stringValue` from Models.swift (numbers and booleans read as text). */
val J?.stringValue: String? get() {
    val p = this as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    if (p.isString) return p.content
    p.booleanOrNull?.let { return if (it) "true" else "false" }
    p.longOrNull?.let { return it.toString() }
    return p.content.toDoubleOrNull()?.let { d -> if (d % 1.0 == 0.0) d.toLong().toString() else d.toString() }
}
val J?.stringArrayValue: List<String>? get() = when (this) {
    is JsonArray -> map { it.stringValue }.takeIf { values -> values.all { it != null } }?.map { it!! }
    is JsonPrimitive -> if (isString) listOf(content) else null
    else -> null
}
val J?.boolValue: Boolean? get() {
    val p = this as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    if (p.isString) return when (p.content.lowercase()) { "true", "yes" -> true; "false", "no" -> false; else -> null }
    p.booleanOrNull?.let { return it }
    return p.content.toDoubleOrNull()?.let { it != 0.0 }
}

/** Swift `UUID(uuidString:)`: exactly 8-4-4-4-12 hex digits. `UUID.fromString` alone is lenient. */
fun isUuid(value: String?): Boolean = value != null && value.length == 36 &&
    runCatching { UUID.fromString(value).toString().equals(value, ignoreCase = true) }.getOrDefault(false)

object WireLimits {
    const val maxJSONBytes = 4 * 1024 * 1024
    const val chunkBytes = 8 * 1024
}

/** Port of the Swift `EngineError`. Messages match the iOS app word for word. */
sealed class EngineError(message: String) : Exception(message) {
    object NativeEngineNotLinked : EngineError("The native XMage library is not linked. No remote engine or simulator was substituted.")
    object MessageTooLarge : EngineError("Message exceeds the supported size.")
    class InvalidMessage(val text: String) : EngineError(text)
    class Rejected(val code: String, val text: String) : EngineError(text)
    class RejectionDetails(val code: String, val text: String, val details: J) : EngineError(
        (listOf(text) + (details["issues"].array ?: emptyList()).mapNotNull { issue ->
            val message = issue["message"].string ?: return@mapNotNull null
            val group = issue["group"].string ?: ""
            if (group.isEmpty()) message else "$group: $message"
        }).joinToString("\n"))
    object IncompatibleBuild : EngineError("Players must use the same engine, catalogue, and protocol build.")
    object UnboundPeer : EngineError("This authenticated peer has not been assigned a seat.")
    object ReplayedMessage : EngineError("Duplicate or out-of-order transport message.")
    object HostSuspended : EngineError("The host paused input. Return the host app to the foreground.")
    class RuntimeFailure(val status: Int) : EngineError("Native runtime failed with status $status.")
}

object EngineJson {
    /** Decoding mirrors Swift Codable: unknown keys ignored, missing optionals are null. */
    val format = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true; isLenient = false }
    private val sortedFormat = Json { prettyPrint = false }

    fun validated(value: J, depth: Int = 0) {
        if (depth > 64) throw EngineError.InvalidMessage("JSON nesting limit exceeded")
        when (value) {
            is JsonArray -> value.forEach { validated(it, depth + 1) }
            is JsonObject -> value.values.forEach { validated(it, depth + 1) }
            is JsonPrimitive -> if (!value.isString && value !is JsonNull && value.booleanOrNull == null) {
                val number = value.content.toDoubleOrNull()
                if (number == null || !number.isFinite()) throw EngineError.InvalidMessage("Nonfinite number")
            }
        }
    }

    /** Keys sorted, like the Swift encoder, so equal values encode to equal bytes. */
    fun sorted(value: J): J = when (value) {
        is JsonObject -> JsonObject(value.toSortedMap().mapValues { sorted(it.value) })
        is JsonArray -> JsonArray(value.map(::sorted))
        else -> value
    }

    fun encode(value: J): ByteArray {
        validated(value)
        val data = sortedFormat.encodeToString(J.serializer(), sorted(value)).toByteArray(Charsets.UTF_8)
        if (data.size > WireLimits.maxJSONBytes) throw EngineError.MessageTooLarge
        return data
    }

    fun decode(data: ByteArray): J {
        if (data.isEmpty() || data.size > WireLimits.maxJSONBytes) throw EngineError.MessageTooLarge
        val value = try { format.parseToJsonElement(String(data, Charsets.UTF_8)) }
        catch (error: Exception) { throw EngineError.InvalidMessage("Malformed JSON") }
        validated(value)
        return value
    }
}
