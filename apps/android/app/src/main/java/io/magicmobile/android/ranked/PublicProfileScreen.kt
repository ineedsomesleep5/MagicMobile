package io.magicmobile.android.ranked

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.FriendChallengeRules
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.game.PublicProfile
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.social.PublicProfileResult
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.launch

private sealed class Load {
    object Loading : Load()
    data class Loaded(val profile: PublicProfile) : Load()
    object NotFound : Load()
    object Unavailable : Load()
    data class Failed(val message: String) : Load()
}

/**
 * Another player's profile (or your own, as others see it): their rank and its history, record, commanders, colors and recent games
 * with the names of who they played (PublicProfileView.swift). Add friend, Challenge, Block and Report live here. Opponents' names
 * open their profiles in turn.
 */
@Composable
fun PublicProfileScreen(account: PlayerAccount, username: String, challenge: ((String, PlayMode) -> Unit)? = null, myRankStep: Int? = null, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    // The profiles opened one from another (an opponent's name); back returns along them.
    val stack = remember { mutableStateListOf(username) }
    val shown = stack.last()
    var load by remember { mutableStateOf<Load>(Load.Loading) }
    var confirmBlock by remember { mutableStateOf(false) }
    var confirmReport by remember { mutableStateOf(false) }
    var showAllGames by remember { mutableStateOf(false) }
    var reloads by remember { mutableIntStateOf(0) }
    fun goBack() { if (stack.size > 1) { stack.removeAt(stack.size - 1); showAllGames = false } else close() }
    BackHandler { goBack() }
    LaunchedEffect(shown, reloads) {
        load = Load.Loading
        load = when (val result = account.publicProfile(shown)) {
            is PublicProfileResult.Profile -> Load.Loaded(result.profile)
            PublicProfileResult.NotFound -> Load.NotFound
            PublicProfileResult.Unavailable -> Load.Unavailable
            is PublicProfileResult.Failed -> Load.Failed(result.message)
        }
    }
    Box(Modifier.fillMaxSize()) {
        TavernLobbyPage(shown, ::goBack, if (stack.size > 1) "Back" else "Friends") {
            when (val state = load) {
                Load.Loading -> Box(Modifier.leatherCard()) { SocialWaiting("Opening $shown's profile…") }
                Load.NotFound -> NoteCard("No player has that name, or you can't see them.", "questionmark.circle")
                Load.Unavailable -> NoteCard("Player profiles arrive with the next server update. You can still add friends and play with them.", "hourglass")
                is Load.Failed -> {
                    NoteCard(state.message, "wifi.exclamationmark")
                    TavernPlaqueButton("Try again", { reloads++ }, Modifier.testTag("publicProfile.retry"), kind = TavernButtonKind.SECONDARY)
                }
                is Load.Loaded -> {
                    val profile = state.profile
                    if (profile.restricted) Restricted(profile, account, scope, { reloads++ }, challenge, myRankStep, { confirmReport = true }, { confirmBlock = true }, close)
                    else Content(profile, account, scope, { reloads++ }, challenge, myRankStep, showAllGames, { showAllGames = !showAllGames },
                        { name -> stack.add(name); showAllGames = false }, { confirmReport = true }, { confirmBlock = true }, close)
                }
            }
        }
        account.notice?.takeIf { account.phase == PlayerAccount.Phase.READY }?.let { SocialNotice(it, { account.notice = null }, Modifier.align(Alignment.BottomCenter)) }
    }
    if (confirmBlock) TavernConfirmationDialog("Block $shown?", "They're removed from your friends and can't send you requests. You can unblock them in Friends later.",
        listOf(TavernDialogAction("Block", destructive = true) { scope.launch { account.block(shown); close() } })) { confirmBlock = false }
    if (confirmReport) TavernConfirmationDialog("Report $shown?", "The developer reviews reports of a name or a profile. You can also block them.",
        listOf(TavernDialogAction("Report", destructive = true) { scope.launch { account.report(shown, null, "profile") } })) { confirmReport = false }
}

@Composable
private fun NoteCard(text: String, icon: String) {
    Box(Modifier.leatherCard().testTag("publicProfile.note")) { ProfileEmptyNote(text, icon) }
}

