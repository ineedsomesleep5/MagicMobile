package io.magicmobile.android.ranked

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.Achievement
import io.magicmobile.android.game.AIDeck
import io.magicmobile.android.game.MatchOpponent
import io.magicmobile.android.game.MatchRecord
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.PlayerRecordFile
import io.magicmobile.android.game.PlayerStats
import io.magicmobile.android.game.RankChange
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.ui.LaunchEnvironment
import java.io.File

/**
 * PlayerRecordStore (PlayerRecord.swift): the profile on this phone, in files/Profile/player-record.json.
 * Ranked standing is also published to the profile server so friends see it (`publish`).
 */
class PlayerRecordStore(context: Context, private val now: () -> Long = System::currentTimeMillis) {
    private val file_ = File(context.filesDir, "Profile/player-record.json")
    var file by mutableStateOf(load()); private set
    /** Set by the root to share ranked results with friends. */
    var publish: ((RankState, Achievement?, String?) -> Unit)? = null

    init {
        val rolled = file.copy(rank = RankLadder.rollover(file.rank, RankLadder.season(now())))
        if (rolled != file) { file = rolled; save() }
        applyUITestSeed(LaunchEnvironment.values)
    }

    private fun load(): PlayerRecordFile = runCatching {
        PlayerRecordFile.json.decodeFromString(PlayerRecordFile.serializer(), file_.readText())
    }.getOrElse { PlayerRecordFile(RankState.fresh(RankLadder.season(now()))) }

    val shownCommander: String? get() = file.favoriteCommander ?: PlayerStats(file.matches).commanders.firstOrNull()?.label

    fun refreshSeason() {
        val season = RankLadder.season(now())
        if (season == file.rank.season) return
        file = file.copy(rank = RankLadder.rollover(file.rank, season)); save()
    }

    fun setTitle(title: Achievement?) { file = file.copy(title = title); save() }
    fun setFavoriteCommander(name: String?) { file = file.copy(favoriteCommander = name); save() }

    /** Records a finished game; a ranked game moves the ladder and returns how. */
    fun record(mode: PlayMode, outcome: RankOutcome, opponents: List<MatchOpponent>, opponentBracket: Int?, aiSkill: Int?, deckID: String,
               deckName: String, commander: String?, colors: List<String>, deckBracket: Int, turns: Int, aiDeckID: String? = null): RankChange? {
        val (next, change) = file.recording(now(), mode, outcome, opponents, opponentBracket, aiSkill, deckID, deckName, commander, colors,
            deckBracket, turns, aiDeckID)
        file = next; save()
        if (mode == PlayMode.RANKED) publish?.invoke(file.rank, file.title, shownCommander)
        return change
    }

    private fun save() {
        runCatching {
            file_.parentFile?.mkdirs()
            val temp = File(file_.parentFile, file_.name + ".tmp")
            temp.writeText(PlayerRecordFile.json.encodeToString(PlayerRecordFile.serializer(), file))
            temp.renameTo(file_)
        }
        // The profile is a convenience: a failed save never interrupts play.
    }

    /** Debug intent extras (as on iOS): MAGICMOBILE_UI_TEST_RANK=<tier>-<division>-<pips> and MAGICMOBILE_UI_TEST_MATCHES=<n>. */
    private fun applyUITestSeed(values: Map<String, String>) {
        values["MAGICMOBILE_UI_TEST_RANK"]?.split("-")?.let { parts ->
            val tier = parts.getOrNull(0)?.let(RankTier::of) ?: return@let
            val position = RankPosition.make(tier, parts.getOrNull(1)?.toIntOrNull() ?: 4, parts.getOrNull(2)?.toIntOrNull() ?: 0)
            file = file.copy(rank = file.rank.copy(position = position, peak = maxOf(file.rank.peak, position)))
        }
        val count = values["MAGICMOBILE_UI_TEST_MATCHES"]?.toIntOrNull() ?: 0
        if (count > 0 && file.matches.isEmpty()) {
            val sample = (0 until count).map { index ->
                MatchRecord(date = now() - index * 3_600_000L, mode = if (index % 3 == 0) PlayMode.RANKED else PlayMode.QUICK,
                    opponents = listOf(MatchOpponent("Opponent ${index + 1}", null, true)), opponentBracket = 2, aiSkill = 3,
                    deckID = "precon:token-triumph", deckName = "Token Triumph", commander = "Emmara, Soul of the Accord",
                    colors = listOf("W", "G"), deckBracket = 2, outcome = if (index % 3 == 1) RankOutcome.LOSS else RankOutcome.WIN, turns = 7 + index % 5)
            }
            file = file.copy(matches = sample)
        }
    }

    companion object {
        @Volatile private var shared: PlayerRecordStore? = null
        fun shared(context: Context): PlayerRecordStore = shared ?: synchronized(this) {
            shared ?: PlayerRecordStore(context.applicationContext).also { shared = it }
        }
    }
}

/** The AI deck pool on this phone: the precons (Core) plus ai-decks.json. */
fun aiPool(precons: List<io.magicmobile.android.ondevice.PreconDeck>, bracketDecks: List<AIDeck>): List<AIDeck> =
    precons.map { AIDeck(it.id, it.name, "", "", it.commander ?: "", io.magicmobile.android.game.CommanderBracket.CORE, it.deck) } + bracketDecks
