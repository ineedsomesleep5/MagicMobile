package io.magicmobile.android.ondevice

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.GameHaptics
import io.magicmobile.android.ui.BrandButton
import io.magicmobile.android.ui.BrandButtonText
import io.magicmobile.android.ui.D20Die
import io.magicmobile.android.ui.D20Die.drawD20
import io.magicmobile.android.ui.D20Die.drawFlatD20
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.Quat
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.Vec3
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private object D20Palette {
    val surface = Color(31, 33, 37)
    val ink = Color(243, 241, 236)
    val secondary = Color(177, 178, 182)
    val accent = Color(255, 128, 88)
}

/**
 * The tumbling die: crosses the screen in about a second, bounces off the far edge and comes
 * back. The path is simulated; the result is never chosen by it (MultiplayerD20View.swift arena).
 */
private class DieArena {
    var x = 0f; var y = 0f; var vx = 0f; var vy = 0f
    var orientation = Quat.identity
    var axis = Vec3(0.5f, 0.9f, 0.65f).normalized()
    var spin = 0f
    var direction = 1f
    var impactX: Float? = null
    var corrected = false
    var reportedRebound = false
    var moving = false
    var revealFrom: Quat? = null
    var revealTo: Quat? = null
    var revealElapsed = 0f
    var halfWidth = 4f; var halfHeight = 8f

    fun launch(turn: Int) {
        direction = if (turn % 2 == 0) 1f else -1f
        impactX = null; corrected = false; reportedRebound = false; revealFrom = null; revealTo = null
        orientation = Quat.axisAngle(Vec3(1f, 1f, 0.2f), 0.48f)
        x = -direction * (halfWidth - 1.2f)
        y = min(halfHeight - 1.3f, 0.7f)
        val travel = max(2.4f, halfWidth * 2 - 2.4f)
        vx = direction * travel / 1.05f; vy = -0.32f
        spin = direction * 13f
        moving = true
    }

    /** Advances `dt` seconds. Returns (edge hit now, rebound now). */
    fun step(dt: Float): Pair<Boolean, Boolean> {
        var edgeHit = false; var rebound = false
        if (moving) {
            val friction = exp(-0.55f * dt)
            vx *= friction; vy *= friction
            x += vx * dt; y += vy * dt
            val reach = 0.92f
            if (abs(x) + reach >= halfWidth && x * vx > 0) {
                x = (halfWidth - reach) * if (x > 0) 1f else -1f
                vx = -vx * 0.88f
                if (impactX == null) { impactX = x; edgeHit = true }
                // A faceted die can lose almost all of its normal speed on a corner hit; keep a modest rebound.
                if (!corrected) {
                    if (vx * direction > -1.8f) vx = -direction * max(1.8f, abs(vx) * 0.65f)
                    corrected = true
                }
                spin = -spin * 0.8f
            }
            if (abs(y) + reach >= halfHeight && y * vy > 0) { y = (halfHeight - reach) * if (y > 0) 1f else -1f; vy = -vy * 0.78f }
            spin *= exp(-0.8f * dt)
            orientation = (Quat.axisAngle(axis, spin * dt) * orientation).normalized()
            val impact = impactX
            if (impact != null && !reportedRebound && (x - impact) * direction < -0.65f) { reportedRebound = true; rebound = true }
        }
        val from = revealFrom; val to = revealTo
        if (from != null && to != null) {
            revealElapsed += dt
            val t = (revealElapsed / 0.24f).coerceIn(0f, 1f)
            orientation = Quat.slerp(from, to, t * t * (3 - 2 * t))
            if (t >= 1f) { revealFrom = null }
        }
        return edgeHit to rebound
    }

    fun reveal(value: Int) {
        moving = false
        revealFrom = orientation; revealTo = D20Die.restOrientation(value); revealElapsed = 0f
    }
}

