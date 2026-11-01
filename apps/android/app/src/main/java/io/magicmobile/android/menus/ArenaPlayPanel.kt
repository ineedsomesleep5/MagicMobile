package io.magicmobile.android.menus

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.AIDeck
import io.magicmobile.android.game.AIDeckPool
import io.magicmobile.android.game.ArenaBoxGeometry
import io.magicmobile.android.game.ArenaFriendWay
import io.magicmobile.android.game.ArenaPlayAction
import io.magicmobile.android.game.ArenaPlayMode
import io.magicmobile.android.game.ArenaPlayRules
import io.magicmobile.android.game.ArenaPlayTab
import io.magicmobile.android.game.ArenaRecentGame
import io.magicmobile.android.game.CommanderBracket
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankedMatchmaker
import io.magicmobile.android.ranked.RankBadge
import io.magicmobile.android.ranked.RankEmblem
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LocalBrandAmbientMotion
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.delay

/*
 * Port of Menus/ArenaPlayPanel.swift: Arena's Play panel (Caleb, 2026-10-22). The room darkened, your decks as boxes on the
 * left, and on the right the blade, lit along its seam, with the tabs, the ways to play, their options and the Play plaque.
 * In portrait the blade is a sheet along the bottom. A search waits inside the blade: Play turns into Cancel under a timer.
 */

/** A shelf of deck boxes in the picker. `offersNewDeck`: the shelf starts with a "New deck" box. */
data class ArenaDeckSection(val id: String, val title: String, val decks: List<ArenaDeckBoxModel>, val offersNewDeck: Boolean = false)

/** Everything the Play panel shows and does. The root view owns the state; the panel only draws it. */
class ArenaPlayPanelModel(
    val sections: List<ArenaDeckSection>,
    val selectedDeckID: String,
    val selectDeck: (String) -> Unit,
    val deckBracket: CommanderBracket?,
    val mode: ArenaPlayMode,
    val setMode: (ArenaPlayMode) -> Unit,
    val tab: ArenaPlayTab,
    val setTab: (ArenaPlayTab) -> Unit,
    // Quick Match
    val quickBracket: Int,
    val setQuickBracket: (Int) -> Unit,
    val quickDeckID: String,
    val setQuickDeckID: (String) -> Unit,
    val quickSkill: Int,
    val setQuickSkill: (Int) -> Unit,
    /** "easy", "medium" or "hard" (the AI's deck by Power, its skill set with it), or "advanced" (the controls below). */
    val quickLevel: String,
    val setQuickLevel: (String) -> Unit,
    val startingPlayer: String,
    val setStartingPlayer: (String) -> Unit,
    val aiPool: List<AIDeck>,
    // Ranked
    val rank: RankState,
    val canSearchPeople: Boolean,
    /** A ranked search running, else null. */
    val search: RankedMatchmaker.Phase?,
    /** A friend's challenge on its way: their name. */
    val waitingFor: String?,
    // Custom
    val playWithFriends: Boolean,
    val setPlayWithFriends: (Boolean) -> Unit,
    val mayStart: Boolean,
    val status: String?,
    val recent: List<ArenaRecentGame>,
    val close: () -> Unit,
    val newDeck: () -> Unit,
    val explainBracket: () -> Unit,
    val startQuick: () -> Unit,
    val findRanked: () -> Unit,
    val cancelSearch: () -> Unit,
    val playAINow: () -> Unit,
    val cancelChallenge: () -> Unit,
    val openCustom: () -> Unit,
    val rankedHall: () -> Unit,
    val leaderboard: () -> Unit,
    val challengeFriend: () -> Unit,
    val hostOnline: () -> Unit,
    val joinOnline: () -> Unit,
    val chooseRecent: (ArenaRecentGame) -> Unit,
) {
    val quickResolvedBracket: Int get() = ArenaPlayRules.quickResolvedBracket(quickBracket, deckBracket)
    val rankedEligible: Boolean get() = ArenaPlayRules.rankedEligible(deckBracket, rank.deckLimitTier)
    val busy: Boolean get() = search != null || waitingFor != null
    val selectedDeck: ArenaDeckBoxModel? get() = sections.asSequence().flatMap { it.decks }.firstOrNull { it.id == selectedDeckID }
}

