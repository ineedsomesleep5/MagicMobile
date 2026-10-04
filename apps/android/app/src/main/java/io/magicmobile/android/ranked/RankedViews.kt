package io.magicmobile.android.ranked

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.Achievement
import io.magicmobile.android.game.AIDeck
import io.magicmobile.android.game.AIDeckPool
import io.magicmobile.android.game.BracketReport
import io.magicmobile.android.game.CommanderBracket
import io.magicmobile.android.game.DeckBracketPreference
import io.magicmobile.android.game.MatchRecord
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.PlayerStats
import io.magicmobile.android.game.RankBonus
import io.magicmobile.android.game.RankChange
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.RankedMatchmaker
import io.magicmobile.android.social.PlayerProfileCard
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.CommanderDeckPortrait
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernButtonText
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernPicker
import io.magicmobile.android.ui.TavernPickerSection
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.TavernSheetBackground
import io.magicmobile.android.ui.TavernStepper
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.engraved
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernBrassFrame
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.tavernPanel
import io.magicmobile.android.ui.tavernTitleBar
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

// Port of Ranked/RankBadgeView.swift, RankCeremonyView.swift, PlayModeViews.swift and ProfileView.swift.

val RankTier.tint: Color get() = when (this) {
    RankTier.BRONZE -> rgb(0.80, 0.50, 0.27); RankTier.SILVER -> rgb(0.80, 0.83, 0.88); RankTier.GOLD -> rgb(1.0, 0.80, 0.36)
    RankTier.PLATINUM -> rgb(0.55, 0.90, 0.86); RankTier.DIAMOND -> rgb(0.50, 0.75, 1.0); RankTier.MYTHIC -> rgb(1.0, 0.45, 0.22)
}
val RankTier.shade: Color get() = when (this) {
    RankTier.BRONZE -> rgb(0.36, 0.18, 0.07); RankTier.SILVER -> rgb(0.32, 0.34, 0.40); RankTier.GOLD -> rgb(0.48, 0.30, 0.06)
    RankTier.PLATINUM -> rgb(0.10, 0.34, 0.36); RankTier.DIAMOND -> rgb(0.08, 0.20, 0.48); RankTier.MYTHIC -> rgb(0.45, 0.07, 0.03)
}
val CommanderBracket.tint: Color get() = when (this) {
    CommanderBracket.EXHIBITION -> rgb(0.55, 0.80, 0.55); CommanderBracket.CORE -> rgb(0.45, 0.70, 0.95)
    CommanderBracket.UPGRADED -> rgb(0.95, 0.75, 0.30); CommanderBracket.OPTIMIZED -> rgb(0.95, 0.42, 0.25); CommanderBracket.CEDH -> rgb(0.75, 0.35, 0.95)
}

private val parchmentInk = TavernPalette.ink
private val brassLabel = rgb(0.74, 0.46, 0.16)
private val good = rgb(0.6, 0.95, 0.55)
private val bad = rgb(1.0, 0.55, 0.45)

/** The rendered badge art (tavern_rank_*, from the iOS asset catalogue), resolved once per name. */
object RankArt {
    private val ids = HashMap<String, Int>()
    const val SPIN_FRAMES = 16

    fun id(context: android.content.Context, name: String): Int = synchronized(ids) {
        ids.getOrPut(name) { context.resources.getIdentifier(name, "drawable", context.packageName) }
    }
}

/** A tier's emblem: the rendered badge, or a drawn medallion if the art is missing. */
@Composable
fun RankEmblem(tier: RankTier, size: Dp = 96.dp, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val id = RankArt.id(context, tier.drawableName)
    if (id != 0) {
        Image(painterResource(id), null, modifier.size(size))
    } else {
        Box(modifier.size(size).padding(size * 0.08f).background(Brush.radialGradient(listOf(tier.tint, tier.shade)), CircleShape)
            .border(size * 0.06f, TavernPalette.brassLine, CircleShape), contentAlignment = Alignment.Center) {
            SfImage(if (tier == RankTier.MYTHIC) "flame.fill" else "crown.fill", Color.White, size * 0.36f)
        }
    }
}

/**
 * A badge turning in 3D: frames of the Meshy model's turn (scripts/brand/rank_badges.py). `turns` whole turns over
 * `durationMillis`, easing to a stop front on; `forever` keeps turning. Reduce motion shows the still.
 */
@Composable
fun RankSpinEmblem(tier: RankTier, size: Dp = 96.dp, startKey: Any = Unit, turns: Float = 2f, durationMillis: Int = 1400,
                   forever: Boolean = false, reverse: Boolean = false) {
    val context = LocalContext.current
    if (LaunchEnvironment.reduceMotion) { RankEmblem(tier, size); return }
    var elapsed by remember(startKey) { mutableLongStateOf(0L) }
    LaunchedEffect(startKey, forever) {
        val start = withFrameMillis { it }
        while (true) {
            val now = withFrameMillis { it }
            elapsed = now - start
            if (!forever && elapsed >= durationMillis) break
        }
    }
    val progress = if (forever) elapsed.toFloat() / durationMillis else (elapsed.toFloat() / durationMillis).coerceAtMost(1f)
    if (!forever && progress >= 1f) { RankEmblem(tier, size); return }
    val turned = if (forever) progress else turns * (1f - (1f - progress).pow(3))
    val raw = (turned * RankArt.SPIN_FRAMES).toInt() % RankArt.SPIN_FRAMES
    val index = if (reverse) (RankArt.SPIN_FRAMES - raw) % RankArt.SPIN_FRAMES else raw
    val id = RankArt.id(context, "${tier.drawableName}_spin_${"%02d".format(index)}")
    if (id != 0) Image(painterResource(id), null, Modifier.size(size))
    else Box(Modifier.size(size).graphicsLayer { rotationY = (if (reverse) -1 else 1) * turned * 360f }) { RankEmblem(tier, size) }
}