@Composable
private fun ColumnScope.Restricted(profile: PublicProfile, account: PlayerAccount, scope: kotlinx.coroutines.CoroutineScope, reload: () -> Unit,
                                   challenge: ((String, PlayMode) -> Unit)?, myRankStep: Int?, report: () -> Unit, block: () -> Unit, close: () -> Unit) {
    Header(profile)
    Column(Modifier.leatherCard().testTag("publicProfile.restricted").semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SfImage("hand.raised", TavernPalette.brass, 30.dp)
        Text(if (profile.visibility == ProfileVisibility.FRIENDS) "Only friends can open this profile." else "This profile is private.", color = TavernPalette.parchment,
            style = sf(15f, SfWeight.semibold, SfDesign.SERIF), textAlign = TextAlign.Center)
        if (!profile.isFriend) Text("You can still send ${profile.username} a friend request.", Modifier.alpha(0.7f), color = TavernPalette.parchment,
            style = sf(12f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center)
    }
    Actions(profile, account, scope, reload, challenge, myRankStep, report, block, close)
}

@Composable
private fun ColumnScope.Content(profile: PublicProfile, account: PlayerAccount, scope: kotlinx.coroutines.CoroutineScope, reload: () -> Unit,
                                challenge: ((String, PlayMode) -> Unit)?, myRankStep: Int?, showAll: Boolean, toggleAll: () -> Unit, openPlayer: (String) -> Unit,
                                report: () -> Unit, block: () -> Unit, close: () -> Unit) {
    val summary = profile.summary
    Header(profile)
    if (profile.isSelf) Box(Modifier.leatherCard().testTag("publicProfile.selfNote")) {
        ProfileEmptyNote("This is how other players see your profile. It is ${profile.visibility.title.lowercase()}.", "eye")
    } else Actions(profile, account, scope, reload, challenge, myRankStep, report, block, close)
    Column(Modifier.leatherCard().testTag("publicProfile.rank"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        val rank = profile.rank
        val position = rank?.position
        if (rank != null && position != null) {
            ProfileRankSummary(position, RankLadder.seasonName(rank.season), rank.wins, rank.losses, RankPosition.atStep(rank.peakStep))
            Box(Modifier.fillMaxWidth().size(1.dp).background(TavernPalette.brass.copy(alpha = 0.4f)))
        } else {
            ProfileSectionTitle("Rank")
            ProfileEmptyNote("${profile.username} hasn't played ranked this season.", "shield.lefthalf.filled")
        }
        ProfileSectionTitle("Rank history")
        if (summary.rankPoints.isEmpty()) ProfileEmptyNote("No ranked games to chart yet.", "chart.bar.fill") else RankHistoryChart(summary.rankPoints)
    }
    Column(Modifier.leatherCard().testTag("publicProfile.stats"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ProfileSectionTitle("Record", "${summary.games} games")
        if (summary.games == 0) ProfileEmptyNote("No games to show yet.")
        else {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                WinRateRing(summary.wins, summary.losses, summary.draws, 118.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ProfileStatTile("Wins", "${summary.wins}", Modifier.weight(1f)); ProfileStatTile("Losses", "${summary.losses}", Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ProfileStatTile("Draws", "${summary.draws}", Modifier.weight(1f))
                        ProfileStatTile("Avg. turns", summary.averageTurns?.let { "%.1f".format(it) } ?: "–", Modifier.weight(1f))
                    }
                }
            }
            StreakRow(summary.currentStreak, summary.bestStreak)
        }
    }
    Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Games over time", "last 8 weeks")
        if (summary.weeks.all { it.games == 0 }) ProfileEmptyNote("Nothing played in the last eight weeks.", "hourglass") else WeeklyBars(summary.weeks)
    }
    if (summary.commanders.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Most played commanders"); CommanderTiles(summary.commanders)
    }
    if (summary.colors.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Color identity"); ColorPie(summary.colors)
    }
    Column(Modifier.leatherCard().testTag("publicProfile.history"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Recent games", "${profile.games.size} shown")
        if (profile.games.isEmpty()) ProfileEmptyNote("No recent games to show.")
        for (game in profile.games.take(if (showAll) 30 else 6)) ProfileGameCard(game, "publicProfile.game.${game.id}", openPlayer = openPlayer)
        if (profile.games.size > 6) TavernPlaqueButton(if (showAll) "Show fewer" else "Show more", toggleAll, Modifier.testTag("publicProfile.games.more"), kind = TavernButtonKind.SECONDARY)
    }
}

@Composable
private fun Header(profile: PublicProfile) {
    Row(Modifier.leatherCard().testTag("publicProfile.header"), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        CommanderArtMedallion(profile.favoriteCommander ?: profile.summary.commanders.firstOrNull()?.id, 78.dp, Modifier.testTag("publicProfile.picture"))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            FitText(profile.username, sf(24f, SfWeight.black, SfDesign.SERIF), Modifier.testTag("publicProfile.name").semantics { heading() }, color = TavernPalette.parchment, minimumScale = 0.7f)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                profile.title?.let { TavernTag(it, leather = true, accent = TavernPalette.ember) }
                TavernTag(when (profile.relation) {
                    "self" -> "YOU"; "friend" -> "FRIEND"; "outgoing" -> "REQUESTED"; "incoming" -> "WANTS TO BE FRIENDS"
                    else -> if (profile.visibility == ProfileVisibility.PUBLIC) "PUBLIC PROFILE" else "FRIENDS ONLY"
                }, leather = true)
            }
            profile.online?.let { online ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(9.dp).background(if (online) rgb(0.4, 0.85, 0.4) else Color.Gray.copy(alpha = 0.6f), CircleShape))
                    Text(if (online) "Online" else "Offline", Modifier.alpha(0.8f), color = TavernPalette.parchment, style = sf(12f, SfWeight.semibold, SfDesign.SERIF))
                }
            }
        }
    }
}

