package io.magicmobile.android.ranked

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.game.ArenaProfileRules
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.RankedLeaderboard
import io.magicmobile.android.game.SeasonRecord
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaPlayButton
import io.magicmobile.android.menus.ArenaSegmented
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

// Port of Ranked/RankedHallViews.swift: the Ranked Hall and the live leaderboard, in Arena's look.

private val brassFill = Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22)))
private val onlineGreen = rgb(0.45, 0.92, 0.45)

/**
 * Ranked's page as Arena's Season Rewards: the title with the season's end in ember and the ways on beside it, a stair of tier
 * plaques from Bronze to Mythic (what each allows, and which you have reached), and your current rank in its own column.
 * Past seasons follow in the scroll. The Ranked tab's page, so no back chevron.
 */
@Composable
fun RankedHallScreen(account: PlayerAccount, rank: RankState, play: () -> Unit, leaderboard: () -> Unit, profile: () -> Unit, back: () -> Unit) {
    var teaser by remember { mutableStateOf<RankedLeaderboard?>(null) }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true; teaser = account.rankedLeaderboard(RankedLeaderboard.Scope.EVERYONE, 3) }
    val appeared = remember { Any() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight
        TavernLobbyPage("", back, showsBack = false, contentWidth = if (wide) 920.dp else null, scrolls = false) {
            HallEntrance(shown, 0) { HallHeader(rank, wide, teaser, play, leaderboard, profile) }
            if (wide) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Column(Modifier.weight(1f).fillMaxHeight().arenaScrollFade().verticalScroll(rememberScrollState()).testTag("lobby.scroll")
                        .padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        TierLadder(rank.position.tier, wide = true, shown)
                        SeasonStrip(rank)
                    }
                    Box(Modifier.width(250.dp)) { HallEntrance(shown, 80) { CurrentRank(rank, 104.dp, teaser, appeared) } }
                }
            } else {
                Column(Modifier.fillMaxSize().arenaScrollFade().verticalScroll(rememberScrollState()).testTag("lobby.scroll")
                    .padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    HallEntrance(shown, 80) { CurrentRank(rank, 120.dp, teaser, appeared) }
                    TierLadder(rank.position.tier, wide = false, shown)
                    SeasonStrip(rank)
                }
            }
        }
    }
}

/** The page's head: "Ranked" in serif with the season's end in ember under it, and the ways on beside it sideways, under it upright. */
@Composable
private fun HallHeader(rank: RankState, wide: Boolean, teaser: RankedLeaderboard?, play: () -> Unit, leaderboard: () -> Unit, profile: () -> Unit) {
    val title: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Ranked", Modifier.semantics { heading() }, color = ArenaMenuStyle.text, style = sf(30f, SfWeight.bold, SfDesign.SERIF))
            Text(ArenaProfileRules.seasonEnds(rank.season, System.currentTimeMillis()), color = ArenaMenuStyle.ember, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
        }
    }
    val ways: @Composable () -> Unit = {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            ArenaPlayButton("Play Ranked", { GameAudio.play(GameSound.MENU_PLAY); play() }, Modifier.size(150.dp, 40.dp), fontSize = 16f,
                identifier = "ranked.hall.play")
            Box(contentAlignment = Alignment.CenterStart) {
                ArenaPillButton("Leaderboard", { GameAudio.play(GameSound.UI_OPEN); leaderboard() }, identifier = "ranked.hall.leaderboard")
                if ((teaser?.online ?: 0) > 0) Box(Modifier.padding(start = 6.dp)) { OnlineDot(7.dp) }
            }
            ArenaPillButton("Profile", profile, identifier = "ranked.hall.profile")
        }
    }
    if (wide) Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { title() }
        ways()
    } else Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { title(); ways() }
}

