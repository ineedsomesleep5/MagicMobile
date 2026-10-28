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
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.graphics.Shadow
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
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.magicmobile.android.R
import io.magicmobile.android.board.TavernCommanderReadyGlow
import io.magicmobile.android.board.TavernManaGemFace
import io.magicmobile.android.board.TavernPhasePlate
import io.magicmobile.android.board.TavernRingLabel
import io.magicmobile.android.board.tavernFrameDrawable
import io.magicmobile.android.board.tavernTileGlow
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.game.HowToPlayPage
import io.magicmobile.android.game.GuidedGameText
import io.magicmobile.android.game.HowToPlayText
import io.magicmobile.android.game.HowToPlayTutorial
import io.magicmobile.android.game.TavernCardParts
import io.magicmobile.android.game.TavernFrameKind
import io.magicmobile.android.menus.ArenaArt
import io.magicmobile.android.menus.ArenaButtonFace
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaEmblem
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPanelHeader
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaPlayButton
import io.magicmobile.android.menus.LocalArenaBoard
import io.magicmobile.android.menus.LocalArenaPanelClose
import io.magicmobile.android.menus.arenaGlassBackground
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.studio.DeckStudioPlayText
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * "How to play" (Caleb, 2026-10-03; Arena's look since 2026-10-22; iOS HowToPlayView.swift): a chooser of tutorial tiles over
 * card art, each tutorial a run of glass pages with an animated scene built from the table's own pieces. [tutorialID] opens
 * straight into one tutorial, which is how the first-launch walkthrough opens. The lessons' words are the shared
 * `HowToPlayText` (a parity golden).
 */
@Composable
fun HowToPlayView(close: () -> Unit, modifier: Modifier = Modifier, tutorialID: String? = null, playGuided: (() -> Unit)? = null,
                  playLesson: ((String) -> Unit)? = null) {
    var tutorial by remember { mutableStateOf(HowToPlayText.tutorials.firstOrNull { it.id == tutorialID }) }
    var lessons by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    fun finish() { GameAudio.play(GameSound.UI_CLOSE); close() }
    fun open(next: HowToPlayTutorial?) { GameAudio.play(GameSound.PAGE_FLIP); tutorial = next; lessons = false }
    // Inside a menu panel the panel's glass shows; in the game menu's sheet it draws its own.
    val inPanel = LocalArenaPanelClose.current != null
    CompositionLocalProvider(LocalArenaBoard provides true, androidx.compose.material3.LocalContentColor provides ArenaMenuStyle.text) {
        Box(modifier.then(if (inPanel) Modifier else Modifier.arenaGlassBackground())) {
            val book = tutorial
            if (lessons && playLesson != null) LessonListView(LessonAssets.all(context), play = { id -> finish(); playLesson(id) },
                playGuided = playGuided?.let { play -> { finish(); play() } }, back = { open(null) })
            else if (book != null) HowToPlayBook(book, backToChooser = if (tutorialID == null) ({ open(null) }) else null, close = ::finish)
            else HowToPlayChooser(choose = { open(it) }, playGuided = playGuided?.let { play -> { finish(); play() } },
                openLessons = if (playLesson == null) null else ({ GameAudio.play(GameSound.PAGE_FLIP); lessons = true }), close = ::finish)
        }
    }
}

// --- Chooser --------------------------------------------------------------------------------------

/**
 * Arena's Learn page: the tutorials as tiles over card art, side by side when the phone lies sideways (all one height, Begin on
 * one line along their foot) and stacked when it stands; the guided first game first when the menu offers it.
 */
@Composable
private fun HowToPlayChooser(choose: (HowToPlayTutorial) -> Unit, playGuided: (() -> Unit)?, openLessons: (() -> Unit)?, close: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val wide = maxWidth > maxHeight
        Column(Modifier.fillMaxWidth()) {
            ArenaPanelHeader(HowToPlayText.TITLE, closeIdentifier = "howToPlay.close", close = close)
            val books: @Composable (Modifier) -> Unit = { tile ->
                // The lessons first: short scripted games on the real board, the guided game as their last step.
                if (openLessons != null) Book("lessons", io.magicmobile.android.game.LessonText.TITLE, "", "graduationcap.fill", "Grizzly Bears",
                    listOf("G"), HowToPlayText.BEGIN, wide, tile, primary = true, choose = openLessons)
                else if (playGuided != null) Book("guided", GuidedGameText.TITLE, GuidedGameText.SUBTITLE, "graduationcap.fill", "Emmara, Soul of the Accord",
                    listOf("G", "W"), GuidedGameText.START, wide, tile, primary = true, choose = playGuided)
                for (tutorial in HowToPlayText.tutorials) {
                    val commander = tutorial.id == "commander"
                    Book(tutorial.id, tutorial.title, tutorial.subtitle, if (commander) "crown.fill" else "table.furniture",
                        if (commander) "The Ur-Dragon" else "Teferi, Temporal Archmage", if (commander) listOf("W", "U", "B", "R", "G") else listOf("U"),
                        HowToPlayText.BEGIN, wide, tile) { choose(tutorial) }
                }
            }
            if (wide) {
                // Sideways the tiles share one height, so nothing is left empty under them; at the largest text sizes they scroll.
                Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)) {
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).heightIn(min = 260.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        books(Modifier.weight(1f).fillMaxHeight())
                    }
                }
            } else {
                // Upright the three tiles fit the panel; shorter art keeps every Begin in view.
                Column(Modifier.fillMaxWidth().arenaScrollFade(20.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                    Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        books(Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}

/**
 * Arena's Learn tiles: a card's art over the title, its plaque at the tile's foot. What it teaches is TalkBack's (no
 * descriptions); the guided game is the one orange plaque, the tutorials dark, as Arena keeps orange for the single primary action.
 */
@Composable
private fun Book(id: String, title: String, subtitle: String, icon: String, art: String, colors: List<String>, action: String, wide: Boolean,
                 modifier: Modifier, primary: Boolean = false, choose: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    val frame = modifier.glow(Color.Black.copy(alpha = 0.5f), 8.dp, 12.dp).clip(shape).background(Color.Black.copy(alpha = 0.45f))
        .border(1.dp, ArenaGlass.hairline, shape)
        .clickable(role = Role.Button) { choose() }
        .semantics(mergeDescendants = true) { contentDescription = if (subtitle.isEmpty()) title else "$title. $subtitle" }.testTag("howToPlay.tutorial.$id")
    if (!wide) {
        // Upright, Arena's way (Caleb, 2026-10-26: the thin strips showed shoulders, not faces, under a gap): the art fills
        // the tile, framed on its upper part, with the title and plaque on a shade along its foot.
        Box(frame.fillMaxWidth().height(158.dp), contentAlignment = Alignment.BottomCenter) {
            ArenaArt(art, colors, Modifier.fillMaxSize().graphicsLayer { scaleX = 1.06f; scaleY = 1.06f }, focus = 0.3f)
            Box(Modifier.fillMaxWidth().height(96.dp).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.88f)))))
            Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(19f, SfWeight.bold).copy(shadow = Shadow(Color.Black, blurRadius = 6f)))
                Plaque(action, icon = "chevron.right", primary = primary)
            }
            Box(Modifier.align(Alignment.TopStart).padding(10.dp).size(34.dp).background(Color.Black.copy(alpha = 0.7f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape),
                contentAlignment = Alignment.Center) { ArenaEmblem(icon, 16.dp, lit = true) }
        }
        return
    }
    Column(frame) {
        Box(Modifier.fillMaxWidth().height(104.dp).clip(RoundedCornerShape(0.dp))) {
            // Cropped in from every edge, so a printing's frame never shows along the art's border.
            ArenaArt(art, colors, Modifier.fillMaxSize().graphicsLayer { scaleX = 1.14f; scaleY = 1.14f }, focus = 0.3f)
            Box(Modifier.padding(10.dp).size(34.dp).background(Color.Black.copy(alpha = 0.7f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape),
                contentAlignment = Alignment.Center) { ArenaEmblem(icon, 16.dp, lit = true) }
        }
        Column(Modifier.fillMaxWidth().weight(1f, fill = wide).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(19f, SfWeight.bold))
            Spacer(Modifier.height(10.dp).then(if (wide) Modifier.weight(1f) else Modifier))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Plaque(action, icon = "chevron.right", primary = primary) }
        }
    }
}