/** A die showing `value` (or unnumbered while rolling), with the accent glow under it. */
@Composable
fun D20Face(value: Int?, emphasized: Boolean, modifier: Modifier = Modifier, compact: Boolean = true) {
    val measurer = rememberTextMeasurer()
    val labels = remember(measurer) {
        (1..20).map { measurer.measure(it.toString(), sf(40f, SfWeight.bold).copy(fontFeatureSettings = "tnum")) }
    }
    val reduceMotion = LaunchEnvironment.reduceMotion
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val glowRadius = size.minDimension * 0.42f
            val glowCenter = Offset(center.x, center.y + 8 * density)
            drawCircle(Brush.radialGradient(listOf(D20Palette.accent.copy(alpha = if (emphasized) 0.38f else 0.18f), Color.Transparent),
                glowCenter, glowRadius), glowRadius, glowCenter)
            if (reduceMotion) drawFlatD20(D20Palette.accent, D20Palette.surface)
            // SceneKit's orthographic camera spans 4.3 die radii of the frame's height.
            else drawD20(D20Die.restOrientation(value), center, size.height / 4.3f, labels, showLabels = value != null)
        }
        if (reduceMotion) Text(value?.toString() ?: "D20", color = D20Palette.ink,
            style = sf(if (compact) 25f else 31f, SfWeight.bold, io.magicmobile.android.ui.SfDesign.ROUNDED).copy(fontFeatureSettings = "tnum"))
    }
}

private class DieFlight(val seat: String, val value: Int, val from: Offset, val fromSize: Float, val to: Offset, val toSize: Float)

/**
 * Port of MultiplayerD20View.swift: plays back an authoritative starting roll. The match owner
 * decides every value, tie round and the winner; this view only shows them.
 */
