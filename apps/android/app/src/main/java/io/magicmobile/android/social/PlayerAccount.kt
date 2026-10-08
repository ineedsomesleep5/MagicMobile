package io.magicmobile.android.social

import android.content.Context
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.GameUploadResult
import io.magicmobile.android.game.HowToPlayLaunch
import io.magicmobile.android.game.MatchRecord
import io.magicmobile.android.game.PlayerSearchResult
import io.magicmobile.android.game.PlayerSearchRules
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.game.PublicProfile
import io.magicmobile.android.ranked.SocialFixtures
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.game.PlayerFriend
import io.magicmobile.android.game.Achievement
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankedQueueService
import io.magicmobile.android.game.RankedTicket
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
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** What opening another player's profile came to. */
sealed class PublicProfileResult {
    data class Profile(val profile: PublicProfile) : PublicProfileResult()
    /** No such player, or one that blocked you (or whom you blocked): the server says the same for both. */
    object NotFound : PublicProfileResult()
    /** The server doesn't have public profiles yet. */
    object Unavailable : PublicProfileResult()
    data class Failed(val message: String) : PublicProfileResult()
}

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
    /** Friends' ranked standings by username (mm_friend_ranks), for their badges. */
    var friendRanks by mutableStateOf<Map<String, RankPosition>>(emptyMap()); private set
    /** Who may open this player's profile (mm_profile). `visibilityKnown` is false on a server that predates the setting. */
    var visibility by mutableStateOf(ProfileVisibility.PUBLIC); private set
    var visibilityKnown by mutableStateOf(false); private set
    /** False once the server has said it has no player search / public profiles yet: the screens fall back gently. */
    var searchAvailable by mutableStateOf(true); private set
    var profilesAvailable by mutableStateOf(true); private set
    var notice by mutableStateOf<String?>(null)
    /** Google sign-ins on this account; empty while the profile lives only on this phone (anonymous). */
    var linkedIdentities by mutableStateOf<List<LinkedIdentity>>(emptyList()); private set
    var isSigningIn by mutableStateOf(false); private set
    /** Runs after each refresh while the app is open: the app sends games that could not be sent before. */
    var afterRefresh: (suspend () -> Unit)? = null

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
        if (SocialFixtures.isActive) { applyFixtureAccount(); return }
        // UI tests and previews never make accounts on the real server.
        if (HowToPlayLaunch.isAutomated(LaunchEnvironment.values)) { phase = Phase.UNAVAILABLE; notice = PlayerAccountRules.message("offline"); return }
        phase = Phase.LOADING
        try {
            val profile = Json.parseToJsonElement(api.rpc("mm_profile")) as? JsonObject
            username = (profile?.get("username") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
            ProfileVisibility.of((profile?.get("visibility") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull)?.let { visibility = it; visibilityKnown = true }
            phase = Phase.READY
            linkedIdentities = runCatching { api.linkedIdentities() }.getOrDefault(linkedIdentities)
            refresh()
        } catch (error: Exception) {
            phase = Phase.UNAVAILABLE
            notice = PlayerAccountRules.message(SupabaseLite.code(error))
        }
    }

    /**
     * Keeps the profile with a Google account. The first time, the sign-in joins this phone's account, so its name,
     * friends and rank stay. If that Google account already has a profile (another phone), this phone switches to it.
     */
    suspend fun signIn(provider: String, idToken: String, nonce: String?) {
        if (isSigningIn) return
        isSigningIn = true
        try {
            try { api.signIn(idToken, provider, nonce, link = true) }
            catch (error: SupabaseLite.Failure) {
                if (error.code != "identity_already_exists") throw error
                api.signIn(idToken, provider, nonce, link = false)
            }
            phase = Phase.IDLE
            start()
            notice = null
        } catch (error: Exception) {
            notice = PlayerAccountRules.message(SupabaseLite.code(error))
        } finally { isSigningIn = false }
    }

    /** Signs out on this phone. The profile stays on the account; this phone starts a fresh one until the player signs in again. */
    suspend fun signOut() {
        api.forgetSession()
        username = null; friends = emptyList(); blocked = emptyList(); friendRanks = emptyMap(); linkedIdentities = emptyList()
        visibility = ProfileVisibility.PUBLIC; visibilityKnown = false
        phase = Phase.IDLE
        start()
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
        if (phase != Phase.READY || SocialFixtures.isActive) return
        try {
            friends = PlayerFriend.decodeList(api.rpc("mm_friends"))
            blocked = (Json.parseToJsonElement(api.rpc("mm_blocked")) as? JsonArray).orEmpty()
                .mapNotNull { ((it as? JsonObject)?.get("username") as? JsonPrimitive)?.contentOrNull }
        } catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
        // Ranks are extra: a server without them leaves the badges off.
        runCatching {
            val season = RankLadder.season(System.currentTimeMillis())
            friendRanks = (Json.parseToJsonElement(api.rpc("mm_friend_ranks")) as? JsonArray).orEmpty().mapNotNull { row ->
                val o = row as? JsonObject ?: return@mapNotNull null
                val name = (o["username"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                if ((o["season"] as? JsonPrimitive)?.contentOrNull != season) return@mapNotNull null
                val step = (o["rank_step"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: return@mapNotNull null
                name to RankPosition.published(step, (o["pips"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: 0)
            }.toMap()
        }
    }

    /** The ranked queue, once the player has a profile name. */
    val rankedQueue: RankedQueueService? get() = if (phase == Phase.READY && username != null) SupabaseRankedQueue(api) else null
    /** Friend challenges, once the player has a profile name. */
    val challenges: io.magicmobile.android.game.FriendChallengeService? get() =
        if (phase == Phase.READY && username != null) SupabaseFriendChallenges(api) else null

    /** Shares this season's standing with friends. Quiet on failure: ranks still count on the phone. */
    suspend fun publishRank(rank: RankState, title: Achievement?, commander: String?) {
        if (phase != Phase.READY || username == null) return
        runCatching {
            api.rpc("mm_ranked_publish", mapOf("p_season" to JsonPrimitive(rank.season), "p_rank_step" to JsonPrimitive(rank.position.step),
                "p_pips" to JsonPrimitive(rank.position.pips), "p_peak_step" to JsonPrimitive(rank.peak.step), "p_wins" to JsonPrimitive(rank.wins),
                "p_losses" to JsonPrimitive(rank.losses), "p_title" to (title?.title?.let(::JsonPrimitive) ?: JsonNull),
                "p_favorite_commander" to (commander?.let(::JsonPrimitive) ?: JsonNull)))
        }
    }

    /** Another player's public ranked card, or null when they have none or can't be seen. */
    suspend fun profileCard(name: String): PlayerProfileCard? = if (phase != Phase.READY) null else runCatching {
        PlayerProfileCard.parse(Json.parseToJsonElement(api.rpc("mm_profile_card", mapOf("p_username" to JsonPrimitive(name)))) as JsonObject)
    }.getOrNull()

    /**
     * Players whose name starts with `prefix` (at least two letters; the server returns nothing for less). A newer search cancels the
     * older one: callers cancel the coroutine, which rethrows here.
     */
    suspend fun search(prefix: String): List<PlayerSearchResult> {
        val text = PlayerSearchRules.normalized(prefix)
        if (phase != Phase.READY || text == null) return emptyList()
        if (SocialFixtures.isActive) return SocialFixtures.search(text, friends)
        try {
            val results = PlayerSearchResult.parse(api.rpc("mm_search_players", mapOf("p_prefix" to JsonPrimitive(text))))
            searchAvailable = true
            return results
        } catch (error: kotlinx.coroutines.CancellationException) { throw error
        } catch (error: Exception) {
            if (SupabaseLite.code(error) == "feature_unavailable") searchAvailable = false
            throw error
        }
    }

    /** Another player's profile (or your own, as others see it). */
    suspend fun publicProfile(name: String): PublicProfileResult {
        if (phase != Phase.READY) return PublicProfileResult.Failed(PlayerAccountRules.message("offline"))
        if (SocialFixtures.isActive) return SocialFixtures.publicProfile(name, friends, username)
        return try {
            val profile = PublicProfile.parse(api.rpc("mm_public_profile", mapOf("p_username" to JsonPrimitive(name))))
            profilesAvailable = true
            PublicProfileResult.Profile(profile)
        } catch (error: kotlinx.coroutines.CancellationException) { throw error
        } catch (error: Exception) {
            when (val code = SupabaseLite.code(error)) {
                "feature_unavailable" -> { profilesAvailable = false; PublicProfileResult.Unavailable }
                "not_found" -> PublicProfileResult.NotFound
                else -> PublicProfileResult.Failed(PlayerAccountRules.message(code))
            }
        }
    }

    /** Who may open this player's profile. Quiet about a server that doesn't have the setting yet. */
    suspend fun setVisibility(next: ProfileVisibility): Boolean {
        if (SocialFixtures.isActive) { visibility = next; visibilityKnown = true; return true }
        if (phase != Phase.READY || username == null) return false
        return try {
            api.rpc("mm_set_visibility", mapOf("p_visibility" to JsonPrimitive(next.raw)))
            visibility = next; visibilityKnown = true; notice = null
            true
        } catch (error: kotlinx.coroutines.CancellationException) { throw error
        } catch (error: Exception) {
            val code = SupabaseLite.code(error)
            if (code == "feature_unavailable") visibilityKnown = false
            notice = PlayerAccountRules.message(code)
            false
        }
    }

    /** Sends one finished game. Never throws: the caller keeps what could not be sent and tries again later. */
    suspend fun recordGame(match: MatchRecord): GameUploadResult {
        if (phase != Phase.READY || username == null) return GameUploadResult.UNAVAILABLE
        if (SocialFixtures.isActive) return GameUploadResult.SENT
        val params = HashMap<String, JsonElement>()
        params["p_client_id"] = JsonPrimitive(match.id)
        params["p_played_at"] = JsonPrimitive(java.time.Instant.ofEpochMilli(match.date).toString())
        params["p_mode"] = JsonPrimitive(match.mode.raw)
        params["p_result"] = JsonPrimitive(match.outcome.raw)
        params["p_deck_name"] = JsonPrimitive(match.deckName.take(80))
        params["p_commanders"] = JsonArray(listOfNotNull(match.commander?.take(160)?.let(::JsonPrimitive)))
        params["p_colors"] = JsonArray(match.colors.map(::JsonPrimitive))
        params["p_opponents"] = JsonArray(match.opponents.take(3).map { opponent ->
            JsonObject(mapOf("name" to JsonPrimitive(opponent.name.take(60)), "commander" to (opponent.commander?.take(160)?.let(::JsonPrimitive) ?: JsonNull),
                "ai" to JsonPrimitive(opponent.isAI)))
        })
        if (match.turns > 0) params["p_turns"] = JsonPrimitive(minOf(1000, match.turns))
        match.rankChange?.let { params["p_rank_points"] = JsonPrimitive(it.after.points) }
        return try {
            api.rpc("mm_record_game", params)
            GameUploadResult.SENT
        } catch (error: kotlinx.coroutines.CancellationException) { throw error
        } catch (error: Exception) {
            when (SupabaseLite.code(error)) {
                "feature_unavailable", "no_username" -> GameUploadResult.UNAVAILABLE
                "invalid_game" -> GameUploadResult.REJECTED
                else -> GameUploadResult.RETRY_LATER
            }
        }
    }

    /** Development fixtures (SocialFixtures): a signed-in account with friends, instead of the server. */
    private fun applyFixtureAccount() {
        phase = Phase.READY
        username = SocialFixtures.OWN_NAME
        friends = SocialFixtures.startingFriends()
        friendRanks = friends.mapNotNull { friend -> SocialFixtures.rank(friend.username)?.let { friend.username to it } }.toMap()
        visibilityKnown = true
    }

    /** The friend actions on the fixture: they change the local list the way the server would. */
    private fun fixturePerform(function: String, params: Map<String, JsonElement>) {
        fun text(key: String) = (params[key] as? JsonPrimitive)?.contentOrNull
        when (function) {
            "mm_respond_friend" -> {
                val id = text("p_requester") ?: return
                friends = if ((params["p_accept"] as? JsonPrimitive)?.booleanOrNull == true) friends.map { if (it.id == id) it.copy(relation = "friend") else it } else friends.filter { it.id != id }
            }
            "mm_remove_friend" -> friends = friends.filter { it.id != text("p_other") }
            "mm_block" -> text("p_username")?.let { name -> friends = friends.filter { it.username != name }; if (name !in blocked) blocked = blocked + name }
            "mm_unblock" -> text("p_username")?.let { name -> blocked = blocked.filter { it != name } }
        }
    }

    suspend fun addFriend(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        if (SocialFixtures.isActive) {
            if (friends.none { it.username == trimmed }) friends = friends + PlayerFriend(java.util.UUID.randomUUID().toString(), trimmed, "outgoing", false, null, null, null, null)
            notice = PlayerAccountRules.requestResult("requested", trimmed)
            return
        }
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
            while (isActive) { heartbeat(); refresh(); runCatching { afterRefresh?.invoke() }; delay(45_000) }
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
        if (SocialFixtures.isActive) { fixturePerform(function, params); return }
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
            // A function the server doesn't have yet (PostgREST PGRST202, or Postgres 42883): the feature isn't there.
            if ((fields["code"] as? JsonPrimitive)?.contentOrNull in setOf("PGRST202", "42883")) "feature_unavailable"
            else (fields["error_code"] as? JsonPrimitive)?.contentOrNull ?: (fields["message"] as? JsonPrimitive)?.contentOrNull
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
        if (status !in 200..299) throw Failure(errorCode(body) ?: if (status == 401) "not_signed_in" else if (status == 404) "feature_unavailable" else "error")
        return body
    }

    /**
     * Google sign-in from Credential Manager (an OpenID Connect ID token). With [link], the identity joins the current
     * (anonymous) account so its profile, friends and rank stay; without it, this phone switches to the account that
     * already has that identity. [nonce] is the raw value whose SHA-256 the provider put in the token.
     */
    suspend fun signIn(idToken: String, provider: String, nonce: String?, link: Boolean) {
        val body = buildMap<String, JsonElement> {
            put("provider", JsonPrimitive(provider)); put("id_token", JsonPrimitive(idToken))
            nonce?.let { put("nonce", JsonPrimitive(it)) }
            if (link) put("link_identity", JsonPrimitive(true))
        }
        val (status, text) = post("$BASE/auth/v1/token?grant_type=id_token", JsonObject(body).toString(), if (link) accessToken() else null)
        val fields = runCatching { Json.parseToJsonElement(text) as JsonObject }.getOrNull()
        val access = (fields?.get("access_token") as? JsonPrimitive)?.contentOrNull
        val refresh = (fields?.get("refresh_token") as? JsonPrimitive)?.contentOrNull
        if (status !in 200..299 || access == null || refresh == null) throw Failure(errorCode(text) ?: "error")
        val expiresIn = (fields["expires_in"] as? JsonPrimitive)?.longOrNull ?: 3600
        tokenLock.withLock {
            val next = Session(access, refresh, System.currentTimeMillis() + expiresIn * 1000)
            session = next
            prefs.edit().putString("access", next.access).putString("refresh", next.refresh).putLong("expiresAt", next.expiresAt).apply()
        }
    }

    /** The sign-in methods on this account beyond its anonymous start ("google", "apple"), with their email. */
    suspend fun linkedIdentities(): List<LinkedIdentity> {
        val token = accessToken()
        val (status, text) = withContext(Dispatchers.IO) {
            val connection = (URL("$BASE/auth/v1/user").openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000; readTimeout = 15_000; useCaches = false; instanceFollowRedirects = false
                setRequestProperty("apikey", PUBLISHABLE_KEY); setRequestProperty("Authorization", "Bearer $token")
            }
            try {
                val code = connection.responseCode
                code to ((if (code in 200..299) connection.inputStream else connection.errorStream)?.bufferedReader()?.use { it.readText() } ?: "")
            } finally { connection.disconnect() }
        }
        if (status != 200) throw Failure(errorCode(text) ?: "error")
        return LinkedIdentity.parse(Json.parseToJsonElement(text) as JsonObject)
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

/** A sign-in method on the account (Google, Apple), from Auth's user record (LinkedIdentity in PlayerAccount.swift). */
data class LinkedIdentity(val provider: String, val email: String?) {
    val title: String get() = when (provider) { "apple" -> "Apple"; "google" -> "Google"; else -> provider.replaceFirstChar { it.uppercase() } }

    companion object {
        /** Auth's `identities`, without the anonymous one. */
        fun parse(user: JsonObject): List<LinkedIdentity> = (user["identities"] as? JsonArray).orEmpty().mapNotNull { item ->
            val identity = item as? JsonObject ?: return@mapNotNull null
            val provider = (identity["provider"] as? JsonPrimitive)?.contentOrNull?.takeIf { it != "anonymous" } ?: return@mapNotNull null
            fun email(o: JsonObject?) = (o?.get("email") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
            LinkedIdentity(provider, email(identity["identity_data"] as? JsonObject) ?: email(identity))
        }
    }
}

/** Another player's public ranked card (mm_profile_card). */
data class PlayerProfileCard(val username: String, val season: String?, val rankStep: Int?, val pips: Int?, val peakStep: Int?,
                             val wins: Int?, val losses: Int?, val title: String?, val favoriteCommander: String?) {
    /** This season's place, or null when unranked or from an earlier season. */
    val position: RankPosition? get() =
        if (rankStep == null || season != RankLadder.season(System.currentTimeMillis())) null else RankPosition.published(rankStep, pips ?: 0)

    companion object {
        fun parse(o: JsonObject): PlayerProfileCard {
            fun s(key: String) = (o[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
            return PlayerProfileCard(s("username") ?: "", s("season"), s("rankStep")?.toIntOrNull(), s("pips")?.toIntOrNull(),
                s("peakStep")?.toIntOrNull(), s("wins")?.toIntOrNull(), s("losses")?.toIntOrNull(), s("title"), s("favoriteCommander"))
        }
    }
}

/** The ranked queue on the profile server (supabase/migrations/20261004120000_ranked_ladder.sql). */
internal class SupabaseRankedQueue(private val api: SupabaseLite) : RankedQueueService {
    private fun decode(text: String) = RankedTicket.parse(Json.parseToJsonElement(text) as JsonObject)
    override suspend fun enqueue(protocol: String, rankStep: Int, deckBracket: Int) = decode(api.rpc("mm_ranked_enqueue",
        mapOf("p_protocol" to JsonPrimitive(protocol), "p_rank_step" to JsonPrimitive(rankStep), "p_deck_bracket" to JsonPrimitive(deckBracket))))
    override suspend fun poll(ticket: String) = decode(api.rpc("mm_ranked_poll", mapOf("p_ticket" to JsonPrimitive(ticket))))
    override suspend fun cancel(ticket: String) = decode(api.rpc("mm_ranked_cancel", mapOf("p_ticket" to JsonPrimitive(ticket))))
    override suspend fun setTable(match: String, code: String) {
        api.rpc("mm_ranked_set_table", mapOf("p_match" to JsonPrimitive(match), "p_code" to JsonPrimitive(code)))
    }
    override suspend fun report(match: String, outcome: RankOutcome) {
        api.rpc("mm_ranked_report", mapOf("p_match" to JsonPrimitive(match), "p_result" to JsonPrimitive(outcome.raw)))
    }
}

/** Friend challenges on the profile server (supabase/migrations/20261004180000_friend_challenges.sql). */
internal class SupabaseFriendChallenges(private val api: SupabaseLite) : io.magicmobile.android.game.FriendChallengeService {
    private fun decode(text: String, id: String? = null) = io.magicmobile.android.game.FriendChallenge.parse(
        Json.parseToJsonElement(text) as? JsonObject ?: JsonObject(emptyMap()), id)
    override suspend fun send(username: String, mode: io.magicmobile.android.game.PlayMode, protocol: String, rankStep: Int, tableCode: String) =
        decode(api.rpc("mm_challenge_send", mapOf("p_username" to JsonPrimitive(username), "p_mode" to JsonPrimitive(mode.raw),
            "p_protocol" to JsonPrimitive(protocol), "p_rank_step" to JsonPrimitive(rankStep), "p_table_code" to JsonPrimitive(tableCode))))
    override suspend fun incoming() = (Json.parseToJsonElement(api.rpc("mm_challenge_incoming")) as? JsonArray).orEmpty()
        .mapNotNull { row -> (row as? JsonObject)?.let { runCatching { io.magicmobile.android.game.FriendChallenge.parse(it) }.getOrNull() } }
    override suspend fun status(id: String) = decode(api.rpc("mm_challenge_status", mapOf("p_challenge" to JsonPrimitive(id))), id)
    override suspend fun accept(id: String, protocol: String, rankStep: Int) = decode(api.rpc("mm_challenge_accept",
        mapOf("p_challenge" to JsonPrimitive(id), "p_protocol" to JsonPrimitive(protocol), "p_rank_step" to JsonPrimitive(rankStep))))
    override suspend fun decline(id: String) { api.rpc("mm_challenge_decline", mapOf("p_challenge" to JsonPrimitive(id))) }
    override suspend fun cancel(id: String) = decode(api.rpc("mm_challenge_cancel", mapOf("p_challenge" to JsonPrimitive(id))), id)
}
