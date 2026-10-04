package io.magicmobile.android.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.R
import io.magicmobile.android.board.TavernCommanderReadyGlow
import io.magicmobile.android.board.TavernManaGemFace
import io.magicmobile.android.board.TavernPhasePlate
import io.magicmobile.android.board.TavernRingLabel
import io.magicmobile.android.board.tavernFrameDrawable
import io.magicmobile.android.board.tavernTileGlow
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.game.HowToPlayPage
import io.magicmobile.android.game.HowToPlayText
import io.magicmobile.android.game.HowToPlayTutorial
import io.magicmobile.android.game.TavernCardParts
import io.magicmobile.android.game.TavernFrameKind
import io.magicmobile.android.studio.DeckStudioPlayText
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * "How to play" in the tavern (Caleb, 2026-10-03; iOS HowToPlayView.swift): a chooser between two
 * tutorials, each a book of parchment pages with an animated scene built from the table's own pieces.
 * [tutorialID] opens straight into one tutorial, which is how the first-launch walkthrough opens.
 */
@Composable
fun HowToPlayView(close: () -> Unit, modifier: Modifier = Modifier, tutorialID: String? = null) {
    var tutorial by remember { mutableStateOf(HowToPlayText.tutorials.firstOrNull { it.id == tutorialID }) }
    fun finish() { GameAudio.play(GameSound.UI_CLOSE); close() }
    fun open(next: HowToPlayTutorial?) { GameAudio.play(GameSound.PAGE_FLIP); tutorial = next }
    CompositionLocalProvider(LocalTavernBoard provides true) {
        Box(modifier) {
            val book = tutorial
            if (book != null) HowToPlayBook(book, backToChooser = if (tutorialID == null) ({ open(null) }) else null, close = ::finish)
            else HowToPlayChooser(choose = { open(it) }, close = ::finish)
        }
    }
}

// --- Chooser --------------------------------------------------------------------------------------

/** Two books on the leather: the short one on the table, the longer one on the format. */
@Composable
private fun HowToPlayChooser(choose: (HowToPlayTutorial) -> Unit, close: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp).tavernTitleBar().padding(start = 12.dp, end = 2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TavernPanelTitle(HowToPlayText.TITLE, Modifier.weight(1f).semantics { heading() })
                TavernSealButton(close, Modifier.testTag("howToPlay.close"), contentDescription = HowToPlayText.DONE)
            }
            val books: @Composable () -> Unit = { for (tutorial in HowToPlayText.tutorials) Book(tutorial, wide) { choose(tutorial) } }
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.widthIn(max = 760.dp)) {
                    if (wide) Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) { books() }
                    else Column(verticalArrangement = Arrangement.spacedBy(16.dp)) { books() }
                }
            }
        }
    }
}

@Composable
private fun Book(tutorial: HowToPlayTutorial, wide: Boolean, choose: () -> Unit) {
    Column(Modifier.then(if (wide) Modifier.width(360.dp) else Modifier.fillMaxWidth())
        .glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp)
        .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(12.dp), overlay = Color.Black.copy(alpha = 0.06f)).tavernBrassFrame(1f)
        .clickable(role = Role.Button) { choose() }
        .semantics { contentDescription = "${tutorial.title}. ${tutorial.subtitle}" }.testTag("howToPlay.tutorial.${tutorial.id}")
        .padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(52.dp).tavernFill(TavernMaterial.LEATHER, CircleShape).border(1.2.dp, BrandTheme.brassGradient, CircleShape),
                contentAlignment = Alignment.Center) {
                SfImage(if (tutorial.id == "commander") "crown.fill" else "square.grid.2x2", TavernPalette.brass, 22.dp)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(tutorial.title, color = TavernPalette.ink, style = sf(21f, SfWeight.black, SfDesign.SERIF))
                Text(tutorial.subtitle, color = TavernPalette.ink.copy(alpha = 0.75f), style = sf(14f, SfWeight.medium, SfDesign.SERIF))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Plaque(HowToPlayText.BEGIN, icon = "chevron.right") }
    }
}

// --- Book -------------------------------------------------------------------------------------------

