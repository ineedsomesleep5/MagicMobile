package io.magicmobile.android.ranked

import io.magicmobile.android.game.MatchOpponent
import io.magicmobile.android.game.PlayerFriend
import io.magicmobile.android.game.PlayerSearchResult
import io.magicmobile.android.game.ProfileGame
import io.magicmobile.android.game.ProfileOpponent
import io.magicmobile.android.game.ProfileRankPoint
import io.magicmobile.android.game.ProfileSummary
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.game.PublicProfile
import io.magicmobile.android.social.PublicProfileResult
import io.magicmobile.android.game.MatchRecord
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.RankChange
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.SeasonRecord
import io.magicmobile.android.ui.LaunchEnvironment

/**
 * Development fixtures for the profile and the friends screens (SocialFixtures.swift), so they can be looked at without the
 * network or an account. They only run from debug intent extras, like the other MAGICMOBILE_UI_TEST_* values.
 *
 *   MAGICMOBILE_UI_TEST_SOCIAL=1   a rich game history for the own profile, and a fixture account (friends, players, public profiles)
 *   MAGICMOBILE_UI_TEST_OPEN=profile|friends|public:<name>|search:<text>   opens that screen at launch
 */
object SocialFixtures {
    val isActive: Boolean get() = LaunchEnvironment["MAGICMOBILE_UI_TEST_SOCIAL"] != null
    val openScreen: String? get() = if (isActive) LaunchEnvironment["MAGICMOBILE_UI_TEST_OPEN"] else null

    data class Deck(val id: String, val name: String, val commander: String, val colors: List<String>, val bracket: Int)

    val decks = listOf(
        Deck("local:goblins", "Goblin Warren", "Krenko, Mob Boss", listOf("R"), 3),
        Deck("local:vampires", "Blood Court", "Edgar Markov", listOf("W", "B", "R"), 3),
        Deck("local:atraxa", "Proliferate", "Atraxa, Praetors' Voice", listOf("W", "U", "B", "G"), 4),
        Deck("local:ninjas", "Shadow Ninjas", "Yuriko, the Tiger's Shadow", listOf("U", "B"), 2),
        Deck("local:elves", "Elven Chorus", "Lathril, Blade of the Elves", listOf("B", "G"), 2),
    )

    val foes = listOf(
        "Ayula's Moot" to "Ayula, Queen Among Bears", "Tavern Brawlers" to "Grand Arbiter Augustin IV",
        "Graveyard Shift" to "Meren of Clan Nel Toth", "Storm Front" to "Niv-Mizzet, Parun",
        "Dragon Hoard" to "The Ur-Dragon", "Elfball" to "Marwyn, the Nurturer",
    )

    /** Oldest first: wins, losses and a draw, finishing on a four-game streak with a best run of six. */
    private const val RESULTS = "WWLWLWWWLWWLLWWWWWWLWLWWDWLWWLWWWWWW"

    /** Thirty-six games over seven weeks, newest first; the ranked ones climb from Silver. Also returns the rank the games leave behind. */
    fun matches(now: Long, season: String): Pair<List<MatchRecord>, RankState> {
        var state = RankState.fresh(season).let {
            val start = RankPosition.make(RankTier.SILVER, 2, 1)
            it.copy(position = start, peak = start)
        }
        val made = ArrayList<MatchRecord>()
        RESULTS.forEachIndexed { index, letter ->
            val deck = decks[(index * index + index / 3) % decks.size]
            val foe = foes[(index * 5 + 1) % foes.size]
            val outcome = when (letter) { 'W' -> RankOutcome.WIN; 'L' -> RankOutcome.LOSS; else -> RankOutcome.DRAW }
            val ranked = index % 2 == 0
            var change: RankChange? = null
            if (ranked) { val (next, c) = RankLadder.apply(outcome, state, deck.bracket); state = next; change = c }
            val date = now - ((RESULTS.length - 1 - index) * 1.35 * 86_400_000).toLong() - 3_600_000L * (index % 5)
            made += MatchRecord(date = date, mode = if (ranked) PlayMode.RANKED else if (index % 7 == 1) PlayMode.CASUAL else PlayMode.QUICK,
                opponents = listOf(MatchOpponent(foe.first, foe.second, true)), opponentBracket = foe.first.length % 3 + 2, aiSkill = 3,
                deckID = deck.id, deckName = deck.name, commander = deck.commander, colors = deck.colors, deckBracket = deck.bracket, outcome = outcome,
                turns = 6 + (index * 3) % 8, rankChange = change, season = if (ranked) season else null)
        }
        state = state.copy(history = listOf(
            SeasonRecord("2026-09", RankPosition.make(RankTier.BRONZE, 1, 2), RankPosition.make(RankTier.SILVER, 4, 0), 11, 9),
            SeasonRecord("2026-08", RankPosition.make(RankTier.BRONZE, 3, 0), RankPosition.make(RankTier.BRONZE, 2, 2), 6, 8)))
        return made.asReversed() to state
    }

