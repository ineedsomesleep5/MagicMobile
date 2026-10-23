package io.magicmobile.android.menus

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.ArenaFeatureTurn
import io.magicmobile.android.game.ArenaHomeArtCrop
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.ranked.RankEmblem
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LocalBrandAmbientMotion
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/*
 * Port of Menus/ArenaHomeView.swift: the home page in Arena's layout over the 3D tavern room (Caleb, 2026-10-22: keep the
 * room, follow Arena). A featured panel and three tiles in the middle, progress medallions on a rail under them, friends in
 * the lower left and the Play plaque in the lower right. Nothing scrolls.
 */

/**
 * Art shipped with the app for the home page: a commander's art crop at 1252 px (from the iOS asset catalogue, staged by
 * prepareBrandAssets as `home_art_*`), so it stays sharp. `focusX`/`focusY` is the point the crop keeps in view.
 */
data class ArenaHomeArt(@DrawableRes val asset: Int, val focusX: Float, val focusY: Float)

/** One page of the home page's featured panel. */
data class ArenaFeature(val id: String, val kicker: String, val title: String, val art: ArenaHomeArt, val action: () -> Unit)

/** One of the tiles beside the featured panel. */
data class ArenaHomeTile(val id: String, val title: String, val subtitle: String, val art: ArenaHomeArt, val action: () -> Unit)

/** What the home page shows. */
data class ArenaHomeContent(
    val features: List<ArenaFeature>,
    val tiles: List<ArenaHomeTile>,
    val deck: ArenaDeckBoxModel?,
    val rank: RankPosition,
    val wins: Int,
    val losses: Int,
    val friendsOnline: Int,
    val unread: Boolean,
    val play: () -> Unit,
    val friends: () -> Unit,
    val updates: () -> Unit,
    val downloads: () -> Unit,
    val openDeck: () -> Unit,
    val openRank: () -> Unit,
)

@Composable
fun ArenaHomeView(content: ArenaHomeContent, compact: Boolean, modifier: Modifier = Modifier) {
    val ambient = LocalBrandAmbientMotion.current
    // The page steps away while a panel covers the menu, so nothing shows half under a panel's foot; the room stays.
    val shown by animateFloatAsState(if (ambient) 1f else 0f, tween(if (BoardMotionFlags.reduceMotion) 0 else 200), label = "homeShown")
    BoxWithConstraints(modifier.fillMaxSize().alpha(shown).windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))) {
        if (compact) Portrait(content, maxWidth, maxHeight) else Landscape(content, maxWidth, maxHeight)
    }
}

@Composable
private fun Landscape(content: ArenaHomeContent, width: Dp, height: Dp) {
    val bottom = 64.dp
    val blockHeight = minOf(250.dp, maxOf(170.dp, height - bottom - 30.dp))
    val featureWidth = minOf(480.dp, (width - 40.dp) * 0.62f)
    val tilesWidth = minOf(270.dp, width - 40.dp - featureWidth - 10.dp)
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.Top) {
            ArenaFeaturePanel(content.features, Modifier.size(featureWidth, blockHeight))
            Column(Modifier.size(tilesWidth, blockHeight), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                content.tiles.forEach { ArenaHomeTileView(it, wide = false, Modifier.weight(1f)) }
            }
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth().height(bottom).padding(horizontal = 16.dp).padding(bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Corner(content, compact = false)
            Spacer(Modifier.weight(1f))
            ArenaProgressRail(content, compact = false)
            Spacer(Modifier.weight(1f))
            PlayButton(content, Modifier.size(176.dp, 44.dp), compact = false)
        }
    }
}

@Composable
private fun Portrait(content: ArenaHomeContent, @Suppress("UNUSED_PARAMETER") width: Dp, height: Dp) {
    val featureHeight = minOf(320.dp, height * 0.38f)
    val tileHeight = minOf(96.dp, maxOf(70.dp, (height - featureHeight - 230.dp) / 3))
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        ArenaFeaturePanel(content.features, Modifier.fillMaxWidth().padding(top = 14.dp).height(featureHeight))
        Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            content.tiles.forEach { ArenaHomeTileView(it, wide = true, Modifier.fillMaxWidth().height(tileHeight)) }
        }
        Spacer(Modifier.weight(1f).heightIn(min = 10.dp))
        ArenaProgressRail(content, compact = true)
        Spacer(Modifier.weight(1f).heightIn(min = 10.dp))
        Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Corner(content, compact = true)
            Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
            PlayButton(content, Modifier.size(190.dp, 50.dp), compact = true)
        }
    }
}