@Composable
fun ArenaPlayPanel(model: ArenaPlayPanelModel, compact: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.78f)).testTag("play.panel")) {
        if (compact) {
            // The blade's glass runs on under the home bar; its controls keep 392 pt above it.
            val homeBar = WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom).asPaddingValues().calculateBottomPadding()
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxWidth()) { ArenaDeckPicker(model, compact = true); SearchScrim(model.busy) }
                ArenaPlayBlade(model, compact = true, Modifier.fillMaxWidth().height(392.dp + homeBar))
            }
        } else {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxHeight().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Start))) {
                    ArenaDeckPicker(model, compact = false); SearchScrim(model.busy)
                }
                ArenaPlayBlade(model, compact = false, Modifier.width(248.dp).fillMaxHeight())
            }
        }
    }
}

/** A search dims the whole deck side evenly, over solid boxes. */
@Composable
private fun SearchScrim(busy: Boolean) {
    if (busy) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)))
}

// MARK: - Deck picker

/** The left of the panel: the way to play in a few words, and every deck as a box, by shelf. */
@Composable
private fun ArenaDeckPicker(model: ArenaPlayPanelModel, compact: Boolean) {
    Column(Modifier.fillMaxSize().testTag("play.decks")) {
        PickerHeader(model, compact)
        if (model.tab == ArenaPlayTab.RECENT) ArenaRecentShelf(model, compact) else DeckShelves(model, compact)
    }
}

