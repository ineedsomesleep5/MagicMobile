package io.magicmobile.android.social

import android.content.Context
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.HowToPlayLaunch
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.game.PlayerFriend
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** The profile for screens that show the player's name (the setup screen's seat). */
val LocalPlayerAccount = compositionLocalOf<PlayerAccount?> { null }

/**
 * The player's instant profile (PlayerAccount.swift): an anonymous Supabase account made on first
 * use, a unique username used at every table, friends with presence, and the table the player
 * hosts. Games never depend on it: offline, the app keeps the typed name and plays as before.
 */
class PlayerAccount(context: Context, private val scope: CoroutineScope) {
    enum class Phase { IDLE, LOADING, READY, UNAVAILABLE }

    var phase by mutableStateOf(Phase.IDLE); private set
    var username by mutableStateOf<String?>(null); private set
    var friends by mutableStateOf<List<PlayerFriend>>(emptyList()); private set
    var blocked by mutableStateOf<List<String>>(emptyList()); private set
    var notice by mutableStateOf<String?>(null)

    /** The code of the table this player hosts while it still has open seats (shared with friends). */
    var hosting: Pair<String, Int>? = null
        set(value) { if (value != field) { field = value; scope.launch { heartbeat() } } }

    private val api = SupabaseLite(context.applicationContext)
    private var heartbeatJob: Job? = null

    val onlineFriendCount: Int get() = friends.count { it.isFriend && it.online }
    val incomingCount: Int get() = friends.count { it.isIncoming }

    /** Signs in (making the anonymous account on first use) and loads the profile. Safe to call often. */
    suspend fun start() {
        if (phase == Phase.LOADING) return
        // UI tests and previews never make accounts on the real server.
        if (HowToPlayLaunch.isAutomated(LaunchEnvironment.values)) { phase = Phase.UNAVAILABLE; notice = PlayerAccountRules.message("offline"); return }
        phase = Phase.LOADING
        try {
            val profile = Json.parseToJsonElement(api.rpc("mm_profile")) as? JsonObject
            username = (profile?.get("username") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
            phase = Phase.READY
            refresh()
        } catch (error: Exception) {
            phase = Phase.UNAVAILABLE
            notice = PlayerAccountRules.message(SupabaseLite.code(error))
        }
    }

    suspend fun claim(name: String): Boolean {
        val trimmed = name.trim()
        if (!PlayerAccountRules.isValidUsername(trimmed)) { notice = PlayerAccountRules.message("invalid_username"); return false }
        return try {
            api.rpc("mm_claim_username", mapOf("p_username" to JsonPrimitive(trimmed)))
            username = trimmed; notice = null
            heartbeat()
            true
        } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)); false }
    }

    suspend fun refresh() {
        if (phase != Phase.READY) return
        try {
            friends = PlayerFriend.decodeList(api.rpc("mm_friends"))
            blocked = (Json.parseToJsonElement(api.rpc("mm_blocked")) as? JsonArray).orEmpty()
                .mapNotNull { ((it as? JsonObject)?.get("username") as? JsonPrimitive)?.contentOrNull }
        } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
    }

    suspend fun addFriend(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        try {
            val result = runCatching { Json.parseToJsonElement(api.rpc("mm_friend_request", mapOf("p_username" to JsonPrimitive(trimmed)))).jsonPrimitive.content }
                .getOrDefault("requested")
            notice = PlayerAccountRules.requestResult(result, trimmed)
            refresh()
        } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
    }

    suspend fun respond(friend: PlayerFriend, accept: Boolean) =
        perform("mm_respond_friend", mapOf("p_requester" to JsonPrimitive(friend.id), "p_accept" to JsonPrimitive(accept)))
    suspend fun remove(friend: PlayerFriend) = perform("mm_remove_friend", mapOf("p_other" to JsonPrimitive(friend.id)))
    suspend fun block(name: String) = perform("mm_block", mapOf("p_username" to JsonPrimitive(name)))
    suspend fun unblock(name: String) = perform("mm_unblock", mapOf("p_username" to JsonPrimitive(name)))

    /** Reports another player's chat message or name to the developer. */
    suspend fun report(name: String, message: String?, context: String) {
        perform("mm_report", mapOf("p_username" to JsonPrimitive(name), "p_message" to (message?.let(::JsonPrimitive) ?: JsonNull),
            "p_context" to JsonPrimitive(context)), refreshAfter = false)
        if (notice == null) notice = "Thanks. $name was reported."
    }

    /** Deletes the account and everything tied to it; a new one is made the next time. */
    suspend fun deleteAccount(): Boolean = try {
        api.rpc("mm_delete_account")
        api.forgetSession()
        username = null; friends = emptyList(); blocked = emptyList(); hosting = null; phase = Phase.IDLE
        true
    } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)); false }

    /** Presence while the app is open: once now, then every 45 seconds, with friends refreshed. */
    fun setForeground(active: Boolean) {
        heartbeatJob?.cancel()
        if (!active) return
        heartbeatJob = scope.launch {
            if (phase != Phase.READY) start()
            while (isActive) { heartbeat(); refresh(); delay(45_000) }
        }
    }

    private suspend fun heartbeat() {
        if (phase != Phase.READY || username == null) return
        val table = hosting
        runCatching {
            api.rpc("mm_heartbeat", mapOf("p_platform" to JsonPrimitive("android"),
                "p_hosting_code" to (table?.first?.let(::JsonPrimitive) ?: JsonNull),
                "p_open_seats" to (table?.second?.let(::JsonPrimitive) ?: JsonNull)))
        }
    }

    private suspend fun perform(function: String, params: Map<String, JsonElement>, refreshAfter: Boolean = true) {
        try {
            api.rpc(function, params); notice = null
            if (refreshAfter) refresh()
        } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
    }
}

