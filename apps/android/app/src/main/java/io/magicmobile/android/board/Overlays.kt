package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.BattlefieldLayoutMetrics
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameStats
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.MobilePromptPresentation
import io.magicmobile.android.game.OpeningHandChoice
import io.magicmobile.android.game.XmageWaitKind
import io.magicmobile.android.game.XmageWaitPresentation
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.BrandDivider
import io.magicmobile.android.ui.BrandMark
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.BrandTitle
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.IosTextButton
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.brandPanel
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rememberAnimationSeconds
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.delay

/** On-device games concede through the engine (Swift GameConcedeHandler). */
class GameConcedeHandler(val concede: () -> Unit)
val LocalGameConcede = compositionLocalOf<GameConcedeHandler?> { null }
/** When set (solo games), the result screen's first button restarts the same match. */
val LocalGameRematchTitle = compositionLocalOf<String?> { null }

enum class GameMenuConfirmation(val title: String, val message: String) {
    START_NEW("Start a new game?", "MagicMobile will ask XMage to clean up the current game, then open setup."),
    QUIT("Quit this game?", "MagicMobile will ask XMage to clean up the current game, then return to the main menu.")
}

/** A red edge that flares when you take a big hit. */
@Composable
fun BoardHitVignette(strength: Float) {
    Canvas(Modifier.fillMaxSize().alpha(strength)) {
        val reach = 520.dp.toPx()
        drawRect(Brush.radialGradient(0f to Color.Transparent, 0.5f to Color.Transparent, 1f to BoardHitVignetteColor, center = center, radius = reach))
    }
}

/** Turn-start ribbon: a gold-edged band sweeps across the board with the owner's name. */
@Composable
fun BoardTurnBanner(title: String, turn: Int, isViewer: Boolean, modifier: Modifier = Modifier) {
    val accent = if (isViewer) BoardFXColors.gold else rgb(0.62, 0.74, 1.0)
    var shown by remember { mutableStateOf(BoardMotion.reduceMotion) }
    var sweep by remember { mutableStateOf(-1f) }
    LaunchedEffect(Unit) { if (!BoardMotion.reduceMotion) { shown = true; delay(250); sweep = 1f } }
    val band by animateFloatAsState(if (shown) 1f else 0.05f, spring(0.78f, 220f), label = "bannerBand")
    val rise by animateFloatAsState(if (shown) 0f else 14f, spring(0.78f, 220f), label = "bannerRise")
    val textAlpha by animateFloatAsState(if (shown) 1f else 0f, spring(0.78f, 220f), label = "bannerAlpha")
    val sweepX by animateFloatAsState(sweep, tween(1100), label = "bannerSweep")
    Box(modifier.padding(horizontal = 6.dp).semantics { contentDescription = "$title, turn $turn" }, contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().height(104.dp).graphicsLayer { scaleX = band }
            .background(Brush.horizontalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.86f), Color.Black.copy(alpha = 0.86f), Color.Transparent)))) {
            val edge = Brush.horizontalGradient(listOf(Color.Transparent, accent, accent, Color.Transparent))
            Box(Modifier.fillMaxWidth().height(2.dp).align(Alignment.TopCenter).glow(accent, 6.dp, 1.dp).background(edge))
            Box(Modifier.fillMaxWidth().height(2.dp).align(Alignment.BottomCenter).glow(accent, 6.dp, 1.dp).background(edge))
        }
        Column(Modifier.graphicsLayer { translationY = rise * density; alpha = textAlpha }, horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val titleStyle = sf(40f, SfWeight.black, SfDesign.SERIF, tracking = 3f).copy(
                brush = Brush.verticalGradient(listOf(Color.White, accent, accent.copy(alpha = 0.8f))), shadow = Shadow(accent.copy(alpha = 0.6f), blurRadius = 14f))
            Box(Modifier.drawWithContent {
                drawContent()
                // Light sweep across the title.
                val x = size.width / 2 + sweepX * 220.dp.toPx()
                drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.9f), Color.Transparent), x - 35.dp.toPx(), x + 35.dp.toPx()),
                    blendMode = BlendMode.SrcAtop)
            }.graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }) {
                FitText(title.uppercase(), titleStyle, minimumScale = 0.6f)
            }
            Text("Turn $turn", color = accent.copy(alpha = 0.85f), style = sf(12f, SfWeight.heavy, tracking = 2f))
        }
    }
}