@Composable
private fun PickerHeader(model: ArenaPlayPanelModel, compact: Boolean) {
    Row(Modifier.fillMaxWidth().padding(start = if (compact) 16.dp else 24.dp, end = if (compact) 8.dp else 12.dp, top = if (compact) 10.dp else 12.dp, bottom = 4.dp),
        verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(ArenaPlayRules.heading(model.tab, model.mode), Modifier.semantics { heading() }, color = ArenaMenuStyle.text,
                style = ArenaMenuStyle.font(if (compact) 22f else 24f, SfWeight.bold).arenaShadow())
            // The table's size only on Find Match, where the mode decides it; upright the line keeps its place on every tab.
            val showsRules = model.tab == ArenaPlayTab.FIND
            val rules = ArenaPlayRules.rulesLine(model.mode)
            if (compact) ArenaCaps(rules, 9.5f, Modifier.alpha(if (showsRules) 1f else 0f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!compact && showsRules) ArenaCaps(rules, 9.5f)
                model.deckBracket?.let { bracket ->
                    BrandPressable(model.explainBracket, Modifier.defaultMinSize(minHeight = 44.dp).testTag("play.deck.bracket")
                        .semantics(mergeDescendants = true) { contentDescription = "${bracket.title}. Bracket details" }) {
                        Row(Modifier.height(20.dp).background(Color.White.copy(alpha = 0.06f), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape)
                            .padding(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(bracket.title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(10.5f, SfWeight.bold), maxLines = 1)
                            SfImage("info.circle", ArenaMenuStyle.gold, 10.dp)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        ArenaCloseButton(model.close, identifier = "lobby.back", enabled = !model.busy)
    }
}

/** One row of boxes on a shelf (null is the "New deck" box). */
private data class ShelfRow(val key: String, val section: ArenaDeckSection, val index: Int, val items: List<ArenaDeckBoxModel?>)

@Composable
private fun DeckShelves(model: ArenaPlayPanelModel, compact: Boolean) {
    var collapsed by rememberSaveable { mutableStateOf(emptyList<String>()) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val (columns, boxWidthValue) = ArenaPlayRules.deckGrid(maxWidth.value, compact)
        val boxWidth = boxWidthValue.dp
        val gap = if (compact) 10.dp else 12.dp
        val rise = ArenaBoxGeometry(boxWidthValue).rise.dp
        val listState = rememberLazyListState()
        // The rows by shelf: each shelf's heading, then its boxes in rows (rows leave room for an open box's lid to rise).
        val rows = remember(model.sections, collapsed, columns) {
            model.sections.flatMap { section ->
                val heading = listOf<Any>(section)
                if (section.id in collapsed) heading else {
                    val boxes: List<ArenaDeckBoxModel?> = (if (section.offersNewDeck) listOf(null) else emptyList<ArenaDeckBoxModel?>()) + section.decks
                    heading + boxes.chunked(columns).mapIndexed { i, chunk -> ShelfRow("row-${section.id}-$i", section, i, chunk) }
                }
            }
        }
        fun rowOf(deckID: String): Int = rows.indexOfFirst { it is ShelfRow && it.items.any { box -> box?.id == deckID } }
        // Once the shelves are laid out, bring the chosen deck's shelf to the top, as iOS does (with no decks of your own that is
        // Precons, over the empty My Decks shelf). The precons can arrive after the panel opens, so it waits for the shelf to exist.
        val landingRow = ArenaPlayRules.landingShelf(model.sections.map { section -> section.id to section.decks.map { it.id } }, model.selectedDeckID)?.let { id -> rows.indexOfFirst { it is ArenaDeckSection && it.id == id } } ?: -1
        var landed by remember { mutableStateOf(false) }
        LaunchedEffect(landingRow) {
            if (landed || landingRow < 0) return@LaunchedEffect
            delay(250)
            landed = true
            if (landingRow > 0) listState.scrollToItem(landingRow)
        }
        LaunchedEffect(model.selectedDeckID) {
            val row = rowOf(model.selectedDeckID)
            if (row >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == row }) listState.animateScrollToItem(row)
        }
        LazyColumn(Modifier.fillMaxSize().arenaScrollFade(30.dp), listState,
            contentPadding = PaddingValues(start = if (compact) 16.dp else 24.dp, end = if (compact) 16.dp else 24.dp, bottom = 20.dp)) {
            rows.forEach { row ->
                when (row) {
                    is ArenaDeckSection -> item(key = "shelf-${row.id}") {
                        ArenaSectionHeader(row.title, Modifier.padding(top = 6.dp), row.decks.size, row.id in collapsed) {
                            collapsed = if (row.id in collapsed) collapsed - row.id else collapsed + row.id
                        }
                    }
                    is ShelfRow -> item(key = row.key) {
                        Row(Modifier.padding(top = if (row.index == 0) rise + 12.dp else rise + 8.dp, bottom = if (row.index == 0) 0.dp else 0.dp),
                            horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.Top) {
                            row.items.forEach { deck ->
                                if (deck == null) BrandPressable(model.newDeck, Modifier.testTag("play.newDeck")) { ArenaNewDeckBox(width = boxWidth) }
                                else DeckButton(model, deck, boxWidth)
                            }
                        }
                    }
                }
            }
            item(key = "foot") { Spacer(Modifier.height(10.dp)) }
        }
    }
}

@Composable
private fun DeckButton(model: ArenaPlayPanelModel, deck: ArenaDeckBoxModel, width: Dp) {
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.selectDeck(deck.id) }, Modifier.testTag("play.deck.${deck.id}"), enabled = !model.busy) {
        ArenaDeckBox(deck, selected = deck.id == model.selectedDeckID, width = width)
    }
}

// MARK: - Recently played

/**
 * Recently Played's left side, as Arena's: a tall tile for each recent table (its deck's art, the way you played, whom you
 * met), or one quiet line when there are none (the blade's plaque leads to Find Match).
 */
@Composable
private fun ArenaRecentShelf(model: ArenaPlayPanelModel, compact: Boolean) {
    if (model.recent.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = if (compact) 0.dp else 40.dp).testTag("recent.empty")
            .semantics(mergeDescendants = true) { }, horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
            ArenaEmblem("clock.arrow.circlepath", 30.dp)
            Text("No tables yet", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(17f, SfWeight.bold))
        }
        return
    }
    if (compact) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            model.recent.forEach { RecentTile(model, it, Modifier.width(168.dp)) }
        }
    } else {
        LazyVerticalGrid(GridCells.Adaptive(150.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 24.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(model.recent, key = { it.id }) { RecentTile(model, it, Modifier.widthIn(max = 190.dp)) }
        }
    }
}

