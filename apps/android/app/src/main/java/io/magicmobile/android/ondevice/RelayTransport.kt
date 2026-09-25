package io.magicmobile.android.ondevice

import android.os.Handler
import android.os.Looper
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import io.magicmobile.android.ui.LaunchEnvironment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.TimeUnit

/** One seat at a relay table as the relay reports it. */
data class RelayPeer(val id: String, val name: String, val connected: Boolean)

/**
 * The cross-play relay (services/table-relay): the same role GameKitTransport plays for Game
 * Center. The relay assigns this phone's peer ID and stamps every delivered packet with its
 * sender's ID; that is the only sender identity this transport ever reports.
 */
class RelayTransport(private val baseURL: String = defaultURL) {
    var onPacket: ((ByteArray, String) -> Unit)? = null
    var onRoster: ((List<RelayPeer>, Boolean) -> Unit)? = null
    /** A player left for good (or never came back): the match cannot continue. */
    var onDisconnect: ((String) -> Unit)? = null
    var onError: ((String) -> Unit)? = null
    /** This phone lost the relay and is trying to reclaim its seat. */
    var onConnectionChanged: ((Boolean) -> Unit)? = null

    var localPeerID: String? = null; private set
    var code: String? = null; private set
    var peers: List<RelayPeer> = emptyList(); private set
    var isFull = false; private set
    /** Human seats at this table, from the relay's welcome. */
    var seats = 0; private set

    private val main = Handler(Looper.getMainLooper())
    private var socket: WebSocket? = null
    private var name = "Player"
    private var token: String? = null
    private var closed = false
    private var generation = 0
    private var reconnectAttempts = 0
    private val parts = HashMap<String, Array<String?>>()
    /** Frames written while the socket reconnects; sent in order once the relay returns the seat. */
    private val outbox = ArrayList<String>()
    private var outboxChars = 0
    private var welcomed = false

    /** Creates a table on the relay and returns its code and the host key only this phone holds. */
    suspend fun createTable(seats: Int): Pair<String, String> = withContext(Dispatchers.IO) {
        val body = """{"seats":$seats}""".toRequestBody("application/json".toMediaType())
        val response = try { client.newCall(Request.Builder().url("$baseURL/v1/tables").post(body).build()).execute() }
            catch (error: java.io.IOException) { throw EngineError.InvalidMessage("Could not reach the table service. Check your connection and try again.") }
        response.use {
            val value = runCatching { Json.parseToJsonElement(it.body?.string().orEmpty()) }.getOrNull()
            val code = value["code"].string; val key = value["hostKey"].string
            if (!it.isSuccessful || code == null || key == null) {
                throw EngineError.InvalidMessage(value["message"].string ?: "The table service could not open a table. Try again.")
            }
            code to key
        }
    }

    /** Opens the table's socket: the creator passes its host key, guests only the code. */
    fun connect(code: String, name: String, hostKey: String? = null) {
        this.code = code.uppercase(); this.name = name
        open(hostKey = hostKey, resume = null)
    }