private val DiamondShape = GenericShape { size, _ ->
    moveTo(size.width / 2, 0f); lineTo(size.width, size.height / 2); lineTo(size.width / 2, size.height); lineTo(0f, size.height / 2); close()
}

/** Pips toward the next division: little cut gems in a brass row. */
@Composable
fun RankPips(filled: Int, tier: RankTier, size: Dp = 14.dp, highlight: Int? = null, total: Int = RankPosition.PIPS_PER_DIVISION) {
    Row(Modifier.semantics { contentDescription = "$filled of $total pips" }, horizontalArrangement = Arrangement.spacedBy(size * 0.45f)) {
        for (index in 0 until total) {
            val on = index < filled
            Box(Modifier.size(size, size * 1.25f).scale(if (index == highlight) 1.25f else 1f)
                .then(if (on) Modifier.glow(tier.tint.copy(alpha = if (index == highlight) 1f else 0.55f), if (index == highlight) size * 0.6f else size * 0.2f, size / 2) else Modifier)
                .clip(DiamondShape)
                .background(if (on) Brush.verticalGradient(listOf(Color.White, tier.tint, tier.shade)) else Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.55f))))
                .border(maxOf(1.dp, size * 0.1f), TavernPalette.brassLine, DiamondShape))
        }
    }
}

/** The emblem with its division on a brass plate, optionally its title and pips; `spinKey` turns it in first. */
@Composable
fun RankBadge(position: RankPosition, size: Dp = 96.dp, showsPips: Boolean = true, showsTitle: Boolean = false,
              spinKey: Any? = null, spinTurns: Float = 1f, spinMillis: Int = 1200, spinReverse: Boolean = false, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {
        contentDescription = if (position.tier == RankTier.MYTHIC) "Rank ${position.title}, ${position.pips} points" else "Rank ${position.title}, ${position.pips} of 4 pips"
    }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(size * 0.06f)) {
        Box(contentAlignment = Alignment.BottomCenter) {
            if (spinKey != null) RankSpinEmblem(position.tier, size, spinKey, spinTurns, spinMillis, reverse = spinReverse) else RankEmblem(position.tier, size)
            if (position.tier != RankTier.MYTHIC) {
                Text(position.divisionNumeral, Modifier.offset(y = size * 0.06f).defaultMinSize(minWidth = size * 0.3f, minHeight = size * 0.2f)
                    .glow(Color.Black.copy(alpha = 0.5f), 2.dp, size)
                    .background(Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), TavernPalette.brass, rgb(0.55, 0.36, 0.12))), CircleShape)
                    .border(1.dp, Color.Black.copy(alpha = 0.35f), CircleShape).padding(horizontal = size * 0.08f),
                    color = rgb(0.25, 0.12, 0.04), style = sf(max(10f, size.value * 0.15f), SfWeight.black, SfDesign.SERIF), textAlign = TextAlign.Center)
            }
        }
        if (showsTitle) Text(position.title, style = sf(max(13f, size.value * 0.17f), SfWeight.black, SfDesign.SERIF)
            .copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), position.tier.tint))).engraved())
        if (showsPips) {
            if (position.tier == RankTier.MYTHIC) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("flame.fill", position.tier.tint, 12.dp)
                Text("${position.pips}", color = position.tier.tint, style = sf(max(11f, size.value * 0.13f), SfWeight.heavy, SfDesign.SERIF))
            } else RankPips(position.pips, position.tier, maxOf(8.dp, size * 0.12f))
        }
    }
}

/** A deck's bracket as a small tavern tag with the bracket's jewel. */
@Composable
fun BracketTag(bracket: CommanderBracket, short: Boolean = false, leather: Boolean = true) {
    TavernTag(if (short) "B${bracket.level}" else bracket.title, Modifier.semantics { contentDescription = bracket.title }, leather = leather, accent = bracket.tint)
}

// MARK: - Page chrome

@Composable
fun TavernScreenHeader(title: String, back: () -> Unit, backTitle: String = "Main menu") {
    Row(Modifier.fillMaxWidth().tavernTitleBar(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(44.dp).clickable { GameAudio.play(GameSound.UI_BACK); back() }.semantics { contentDescription = backTitle }.testTag("lobby.back"),
            contentAlignment = Alignment.Center) { SfImage("chevron.left", TavernPalette.brass, 15.dp) }
        TavernPanelTitle(title, Modifier.semantics { heading() })
    }
}

fun Modifier.parchmentCard(): Modifier = this.fillMaxWidth()
    .glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp)
    .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(12.dp), overlayBrush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.12f))))
    .tavernBrassFrame(1f)
    .padding(16.dp)

fun Modifier.leatherCard(): Modifier = this.fillMaxWidth().glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp).tavernPanel(12.dp).padding(16.dp)

@Composable
fun TavernLobbyPage(title: String, back: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            Box(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) { TavernScreenHeader(title, back) }
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, color: Color = TavernPalette.brass) {
    Text(text.uppercase(), Modifier.semantics { heading() }, color = color, style = sf(11f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f))
}

// MARK: - Mode chooser

@Composable
fun PlayModeChooser(rank: RankPosition, seasonName: String, quick: () -> Unit, ranked: () -> Unit, custom: () -> Unit, back: () -> Unit) {
    TavernLobbyPage("Play Commander", back) {
        ModeCard("Quick Match", "One AI opponent at your deck's bracket. Choose the bracket, deck and skill, or let the tavern pick.", "play.quick", quick) {
            SfImage("bolt.fill", TavernPalette.brass, 26.dp)
        }
        ModeCard("Ranked", "1v1 from Bronze to Mythic. Win to climb, lose and you slip. Season: $seasonName.", "play.ranked", ranked) {
            RankBadge(rank, 52.dp, showsPips = false)
        }
        ModeCard("Custom Table", "Up to three AI opponents, or an online table with friends on iPhone and Android.", "play.custom", custom) {
            SfImage("person.3.fill", TavernPalette.brass, 22.dp)
        }
    }
}