@Composable
private fun RecentTile(model: ArenaPlayPanelModel, game: ArenaRecentGame, modifier: Modifier) {
    val chosen = ArenaPlayRules.isChosen(game, model.selectedDeckID, model.mode)
    val shape = RoundedCornerShape(10.dp)
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.chooseRecent(game) }, modifier.testTag("recent.${game.id}")
        .semantics(mergeDescendants = true) { selected = chosen }) {
        Column(Modifier.fillMaxWidth()
            .glow(if (chosen) rgb(1.0, 0.78, 0.36).copy(alpha = 0.5f) else Color.Transparent, 8.dp, 10.dp)
            .background(Color.Black.copy(alpha = 0.45f), shape)
            .border(if (chosen) 1.6.dp else 0.8.dp, if (chosen) rgb(1.0, 0.88, 0.56) else ArenaGlass.hairlineTop.copy(alpha = 0.5f), shape)
            .padding(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(Modifier.fillMaxWidth().height(120.dp).clip(shape)) {
                ArenaArt(game.commander ?: "", game.colors, Modifier.fillMaxSize())
                ArenaPips(game.colors, 14.dp, Modifier.align(Alignment.BottomStart).padding(8.dp))
            }
            ArenaCaps(game.modeTitle, 9f)
            Text(game.deckName, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.bold), maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(game.detail, Modifier.weight(1f), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium), maxLines = 1)
                game.won?.let { won ->
                    Text(if (won) "Won" else "Lost", color = if (won) ArenaMenuStyle.win else ArenaMenuStyle.loss, style = ArenaMenuStyle.font(11f, SfWeight.bold))
                }
            }
        }
    }
}

// MARK: - Blade

/** The right of the panel (the bottom in portrait): tabs, the ways to play, options, and the Play plaque. */
@Composable
private fun ArenaPlayBlade(model: ArenaPlayPanelModel, compact: Boolean, modifier: Modifier) {
    var friendWayRaw by rememberSaveable { mutableStateOf(ArenaFriendWay.CHALLENGE.raw) }
    val friendWay = ArenaFriendWay.entries.firstOrNull { it.raw == friendWayRaw } ?: ArenaFriendWay.CHALLENGE
    val shape = RoundedCornerShape(topStart = if (compact) 18.dp else 0.dp, topEnd = if (compact) 18.dp else 0.dp)
    // Only the glass takes the rounded shape: the seam's glow spills past the blade's edge.
    Box(modifier.background(Brush.verticalGradient(listOf(rgb(0.085, 0.085, 0.11).copy(alpha = 0.98f), rgb(0.035, 0.035, 0.047).copy(alpha = 0.99f))), shape)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing.only(if (compact) WindowInsetsSides.Bottom else WindowInsetsSides.Bottom + WindowInsetsSides.End))) {
            BladeTabs(model, compact)
            if (model.tab == ArenaPlayTab.FIND) BladeModes(model, compact)
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).testTag("lobby.scroll").padding(horizontal = 14.dp).padding(bottom = 18.dp)) {
                when (model.tab) {
                    ArenaPlayTab.FIND -> when (model.mode) {
                        ArenaPlayMode.QUICK -> QuickOptions(model)
                        ArenaPlayMode.RANKED -> RankedOptions(model)
                        ArenaPlayMode.CUSTOM -> CustomOptions(model)
                    }
                    ArenaPlayTab.FRIENDS -> {
                        ArenaCaps("With friends", 9.5f, Modifier.padding(top = 8.dp, bottom = 2.dp))
                        ArenaFriendWay.entries.forEach { way ->
                            ArenaOptionRow(way.title, { friendWayRaw = way.raw }, selected = friendWay == way, identifier = "friends.${way.raw}")
                        }
                    }
                    ArenaPlayTab.RECENT -> RecentOptions(model)
                }
            }
            BladeFooter(model, friendWay, compact)
        }
        ArenaSeam(vertical = !compact, if (compact) Modifier.align(Alignment.TopCenter).fillMaxWidth() else Modifier.align(Alignment.CenterStart).fillMaxHeight())
    }
}

@Composable
private fun BladeTabs(model: ArenaPlayPanelModel, compact: Boolean) {
    Row(Modifier.fillMaxWidth().padding(top = if (compact) 4.dp else 0.dp).drawBehind {
        drawRect(ArenaGlass.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()), alpha = 0.35f)
    }) {
        ArenaPlayTab.entries.forEach { tab ->
            val on = model.tab == tab
            BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.setTab(tab) }, Modifier.weight(1f).height(if (compact) 50.dp else 56.dp)
                .alpha(if (model.busy) 0.5f else 1f).testTag("play.tab.${tab.raw}").semantics(mergeDescendants = true) { contentDescription = tab.title; selected = on },
                enabled = !model.busy) {
                Box(Modifier.fillMaxSize().background(if (on) Color.White.copy(alpha = 0.05f) else Color.Transparent)) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        ArenaEmblem(tab.symbol, 18.dp, on)
                        FitText(tab.title, ArenaMenuStyle.font(10f, SfWeight.semibold), color = if (on) Color.White else ArenaMenuStyle.dim, minimumScale = 0.75f)
                    }
                    ArenaTabBar(on, Modifier.align(Alignment.BottomCenter).padding(horizontal = 8.dp))
                }
            }
        }
    }
}

