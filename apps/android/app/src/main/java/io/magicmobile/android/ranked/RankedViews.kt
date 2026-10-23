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
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.asImageBitmap
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
import androidx.compose.ui.semantics.role
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
import io.magicmobile.android.game.ProfileGame
import io.magicmobile.android.game.ProfileSummary
import io.magicmobile.android.game.RankBonus
import io.magicmobile.android.game.RankChange
import io.magicmobile.android.game.RankLadder
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankState
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.game.RankedMatchmaker
import io.magicmobile.android.social.PlayerProfileCard
import io.magicmobile.android.game.ArenaProfileRules
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaEmblem
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaSegmented
import io.magicmobile.android.menus.ArenaTabBar
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaGlassPanel
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.menus.arenaShadow
import androidx.compose.ui.composed
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

private val brassLabel = rgb(0.74, 0.46, 0.16)
private val good = rgb(0.6, 0.95, 0.55)
private val bad = rgb(1.0, 0.55, 0.45)

/** The rendered badge art (tavern_rank_*, from the iOS asset catalogue), resolved once per name. */
object RankArt {
    private val ids = HashMap<String, Int>()
    private val spins = HashMap<RankTier, List<androidx.compose.ui.graphics.ImageBitmap>>()
    const val SPIN_FRAMES = 32

    fun id(context: android.content.Context, name: String): Int = synchronized(ids) {
        ids.getOrPut(name) { context.resources.getIdentifier(name, "drawable", context.packageName) }
    }

    /**
     * A tier's spin frames, decoded off the main thread once and kept (painterResource decoded a new bitmap every
     * frame, which made the turn stutter). Empty when the art is missing.
     */
    suspend fun spinFrames(context: android.content.Context, tier: RankTier): List<androidx.compose.ui.graphics.ImageBitmap> {
        synchronized(spins) { spins[tier] }?.let { return it }
        val frames = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            (0 until SPIN_FRAMES).mapNotNull { index ->
                val id = id(context, "${tier.drawableName}_spin_${"%02d".format(index)}")
                if (id == 0) null else runCatching {
                    android.graphics.BitmapFactory.decodeResource(context.resources, id)?.also { it.prepareToDraw() }?.asImageBitmap()
                }.getOrNull()
            }
        }.takeIf { it.size == SPIN_FRAMES } ?: emptyList()
        synchronized(spins) { spins[tier] = frames }
        return frames
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
    var frames by remember(tier) { mutableStateOf<List<androidx.compose.ui.graphics.ImageBitmap>?>(null) }
    LaunchedEffect(tier) { frames = RankArt.spinFrames(context, tier) }
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
    val loaded = frames
    when {
        loaded == null -> RankEmblem(tier, size)  // decoding, first appearance only: hold the still front
        loaded.isNotEmpty() -> {
            // Neighbouring frames crossfade, so the slow end of the turn glides instead of stepping.
            val position = turned * RankArt.SPIN_FRAMES
            val raw = kotlin.math.floor(position).toInt()
            val blend = position - raw
            fun frame(step: Int): Int {
                val wrapped = ((step % RankArt.SPIN_FRAMES) + RankArt.SPIN_FRAMES) % RankArt.SPIN_FRAMES
                return if (reverse) (RankArt.SPIN_FRAMES - wrapped) % RankArt.SPIN_FRAMES else wrapped
            }
            Box(Modifier.size(size)) {
                Image(loaded[frame(raw)], null, Modifier.matchParentSize())
                Image(loaded[frame(raw + 1)], null, Modifier.matchParentSize(), alpha = blend)
            }
        }
        else -> Box(Modifier.size(size).graphicsLayer { rotationY = (if (reverse) -1 else 1) * turned * 360f }) { RankEmblem(tier, size) }
    }
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

/**
 * A lobby page's head (PlayModeViews.swift TavernScreenHeader). In the Arena menus: a back chevron where the page has
 * somewhere to go back to (`showsBack` false on a page a top-bar tab reaches) and the title in large type on the page, no bar.
 * Elsewhere the tavern's leather title bar, which always keeps its chevron.
 */
@Composable
fun TavernScreenHeader(title: String, back: () -> Unit, backTitle: String = "Main menu", showsBack: Boolean = true,
                       trailing: @Composable () -> Unit = {}) {
    if (io.magicmobile.android.menus.LocalArenaBoard.current) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (showsBack) Box(Modifier.size(40.dp, 44.dp).clickable { GameAudio.play(GameSound.UI_BACK); back() }
                .semantics { contentDescription = backTitle; role = androidx.compose.ui.semantics.Role.Button }.testTag("lobby.back"),
                contentAlignment = Alignment.Center) { SfImage("chevron.left", ArenaMenuStyle.text, 17.dp) }
            FitText(title, ArenaMenuStyle.font(24f, SfWeight.bold).arenaShadow(2f), Modifier.weight(1f).semantics { heading() },
                color = ArenaMenuStyle.text, minimumScale = 0.7f)
            trailing()
        }
        return
    }
    Row(Modifier.fillMaxWidth().tavernTitleBar(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(44.dp).clickable { GameAudio.play(GameSound.UI_BACK); back() }.semantics { contentDescription = backTitle }.testTag("lobby.back"),
            contentAlignment = Alignment.Center) { SfImage("chevron.left", TavernPalette.brass, 15.dp) }
        TavernPanelTitle(title, Modifier.weight(1f).semantics { heading() })
        trailing()
    }
}