/** Arena's reward plaque: a bar whose right end comes to a point, like an arrow along the stair. */
private object RewardPlaque : androidx.compose.ui.graphics.Shape {
    override fun createOutline(size: androidx.compose.ui.geometry.Size, layoutDirection: androidx.compose.ui.unit.LayoutDirection,
                               density: androidx.compose.ui.unit.Density): androidx.compose.ui.graphics.Outline {
        val point = minOf(with(density) { 16.dp.toPx() }, size.height * 0.45f)
        val r = minOf(with(density) { 6.dp.toPx() }, size.height / 3f)
        val path = androidx.compose.ui.graphics.Path().apply {
            moveTo(r, 0f)
            lineTo(size.width - point, 0f)
            lineTo(size.width, size.height / 2)
            lineTo(size.width - point, size.height)
            lineTo(r, size.height)
            quadraticTo(0f, size.height, 0f, size.height - r)
            lineTo(0f, r)
            quadraticTo(0f, 0f, r, 0f)
            close()
        }
        return androidx.compose.ui.graphics.Outline.Generic(path)
    }
}

/** Arena's stair of reward plaques: each tier a step wider than the one before; the tiers you've reached lit, yours edged in gold. */
@Composable
private fun TierLadder(tier: RankTier, wide: Boolean, shown: Boolean) {
    Column(Modifier.testTag("ranked.hall.tiers"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        RankTier.entries.forEachIndexed { index, step ->
            HallEntrance(shown, 100 + index * 40) { TierPlaque(step, tier, ArenaProfileRules.tierPlaqueWidth(index, wide).dp) }
        }
    }
}

@Composable
private fun TierPlaque(step: RankTier, tier: RankTier, width: Dp) {
    val reached = step <= tier
    val current = step == tier
    Row(Modifier.widthIn(max = width).fillMaxWidth().alpha(if (reached) 1f else 0.55f)
        .then(if (current) Modifier.glow(ArenaMenuStyle.gold.copy(alpha = 0.5f), 6.dp, 8.dp) else Modifier)
        .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = 0.95f), ArenaGlass.bottom.copy(alpha = 0.95f))), RewardPlaque)
        .then(if (current) Modifier.border(1.6.dp, ArenaMenuStyle.gold, RewardPlaque) else Modifier.border(1.dp, ArenaGlass.hairline, RewardPlaque))
        .padding(start = 12.dp, end = 26.dp, top = 7.dp, bottom = 7.dp)
        .semantics(mergeDescendants = true) { selected = current },
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        RankEmblem(step, 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(step.label, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold))
            Text("Decks up to Bracket ${step.maxDeckBracket}", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11.5f, SfWeight.medium))
        }
        if (current) ArenaCaps("You", 9f)
        else if (reached) SfImage("checkmark", ArenaMenuStyle.gold, 11.dp)
    }
}

/** Arena's Current Rank column: the badge turning in its glow with its pips and title, then the season's record. */
@Composable
private fun CurrentRank(rank: RankState, badge: Dp, teaser: RankedLeaderboard?, appeared: Any) {
    Column(Modifier.fillMaxWidth().testTag("ranked.hall.standing"), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("Current rank")
        Box(Modifier.padding(top = 4.dp), contentAlignment = Alignment.Center) {
            RankGlow(rank.position.tier, badge * 1.45f)
            RankBadge(rank.position, badge, showsPips = true, showsTitle = true, spinKey = appeared)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            HallStat("Wins", "${rank.wins}"); HallStat("Losses", "${rank.losses}"); HallStat("Peak", rank.peak.title)
            teaser?.me?.let { HallStat("Place", "#${it.position}") }
        }
    }
}

@Composable
private fun SeasonStrip(rank: RankState) {
    Column(Modifier.fillMaxWidth().testTag("ranked.hall.seasons"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("Past seasons")
        if (rank.history.isEmpty()) Text("First season", Modifier.alpha(0.8f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.regular))
        else Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            rank.history.take(6).forEach { SeasonChip(it) }
        }
    }
}

@Composable
private fun HallEntrance(shown: Boolean, delayMillis: Int, content: @Composable () -> Unit) {
    if (LaunchEnvironment.reduceMotion) { content(); return }
    AnimatedVisibility(shown, enter = fadeIn(tween(350, delayMillis)) +
        slideInVertically(spring(dampingRatio = 0.82f, stiffness = Spring.StiffnessMediumLow)) { it / 6 }) { content() }
}