/** One tutorial: engraved title, swipeable parchment pages, brass progress coins and the Back, Next and Done plaques. */
@Composable
private fun HowToPlayBook(tutorial: HowToPlayTutorial, backToChooser: (() -> Unit)?, close: () -> Unit) {
    val pages = tutorial.pages
    val pager = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()
    val reduceMotion = BoardMotionFlags.reduceMotion
    val index = pager.currentPage
    val isLast = index == pages.size - 1
    var turned by remember { mutableStateOf(false) }
    LaunchedEffect(index) { if (turned) GameAudio.play(GameSound.PAGE_FLIP) else turned = true }

    fun go(step: Int) {
        val next = (index + step).coerceIn(0, pages.size - 1)
        if (next == index) return
        scope.launch { if (reduceMotion) pager.scrollToPage(next) else pager.animateScrollToPage(next) }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp).tavernTitleBar().padding(start = 4.dp, end = 2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (backToChooser != null) {
                    Box(Modifier.size(44.dp).clickable(role = Role.Button, onClick = backToChooser).testTag("howToPlay.chooser")
                        .semantics { contentDescription = HowToPlayText.TITLE }, contentAlignment = Alignment.Center) {
                        SfImage("chevron.left", TavernPalette.parchment, 14.dp)
                    }
                } else Spacer(Modifier.width(8.dp))
                TavernPanelTitle(tutorial.title, Modifier.weight(1f).semantics { heading() })
                Box(Modifier.defaultMinSize(44.dp, 44.dp).alpha(if (isLast) 0f else 1f).testTag("howToPlay.skip")
                    .then(if (isLast) Modifier.clearAndSetSemantics {} else Modifier.clickable(role = Role.Button) { close() }),
                    contentAlignment = Alignment.Center) {
                    Text(HowToPlayText.SKIP, Modifier.padding(horizontal = 8.dp), color = TavernPalette.parchment.copy(alpha = 0.85f),
                        style = sf(15f, SfWeight.bold, SfDesign.SERIF))
                }
            }
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { page -> HowToPlayPageView(tutorial.id, pages[page], wide) }
            Column(Modifier.fillMaxWidth().widthIn(max = 560.dp).padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ProgressCoins(index, pages.size, reduceMotion, next = { go(1) }, back = { go(-1) })
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    TavernButton({ go(-1) }, Modifier.weight(1f).testTag("howToPlay.back"), kind = TavernButtonKind.SECONDARY, enabled = index > 0, fullWidth = true) {
                        TavernButtonText(HowToPlayText.BACK)
                    }
                    if (isLast) TavernButton({ close() }, Modifier.weight(1f).testTag("howToPlay.done"), fullWidth = true) { TavernButtonText(HowToPlayText.DONE) }
                    else TavernButton({ go(1) }, Modifier.weight(1f).testTag("howToPlay.next"), fullWidth = true) { TavernButtonText(HowToPlayText.NEXT) }
                }
            }
        }
    }
}

/** Brass coins, the current page's lit; TalkBack hears "Page 3 of 12", with Next and Back actions. */
@Composable
private fun ProgressCoins(index: Int, count: Int, reduceMotion: Boolean, next: () -> Unit, back: () -> Unit) {
    Row(Modifier.heightIn(min = 20.dp).testTag("howToPlay.progress").clearAndSetSemantics {
        contentDescription = HowToPlayText.progress(index + 1, count)
        liveRegion = LiveRegionMode.Polite
        customActions = listOf(CustomAccessibilityAction(HowToPlayText.NEXT) { next(); true },
            CustomAccessibilityAction(HowToPlayText.BACK) { back(); true })
    }, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { page ->
            val lit = page == index
            val size by animateDpAsState(if (lit) 11.dp else 7.dp, tween(if (reduceMotion) 0 else 200), label = "howToPlayCoin")
            Box(Modifier.size(size).background(if (lit) BrandTheme.brassGradient else Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Black.copy(alpha = 0.45f))), CircleShape)
                .border(1.dp, TavernPalette.brass.copy(alpha = if (lit) 1f else 0.45f), CircleShape))
        }
    }
}

/** One page: the scene in a leather inset, then the title and body on parchment. It scrolls, so large text never clips. */
@Composable
private fun HowToPlayPageView(tutorialID: String, page: HowToPlayPage, wide: Boolean) {
    val words: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier.widthIn(max = 480.dp).tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(12.dp)).tavernBrassFrame(0.8f).padding(16.dp),
            horizontalAlignment = if (wide) Alignment.Start else Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val align = if (wide) TextAlign.Start else TextAlign.Center
            Text(page.title, Modifier.semantics { heading() }, color = TavernPalette.ink, style = sf(24f, SfWeight.black, SfDesign.SERIF), textAlign = align)
            Text(page.body, color = TavernPalette.ink.copy(alpha = 0.85f), style = sf(16f, SfWeight.medium, SfDesign.SERIF), textAlign = align)
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp).testTag("howToPlay.page.${page.id}"),
        horizontalAlignment = Alignment.CenterHorizontally) {
        if (wide) Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
            HowToPlayScene("$tutorialID/${page.id}", Modifier.widthIn(max = 320.dp).fillMaxWidth(0.45f).height(210.dp))
            words(Modifier.weight(1f))
        } else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            HowToPlayScene("$tutorialID/${page.id}", Modifier.widthIn(max = 380.dp).fillMaxWidth().height(210.dp))
            words(Modifier)
        }
    }
}

// --- Scenes -----------------------------------------------------------------------------------------

/** Seconds since the scene appeared, looping scenes on one clock; a one-second still with reduced motion. */
@Composable
private fun sceneClock(): Double {
    val reduce = BoardMotionFlags.reduceMotion
    val t = rememberAnimationSeconds(reduce)
    return if (reduce) 1.0 else t.toDouble()
}

private fun loop(t: Double, period: Double) = t % period
private fun breath(t: Double, speed: Double = 2.4) = 0.5 + 0.5 * sin(t * speed)