/**
 * Animated backdrop for the game-over panel, edge to edge: one continuous tint, turning
 * rays and rising motes for a win, falling ash for a loss.
 */
@Composable
fun GameResultBackdrop(victory: Boolean) {
    val t = rememberAnimationSeconds(BoardMotion.reduceMotion).toDouble()
    Canvas(Modifier.fillMaxSize()) {
        val reach = max(1f, hypot(size.width, size.height) * 0.6f)
        val center = Offset(size.width / 2, size.height * 0.42f)
        drawRect(Brush.radialGradient(if (victory) listOf(rgb(0.62, 0.46, 0.12).copy(alpha = 0.62f), rgb(0.40, 0.28, 0.07).copy(alpha = 0.46f))
            else listOf(rgb(0.42, 0.05, 0.04).copy(alpha = 0.62f), rgb(0.20, 0.02, 0.02).copy(alpha = 0.5f)), center, reach))
        if (BoardMotion.reduceMotion) return@Canvas
        val intro = min(1.0, t / 0.8)
        val full = hypot(size.width, size.height) / density
        with(BoardFXPainter) {
            if (victory) {
                rays(BoardPoint(center.x / density, center.y / density), gold, full * 0.7, 0.4, t * 0.6)
                // Motes rise across the whole screen, not a band.
                for (i in 0 until 70) {
                    val speed = 0.05 + 0.08 * noise(9, i, 1)
                    val life = (t * speed + noise(9, i, 2)) % 1.0
                    val x = size.width * noise(9, i, 3) + sin(t * 0.8 + i) * 14 * density
                    val y = size.height * (1.02 - 1.08 * life)
                    val r = (1.2 + 2.4 * noise(9, i, 4)) * density
                    val a = intro * sin(PI * life) * (0.55 + 0.45 * sin(t * 3 + i))
                    drawCircle((if (i % 3 == 0) Color.White else gold).copy(alpha = a.toFloat().coerceIn(0f, 1f)), r.toFloat(), Offset(x.toFloat(), y.toFloat()), blendMode = BlendMode.Plus)
                }
            } else for (i in 0 until 60) {
                val life = (t * (0.06 + 0.08 * noise(3, i, 1)) + noise(3, i, 2)) % 1.0
                val x = size.width * noise(3, i, 3) + sin(t + i) * 12 * density
                val y = size.height * (1.08 * life - 0.04)
                drawOval(rgb(0.75, 0.7, 0.68).copy(alpha = (0.5 * sin(PI * life) * intro).toFloat().coerceIn(0f, 1f)), Offset(x.toFloat(), y.toFloat()),
                    androidx.compose.ui.geometry.Size(3 * density, 3 * density))
            }
        }
    }
}

/** The game in numbers under the result title, with the card that hit hardest. */
@Composable
fun GameSummaryPanel(stats: GameStats, victory: Boolean, modifier: Modifier = Modifier) {
    @Composable
    fun tile(value: String, label: String, tileModifier: Modifier) {
        Column(tileModifier.defaultMinSize(minHeight = 58.dp).background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(10.dp)).padding(vertical = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
            Text(value, color = if (victory) MagicPalette.antiqueGold else MagicPalette.parchment, style = sf(22f, SfWeight.black, SfDesign.ROUNDED))
            FitText(label.uppercase(), sf(9f, SfWeight.heavy, tracking = 0.8f), color = Color.White.copy(alpha = 0.62f), maxLines = 2, minimumScale = 0.8f, textAlign = TextAlign.Center)
        }
    }
    Column(modifier.semantics { contentDescription = "board.result.summary" }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            tile("${stats.turns}", "Turns", Modifier.weight(1f))
            tile("${stats.combatDamage}", "Combat damage", Modifier.weight(1f))
            tile("${stats.creaturesDestroyed}", "Creatures destroyed", Modifier.weight(1f))
        }
        stats.topCard?.let { (name, damage) ->
            Row(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(10.dp)).padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.7f), RoundedCornerShape(8.dp))) {
                    CardArtwork(name, Modifier.fillMaxSize(), artOnly = true) { Box(Modifier.fillMaxSize().background(MagicPalette.iron)) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("TOP ATTACKER", color = MagicPalette.antiqueGold, style = sf(10f, SfWeight.black, tracking = 1.2f))
                    FitText(name, SfText.subheadline(SfWeight.heavy), color = Color.White, minimumScale = 0.7f)
                }
                Text("$damage dmg", color = MagicPalette.parchment, style = sf(15f, SfWeight.black, SfDesign.ROUNDED))
            }
        }
    }
}

