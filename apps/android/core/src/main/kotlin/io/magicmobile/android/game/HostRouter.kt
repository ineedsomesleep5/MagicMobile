package io.magicmobile.android.game

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.Base64
import java.util.UUID

/** Port of MagicMobileOnDevice/HostRouter.swift and PacketChunks.swift. Wire formats match Swift Codable. */
data class BuildIdentity(val upstreamCommit: String, val catalogueHash: String, val adapterVersion: String = "ondevice-0.1") {
    val protocolVersion: Int = 1
    val json: J get() = jsonObject("protocolVersion" to JsonPrimitive(protocolVersion.toLong()),
        "upstreamCommit" to JsonPrimitive(upstreamCommit), "catalogueHash" to JsonPrimitive(catalogueHash),
        "adapterVersion" to JsonPrimitive(adapterVersion))
}

/** Swift encodes `epoch` as an uppercase UUID string and `sequence` as a number. */
data class PeerFrame(val epoch: UUID, val sequence: Long, val operation: String, val payload: J) {
    fun json(): J = jsonObject("epoch" to JsonPrimitive(epoch.toString().uppercase()), "sequence" to JsonPrimitive(sequence),
        "operation" to JsonPrimitive(operation), "payload" to payload)

    companion object {
        fun parse(value: J): PeerFrame {
            val epoch = value["epoch"].string?.takeIf(::isUuid)?.let(UUID::fromString)
            val sequence = value["sequence"].integer
            val operation = value["operation"].string
            val payload = value["payload"]
            if (epoch == null || sequence == null || sequence < 0 || operation == null || payload == null) {
                throw EngineError.InvalidMessage("Malformed peer frame")
            }
            return PeerFrame(epoch, sequence, operation, payload)
        }
    }
}

/**
 * Only the HOST constructs this router. The authenticated peer ID is an out-of-band
 * argument (GameKit player ID or relay-assigned connection ID), never a value read from
 * a peer-supplied JSON field. A peer can poll, answer and concede only as its own seat.
 */
class HostRouter(private val engine: EngineClient, private val matchID: String, private val identity: BuildIdentity,
                 val epoch: UUID = UUID.randomUUID()) {
    private data class Binding(val seat: String, var ready: Boolean = false, var lastSequence: Long = 0)
    private val lock = Mutex()
    private val peers = HashMap<String, Binding>()
    private var suspended = false
    private var suspensionRevision = 0L

    suspend fun bind(authenticatedPeerID: String, seatID: String) = lock.withLock {
        if (authenticatedPeerID.isEmpty() || seatID.isEmpty() || peers.size >= 3 || peers.containsKey(authenticatedPeerID) ||
            peers.values.any { it.seat == seatID }) throw EngineError.InvalidMessage("Duplicate/invalid peer binding or a full match")
        peers[authenticatedPeerID] = Binding(seatID)
    }

    suspend fun setSuspended(value: Boolean) = lock.withLock { suspended = value }
    suspend fun setSuspended(value: Boolean, revision: Long) = lock.withLock {
        if (revision > suspensionRevision) { suspensionRevision = revision; suspended = value }
    }

    suspend fun handle(frame: PeerFrame, authenticatedPeerID: String): J {
        val binding = lock.withLock {
            val current = peers[authenticatedPeerID] ?: throw EngineError.UnboundPeer
            if (frame.epoch != epoch) throw EngineError.IncompatibleBuild
            if (frame.sequence <= current.lastSequence) throw EngineError.ReplayedMessage
            EngineJson.validated(frame.payload)
            // Advance before awaiting the engine so concurrent requests cannot reuse a sequence.
            current.lastSequence = frame.sequence
            if (frame.operation == "hello") {
                if (frame.payload != identity.json) throw EngineError.IncompatibleBuild
                current.ready = true
                return jsonObject("seatId" to JsonPrimitive(current.seat), "build" to identity.json)
            }
            if (!current.ready) throw EngineError.IncompatibleBuild
            current.copy()
        }
        val seat = JsonPrimitive(binding.seat)
        val match = JsonPrimitive(matchID)
        return when (frame.operation) {
            "poll" -> {
                val p = frame.payload.obj
                val after = p?.get("after").integer
                if (p == null || p.keys != setOf("after") || after == null) throw EngineError.InvalidMessage("Invalid poll payload")
                engine.poll(matchID, binding.seat, after).raw
            }
            "respond" -> {
                if (lock.withLock { suspended }) throw EngineError.HostSuspended
                val p = frame.payload.obj
                if (p == null || p.keys != setOf("requestId", "promptId", "promptRevision", "answer")) throw EngineError.InvalidMessage("Invalid answer payload")
                engine.call("respond", mapOf("matchId" to match, "viewerId" to seat, "command" to frame.payload))
            }
            "concede" -> {
                // Always allowed, even while suspended: a peer may only concede its own bound seat.
                if (frame.payload != JsonObject(emptyMap())) throw EngineError.InvalidMessage("Invalid concede payload")
                engine.call("concede", mapOf("matchId" to match, "viewerId" to seat))
            }
            else -> throw EngineError.InvalidMessage("Remote operation not allowed")
        }
    }
}