/**
 * The lesson's picture in a leather inset. Decorative: the words say the same, so TalkBack skips it, and
 * its type ignores the font scale so it never grows out of its frame.
 */
@Composable
private fun HowToPlayScene(key: String, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, 1f)) {
        Box(modifier.tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(12.dp))
            .drawBehind { drawRect(Brush.radialGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.45f)), center, 260.dp.toPx())) }
            .tavernBrassFrame(1f).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            when (key) {
                "table/welcome" -> WelcomeScene()
                "table/decks" -> DecksScene()
                "table/start" -> StartScene()
                "table/board" -> TableScene()
                "table/casting" -> CastScene()
                "table/glow" -> GlowScene()
                "table/priority" -> PriorityScene()
                "table/combat" -> CombatScene(keywords = false)
                "table/piles" -> PileScene()
                "table/reading" -> ReadingScene()
                "table/resume" -> ResumeScene()
                "table/friends" -> FriendsScene()
                "commander/format" -> FormatScene()
                "commander/commander" -> CommanderScene()
                "commander/colors" -> ColorsScene()
                "commander/turn" -> TurnScene()
                "commander/mana" -> ManaScene()
                "commander/stack" -> StackScene()
                "commander/combat" -> CombatScene(keywords = true)
                "commander/permanents" -> PermanentsScene()
                "commander/winning" -> WinningScene()
            }
        }
    }
}

// Pieces

private val sceneInk = TavernPalette.ink

/** A framed battlefield tile as the lessons draw it: the real painted frame over a coloured art wash, a name on the ribbon. */
@Composable
private fun Tile(kind: TavernFrameKind = TavernFrameKind.CREATURE, name: String? = null, tint: Color = rgb(0.22, 0.40, 0.30), width: Dp = 56.dp,
                 symbol: String = "sparkle", modifier: Modifier = Modifier) {
    val w = width.value; val h = w * 1.08f
    val frame = tavernImage(tavernFrameDrawable(kind))
    val window = kind.window
    Box(modifier.requiredSize(width, h.dp).glow(Color.Black.copy(alpha = 0.5f), 3.dp, 6.dp)) {
        Box(Modifier.offset((w * window.minX).dp, (h * window.minY).dp).requiredSize((w * window.width).dp, (h * window.height).dp)
            .background(Brush.verticalGradient(listOf(tint, tint.copy(alpha = 0.5f), Color.Black.copy(alpha = 0.65f)))), contentAlignment = Alignment.Center) {
            SfImage(symbol, TavernPalette.brass.copy(alpha = 0.75f), (w * 0.24f).dp)
        }
        Box(Modifier.fillMaxSize().drawBehind { drawStretched(frame) })
        if (name != null) {
            val ribbon = tavernImage(R.drawable.tavern_card_ribbon)
            val ribbonHeight = w * TavernCardParts.ribbonAspect
            Box(Modifier.align(Alignment.TopCenter).offset(y = (h * TavernFrameKind.ribbonCenterY - ribbonHeight / 2).dp)
                .requiredSize(width, ribbonHeight.dp).drawBehind { drawStretched(ribbon) }, contentAlignment = Alignment.Center) {
                FitText(name, sf(maxOf(7f, w * 0.105f), SfWeight.bold, SfDesign.SERIF), Modifier.width((w * 0.62f).dp).offset(y = (-ribbonHeight * 0.06f).dp),
                    color = sceneInk, minimumScale = 0.55f, textAlign = TextAlign.Center)
            }
        }
    }
}

/** A player's medallion: initial in a brass ring, life on a coin below. */
@Composable
private fun Medallion(label: String = "A", life: Int? = 40, size: Dp = 46.dp, modifier: Modifier = Modifier) {
    val ring = tavernImage(R.drawable.tavern_pass_ring)
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().glow(Color.Black.copy(alpha = 0.5f), 3.dp, size / 2)
            .background(Brush.radialGradient(listOf(rgb(0.34, 0.20, 0.10), rgb(0.12, 0.07, 0.04))), CircleShape), contentAlignment = Alignment.Center) {
            Text(label, color = TavernPalette.parchment, style = sf(size.value * 0.42f, SfWeight.black, SfDesign.SERIF))
        }
        Box(Modifier.fillMaxSize().drawBehind { drawStretched(ring) })
        if (life != null) TavernCoin(life, size * 0.44f, Modifier.align(Alignment.BottomCenter).offset(y = size * 0.2f))
    }
}

/** The hourglass pass button's painted face. */
@Composable
private fun Hourglass(size: Dp = 60.dp, modifier: Modifier = Modifier) {
    val face = tavernImage(R.drawable.tavern_hourglass_button)
    Box(modifier.size(size).glow(Color.Black.copy(alpha = 0.5f), 4.dp, size / 2).drawBehind { drawStretched(face) })
}