@Composable
private fun BladeModes(model: ArenaPlayPanelModel, compact: Boolean) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp).padding(top = 8.dp, bottom = 4.dp).alpha(if (model.busy) 0.4f else 1f),
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ArenaPlayMode.entries.forEach { mode ->
            val on = model.mode == mode
            val shape = RoundedCornerShape(10.dp)
            BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.setMode(mode) }, Modifier.weight(1f).testTag("play.${mode.raw}")
                .semantics(mergeDescendants = true) { contentDescription = mode.title; selected = on }, enabled = !model.busy) {
                Column(Modifier.fillMaxWidth().then(if (on) Modifier.background(Color.White.copy(alpha = 0.07f), shape).border(0.8.dp, ArenaGlass.hairline, shape) else Modifier)
                    .padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ArenaModeGem(mode, model.rank.shownPosition, on, if (compact) 34.dp else 40.dp)
                    Text(mode.title, color = if (on) Color.White else ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.semibold))
                }
            }
        }
    }
}

// MARK: Options

private val quickLevels = listOf("easy" to "Easy", "medium" to "Medium", "hard" to "Hard", "advanced" to "Advanced")

/**
 * Quick Match: Easy, Medium or Hard, then who goes first. Advanced adds the opponent's bracket as five gems, the opponent's
 * deck on one line and the AI's skill.
 */
@Composable
private fun ColumnScope.QuickOptions(model: ArenaPlayPanelModel) {
    val advanced = model.quickLevel == "advanced"
    ArenaCaps("Opponent · ${quickLevels.firstOrNull { it.first == model.quickLevel }?.second ?: "Medium"}", 9.5f, Modifier.padding(top = 6.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        quickLevels.forEach { (value, name) -> LevelGem(model, value, name, Modifier.weight(1f)) }
    }
    if (advanced) {
        val brackets = CommanderBracket.entries.filter { it != CommanderBracket.CEDH }
        val chosen = brackets.firstOrNull { it.level == model.quickBracket }
        val matched = ArenaPlayRules.matchedLabel(model.deckBracket)
        ArenaCaps(chosen?.let { "Bracket · ${it.label}" } ?: "Bracket · Match my deck", 9.5f, Modifier.padding(top = 6.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            BracketGem(model, "Match", 0, matched, Modifier.weight(1f))
            brackets.forEach { BracketGem(model, "${it.level}", it.level, it.label, Modifier.weight(1f)) }
        }
        OpponentDeckRow(model)
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (advanced) ArenaStepper("AI skill", model.quickSkill, 1..10, model.setQuickSkill, Modifier.weight(1f), identifier = "quick.skill", compact = true)
        else Spacer(Modifier.weight(1f))
        RollToggle(model)
    }
}

/** Easy, Medium, Hard or Advanced as a pill gem, gold when chosen (the bracket gems' look, wide enough for the word). */
@Composable
private fun LevelGem(model: ArenaPlayPanelModel, value: String, name: String, modifier: Modifier) {
    val on = model.quickLevel == value
    val shape = RoundedCornerShape(18.dp)
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.setQuickLevel(value) }, modifier.defaultMinSize(minHeight = 44.dp).testTag("quick.level.$value")
        .semantics { contentDescription = name; selected = on }) {
        Box(Modifier.fillMaxWidth().height(36.dp).glow(if (on) ArenaMenuStyle.gold.copy(alpha = 0.5f) else Color.Transparent, 5.dp, 18.dp)
            .background(if (on) ArenaMenuStyle.goldFill else Brush.verticalGradient(List(2) { Color.Black.copy(alpha = 0.45f) }), shape)
            .border(if (on) 1.4.dp else 0.9.dp, if (on) ArenaMenuStyle.metal else ArenaGlass.hairline, shape), contentAlignment = Alignment.Center) {
            FitText(name, ArenaMenuStyle.font(11f, SfWeight.bold), color = if (on) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.text, minimumScale = 0.7f)
        }
    }
}