/** Victory or defeat, the result backdrop, the game summary and what to do next. */
@Composable
fun GameCompletionOverlay(snapshot: GameSnapshot, newGame: () -> Unit, quitGame: () -> Unit, stats: GameStats? = null) {
    val rematchTitle = LocalGameRematchTitle.current
    val view = LocalView.current
    val winners = snapshot.winnerPlayerIds
    val isVictory = winners?.contains(snapshot.viewerID) == true
    val title = if (winners.isNullOrEmpty()) "Game Over" else if (isVictory) "Victory" else "Defeat"
    val names = snapshot.winnerDisplayNames
    val winnerText = if (names.isEmpty()) "XMage has completed the match." else if (names == listOf("You")) "You won the match." else "Winner: ${names.joinToString(", ")}"
    val reasonText = snapshot.endReason?.takeIf { it.isNotEmpty() }?.replace("_", " ")?.let { io.magicmobile.android.game.capitalizedWords(it.lowercase()) }
    val reduceMotion = BoardMotion.reduceMotion
    var revealed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(100); revealed = true
        view.performHapticFeedback(if (isVictory) android.view.HapticFeedbackConstants.CONFIRM else android.view.HapticFeedbackConstants.REJECT)
    }
    val titleScale by animateFloatAsState(if (revealed || reduceMotion) 1f else 1.6f, spring(0.62f, 130f), label = "resultScale")
    val titleAlpha by animateFloatAsState(if (revealed || reduceMotion) 1f else 0f, spring(0.62f, 130f), label = "resultAlpha")
    val summaryAlpha by animateFloatAsState(if (revealed || reduceMotion) 1f else 0f, tween(450, 350), label = "summaryAlpha")
    val defeatRed = rgb(0.8, 0.35, 0.3)
    Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) {}
        .semantics { contentDescription = "Game completed. $title. $winnerText" }, contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)))
        GameResultBackdrop(isVictory)
        Column(Modifier.padding(horizontal = 20.dp).widthIn(max = 420.dp).glow(Color.Black.copy(alpha = 0.48f), 18.dp, 16.dp)
            .background(MagicPalette.iron.copy(alpha = 0.9f), RoundedCornerShape(16.dp))
            .border(1.5.dp, (if (isVictory) MagicPalette.antiqueGold else rgb(0.6, 0.2, 0.18)).copy(alpha = 0.8f), RoundedCornerShape(16.dp)).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.glow((if (isVictory) MagicPalette.antiqueGold else Color.Red).copy(alpha = 0.6f), 12.dp, 20.dp)) {
                SfImage(if (isVictory) "trophy.fill" else "flag.checkered", if (isVictory) MagicPalette.antiqueGold else defeatRed, 44.dp)
            }
            FitText(title.uppercase(), sf(48f, SfWeight.black, SfDesign.SERIF, tracking = 4f).copy(
                brush = Brush.verticalGradient(if (isVictory) listOf(Color.White, MagicPalette.antiqueGold, rgb(0.7, 0.5, 0.16)) else listOf(Color(0.9f, 0.9f, 0.9f), rgb(0.72, 0.2, 0.18))),
                shadow = Shadow((if (isVictory) MagicPalette.antiqueGold else Color.Red).copy(alpha = 0.55f), blurRadius = 16f)),
                Modifier.graphicsLayer { scaleX = titleScale; scaleY = titleScale; alpha = titleAlpha }, minimumScale = 0.6f)
            Text(winnerText, color = MagicPalette.parchment, style = SfText.callout(SfWeight.bold), textAlign = TextAlign.Center)
            reasonText?.let { Text(it, color = Color.White.copy(alpha = 0.68f), style = SfText.caption(SfWeight.semibold), textAlign = TextAlign.Center) }
            if (stats != null && stats.turns > 0) GameSummaryPanel(stats, isVictory, Modifier.graphicsLayer { alpha = summaryAlpha; translationY = (1 - summaryAlpha) * 12 * density })
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CompactActionButton(newGame, Modifier.semantics { contentDescription = "board.result.rematch" }, isPrimary = true) { CompactActionText(rematchTitle ?: "New Game", true) }
                CompactActionButton(quitGame) { CompactActionText("Main Menu") }
            }
        }
    }
}

