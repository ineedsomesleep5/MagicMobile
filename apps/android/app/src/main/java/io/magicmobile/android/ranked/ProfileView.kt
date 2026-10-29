package io.magicmobile.android.ranked

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.magicmobile.android.game.Achievement
import io.magicmobile.android.game.ArenaProfileRules
import io.magicmobile.android.game.MatchRecord
import io.magicmobile.android.game.PlayerStats
import io.magicmobile.android.game.ProfileGame
import io.magicmobile.android.game.ProfileSummary
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.SeasonBadge
import io.magicmobile.android.menus.ArenaArt
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaEmblem
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPanel
import io.magicmobile.android.menus.ArenaPanelHeader
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaSegmented
import io.magicmobile.android.menus.ArenaTabBar
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.menus.arenaShadow
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.launch

// Port of Ranked/ProfileView.swift: the player's own profile in Arena's layout.

private enum class ResultFilter(val title: String) {
    ALL("All"), WINS("Wins"), LOSSES("Losses"), DRAWS("Draws");
    fun includes(outcome: RankOutcome) = when (this) {
        ALL -> true; WINS -> outcome == RankOutcome.WIN; LOSSES -> outcome == RankOutcome.LOSS; DRAWS -> outcome == RankOutcome.DRAW
    }
}

private enum class ProfileTab { OVERVIEW, CUSTOMIZATION }
private enum class Chooser { TITLE, PICTURE }

/**
 * The player's own profile (PlayerProfileView in ProfileView.swift), as Arena's Profile: the player's name as the headline,
 * the season rank and the progression under it, the chosen commander as full-height hero art on the right with the cosmetics
 * pills at its foot, and Arena's Overview / Customization strip along the bottom. Upright the hero leads the page. The rest
 * of the story (the season's chart, record, trophies, games, account and privacy) follows in the scroll. A game with a saved
 * detailed record opens the match dashboard.
 */