@Composable
private fun HallStat(title: String, value: String) {
    Column(Modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = ArenaMenuStyle.text, style = sf(18f, SfWeight.black, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
        Text(title.uppercase(), Modifier.alpha(0.7f), color = ArenaMenuStyle.text, style = sf(9f, SfWeight.heavy, tracking = 1.2f))
    }
}

@Composable
private fun SeasonChip(record: SeasonRecord) {
    Column(Modifier.defaultMinSize(minWidth = 92.dp).background(Color.Black.copy(alpha = 0.25f), RoundedCornerShape(10.dp))
        .border(0.9.dp, ArenaGlass.hairline, RoundedCornerShape(10.dp)).padding(horizontal = 12.dp, vertical = 8.dp)
        .semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        RankEmblem(record.final.tier, 44.dp)
        Text(record.final.title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.black), maxLines = 1)
        Text(RankLadder.seasonName(record.season), Modifier.alpha(0.75f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(10f, SfWeight.semibold))
        Text("${record.wins}–${record.losses}", Modifier.alpha(0.85f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(11f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
    }
}

/** A slow breathing glow of the tier's metal behind a badge. */
@Composable
private fun RankGlow(tier: RankTier, size: Dp) {
    val breathe = if (LaunchEnvironment.reduceMotion) 0.5f else {
        val transition = rememberInfiniteTransition(label = "rankGlow")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(2600), RepeatMode.Reverse), label = "breathe").value
    }
    Canvas(Modifier.size(size).scale(0.9f + 0.16f * breathe).alpha(0.7f + 0.3f * breathe)) {
        drawCircle(Brush.radialGradient(listOf(tier.tint.copy(alpha = 0.55f), tier.tint.copy(alpha = 0.12f), Color.Transparent)))
    }
}

/** A glowing green dot with a ring pulsing out of it: this player is online now. */
@Composable
fun OnlineDot(size: Dp = 8.dp) {
    val pulse = if (LaunchEnvironment.reduceMotion) 1f else {
        val transition = rememberInfiniteTransition(label = "online")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = LinearEasing)), label = "pulse").value
    }
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.size(size).scale(1f + 1.4f * pulse).alpha(0.8f * (1f - pulse)).background(onlineGreen.copy(alpha = 0.5f), CircleShape))
        Box(Modifier.size(size).glow(onlineGreen, 3.dp, size).background(Brush.radialGradient(listOf(Color.White, onlineGreen)), CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.5f), CircleShape))
    }
}

/** A band of gold light sweeping across Mythic rows every few seconds. */
private fun Modifier.mythicShimmer(active: Boolean, phase: Float): Modifier = if (!active || LaunchEnvironment.reduceMotion) this else drawWithContent {
    drawContent()
    val band = size.width * 0.4f
    val x = -band + (size.width + band * 2) * phase
    drawRect(Brush.horizontalGradient(listOf(Color.Transparent, ArenaMenuStyle.gold.copy(alpha = 0.22f), Color.White.copy(alpha = 0.22f), Color.Transparent),
        startX = x, endX = x + band), blendMode = BlendMode.Screen)
}

// MARK: - Leaderboard

private sealed interface BoardLoad {
    data object Loading : BoardLoad
    data object Offline : BoardLoad
    data class Loaded(val board: RankedLeaderboard) : BoardLoad
}

/**
 * The season's standings from the server (mm_ranked_leaderboard): everyone or friends, a podium for the top three, rows that
 * slide when places change, a pulsing dot for who's online, a shimmer on Mythic rows and your own row pinned when it's off the
 * list. Refreshes every 20 seconds while open and the app is in front. Sideways the podium stands on its own glass on the left
 * and the standings run down the right, with your own row at their head; upright the podium leads and your row is pinned below.
 */