    // MARK: The fixture account: friends, searchable players and public profiles instead of the server

    const val OWN_NAME = "CalebM"

    data class Player(val name: String, val visibility: ProfileVisibility, val commander: String, val step: Int, val pips: Int, val title: String?,
                      val online: Boolean, val hosting: Pair<String, Int>? = null)

    val players = listOf(
        Player("Aria_Blade", ProfileVisibility.PUBLIC, "Atraxa, Praetors' Voice", 13, 2, "Gold Champion", true, "K7M2QX" to 2),
        Player("DarkMoonDan", ProfileVisibility.PUBLIC, "Yuriko, the Tiger's Shadow", 9, 1, null, false),
        Player("ManaFiend", ProfileVisibility.PUBLIC, "Krenko, Mob Boss", 17, 3, "Platinum Warden", true),
        Player("DannyDraws", ProfileVisibility.PUBLIC, "Edgar Markov", 6, 0, null, true),
        Player("DaisyDuel", ProfileVisibility.PUBLIC, "Lathril, Blade of the Elves", 11, 1, "Contender", false),
        Player("DarthMulligan", ProfileVisibility.PUBLIC, "The Ur-Dragon", 14, 0, "Unstoppable", false),
        Player("DaCommander", ProfileVisibility.PUBLIC, "Meren of Clan Nel Toth", 3, 2, null, false),
        Player("Dahlia_Rose", ProfileVisibility.PUBLIC, "Ayula, Queen Among Bears", 20, 7, "Mythic Legend", false),
        Player("Dagger99", ProfileVisibility.FRIENDS, "Niv-Mizzet, Parun", 8, 3, null, false),
        Player("DaPrivate", ProfileVisibility.PRIVATE, "Marwyn, the Nurturer", 7, 0, null, false),
        Player("Zephyr_K", ProfileVisibility.PUBLIC, "Ghave, Guru of Spores", 5, 1, null, false),
    )

    /** The friends list the fixture account starts with. */
    fun startingFriends(now: Long = System.currentTimeMillis()): List<PlayerFriend> {
        fun row(name: String, relation: String, hoursAgo: Double? = null): PlayerFriend {
            val player = players.firstOrNull { it.name == name }
            return PlayerFriend(java.util.UUID.randomUUID().toString(), name, relation, relation == "friend" && player?.online == true,
                hoursAgo?.let { java.time.Instant.ofEpochMilli(now - (it * 3_600_000).toLong()).toString() }, if (name == "Aria_Blade") "android" else "ios",
                if (relation == "friend") player?.hosting?.first else null, if (relation == "friend") player?.hosting?.second else null)
        }
        return listOf(row("Aria_Blade", "friend"), row("ManaFiend", "friend"), row("DarkMoonDan", "friend", 2.0), row("DannyDraws", "incoming"), row("DaisyDuel", "outgoing"))
    }

    fun rank(name: String): RankPosition? = players.firstOrNull { it.name == name }?.let { RankPosition.published(it.step, it.pips) }