/** The opponent's deck as one of the blade's rows: a tap lists the decks at that bracket in the glass pop-over, the chosen one with a gold diamond. */
@Composable
private fun OpponentDeckRow(model: ArenaPlayPanelModel) {
    val pool = AIDeckPool.pool(model.quickResolvedBracket, model.aiPool)
    val chosen = pool.firstOrNull { it.id == model.quickDeckID }
    TavernMenu(Modifier.fillMaxWidth().testTag("quick.deck"), edge = TavernMenuEdge.BELOW, scrollHeight = 300.dp,
        contentDescription = "Opponent deck, ${chosen?.name ?: "Surprise me"}",
        label = {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).drawBehind {
                val line = 1.dp.toPx()
                drawRect(Color.White.copy(alpha = 0.07f), size = Size(size.width, line))
                drawRect(Color.White.copy(alpha = 0.07f), Offset(0f, size.height - line), Size(size.width, line))
            }.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Opponent", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.medium), maxLines = 1)
                Spacer(Modifier.weight(1f))
                FitText(chosen?.name ?: "Surprise me", ArenaMenuStyle.font(13f, SfWeight.bold), Modifier.weight(2f, fill = false), color = ArenaMenuStyle.gold,
                    minimumScale = 0.75f)
                SfImage("chevron.right", ArenaMenuStyle.gold.copy(alpha = 0.8f), 10.dp)
            }
        }) {
        TavernMenuItem("Surprise me", { model.setQuickDeckID("") }, systemImage = if (chosen == null) "diamond.fill" else null)
        ArenaCaps("Bracket ${model.quickResolvedBracket} decks", 9.5f, Modifier.padding(top = 4.dp))
        pool.forEach { deck ->
            TavernMenuItem("${deck.name} · ${deck.commander}", { model.setQuickDeckID(deck.id) }, systemImage = if (deck.id == chosen?.id) "diamond.fill" else null)
        }
    }
}

/** Who goes first as one die beside the skill: lit, everyone rolls a D20; dark, you choose at the table. */
@Composable
private fun RollToggle(model: ArenaPlayPanelModel) {
    val roll = model.startingPlayer == "roll"
    val shape = RoundedCornerShape(9.dp)
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.setStartingPlayer(if (roll) "choose" else "roll") },
        Modifier.size(44.dp).testTag("quick.startingPlayer").semantics(mergeDescendants = true) {
            contentDescription = "Who goes first"; stateDescription = if (roll) "Everyone rolls a D20" else "Choose at the table"
        }) {
        val ink = if (roll) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.dim
        Column(Modifier.fillMaxSize().background(if (roll) ArenaMenuStyle.goldFill else Brush.verticalGradient(List(2) { Color.Black.copy(alpha = 0.45f) }), shape)
            .border(0.9.dp, ArenaGlass.hairline, shape), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically)) {
            SfImage("dice.fill", ink, 15.dp)
            Text(if (roll) "D20" else "Pick", color = ink, style = ArenaMenuStyle.font(9f, SfWeight.bold))
        }
    }
}

/** One of the opponent's brackets as a round gem, gold when chosen. */
@Composable
private fun BracketGem(model: ArenaPlayPanelModel, text: String, value: Int, label: String, modifier: Modifier) {
    val on = model.quickBracket == value
    BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.setQuickBracket(value) }, modifier.defaultMinSize(minHeight = 44.dp).testTag("quick.bracket.$value")
        .semantics { contentDescription = label; selected = on }) {
        Box(Modifier.size(36.dp).glow(if (on) ArenaMenuStyle.gold.copy(alpha = 0.5f) else Color.Transparent, 5.dp, 18.dp)
            .background(if (on) ArenaMenuStyle.goldFill else Brush.verticalGradient(List(2) { Color.Black.copy(alpha = 0.45f) }), CircleShape)
            .border(if (on) 1.4.dp else 0.9.dp, if (on) ArenaMenuStyle.metal else ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
            FitText(text, ArenaMenuStyle.font(if (value == 0) 9.5f else 14f, SfWeight.bold), color = if (on) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.text,
                minimumScale = 0.7f)
        }
    }
}