// --- Book -------------------------------------------------------------------------------------------

/** One tutorial: its title, swipeable glass pages, gold progress diamonds and the Back, Next and Done plaques. */
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
            // The panel's head, as ArenaPanelHeader draws it: back to the tutorials, the title in large type, and Skip.
            Row(Modifier.fillMaxWidth().padding(start = if (backToChooser == null) 18.dp else 6.dp, end = 10.dp, top = 6.dp)
                .drawBehind { drawRect(ArenaGlass.hairline, androidx.compose.ui.geometry.Offset(0f, size.height - 1.dp.toPx()),
                    androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()), alpha = 0.45f) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (backToChooser != null) {
                    BrandPressable(backToChooser, Modifier.size(40.dp, 44.dp).testTag("howToPlay.chooser")
                        .semantics { contentDescription = HowToPlayText.TITLE; role = Role.Button }) {
                        SfImage("chevron.left", ArenaMenuStyle.text, 16.dp)
                    }
                }
                FitText(tutorial.title, ArenaMenuStyle.font(22f, SfWeight.bold), Modifier.weight(1f).semantics { heading() }, color = ArenaMenuStyle.text,
                    minimumScale = 0.7f)
                Box(Modifier.alpha(if (isLast) 0f else 1f).then(if (isLast) Modifier.clearAndSetSemantics {} else Modifier)) {
                    ArenaPillButton(HowToPlayText.SKIP, { if (!isLast) close() }, enabled = !isLast, identifier = "howToPlay.skip")
                }
            }
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth().heightIn(min = if (wide) 214.dp else 460.dp)) { page ->
                HowToPlayPageView(tutorial.id, pages[page], wide)
            }
            // The gold diamonds, then Back as the dark pill and Next (or Done) as the orange one. Sideways the diamonds sit between
            // the two, so the whole page fits under the top bar.
            Column(Modifier.fillMaxWidth().then(if (wide) Modifier else Modifier.widthIn(max = 560.dp))
                .padding(start = 20.dp, end = 20.dp, top = if (wide) 2.dp else 6.dp, bottom = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!wide) ProgressDiamonds(index, pages.size, reduceMotion, next = { go(1) }, back = { go(-1) })
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    ArenaPlayButton(HowToPlayText.BACK, { go(-1) }, Modifier.weight(1f).height(46.dp).alpha(if (index == 0) 0.5f else 1f), cancel = true,
                        fontSize = 17f, enabled = index > 0, identifier = "howToPlay.back")
                    if (wide) ProgressDiamonds(index, pages.size, reduceMotion, next = { go(1) }, back = { go(-1) })
                    if (isLast) ArenaPlayButton(HowToPlayText.DONE, { close() }, Modifier.weight(1f).height(46.dp), fontSize = 17f, identifier = "howToPlay.done")
                    else ArenaPlayButton(HowToPlayText.NEXT, { go(1) }, Modifier.weight(1f).height(46.dp), fontSize = 17f, identifier = "howToPlay.next")
                }
            }
        }
    }
}