/** Shown instead of your controls once you're out of a pod: the game plays on without you. */
@Composable
fun SpectatorBar(snapshot: GameSnapshot, leave: () -> Unit, modifier: Modifier = Modifier) {
    // Whose seat the bottom of the board shows while you watch.
    val detail = io.magicmobile.android.game.SpectatorSeatPresentation.detail(snapshot)
    Row(modifier.glow(Color.Black.copy(alpha = 0.45f), 12.dp, 18.dp).background(MagicPalette.iron.copy(alpha = 0.94f), RoundedCornerShape(18.dp))
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.42f), RoundedCornerShape(18.dp)).padding(horizontal = 12.dp, vertical = 7.dp)
        .semantics { contentDescription = "board.spectator" }, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.45f), CircleShape),
            contentAlignment = Alignment.Center) { SfImage("eye.fill", MagicPalette.antiqueGold, 18.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(io.magicmobile.android.game.SpectatorSeatPresentation.title(snapshot), sf(16f, SfWeight.black, SfDesign.ROUNDED),
                color = Color.White, minimumScale = 0.75f)
            FitText(detail, SfText.caption(SfWeight.semibold), color = MagicPalette.parchment.copy(alpha = 0.78f), minimumScale = 0.8f)
        }
        CompactActionButton(leave, Modifier.semantics { contentDescription = "board.spectator.leave" }) { CompactActionText("Leave") }
    }
}

/** Arena-style opening hand: the cards fanned large over a dimmed table, with Mulligan and Keep. */
@Composable
fun OpeningHandOverlay(choice: OpeningHandChoice, cards: List<ZoneCard>, pending: Boolean, answer: (GameCommand, String, String) -> Unit) {
    val reduceMotion = BoardMotion.reduceMotion
    var dealt by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf<ZoneCard?>(null) }
    LaunchedEffect(Unit) { dealt = true; GameAudio.play(GameSound.CARD_DRAW) }
    BoxWithConstraints(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) {}.semantics { contentDescription = "board.opening" }) {
        val availableWidth = maxWidth.value
        val count = maxOf(cards.size, 1)
        val width = min(116f, (availableWidth - 56) / (count * 0.5f + 0.62f))
        val height = width * BattlefieldLayoutMetrics.magicCardHeightToWidth
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.78f)))
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Brush.radialGradient(listOf(MagicPalette.antiqueGold.copy(alpha = 0.16f), Color.Transparent), center, max(1f, size.width * 0.7f)))
        }
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("OPENING HAND", color = MagicPalette.antiqueGold, style = sf(13f, SfWeight.black, tracking = 3f))
                Text(choice.message, Modifier.padding(horizontal = 24.dp).semantics { contentDescription = "board.opening.message" }, color = Color.White,
                    style = sf(20f, SfWeight.black, SfDesign.SERIF), textAlign = TextAlign.Center)
            }
            Box(Modifier.fillMaxWidth().height((height * 1.2f).dp).padding(bottom = 10.dp), contentAlignment = Alignment.Center) {
                val mid = (cards.size - 1) / 2f
                val step = min(width * 0.52f, (availableWidth - 64 - width) / maxOf(cards.size - 1, 1))
                cards.forEachIndexed { index, card ->
                    key(card.id) {
                        val offset = index - mid
                        val progress by animateFloatAsState(if (dealt) 1f else 0f, if (reduceMotion) tween(0) else spring(0.8f, 160f), label = "deal$index")
                        Box(Modifier.graphicsLayer {
                            transformOrigin = TransformOrigin(0.5f, 1f)
                            rotationZ = offset * 5 * progress
                            translationX = offset * step * progress * density
                            translationY = (abs(offset) * abs(offset) * 2.2f * progress + height * 0.6f * (1 - progress)) * density
                            alpha = progress
                        }.glow(Color.Black.copy(alpha = 0.55f), 8.dp, 6.dp).clickable { focused = card }.semantics { contentDescription = card.card.name }) {
                            CardTile(card, false, zoneName = "Opening hand", width = width.dp, height = height.dp, ignoreTappedRotation = true)
                        }
                    }
                }
            }
            Row(Modifier.widthIn(max = 420.dp).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OpeningHandButton(choice.mulliganLabel, "arrow.triangle.2.circlepath", false, !pending, Modifier.weight(1f).semantics { contentDescription = "board.opening.mulligan" }) {
                    GameAudio.play(GameSound.SHUFFLE)
                    answer(choice.mulligan, choice.mulliganLabel, "opening-mulligan-${choice.promptID}")
                }
                OpeningHandButton(choice.keepLabel, "hand.thumbsup.fill", true, !pending, Modifier.weight(1f).semantics { contentDescription = "board.opening.keep" }) {
                    answer(choice.keep, choice.keepLabel, "opening-keep-${choice.promptID}")
                }
            }
        }
        focused?.let { card ->
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)).clickable { focused = null }, contentAlignment = Alignment.Center) {
                val big = min(availableWidth - 56, 320f)
                Box(Modifier.glow(Color.Black.copy(alpha = 0.7f), 20.dp, 8.dp)) {
                    CardTile(card, false, zoneName = "Opening hand", width = big.dp, height = (big * BattlefieldLayoutMetrics.magicCardHeightToWidth).dp, ignoreTappedRotation = true)
                }
            }
        }
    }
}