@Composable
private fun ModeCard(title: String, detail: String, tag: String, action: () -> Unit, icon: @Composable () -> Unit) {
    Row(Modifier.clickable { GameAudio.play(GameSound.UI_OPEN); action() }.testTag(tag).semantics(mergeDescendants = true) { contentDescription = "$title. $detail" }
        .parchmentCard(), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(64.dp).background(TavernPalette.leather.copy(alpha = 0.9f), CircleShape).border(2.dp, TavernPalette.brassLine, CircleShape),
            contentAlignment = Alignment.Center) { icon() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = parchmentInk, style = sf(21f, SfWeight.black, SfDesign.SERIF))
            Text(detail, color = parchmentInk.copy(alpha = 0.78f), style = sf(14f, SfWeight.medium, SfDesign.SERIF))
        }
        SfImage("chevron.right", brassLabel, 15.dp)
    }
}

// MARK: - Deck + bracket

@Composable
fun PlayDeckSection(deckName: String?, commander: String?, bracket: CommanderBracket?, canDeclare: Boolean, deckID: String,
                    sections: List<TavernPickerSection<String>>, selectDeck: (String) -> Unit, editDecks: () -> Unit, explainBracket: () -> Unit,
                    enabled: Boolean = true) {
    Column(Modifier.parchmentCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            CommanderDeckPortrait(commander, Modifier.size(84.dp, 117.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("YOUR DECK", color = brassLabel, style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.6f))
                Text(deckName ?: "Choose a deck", color = parchmentInk, style = sf(19f, SfWeight.black, SfDesign.SERIF))
                commander?.let { Text(it, color = parchmentInk.copy(alpha = 0.75f), style = sf(13f, SfWeight.regular, SfDesign.SERIF)) }
                if (bracket != null) Row(Modifier.defaultMinSize(minHeight = 44.dp).clickable(onClick = explainBracket).testTag("play.deck.bracket")
                    .semantics(mergeDescendants = true) { contentDescription = "${bracket.title}. Bracket details" },
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    BracketTag(bracket)
                    SfImage(if (canDeclare) "slider.horizontal.3" else "info.circle", brassLabel, 12.dp)
                }
            }
        }
        TavernPicker("Your deck", deckID, sections, selectDeck, Modifier.testTag("play.deck"), enabled = enabled)
        TavernPlaqueButton("Browse, import or edit decks", editDecks, kind = TavernButtonKind.SECONDARY, systemImage = "rectangle.stack.badge.plus", enabled = enabled)
    }
}

/** Why a deck is in its bracket, and the player's own label for it (nil `declared` for included decks). */
@Composable
fun DeckBracketSheet(deckName: String, report: BracketReport, declared: CommanderBracket?, fixedBracket: CommanderBracket?,
                     setDeclared: ((CommanderBracket?) -> Unit)?, close: () -> Unit) {
    val effective = fixedBracket ?: DeckBracketPreference.effective(report.minimum, declared)
    Box(Modifier.fillMaxWidth()) {
        TavernSheetBackground(Modifier.matchParentSizeCompat())
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth().tavernTitleBar(), verticalAlignment = Alignment.CenterVertically) {
                TavernPanelTitle("Bracket", Modifier.weight(1f))
                TavernSealButton(close, Modifier.testTag("bracket.close"), contentDescription = "Done")
            }
            Column(Modifier.parchmentCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(deckName, color = parchmentInk, style = sf(20f, SfWeight.black, SfDesign.SERIF))
                BracketTag(effective, leather = false)
                Text(effective.blurb, color = parchmentInk.copy(alpha = 0.8f), style = sf(14f, SfWeight.regular, SfDesign.SERIF))
            }
            Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionLabel("What the list shows")
                if (report.reasons.isEmpty()) Text("No Game Changers, mass land denial, chained extra turns or two-card combos: Bracket 2 at most.",
                    color = TavernPalette.parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
                for (line in report.reasons) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("◆", color = TavernPalette.brass, style = sf(8f))
                    Text(line, color = TavernPalette.parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
                }
                Text("Lowest bracket for this list: ${report.minimum.title}.", color = TavernPalette.parchment.copy(alpha = 0.8f),
                    style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
            }
            if (setDeclared != null) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("Your call")
                Text("Brackets are also about intent. Raise the bracket if the deck plays stronger than its list shows. A Core list may be called Exhibition.",
                    color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF))
                TavernPicker("Bracket", declared, listOf(TavernPickerSection(null, listOf<Pair<String, CommanderBracket?>>("Use the list (${report.minimum.title})" to null) +
                    DeckBracketPreference.choices(report.minimum).filter { it != report.minimum }.map { it.title to it })), setDeclared,
                    Modifier.testTag("bracket.declare"))
            }
        }
    }
}

private fun Modifier.matchParentSizeCompat(): Modifier = this.fillMaxSize()

// MARK: - Quick Match