/** A plaque as a label: the ember primary or the leather secondary button face. */
@Composable
private fun Plaque(text: String, icon: String? = null, primary: Boolean = true, modifier: Modifier = Modifier) {
    val ink = if (primary) rgb(1.0, 0.91, 0.66) else TavernPalette.parchment
    Row(modifier.height(34.dp).glow(Color.Black.copy(alpha = 0.45f), 3.dp, 17.dp)
        .tavernFill(if (primary) TavernMaterial.EMBER else TavernMaterial.LEATHER, CircleShape).tavernCapsuleRim()
        .padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) SfImage(icon, ink, 10.dp)
        Text(text, color = ink, style = sf(12f, SfWeight.heavy, SfDesign.SERIF).engraved(), maxLines = 1)
    }
}

/** A parchment name ribbon on its own, the banner under a showcased spell. */
@Composable
private fun Ribbon(text: String, width: Dp = 120.dp, modifier: Modifier = Modifier) {
    val ribbon = tavernImage(R.drawable.tavern_card_ribbon)
    Box(modifier.size(width, width * 0.24f).glow(Color.Black.copy(alpha = 0.5f), 3.dp, 4.dp).drawBehind { drawStretched(ribbon) },
        contentAlignment = Alignment.Center) {
        FitText(text, sf(width.value * 0.095f, SfWeight.heavy, SfDesign.SERIF), Modifier.width(width * 0.64f), color = sceneInk, minimumScale = 0.6f,
            textAlign = TextAlign.Center)
    }
}

/** A finger's touch: a brass ring that swells and fades. */
@Composable
private fun Touch(phase: Double, modifier: Modifier = Modifier) {
    val p = phase.coerceIn(0.0, 1.0)
    Box(modifier.size((18 + 26 * p).dp).alpha((1 - p).toFloat()).border(2.dp, TavernPalette.brass, CircleShape))
}

@Composable
private fun Note(text: String) = Text(text, color = TavernPalette.parchment.copy(alpha = 0.9f), style = sf(12f, SfWeight.semibold, SfDesign.SERIF))

// Table scenes

@Composable
private fun WelcomeScene() {
    val t = sceneClock()
    val mark = tavernImage(R.drawable.launch_mark)
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(contentAlignment = Alignment.Center) {
            Box(Modifier.size(130.dp).glow(BrandTheme.ember.copy(alpha = (0.18 + 0.12 * breath(t, 1.6)).toFloat()), 16.dp, 65.dp))
            Box(Modifier.size(96.dp).drawBehind { drawStretched(mark) })
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { TavernTag("COMMANDER"); TavernTag("RULES BY XMAGE") }
    }
}

@Composable
private fun DecksScene() {
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        Tile(TavernFrameKind.CREATURE, "Emmara", rgb(0.2, 0.45, 0.28), 78.dp, "crown.fill")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(8.dp)).border(1.2.dp, BrandTheme.brassGradient, RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("YOUR DECK", color = rgb(0.62, 0.16, 0.08), style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 2f))
                Text("Token Triumph", color = sceneInk, style = sf(17f, SfWeight.black, SfDesign.SERIF))
            }
            TavernTag("PLAYING", leather = true)
            Plaque(DeckStudioPlayText.play, icon = "play.fill")
        }
    }
}

@Composable
private fun StartScene() {
    val t = sceneClock()
    val roll = loop(t, 3.2)
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
        D20(78.dp, Modifier.rotate(if (roll < 1) (sin(roll * 18) * 14 * (1 - roll)).toFloat() else 0f))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.height(60.dp).width(100.dp), contentAlignment = Alignment.BottomCenter) {
                val kinds = listOf(TavernFrameKind.CREATURE, TavernFrameKind.LAND, TavernFrameKind.ARTIFACT)
                val tints = listOf(rgb(0.2, 0.4, 0.3), rgb(0.3, 0.3, 0.3), rgb(0.45, 0.3, 0.2))
                for (card in 0 until 3) Tile(kinds[card], tint = tints[card], width = 40.dp, modifier = Modifier.offset(x = ((card - 1) * 18).dp)
                    .graphicsLayer { rotationZ = (card - 1) * 12f; transformOrigin = TransformOrigin(0.5f, 1f) })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Plaque("Mulligan", primary = false); Plaque("Keep") }
        }
    }
}