@Composable
private fun Actions(profile: PublicProfile, account: PlayerAccount, scope: kotlinx.coroutines.CoroutineScope, reload: () -> Unit,
                    challenge: ((String, PlayMode) -> Unit)?, myRankStep: Int?, report: () -> Unit, block: () -> Unit, close: () -> Unit) {
    if (profile.isSelf) return
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        when (profile.relation) {
            "friend" -> if (challenge != null && profile.online == true) {
                val mayRank = myRankStep?.let { FriendChallengeRules.mayRank(it, profile.rank?.position?.step) } ?: false
                TavernMenu(Modifier.testTag("publicProfile.challenge"), TavernMenuEdge.BELOW, contentDescription = "Challenge ${profile.username}", label = {
                    TavernFacePlaque("Challenge")
                }) {
                    TavernMenuItem("Quick Match", { challenge(profile.username, PlayMode.QUICK); close() }, systemImage = "bolt.fill")
                    TavernMenuItem(if (mayRank) "Ranked" else "Ranked · same tier only", { if (mayRank) { challenge(profile.username, PlayMode.RANKED); close() } },
                        systemImage = "shield.lefthalf.filled")
                }
            }
            "outgoing" -> TavernPlaqueButton("Request sent", {}, Modifier.testTag("publicProfile.requested"), kind = TavernButtonKind.SECONDARY, enabled = false)
            "incoming" -> {
                TavernPlaqueButton("Accept request", {
                    account.friends.firstOrNull { it.username == profile.username }?.let { scope.launch { account.respond(it, true); reload() } }
                }, Modifier.testTag("publicProfile.accept"))
                TavernPlaqueButton("Decline", {
                    account.friends.firstOrNull { it.username == profile.username }?.let { scope.launch { account.respond(it, false); reload() } }
                }, Modifier.testTag("publicProfile.decline"), kind = TavernButtonKind.SECONDARY)
            }
            else -> TavernPlaqueButton("Add friend", { scope.launch { account.addFriend(profile.username); reload() } }, Modifier.testTag("publicProfile.add"))
        }
        Spacer(Modifier.weight(1f))
        TavernMenu(Modifier.testTag("publicProfile.more"), TavernMenuEdge.BELOW, contentDescription = "More about ${profile.username}", label = {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis", TavernPalette.brass, 17.dp) }
        }) {
            TavernMenuItem("Report player", report, systemImage = "exclamationmark.bubble.fill", destructive = true)
            TavernMenuItem("Block player", block, systemImage = "hand.raised", destructive = true)
        }
    }
}