/** Ranked: your standing, the one format, and the ways to the season and the leaderboard side by side. */
@Composable
private fun ColumnScope.RankedOptions(model: ArenaPlayPanelModel) {
    val rank = model.rank
    ArenaCaps("Ranked Commander · 1v1", 9.5f, Modifier.padding(top = 6.dp))
    Row(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 10.dp).testTag("ranked.standing").semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        // Searching, the footer grows: the standing shrinks to its badge and title.
        RankBadge(rank.shownPosition, if (model.search == null) 42.dp else 30.dp, showsPips = model.search == null, unplaced = rank.isPlacing)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(rank.shownTitle, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(16f, SfWeight.bold))
            Text("${rank.wins} wins · ${rank.losses} losses", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(11f, SfWeight.semibold))
        }
    }
    if (model.search != null) return
    val bracket = model.deckBracket
    if (!model.rankedEligible && bracket != null) {
        Row(Modifier.padding(vertical = 4.dp).testTag("ranked.ineligible"), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val warm = rgb(1.0, 0.72, 0.5)
            SfImage("exclamationmark.triangle.fill", warm, 11.dp)
            Text("${bracket.title} is above ${rank.deckLimitTier.label}'s limit (Bracket ${rank.deckLimitTier.maxDeckBracket}). Choose another deck.",
                color = warm, style = ArenaMenuStyle.font(11.5f, SfWeight.semibold))
        }
    }
    // Only the offline case is said: the normal search needs no explaining.
    if (!model.canSearchPeople) Text("Profiles are offline: an AI takes the seat, and counts the same.", Modifier.padding(bottom = 6.dp),
        color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ArenaPillButton("Season", model.rankedHall, identifier = "ranked.hall")
        ArenaPillButton("Leaderboard", model.leaderboard, identifier = "ranked.leaderboard")
    }
}

/** The ways to fill the table, each one line (Android has no Game Center: relay tables only). */
@Composable
private fun ColumnScope.CustomOptions(model: ArenaPlayPanelModel) {
    ArenaCaps("Players", 9.5f, Modifier.padding(top = 6.dp))
    ArenaOptionRow("Against the AI", { model.setPlayWithFriends(false) }, selected = !model.playWithFriends, identifier = "custom.ai")
    ArenaOptionRow("Online table", { model.setPlayWithFriends(true) }, selected = model.playWithFriends, identifier = "custom.online")
}

/** The chosen table's deck as an open box (the deck you'd play next while there are none yet), the way it was played and the deck's bracket. */
@Composable
private fun ColumnScope.RecentOptions(model: ArenaPlayPanelModel) {
    Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        model.selectedDeck?.let { deck ->
            ArenaDeckBox(deck, Modifier.padding(top = (ArenaBoxGeometry(120f).rise * 1.5f + 12f).dp), selected = true, width = 120.dp)
        }
        // With no tables yet the box speaks for itself; after a game it names the way you played.
        if (model.recent.isNotEmpty()) ArenaCaps(model.mode.heading, 10f)
        model.deckBracket?.let { Text(it.title, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.semibold)) }
    }
}

// MARK: Footer

@Composable
private fun BladeFooter(model: ArenaPlayPanelModel, friendWay: ArenaFriendWay, compact: Boolean) {
    Column(Modifier.fillMaxWidth().drawBehind { drawRect(ArenaGlass.hairline, size = Size(size.width, 1.dp.toPx()), alpha = 0.3f) }
        .padding(horizontal = 16.dp).padding(top = 8.dp, bottom = if (compact) 6.dp else 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val search = model.search
        val friend = model.waitingFor
        when {
            search != null -> ArenaSearchStatus(search, model.playAINow)
            friend != null -> Column(Modifier.testTag("challenge.waiting").semantics(mergeDescendants = true) { },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Waiting for $friend…", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.bold))
                Text("Your challenge is on its way.", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium))
            }
            model.status != null -> Text(model.status, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium), maxLines = 2,
                textAlign = TextAlign.Center)
        }
        val plaque = Modifier.fillMaxWidth().height(46.dp)
        when {
            search != null -> ArenaPlayButton("Cancel", model.cancelSearch, plaque, cancel = true, fontSize = 19f,
                enabled = search !is RankedMatchmaker.Phase.Matched, identifier = "ranked.search.cancel")
            friend != null -> ArenaPlayButton("Withdraw", model.cancelChallenge, plaque, cancel = true, fontSize = 19f, identifier = "challenge.cancel")
            else -> {
                val primary = ArenaPlayRules.primary(model.tab, friendWay, model.mode, model.recent.isEmpty(), model.mayStart, model.rankedEligible)
                val action: () -> Unit = when (primary.action) {
                    ArenaPlayAction.CHALLENGE -> model.challengeFriend
                    ArenaPlayAction.HOST -> model.hostOnline
                    ArenaPlayAction.JOIN -> model.joinOnline
                    ArenaPlayAction.FIND_MATCH_TAB -> { { model.setTab(ArenaPlayTab.FIND) } }
                    ArenaPlayAction.START_QUICK -> model.startQuick
                    ArenaPlayAction.FIND_RANKED -> model.findRanked
                    ArenaPlayAction.OPEN_CUSTOM -> model.openCustom
                }
                ArenaPlayButton(primary.title, action, plaque, fontSize = 20f, enabled = primary.enabled, identifier = primary.identifier)
            }
        }
    }
}