    /** mm_search_players on the fixture: a name's start, case-insensitive; never private profiles; the exact name first, then friends, then alphabetical; twelve at most. */
    fun search(prefix: String, friends: List<PlayerFriend>): List<PlayerSearchResult> {
        val wanted = prefix.lowercase()
        val season = RankLadder.season(System.currentTimeMillis())
        return players.filter { it.name.lowercase().startsWith(wanted) && it.visibility != ProfileVisibility.PRIVATE }
            .sortedWith(compareByDescending<Player> { it.name.lowercase() == wanted }
                .thenByDescending { player -> friends.any { it.username == player.name && it.isFriend } }.thenBy { it.name.lowercase() })
            .take(12).map { player ->
                val relation = friends.firstOrNull { it.username == player.name }?.relation ?: "none"
                val visible = player.visibility == ProfileVisibility.PUBLIC || relation == "friend"
                PlayerSearchResult(player.name, if (visible) player.commander else null, if (visible) season else null, if (visible) player.step else null,
                    if (visible) player.pips else null, player.visibility, relation, if (relation == "friend") player.online else null)
            }
    }

    /** mm_public_profile on the fixture. */
    fun publicProfile(name: String, friends: List<PlayerFriend>, own: String?): PublicProfileResult {
        if (name.equals(own ?: OWN_NAME, ignoreCase = true)) {
            return PublicProfileResult.Profile(profile(Player(own ?: OWN_NAME, ProfileVisibility.PUBLIC, "Krenko, Mob Boss", 9, 1, "Rising Star", true), "self"))
        }
        val player = players.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: return PublicProfileResult.NotFound
        val relation = friends.firstOrNull { it.username == player.name }?.relation ?: "none"
        val allowed = player.visibility == ProfileVisibility.PUBLIC || (player.visibility == ProfileVisibility.FRIENDS && relation == "friend")
        if (!allowed) return PublicProfileResult.Profile(PublicProfile(player.name, true, player.visibility, relation, null, null, null, null,
            ProfileSummary(weeks = ProfileSummary.emptyWeeks(System.currentTimeMillis())), emptyList()))
        return PublicProfileResult.Profile(profile(player, relation))
    }

    private fun profile(player: Player, relation: String): PublicProfile {
        var seed = player.name.fold(7L) { acc, c -> (acc * 31 + c.code) % 1_000_003 }
        fun next(bound: Int): Int {
            seed = seed * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            return ((seed ushr 33) % bound).toInt()
        }
        val now = System.currentTimeMillis()
        val humans = players.map { it.name }.filter { it != player.name }
        val games = ArrayList<ProfileGame>()
        val points = ArrayList<ProfileRankPoint>()
        var standing = maxOf(0, player.step * 4 + player.pips - 10)
        val count = 22 + next(8)
        for (index in 0 until count) {
            val deck = decks[(index + next(3)) % decks.size]
            val won = next(100) < 45 + player.step * 2
            val ranked = index % 2 == 0
            val withHuman = next(3) == 0
            val foeName: String; val foeCommander: String
            if (withHuman) { foeName = humans[next(humans.size)]; foeCommander = foes[next(foes.size)].second }
            else { foeName = foes[next(foes.size)].first; foeCommander = foes[next(foes.size)].second }
            val date = now - ((count - 1 - index) * 1.6 * 86_400_000).toLong() - next(40_000) * 1000L
            if (ranked) { standing = maxOf(0, standing + if (won) 1 else -1); points += ProfileRankPoint(date, standing) }
            games += ProfileGame("${player.name}-$index", date, if (ranked) PlayMode.RANKED else if (index % 5 == 1) PlayMode.CASUAL else PlayMode.QUICK,
                if (won) RankOutcome.WIN else RankOutcome.LOSS, deck.name, listOf(deck.commander), deck.colors,
                listOf(ProfileOpponent(foeName, foeCommander, !withHuman, foeName == "Dagger99" && index % 3 == 0 && withHuman)), 5 + next(9))
        }
        games.reverse()
        val summary = ProfileSummary.of(games, now, points.takeLast(60))
        return PublicProfile(player.name, false, player.visibility, relation, if (relation == "friend") player.online else null, player.title, player.commander,
            PublicProfile.Rank(RankLadder.season(now), player.step, player.pips, minOf(20, player.step + 1), summary.wins / 2, summary.losses / 2), summary, games.take(30))
    }
}
