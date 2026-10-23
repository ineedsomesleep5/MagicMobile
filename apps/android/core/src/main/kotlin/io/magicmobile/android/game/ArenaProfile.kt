package io.magicmobile.android.game

import kotlin.math.ceil
import kotlin.math.roundToInt

/**
 * The pure rules of the Arena Profile, Ranked Hall and Friends pages (Ranked/ProfileView.swift, RankedHallViews.swift,
 * FriendsView.swift): the words and choices the screens show, kept here so they are JVM-tested.
 */
object ArenaProfileRules {
    /** The Ranked Hall's line under its title: "Season ends in 9 days", "Season ends tomorrow", or the season's name. */
    fun seasonEnds(season: String, now: Long): String {
        val end = RankLadder.seasonEnd(season) ?: return RankLadder.seasonName(season)
        val days = maxOf(0, ceil((end - now) / 86_400_000.0).toInt())
        return if (days <= 1) "Season ends tomorrow" else "Season ends in $days days"
    }

    /** A record's win rate as the progression tile writes it: "–" before any game, else a whole percent. */
    fun winRate(wins: Int, games: Int): String = if (games == 0) "–" else "${(wins.toDouble() / games * 100).roundToInt()}%"

    /** Each tier plaque of the Ranked Hall's stair is a step wider than the one before. */
    fun tierPlaqueWidth(index: Int, wide: Boolean): Float = (if (wide) 300f else 250f) + index * (if (wide) 26f else 22f)

    /**
     * The portrait choices besides "Most played": the commanders played most (up to 12), then the player's decks'
     * commanders not already listed, and a choice from a deck since deleted, which stays selectable among the played.
     */
    fun pictureChoices(played: List<String>, deckCommanders: List<String>, current: String?): Pair<List<String>, List<String>> {
        val most = played.take(12).toMutableList()
        val seen = most.toMutableSet()
        val decks = deckCommanders.filter { it.isNotBlank() && seen.add(it) }
        if (current != null && current !in seen) most.add(current)
        return most to decks
    }

    /** The podium's order: second, first, third (or second, first), so the winner stands in the middle. */
    fun <T> podiumOrder(top: List<T>): List<T> = when (top.size) {
        3 -> listOf(top[1], top[0], top[2])
        2 -> listOf(top[1], top[0])
        else -> top
    }

    /** An achievement's identifier as iOS spells it (its Swift case: "firstWin", "streak5"), for `profile.title.<id>`. */
    fun achievementID(achievement: Achievement): String = achievement.name.lowercase().split('_')
        .mapIndexed { index, part -> if (index == 0) part else part.replaceFirstChar { it.uppercase() } }.joinToString("")

    /** The question before a profile is deleted (FriendsView.swift, 2026-10-22). */
    const val DELETE_PROFILE_MESSAGE =
        "Your player name, friends, blocks and game history are removed from MagicMobile's server for good. Your decks and games on this phone stay."
}