/** Friends, and in portrait news and downloads (the top bar has no room for them there). */
@Composable
private fun Corner(content: ArenaHomeContent, compact: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        ArenaCornerButton("person.2.fill", "Friends", "menu.social", content.friends,
            badge = if (content.friendsOnline > 0) "${content.friendsOnline}" else null, unread = content.unread)
        if (compact) {
            ArenaCornerButton("newspaper.fill", "Updates", "menu.updates", content.updates)
            ArenaCornerButton("arrow.down.circle.fill", "Downloads", "menu.downloads", content.downloads)
        }
    }
}

@Composable
private fun PlayButton(content: ArenaHomeContent, modifier: Modifier, compact: Boolean) {
    ArenaPlayButton("Play", { GameAudio.play(GameSound.MENU_PLAY); content.play() }, modifier, fontSize = if (compact) 23f else 21f, identifier = "menu.play")
}

// MARK: - Featured panel

/** The big panel: one feature at a time over its card's art, arrows and dots to move between them, and a slow turn on its own. */
@Composable
fun ArenaFeaturePanel(features: List<ArenaFeature>, modifier: Modifier = Modifier) {
    var index by remember { mutableIntStateOf(0) }
    var forward by remember { mutableStateOf(true) }
    val drag = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val reduce = BoardMotionFlags.reduceMotion
    val ambient = LocalBrandAmbientMotion.current
    val shape = RoundedCornerShape(12.dp)
    fun step(delta: Int) {
        if (features.isEmpty()) return
        forward = delta > 0
        index = ArenaFeatureTurn.step(index, delta, features.size)
    }
    // Restarts when a panel closes, so the pages turn again; a panel opened meanwhile holds them still.
    LaunchedEffect(index, ambient, features.size) {
        if (features.size <= 1 || reduce || !ambient) return@LaunchedEffect
        delay(ArenaFeatureTurn.AUTO_SECONDS * 1000)
        step(1)
    }
    Box(modifier.glow(Color.Black.copy(alpha = 0.6f), 12.dp, 12.dp).clip(shape).border(1.dp, ArenaGlass.hairline, shape)
        // The page follows the finger and turns past 60 pt of a swipe.
        .pointerInput(features.size) {
            detectHorizontalDragGestures(
                onDragEnd = {
                    val turn = ArenaFeatureTurn.swipe(drag.value / density)
                    if (turn != 0) step(turn)
                    scope.launch { drag.animateTo(0f, if (reduce) tween(0) else spring(dampingRatio = 0.86f, stiffness = 440f)) }
                },
                onDragCancel = { scope.launch { drag.animateTo(0f) } }) { change, amount ->
                change.consume()
                scope.launch { drag.snapTo(drag.value + amount) }
            }
        }) {
        val feature = features.getOrNull(index.coerceAtMost(features.size - 1))
        // Pages slide across as Arena's do, so two pages' words never show at once.
        AnimatedContent(feature, Modifier.fillMaxSize(), transitionSpec = {
            if (reduce) fadeIn(tween(150)) togetherWith fadeOut(tween(150))
            else (slideInHorizontally(tween(450)) { if (forward) it else -it }) togetherWith (slideOutHorizontally(tween(450)) { if (forward) -it else it })
        }, contentKey = { it?.id }, label = "feature") { page ->
            if (page != null) BrandPressable({ GameAudio.play(GameSound.UI_OPEN); page.action() },
                Modifier.fillMaxSize().offset { IntOffset(drag.value.roundToInt(), 0) }.testTag("home.feature.${page.id}")
                    .semantics(mergeDescendants = true) { contentDescription = "${page.kicker}, ${page.title}"; role = androidx.compose.ui.semantics.Role.Button }) {
                Box(Modifier.fillMaxSize()) {
                    ArenaFocusedArt(page.art, Modifier.fillMaxSize())
                    // A dark band only behind the words: the art stays crisp above it.
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.88f))))
                    Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = 18.dp, end = 48.dp, bottom = 22.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        ArenaCaps(page.kicker)
                        FitText(page.title, ArenaMenuStyle.title(24f, SfWeight.bold).arenaShadow(3f), color = ArenaMenuStyle.text, maxLines = 2, minimumScale = 0.8f)
                    }
                }
            }
        }
        if (features.size > 1) {
            Row(Modifier.align(Alignment.CenterStart).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                FeatureArrow("chevron.left", "Previous") { step(-1) }
                FeatureArrow("chevron.right", "Next") { step(1) }
            }
            Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp).clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                features.indices.forEach { i -> Box(Modifier.size(5.dp).background(if (i == index) Color.White else Color.White.copy(alpha = 0.35f), CircleShape)) }
            }
        }
    }
}

