package io.magicmobile.android.ranked

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.RankedLeaderboard
import io.magicmobile.android.game.SeasonRecord
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

// Port of Ranked/RankedHallViews.swift: the Ranked Hall and the live leaderboard.

private val hallInk = TavernPalette.ink
private val hallAccent = rgb(0.74, 0.46, 0.16)
private val brassFill = Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22)))
private val darkBrassInk = rgb(0.25, 0.12, 0.04)
private val onlineGreen = rgb(0.45, 0.92, 0.45)

/** Ranked's front room: your rank card, Play Ranked, the live leaderboard and your past seasons. */
@Composable
fun RankedHallScreen(account: PlayerAccount, rank: RankState, play: () -> Unit, leaderboard: () -> Unit, profile: () -> Unit, back: () -> Unit) {
    var teaser by remember { mutableStateOf<RankedLeaderboard?>(null) }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true; teaser = account.rankedLeaderboard(RankedLeaderboard.Scope.EVERYONE, 3) }
    val tier = rank.position.tier
    val appeared = remember { Any() }
    TavernLobbyPage("Ranked Hall", back, backTitle = "Play") {
        HallEntrance(shown, 0) {
            Column(Modifier.leatherCard().testTag("ranked.hall.standing"), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(contentAlignment = Alignment.Center) {
                    RankGlow(tier, 190.dp)
                    RankBadge(rank.position, 132.dp, showsPips = true, showsTitle = true, spinKey = appeared)
                }
                val left = RankLadder.seasonEnd(rank.season)?.let { maxOf(0L, (it - System.currentTimeMillis() + 86_399_999) / 86_400_000) }
                Text("Season: ${RankLadder.seasonName(rank.season)}" + (left?.let { if (it == 1L) " · 1 day left" else " · $it days left" } ?: ""),
                    color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    HallStat("Wins", "${rank.wins}"); HallStat("Losses", "${rank.losses}"); HallStat("Peak", rank.peak.title)
                    teaser?.me?.let { HallStat("Place", "#${it.position}") }
                }
                TavernPlaqueButton("Your profile", profile, Modifier.testTag("ranked.hall.profile"), kind = TavernButtonKind.SECONDARY, systemImage = "person.crop.circle")
            }
        }
        HallEntrance(shown, 80) {
            HallChoice("Play Ranked", "Pick your deck, then face a player near your rank or an AI. ${tier.label} allows decks up to Bracket ${tier.maxDeckBracket}.",
                "ranked.hall.play", GameSound.MENU_PLAY, play, icon = { SfImage("shield.lefthalf.filled", TavernPalette.brass, 26.dp) })
        }
        HallEntrance(shown, 160) {
            HallChoice("Leaderboard", "This season's top players, live, with who's online now.", "ranked.hall.leaderboard", GameSound.UI_OPEN, leaderboard,
                icon = { SfImage("trophy.fill", TavernPalette.brass, 24.dp) }) {
                val t = teaser
                if (t != null && t.entries.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) { t.entries.take(3).forEach { RankEmblem(it.rank.tier, 30.dp) } }
                    if (t.online > 0) {
                        OnlineDot(8.dp)
                        Text(if (t.online == 1) "1 online now" else "${t.online} online now", color = hallInk, style = sf(12f, SfWeight.bold, SfDesign.SERIF))
                    }
                    Text("${t.total} ranked", color = hallInk.copy(alpha = 0.7f), style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 1, softWrap = false)
                }
            }
        }
        HallEntrance(shown, 240) {
            Column(Modifier.leatherCard().testTag("ranked.hall.seasons"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("PAST SEASONS", color = TavernPalette.brass, style = sf(11f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f))
                if (rank.history.isEmpty()) Text("This is your first season. Where you finish it starts your history here.",
                    color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(14f, SfWeight.regular, SfDesign.SERIF))
                else Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    rank.history.take(6).forEach { SeasonChip(it) }
                }
            }
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
    Column(Modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = TavernPalette.parchment, style = sf(18f, SfWeight.black, SfDesign.SERIF))
        Text(title.uppercase(), color = TavernPalette.parchment.copy(alpha = 0.7f), style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.2f))
    }
}