/** Keep glows gold; Mulligan is a gold-edged outline, both easy to hit. */
@Composable
private fun OpeningHandButton(title: String, icon: String, primary: Boolean, enabled: Boolean, modifier: Modifier, action: () -> Unit) {
    PressableBox(action, modifier, enabled, pressSound = if (primary) GameSound.UI_CONFIRM else null) { pressed ->
        val ink = if (primary) rgb(0.16, 0.11, 0.05) else MagicPalette.parchment
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 50.dp).scale(if (pressed) 0.96f else 1f).alpha(if (enabled) 1f else 0.5f)
            .glow(if (primary) MagicPalette.antiqueGold.copy(alpha = 0.5f) else Color.Transparent, 10.dp, 25.dp)
            .background(if (primary) Brush.verticalGradient(listOf(rgb(1.0, 0.86, 0.5), MagicPalette.antiqueGold)) else Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.55f))), CircleShape)
            .border(1.5.dp, MagicPalette.antiqueGold.copy(alpha = if (primary) 0f else 0.8f), CircleShape).padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            SfImage(icon, ink, 17.dp)
            Text(title, color = ink, style = sf(17f, SfWeight.black, SfDesign.ROUNDED))
        }
    }
}

/** How long the engine has been deciding, with refresh and reconnect. */
@Composable
fun AIWaitFallbackControls(snapshot: GameSnapshot, pendingActionId: String?, liveUpdateStatus: String, beganAt: Long, didRefresh: Boolean,
                           didReconnect: Boolean, didDiagnose: Boolean, refreshAction: () -> Unit, reconnectAction: () -> Unit, modifier: Modifier = Modifier) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(beganAt) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val elapsed = (now - beganAt) / 1000.0
    val wait = XmageWaitPresentation.make(snapshot, pendingActionId, liveUpdateStatus, elapsed, didRefresh, didReconnect, didDiagnose)
    val warn = wait.kind == XmageWaitKind.SNAPSHOT_STALE || wait.kind == XmageWaitKind.MANUAL_RECONNECT_AVAILABLE
    val accent = if (warn) MagicPalette.warningAmber else MagicPalette.arcaneBlue
    Column(modifier.glow(Color.Black.copy(alpha = 0.35f), 12.dp, 10.dp).background(MagicPalette.iron.copy(alpha = 0.86f), RoundedCornerShape(10.dp))
        .border(1.2.dp, accent.copy(alpha = 0.46f), RoundedCornerShape(10.dp)).padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(wait.title.uppercase(), color = accent, style = sf(8f, SfWeight.black))
        Text("${elapsed.toInt()}s", color = Color.White, style = sf(18f, SfWeight.black, SfDesign.SERIF))
        Text(wait.detail, color = Color.White.copy(alpha = 0.62f), style = sf(8f, SfWeight.bold), textAlign = TextAlign.Center, maxLines = 2)
        CompactActionButton(refreshAction, isPrimary = true) { CompactActionText("REFRESH", true) }
        CompactActionButton(reconnectAction) { CompactActionText("RECONNECT") }
    }
}