@Composable
fun RankedLeaderboardScreen(account: PlayerAccount, back: () -> Unit) {
    var scope by remember { mutableStateOf(RankedLeaderboard.Scope.EVERYONE) }
    var load by remember { mutableStateOf<BoardLoad>(BoardLoad.Loading) }
    val moves = remember { mutableStateMapOf<String, Int>() }
    var profile by remember { mutableStateOf<String?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(scope) {
        val last = HashMap<String, Int>()
        moves.clear()
        (load as? BoardLoad.Loaded)?.let { if (it.board.scope != scope.raw) load = BoardLoad.Loading }
        while (isActive) {
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                val board = account.rankedLeaderboard(scope)
                if (!isActive) break
                if (board == null) { if (load !is BoardLoad.Loaded) load = BoardLoad.Offline }
                else {
                    val changed = board.entries.mapNotNull { e -> last[e.username]?.takeIf { it != e.position }?.let { e.username to (it - e.position) } }.toMap()
                    moves.clear(); moves.putAll(changed)
                    last.clear(); board.entries.forEach { last[it.username] = it.position }
                    load = BoardLoad.Loaded(board)
                }
            }
            delay(REFRESH_MILLIS)
        }
    }
    val shimmerPhase = if (LaunchEnvironment.reduceMotion) 0f else {
        val transition = rememberInfiniteTransition(label = "mythic")
        transition.animateFloat(0f, 1f, infiniteRepeatable(tween(2200, delayMillis = 600, easing = LinearEasing)), label = "sweep").value
    }
    val open: (RankedLeaderboard.Entry) -> Unit = { GameAudio.play(GameSound.UI_OPEN); profile = it.username }
    val scopePicker: @Composable (Modifier) -> Unit = { modifier ->
        ArenaSegmented(RankedLeaderboard.Scope.entries.map { (if (it == RankedLeaderboard.Scope.EVERYONE) "Everyone" else "Friends") to it }, scope,
            { scope = it }, modifier, identifier = "leaderboard.scope")
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight
        val board = (load as? BoardLoad.Loaded)?.board
        TavernLobbyPage("Leaderboard", back, backTitle = "Ranked Hall", contentWidth = if (wide) 900.dp else null) {
            if (wide) Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                scopePicker(Modifier.width(240.dp))
                board?.let { Box(Modifier.weight(1f)) { LiveStrip(it) } }
            } else scopePicker(Modifier)
            when (val state = load) {
                BoardLoad.Loading -> Box(Modifier.leatherCard()) { SocialWaiting("Gathering the standings…") }
                BoardLoad.Offline -> BoardNote("The leaderboard needs your profile and a connection. Sign in from your profile, then come back.", "wifi.exclamationmark", "leaderboard.offline")
                is BoardLoad.Loaded -> {
                    val loaded = state.board
                    if (!wide) LiveStrip(loaded)
                    if (loaded.entries.isEmpty()) {
                        BoardNote(if (scope == RankedLeaderboard.Scope.FRIENDS) "None of your friends has played ranked this season yet. Challenge one from Friends."
                            else "Nobody has played ranked this season yet. Win a game to take the top spot.", "trophy.fill", "leaderboard.empty")
                    } else if (wide) {
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Box(Modifier.width(330.dp)) { Podium(loaded.entries.take(3), compact = true, open) }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                loaded.pinnedMe?.let { BoardRow(it, moves[it.username], shimmerPhase, pinned = true, open) }
                                for (entry in loaded.entries.drop(3)) BoardRow(entry, moves[entry.username], shimmerPhase, pinned = false, open)
                            }
                        }
                    } else {
                        Podium(loaded.entries.take(3), compact = false, open)
                        for (entry in loaded.entries.drop(3)) BoardRow(entry, moves[entry.username], shimmerPhase, pinned = false, open)
                    }
                    if (loaded.pinnedMe != null && !wide) Spacer(Modifier.height(72.dp))
                }
            }
        }
        val me = board?.pinnedMe
        if (me != null && !wide) {
            Box(Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal = 16.dp).padding(bottom = 8.dp)
                .widthIn(max = 608.dp)) { BoardRow(me, moves[me.username], shimmerPhase, pinned = true, open) }
        }
        profile?.let { name ->
            BackHandler { profile = null }
            PublicProfileScreen(account, name) { profile = null }
        }
    }
}