@Composable
private fun HallChoice(title: String, detail: String, tag: String, sound: GameSound, action: () -> Unit, icon: @Composable () -> Unit,
                       footer: @Composable () -> Unit = {}) {
    Row(Modifier.clickable { GameAudio.play(sound); action() }.testTag(tag).semantics(mergeDescendants = true) { contentDescription = "$title. $detail" }
        .parchmentCard(), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(64.dp).background(TavernPalette.leather.copy(alpha = 0.9f), CircleShape).border(2.dp, TavernPalette.brassLine, CircleShape),
            contentAlignment = Alignment.Center) { icon() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(title, color = hallInk, style = sf(21f, SfWeight.black, SfDesign.SERIF))
            Text(detail, color = hallInk.copy(alpha = 0.78f), style = sf(14f, SfWeight.medium, SfDesign.SERIF))
            footer()
        }
        SfImage("chevron.right", hallAccent, 15.dp)
    }
}

@Composable
private fun SeasonChip(record: SeasonRecord) {
    Column(Modifier.defaultMinSize(minWidth = 92.dp).background(Color.Black.copy(alpha = 0.25f), RoundedCornerShape(10.dp))
        .border(1.dp, TavernPalette.brass.copy(alpha = 0.5f), RoundedCornerShape(10.dp)).padding(horizontal = 12.dp, vertical = 8.dp)
        .semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        RankEmblem(record.final.tier, 44.dp)
        Text(record.final.title, color = TavernPalette.parchment, style = sf(12f, SfWeight.black, SfDesign.SERIF), maxLines = 1)
        Text(RankLadder.seasonName(record.season), color = TavernPalette.parchment.copy(alpha = 0.75f), style = sf(10f, SfWeight.semibold, SfDesign.SERIF))
        Text("${record.wins}–${record.losses}", color = TavernPalette.parchment.copy(alpha = 0.85f), style = sf(11f, SfWeight.bold, SfDesign.SERIF))
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

/** A band of ember light sweeping across Mythic rows every few seconds. */
private fun Modifier.mythicShimmer(active: Boolean, phase: Float): Modifier = if (!active || LaunchEnvironment.reduceMotion) this else drawWithContent {
    drawContent()
    val band = size.width * 0.4f
    val x = -band + (size.width + band * 2) * phase
    drawRect(Brush.horizontalGradient(listOf(Color.Transparent, RankTier.MYTHIC.tint.copy(alpha = 0.35f), Color.White.copy(alpha = 0.28f), Color.Transparent),
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
 * list. Refreshes every 20 seconds while open and the app is in front.
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

    Box(Modifier.fillMaxSize()) {
        // Inside the Arena menu shell the room is already drawn behind the page.
        if (!io.magicmobile.android.menus.LocalArenaMenuBackdrop.current) BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            Box(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) { TavernScreenHeader("Leaderboard", back, "Ranked Hall") }
            val loaded = (load as? BoardLoad.Loaded)?.board
            LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("lobby.scroll"), horizontalAlignment = Alignment.CenterHorizontally,
                contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item(key = "scope") { Box(Modifier.widthIn(max = 640.dp)) { ScopePicker(scope) { scope = it } } }
                when (val state = load) {
                    BoardLoad.Loading -> item(key = "loading") { Box(Modifier.widthIn(max = 640.dp)) { Box(Modifier.leatherCard()) { SocialWaiting("Gathering the standings…") } } }
                    BoardLoad.Offline -> item(key = "offline") {
                        BoardNote("The leaderboard needs your profile and a connection. Sign in from your profile, then come back.", "wifi.exclamationmark", "leaderboard.offline")
                    }
                    is BoardLoad.Loaded -> {
                        val board = state.board
                        item(key = "live") { Box(Modifier.widthIn(max = 640.dp)) { LiveStrip(board) } }
                        if (board.entries.isEmpty()) item(key = "empty") {
                            BoardNote(if (scope == RankedLeaderboard.Scope.FRIENDS) "None of your friends has played ranked this season yet. Challenge one from Friends."
                                else "Nobody has played ranked this season yet. Win a game to take the top spot.", "trophy.fill", "leaderboard.empty")
                        } else {
                            item(key = "podium") { Box(Modifier.widthIn(max = 640.dp)) { Podium(board.entries.take(3), open) } }
                            items(board.entries.drop(3), key = { it.username }) { entry ->
                                Box(Modifier.widthIn(max = 640.dp).animateItem()) { BoardRow(entry, moves[entry.username], shimmerPhase, pinned = false, open) }
                            }
                        }
                    }
                }
                if (loaded?.pinnedMe != null) item(key = "pinnedSpace") { Spacer(Modifier.height(72.dp)) }
            }
        }
        val me = (load as? BoardLoad.Loaded)?.board?.pinnedMe
        if (me != null) {
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
private fun ScopePicker(scope: RankedLeaderboard.Scope, select: (RankedLeaderboard.Scope) -> Unit) {
    Row(Modifier.fillMaxWidth().tavernFill(TavernMaterial.LEATHER, CircleShape).tavernCapsuleRim(thin = true).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        RankedLeaderboard.Scope.entries.forEach { option ->
            val selected = option == scope
            Box(Modifier.weight(1f).height(40.dp).clip(CircleShape).then(if (selected) Modifier.background(brassFill, CircleShape) else Modifier)
                .clickable { if (!selected) { GameAudio.play(GameSound.UI_TAP); select(option) } }
                .semantics { this.selected = selected; role = Role.Tab }.testTag("leaderboard.scope.${option.raw}"), contentAlignment = Alignment.Center) {
                Text(if (option == RankedLeaderboard.Scope.EVERYONE) "Everyone" else "Friends",
                    color = if (selected) darkBrassInk else TavernPalette.parchment.copy(alpha = 0.8f), style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
            }
        }
    }
}

@Composable
private fun LiveStrip(board: RankedLeaderboard) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).tavernFill(TavernMaterial.LEATHER, CircleShape).tavernCapsuleRim(thin = true)
        .padding(horizontal = 16.dp).semantics(mergeDescendants = true) {}.testTag("leaderboard.live"),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        OnlineDot(10.dp)
        Text(if (board.online == 1) "1 player online" else "${board.online} players online", color = TavernPalette.parchment,
            style = sf(14f, SfWeight.bold, SfDesign.SERIF))
        Spacer(Modifier.weight(1f))
        Text("${board.total} ranked · ${RankLadder.seasonName(board.season)}", color = TavernPalette.parchment.copy(alpha = 0.75f),
            style = sf(12f, SfWeight.semibold, SfDesign.SERIF), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Podium(top: List<RankedLeaderboard.Entry>, open: (RankedLeaderboard.Entry) -> Unit) {
    val order = when (top.size) { 3 -> listOf(top[1], top[0], top[2]); 2 -> listOf(top[1], top[0]); else -> top }
    var up by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { up = true }
    Row(Modifier.fillMaxWidth().padding(top = 6.dp).testTag("leaderboard.podium"), horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom) {
        order.forEach { entry -> Box(Modifier.weight(1f)) { PodiumStep(entry, up, open) } }
    }
}

@Composable
private fun PodiumStep(entry: RankedLeaderboard.Entry, up: Boolean, open: (RankedLeaderboard.Entry) -> Unit) {
    val place = entry.position
    val full = when (place) { 1 -> 112.dp; 2 -> 84.dp; else -> 66.dp }
    val reduce = LaunchEnvironment.reduceMotion
    val height by animateDpAsState(if (up || reduce) full else 14.dp,
        if (reduce) tween(0) else tween(700, delayMillis = when (place) { 1 -> 300; 2 -> 150; else -> 0 }), label = "podium")
    val shape = RoundedCornerShape(topStart = 10.dp, topEnd = 10.dp)
    Column(Modifier.fillMaxWidth().clickable { open(entry) }.semantics(mergeDescendants = true) { contentDescription = describe(entry); role = Role.Button }
        .testTag("leaderboard.row.${entry.username}"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (place == 1) SfImage("crown.fill", TavernPalette.brass, 22.dp, Modifier.glow(TavernPalette.ember.copy(alpha = 0.7f), 6.dp, 22.dp))
        Box(contentAlignment = Alignment.Center) {
            if (place == 1) RankGlow(entry.rank.tier, 110.dp)
            Box(contentAlignment = Alignment.BottomEnd) {
                RankEmblem(entry.rank.tier, if (place == 1) 74.dp else 58.dp)
                if (entry.online) Box(Modifier.padding(4.dp)) { OnlineDot(12.dp) }
            }
        }
        Text(entry.username, color = TavernPalette.parchment, style = sf(if (place == 1) 15f else 13f, SfWeight.black, SfDesign.SERIF), maxLines = 1,
            overflow = TextOverflow.Ellipsis)
        Text(entry.title ?: entry.rank.title, color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(11f, SfWeight.regular, SfDesign.SERIF),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Box(Modifier.fillMaxWidth().height(height).clip(shape)
            .tavernFill(TavernMaterial.LEATHER, shape, overlayBrush = Brush.verticalGradient(listOf(entry.rank.tier.tint.copy(alpha = 0.35f), Color.Transparent)))
            .border(if (entry.you) 2.5.dp else 1.5.dp, if (entry.you) TavernPalette.brass else TavernPalette.brass.copy(alpha = 0.6f), shape),
            contentAlignment = Alignment.TopCenter) {
            Text("$place", Modifier.padding(top = 8.dp), style = sf(if (place == 1) 34f else 26f, SfWeight.black, SfDesign.SERIF).copy(brush = brassFill))
        }
    }
}

@Composable
private fun BoardRow(entry: RankedLeaderboard.Entry, move: Int?, shimmerPhase: Float, pinned: Boolean, open: (RankedLeaderboard.Entry) -> Unit) {
    val rank = entry.rank
    val mythic = rank.tier == RankTier.MYTHIC
    val shape = RoundedCornerShape(10.dp)
    Row(Modifier.fillMaxWidth()
        .glow(if (mythic) RankTier.MYTHIC.tint.copy(alpha = 0.35f) else Color.Black.copy(alpha = if (pinned) 0.6f else 0.35f), if (pinned) 10.dp else 5.dp, 10.dp)
        .clip(shape)
        .tavernFill(TavernMaterial.LEATHER, shape, overlayBrush = Brush.horizontalGradient(listOf(rank.tier.tint.copy(alpha = if (entry.you) 0.22f else 0.08f), Color.Transparent)))
        .border(if (entry.you) 2.dp else 1.dp, if (entry.you) TavernPalette.brass else TavernPalette.brass.copy(alpha = 0.4f), shape)
        .mythicShimmer(mythic, shimmerPhase)
        .clickable { open(entry) }
        .semantics(mergeDescendants = true) { contentDescription = describe(entry); role = Role.Button }
        .testTag(if (pinned) "leaderboard.me" else "leaderboard.row.${entry.username}")
        .padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${entry.position}", Modifier.widthIn(min = 34.dp), style = sf(17f, SfWeight.black, SfDesign.SERIF).copy(brush = brassFill))
        Box(contentAlignment = Alignment.BottomEnd) {
            RankEmblem(rank.tier, 40.dp)
            if (entry.online) OnlineDot(9.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(entry.username, Modifier.weight(1f, fill = false), color = TavernPalette.parchment, style = sf(16f, SfWeight.black, SfDesign.SERIF),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (entry.you) TavernTag("YOU", leather = true)
            }
            Text(entry.title?.let { "${rank.title} · $it" } ?: rank.title, color = TavernPalette.parchment.copy(alpha = 0.75f),
                style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            AnimatedVisibility(move != null, enter = scaleIn() + fadeIn()) {
                val m = move ?: 0
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                    val tint = if (m > 0) rgb(0.5, 0.9, 0.45) else rgb(1.0, 0.55, 0.45)
                    Text(if (m > 0) "▲" else "▼", color = tint, style = sf(8f, SfWeight.black))
                    Text("${kotlin.math.abs(m)}", color = tint, style = sf(11f, SfWeight.heavy, SfDesign.SERIF))
                }
            }
            Text("${entry.wins}–${entry.losses}", color = TavernPalette.parchment.copy(alpha = 0.85f), style = sf(13f, SfWeight.bold, SfDesign.SERIF))
            if (!mythic) RankPips(rank.pips, rank.tier, 7.dp)
        }
    }
}

@Composable
private fun BoardNote(text: String, icon: String, tag: String) {
    Row(Modifier.widthIn(max = 640.dp).leatherCard().testTag(tag), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SfImage(icon, TavernPalette.brass, 16.dp)
        Text(text, color = TavernPalette.parchment, style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
    }
}

private fun describe(entry: RankedLeaderboard.Entry): String = buildList {
    add("Number ${entry.position}"); add(entry.username); add(entry.rank.title)
    entry.title?.let(::add)
    if (entry.online) add("online")
    add("${entry.wins} wins, ${entry.losses} losses")
    if (entry.you) add("you")
}.joinToString(", ")