/** "Shuffling up…" while the engine seats the table, with a rotating tip. */
@Composable
fun LoadingGameView(status: String? = null, message: String? = null, error: String? = null) {
    val tips = listOf("Hold a card to inspect it. Drag a card upward to play it.",
        "Tap the stack beside your mana to see everything waiting to resolve.",
        "Skip ends your turn but stops for anything that needs your answer.",
        "Tap a land to add its mana; the engine pays costs exactly as the rules say.",
        "Your commander returns to the command zone when it would leave play.",
        "Legendary permanents wear a gold edge on the battlefield.",
        "Turn on music and effect sounds in Settings for the full table experience.")
    var tipIndex by remember { mutableIntStateOf(tips.indices.random()) }
    LaunchedEffect(Unit) { while (true) { delay(4000); tipIndex += 1 } }
    val failed = status == "failed"
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        BrandBackdrop()
        Column(Modifier.padding(24.dp).widthIn(max = 420.dp).brandPanel(0.dp).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (failed) SfImage("exclamationmark.triangle.fill", BrandTheme.ember, 30.dp) else BrandMark(72.dp)
            BrandTitle(if (failed) "XMage start failed" else "Shuffling up…", 26f, textAlign = TextAlign.Center)
            Text(error ?: message ?: "Seating players at the table.", color = BrandTheme.inkSecondary, style = SfText.callout(), textAlign = TextAlign.Center, maxLines = 3)
            if (!failed) {
                BrandDivider(Modifier.widthIn(max = 240.dp).padding(top = 4.dp), title = "Tip")
                androidx.compose.animation.Crossfade(tipIndex % tips.size, animationSpec = tween(400), label = "tip") { index ->
                    Text(tips[index], Modifier.heightIn(min = 40.dp), color = BrandTheme.ink.copy(alpha = 0.85f), style = SfText.footnote(), textAlign = TextAlign.Center)
                }
            }
        }
    }
}

/** The in-game menu: appearance, effects, concede, start new, quit and prompt debug. */
@Composable
fun GameManagementMenu(snapshot: GameSnapshot, concedeAction: LegalAction?, runAction: (LegalAction) -> Unit, portraitModeEnabled: Boolean,
                       setPortraitModeEnabled: (Boolean) -> Unit, openPromptInspector: () -> Unit, confirmStartNew: () -> Unit, confirmQuit: () -> Unit,
                       dismiss: () -> Unit) {
    val gameConcede = LocalGameConcede.current
    var confirmingConcede by remember { mutableStateOf(false) }
    val canConcede = !snapshot.isCompleted && snapshot.human?.isOut != true && (gameConcede != null || concedeAction != null)
    Box(Modifier.fillMaxWidth()) {
        BattlefieldSurface(Modifier.matchParentSize())
        Column {
            Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Game Menu", Modifier.weight(1f), color = Color.White, style = sf(22f, SfWeight.black, SfDesign.ROUNDED))
                IosTextButton("Done", dismiss, Modifier.semantics { contentDescription = "board.menu.done" }, color = MagicPalette.antiqueGold, bold = true)
            }
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(18.dp).semantics { contentDescription = "board.menu.scroll" },
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                BoardAppearancePicker()
                PortraitModeToggle(portraitModeEnabled, setPortraitModeEnabled)
                FollowTurnsToggle()
                BoardEffectsPicker()
                if (snapshot.isSpectating) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SfImage("eye.fill", MagicPalette.parchment.copy(alpha = 0.8f), 12.dp)
                    Text("You’re out of this game and watching the others play. Quit when you’re done.", color = MagicPalette.parchment.copy(alpha = 0.8f),
                        style = SfText.caption(SfWeight.bold))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CompactActionButton({ confirmingConcede = true }, Modifier.weight(1f).semantics { contentDescription = "board.menu.concede" }, isDanger = true, enabled = canConcede) {
                        SfImage("flag.fill", Color.White, 13.dp); Spacer(Modifier.width(5.dp)); CompactActionText("Concede")
                    }
                    CompactActionButton(confirmStartNew, Modifier.weight(1f), isPrimary = true) {
                        SfImage("arrow.clockwise", Color.White, 13.dp); Spacer(Modifier.width(5.dp)); CompactActionText("Start New", true)
                    }
                    CompactActionButton(confirmQuit, Modifier.weight(1f).semantics { contentDescription = "board.menu.quit" }) {
                        SfImage("rectangle.portrait.and.arrow.right", Color.White, 13.dp); Spacer(Modifier.width(5.dp)); CompactActionText("Quit")
                    }
                }
                CompactActionButton(openPromptInspector, Modifier.fillMaxWidth()) {
                    SfImage("ladybug.fill", Color.White, 13.dp); Spacer(Modifier.width(5.dp)); CompactActionText("Prompt Debug")
                }
            }
        }
    }
    if (confirmingConcede) {
        ConfirmationDialog("Concede this game?", if (snapshot.remainingOpponents.size > 1) "You leave the game and can keep watching the others play it out."
            else "Your opponent wins this game.", listOf(ConfirmationAction("Concede", destructive = true) {
            dismiss()
            if (gameConcede != null) gameConcede.concede() else concedeAction?.let(runAction)
        }), cancelTitle = "Keep Playing") { confirmingConcede = false }
    }
}