@Composable
fun QuickMatchScreen(deckBracket: CommanderBracket?, opponentBracket: Int, setOpponentBracket: (Int) -> Unit, opponentDeckID: String,
                     setOpponentDeckID: (String) -> Unit, aiSkill: Int, setAISkill: (Int) -> Unit, startingMode: String, setStartingMode: (String) -> Unit,
                     pool: List<AIDeck>, mayStart: Boolean, status: String?, start: () -> Unit, back: () -> Unit, deckSlot: @Composable () -> Unit) {
    val resolved = if (opponentBracket == 0) minOf(4, deckBracket?.level ?: 2) else opponentBracket
    val poolDecks = AIDeckPool.pool(resolved, pool)
    LaunchedEffect(resolved) { if (opponentDeckID.isNotEmpty() && poolDecks.none { it.id == opponentDeckID }) setOpponentDeckID("") }
    TavernLobbyPage("Quick Match", back) {
        deckSlot()
        Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionLabel("Your opponent")
            TavernPicker("Opponent bracket", opponentBracket, listOf(
                TavernPickerSection(null, listOf((deckBracket?.let { "Match my deck (Bracket ${minOf(4, it.level)})" } ?: "Match my deck") to 0)),
                TavernPickerSection("Choose", CommanderBracket.entries.filter { it != CommanderBracket.CEDH }.map { it.title to it.level })),
                setOpponentBracket, Modifier.testTag("quick.bracket"))
            TavernPicker("Opponent deck", opponentDeckID, listOf(TavernPickerSection(null, listOf("Surprise me" to "")),
                TavernPickerSection("Bracket $resolved decks", poolDecks.map { "${it.name} · ${it.commander}" to it.id })), setOpponentDeckID,
                Modifier.testTag("quick.deck"))
            TavernStepper("AI skill: $aiSkill", aiSkill, 1..10, setAISkill, Modifier.testTag("quick.skill"), color = TavernPalette.parchment)
            Text("3 is a fair fight. Higher skill thinks longer and may slow turns.", color = TavernPalette.parchment.copy(alpha = 0.7f),
                style = sf(12f, SfWeight.regular, SfDesign.SERIF))
            TavernPicker("Who goes first?", startingMode, listOf(TavernPickerSection(null, listOf("Choose at the table" to "choose", "Roll a D20" to "roll"))),
                setStartingMode, Modifier.testTag("quick.startingPlayer"))
        }
        status?.let { Text(it, color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF)) }
        TavernButton({ GameAudio.play(GameSound.MENU_PLAY); start() }, Modifier.testTag("quick.start").semantics { contentDescription = "Start Quick Match" },
            fontSize = 17f, fullWidth = true, enabled = mayStart) {
            SfImage("flame.fill", rgb(1.0, 0.91, 0.66), 15.dp)
            TavernButtonText("Start Quick Match")
        }
    }
}

// MARK: - Ranked

@Composable
fun RankedLobbyScreen(rank: RankState, deckBracket: CommanderBracket?, canSearchPeople: Boolean, mayStart: Boolean, status: String?,
                      find: () -> Unit, profile: () -> Unit, back: () -> Unit, deckSlot: @Composable () -> Unit) {
    val tier = rank.position.tier
    val eligible = (deckBracket?.level ?: 99) <= tier.maxDeckBracket
    val appeared = remember { Any() }
    TavernLobbyPage("Ranked", back) {
        Column(Modifier.leatherCard().testTag("ranked.standing"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            RankBadge(rank.position, 132.dp, showsPips = true, showsTitle = true, spinKey = appeared)
            val left = RankLadder.seasonEnd(rank.season)?.let { maxOf(0L, (it - System.currentTimeMillis() + 86_399_999) / 86_400_000) }
            Text("Season: ${RankLadder.seasonName(rank.season)}" + (left?.let { if (it == 1L) " · 1 day left" else " · $it days left" } ?: ""),
                color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                Stat("Wins", "${rank.wins}"); Stat("Losses", "${rank.losses}"); Stat("Peak", rank.peak.title)
            }
            TavernPlaqueButton("Your profile", profile, Modifier.testTag("ranked.profile"), kind = TavernButtonKind.SECONDARY, systemImage = "person.crop.circle")
        }
        deckSlot()
        Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionLabel("At ${tier.label}")
            val range = tier.opponentBrackets
            val brackets = if (range.first == range.last) "${range.first}" else "${range.first}–${range.last}"
            Rule("person.2.fill", "Opponents play Bracket $brackets decks. AI opponents play at skill ${tier.aiSkill}.")
            Rule("checkmark.seal.fill", "Your deck may be up to Bracket ${tier.maxDeckBracket}. A lower bracket earns +1 pip for each win.")
            Rule("arrow.up.arrow.down", "Each win fills a pip and each loss empties one. Four pips win a division; with none left a loss drops you a division.")
            if (tier < RankTier.GOLD) Rule("flame.fill", "Three wins in a row below Gold earn an extra pip.")
            Rule(if (canSearchPeople) "antenna.radiowaves.left.and.right" else "cpu",
                if (canSearchPeople) "We look for a player near your rank first. If nobody's searching, an AI takes the seat."
                else "Profiles are offline, so an AI takes the seat. AI games count the same.")
        }
        if (!eligible && deckBracket != null) Row(Modifier.testTag("ranked.ineligible"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SfImage("exclamationmark.triangle.fill", rgb(1.0, 0.72, 0.5), 14.dp)
            Text("${deckBracket.title} is above ${tier.label}'s limit (Bracket ${tier.maxDeckBracket}). Choose another deck.",
                color = rgb(1.0, 0.72, 0.5), style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
        }
        status?.let { Text(it, color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF)) }
        TavernButton({ GameAudio.play(GameSound.MENU_PLAY); find() }, Modifier.testTag("ranked.find").semantics { contentDescription = "Find Ranked Match" },
            fontSize = 17f, fullWidth = true, enabled = mayStart && eligible) {
            SfImage("shield.lefthalf.filled", rgb(1.0, 0.91, 0.66), 15.dp)
            TavernButtonText("Find Ranked Match")
        }
    }
}

@Composable
private fun Stat(title: String, value: String) {
    Column(Modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = TavernPalette.parchment, style = sf(18f, SfWeight.black, SfDesign.SERIF))
        Text(title.uppercase(), color = TavernPalette.parchment.copy(alpha = 0.7f), style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.2f))
    }
}

@Composable
private fun Rule(icon: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(20.dp).padding(top = 2.dp), contentAlignment = Alignment.Center) { SfImage(icon, TavernPalette.brass, 13.dp) }
        Text(text, color = TavernPalette.parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
    }
}