@Composable
fun MultiplayerD20View(roll: OnDeviceStartingRoll, seatNames: Map<String, String>, isLocalWinner: Boolean, revealedStepCount: Int,
                       localSeatID: String?, rollPending: Boolean = false, onRollTap: () -> Unit, onStepPlayed: () -> Unit = {},
                       onDismiss: () -> Unit) {
    val reduceMotion = LaunchEnvironment.reduceMotion
    val view = LocalView.current
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()
    val rounds = roll.rounds
    val steps = roll.steps
    val playerIDs = (rounds.firstOrNull()?.keys?.toList() ?: seatNames.keys.toList()).sorted()
    var shownRoundIndex by remember { mutableStateOf<Int?>(null) }
    var activeSeatID by remember { mutableStateOf<String?>(null) }
    var activeValue by remember { mutableStateOf<Int?>(null) }
    val settledRolls = remember { mutableStateMapOf<String, Int>() }
    var landed by remember { mutableStateOf(false) }
    var revealFace by remember { mutableStateOf(false) }
    var diePosition by remember { mutableStateOf<Offset?>(null) }
    var stageSize by remember { mutableStateOf(androidx.compose.ui.geometry.Size.Zero) }
    var stageOrigin by remember { mutableStateOf(Offset.Zero) }
    var edgeHitTurn by remember { mutableStateOf<Int?>(null) }
    var reboundTurn by remember { mutableStateOf<Int?>(null) }
    var playbackFinished by remember { mutableStateOf(false) }
    var spinTurns by remember { mutableIntStateOf(0) }
    var skipAnimation by remember { mutableStateOf(false) }
    var playedStepCount by remember { mutableIntStateOf(0) }
    var didAutoDismiss by remember { mutableStateOf(false) }
    var flight by remember { mutableStateOf<DieFlight?>(null) }
    val flightProgress = remember { Animatable(0f) }
    val slotBounds = remember { HashMap<String, androidx.compose.ui.geometry.Rect>() }
    val arena = remember { DieArena() }
    var frame by remember { mutableLongStateOf(0L) }
    val unlockedStepCount by rememberUpdatedState(min(revealedStepCount, steps.size))
    val stepPlayed by rememberUpdatedState(onStepPlayed)
    val dismiss by rememberUpdatedState(onDismiss)

    val winnerName: String? = if (roll.winnerSeatID in playerIDs) seatNames[roll.winnerSeatID] ?: "Player" else null
    val nextWaitingSeatID: String? = if (activeSeatID == null && !playbackFinished && playedStepCount == unlockedStepCount)
        steps.getOrNull(playedStepCount)?.seatID else null

    fun tiedLeaders(index: Int): Set<String> {
        val round = rounds.getOrNull(index) ?: return emptySet()
        val highest = round.values.maxOrNull() ?: return emptySet()
        val leaders = round.filterValues { it == highest }
        return if (leaders.size > 1) leaders.keys else emptySet()
    }

    // The arena runs its own frame loop only while a die is in the air.
    val arenaActive = activeSeatID != null && !landed && !reduceMotion
    LaunchedEffect(arenaActive, spinTurns) {
        if (!arenaActive) return@LaunchedEffect
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 0f else ((now - last) / 1e9f).coerceAtMost(0.05f)
                last = now
                val (edge, rebound) = arena.step(dt)
                if (edge && edgeHitTurn != spinTurns) { edgeHitTurn = spinTurns; GameHaptics.selection(view) }
                if (rebound) reboundTurn = spinTurns
                frame = now
            }
        }
    }

    LaunchedEffect(rounds, roll.winnerSeatID, seatNames, reduceMotion, skipAnimation) {
        if (steps.isEmpty()) {
            shownRoundIndex = null; activeSeatID = null; settledRolls.clear(); playbackFinished = false; playedStepCount = 0
            return@LaunchedEffect
        }
        playbackFinished = false
        while (playedStepCount < steps.size) {
            if (playedStepCount >= unlockedStepCount) { delay(80); continue }
            val step = steps[playedStepCount]
            val seat = step.seatID; val value = step.value
            shownRoundIndex = step.roundIndex
            if (reduceMotion || skipAnimation) {
                settledRolls[seat] = value
                activeSeatID = null; activeValue = null; landed = false; revealFace = false; diePosition = null; flight = null
                playedStepCount += 1
                stepPlayed()
                continue
            }
            settledRolls.remove(seat)
            activeSeatID = seat; activeValue = value; landed = false; revealFace = false; diePosition = null
            edgeHitTurn = null; reboundTurn = null
            spinTurns += 1
            val diePoints = min(138f, max(108f, stageSize.width / density * 0.29f))
            val scale = diePoints / 2 * density
            arena.halfWidth = stageSize.width / (2 * scale); arena.halfHeight = stageSize.height / (2 * scale)
            arena.launch(spinTurns)
            GameAudio.play(GameSound.DICE_ROLL)
            // Physics decides the path, never the result. Wait for the trip back from the wall.
            for (attempt in 0 until 48) { if (reboundTurn == spinTurns) break; delay(100) }
            delay(450)
            revealFace = true
            arena.reveal(value)
            val point = Offset(stageSize.width / 2 + arena.x * scale, stageSize.height / 2 - arena.y * scale)
            diePosition = Offset(point.x.coerceIn(74 * density, max(74 * density, stageSize.width - 74 * density)),
                point.y.coerceIn(74 * density, max(74 * density, stageSize.height - 110 * density)))
            delay(280)
            if (diePosition == null) diePosition = Offset(stageSize.width / 2, stageSize.height * 0.40f)
            landed = true
            GameHaptics.impact(view)
            GameAudio.play(GameSound.DICE_LAND)
            // Long enough to read the result before the die flies into the player's square.
            delay(1900)
            val from = diePosition ?: Offset(stageSize.width / 2, stageSize.height * 0.4f)
            val slot = slotBounds[seat]
            if (slot != null) {
                flight = DieFlight(seat, value, from, 138 * density, slot.center - stageOrigin, slot.width)
                flightProgress.snapTo(0f)
                scope.launch { flightProgress.animateTo(1f, spring(0.78f, 160f)) }
            }
            settledRolls[seat] = value
            activeSeatID = null; landed = false
            delay(450)
            flight = null
            playedStepCount += 1
            stepPlayed()
        }
        playbackFinished = true
        if (winnerName != null) {
            delay(if (reduceMotion || skipAnimation) 1200 else 1900)
            if (!didAutoDismiss) { didAutoDismiss = true; dismiss() }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { coordinates ->
        stageSize = androidx.compose.ui.geometry.Size(coordinates.size.width.toFloat(), coordinates.size.height.toFloat())
        stageOrigin = coordinates.boundsInRoot().topLeft
    }) {
        val wide = maxWidth > maxHeight && maxWidth >= 560.dp
        val stageHeight = maxHeight
        val columnCount = if (wide) playerIDs.size else 2
        if (arenaActive) {
            val measurer = rememberTextMeasurer()
            val labels = remember(measurer) { (1..20).map { measurer.measure(it.toString(), sf(40f, SfWeight.bold).copy(fontFeatureSettings = "tnum")) } }
            Canvas(Modifier.fillMaxSize().semantics { contentDescription = "D20 rolling" }) {
                @Suppress("UNUSED_VARIABLE") val tick = frame
                val diePoints = min(138f, max(108f, size.width / density * 0.29f))
                val scale = diePoints / 2 * density
                drawD20(arena.orientation, Offset(size.width / 2 + arena.x * scale, size.height / 2 - arena.y * scale), scale, labels,
                    showLabels = revealFace)
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center) {
            Column(Modifier.widthIn(max = if (wide) 900.dp else 620.dp).fillMaxWidth().heightIn(min = stageHeight).padding(horizontal = if (wide) 24.dp else 20.dp),
                verticalArrangement = Arrangement.spacedBy(if (wide) 12.dp else 22.dp, Alignment.CenterVertically)) {
                // Header
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("STARTING ROLL", color = D20Palette.accent, style = sf(12f, SfWeight.bold, tracking = 1.5f))
                    val headline = when {
                        playbackFinished && winnerName != null -> if (isLocalWinner) "You go first" else "$winnerName goes first"
                        activeSeatID != null -> "${seatNames[activeSeatID] ?: "Player"} rolls"
                        nextWaitingSeatID != null -> if (nextWaitingSeatID == localSeatID) "Your roll" else "${seatNames[nextWaitingSeatID] ?: "Player"}'s roll"
                        (shownRoundIndex ?: 0) > 0 -> "Tie. Roll again."
                        else -> "Who goes first?"
                    }
                    Text(headline, color = D20Palette.ink, style = SfText.title2(SfWeight.bold))
                    val detail = shownRoundIndex?.let { index ->
                        if (playbackFinished && winnerName != null) "Round ${index + 1} of ${rounds.size} · D20"
                        else "Round ${index + 1} of ${rounds.size} · Highest roll starts. Ties reroll."
                    } ?: if (nextWaitingSeatID == localSeatID) "Tap to roll D20. Highest starts; ties reroll." else "Waiting for the next player to roll."
                    Text(detail, color = D20Palette.secondary, style = SfText.subheadline())
                    if (!playbackFinished && !reduceMotion) {
                        Text("Skip animation", Modifier.padding(top = 5.dp).clickable { skipAnimation = true }
                            .semantics { contentDescription = "Skip animation" }, color = D20Palette.accent, style = SfText.caption(SfWeight.semibold))
                    }
                }
                if (!playbackFinished) {
                    Spacer(Modifier.fillMaxWidth().height(if (wide) min(52f, max(32f, stageHeight.value * 0.12f)).dp
                        else min(360f, max(250f, stageHeight.value * 0.40f)).dp).semantics {
                        contentDescription = if (reboundTurn == spinTurns) "Rebounded from screen edge" else if (edgeHitTurn == spinTurns) "Touched screen edge" else "D20 roll area"
                    })
                }
                // Result and roll control
                Box(Modifier.fillMaxWidth().height(if (wide) 62.dp else 72.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.widthIn(max = if (wide) 340.dp else 440.dp), contentAlignment = Alignment.Center) {
                        val value = activeValue
                        val shown = landed && value != null
                        val resultAlpha by androidx.compose.animation.core.animateFloatAsState(if (shown) 1f else 0f, tween(220), label = "rollResult")
                        val resultScale by androidx.compose.animation.core.animateFloatAsState(if (shown) 1f else 0.72f, spring(0.6f, 300f), label = "rollResultScale")
                        if (shown || resultAlpha > 0.01f) {
                            Text("Rolled ${value ?: ""}", Modifier.scale(resultScale).alpha(resultAlpha).background(D20Palette.surface, CircleShape)
                                .padding(horizontal = 18.dp, vertical = 8.dp),
                                color = D20Palette.ink, style = SfText.title(SfWeight.bold).copy(fontFeatureSettings = "tnum"))
                        }
                        if (!landed && nextWaitingSeatID != null) {
                            if (nextWaitingSeatID == localSeatID) {
                                BrandButton(onRollTap, enabled = !rollPending) { BrandButtonText(if (rollPending) "Sharing your roll…" else "Tap to roll D20") }
                            } else {
                                Text("Waiting for ${seatNames[nextWaitingSeatID] ?: "the next player"} to roll…", color = D20Palette.ink,
                                    style = SfText.subheadline(SfWeight.semibold), textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
                // Player cards
                playerIDs.chunked(maxOf(1, columnCount)).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { playerID ->
                            val name = seatNames[playerID] ?: "Player"
                            val value = settledRolls[playerID]
                            val isRolling = activeSeatID == playerID
                            val isWinner = playbackFinished && roll.winnerSeatID == playerID
                            val isOut = shownRoundIndex?.let { it > 0 && rounds[it][playerID] == null && value != null } ?: false
                            val status = when {
                                isWinner && value != null -> "Rolled $value · Goes first"
                                isOut -> "Out of the reroll"
                                isRolling -> "Rolling…"
                                value == null -> "Ready"
                                shownRoundIndex.let { it != null && it < rounds.size - 1 && playerID in tiedLeaders(it) } -> "Tied · reroll"
                                else -> "Rolled $value"
                            }
                            val shape = RoundedCornerShape(18.dp)
                            Column(Modifier.weight(1f).alpha(if (isOut) 0.65f else 1f).background(D20Palette.surface, shape)
                                .border(if (isWinner) 2.dp else 1.dp, if (isWinner) D20Palette.accent else D20Palette.ink.copy(alpha = 0.12f), shape)
                                .padding(vertical = if (wide) 8.dp else 18.dp, horizontal = 8.dp)
                                .semantics { contentDescription = if (isRolling) "$name is rolling a twenty-sided die" else value?.let { "$name rolled $it on a twenty-sided die" } ?: "$name, waiting to roll" },
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (wide) 7.dp else 10.dp)) {
                                val slot = if (wide) 56.dp else 76.dp
                                Box(Modifier.size(slot).onGloballyPositioned { slotBounds[playerID] = it.boundsInRoot() }, contentAlignment = Alignment.Center) {
                                    if (value != null && !isRolling) {
                                        D20Face(value, isWinner, Modifier.fillMaxSize().alpha(if (flight?.seat == playerID) 0f else 1f), compact = wide)
                                    } else SfImage("dice", D20Palette.secondary.copy(alpha = 0.7f), 29.dp)
                                }
                                Text(name, color = D20Palette.ink, style = SfText.subheadline(SfWeight.semibold), maxLines = 2, textAlign = TextAlign.Center)
                                Text(status, color = if (isWinner) D20Palette.accent else D20Palette.secondary, style = SfText.caption(SfWeight.medium),
                                    maxLines = 2, textAlign = TextAlign.Center)
                            }
                        }
                        repeat(maxOf(1, columnCount) - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        // The landed die, then its flight into the roller's square.
        val position = diePosition
        if (landed && activeSeatID != null && position != null) {
            val appear = remember(spinTurns) { Animatable(0.6f) }
            LaunchedEffect(spinTurns) { appear.animateTo(1f, spring(0.58f, 250f)) }
            D20Face(activeValue, true, Modifier.offset { IntOffset((position.x - 69 * density).roundToInt(), (position.y - 69 * density).roundToInt()) }
                .requiredSize(138.dp).alpha(appear.value.coerceIn(0f, 1f)).scale(appear.value), compact = false)
        }
        flight?.let { f ->
            val p = flightProgress.value
            val center = Offset(f.from.x + (f.to.x - f.from.x) * p, f.from.y + (f.to.y - f.from.y) * p)
            val size = f.fromSize + (f.toSize - f.fromSize) * p
            D20Face(f.value, false, Modifier.offset { IntOffset((center.x - size / 2).roundToInt(), (center.y - size / 2).roundToInt()) }
                .requiredSize((size / density).dp))
        }
    }
}