/**
 * The few Supabase Auth and PostgREST calls the profile needs (SupabaseLite in PlayerAccount.swift).
 * The session stays in app-private preferences (backups are off). The publishable key is public by design.
 */
internal class SupabaseLite(context: Context) {
    class Failure(val code: String) : Exception(code)
    private data class Session(val access: String, val refresh: String, val expiresAt: Long)

    companion object {
        const val BASE = "https://pbspondpyvrjcnvwhtim.supabase.co"
        const val PUBLISHABLE_KEY = "sb_publishable_V_i-mPM26P8fNLlKAYu2xg_4p-lPHYu"

        /** A server error's code ("username_taken"), "offline", or "error". */
        fun code(error: Throwable): String = when (error) {
            is Failure -> error.code
            is IOException -> "offline"
            else -> "error"
        }

        /** PostgREST's {"message": "username_taken", ...} or Auth's {"error_code": ...}. */
        fun errorCode(body: String): String? = runCatching {
            val fields = Json.parseToJsonElement(body) as JsonObject
            (fields["error_code"] as? JsonPrimitive)?.contentOrNull ?: (fields["message"] as? JsonPrimitive)?.contentOrNull
        }.getOrNull()
    }

    private val prefs = context.getSharedPreferences("magicmobile.account", Context.MODE_PRIVATE)
    private val tokenLock = Mutex()
    private var session: Session? = prefs.getString("access", null)?.let { access ->
        prefs.getString("refresh", null)?.let { refresh -> Session(access, refresh, prefs.getLong("expiresAt", 0)) }
    }

    suspend fun rpc(function: String, params: Map<String, JsonElement> = emptyMap()): String {
        val token = accessToken()
        val (status, body) = post("$BASE/rest/v1/rpc/$function", JsonObject(params).toString(), token)
        if (status == 401) session = session?.copy(expiresAt = 0)
        if (status !in 200..299) throw Failure(errorCode(body) ?: if (status == 401) "not_signed_in" else "error")
        return body
    }

    fun forgetSession() {
        session = null
        prefs.edit().clear().apply()
    }

    /** One sign-in or refresh at a time: two calls at first launch must not make two players. */
    private suspend fun accessToken(): String = tokenLock.withLock {
        session?.takeIf { it.expiresAt > System.currentTimeMillis() + 60_000 }?.let { return@withLock it.access }
        val refresh = session?.refresh
        // No email or password: Supabase makes an anonymous user.
        val (status, body) = if (refresh == null) post("$BASE/auth/v1/signup", """{"data":{}}""", null)
            else post("$BASE/auth/v1/token?grant_type=refresh_token", JsonObject(mapOf("refresh_token" to JsonPrimitive(refresh))).toString(), null)
        val fields = runCatching { Json.parseToJsonElement(body) as JsonObject }.getOrNull()
        val access = (fields?.get("access_token") as? JsonPrimitive)?.contentOrNull
        val newRefresh = (fields?.get("refresh_token") as? JsonPrimitive)?.contentOrNull
        if (status !in 200..299 || access == null || newRefresh == null) {
            // A refresh token that no longer works (deleted account): start over as a new player.
            if (refresh != null && status in 400..499) forgetSession()
            throw Failure(errorCode(body) ?: "error")
        }
        val expiresIn = (fields["expires_in"] as? JsonPrimitive)?.longOrNull ?: 3600
        val next = Session(access, newRefresh, System.currentTimeMillis() + expiresIn * 1000)
        session = next
        prefs.edit().putString("access", next.access).putString("refresh", next.refresh).putLong("expiresAt", next.expiresAt).apply()
        access
    }

    private suspend fun post(url: String, json: String, token: String?): Pair<Int, String> = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"; doOutput = true; connectTimeout = 15_000; readTimeout = 15_000; useCaches = false
            instanceFollowRedirects = false
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("apikey", PUBLISHABLE_KEY)
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
        try {
            connection.outputStream.use { it.write(json.toByteArray()) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            status to (stream?.bufferedReader()?.use { it.readText() } ?: "")
        } finally { connection.disconnect() }
    }
}