/** Gold diamonds, the current page's lit; TalkBack hears "Page 3 of 12", with Next and Back actions. */
@Composable
private fun ProgressDiamonds(index: Int, count: Int, reduceMotion: Boolean, next: () -> Unit, back: () -> Unit) {
    Row(Modifier.heightIn(min = 20.dp).testTag("howToPlay.progress").clearAndSetSemantics {
        contentDescription = HowToPlayText.progress(index + 1, count)
        liveRegion = LiveRegionMode.Polite
        customActions = listOf(CustomAccessibilityAction(HowToPlayText.NEXT) { next(); true },
            CustomAccessibilityAction(HowToPlayText.BACK) { back(); true })
    }, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { page ->
            val lit = page == index
            val size by animateDpAsState(if (lit) 8.dp else 5.5.dp, tween(if (reduceMotion) 0 else 200), label = "howToPlayDiamond")
            Box(Modifier.size(11.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(size).rotate(45f).glow(if (lit) ArenaMenuStyle.gold.copy(alpha = 0.7f) else Color.Transparent, 3.dp, 1.dp)
                    .then(if (lit) Modifier.background(ArenaMenuStyle.goldFill) else Modifier.background(Color.White.copy(alpha = 0.18f))))
            }
        }
    }
}

/**
 * One page: the scene in its dark inset, then the title and words on glass. The picture grows into the page's height, and
 * sideways the words' pane runs the picture's full height, so the two share their top and bottom edges; long words scroll.
 */