@Composable
fun PlayerProfileScreen(store: PlayerRecordStore, account: PlayerAccount, playerName: String, deckCommanders: List<String> = emptyList(),
                        loadMetadata: suspend () -> io.magicmobile.android.studio.NativeDeckMetadataCatalogue? = { null }, back: () -> Unit) {
    val file = store.file
    val stats = remember(file.matches) { PlayerStats(file.matches) }
    val unlocked = remember(file.matches, file.rank) { Achievement.unlocked(file.matches, file.rank) }
    var deckFilter by remember { mutableStateOf<String?>(null) }
    var resultFilter by remember { mutableStateOf(ResultFilter.ALL) }
    var showAll by remember { mutableStateOf(false) }
    var tab by remember { mutableStateOf(ProfileTab.OVERVIEW) }
    var choosing by remember { mutableStateOf<Chooser?>(null) }
    val details = rememberProfileGameDetails()
    var review by remember { mutableStateOf<io.magicmobile.android.studio.DeckStudioRecordedGame?>(null) }
    var metadata by remember { mutableStateOf<io.magicmobile.android.studio.NativeDeckMetadataCatalogue?>(null) }
    val scope = rememberCoroutineScope()
    var previewAsOthers by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { store.refreshSeason() }
    val scoped = remember(file.matches, deckFilter) { deckFilter?.let { id -> file.matches.filter { it.deckID == id } } ?: file.matches }
    val summary = remember(scoped, file.matches, deckFilter) {
        // The rank history is the ranked standings, whatever deck the totals are narrowed to.
        ProfileSummary.of(scoped).let { if (deckFilter != null) it.copy(rankPoints = ProfileSummary.of(file.matches).rankPoints) else it }
    }
    fun choose(chooser: Chooser) { GameAudio.play(GameSound.UI_OPEN); choosing = chooser }
    val name = playerName.ifBlank { "Player" }

    @Composable
    fun nameBlock(size: Float) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(name, sf(size, SfWeight.bold, SfDesign.SERIF).arenaShadow(4f, 0.8f), Modifier.semantics { heading() }.testTag("profile.name"),
                color = ArenaMenuStyle.text, minimumScale = 0.6f)
            file.title?.let { ArenaCaps(it.title) }
        }
    }

    /** The rest of the player's story, under the season rank. */
    @Composable
    fun ColumnScope.playerStory() {
        SeasonCard(store, summary)
        SeasonBadgesCard(store.file.rank)
        if (stats.decks.size > 1) ChipRow(Modifier.trailingFade().testTag("profile.filter.decks")) {
            ProfileChip("All decks", deckFilter == null, "profile.filter.deck.all", { deckFilter = null; showAll = false }, detail = "${file.matches.size}")
            for (deck in stats.decks.take(8)) ProfileChip(deck.label, deckFilter == deck.id, "profile.filter.deck.${deck.id}", { deckFilter = deck.id; showAll = false }, detail = "${deck.games}")
        }
        val insights = io.magicmobile.android.game.ProfileInsights.of(scoped.map(ProfileGame::of))
        RecordCard(deckFilter?.let { id -> stats.decks.firstOrNull { it.id == id }?.label } ?: "Record", summary, insights.form)
        InsightCards(insights)
        WeeksCard(summary)
        if (summary.commanders.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Most played commanders")
            CommanderTiles(summary.commanders)
        }
        if (summary.colors.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Color identity")
            ColorPie(summary.colors)
        }
        Column(Modifier.leatherCard().testTag("profile.achievements"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Trophies", "${unlocked.size}/${Achievement.entries.size}")
            TrophyShelf(unlocked)
        }
        val visible = scoped.filter { resultFilter.includes(it.outcome) }
        Column(Modifier.leatherCard().testTag("profile.history"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Recent games", "${visible.size} shown")
            ChipRow(Modifier.trailingFade()) {
                for (filter in ResultFilter.entries) ProfileChip(filter.title, resultFilter == filter, "profile.filter.result.${filter.name.lowercase()}", { resultFilter = filter; showAll = false })
            }
            if (file.matches.isEmpty()) ProfileEmptyNote("Your games show here after you play.")
            else if (visible.isEmpty()) ProfileEmptyNote("No games match these filters.", "line.3.horizontal.decrease")
            for (match in visible.take(if (showAll) 40 else 6)) {
                val recorded = match.engineMatchID?.let { details.byMatch[it] }
                ProfileGameCard(ProfileGame.of(match), recorded?.let { "deckHistory.match.${it.id}.expand" } ?: "profile.game.${match.id}",
                    onOpenDetail = recorded?.let { game -> {
                        review = game
                        if (metadata == null) scope.launch { metadata = loadMetadata() }
                    } })
            }
            if (visible.size > 6) ArenaButton({ showAll = !showAll }, kind = ArenaButtonKind.SECONDARY, compact = true, identifier = "profile.games.more") {
                ArenaButtonText(if (showAll) "Show fewer" else "Show more")
            }
        }
        AccountSignInCard(account)
        PrivacyCard(account) { previewAsOthers = true }
        Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) { ProfileHistorySettings(details) }
    }

    Box(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth > maxHeight
            TavernLobbyPage("", back, showsBack = false, contentWidth = if (wide) 940.dp else null, scrolls = false) {
                Column(Modifier.fillMaxSize()) {
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        when (tab) {
                            ProfileTab.OVERVIEW -> if (wide) {
                                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                    Column(Modifier.weight(1f).fillMaxHeight().arenaScrollFade().verticalScroll(rememberScrollState()).testTag("lobby.scroll")
                                        .padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                        nameBlock(34f)
                                        Identity(store, unlocked.size)
                                        playerStory()
                                    }
                                    ProfileHero(store, wide = true, nameBlock = { nameBlock(30f) }, Modifier.width(330.dp).fillMaxHeight().padding(bottom = 4.dp),
                                        pickPortrait = { choose(Chooser.PICTURE) }, pickTitle = { choose(Chooser.TITLE) })
                                }
                            } else {
                                Column(Modifier.fillMaxSize().arenaScrollFade().verticalScroll(rememberScrollState()).testTag("lobby.scroll")
                                    .padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                    ProfileHero(store, wide = false, nameBlock = { nameBlock(30f) }, Modifier.fillMaxWidth().height(300.dp),
                                        pickPortrait = { choose(Chooser.PICTURE) }, pickTitle = { choose(Chooser.TITLE) })
                                    Identity(store, unlocked.size)
                                    playerStory()
                                }
                            }
                            ProfileTab.CUSTOMIZATION -> Customization(store, wide, { choose(Chooser.PICTURE) }, { choose(Chooser.TITLE) })
                        }
                    }
                    ArenaSegmented(listOf("Overview" to ProfileTab.OVERVIEW, "Customization" to ProfileTab.CUSTOMIZATION), tab, { tab = it },
                        Modifier.padding(top = 4.dp), identifier = "profile.tab")
                }
            }
        }
        // Arena's cosmetics choosers: the titles as plaques, the portraits as arched art tiles; a tap chooses and closes.
        ArenaPanel(choosing != null, { choosing = null }, maxWidth = 620.dp) {
            Column(Modifier.fillMaxSize()) {
                ArenaPanelHeader(if (choosing == Chooser.TITLE) "Choose a title" else "Choose a portrait", closeIdentifier = "profile.chooser.close")
                Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    if (choosing == Chooser.TITLE) {
                        AdaptiveGrid(listOf<Achievement?>(null) + Achievement.entries.filter { it in unlocked }, 160.dp, 10.dp) { value ->
                            TitleTile(value, file.title == value) { GameAudio.play(GameSound.UI_CONFIRM); store.setTitle(value); choosing = null }
                        }
                    } else {
                        val (played, decks) = ArenaProfileRules.pictureChoices(stats.commanders.map { it.label }, deckCommanders, file.favoriteCommander)
                        val pick: (String?) -> Unit = { GameAudio.play(GameSound.UI_CONFIRM); store.setFavoriteCommander(it); choosing = null }
                        AdaptiveGrid(listOf<String?>(null) + played, 96.dp, 10.dp, 12.dp) { value ->
                            PictureTile(value, value ?: stats.commanders.firstOrNull()?.label, file.favoriteCommander == value) { pick(value) }
                        }
                        if (decks.isNotEmpty()) {
                            ArenaCaps("Your decks")
                            AdaptiveGrid(decks, 96.dp, 10.dp, 12.dp) { value -> PictureTile(value, value, file.favoriteCommander == value) { pick(value) } }
                        }
                    }
                }
            }
        }
        if (previewAsOthers) account.username?.let { username ->
            androidx.compose.ui.window.Dialog({ previewAsOthers = false }, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
                io.magicmobile.android.ui.EdgeToEdgeDialogWindow()
                PublicProfileScreen(account, username, null, null) { previewAsOthers = false }
            }
        }
        io.magicmobile.android.studio.StudioCover(review != null) {
            review?.let { game -> io.magicmobile.android.studio.MatchHistoryDashboard(game, false, metadata) { review = null } }
        }
    }
}