/** XMage prompt and bridge state, for diagnosing a stuck decision. */
@Composable
fun PromptDebugInspector(snapshot: GameSnapshot, liveUpdateStatus: String) {
    val prompt = snapshot.promptEnvelopeV2
    val presentation = MobilePromptPresentation.make(snapshot, snapshot.legalActions ?: emptyList())
    Box(Modifier.fillMaxWidth()) {
        BattlefieldSurface(Modifier.matchParentSize())
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Prompt Debug", color = Color.White, style = sf(22f, SfWeight.black, SfDesign.ROUNDED))
            Text("XMage prompt and bridge state", color = Color.White.copy(alpha = 0.62f), style = SfText.caption(SfWeight.semibold))
            Text("Protocol debug export is not available for this on-device session.", color = MagicPalette.warningAmber, style = sf(10f, SfWeight.bold))
            val rows = listOf("Kind" to (presentation?.kind?.name?.lowercase() ?: "none"), "Method" to (prompt?.method ?: "none"),
                "Response" to (prompt?.responseKind ?: "none"), "Command" to (prompt?.responseCommand?.type ?: "none"), "Prompt ID" to (prompt?.id ?: "none"),
                "Message" to (prompt?.messageId?.toString() ?: "none"), "Revision" to (snapshot.bridgeRevision?.toString() ?: "n/a"),
                "Cycle" to (snapshot.xmageCycle?.toString() ?: "n/a"), "Pending" to (snapshot.pendingStatus ?: "none"),
                "Priority" to (snapshot.priorityPlayerId ?: "none"), "Waiting" to (snapshot.waitingOnPlayerId ?: "none"),
                "Legal" to "${snapshot.legalActions?.size ?: 0}", "WS" to liveUpdateStatus)
            Column(Modifier.fillMaxWidth().background(MagicPalette.iron.copy(alpha = 0.7f), RoundedCornerShape(8.dp))
                .border(1.dp, MagicPalette.borderBronze.copy(alpha = 0.35f), RoundedCornerShape(8.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((label, value) in rows) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(label.uppercase(), Modifier.width(76.dp), color = MagicPalette.antiqueGold, style = sf(8f, SfWeight.black))
                    FitText(value, sf(10f, SfWeight.bold), color = Color.White.copy(alpha = 0.82f), maxLines = 2, minimumScale = 0.7f)
                }
            }
            snapshot.legalActions?.takeIf { it.isNotEmpty() }?.let { actions ->
                PromptPanelSection("Legal action types", "${actions.size}") {
                    Text(actions.map { it.type }.toSet().sorted().joinToString(", "), color = Color.White.copy(alpha = 0.72f), style = sf(10f, SfWeight.bold))
                }
            }
        }
    }
}