@Composable
private fun HowToPlayPageView(tutorialID: String, page: HowToPlayPage, wide: Boolean) {
    val words: @Composable (Modifier) -> Unit = { modifier ->
        val shape = RoundedCornerShape(12.dp)
        Column(modifier.widthIn(max = 480.dp).background(Color.White.copy(alpha = 0.045f), shape).border(0.9.dp, ArenaGlass.hairlineTop.copy(alpha = 0.55f), shape)
            .padding(16.dp), horizontalAlignment = if (wide) Alignment.Start else Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val align = if (wide) TextAlign.Start else TextAlign.Center
            Text(page.title, Modifier.semantics { heading() }, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(23f, SfWeight.bold), textAlign = align)
            Text(page.body, color = ArenaMenuStyle.text.copy(alpha = 0.82f), style = ArenaMenuStyle.font(16f, SfWeight.medium).copy(lineHeight = 22.sp), textAlign = align)
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().testTag("howToPlay.page.${page.id}")) {
        if (wide) {
            val height = (maxHeight - 20.dp).coerceAtLeast(180.dp)
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp).height(height), horizontalArrangement = Arrangement.spacedBy(22.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                HowToPlayScene("$tutorialID/${page.id}", Modifier.widthIn(max = 320.dp).fillMaxWidth(0.45f).fillMaxHeight())
                words(Modifier.weight(1f, fill = false).fillMaxHeight().verticalScroll(rememberScrollState()))
            }
        } else {
            val scene = (maxHeight * 0.5f).coerceIn(210.dp, 340.dp)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                HowToPlayScene("$tutorialID/${page.id}", Modifier.widthIn(max = 400.dp).fillMaxWidth().height(scene))
                words(Modifier)
            }
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
 * The lesson's picture in its dark inset in the gold hairline. Decorative: the words say the same, so TalkBack skips it, and
 * its type ignores the font scale so it never grows out of its frame.
 */
@Composable
private fun HowToPlayScene(key: String, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, 1f)) {
        val shape = RoundedCornerShape(12.dp)
        Box(modifier.clip(shape).background(Brush.verticalGradient(listOf(rgb(0.13, 0.12, 0.14), rgb(0.05, 0.05, 0.06))))
            .drawBehind { drawRect(Brush.radialGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.45f)), center, 260.dp.toPx())) }
            .border(1.dp, ArenaGlass.hairline, shape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
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

private val sceneInk = ArenaGlass.text

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
            SfImage(symbol, ArenaMenuStyle.gold.copy(alpha = 0.75f), (w * 0.24f).dp)
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

/** A player's medallion as the Arena board draws it: an initial on dark glass in a thin gold ring, life on a dark oval below. */
@Composable
private fun Medallion(label: String = "A", life: Int? = 40, size: Dp = 46.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().glow(Color.Black.copy(alpha = 0.5f), 3.dp, size / 2)
            .background(Brush.radialGradient(listOf(rgb(0.20, 0.21, 0.25), rgb(0.06, 0.06, 0.08))), CircleShape)
            .border(maxOf(1.dp, size * 0.04f), ArenaMenuStyle.gold.copy(alpha = 0.8f), CircleShape), contentAlignment = Alignment.Center) {
            Text(label, color = ArenaGlass.text, style = ArenaMenuStyle.title(size.value * 0.42f, SfWeight.bold))
        }
        if (life != null) CountBadge(life, size * 0.42f, Modifier.align(Alignment.BottomCenter).offset(y = size * 0.2f))
    }
}

/** A count as the Arena board shows one (ArenaCountBadge): a white number on a dark oval in a thin gold line. */
@Composable
private fun CountBadge(count: Int, size: Dp = 17.dp, modifier: Modifier = Modifier) {
    Box(modifier.defaultMinSize(minWidth = size + 3.dp, minHeight = size).glow(Color.Black.copy(alpha = 0.6f), 2.dp, size / 2)
        .background(rgb(0.07, 0.07, 0.08).copy(alpha = 0.94f), CircleShape).border(1.dp, ArenaMenuStyle.gold.copy(alpha = 0.7f), CircleShape)
        .padding(horizontal = maxOf(5.dp, size * 0.18f)), contentAlignment = Alignment.Center) {
        Text("$count", color = Color.White, style = sf(maxOf(11f, size.value * 0.5f), SfWeight.bold).copy(fontFeatureSettings = "tnum"))
    }
}

