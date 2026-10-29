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
    /** Unread messages from friends: the badge on the Friends button. */
    var unreadMessages by mutableStateOf(0); private set
    /** False on a server without friend messages yet. */
    var messagesAvailable by mutableStateOf(true); private set
    /** The fixture account's conversations, changed as the player sends. */
    private var fixtureMessages: Map<String, List<io.magicmobile.android.game.FriendMessage>> = emptyMap()
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

    /**
     * The profile is reachable but has no name yet: the app asks for one before the menus (menus/NameGate.kt). False
     * offline, while loading and with the profile server unavailable, so a player is never locked out of playing.
     */
    val needsName: Boolean get() = phase == Phase.READY && username == null
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
        username = null; friends = emptyList(); blocked = emptyList(); friendRanks = emptyMap(); linkedIdentities = emptyList(); unreadMessages = 0
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
        // Messages are extra too: a server without them leaves the badge off.
        runCatching { unreadMessages = api.rpc("mm_message_unread").trim().toInt() }
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
    /** Deck sync's server functions (docs/DECK_SYNC.md). */
    internal val deckSyncAPI: io.magicmobile.android.studio.DeckSyncAPI get() = SupabaseDeckSync(api)
    /** Card picture sync's server calls (docs/CARD_ART_SYNC.md). */
    internal val cardArtSyncAPI: io.magicmobile.android.studio.CardArtSyncAPI get() = SupabaseCardArtSync(api)

    /** The signed-in profile's id (the access token's `sub`) for deck sync; null until the profile is ready, and in fixtures and UI tests. */
    suspend fun profileID(): String? {
        if (phase != Phase.READY || SocialFixtures.isActive || HowToPlayLaunch.isAutomated(LaunchEnvironment.values)) return null
        return runCatching { api.userID() }.getOrNull()
    }

    /** Friend challenges, once the player has a profile name. */
    val challenges: io.magicmobile.android.game.FriendChallengeService? get() =
        if (phase == Phase.READY && username != null) SupabaseFriendChallenges(api) else null

    /**
     * Starts a ranked game against the AI on the server (mm_ranked_ai_start2), so its result counts there, with the seed the
     * engine deals it with. Null offline or without a profile name: that game then counts on this phone only. Waits at most
     * [timeoutMillis], since the game waits for it.
     */
    suspend fun startRankedAIGame(deckBracket: Int, timeoutMillis: Long = 4_000): io.magicmobile.android.game.RankedAITicket? {
        if (phase != Phase.READY || username == null) return null
        return kotlinx.coroutines.withTimeoutOrNull(timeoutMillis) {
            runCatching { api.rpc("mm_ranked_ai_start2", mapOf("p_deck_bracket" to JsonPrimitive(deckBracket))) }.getOrNull()
                ?.let(io.magicmobile.android.game.RankedAITicket::parse)
        }
    }

    /**
     * Sends finished ranked AI games, then takes the server's standing (seeding it once from this phone when the server
     * has none yet). Quiet on failure: the phone's own count stands until the next try.
     */
    suspend fun syncRank(record: io.magicmobile.android.ranked.PlayerRecordStore) {
        if (phase != Phase.READY || username == null) return
        fun parse(text: String) = runCatching { io.magicmobile.android.game.RankedStanding.parse(Json.parseToJsonElement(text) as JsonObject) }.getOrNull()
        for (pending in record.file.pendingRankedResults) {
            // A record kept on this phone but unreadable for now waits for the next sync rather than going without it.
            if (pending.seeded && pending.recordFile?.let { record.gameRecordIsKept(it) && record.gameRecord(it) == null } == true) continue
            try {
                val text = if (pending.seeded) {
                    // The game record backs the result; without one a win settles as unverified.
                    val gameRecord = pending.recordFile?.let(record::gameRecord)
                        ?.let { runCatching { Json.parseToJsonElement(it.decodeToString()) }.getOrNull() } ?: kotlinx.serialization.json.JsonNull
                    api.rpc("mm_ranked_ai_result2", mapOf("p_game" to JsonPrimitive(pending.ticket), "p_result" to JsonPrimitive(pending.outcome.raw),
                        "p_record" to gameRecord))
                } else {
                    api.rpc("mm_ranked_ai_result", mapOf("p_game" to JsonPrimitive(pending.ticket), "p_result" to JsonPrimitive(pending.outcome.raw)))
                }
                record.resolvePendingRankedResult(pending.ticket)
                parse(text)?.let { standing -> record.settleRanked(pending.ticket, standing); record.adopt(standing) }
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                // A ticket the server doesn't know never will be; anything else waits for the next sync.
                if (SupabaseLite.code(error) == "not_found") record.resolvePendingRankedResult(pending.ticket)
            }
        }
        var standing = runCatching { api.rpc("mm_ranked_standing") }.getOrNull()?.let(::parse) ?: return
        val local = record.file.rank
        if (!standing.seeded && (local.position > io.magicmobile.android.game.RankPosition.START || local.wins + local.losses > 0)) {
            runCatching {
                api.rpc("mm_ranked_seed", mapOf("p_points" to JsonPrimitive(local.position.points), "p_peak_points" to JsonPrimitive(local.peak.points),
                    "p_wins" to JsonPrimitive(local.wins), "p_losses" to JsonPrimitive(local.losses)))
            }.getOrNull()?.let(::parse)?.let { standing = it }
        }
        record.adopt(standing)
    }

    /**
     * Shares the title and favourite commander with friends. The server keeps the rank itself and ignores the rank numbers
     * sent here (they stay for older servers). Quiet on failure.
     */
    suspend fun publishRank(rank: RankState, title: Achievement?, commander: String?) {
        if (phase != Phase.READY || username == null) return
        runCatching {
            api.rpc("mm_ranked_publish", mapOf("p_season" to JsonPrimitive(rank.season), "p_rank_step" to JsonPrimitive(rank.position.step),
                "p_pips" to JsonPrimitive(rank.position.pips), "p_peak_step" to JsonPrimitive(rank.peak.step), "p_wins" to JsonPrimitive(rank.wins),
                "p_losses" to JsonPrimitive(rank.losses), "p_title" to (title?.title?.let(::JsonPrimitive) ?: JsonNull),
                "p_favorite_commander" to (commander?.let(::JsonPrimitive) ?: JsonNull)))
        }
    }

    /** The season leaderboard (mm_ranked_leaderboard), or null offline or without a profile name. */
    suspend fun rankedLeaderboard(scope: io.magicmobile.android.game.RankedLeaderboard.Scope, limit: Int = 50): io.magicmobile.android.game.RankedLeaderboard? {
        if (SocialFixtures.isActive) return SocialFixtures.leaderboard(scope, username ?: SocialFixtures.OWN_NAME, limit)
        if (phase != Phase.READY || username == null) return null
        return runCatching {
            io.magicmobile.android.game.RankedLeaderboard.parse(Json.parseToJsonElement(api.rpc("mm_ranked_leaderboard",
                mapOf("p_scope" to JsonPrimitive(scope.raw), "p_limit" to JsonPrimitive(limit)))) as JsonObject)
        }.getOrNull()
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

    /**
     * The server's settings for this build (mm_app_config): the menu's notice, card-name fixes and feature switches, kept in
     * [AppConfigStore]. Best effort: the last copy stays when this fails.
     */
    /** A voice chat token for one seat of one game (the agora-token function; VoiceRoom): the App ID and the token. */
    suspend fun voiceToken(channel: String, seat: String): Pair<String, String> {
        val reply = api.invoke("agora-token", mapOf("channel" to JsonPrimitive(channel), "account" to JsonPrimitive(seat)))
        val json = kotlinx.serialization.json.Json.parseToJsonElement(reply) as? JsonObject ?: throw SupabaseLite.Failure("error")
        val appId = (json["appId"] as? JsonPrimitive)?.content ?: throw SupabaseLite.Failure("error")
        val token = (json["token"] as? JsonPrimitive)?.content ?: throw SupabaseLite.Failure("error")
        return appId to token
    }

    suspend fun refreshAppConfig() {
        if (phase != Phase.READY) return
        runCatching {
            api.rpc("mm_app_config", mapOf("p_platform" to JsonPrimitive("android"),
                "p_build" to JsonPrimitive(io.magicmobile.android.BuildConfig.RELEASE_BUILD)))
        }.getOrNull()?.let(io.magicmobile.android.ui.AppConfigStore::store)
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
        match.durationSeconds?.takeIf { it > 0 }?.let { params["p_duration_seconds"] = JsonPrimitive(minOf(86_400, it)) }
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
        fixtureMessages = SocialFixtures.messages()
        unreadMessages = fixtureMessages.values.flatten().count { !it.fromMe && !it.read }
    }

    // MARK: Messages between friends

    /** Just the unread count (checked more often during a game). */
    suspend fun refreshUnread() {
        if (SocialFixtures.isActive || phase != Phase.READY || username == null || !messagesAvailable) return
        try { unreadMessages = api.rpc("mm_message_unread").trim().toInt() }
        catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) { if (SupabaseLite.code(error) == "feature_unavailable") messagesAvailable = false }
    }

    /** Conversations with friends, newest first; null offline or on a server without messages. */
    suspend fun conversations(): List<io.magicmobile.android.game.MessageConversation>? {
        if (SocialFixtures.isActive) return fixtureMessages.mapNotNull { (name, messages) ->
            messages.lastOrNull()?.let { io.magicmobile.android.game.MessageConversation(name, messages.count { !it.fromMe && !it.read }, it) }
        }.sortedByDescending { it.last.id }
        if (phase != Phase.READY || username == null) return null
        return try {
            io.magicmobile.android.game.FriendMessageRules.parseConversations(api.rpc("mm_message_conversations")).also { messagesAvailable = true }
        } catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) { if (SupabaseLite.code(error) == "feature_unavailable") messagesAvailable = false; null }
    }

    /** A page of a conversation (the newest, or the messages before [before]). Reading the newest marks theirs read. */
    suspend fun thread(name: String, before: Long? = null): io.magicmobile.android.game.MessageThread {
        if (SocialFixtures.isActive) {
            if (before == null) {
                fixtureMessages = fixtureMessages + (name to fixtureMessages[name].orEmpty().map { if (it.fromMe) it else it.copy(read = true) })
                unreadMessages = fixtureMessages.values.flatten().count { !it.fromMe && !it.read }
            }
            return io.magicmobile.android.game.MessageThread(name, fixtureMessages[name].orEmpty().filter { before == null || it.id < before }, false)
        }
        val thread = io.magicmobile.android.game.FriendMessageRules.parseThread(api.rpc("mm_message_thread", mapOf("p_username" to JsonPrimitive(name),
            "p_before" to (before?.let(::JsonPrimitive) ?: JsonNull), "p_limit" to JsonPrimitive(50)))) ?: throw SupabaseLite.Failure("error")
        if (before == null) runCatching { unreadMessages = api.rpc("mm_message_unread").trim().toInt() }
        return thread
    }

    /** Sends a message to a friend; null (with a notice) when it couldn't be sent. */
    suspend fun sendMessage(name: String, raw: String): io.magicmobile.android.game.FriendMessage? {
        val body = io.magicmobile.android.game.FriendMessageRules.sanitize(raw) ?: return null
        if (SocialFixtures.isActive) {
            val message = io.magicmobile.android.game.FriendMessage((fixtureMessages.values.flatten().maxOfOrNull { it.id } ?: 0) + 1, body,
                System.currentTimeMillis(), fromMe = true, read = false)
            fixtureMessages = fixtureMessages + (name to fixtureMessages[name].orEmpty() + message)
            return message
        }
        return try {
            io.magicmobile.android.game.FriendMessageRules.parseMessage(api.rpc("mm_message_send", mapOf("p_username" to JsonPrimitive(name), "p_body" to JsonPrimitive(body))))
        } catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) { notice = PlayerAccountRules.message(SupabaseLite.code(error)); null }
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

    /**
     * A freeze report (docs/FREEZE_LOG.md), only after the player taps Send: true once the server stored it. Fails quietly
     * offline or over the hourly limit; the report stays on the phone.
     */
    suspend fun sendDiagnostic(kind: String, report: String): Boolean {
        if (SocialFixtures.isActive || HowToPlayLaunch.isAutomated(LaunchEnvironment.values)) return false
        return try {
            api.rpc("mm_send_diagnostic", mapOf("p_platform" to JsonPrimitive("android"),
                "p_app_version" to JsonPrimitive(io.magicmobile.android.BuildConfig.VERSION_NAME),
                "p_build" to JsonPrimitive(io.magicmobile.android.BuildConfig.VERSION_CODE.toString()),
                "p_kind" to JsonPrimitive(kind), "p_report" to JsonPrimitive(report.take(io.magicmobile.android.game.FreezeReport.MAX_CHARACTERS))))
                .trim() == "true"
        } catch (error: Exception) { false }
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

    suspend fun rpc(function: String, params: Map<String, JsonElement> = emptyMap()): String = call("$BASE/rest/v1/rpc/$function", params)

    /**
     * One file in Storage as the player (storage/v1/object/<bucket>/<path>): PUT uploads (replacing), GET answers the
     * file, DELETE removes it. Card pictures (CardArtSync) are the only use.
     */
    suspend fun storage(method: String, objectPath: String, body: ByteArray? = null): ByteArray {
        val token = accessToken()
        val (status, bytes) = withContext(Dispatchers.IO) {
            val connection = (URL("$BASE/storage/v1/object/$objectPath").openConnection() as HttpURLConnection).apply {
                requestMethod = method; connectTimeout = 15_000; readTimeout = 30_000; useCaches = false
                instanceFollowRedirects = false
                setRequestProperty("apikey", PUBLISHABLE_KEY)
                setRequestProperty("Authorization", "Bearer $token")
                if (body != null) { doOutput = true; setRequestProperty("Content-Type", "image/jpeg"); setRequestProperty("x-upsert", "true") }
            }
            try {
                body?.let { bytes -> connection.outputStream.use { it.write(bytes) } }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                status to (stream?.use { it.readBytes() } ?: ByteArray(0))
            } finally { connection.disconnect() }
        }
        if (status == 401) session = session?.copy(expiresAt = 0)
        if (status !in 200..299) {
            val text = String(bytes)
            val error = runCatching { ((Json.parseToJsonElement(text) as JsonObject)["error"] as? JsonPrimitive)?.contentOrNull }.getOrNull()
            throw Failure(if (status == 413) "Payload too large" else error ?: errorCode(text) ?: if (status == 404) "not_found" else "error")
        }
        return bytes
    }

    /** Calls the edge function functions/v1/[function] as the player (agora-token). */
    suspend fun invoke(function: String, params: Map<String, JsonElement> = emptyMap()): String = call("$BASE/functions/v1/$function", params)

    private suspend fun call(url: String, params: Map<String, JsonElement>): String {
        val token = accessToken()
        val (status, body) = post(url, JsonObject(params).toString(), token)
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

    /** The signed-in user's id: the access token's `sub` claim. */
    suspend fun userID(): String? {
        val payload = accessToken().split('.').getOrNull(1) ?: return null
        val claims = Json.parseToJsonElement(String(java.util.Base64.getUrlDecoder().decode(payload.trimEnd('=')), Charsets.UTF_8)) as? JsonObject
        return (claims?.get("sub") as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }
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
/** Deck sync over mm_decks_since / mm_deck_save / mm_deck_delete (supabaseDeckSync in the web's deckStudio/sync.ts). */
internal class SupabaseDeckSync(private val api: SupabaseLite) : io.magicmobile.android.studio.DeckSyncAPI {
    private fun fields(text: String) = Json.parseToJsonElement(text) as? JsonObject ?: JsonObject(emptyMap())
    private fun long(value: JsonElement?) = (value as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
    private fun view(value: JsonElement?): io.magicmobile.android.studio.ServerDeck {
        val row = value as? JsonObject ?: JsonObject(emptyMap())
        return io.magicmobile.android.studio.ServerDeck((row["id"] as? JsonPrimitive)?.contentOrNull ?: "", (row["name"] as? JsonPrimitive)?.contentOrNull ?: "",
            long(row["revision"]) ?: 0, long(row["changeSeq"]) ?: 0, (row["deleted"] as? JsonPrimitive)?.booleanOrNull == true,
            row["deck"]?.takeIf { it !is JsonNull })
    }

    override suspend fun since(cursor: Long): io.magicmobile.android.studio.DeckSyncAPI.Page {
        val answer = fields(api.rpc("mm_decks_since", mapOf("p_cursor" to JsonPrimitive(cursor))))
        return io.magicmobile.android.studio.DeckSyncAPI.Page((answer["decks"] as? JsonArray).orEmpty().map(::view),
            long(answer["cursor"]) ?: cursor, (answer["more"] as? JsonPrimitive)?.booleanOrNull == true)
    }

    override suspend fun save(id: String, name: String, document: JsonObject, base: Long?): io.magicmobile.android.studio.DeckSyncAPI.Saved {
        val answer = fields(api.rpc("mm_deck_save", mapOf("p_id" to JsonPrimitive(id), "p_name" to JsonPrimitive(name), "p_deck" to document,
            "p_base" to (base?.let(::JsonPrimitive) ?: JsonNull))))
        return io.magicmobile.android.studio.DeckSyncAPI.Saved((answer["status"] as? JsonPrimitive)?.contentOrNull == "saved", view(answer["deck"]))
    }

    override suspend fun remove(id: String, base: Long): io.magicmobile.android.studio.DeckSyncAPI.Deleted {
        val answer = fields(api.rpc("mm_deck_delete", mapOf("p_id" to JsonPrimitive(id), "p_base" to JsonPrimitive(base))))
        return io.magicmobile.android.studio.DeckSyncAPI.Deleted((answer["status"] as? JsonPrimitive)?.contentOrNull == "conflict",
            answer["deck"]?.takeIf { it !is JsonNull }?.let(::view))
    }
}

/** Card picture sync over mm_card_art_since / mm_card_art_set and the player's picture folder (supabaseCardArtSync in the web's cardArtSync.ts). */
internal class SupabaseCardArtSync(private val api: SupabaseLite) : io.magicmobile.android.studio.CardArtSyncAPI {
    private fun long(value: JsonElement?) = (value as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
    private fun art(value: JsonElement?): io.magicmobile.android.studio.ServerCardArt {
        val row = value as? JsonObject ?: JsonObject(emptyMap())
        return io.magicmobile.android.studio.ServerCardArt((row["cardKey"] as? JsonPrimitive)?.contentOrNull ?: "",
            (row["picture"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull, long(row["changeSeq"]) ?: 0)
    }
    private suspend fun file(picture: String): String {
        val user = api.userID() ?: throw SupabaseLite.Failure("not_signed_in")
        return "custom-card-art/$user/$picture.jpg"
    }

    override suspend fun since(cursor: Long): io.magicmobile.android.studio.CardArtSyncAPI.Page {
        val answer = Json.parseToJsonElement(api.rpc("mm_card_art_since", mapOf("p_cursor" to JsonPrimitive(cursor)))) as? JsonObject ?: JsonObject(emptyMap())
        return io.magicmobile.android.studio.CardArtSyncAPI.Page((answer["arts"] as? JsonArray).orEmpty().map(::art),
            long(answer["cursor"]) ?: cursor, (answer["more"] as? JsonPrimitive)?.booleanOrNull == true)
    }

    override suspend fun set(cardKey: String, picture: String?) =
        art(Json.parseToJsonElement(api.rpc("mm_card_art_set", mapOf("p_card_key" to JsonPrimitive(cardKey), "p_picture" to (picture?.let(::JsonPrimitive) ?: JsonNull)))))

    override suspend fun upload(picture: String, bytes: ByteArray) { api.storage("PUT", file(picture), bytes) }
    override suspend fun download(picture: String): ByteArray = api.storage("GET", file(picture))
    override suspend fun removeFile(picture: String) { api.storage("DELETE", file(picture)) }
}

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