/** The table in miniature, a brass ring pointing out each part in turn. */
@Composable
private fun TableScene() {
    val t = sceneClock()
    val callouts = listOf("Opponent", "The mat", "Your hand", "Turn plate", "Hourglass")
    val step = (loop(t, callouts.size * 1.5) / 1.5).toInt().coerceIn(0, callouts.size - 1)
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(150.dp, 190.dp).tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(10.dp), overlay = Color.Black.copy(alpha = 0.25f)).tavernBrassFrame(0.6f)) {
            Column(Modifier.fillMaxSize().padding(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Medallion("A", 40, 30.dp, Modifier.padding(start = 4.dp)); Spacer(Modifier.weight(1f)); TavernTag("TURN 3", leather = true)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally)) { repeat(3) { Tile(width = 22.dp) } }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally)) { repeat(3) { Tile(TavernFrameKind.ARTIFACT, tint = rgb(0.4, 0.3, 0.2), width = 22.dp) } }
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), verticalAlignment = Alignment.Bottom) {
                    Medallion("Y", 37, 30.dp, Modifier.padding(start = 4.dp))
                    Spacer(Modifier.weight(1f))
                    Box(Modifier.size(50.dp, 26.dp), contentAlignment = Alignment.BottomCenter) {
                        for (card in 0 until 4) Tile(TavernFrameKind.LAND, tint = rgb(0.2, 0.3, 0.4), width = 18.dp,
                            modifier = Modifier.offset(x = (card * 9 - 14).dp).graphicsLayer { rotationZ = card * 8f - 12f; transformOrigin = TransformOrigin(0.5f, 1f) })
                    }
                    Spacer(Modifier.weight(1f))
                    Hourglass(30.dp, Modifier.padding(end = 4.dp))
                }
            }
            val frames = listOf(listOf(4, 4, 40, 40), listOf(10, 48, 130, 76), listOf(48, 140, 56, 46), listOf(92, 8, 54, 26), listOf(106, 142, 40, 40))
            val f = frames[step]
            val x by animateDpAsState(f[0].dp, tween(350), label = "calloutX"); val y by animateDpAsState(f[1].dp, tween(350), label = "calloutY")
            val w by animateDpAsState(f[2].dp, tween(350), label = "calloutW"); val h by animateDpAsState(f[3].dp, tween(350), label = "calloutH")
            Box(Modifier.offset(x, y).size(w, h).glow(TavernPalette.brass.copy(alpha = 0.8f), 4.dp, 8.dp).border(2.dp, BrandTheme.brassGradient, RoundedCornerShape(8.dp)))
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            callouts.forEachIndexed { offset, label ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).background(if (offset == step) BrandTheme.brassGradient else Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.4f), Color.Black.copy(alpha = 0.4f))), CircleShape))
                    Text(label, color = TavernPalette.parchment.copy(alpha = if (offset == step) 1f else 0.6f),
                        style = sf(12f, if (offset == step) SfWeight.black else SfWeight.semibold, SfDesign.SERIF))
                }
            }
        }
    }
}

/** A hand card rises to the centre, hangs in its colour's light with its ribbon, then goes. */
@Composable
private fun CastScene() {
    val t = sceneClock()
    val p = loop(t, 3.4)
    val rise = minOf(1.0, p / 0.7)
    val lift = 1 - (1 - rise).pow(3)
    val fade = if (p > 2.8) maxOf(0.0, 1 - (p - 2.8) / 0.6) else 1.0
    val glow = if (p > 0.6) minOf(1.0, (p - 0.6) / 0.4) * fade else 0.0
    Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(130.dp, 190.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.offset(y = (70 - 90 * lift).dp).graphicsLayer { scaleX = (0.55 + 0.45 * lift).toFloat(); scaleY = scaleX; alpha = fade.toFloat() }) {
                Box(Modifier.alpha(glow.toFloat()).requiredSize(70.dp, 76.dp).tavernTileGlow(rgb(1.0, 0.95, 0.78)))
                Tile(TavernFrameKind.CREATURE, "Serra Angel", rgb(0.75, 0.7, 0.5), 70.dp, "sparkles")
            }
            Ribbon("Serra Angel", 110.dp, Modifier.offset(y = 62.dp).alpha(glow.toFloat()))
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                TavernTag("PAY COST"); TavernManaGemFace("W", 1, diameter = 22.dp); TavernManaGemFace("W", 0, diameter = 22.dp); TavernGenericGem(3)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                val tapped by animateFloatAsState(if (p > 1.2) 90f else 0f, tween(300), label = "landTap")
                Tile(TavernFrameKind.LAND, tint = rgb(0.35, 0.33, 0.3), width = 34.dp, modifier = Modifier.rotate(tapped))
                SfImage("hand.raised", TavernPalette.brass, 16.dp)
                Text("tap a land", color = TavernPalette.parchment.copy(alpha = 0.8f), style = sf(11f, SfWeight.semibold, SfDesign.SERIF))
            }
        }
    }
}

@Composable
private fun GlowScene() {
    val t = sceneClock()
    val b = breath(t).toFloat()
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box { Box(Modifier.requiredSize(56.dp, 60.dp).tavernTileGlow(rgb(0.3, 0.95, 0.45), 0.7f + 0.3f * b)); Tile(width = 56.dp) }
            TavernTag("PLAY", leather = true)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box { Box(Modifier.requiredSize(56.dp, 60.dp).tavernTileGlow(Color.Red, 0.7f + 0.3f * b)); Tile(tint = rgb(0.45, 0.2, 0.2), width = 56.dp) }
            TavernTag("TARGET", leather = true)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(60.dp), contentAlignment = Alignment.Center) {
                Tile(TavernFrameKind.ARTIFACT, tint = rgb(0.4, 0.3, 0.2), width = 56.dp, modifier = Modifier.rotate(90f).colorAdjust(0.3f, -0.12f))
            }
            TavernTag("TAPPED", leather = true)
        }
    }
}