/** Arena's two rows under the name: the season's rank (the emblem, its pips, the record and the peak), then the progression as emblem tiles. */
@Composable
private fun Identity(store: PlayerRecordStore, trophies: Int) {
    val rank = store.file.rank
    val all = remember(store.file.matches) { ProfileSummary.of(store.file.matches) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("${RankLadder.seasonName(rank.season)} · Season rank")
        Row(Modifier.arenaCard(12.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            RankBadge(rank.position, 64.dp, showsPips = false)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(rank.position.title, color = ArenaMenuStyle.text, style = sf(20f, SfWeight.bold, SfDesign.SERIF))
                if (rank.position.tier != RankTier.MYTHIC) RankPips(rank.position.pips, rank.position.tier, 10.dp)
                Text("${rank.wins}–${rank.losses}", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
                if (rank.peak != rank.position) Text("Peak ${rank.peak.title}", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11.5f, SfWeight.semibold))
            }
        }
        ArenaCaps("Progression", modifier = Modifier.padding(top = 4.dp))
        Row(Modifier.fillMaxWidth().testTag("profile.career"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ProgressTile("${all.games}", "Games", "gamecontroller.fill", Modifier.weight(1f))
            ProgressTile(ArenaProfileRules.winRate(all.wins, all.games), "Win rate", "chart.pie.fill", Modifier.weight(1f))
            ProgressTile("$trophies", "Trophies", "trophy.fill", Modifier.weight(1f))
        }
    }
}

/** One of the progression's emblem tiles: a plain gold emblem (no coin ring, as Arena's progression icons) over its number and name. */
@Composable
private fun ProgressTile(value: String, label: String, symbol: String, modifier: Modifier) {
    Column(modifier.arenaCard(0.dp).padding(vertical = 10.dp).semantics(mergeDescendants = true) { contentDescription = "$label: $value" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(40.dp, 34.dp), contentAlignment = Alignment.Center) { ArenaEmblem(symbol, 22.dp, lit = true) }
        FitText(value, sf(19f, SfWeight.bold, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"), color = ArenaMenuStyle.text, minimumScale = 0.7f)
        ArenaCaps(label, 8.5f)
    }
}

/**
 * The chosen commander as Arena's avatar art: full height beside the player sideways, across the top upright with the name over
 * it. Its name sits at the foot, with the cosmetics pills at the bottom right. A tap on the art chooses another portrait.
 */
@Composable
private fun ProfileHero(store: PlayerRecordStore, wide: Boolean, nameBlock: @Composable () -> Unit, modifier: Modifier,
                        pickPortrait: () -> Unit, pickTitle: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val commander = store.shownCommander
    Box(modifier.glow(Color.Black.copy(alpha = 0.6f), 14.dp, 16.dp).clip(shape).border(1.dp, ArenaGlass.hairline, shape)) {
        BrandPressable(pickPortrait, Modifier.fillMaxSize().testTag("profile.picture").semantics {
            contentDescription = commander?.let { "Profile picture: $it" } ?: "Profile picture"; role = Role.Button
        }) { ArenaArt(commander ?: "", modifier = Modifier.fillMaxSize()) }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
        Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!wide) nameBlock()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f)) {
                    commander?.let {
                        FitText(it, ArenaMenuStyle.font(13f, SfWeight.semibold).copy(fontStyle = FontStyle.Italic), color = ArenaMenuStyle.text.copy(alpha = 0.85f),
                            maxLines = 2, minimumScale = 0.8f)
                    }
                }
                // One word each, sized to it: a pill is never cut short (the judge, 2026-10-22).
                ArenaPillButton("Title", pickTitle, identifier = "profile.title")
                ArenaPillButton("Portrait", pickPortrait, identifier = "profile.commander")
            }
        }
    }
}