/** The hourglass pass button's painted face. */
@Composable
private fun Hourglass(size: Dp = 60.dp, modifier: Modifier = Modifier) {
    val face = tavernImage(R.drawable.tavern_hourglass_button)
    Box(modifier.size(size).glow(Color.Black.copy(alpha = 0.5f), 4.dp, size / 2).drawBehind { drawStretched(face) })
}

/** A button as a label: Arena's orange pill, or its dark glass one. */
@Composable
internal fun Plaque(text: String, icon: String? = null, primary: Boolean = true, modifier: Modifier = Modifier) {
    ArenaButtonFace(if (primary) ArenaButtonKind.PRIMARY else ArenaButtonKind.SECONDARY, ArenaMenuStyle.title(13f, SfWeight.bold), pressed = false,
        modifier = modifier, fills = false, inset = 8.dp, glow = 0.5f) {
        if (icon != null) SfImage(icon, androidx.compose.material3.LocalContentColor.current, 10.dp)
        ArenaButtonText(text)
    }
}

/** A name plate on its own, the banner under a showcased spell: light serif on dark glass in a gold hairline. */
@Composable
private fun Ribbon(text: String, width: Dp = 120.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(width * 0.84f, width * 0.2f).glow(Color.Black.copy(alpha = 0.5f), 3.dp, width * 0.1f)
        .background(Color.Black.copy(alpha = 0.6f), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
        FitText(text, ArenaMenuStyle.title(width.value * 0.095f, SfWeight.bold), Modifier.padding(horizontal = 6.dp), color = ArenaGlass.text, minimumScale = 0.6f,
            textAlign = TextAlign.Center)
    }
}

/** A finger's touch: a pale ring that swells and fades. */
@Composable
private fun Touch(phase: Double, modifier: Modifier = Modifier) {
    val p = phase.coerceIn(0.0, 1.0)
    Box(modifier.size((18 + 26 * p).dp).alpha((1 - p).toFloat()).border(2.dp, Color.White.copy(alpha = 0.85f), CircleShape))
}

@Composable
private fun Note(text: String) = Text(text, color = ArenaGlass.text.copy(alpha = 0.9f), style = ArenaMenuStyle.font(12f, SfWeight.semibold))

/** A note or a card in a lesson: dark glass in the gold hairline, where the tavern had parchment. */
private fun Modifier.howToPlayGlass(cornerRadius: Dp = 10.dp): Modifier =
    this.background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(cornerRadius)).border(1.dp, ArenaGlass.hairline, RoundedCornerShape(cornerRadius))

/** The table in a lesson: the Arena board's surface in its glass edge (its plate waits for Android's Arena board, so the walnut wash). */
@Composable
private fun HowToPlayTable(modifier: Modifier = Modifier) {
    Box(modifier.clip(RoundedCornerShape(10.dp)).background(Brush.verticalGradient(listOf(rgb(0.22, 0.16, 0.11), rgb(0.10, 0.07, 0.05))))
        .background(Color.Black.copy(alpha = 0.2f)).border(1.dp, ArenaGlass.hairline, RoundedCornerShape(10.dp)))
}

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
            Column(Modifier.howToPlayGlass(8.dp)
                .padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("YOUR DECK", color = rgb(0.62, 0.16, 0.08), style = sf(9f, SfWeight.heavy, tracking = 2f))
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
        Box(Modifier.size(150.dp, 190.dp)) {
            HowToPlayTable(Modifier.matchParentSize())
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
            Box(Modifier.offset(x, y).size(w, h).glow(ArenaMenuStyle.gold.copy(alpha = 0.8f), 4.dp, 8.dp).border(2.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(8.dp)))
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            callouts.forEachIndexed { offset, label ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).background(if (offset == step) ArenaMenuStyle.orange else Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.4f), Color.Black.copy(alpha = 0.4f))), CircleShape))
                    Text(label, color = ArenaGlass.text.copy(alpha = if (offset == step) 1f else 0.6f),
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
                SfImage("hand.raised", ArenaMenuStyle.gold, 16.dp)
                Text("tap a land", color = ArenaGlass.text.copy(alpha = 0.8f), style = ArenaMenuStyle.font(11f, SfWeight.semibold))
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
                TavernRingLabel { SfImage("forward.end.fill", ArenaGlass.text, 13.dp) }
                Text("Skip", color = ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.bold))
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
            CountBadge(9, 24.dp, Modifier.align(Alignment.BottomEnd).offset(x = 10.dp, y = 8.dp).alpha((1 - spread).toFloat()))
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
        Column(Modifier.howToPlayGlass(10.dp).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("text.book.closed", rgb(0.62, 0.16, 0.08), 9.dp)
                Text("GAME LOG", color = rgb(0.62, 0.16, 0.08), style = sf(9f, SfWeight.heavy, tracking = 1.6f))
            }
            for (width in listOf(96, 70, 84, 58)) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(5.dp).background(ArenaMenuStyle.gold, CircleShape))
                Box(Modifier.size(width.dp, 5.dp).background(sceneInk.copy(alpha = 0.35f), CircleShape))
            }
        }
    }
}