@Composable
private fun FeatureArrow(symbol: String, label: String, action: () -> Unit) {
    BrandPressable(action, Modifier.size(44.dp, 64.dp).semantics { contentDescription = label; role = androidx.compose.ui.semantics.Role.Button }) {
        Box(contentAlignment = Alignment.Center) {
            SfImage(symbol, Color.Black.copy(alpha = 0.6f), 15.dp, Modifier.offset(y = 1.dp))
            SfImage(symbol, Color.White.copy(alpha = 0.85f), 15.dp)
        }
    }
}

/** A tile: crisp art with the title and a gold line on a dark band at the bottom. */
@Composable
fun ArenaHomeTileView(tile: ArenaHomeTile, wide: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(10.dp)
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); tile.action() }, modifier.fillMaxWidth().testTag("home.tile.${tile.id}")
        .semantics(mergeDescendants = true) { contentDescription = if (tile.subtitle.isEmpty()) tile.title else "${tile.title}, ${tile.subtitle}" }) {
        Box(Modifier.fillMaxSize().glow(Color.Black.copy(alpha = 0.55f), 8.dp, 10.dp).clip(shape).border(1.dp, ArenaGlass.hairline, shape)) {
            ArenaFocusedArt(tile.art, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient((if (wide) 0.35f else 0.3f) to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
            Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 12.dp).padding(bottom = 9.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tile.title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.title(if (wide) 20f else 16f, SfWeight.bold).arenaShadow(), maxLines = 1)
                if (tile.subtitle.isNotEmpty()) FitText(tile.subtitle, ArenaMenuStyle.font(11f, SfWeight.semibold), color = ArenaMenuStyle.gold, minimumScale = 0.85f)
            }
        }
    }
}

/** Shipped home art filling its frame, cropped around its focus point rather than its centre (ArenaFocusedArt). */
@Composable
fun ArenaFocusedArt(art: ArenaHomeArt, modifier: Modifier = Modifier) {
    val image: ImageBitmap = ImageBitmap.imageResource(art.asset)
    if (image.width <= 0 || image.height <= 0) { ArenaColorGlass(emptyList(), modifier); return }
    Canvas(modifier.clipToBounds().clearAndSetSemantics { }) {
        val place = ArenaHomeArtCrop.place(image.width.toFloat(), image.height.toFloat(), size.width, size.height, art.focusX, art.focusY)
        drawImage(image, IntOffset.Zero, IntSize(image.width, image.height), IntOffset(place.x.roundToInt(), place.y.roundToInt()),
            IntSize(place.width.roundToInt().coerceAtLeast(1), place.height.roundToInt().coerceAtLeast(1)), filterQuality = FilterQuality.High)
    }
}

/** A card's art, filling its frame; the deck's colours as light through glass until the art is on the phone. */
@Composable
fun ArenaArt(name: String, colors: List<String> = emptyList(), modifier: Modifier = Modifier) {
    CardArtwork(name, modifier.clipToBounds().clearAndSetSemantics { }, artOnly = true) { ArenaColorGlass(colors, Modifier.fillMaxSize()) }
}

// MARK: - Progress