/** The hourglass turns over on a tap; the skip ring waits beside it. */
@Composable
private fun PriorityScene() {
    val t = sceneClock()
    val p = loop(t, 3.0)
    val turn = if (p < 0.6) 0.0 else minOf(1.0, (p - 0.6) / 0.6)
    Row(horizontalArrangement = Arrangement.spacedBy(26.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(contentAlignment = Alignment.Center) {
            Hourglass(84.dp, Modifier.graphicsLayer { rotationY = (180 * (1 - (1 - turn).pow(2))).toFloat(); cameraDistance = 12f * density })
            if (p < 0.6) Touch(p / 0.6)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TavernTag("PASS PRIORITY")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TavernRingLabel { SfImage("forward.end.fill", TavernPalette.parchment, 13.dp) }
                Text("Skip", color = TavernPalette.parchment, style = sf(13f, SfWeight.bold, SfDesign.SERIF))
            }
            TavernStackTray(1, "Counterspell", {}, width = 124.dp)
        }
    }
}

/** An attacker lunges in its red light; a blocker steps into its way. The format's lesson adds the flying and reach badges. */
@Composable
private fun CombatScene(keywords: Boolean) {
    val t = sceneClock()
    val p = loop(t, 3.0)
    val lunge = when { p < 1 -> 0.0; p < 1.5 -> (p - 1) / 0.5; p < 2.4 -> 1.0; else -> maxOf(0.0, 1 - (p - 2.4) / 0.6) }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(40.dp), verticalAlignment = Alignment.Top) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (keywords) TavernTag("FLYING", leather = true)
                Box(Modifier.offset(y = (16 * lunge).dp)) {
                    Box(Modifier.alpha(lunge.toFloat()).requiredSize(58.dp, 63.dp).tavernTileGlow(Color.Red))
                    Tile(TavernFrameKind.CREATURE, "Attacker", rgb(0.5, 0.18, 0.15), 58.dp, "bolt.fill")
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (keywords) TavernTag("REACH", leather = true)
                Tile(TavernFrameKind.CREATURE, "Blocker", rgb(0.2, 0.35, 0.5), 58.dp, "shield.fill", Modifier.offset(y = (-10 * lunge).dp))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Plaque(HowToPlayText.BACK, primary = false); Plaque(if (keywords) "Done Blocking" else "Done Attacking") }
    }
}

@Composable
private fun PileScene() {
    val t = sceneClock()
    val p = loop(t, 2.6)
    val spread = if (p < 1.2) 0.0 else minOf(1.0, (p - 1.2) / 0.5)
    Row(horizontalArrangement = Arrangement.spacedBy(30.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(120.dp, 80.dp), contentAlignment = Alignment.Center) {
            for (card in 0 until 4) Tile(TavernFrameKind.TOKEN, "Soldier", rgb(0.75, 0.68, 0.5), 54.dp,
                modifier = Modifier.offset(x = (card * (4 + 18 * spread)).dp, y = (-card * (3 - 3 * spread)).dp))
            TavernCoin(9, 24.dp, Modifier.align(Alignment.BottomEnd).offset(x = 10.dp, y = 8.dp).alpha((1 - spread).toFloat()))
            if (p < 1.2) Touch(p / 1.2, Modifier.offset(x = (-20).dp, y = (-20).dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { TavernTag("TAP · NEXT", leather = true); TavernTag("HOLD · SPREAD", leather = true) }
    }
}

@Composable
private fun ReadingScene() {
    val t = sceneClock()
    val p = loop(t, 2.4)
    val held by animateFloatAsState(if (p > 1) 1.08f else 1f, tween(250), label = "holdScale")
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(contentAlignment = Alignment.Center) {
            Tile(TavernFrameKind.ENCHANTMENT, "Rhystic Study", rgb(0.2, 0.3, 0.5), 84.dp, "eye.fill", Modifier.graphicsLayer { scaleX = held; scaleY = held })
            if (p < 1) Touch(p)
        }
        Column(Modifier.tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(10.dp)).border(1.2.dp, BrandTheme.brassGradient, RoundedCornerShape(10.dp)).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("text.book.closed", rgb(0.62, 0.16, 0.08), 9.dp)
                Text("GAME LOG", color = rgb(0.62, 0.16, 0.08), style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.6f))
            }
            for (width in listOf(96, 70, 84, 58)) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(5.dp).background(TavernPalette.brass, CircleShape))
                Box(Modifier.size(width.dp, 5.dp).background(sceneInk.copy(alpha = 0.35f), CircleShape))
            }
        }
    }
}

@Composable
private fun ResumeScene() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Hourglass(44.dp); Text("10 min", color = TavernPalette.parchment, style = sf(26f, SfWeight.black, SfDesign.SERIF))
        }
        Column(Modifier.tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(12.dp)).tavernBrassFrame(0.7f).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(GameResumeText.PROMPT_TITLE, color = sceneInk, style = sf(13f, SfWeight.heavy, SfDesign.SERIF))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Plaque(GameResumeText.RESUME, icon = "play.fill"); Plaque(GameResumeText.ABANDON, primary = false) }
        }
    }
}