/** Searching the ranked queue: a turning badge, the time, and what happens next. */
@Composable
fun RankedSearchOverlay(phase: RankedMatchmaker.Phase, rank: RankPosition, playAI: () -> Unit, cancel: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.72f)).clickable(remember { MutableInteractionSource() }, null) {}
        .testTag("ranked.search"), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(20.dp).widthIn(max = 420.dp).fillMaxWidth().tavernPanel(16.dp).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            RankSpinEmblem(rank.tier, 110.dp, durationMillis = 2400, forever = true)
            if (phase is RankedMatchmaker.Phase.Matched) {
                Text("Challenger found", color = TavernPalette.parchment, style = sf(22f, SfWeight.black, SfDesign.SERIF))
                Text(phase.ticket.opponent ?: "Another player", color = TavernPalette.brass, style = sf(18f, SfWeight.bold, SfDesign.SERIF))
                Text("Setting the table…", color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(14f, SfWeight.regular, SfDesign.SERIF))
            } else {
                val since = (phase as? RankedMatchmaker.Phase.Searching)?.since ?: System.currentTimeMillis()
                var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
                LaunchedEffect(since) { while (true) { now = System.currentTimeMillis(); kotlinx.coroutines.delay(500) } }
                val elapsed = maxOf(0L, (now - since) / 1000)
                val left = maxOf(0L, RankedMatchmaker.SEARCH_MILLIS / 1000 - elapsed)
                Text("Looking for a challenger", color = TavernPalette.parchment, style = sf(22f, SfWeight.black, SfDesign.SERIF), textAlign = TextAlign.Center)
                Text("%d:%02d".format(elapsed / 60, elapsed % 60), color = TavernPalette.parchment, style = sf(30f, SfWeight.black, SfDesign.SERIF))
                Text("An AI takes the seat in $left s if nobody's searching.", color = TavernPalette.parchment.copy(alpha = 0.8f),
                    style = sf(13f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TavernPlaqueButton("Cancel", cancel, Modifier.testTag("ranked.search.cancel"), kind = TavernButtonKind.SECONDARY, compact = false)
                    TavernPlaqueButton("Play the AI now", playAI, Modifier.testTag("ranked.search.ai"), compact = false)
                }
            }
        }
    }
}

// MARK: - Result strip and rank moments

/** The result screen's rank strip: the badge, then each pip filling or emptying in turn, with any bonuses. */
@Composable
fun RankProgressPanel(change: RankChange) {
    var shown by remember(change) { mutableIntStateOf(change.before.points) }
    val position = RankPosition.ofPoints(shown)
    LaunchedEffect(change) {
        val step = if (change.after.points > change.before.points) 1 else -1
        if (change.after.points == change.before.points) return@LaunchedEffect
        if (LaunchEnvironment.reduceMotion) { shown = change.after.points; return@LaunchedEffect }
        kotlinx.coroutines.delay(700)
        while (shown != change.after.points) {
            shown += step
            GameAudio.play(if (step > 0) GameSound.COUNTER else GameSound.LIFE_LOSS)
            kotlinx.coroutines.delay(420)
        }
    }
    val delta = change.pipDelta
    val deltaText = when {
        delta > 0 -> if (delta == 1) "+1 pip" else "+$delta pips"
        delta < 0 -> if (delta == -1) "−1 pip" else "$delta pips"
        change.outcome == RankOutcome.LOSS -> "No pips to lose"
        else -> "No change"
    }
    Row(Modifier.fillMaxWidth().tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(10.dp), overlay = Color.Black.copy(alpha = 0.3f)).tavernBrassFrame(0.5f)
        .padding(12.dp).testTag("rank.progress").semantics(mergeDescendants = true) { contentDescription = "Ranked: ${change.after.title}. $deltaText" },
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        RankBadge(position, 64.dp, showsPips = false)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(position.title, style = sf(18f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), position.tier.tint))))
            if (position.tier == RankTier.MYTHIC) Text("🔥 ${position.pips}", color = position.tier.tint, style = sf(14f, SfWeight.heavy, SfDesign.SERIF))
            else RankPips(position.pips, position.tier, 13.dp, highlight = if (shown == change.before.points) null else if (delta >= 0) position.pips - 1 else position.pips)
            Text(deltaText, color = if (delta > 0) good else if (delta < 0) bad else TavernPalette.parchment.copy(alpha = 0.7f),
                style = sf(12f, SfWeight.heavy, SfDesign.SERIF))
            if (change.bonuses.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (bonus in change.bonuses) TavernTag(if (bonus == RankBonus.STREAK) "Win streak +1" else "Underdog +1", leather = true, accent = TavernPalette.ember)
            }
        }
    }
}

/**
 * A full-screen moment for moving up or down a division or tier: up, the old badge charges and bursts into
 * embers while the new one spins in under turning light; down, it cracks and falls away and the lower one settles.
 */