private const val REFRESH_MILLIS = 20_000L

@Composable
private fun LiveStrip(board: RankedLeaderboard) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
        .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = 0.92f), ArenaGlass.bottom.copy(alpha = 0.92f))), CircleShape)
        .border(0.9.dp, ArenaGlass.hairline, CircleShape)
        .padding(horizontal = 16.dp).semantics(mergeDescendants = true) {}.testTag("leaderboard.live"),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        OnlineDot(10.dp)
        FitText(if (board.online == 1) "1 player online" else "${board.online} players online", ArenaMenuStyle.font(14f, SfWeight.bold),
            color = ArenaMenuStyle.text, minimumScale = 0.8f)
        Spacer(Modifier.weight(1f))
        Text("${board.total} ranked · ${RankLadder.seasonName(board.season)}", Modifier.alpha(0.75f), color = ArenaMenuStyle.text,
            style = ArenaMenuStyle.font(12f, SfWeight.semibold), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The top three on their steps, on a glass panel of their own. `compact` (sideways) makes the steps and emblems shorter. */
@Composable
private fun Podium(top: List<RankedLeaderboard.Entry>, compact: Boolean, open: (RankedLeaderboard.Entry) -> Unit) {
    var up by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { up = true }
    Row(Modifier.arenaCard(12.dp).padding(top = 6.dp).testTag("leaderboard.podium"), horizontalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 10.dp),
        verticalAlignment = Alignment.Bottom) {
        ArenaProfileRules.podiumOrder(top).forEach { entry -> Box(Modifier.weight(1f)) { PodiumStep(entry, up, compact, open) } }
    }
}

@Composable
private fun PodiumStep(entry: RankedLeaderboard.Entry, up: Boolean, compact: Boolean, open: (RankedLeaderboard.Entry) -> Unit) {
    val place = entry.position
    val full = if (compact) when (place) { 1 -> 72.dp; 2 -> 56.dp; else -> 44.dp } else when (place) { 1 -> 112.dp; 2 -> 84.dp; else -> 66.dp }
    val emblem = if (compact) (if (place == 1) 58.dp else 46.dp) else (if (place == 1) 74.dp else 58.dp)
    val reduce = LaunchEnvironment.reduceMotion
    val height by animateDpAsState(if (up || reduce) full else 14.dp,
        if (reduce) tween(0) else tween(700, delayMillis = when (place) { 1 -> 300; 2 -> 150; else -> 0 }), label = "podium")
    val shape = RoundedCornerShape(topStart = 10.dp, topEnd = 10.dp)
    BrandPressable({ open(entry) }, Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = describe(entry); role = Role.Button }
        .testTag("leaderboard.row.${entry.username}")) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 6.dp)) {
            if (place == 1) SfImage("crown.fill", TavernPalette.brass, if (compact) 18.dp else 22.dp, Modifier.glow(TavernPalette.ember.copy(alpha = 0.7f), 6.dp, 22.dp))
            Box(contentAlignment = Alignment.Center) {
                if (place == 1) RankGlow(entry.rank.tier, if (compact) 86.dp else 110.dp)
                Box(contentAlignment = Alignment.BottomEnd) {
                    RankEmblem(entry.rank.tier, emblem)
                    if (entry.online) Box(Modifier.padding(4.dp)) { OnlineDot(12.dp) }
                }
            }
            FitText(entry.username, sf(if (place == 1) (if (compact) 14f else 15f) else (if (compact) 12f else 13f), SfWeight.black, SfDesign.SERIF),
                color = ArenaMenuStyle.text, minimumScale = 0.6f)
            FitText(entry.title ?: entry.rank.title, sf(if (compact) 10f else 11f, SfWeight.regular, SfDesign.SERIF)
                .copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic), Modifier.alpha(0.8f), color = ArenaMenuStyle.text, minimumScale = 0.7f)
            // The step: dark glass lit with gold from its top edge, its place in gold; the same even rim on every step.
            Box(Modifier.fillMaxWidth().height(height).clip(shape)
                .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)))
                .background(Brush.verticalGradient(listOf(ArenaMenuStyle.gold.copy(alpha = if (place == 1) 0.24f else 0.13f), Color.Transparent)))
                .border(if (entry.you) 2.5.dp else 1.2.dp, if (entry.you) Brush.linearGradient(listOf(ArenaMenuStyle.gold, ArenaMenuStyle.gold)) else ArenaGlass.hairline, shape),
                contentAlignment = Alignment.TopCenter) {
                Text("$place", Modifier.padding(top = if (compact) 6.dp else 8.dp),
                    style = sf(if (place == 1) (if (compact) 28f else 34f) else (if (compact) 22f else 26f), SfWeight.black, SfDesign.SERIF).copy(brush = brassFill))
            }
        }
    }
}