@Composable
private fun FriendsScene() {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Phone("Y")
        Box(contentAlignment = Alignment.Center) {
            Column(Modifier.tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(8.dp)).border(1.2.dp, BrandTheme.brassGradient, RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("TABLE CODE", color = rgb(0.62, 0.16, 0.08), style = sf(8f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f))
                Text("K7Q 2MX", color = sceneInk, style = sf(19f, SfWeight.black, SfDesign.MONOSPACED))
            }
            TavernTag("ONLINE", Modifier.align(Alignment.BottomCenter).offset(y = 16.dp), leather = true)
        }
        Phone("A")
    }
}

@Composable
private fun Phone(label: String) {
    Box(Modifier.size(48.dp, 86.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(10.dp)).border(1.5.dp, BrandTheme.brassGradient, RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center) { Medallion(label, null, 30.dp) }
}

// Commander scenes

@Composable
private fun FormatScene() {
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(150.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(96.dp).tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(10.dp), overlay = Color.Black.copy(alpha = 0.25f)).tavernBrassFrame(0.5f))
            Medallion("A", null, 30.dp, Modifier.offset(y = (-58).dp)); Medallion("B", null, 30.dp, Modifier.offset(x = 62.dp))
            Medallion("C", null, 30.dp, Modifier.offset(y = 58.dp)); Medallion("Y", null, 30.dp, Modifier.offset(x = (-62).dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { TavernCoin(100, 30.dp); Note("cards, one of each") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { TavernCoin(40, 30.dp); Note("life each") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(30.dp), contentAlignment = Alignment.Center) { SfImage("crown.fill", TavernPalette.brass, 14.dp) }; Note("a legendary leader")
            }
        }
    }
}

/** The commander rises from the command zone; each recast adds two to its cost. */
@Composable
private fun CommanderScene() {
    val t = sceneClock()
    val p = loop(t, 4.0)
    val rise = minOf(1.0, p / 0.8)
    val lift = 1 - (1 - rise).pow(3)
    val casts = minOf(2, (p / 1.5).toInt())
    Row(horizontalArrangement = Arrangement.spacedBy(26.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(90.dp, 190.dp), contentAlignment = Alignment.Center) {
            if (p < 0.5) TavernCommanderReadyGlow(50.dp)
            Medallion("Y", null, 50.dp)
            Tile(TavernFrameKind.CREATURE, "Commander", rgb(0.55, 0.42, 0.2), 60.dp, "crown.fill",
                Modifier.offset(y = (-8 - 74 * lift).dp).graphicsLayer { scaleX = (0.4 + 0.6 * lift).toFloat(); scaleY = scaleX; alpha = minOf(1.0, rise * 3).toFloat() })
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            TavernTag("COMMAND ZONE")
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                TavernGenericGem(3)
                repeat(casts) { Text("+2", color = TavernPalette.parchment, style = sf(13f, SfWeight.black, SfDesign.SERIF)) }
            }
            Note("the commander tax")
        }
    }
}

@Composable
private fun ColorsScene() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Tile(TavernFrameKind.CREATURE, "Emmara", rgb(0.2, 0.45, 0.28), 64.dp, "crown.fill")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (symbol in listOf("W", "U", "B", "R", "G")) {
                val lit = symbol == "G" || symbol == "W"
                TavernManaGemFace(symbol, if (lit) 1 else 0, Modifier.alpha(if (lit) 1f else 0.4f), diameter = 28.dp)
            }
        }
        TavernTag("GREEN AND WHITE ONLY", leather = true)
    }
}

@Composable
private fun TurnScene() {
    val t = sceneClock()
    val steps = listOf("UNTAP", "DRAW", "MAIN 1", "COMBAT", "MAIN 2", "END")
    val keys = listOf("untap", "draw", "precombat-main", "combat", "postcombat-main", "end")
    val current = (loop(t, steps.size * 1.1) / 1.1).toInt().coerceIn(0, steps.size - 1)
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TavernPhasePlate(keys[current], 3, width = 140.dp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            steps.forEachIndexed { offset, step ->
                val scale by animateFloatAsState(if (offset == current) 1.08f else 0.92f, tween(250), label = "turnStep")
                TavernTag(step, Modifier.graphicsLayer { scaleX = scale; scaleY = scale }, leather = offset != current)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("arrow.turn.down.right", TavernPalette.brass, 12.dp); Note("then the player on your left")
        }
    }
}

/** Three lands tap one after another and the rail's gems light up. */
@Composable
private fun ManaScene() {
    val t = sceneClock()
    val p = loop(t, 3.6)
    val tapped = minOf(3, (p / 0.7).toInt())
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            for (index in 0 until 3) {
                val turn by animateFloatAsState(if (index < tapped) 90f else 0f, tween(300), label = "landTap$index")
                Box(Modifier.size(54.dp), contentAlignment = Alignment.Center) {
                    Tile(TavernFrameKind.LAND, if (index == 2) "Plains" else "Forest", if (index == 2) rgb(0.6, 0.55, 0.4) else rgb(0.2, 0.4, 0.25), 46.dp,
                        modifier = Modifier.rotate(turn))
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TavernManaGemFace("G", minOf(2, tapped), diameter = 26.dp); TavernManaGemFace("W", if (tapped > 2) 1 else 0, diameter = 26.dp)
            TavernGenericGem(2); Note("= a 3-mana spell")
        }
    }
}