/** A way to play as a cut gem: an ember bolt for Quick, your rank's emblem for Ranked, a table for Custom. */
@Composable
fun ArenaModeGem(mode: ArenaPlayMode, rank: RankPosition, lit: Boolean, size: Dp = 40.dp) {
    Box(Modifier.size(size).glow(if (lit) ArenaMenuStyle.ember.copy(alpha = 0.55f) else Color.Transparent, 8.dp, size / 2)
        .background(Brush.radialGradient(listOf(rgb(0.24, 0.16, 0.10), rgb(0.07, 0.05, 0.04)), center = Offset.Unspecified), CircleShape)
        .border(if (lit) 1.6.dp else 1.dp, if (lit) ArenaMenuStyle.metal else ArenaGlass.hairline, CircleShape)
        .clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        when (mode) {
            ArenaPlayMode.QUICK -> ArenaGlyph("bolt.fill", 17.dp, Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), ArenaMenuStyle.ember)), emboss = false)
            ArenaPlayMode.RANKED -> RankEmblem(rank.tier, size * 0.8f)
            ArenaPlayMode.CUSTOM -> ArenaGlyph("person.3.fill", 14.dp, ArenaMenuStyle.metal, emboss = false)
        }
    }
}

/** The blade's lit edge: an ember seam that flickers like a flame (a bright core, an ember glow around it, a wider haze). */
@Composable
fun ArenaSeam(vertical: Boolean, modifier: Modifier = Modifier) {
    val still = BoardMotionFlags.reduceMotion || !LocalBrandAmbientMotion.current
    val flicker = if (still) 0f else rememberInfiniteTransition(label = "seam")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Reverse), label = "flicker").value
    val stops = listOf(ArenaMenuStyle.seam.copy(alpha = 0.55f), rgb(1.0, 0.84, 0.5), ArenaMenuStyle.seam, rgb(1.0, 0.7, 0.3), ArenaMenuStyle.seam.copy(alpha = 0.6f))
    Box(modifier.then(if (vertical) Modifier.width(3.5.dp) else Modifier.height(3.5.dp)).clearAndSetSemantics { }.drawBehind {
        val rect = Rect(Offset.Zero, size)
        blurredRoundRect(rgb(1.0, 0.35, 0.1).copy(alpha = 0.55f), 20.dp.toPx(), rect, 0f)
        blurredRoundRect(ArenaMenuStyle.seam.copy(alpha = 0.7f + 0.3f * flicker), (7f + 2f * flicker).dp.toPx(), rect, 0f)
        drawRect(if (vertical) Brush.verticalGradient(stops) else Brush.horizontalGradient(stops))
    })
}

/** A ranked search in the blade: how long it has run, and the AI on offer. */
@Composable
fun ArenaSearchStatus(phase: RankedMatchmaker.Phase, playAINow: () -> Unit) {
    if (phase is RankedMatchmaker.Phase.Matched) {
        Column(Modifier.testTag("ranked.search").semantics(mergeDescendants = true) { }, horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Challenger found", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.bold))
            Text(phase.ticket.opponent ?: "Another player", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
            Text("Setting the table…", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.medium))
        }
        return
    }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(phase) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val since = (phase as? RankedMatchmaker.Phase.Searching)?.since ?: now
    val elapsed = maxOf(0L, (now - since) / 1000).toInt()
    val left = maxOf(0, (RankedMatchmaker.SEARCH_MILLIS / 1000).toInt() - elapsed)
    Column(Modifier.testTag("ranked.search"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Searching…", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.bold))
            Text("%d:%02d".format(elapsed / 60, elapsed % 60), color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(14f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
        }
        // The countdown rides on the button, not a line of its own (the judge, 2026-10-22).
        ArenaPillButton("Play the AI now · $left s", playAINow, identifier = "ranked.search.ai")
    }
}