@Composable
fun RankCeremonyOverlay(change: RankChange, done: () -> Unit) {
    val promoted = change.after > change.before
    val tierChange = change.after.tier != change.before.tier
    var stage by remember(change) { mutableIntStateOf(0) }
    var finished by remember(change) { mutableStateOf(false) }
    var burstKey by remember(change) { mutableIntStateOf(0) }
    LaunchedEffect(change) {
        if (LaunchEnvironment.reduceMotion) { stage = 3; finished = true; GameAudio.play(if (promoted) GameSound.VICTORY else GameSound.DEFEAT); return@LaunchedEffect }
        stage = 1; GameAudio.play(if (promoted) GameSound.ABILITY else GameSound.LIFE_LOSS)
        kotlinx.coroutines.delay(if (promoted) 900 else 1100)
        burstKey++; GameAudio.play(if (promoted) GameSound.COMMANDER_CAST else GameSound.DEATH); stage = 2
        kotlinx.coroutines.delay(650); stage = 3
        if (promoted) GameAudio.play(GameSound.VICTORY)
        kotlinx.coroutines.delay(700); finished = true
    }
    val shake = rememberInfiniteTransition(label = "rankShake").animateFloat(-1f, 1f, infiniteRepeatable(tween(40, easing = LinearEasing), RepeatMode.Reverse), label = "shake")
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (stage > 0) 0.9f else 0f))
        // Only Continue closes it, so a stray tap never skips the moment.
        .clickable(remember { MutableInteractionSource() }, null) {}
        .testTag("rank.ceremony").semantics { contentDescription = if (promoted) "Ranked up to ${change.after.title}" else "Ranked down to ${change.after.title}" },
        contentAlignment = Alignment.Center) {
        if (promoted && stage >= 2) LightRays(change.after.tier.tint)
        if (burstKey > 0) EmberBurst(burstKey, if (promoted) change.after.tier.tint else rgb(0.55, 0.55, 0.55), promoted)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(Modifier.height(220.dp), contentAlignment = Alignment.Center) {
                if (stage < 2) {
                    Box(Modifier.graphicsLayer {
                        val s = if (stage == 1) (if (promoted) 1.1f else 0.96f) else 1f; scaleX = s; scaleY = s
                        translationX = if (stage == 1) shake.value * (if (promoted) 3f else 7f) * density else 0f
                    }.alpha(if (!promoted && stage >= 1) 0.75f else 1f)) {
                        RankBadge(change.before, 170.dp, showsPips = false, spinKey = if (stage == 1 && promoted) change else null, spinTurns = 1f, spinMillis = 900)
                        if (!promoted && stage >= 1) Cracks(Modifier.size(150.dp).align(Alignment.Center))
                    }
                } else {
                    val drop = remember(change) { Animatable(if (promoted) 2.2f else 0f) }
                    LaunchedEffect(change) { drop.animateTo(if (promoted) 1f else 0f, spring(0.55f, 300f)) }
                    Box(Modifier.graphicsLayer { scaleX = if (promoted) drop.value else 1f; scaleY = if (promoted) drop.value else 1f }
                        .glow(if (promoted) change.after.tier.tint.copy(alpha = 0.85f) else Color.Black.copy(alpha = 0.5f), if (promoted) 34.dp else 10.dp, 95.dp)) {
                        RankBadge(change.after, 190.dp, showsPips = false, spinKey = burstKey, spinTurns = if (promoted) 3f else 1f,
                            spinMillis = if (promoted) 1600 else 1100, spinReverse = !promoted)
                    }
                }
            }
            Column(Modifier.alpha(if (stage >= 3) 1f else 0f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (promoted) (if (tierChange) "NEW RANK" else "RANKED UP") else "RANKED DOWN",
                    color = if (promoted) TavernPalette.brass else rgb(0.85, 0.4, 0.35), style = sf(15f, SfWeight.black, SfDesign.SERIF, tracking = 4f))
                Text(change.after.title, style = sf(40f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(Color.White, change.after.tier.tint))))
                Text(if (promoted) "Your opponents grow stronger." else "Win your next games to climb back.", color = TavernPalette.parchment.copy(alpha = 0.8f),
                    style = sf(14f, SfWeight.medium, SfDesign.SERIF), textAlign = TextAlign.Center)
            }
            if (finished) TavernButton({ GameAudio.play(GameSound.UI_CONFIRM); done() }, Modifier.width(180.dp).testTag("rank.ceremony.continue"),
                fontSize = 18f) { TavernButtonText("Continue") }
            else Spacer(Modifier.height(44.dp))
        }
    }
}

@Composable
private fun LightRays(tint: Color) {
    val turn = rememberInfiniteTransition(label = "rays").animateFloat(0f, 360f, infiniteRepeatable(tween(24_000, easing = LinearEasing)), label = "rayTurn")
    Canvas(Modifier.fillMaxSize()) {
        val center = Offset(size.width / 2, size.height * 0.42f)
        val radius = max(size.width, size.height)
        for (index in 0 until 12) {
            val start = Math.toRadians((turn.value + index * 30).toDouble())
            val end = start + Math.toRadians(9.0)
            val path = Path().apply {
                moveTo(center.x, center.y)
                lineTo(center.x + (cos(start) * radius).toFloat(), center.y + (sin(start) * radius).toFloat())
                lineTo(center.x + (cos(end) * radius).toFloat(), center.y + (sin(end) * radius).toFloat())
                close()
            }
            drawPath(path, Brush.radialGradient(listOf(tint.copy(alpha = 0.35f), Color.Transparent), center, radius * 0.6f))
        }
    }
}

@Composable
private fun EmberBurst(key: Int, tint: Color, upward: Boolean) {
    var t by remember(key) { mutableStateOf(0f) }
    LaunchedEffect(key) { val start = withFrameMillis { it }; while (t < 2.6f) { t = (withFrameMillis { it } - start) / 1000f } }
    Canvas(Modifier.fillMaxSize()) {
        if (t >= 2.6f) return@Canvas
        val center = Offset(size.width / 2, size.height * 0.42f)
        for (index in 0 until 46) {
            val seed = index * 12.9898
            val angle = seed % (2 * PI)
            val speed = (120 + (seed * 7) % 220) * density
            val gravity = if (upward) -40.0 * density else 260.0 * density
            val x = center.x + (cos(angle) * speed * t).toFloat()
            val y = center.y + (sin(angle) * speed * t * (if (upward) 1.0 else 0.4) + 0.5 * gravity * t * t).toFloat()
            val life = (1f - t / 2.4f).coerceAtLeast(0f)
            val r = ((2 + (seed * 3) % 4) * life * density).toFloat()
            drawCircle(tint.copy(alpha = life * 0.25f), r * 2, Offset(x, y))
            drawCircle(tint.copy(alpha = life), r, Offset(x, y))
        }
    }
}