/** Arena's Customization board: a tile for each thing the player shows, the portrait large, the title beside it. A tap opens its chooser. */
@Composable
private fun Customization(store: PlayerRecordStore, wide: Boolean, pickPortrait: () -> Unit, pickTitle: () -> Unit) {
    val title = store.file.title
    @Composable
    fun titleFace() {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
            Text(title?.title ?: "No title", Modifier.padding(horizontal = 18.dp).defaultMinSize(minHeight = 50.dp)
                .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape)
                .padding(horizontal = 18.dp, vertical = 14.dp),
                color = if (title == null) ArenaMenuStyle.dim else ArenaMenuStyle.gold, style = sf(17f, SfWeight.bold, SfDesign.SERIF), textAlign = TextAlign.Center)
        }
    }
    if (wide) Row(Modifier.fillMaxSize().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        CustomizationTile("Portrait", "profile.customize.picture", pickPortrait, Modifier.weight(1f).fillMaxHeight()) { ArenaArt(store.shownCommander ?: "", modifier = Modifier.fillMaxSize()) }
        CustomizationTile("Title", "profile.customize.title", pickTitle, Modifier.width(300.dp).fillMaxHeight()) { titleFace() }
    } else Column(Modifier.fillMaxSize().padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        CustomizationTile("Portrait", "profile.customize.picture", pickPortrait, Modifier.fillMaxWidth().weight(1f)) { ArenaArt(store.shownCommander ?: "", modifier = Modifier.fillMaxSize()) }
        CustomizationTile("Title", "profile.customize.title", pickTitle, Modifier.fillMaxWidth().height(180.dp)) { titleFace() }
    }
}