/** Spells pile onto the stack and the last one in resolves first. */
@Composable
private fun StackScene() {
    val t = sceneClock()
    val p = loop(t, 4.2)
    val names = listOf("Giant Growth", "Lightning Bolt", "Counterspell")
    val shown = minOf(3, (p / 0.8).toInt() + 1)
    val resolving = p > 2.8
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(130.dp, 120.dp), contentAlignment = Alignment.BottomCenter) {
            for (index in 0 until shown) {
                val fade = if (resolving && index == shown - 1) maxOf(0.0, 1 - (p - 2.8) / 0.6) else 1.0
                Ribbon(names[index], 128.dp, Modifier.offset(y = (-index * 30).dp).alpha(fade.toFloat()))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            TavernTag("LAST IN", leather = true); SfImage("chevron.down", TavernPalette.brass, 12.dp); TavernTag("FIRST OUT", leather = true)
        }
    }
}

@Composable
private fun PermanentsScene() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(contentAlignment = Alignment.BottomCenter) {
                Tile(width = 50.dp)
                SfImage("hourglass", rgb(1.0, 0.86, 0.56), 12.dp, Modifier.offset(y = 4.dp))
            }
            Tile(TavernFrameKind.ARTIFACT, tint = rgb(0.4, 0.3, 0.2), width = 50.dp)
            Tile(TavernFrameKind.ENCHANTMENT, tint = rgb(0.4, 0.25, 0.4), width = 50.dp)
            Tile(TavernFrameKind.LAND, tint = rgb(0.3, 0.32, 0.3), width = 50.dp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { for (name in listOf("CREATURE", "ARTIFACT", "ENCHANTMENT", "LAND")) TavernTag(name, leather = true) }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("hourglass", rgb(1.0, 0.86, 0.56), 11.dp); Note("summoning sick this turn")
        }
    }
}

@Composable
private fun WinningScene() {
    val t = sceneClock()
    val p = loop(t, 3.0)
    val life = maxOf(0, 40 - (p / 2.2 * 40).toInt())
    Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
        Medallion("A", life, 56.dp, Modifier.alpha(if (life == 0) 0.45f else 1f).colorAdjust(if (life == 0) 0.2f else 1f))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { TavernCoin(0, 26.dp); Note("life") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(26.dp), contentAlignment = Alignment.Center) { SfImage("circle.hexagongrid.fill", rgb(0.45, 0.85, 0.4), 13.dp) }; Note("10 poison")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(26.dp), contentAlignment = Alignment.Center) { SfImage("crown.fill", TavernPalette.brass, 13.dp) }; Note("21 from one commander")
            }
        }
    }
}

/** A D20 seen face-on in brass: a hexagon with the center face and its edges. */
@Composable
private fun D20(size: Dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).glow(TavernPalette.brass.copy(alpha = 0.4f), 10.dp, size / 2).drawBehind {
        val c = center; val r = this.size.minDimension / 2
        fun point(degrees: Double, scale: Double) = androidx.compose.ui.geometry.Offset(
            c.x + (cos(degrees * PI / 180) * scale * r).toFloat(), c.y + (sin(degrees * PI / 180) * scale * r).toFloat())
        val outer = listOf(-90.0, -30.0, 30.0, 90.0, 150.0, 210.0).map { point(it, 1.0) }
        val hex = Path().apply { moveTo(outer[0].x, outer[0].y); for (o in outer.drop(1)) lineTo(o.x, o.y); close() }
        drawPath(hex, BrandTheme.brassGradient)
        val inner = listOf(-90.0, 30.0, 150.0).map { point(it, 0.55) }
        val facets = Path().apply {
            moveTo(inner[0].x, inner[0].y); for (i in inner.drop(1)) lineTo(i.x, i.y); close()
            for ((corner, outerIndex) in inner.zip(listOf(0, 2, 4))) for (offset in listOf(-1, 0, 1)) {
                val o = outer[(outerIndex + offset + 6) % 6]; moveTo(corner.x, corner.y); lineTo(o.x, o.y)
            }
        }
        drawPath(facets, rgb(0.35, 0.2, 0.06).copy(alpha = 0.6f), style = Stroke(1.5.dp.toPx()))
        drawPath(hex, Color.White.copy(alpha = 0.3f), style = Stroke(1.dp.toPx()))
    }, contentAlignment = Alignment.Center) {
        Text("20", Modifier.offset(y = size * 0.04f), color = rgb(0.3, 0.16, 0.05), style = sf(size.value * 0.24f, SfWeight.black, SfDesign.SERIF))
    }
}