@Composable
private fun BoardRow(entry: RankedLeaderboard.Entry, move: Int?, shimmerPhase: Float, pinned: Boolean, open: (RankedLeaderboard.Entry) -> Unit) {
    val rank = entry.rank
    val mythic = rank.tier == RankTier.MYTHIC
    val shape = RoundedCornerShape(10.dp)
    Row(Modifier.fillMaxWidth()
        .glow(if (mythic) ArenaMenuStyle.gold.copy(alpha = 0.3f) else Color.Black.copy(alpha = if (pinned) 0.6f else 0.35f), if (pinned) 10.dp else 5.dp, 10.dp)
        .clip(shape)
        .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = 0.94f), ArenaGlass.bottom.copy(alpha = 0.94f))))
        .background(Brush.horizontalGradient(listOf(ArenaMenuStyle.gold.copy(alpha = if (entry.you) 0.16f else 0.04f), Color.Transparent)))
        .border(if (entry.you) 2.dp else 1.dp, if (entry.you) ArenaMenuStyle.gold else Color.White.copy(alpha = 0.12f), shape)
        .mythicShimmer(mythic, shimmerPhase)
        .clickable { open(entry) }
        .semantics(mergeDescendants = true) { contentDescription = describe(entry); role = Role.Button }
        .testTag(if (pinned) "leaderboard.me" else "leaderboard.row.${entry.username}")
        .padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${entry.position}", Modifier.widthIn(min = 34.dp), style = sf(17f, SfWeight.black, SfDesign.SERIF).copy(brush = brassFill, fontFeatureSettings = "tnum"))
        Box(contentAlignment = Alignment.BottomEnd) {
            RankEmblem(rank.tier, 40.dp)
            if (entry.online) OnlineDot(9.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(entry.username, Modifier.weight(1f, fill = false), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(16f, SfWeight.black),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (entry.you) TavernTag("YOU", leather = true)
            }
            Text(entry.title?.let { "${rank.title} · $it" } ?: rank.title, Modifier.alpha(0.75f), color = ArenaMenuStyle.text,
                style = ArenaMenuStyle.font(12f, SfWeight.regular), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            AnimatedVisibility(move != null, enter = scaleIn() + fadeIn()) {
                val m = move ?: 0
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                    val tint = if (m > 0) ArenaMenuStyle.win else ArenaMenuStyle.loss
                    Text(if (m > 0) "▲" else "▼", color = tint, style = sf(8f, SfWeight.black))
                    Text("${kotlin.math.abs(m)}", color = tint, style = ArenaMenuStyle.font(11f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
                }
            }
            Text("${entry.wins}–${entry.losses}", Modifier.alpha(0.85f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
            if (!mythic) RankPips(rank.pips, rank.tier, 7.dp)
        }
    }
}

@Composable
private fun BoardNote(text: String, icon: String, tag: String) {
    Row(Modifier.leatherCard().testTag(tag), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SfImage(icon, TavernPalette.brass, 16.dp)
        Text(text, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.semibold))
    }
}

private fun describe(entry: RankedLeaderboard.Entry): String = buildList {
    add("Number ${entry.position}"); add(entry.username); add(entry.rank.title)
    entry.title?.let(::add)
    if (entry.online) add("online")
    add("${entry.wins} wins, ${entry.losses} losses")
    if (entry.you) add("you")
}.joinToString(", ")