/** A parchment card in brass trim: the lobby's sections. Glass in the Arena menus (TavernParchmentCard). Words take [parchmentCardInk]. */
fun Modifier.parchmentCard(): Modifier = composed {
    if (io.magicmobile.android.menus.LocalArenaBoard.current) arenaCard(16.dp)
    else fillMaxWidth()
        .glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp)
        .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(12.dp), overlayBrush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.12f))))
        .tavernBrassFrame(1f)
        .padding(16.dp)
}

/** The ink of words on a [parchmentCard]: dark on parchment, light on Arena's glass. */
val parchmentCardInk: Color @Composable get() = if (io.magicmobile.android.menus.LocalArenaBoard.current) ArenaMenuStyle.text else TavernPalette.ink

/** A leather card in brass trim, for controls in parchment-coloured text. Glass in the Arena menus (TavernLeatherCard). */
fun Modifier.leatherCard(): Modifier = composed {
    if (io.magicmobile.android.menus.LocalArenaBoard.current) arenaCard(16.dp)
    else fillMaxWidth().glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp).tavernPanel(12.dp).padding(16.dp)
}

/**
 * The page every lobby screen uses (PlayModeViews.swift TavernLobbyPage): the header on top, the content centred and capped.
 * An empty `title` with `showsBack` false in the Arena menus leaves the header out (the profile's name is its headline).
 * `contentWidth` widens the cap for a page laid out in columns sideways; `scrolls` false gives the content the page below
 * the title to lay out and scroll in its own columns. In the Arena menus the scroll fades at its foot.
 */
@Composable
fun TavernLobbyPage(title: String, back: () -> Unit, backTitle: String = "Main menu", showsBack: Boolean = true, contentWidth: Dp? = null,
                    scrolls: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val arena = io.magicmobile.android.menus.LocalArenaBoard.current
    val cap = contentWidth ?: if (arena) 760.dp else 640.dp
    Box(Modifier.fillMaxSize()) {
        // Inside the Arena menu shell the room is already drawn behind the page.
        if (!io.magicmobile.android.menus.LocalArenaMenuBackdrop.current) {
            if (arena) io.magicmobile.android.menus.ArenaRoomBackdrop(0.6f) else BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        }
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            if (title.isNotEmpty() || showsBack || !arena) {
                Box(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp)) { TavernScreenHeader(title, back, backTitle, showsBack || !arena) }
            }
            if (scrolls) {
                Column(Modifier.fillMaxWidth().weight(1f).then(if (arena) Modifier.arenaScrollFade() else Modifier)
                    .verticalScroll(rememberScrollState()).testTag("lobby.scroll"), horizontalAlignment = Alignment.CenterHorizontally) {
                    Column(Modifier.widthIn(max = cap).fillMaxWidth().padding(16.dp).padding(bottom = if (arena) 20.dp else 0.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
                }
            } else {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.TopCenter) {
                    Column(Modifier.widthIn(max = cap).fillMaxSize().padding(horizontal = 16.dp).padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, color: Color = TavernPalette.brass) {
    Text(text.uppercase(), Modifier.semantics { heading() }, color = color, style = sf(11f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f))
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
                Text(deckName, color = parchmentCardInk, style = sf(20f, SfWeight.black, SfDesign.SERIF))
                BracketTag(effective, leather = false)
                Text(effective.blurb, color = parchmentCardInk.copy(alpha = 0.8f), style = sf(14f, SfWeight.regular, SfDesign.SERIF))
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
    Row(Modifier.fillMaxWidth().arenaGlassPanel(12.dp, 0.95f)
        .padding(12.dp).testTag("rank.progress").semantics(mergeDescendants = true) { contentDescription = "Ranked: ${change.after.title}. $deltaText" },
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        RankBadge(position, 64.dp, showsPips = false)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(position.title, style = sf(18f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), position.tier.tint))))
            if (position.tier == RankTier.MYTHIC) Text("🔥 ${position.pips}", color = position.tier.tint, style = ArenaMenuStyle.font(14f, SfWeight.heavy))
            else RankPips(position.pips, position.tier, 13.dp, highlight = if (shown == change.before.points) null else if (delta >= 0) position.pips - 1 else position.pips)
            Text(deltaText, color = if (delta > 0) good else if (delta < 0) bad else TavernPalette.parchment.copy(alpha = 0.7f),
                style = ArenaMenuStyle.font(12f, SfWeight.heavy))
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
                    color = if (promoted) TavernPalette.brass else rgb(0.85, 0.4, 0.35), style = sf(15f, SfWeight.black, tracking = 4f))
                Text(change.after.title, style = sf(40f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(Color.White, change.after.tier.tint))))
                Text(if (promoted) "Your opponents grow stronger." else "Win your next games to climb back.", color = TavernPalette.parchment.copy(alpha = 0.8f),
                    style = ArenaMenuStyle.font(14f, SfWeight.medium), textAlign = TextAlign.Center)
            }
            if (finished) ArenaButton({ done() }, Modifier.width(180.dp), ArenaButtonKind.PRIMARY, identifier = "rank.ceremony.continue",
                fontSize = 18f, fullWidth = true) { ArenaButtonText("Continue") }
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