@Composable
private fun CustomizationTile(title: String, identifier: String, action: () -> Unit, modifier: Modifier, face: @Composable () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); action() }, modifier.testTag(identifier).semantics { contentDescription = title; role = Role.Button }) {
        Box(Modifier.fillMaxSize().clip(shape).border(1.dp, ArenaGlass.hairline, shape)) {
            face()
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.6f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
            Text(title, Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(16f, SfWeight.bold))
        }
    }
}

/** A title as a glass plaque, edged in gold when it is the one shown. */
@Composable
private fun TitleTile(value: Achievement?, on: Boolean, choose: () -> Unit) {
    BrandPressable(choose, Modifier.fillMaxWidth().testTag("profile.title.${value?.let(ArenaProfileRules::achievementID) ?: "none"}")
        .semantics { contentDescription = value?.title ?: "No title"; role = Role.Button; selected = on }) {
        Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp)
            .then(if (on) Modifier.glow(ArenaMenuStyle.gold.copy(alpha = 0.45f), 8.dp, 24.dp) else Modifier)
            .background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape)
            .then(if (on) Modifier.border(2.dp, ArenaMenuStyle.gold, CircleShape) else Modifier.border(1.dp, ArenaGlass.hairline, CircleShape))
            .padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
            FitText(value?.title ?: "No title", ArenaMenuStyle.font(14f, SfWeight.bold), color = if (on) ArenaMenuStyle.gold else ArenaMenuStyle.text,
                maxLines = 2, minimumScale = 0.8f, textAlign = TextAlign.Center)
        }
    }
}