@Composable
private fun ResumeScene() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Hourglass(44.dp); Text("10 min", color = ArenaGlass.text, style = sf(26f, SfWeight.black, SfDesign.SERIF))
        }
        Column(Modifier.howToPlayGlass(12.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(GameResumeText.PROMPT_TITLE, color = sceneInk, style = ArenaMenuStyle.font(13f, SfWeight.heavy))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Plaque(GameResumeText.RESUME, icon = "play.fill"); Plaque(GameResumeText.ABANDON, primary = false) }
        }
    }
}

@Composable
private fun FriendsScene() {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Phone("Y")
        Box(contentAlignment = Alignment.Center) {
            Column(Modifier.howToPlayGlass(8.dp)
                .padding(horizontal = 12.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("TABLE CODE", color = rgb(0.62, 0.16, 0.08), style = sf(8f, SfWeight.heavy, tracking = 1.4f))
                Text("K7Q 2MX", color = sceneInk, style = sf(19f, SfWeight.black, SfDesign.MONOSPACED))
            }
            TavernTag("ONLINE", Modifier.align(Alignment.BottomCenter).offset(y = 16.dp), leather = true)
        }
        Phone("A")
    }
}

@Composable
private fun Phone(label: String) {
    Box(Modifier.size(48.dp, 86.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(10.dp)).border(1.dp, ArenaGlass.hairline, RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center) { Medallion(label, null, 30.dp) }
}

// Commander scenes

@Composable
private fun FormatScene() {
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(150.dp), contentAlignment = Alignment.Center) {
            HowToPlayTable(Modifier.size(96.dp))
            Medallion("A", null, 30.dp, Modifier.offset(y = (-58).dp)); Medallion("B", null, 30.dp, Modifier.offset(x = 62.dp))
            Medallion("C", null, 30.dp, Modifier.offset(y = 58.dp)); Medallion("Y", null, 30.dp, Modifier.offset(x = (-62).dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { CountBadge(100, 30.dp); Note("cards, one of each") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { CountBadge(40, 30.dp); Note("life each") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(30.dp), contentAlignment = Alignment.Center) { SfImage("crown.fill", ArenaMenuStyle.gold, 14.dp) }; Note("a legendary leader")
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
                repeat(casts) { Text("+2", color = ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.black)) }
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
            SfImage("arrow.turn.down.right", ArenaMenuStyle.gold, 12.dp); Note("then the player on your left")
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
            TavernTag("LAST IN", leather = true); SfImage("chevron.down", ArenaMenuStyle.gold, 12.dp); TavernTag("FIRST OUT", leather = true)
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
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { CountBadge(0, 26.dp); Note("life") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(26.dp), contentAlignment = Alignment.Center) { SfImage("circle.hexagongrid.fill", rgb(0.45, 0.85, 0.4), 13.dp) }; Note("10 poison")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(26.dp), contentAlignment = Alignment.Center) { SfImage("crown.fill", ArenaMenuStyle.gold, 13.dp) }; Note("21 from one commander")
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