@Composable
private fun Cracks(modifier: Modifier) {
    Canvas(modifier) {
        val lines = listOf(listOf(0.5f to 0.45f, 0.38f to 0.3f, 0.33f to 0.12f), listOf(0.5f to 0.45f, 0.66f to 0.36f, 0.82f to 0.38f),
            listOf(0.5f to 0.45f, 0.55f to 0.62f, 0.47f to 0.86f), listOf(0.55f to 0.62f, 0.72f to 0.7f), listOf(0.38f to 0.3f, 0.2f to 0.4f))
        for (line in lines) {
            val path = Path().apply { line.forEachIndexed { i, (x, y) -> if (i == 0) moveTo(x * size.width, y * size.height) else lineTo(x * size.width, y * size.height) } }
            drawPath(path, Color.Black.copy(alpha = 0.85f), style = Stroke(3.dp.toPx()))
            drawPath(path, Color.White.copy(alpha = 0.35f), style = Stroke(1.dp.toPx()))
        }
    }
}

// MARK: - Profile

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PlayerProfileScreen(store: PlayerRecordStore, playerName: String, back: () -> Unit) {
    val file = store.file
    val stats = remember(file.matches) { PlayerStats(file.matches) }
    val unlocked = remember(file.matches, file.rank) { Achievement.unlocked(file.matches, file.rank) }
    var showAll by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { store.refreshSeason() }
    TavernLobbyPage("Profile", back) {
        Row(Modifier.leatherCard(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(84.dp).clip(CircleShape).border(3.dp, TavernPalette.brassLine, CircleShape)) {
                CommanderDeckPortrait(store.shownCommander, Modifier.size(84.dp, 117.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                FitText(playerName.ifBlank { "Player" }, sf(24f, SfWeight.black, SfDesign.SERIF), Modifier.testTag("profile.name"), color = TavernPalette.parchment, minimumScale = 0.7f)
                TavernPicker("Title", file.title, listOf(TavernPickerSection(null, listOf<Pair<String, Achievement?>>("No title" to null) +
                    Achievement.entries.filter { it in unlocked }.map { it.title to it })), { store.setTitle(it) }, Modifier.testTag("profile.title"))
                TavernPicker("Favorite commander", file.favoriteCommander, listOf(TavernPickerSection(null, listOf<Pair<String, String?>>("Most played" to null) +
                    stats.commanders.take(12).map { it.label to it.label })), { store.setFavoriteCommander(it) }, Modifier.testTag("profile.commander"))
            }
        }
        Row(Modifier.leatherCard().testTag("profile.season"), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            RankBadge(file.rank.position, 104.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(file.rank.position.title, style = sf(22f, SfWeight.black, SfDesign.SERIF)
                    .copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), file.rank.position.tier.tint))))
                Text("Season ${RankLadder.seasonName(file.rank.season)}", color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
                Text("Ranked ${file.rank.wins}–${file.rank.losses} · Peak ${file.rank.peak.title}", color = TavernPalette.parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
                for (past in file.rank.history.take(4)) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    RankEmblem(past.peak.tier, 22.dp)
                    Text("${RankLadder.seasonName(past.season)}: ${past.peak.title}", Modifier.weight(1f), color = TavernPalette.parchment, style = sf(13f, SfWeight.regular, SfDesign.SERIF))
                    Text("${past.wins}–${past.losses}", color = TavernPalette.parchment.copy(alpha = 0.7f), style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                }
            }
        }
        Column(Modifier.leatherCard().testTag("profile.stats"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionLabel("Record")
            val tiles = listOf("Games" to "${stats.games}", "Wins" to "${stats.wins}",
                "Win rate" to (if (stats.games == 0) "–" else "${Math.round(stats.winRate * 100)}%"), "Streak" to "${stats.currentStreak}",
                "Best streak" to "${stats.bestStreak}", "Avg. turns" to (stats.averageTurns?.let { "%.1f".format(it) } ?: "–"))
            for (row in tiles.chunked(3)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((title, value) in row) Column(Modifier.weight(1f).defaultMinSize(minHeight = 58.dp).background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(8.dp))
                    .border(1.dp, TavernPalette.brass.copy(alpha = 0.4f), RoundedCornerShape(8.dp)).padding(6.dp).semantics(mergeDescendants = true) {},
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    FitText(value, sf(20f, SfWeight.black, SfDesign.SERIF), color = TavernPalette.parchment, minimumScale = 0.6f)
                    FitText(title.uppercase(), sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f), color = TavernPalette.parchment.copy(alpha = 0.7f), minimumScale = 0.7f)
                }
            }
        }
        if (stats.colors.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionLabel("Colors")
            for (line in stats.colors) Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "${line.label}: ${line.wins} wins in ${line.games} games" },
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                io.magicmobile.android.board.TavernAwareManaSymbol(line.id, 20.dp)
                Text(line.label, Modifier.width(64.dp), color = TavernPalette.parchment, style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
                Box(Modifier.weight(1f).height(10.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape)) {
                    Box(Modifier.fillMaxWidth(line.winRate.toFloat().coerceAtLeast(0.03f)).height(10.dp)
                        .background(Brush.horizontalGradient(listOf(rgb(1.0, 0.62, 0.32), TavernPalette.enamel)), CircleShape))
                }
                Text("${line.wins}/${line.games}", color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(12f, SfWeight.regular, SfDesign.SERIF))
            }
        }
        if (stats.decks.isNotEmpty()) Column(Modifier.parchmentCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionLabel("Your decks", brassLabel)
            for (line in stats.decks.take(6)) Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                CommanderDeckPortrait(line.detail, Modifier.size(34.dp, 47.dp))
                Column(Modifier.weight(1f)) {
                    Text(line.label, color = parchmentInk, style = sf(15f, SfWeight.bold, SfDesign.SERIF), maxLines = 1)
                    line.detail?.let { Text(it, color = parchmentInk.copy(alpha = 0.7f), style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 1) }
                }
                Text("${line.wins}–${line.games - line.wins}", color = parchmentInk, style = sf(14f, SfWeight.heavy, SfDesign.SERIF))
            }
        }
        Column(Modifier.leatherCard().testTag("profile.achievements"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionLabel("Achievements · ${unlocked.size}/${Achievement.entries.size}")
            for (row in Achievement.entries.chunked(2)) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (achievement in row) {
                    val earned = achievement in unlocked
                    Row(Modifier.weight(1f).alpha(if (earned) 1f else 0.5f).semantics(mergeDescendants = true) { contentDescription = "${achievement.title}. ${achievement.detail}. ${if (earned) "Earned" else "Locked"}" },
                        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(36.dp).background(Color.Black.copy(alpha = 0.4f), CircleShape)
                            .border(1.5.dp, if (earned) TavernPalette.brass else Color.Gray.copy(alpha = 0.5f), CircleShape), contentAlignment = Alignment.Center) {
                            SfImage(achievementIcon(achievement), if (earned) TavernPalette.brass else Color.Gray, 16.dp)
                        }
                        Column {
                            Text(achievement.title, color = TavernPalette.parchment, style = sf(13f, SfWeight.heavy, SfDesign.SERIF), maxLines = 1)
                            Text(achievement.detail, color = TavernPalette.parchment.copy(alpha = 0.75f), style = sf(11f, SfWeight.regular, SfDesign.SERIF))
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        Column(Modifier.leatherCard().testTag("profile.history"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionLabel("Match history")
            if (file.matches.isEmpty()) Text("Your games show here after you play.", color = TavernPalette.parchment.copy(alpha = 0.75f), style = sf(14f, SfWeight.regular, SfDesign.SERIF))
            for (match in file.matches.take(if (showAll) 60 else 8)) MatchRow(match)
            if (file.matches.size > 8) TavernPlaqueButton(if (showAll) "Show fewer" else "Show more", { showAll = !showAll }, kind = TavernButtonKind.SECONDARY)
        }
    }
}

private fun achievementIcon(a: Achievement): String = when (a) {
    Achievement.FIRST_WIN -> "star.fill"; Achievement.FIRST_RANKED_WIN -> "shield.lefthalf.filled"
    Achievement.SILVER, Achievement.GOLD, Achievement.PLATINUM, Achievement.DIAMOND, Achievement.MYTHIC -> "crown.fill"
    Achievement.STREAK5 -> "flame.fill"; Achievement.VETERAN -> "hourglass"; Achievement.PRISMATIC -> "circle.hexagongrid.fill"
    Achievement.GIANT_SLAYER -> "bolt.shield.fill"; Achievement.QUICK_DRAW -> "hare.fill"; Achievement.HUMAN_WIN -> "person.2.fill"
}

@Composable
private fun MatchRow(match: MatchRecord) {
    val names = match.opponents.map { it.name }
    val opponent = if (names.size <= 1) names.firstOrNull() ?: "Opponent" else "${names.size} opponents"
    val mode = when (match.mode) {
        PlayMode.QUICK -> "Quick"; PlayMode.RANKED -> if (match.vsHuman) "Ranked · Player" else "Ranked · AI"; PlayMode.CASUAL -> "Custom"
    }
    val date = java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(match.date))
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        val (letter, color) = when (match.outcome) { RankOutcome.WIN -> "W" to rgb(0.25, 0.5, 0.2); RankOutcome.LOSS -> "L" to rgb(0.45, 0.10, 0.08); RankOutcome.DRAW -> "D" to rgb(0.35, 0.35, 0.35) }
        Box(Modifier.size(30.dp).background(color, CircleShape).border(1.dp, TavernPalette.brass.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
            Text(letter, color = Color.White, style = sf(15f, SfWeight.black, SfDesign.SERIF))
        }
        Column(Modifier.weight(1f)) {
            Text("vs $opponent", color = TavernPalette.parchment, style = sf(14f, SfWeight.bold, SfDesign.SERIF), maxLines = 1)
            Text("$mode · ${match.deckName} · $date", color = TavernPalette.parchment.copy(alpha = 0.7f), style = sf(11f, SfWeight.regular, SfDesign.SERIF), maxLines = 1)
        }
        match.rankChange?.let { change ->
            Column(horizontalAlignment = Alignment.End) {
                Text(if (change.pipDelta > 0) "+${change.pipDelta}" else "${change.pipDelta}", color = if (change.pipDelta >= 0) good else bad, style = sf(13f, SfWeight.heavy, SfDesign.SERIF))
                Text(change.after.title, color = TavernPalette.parchment.copy(alpha = 0.7f), style = sf(10f, SfWeight.regular, SfDesign.SERIF))
            }
        }
    }
}

/** A friend's ranked card, opened from the friends list. */
@Composable
fun PlayerCardSheet(username: String, card: PlayerProfileCard?, loading: Boolean, close: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.fillMaxWidth().tavernTitleBar(), verticalAlignment = Alignment.CenterVertically) {
            TavernPanelTitle(username, Modifier.weight(1f))
            TavernSealButton(close, Modifier.testTag("playerCard.close"), contentDescription = "Done")
        }
        val position = card?.position
        when {
            loading -> CircularProgressIndicator(color = TavernPalette.brass, modifier = Modifier.padding(40.dp))
            card != null && position != null -> {
                RankBadge(position, 120.dp, showsPips = true, showsTitle = true)
                card.title?.let { TavernTag(it, leather = true, accent = TavernPalette.ember) }
                Text("Ranked ${card.wins ?: 0}–${card.losses ?: 0} this season", color = TavernPalette.parchment, style = sf(15f, SfWeight.regular, SfDesign.SERIF))
                card.peakStep?.let { Text("Peak ${RankPosition.atStep(it).title}", color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF)) }
                card.favoriteCommander?.let {
                    CommanderDeckPortrait(it, Modifier.size(90.dp, 125.dp))
                    Text(it, color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(13f, SfWeight.regular, SfDesign.SERIF))
                }
            }
            else -> {
                SfImage("shield.lefthalf.filled", TavernPalette.brass, 40.dp)
                Text("$username hasn't played ranked this season.", color = TavernPalette.parchment, style = sf(15f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}