/** One portrait: the commander's art in the profile's arch, its name under it; "Most played" (null) follows the games. */
@Composable
private fun PictureTile(value: String?, art: String?, on: Boolean, choose: () -> Unit) {
    val arch = RoundedCornerShape(CornerSize(50), CornerSize(50), CornerSize(8.dp), CornerSize(8.dp))
    BrandPressable(choose, Modifier.fillMaxWidth().semantics { contentDescription = value ?: "Most played"; role = Role.Button; selected = on }) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(0.74f)
                .glow(if (on) ArenaMenuStyle.gold.copy(alpha = 0.5f) else Color.Black.copy(alpha = 0.5f), if (on) 9.dp else 5.dp, 12.dp)
                .clip(arch).then(if (on) Modifier.border(2.5.dp, ArenaMenuStyle.gold, arch) else Modifier.border(1.dp, ArenaGlass.hairline, arch))) {
                ArenaArt(art ?: "", modifier = Modifier.fillMaxSize())
            }
            Text(value ?: "Most played", Modifier.fillMaxWidth().defaultMinSize(minHeight = 28.dp), color = if (on) ArenaMenuStyle.gold else ArenaMenuStyle.text,
                style = sf(11f, if (on) SfWeight.bold else SfWeight.semibold, SfDesign.SERIF), textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

/** A grid whose columns are as many as fit at `minWidth` each (SwiftUI's adaptive GridItem). */
@Composable
internal fun <T> AdaptiveGrid(items: List<T>, minWidth: Dp, spacing: Dp, rowSpacing: Dp = spacing, cell: @Composable (T) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = maxOf(1, ((maxWidth + spacing) / (minWidth + spacing)).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(rowSpacing)) {
            for (row in items.chunked(columns)) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing)) {
                for (item in row) Box(Modifier.weight(1f)) { cell(item) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** A row that runs on fades at its right edge instead of stopping short (the judge, 2026-10-22). */
internal fun Modifier.trailingFade(): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        drawRect(Brush.horizontalGradient(0.9f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
    }

/** The badge each season earned at its peak, the season in play still being earned (Caleb, 2026-10-26). */
@Composable
private fun SeasonBadgesCard(rank: RankState) {
    val badges = SeasonBadge.earned(rank)
    Column(Modifier.leatherCard().testTag("profile.seasonBadges"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Season badges")
        if (badges.isEmpty()) ProfileEmptyNote("Play ranked to earn this season's badge.", "rosette") else SeasonBadgeShelf(badges)
    }
}

@Composable
private fun SeasonCard(store: PlayerRecordStore, summary: ProfileSummary) {
    val rank = store.file.rank
    Column(Modifier.leatherCard().testTag("profile.season"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ProfileSectionTitle("Rank history")
        if (summary.rankPoints.isEmpty()) ProfileEmptyNote("Play ranked games to chart your climb.", "chart.bar.fill")
        else RankHistoryChart(summary.rankPoints)
        if (rank.history.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(TavernPalette.brass.copy(alpha = 0.4f)))
            for (past in rank.history.take(4)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                // Where the season finished, as the Ranked Hall shows it (the judge, 2026-10-22: one answer).
                RankEmblem(past.final.tier, 22.dp)
                Text("${RankLadder.seasonName(past.season)}: ${past.final.title}", Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.regular))
                Text("${past.wins}–${past.losses}", Modifier.alpha(0.7f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.regular).copy(fontFeatureSettings = "tnum"))
            }
        }
    }
}

@Composable
private fun RecordCard(title: String, summary: ProfileSummary, form: List<RankOutcome>) {
    Column(Modifier.leatherCard().testTag("profile.stats"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ProfileSectionTitle(title, "${summary.games} games")
        if (summary.games == 0) ProfileEmptyNote("Your games show here after you play.")
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
            if (form.size >= 3) Row(Modifier.testTag("profile.form"), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("RECENT FORM", Modifier.alpha(0.7f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(9f, SfWeight.heavy).copy(letterSpacing = 1.sp))
                FormStrip(form)
            }
        }
    }
}

/** Highlights, records by mode and by ranked tier, and how the player does against each commander (iOS insightCards). */
@Composable
private fun InsightCards(insights: io.magicmobile.android.game.ProfileInsights) {
    if (insights.fastestWin != null || insights.averageMinutes != null || insights.bestDeck != null) {
        Column(Modifier.leatherCard().testTag("profile.highlights"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Highlights")
            val tiles = listOfNotNull(insights.fastestWin?.let { "Fastest win" to "Turn $it" },
                insights.averageMinutes?.let { "Avg. game" to "${Math.round(it)} min" },
                insights.averageTurnsInWins?.let { "Turns in wins" to "%.1f".format(it) },
                insights.averageTurnsInLosses?.let { "Turns in losses" to "%.1f".format(it) })
            for (pair in tiles.chunked(2)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((title, value) in pair) ProfileStatTile(title, value, Modifier.weight(1f))
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
            insights.bestDeck?.let { best -> ProfileRecordLine("Best deck: ${best.id}", best) { SfImage("star.fill", ProfilePalette.win, 14.dp) } }
        }
    }
    if (insights.modes.size > 1 || insights.tiers.isNotEmpty()) {
        Column(Modifier.leatherCard().testTag("profile.records"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Records")
            for (line in insights.modes) ProfileRecordLine(when (line.id) { "ranked" -> "Ranked"; "quick" -> "Quick Match"; else -> "Casual" }, line) {
                SfImage(when (line.id) { "ranked" -> "shield.lefthalf.filled"; "quick" -> "bolt.fill"; else -> "person.3.fill" }, ArenaMenuStyle.gold, 14.dp)
            }
            if (insights.tiers.isNotEmpty()) {
                ArenaCaps("Ranked by tier")
                for (line in insights.tiers) {
                    val tier = RankTier.entries.firstOrNull { it.name.lowercase() == line.id } ?: RankTier.BRONZE
                    ProfileRecordLine(tier.label, line) { RankEmblem(tier, 26.dp) }
                }
            }
        }
    }
    if (insights.matchups.isNotEmpty()) {
        Column(Modifier.leatherCard().testTag("profile.matchups"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ProfileSectionTitle("Matchups", "most faced")
            for (line in insights.matchups) ProfileRecordLine("vs ${line.id}", line) { CommanderArtMedallion(line.id, 28.dp) }
        }
    }
}

@Composable
private fun WeeksCard(summary: ProfileSummary) {
    Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Games over time", "last 8 weeks")
        if (summary.weeks.all { it.games == 0 }) ProfileEmptyNote("Nothing played in the last eight weeks.", "hourglass")
        else {
            WeeklyBars(summary.weeks)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                for ((color, text) in listOf(ProfilePalette.win to "Won", ProfilePalette.loss to "Not won")) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(9.dp).background(color, CircleShape))
                    Text(text, Modifier.alpha(0.75f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(11f, SfWeight.semibold))
                }
            }
        }
    }
}

/** Who may open this profile: Public (the default), Friends only or Private. The server enforces it. */
@Composable
private fun PrivacyCard(account: PlayerAccount, preview: () -> Unit) {
    val scope = rememberCoroutineScope()
    val signedIn = account.phase == PlayerAccount.Phase.READY && account.username != null
    val ready = signedIn && account.visibilityKnown
    Column(Modifier.leatherCard().testTag("profile.privacyCard"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle("Who can see your profile")
        Box(Modifier.alpha(if (ready) 1f else 0.55f)) {
            ProfilePrivacyTabs(account.visibility) { choice -> if (ready) scope.launch { account.setVisibility(choice) } }
        }
        Text(when {
            !signedIn -> "Choose your player name in Friends to share a profile with other players."
            !account.visibilityKnown -> "Privacy settings arrive with the next server update. Until then your profile stays as it is."
            else -> account.visibility.detail
        }, Modifier.alpha(0.8f).testTag("profile.privacy.note"), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.regular))
        if (signedIn && account.profilesAvailable) ArenaButton(preview, kind = ArenaButtonKind.SECONDARY, compact = true, identifier = "profile.privacy.preview") {
            ArenaButtonText("See it as others do")
        }
    }
}

/**
 * Who may see the profile, as Arena's tab strip (Caleb, 2026-10-22: no ember pills in the menus): each choice with its symbol,
 * the chosen one bright over a glowing gold bar. Each keeps its identifier, `profile.privacy.<visibility>`.
 */
@Composable
private fun ProfilePrivacyTabs(selection: ProfileVisibility, select: (ProfileVisibility) -> Unit) {
    Box(Modifier.fillMaxWidth().testTag("profile.privacy")) {
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(bottom = 2.dp).height(1.dp).alpha(0.35f).background(ArenaGlass.hairline))
        Row(Modifier.fillMaxWidth()) {
            for (option in ProfileVisibility.entries) {
                val on = option == selection
                BrandPressable({ if (!on) { GameAudio.play(GameSound.UI_TAP); select(option) } }, Modifier.weight(1f).defaultMinSize(minHeight = 44.dp)
                    .testTag("profile.privacy.${option.raw}").semantics { contentDescription = option.title; role = Role.Button; selected = on }) {
                    Box(Modifier.fillMaxWidth().height(40.dp), contentAlignment = Alignment.Center) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            SfImage(privacyIcon(option), if (on) ArenaMenuStyle.text else ArenaMenuStyle.dim, 12.dp)
                            FitText(option.title, ArenaMenuStyle.font(13.5f, if (on) SfWeight.bold else SfWeight.semibold),
                                color = if (on) ArenaMenuStyle.text else ArenaMenuStyle.dim, minimumScale = 0.7f)
                        }
                        ArenaTabBar(on, Modifier.align(Alignment.BottomCenter))
                    }
                }
            }
        }
    }
}

internal fun privacyIcon(visibility: ProfileVisibility): String = when (visibility) {
    ProfileVisibility.PUBLIC -> "globe"; ProfileVisibility.FRIENDS -> "person.2.fill"; ProfileVisibility.PRIVATE -> "hand.raised"
}

/** A profile picture: the commander's illustration alone (no card frame) in the table's brass ring. */
@Composable
fun CommanderArtMedallion(name: String?, diameter: Dp, modifier: Modifier = Modifier) {
    val placeholder: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { PersonGlyph(TavernPalette.parchment.copy(alpha = 0.55f), diameter * 0.42f) }
    }
    io.magicmobile.android.board.TavernMedallion(diameter, null, modifier.semantics { contentDescription = name?.let { "Profile picture: $it" } ?: "Profile picture" }) {
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(io.magicmobile.android.ui.MagicPalette.iron, io.magicmobile.android.ui.MagicPalette.leather)))) {
            if (!name.isNullOrBlank()) io.magicmobile.android.CardArtwork(name, Modifier.fillMaxSize(), artOnly = true, placeholder = placeholder) else placeholder()
        }
    }
}