/** Your deck, rank and season as medallions on a gold rail with tick marks, centred under the panels. */
@Composable
fun ArenaProgressRail(content: ArenaHomeContent, compact: Boolean, modifier: Modifier = Modifier) {
    val rank = content.rank
    val perDivision = RankPosition.PIPS_PER_DIVISION
    val pips = if (rank.tier == RankTier.MYTHIC) perDivision else minOf(perDivision, rank.pips)
    val played = content.wins + content.losses
    Row(modifier.then(if (compact) Modifier.fillMaxWidth() else Modifier).drawBehind {
        // The line the medallions sit on, with a tick between each, running 18 pt past either end.
        val y = size.height / 2
        val over = 18.dp.toPx(); val start = -over; val length = size.width + over * 2
        val tick = 3.dp.toPx(); val stroke = 1.dp.toPx()
        drawLine(ArenaGlass.hairline, Offset(start, y), Offset(start + length, y), stroke, alpha = 0.65f)
        for (i in 0..8) {
            val x = start + length * i / 8
            drawLine(ArenaGlass.hairline, Offset(x, y - tick), Offset(x, y + tick), stroke, alpha = 0.65f)
        }
    }.padding(horizontal = 6.dp), horizontalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 14.dp), verticalAlignment = Alignment.CenterVertically) {
        val cell = if (compact) Modifier.weight(1f) else Modifier
        content.deck?.let { deck ->
            Medallion(1f, deck.name, "", content.openDeck, "home.deck", compact, cell) {
                ArenaArt(deck.commander ?: "", deck.colors, Modifier.fillMaxSize().clip(CircleShape))
            }
        }
        Medallion(pips.toFloat() / perDivision, rank.title, if (rank.tier == RankTier.MYTHIC) "Mythic" else "$pips of $perDivision pips",
            content.openRank, "home.rank", compact, cell) { RankEmblem(rank.tier, 32.dp) }
        if (!compact || content.deck == null) {
            val share = if (played == 0) 0f else content.wins.toFloat() / played
            Medallion(share, "Season ${content.wins}–${content.losses}", if (played == 0) "No games yet" else "${(share * 100).roundToInt()}% won",
                content.openRank, "home.season", compact, cell) {
                ArenaGlyph("laurel.leading", 18.dp, ArenaMenuStyle.metal, emboss = false)
            }
        }
    }
}

@Composable
private fun Medallion(progress: Float, title: String, subtitle: String, action: () -> Unit, identifier: String, compact: Boolean, modifier: Modifier,
                      face: @Composable () -> Unit) {
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); action() }, modifier.testTag(identifier)
        .semantics(mergeDescendants = true) { contentDescription = if (subtitle.isEmpty()) title else "$title, $subtitle" }) {
        Row(Modifier.then(if (compact) Modifier.fillMaxWidth() else Modifier)
            .background(Brush.verticalGradient(listOf(rgb(0.10, 0.11, 0.14).copy(alpha = 0.92f), rgb(0.04, 0.045, 0.06).copy(alpha = 0.94f))), CircleShape)
            .border(0.8.dp, ArenaGlass.hairline, CircleShape)
            .padding(start = 4.dp, end = 12.dp, top = 4.dp, bottom = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val ring = 3.dp.toPx(); val inset = 1.5.dp.toPx() + ring / 2
                    drawCircle(rgb(0.08, 0.07, 0.06))
                    val arc = Rect(inset, inset, size.width - inset, size.height - inset)
                    drawCircle(Color.White.copy(alpha = 0.12f), arc.width / 2, center, style = Stroke(ring))
                    drawArc(Brush.verticalGradient(listOf(rgb(1.0, 0.72, 0.38), ArenaMenuStyle.ember)), -90f, 360f * maxOf(0.001f, progress), false,
                        arc.topLeft, Size(arc.width, arc.height), style = Stroke(ring, cap = StrokeCap.Round))
                }
                Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { face() }
            }
            Column(Modifier.then(if (compact) Modifier.weight(1f) else Modifier.widthIn(max = 130.dp)), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.bold), maxLines = 1)
                if (subtitle.isNotEmpty()) Text(subtitle, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(10.5f, SfWeight.semibold), maxLines = 1)
            }
        }
    }
}

/** A deck's colours as light through dark glass, standing in for art that isn't on the phone yet (no words, no pips). */
@Composable
fun ArenaColorGlass(colors: List<String>, modifier: Modifier = Modifier) {
    val tints = mapOf("W" to rgb(0.93, 0.86, 0.66), "U" to rgb(0.2, 0.46, 0.78), "B" to rgb(0.36, 0.28, 0.40),
        "R" to rgb(0.8, 0.28, 0.18), "G" to rgb(0.22, 0.55, 0.32))
    val chosen = listOf("W", "U", "B", "R", "G").filter { it in colors }.mapNotNull { tints[it] }
    val palette = when (chosen.size) {
        0 -> listOf(rgb(0.40, 0.41, 0.44), rgb(0.16, 0.17, 0.19))
        1 -> listOf(chosen[0], chosen[0].copy(alpha = 0.45f))
        else -> chosen
    }
    // Until the art arrives: a dark band with only a breath of the colours.
    Box(modifier.clearAndSetSemantics { }.background(rgb(0.06, 0.05, 0.05)).background(Brush.linearGradient(palette.map { it.copy(alpha = it.alpha * 0.18f) })))
}