/** Swift `PacketChunk` Codable: `bytes` is base64 (Foundation's Data encoding) and `id` an uppercase UUID. */
data class PacketChunk(val id: UUID, val index: Int, val count: Int, val totalBytes: Int, val bytes: ByteArray) {
    fun json(): J = jsonObject("id" to JsonPrimitive(id.toString().uppercase()), "index" to JsonPrimitive(index),
        "count" to JsonPrimitive(count), "totalBytes" to JsonPrimitive(totalBytes),
        "bytes" to JsonPrimitive(Base64.getEncoder().encodeToString(bytes)))

    override fun equals(other: Any?): Boolean = other is PacketChunk && other.id == id && other.index == index &&
        other.count == count && other.totalBytes == totalBytes && other.bytes.contentEquals(bytes)
    override fun hashCode(): Int = id.hashCode() * 31 + index

    companion object {
        fun split(data: ByteArray, id: UUID = UUID.randomUUID()): List<PacketChunk> {
            if (data.isEmpty() || data.size > WireLimits.maxJSONBytes) throw EngineError.MessageTooLarge
            val count = (data.size + WireLimits.chunkBytes - 1) / WireLimits.chunkBytes
            return (0 until count).map { i ->
                val start = i * WireLimits.chunkBytes
                val end = minOf(data.size, (i + 1) * WireLimits.chunkBytes)
                PacketChunk(id, i, count, data.size, data.copyOfRange(start, end))
            }
        }

        fun parse(value: J): PacketChunk {
            val id = value["id"].string?.takeIf(::isUuid)?.let(UUID::fromString)
            val index = value["index"].integer
            val count = value["count"].integer
            val total = value["totalBytes"].integer
            val bytes = value["bytes"].string?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }
            if (id == null || index == null || count == null || total == null || bytes == null ||
                index !in 0..Int.MAX_VALUE || count !in 0..Int.MAX_VALUE || total !in 0..Int.MAX_VALUE) {
                throw EngineError.InvalidMessage("Invalid chunk metadata")
            }
            return PacketChunk(id, index.toInt(), count.toInt(), total.toInt(), bytes)
        }
    }
}

/** Bounded, per-authenticated-peer assembly. Safe for out-of-order reliable packets. */
class PacketAssembler {
    private data class Key(val peer: String, val id: UUID)
    private class Assembly(val count: Int, val total: Int, val started: Double) { val pieces = HashMap<Int, ByteArray>() }
    private val lock = Mutex()
    private var pending = HashMap<Key, Assembly>()

    suspend fun receive(c: PacketChunk, peer: String, now: Double = System.currentTimeMillis() / 1000.0): ByteArray? = lock.withLock {
        if (peer.isEmpty()) throw EngineError.UnboundPeer
        pending = HashMap(pending.filter { now - it.value.started < 15 })
        if (c.totalBytes <= 0 || c.totalBytes > WireLimits.maxJSONBytes || c.index < 0 ||
            c.count != (c.totalBytes + WireLimits.chunkBytes - 1) / WireLimits.chunkBytes || c.index >= c.count) {
            throw EngineError.InvalidMessage("Invalid chunk metadata")
        }
        val expected = if (c.index == c.count - 1) c.totalBytes - (c.count - 1) * WireLimits.chunkBytes else WireLimits.chunkBytes
        if (c.bytes.size != expected) throw EngineError.InvalidMessage("Invalid chunk length")
        val key = Key(peer, c.id)
        if (pending[key] == null) {
            if (pending.size >= 12 || pending.keys.count { it.peer == peer } >= 4 ||
                pending.values.sumOf { it.total } + c.totalBytes > 16 * 1024 * 1024) throw EngineError.MessageTooLarge
            pending[key] = Assembly(c.count, c.totalBytes, now)
        }
        val a = pending[key]!!
        if (a.total != c.totalBytes || a.count != c.count) throw EngineError.InvalidMessage("Conflicting chunk header")
        a.pieces[c.index]?.let { existing -> if (!existing.contentEquals(c.bytes)) throw EngineError.InvalidMessage("Conflicting duplicate chunk") }
        a.pieces[c.index] = c.bytes
        if (a.pieces.size != a.count) return@withLock null
        val data = ByteArray(a.total)
        var offset = 0
        for (i in 0 until a.count) {
            val part = a.pieces[i] ?: return@withLock null
            part.copyInto(data, offset); offset += part.size
        }
        pending.remove(key)
        data
    }

    suspend fun drop(peer: String) = lock.withLock { pending = HashMap(pending.filter { it.key.peer != peer }) }
    suspend fun pendingCount(): Int = lock.withLock { pending.size }
}

internal val JsonNullValue: J = JsonNull