    private fun open(hostKey: String?, resume: String?) {
        val code = code ?: return
        val current = ++generation
        val query = buildList {
            add("name=" + URLEncoder.encode(name, "UTF-8"))
            hostKey?.let { add("key=" + URLEncoder.encode(it, "UTF-8")) }
            resume?.let { add("resume=" + URLEncoder.encode(it, "UTF-8")) }
        }.joinToString("&")
        val url = baseURL.replaceFirst("http", "ws") + "/v1/tables/$code/socket?$query"
        socket = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                main.post { if (current == generation && !closed) receive(text) }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { if (current == generation) dropped(code) }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.post { if (current == generation) dropped(null) }
            }
        })
    }

    private fun receive(text: String) {
        val frame = runCatching { Json.parseToJsonElement(text) }.getOrNull()?.obj ?: return
        when (frame["t"].string) {
            "welcome" -> {
                welcomed = true
                localPeerID = frame["you"].string; token = frame["token"].string
                seats = frame["seats"].integer?.toInt() ?: seats
                reconnectAttempts = 0
                val queued = outbox.toList()
                outbox.clear(); outboxChars = 0
                queued.forEach { socket?.send(it) }
                updateRoster(frame["peers"], frame["full"].bool == true)
                onConnectionChanged?.invoke(true)
            }
            "roster" -> updateRoster(frame["peers"], frame["full"].bool == true)
            "msg" -> {
                val from = frame["from"].string ?: return
                val data = frame["d"].string ?: return
                val part = frame["p"].obj
                if (part == null) { onPacket?.invoke(data.toByteArray(Charsets.UTF_8), from); return }
                val id = part["id"].string ?: return
                val index = part["i"].integer?.toInt() ?: return
                val count = part["n"].integer?.toInt() ?: return
                if (count !in 1..64 || index !in 0 until count) return
                val key = "$from/$id"
                val pieces = parts.getOrPut(key) { arrayOfNulls(count) }
                if (pieces.size != count) { parts.remove(key); return }
                pieces[index] = data
                if (pieces.all { it != null }) {
                    parts.remove(key)
                    onPacket?.invoke(pieces.joinToString("") { it!! }.toByteArray(Charsets.UTF_8), from)
                }
            }
            "gone" -> frame["id"].string?.let { onDisconnect?.invoke(it) }
            "error" -> {
                closed = true
                onError?.invoke(frame["message"].string ?: "The table service closed the connection.")
            }
        }
    }

    private fun updateRoster(value: J?, full: Boolean) {
        peers = value.array?.mapNotNull { row ->
            val id = row["id"].string ?: return@mapNotNull null
            RelayPeer(id, row["name"].string ?: "Player", row["connected"].bool == true)
        } ?: peers
        isFull = full
        onRoster?.invoke(peers, full)
    }

    /** A dropped socket reclaims the seat with its resume token, with backoff, for about a minute. */
    private fun dropped(code: Int?) {
        socket = null; welcomed = false
        if (closed) return
        val resume = token
        if (resume == null || code == 4400) { closed = true; onError?.invoke("Could not connect to the table."); return }
        onConnectionChanged?.invoke(false)
        if (reconnectAttempts >= 12) { closed = true; onError?.invoke("Lost the connection to the table."); return }
        val delay = minOf(8_000L, 500L shl minOf(reconnectAttempts, 4))
        reconnectAttempts += 1
        main.postDelayed({ if (!closed && socket == null) open(hostKey = null, resume = resume) }, delay)
    }

    fun send(data: ByteArray, peer: String) {
        if (closed) throw EngineError.InvalidMessage("The table connection is closed.")
        val text = String(data, Charsets.UTF_8)
        if (text.length <= partChars) {
            write(frame(peer, text, null))
            return
        }
        // Never split a surrogate pair: iOS rejects a string holding half of one.
        val pieces = ArrayList<String>()
        var start = 0
        while (start < text.length) {
            var end = minOf(text.length, start + partChars)
            if (end < text.length && text[end - 1].isHighSurrogate()) end -= 1
            pieces += text.substring(start, end)
            start = end
        }
        if (pieces.size > 64) throw EngineError.MessageTooLarge
        val id = UUID.randomUUID().toString()
        pieces.forEachIndexed { index, piece ->
            write(frame(peer, piece, JsonObject(mapOf("id" to JsonPrimitive(id), "i" to JsonPrimitive(index), "n" to JsonPrimitive(pieces.size)))))
        }
    }

    /** Sends now, or holds the frame until the relay returns this phone's seat. */
    private fun write(frame: String) {
        val socket = socket
        if (socket != null && welcomed) { socket.send(frame); return }
        if (outbox.size >= 512 || outboxChars + frame.length > 8_000_000) {
            throw EngineError.InvalidMessage("Lost the connection to the table.")
        }
        outbox += frame; outboxChars += frame.length
    }

    private fun frame(peer: String, text: String, part: JsonObject?): String =
        JsonObject(buildMap {
            put("t", JsonPrimitive("send")); put("to", JsonPrimitive(peer)); put("d", JsonPrimitive(text))
            part?.let { put("p", it) }
        }).toString()

    /** Leaves the table for good; the other phones are told at once. */
    fun disconnect() {
        if (closed && socket == null) return
        closed = true
        generation += 1
        socket?.let { it.send("""{"t":"bye"}"""); it.close(1000, "bye") }
        socket = null; welcomed = false; outbox.clear(); outboxChars = 0
        onPacket = null; onRoster = null; onDisconnect = null; onError = null; onConnectionChanged = null
    }

    companion object {
        /** Frames stay well under the relay's 1,000,000-character limit after JSON escaping. */
        private const val partChars = 400_000
        private val client = OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).connectTimeout(15, TimeUnit.SECONDS).build()

        /** Debug builds may point at a local `wrangler dev` (MAGICMOBILE_RELAY_URL). */
        val defaultURL: String get() = LaunchEnvironment["MAGICMOBILE_RELAY_URL"]?.takeIf { BuildConfig.DEBUG }?.trimEnd('/')
            ?: BuildConfig.RELAY_URL
    }
}
