package io.magicmobile.android.ondevice

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.R
import io.magicmobile.android.board.GameHaptics
import io.magicmobile.android.studio.BinderPlaque
import io.magicmobile.android.studio.BinderTag
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonText
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.engraved
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernBrassFrame
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.tavernImage
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min

/** The Walnut Tavern inks: cream and brass on leather, brown on parchment. */
private object D20Ink {
    val cream = Color(0.98f, 0.92f, 0.80f)
    val muted = Color(0.84f, 0.72f, 0.52f)
    val brass = Color(0.98f, 0.82f, 0.48f)
    val brown = Color(0.24f, 0.12f, 0.05f)
    val brownSoft = Color(0.42f, 0.27f, 0.14f)
}

/** The number a seat rolled, struck on a brass coin; blank (a dash) before the seat has rolled. */
@Composable
private fun SeatCoin(value: Int?, size: androidx.compose.ui.unit.Dp, lit: Boolean) {
    val coin = tavernImage(R.drawable.tavern_ui_coin)
    Box(Modifier.size(size).then(if (lit) Modifier.glow(TavernPalette.ember.copy(alpha = 0.9f), 2.dp, 8.dp) else Modifier)
        .clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        androidx.compose.foundation.Image(coin, null, Modifier.fillMaxSize())
        Text(value?.toString() ?: "–", color = Color(0.25f, 0.12f, 0.04f).copy(alpha = if (value == null) 0.45f else 1f), maxLines = 1,
            style = sf(size.value * (if ((value ?: 0) >= 10) 0.46f else 0.54f), SfWeight.black, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
    }
}

/**
 * Port of MultiplayerD20View.swift: plays back an authoritative starting roll. The match owner
 * decides every value, tie round and the winner; this view only shows them, on the tavern table:
 * each seat's d20 is thrown onto the board's leather mat, tumbles, bounces off the rail and settles on
 * the number the game decided (StartingRollTable.kt, docs/STARTING_ROLL.md).
 */
@Composable
fun MultiplayerD20View(roll: OnDeviceStartingRoll, seatNames: Map<String, String>, isLocalWinner: Boolean, revealedStepCount: Int,
                       localSeatID: String?, rollPending: Boolean = false, onRollTap: () -> Unit, onStepPlayed: () -> Unit = {},
                       onDismiss: () -> Unit) {
    val reduceMotion = LaunchEnvironment.reduceMotion
    val view = LocalView.current
    val context = LocalContext.current
    val rounds = roll.rounds
    val steps = roll.steps
    val playerIDs = run {
        val ids = (rounds.firstOrNull()?.keys ?: seatNames.keys).toSet()
        // The roll's own order (the viewer first), which is also the table's lane order.
        val ordered = roll.seatOrder.filter { it in ids }
        ordered + (ids - ordered.toSet()).sorted()
    }
    var shownRoundIndex by remember { mutableStateOf<Int?>(null) }
    var activeSeatID by remember { mutableStateOf<String?>(null) }
    var activeValue by remember { mutableStateOf<Int?>(null) }
    val settledRolls = remember { mutableStateMapOf<String, Int>() }
    var landed by remember { mutableStateOf(false) }
    var edgeHitTurn by remember { mutableStateOf<Int?>(null) }
    var reboundTurn by remember { mutableStateOf<Int?>(null) }
    var restTurn by remember { mutableStateOf<Int?>(null) }
    var playbackFinished by remember { mutableStateOf(false) }
    var spinTurns by remember { mutableIntStateOf(0) }
    var skipAnimation by remember { mutableStateOf(false) }
    var playedStepCount by remember { mutableIntStateOf(0) }
    var didAutoDismiss by remember { mutableStateOf(false) }
    // The dice on the table: the round they belong to, the ones at rest and the one in the air.
    var tableRound by remember { mutableIntStateOf(0) }
    val tableResting = remember { mutableStateMapOf<String, Int>() }
    var tableThrow by remember { mutableStateOf<D20TableState.Throw?>(null) }
    var rollRegion by remember { mutableStateOf(Rect.Zero) }
    var tableOrigin by remember { mutableStateOf(Offset.Zero) }
    val unlockedStepCount by rememberUpdatedState(min(revealedStepCount, steps.size))
    val stepPlayed by rememberUpdatedState(onStepPlayed)
    val dismiss by rememberUpdatedState(onDismiss)
    val tableReady = remember { D20Assets.available(context) }
    var tableDrawn by remember { mutableStateOf(!tableReady) }
    val drawn by rememberUpdatedState(tableDrawn)

    val winnerName: String? = if (roll.winnerSeatID in playerIDs) seatNames[roll.winnerSeatID] ?: "Player" else null
    val nextWaitingSeatID: String? = if (activeSeatID == null && !playbackFinished && playedStepCount == unlockedStepCount)
        steps.getOrNull(playedStepCount)?.seatID else null

    fun tiedLeaders(index: Int): Set<String> {
        val round = rounds.getOrNull(index) ?: return emptySet()
        val highest = round.values.maxOrNull() ?: return emptySet()
        val leaders = round.filterValues { it == highest }
        return if (leaders.size > 1) leaders.keys else emptySet()
    }

    LaunchedEffect(rounds, roll.winnerSeatID, seatNames, reduceMotion, skipAnimation) {
        if (steps.isEmpty()) {
            shownRoundIndex = null; activeSeatID = null; settledRolls.clear(); playbackFinished = false; playedStepCount = 0
            tableResting.clear(); tableThrow = null
            return@LaunchedEffect
        }
        playbackFinished = false
        // The roll starts (briefly) after the table's first frames, so no die is thrown, or laid down, into a blank screen.
        var waitedForTable = 0
        while (!drawn && waitedForTable < 5000) { delay(100); waitedForTable += 100 }
        while (playedStepCount < steps.size) {
            if (playedStepCount >= unlockedStepCount) { delay(80); continue }
            val step = steps[playedStepCount]
            val seat = step.seatID; val value = step.value
            shownRoundIndex = step.roundIndex
            // A reroll starts with a bare table: the dice come up and the tied seats throw again.
            if (step.roundIndex != tableRound) {
                tableRound = step.roundIndex
                tableResting.clear()
                tableThrow = null
                if (!(reduceMotion || skipAnimation)) delay(380)
            }
            if (reduceMotion || skipAnimation) {
                // No tumble: the die lies on its number and the roll moves on.
                tableThrow = null
                tableResting[seat] = value
                settledRolls[seat] = value
                activeSeatID = null; activeValue = null; landed = false
                playedStepCount += 1
                stepPlayed()
                continue
            }
            settledRolls.remove(seat)
            tableResting.remove(seat)
            activeSeatID = seat; activeValue = value; landed = false
            edgeHitTurn = null; reboundTurn = null; restTurn = null
            spinTurns += 1
            tableThrow = D20TableState.Throw(seat, value, spinTurns)
            GameAudio.play(GameSound.DICE_ROLL)
            // The recording decides the path, never the result. Wait for the die to come to rest, with a
            // bounded recovery if rendering pauses (or a build has no dice assets).
            for (attempt in 0 until (if (tableReady) 90 else 6)) { if (restTurn == spinTurns) break; delay(100) }
            tableResting[seat] = value
            tableThrow = null
            landed = true
            GameHaptics.impact(view)
            GameAudio.play(GameSound.DICE_LAND)
            // Long enough to read the result before the roll moves on.
            delay(1900)
            settledRolls[seat] = value
            activeSeatID = null; landed = false
            delay(450)
            playedStepCount += 1
            stepPlayed()
        }
        playbackFinished = true
        if (winnerName != null) {
            delay(if (reduceMotion || skipAnimation) 1200 else 1900)
            if (!didAutoDismiss) { didAutoDismiss = true; dismiss() }
        }
    }

    val tableState = D20TableState(playerIDs, tableRound, tableResting.toMap(), tableThrow, if (playbackFinished) roll.winnerSeatID else null)
    Box(Modifier.fillMaxSize()) {
        // The tavern table fills the whole screen behind the controls; its camera frames the roll area.
        D20TableView(rollRegion.translate(-tableOrigin.x, -tableOrigin.y), tableState, reduceMotion,
            Modifier.fillMaxSize().onGloballyPositioned { tableOrigin = it.boundsInRoot().topLeft }.clearAndSetSemantics {},
            onEdgeHit = { turn -> if (turn == spinTurns && edgeHitTurn != turn) { edgeHitTurn = turn; GameHaptics.selection(view) } },
            onRebound = { turn -> if (turn == spinTurns) reboundTurn = turn },
            onRest = { turn -> if (turn == spinTurns) restTurn = turn },
            onReady = { tableDrawn = true })
        BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            val wide = maxWidth > maxHeight && maxWidth >= 560.dp
            val stageHeight = maxHeight
            val columnCount = if (wide) playerIDs.size else 2
            // Upright the roll area takes everything the header, the result and the seat plates leave, so the throw
            // runs its full length across the table (Caleb, 2026-10-07: the dice had too little room).
            val plateRows = (playerIDs.size + columnCount - 1) / columnCount
            val uprightRoll = max(260f, stageHeight.value - 128f - 64f - (plateRows * 70f + max(0, plateRows - 1) * 18f) - 18f * 3 - 16f)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Top) {
                // The header sits at the top of the screen, not floating in the middle.
                Column(Modifier.widthIn(max = if (wide) 900.dp else 620.dp).fillMaxWidth().heightIn(min = stageHeight)
                    .padding(start = if (wide) 24.dp else 18.dp, end = if (wide) 24.dp else 18.dp, top = if (wide) 4.dp else 8.dp),
                    verticalArrangement = Arrangement.spacedBy(if (wide) 8.dp else 18.dp, Alignment.Top)) {
                    // Header: leather in brass, the skip plaque riveted at its corner.
                    val headline = when {
                        playbackFinished && winnerName != null -> if (isLocalWinner) "You go first" else "$winnerName goes first"
                        activeSeatID != null -> "${seatNames[activeSeatID] ?: "Player"} rolls"
                        nextWaitingSeatID != null -> if (nextWaitingSeatID == localSeatID) "Your roll" else "${seatNames[nextWaitingSeatID] ?: "Player"}'s roll"
                        (shownRoundIndex ?: 0) > 0 -> "Tie. Roll again."
                        else -> "Who goes first?"
                    }
                    val detail = shownRoundIndex?.let { index ->
                        if (playbackFinished && winnerName != null) "Round ${index + 1} of ${rounds.size} · D20"
                        else "Round ${index + 1} of ${rounds.size} · Highest roll starts. Ties reroll."
                    } ?: if (nextWaitingSeatID == localSeatID) "Tap to roll D20. Highest starts; ties reroll." else "Waiting for the next player to roll."
                    val headlineStyle = sf(if (wide) 17f else 24f, SfWeight.heavy, SfDesign.SERIF).engraved(0.7f)
                    val skipPlaque: @Composable () -> Unit = {
                        if (!playbackFinished && !reduceMotion) BinderPlaque(title = "Skip", label = "Skip animation", onClick = { skipAnimation = true })
                    }
                    Column(Modifier.fillMaxWidth().shadow(8.dp, RoundedCornerShape(12.dp)).tavernBrassFrame(0.5f).padding(2.dp)
                        .tavernFill(TavernMaterial.LEATHER, RoundedCornerShape(12.dp)).padding(horizontal = 16.dp, vertical = if (wide) 4.dp else 12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (wide) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                BinderTag("STARTING ROLL", material = TavernMaterial.EMBER, jewel = true)
                                Column(Modifier.weight(1f)) {
                                    Text(headline, color = D20Ink.cream, style = headlineStyle, maxLines = 1)
                                    Text(detail, color = D20Ink.muted, style = sf(13f, SfWeight.medium, SfDesign.SERIF), maxLines = 2)
                                }
                                skipPlaque()
                            }
                        } else {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                BinderTag("STARTING ROLL", material = TavernMaterial.EMBER, jewel = true)
                                Spacer(Modifier.weight(1f))
                                skipPlaque()
                            }
                            Text(headline, color = D20Ink.cream, style = headlineStyle)
                            Text(detail, color = D20Ink.muted, style = sf(14f, SfWeight.medium, SfDesign.SERIF))
                        }
                    }
                    // The roll area stays, so the dice stay in view under the result; it only speaks while rolling.
                    Spacer(Modifier.fillMaxWidth().height(if (wide) max(120f, stageHeight.value - 178f).dp else uprightRoll.dp)
                        .onGloballyPositioned { rollRegion = it.boundsInRoot() }
                        .then(if (playbackFinished) Modifier.clearAndSetSemantics {} else Modifier.semantics {
                            contentDescription = if (reboundTurn == spinTurns) "Rebounded from screen edge" else if (edgeHitTurn == spinTurns) "Touched screen edge" else "D20 roll area"
                        }))
                    // Result and roll control
                    Box(Modifier.fillMaxWidth().height(if (wide) 48.dp else 64.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.widthIn(max = if (wide) 340.dp else 440.dp), contentAlignment = Alignment.Center) {
                            val value = activeValue
                            val shown = landed && value != null
                            val resultAlpha by animateFloatAsState(if (shown) 1f else 0f, tween(220), label = "rollResult")
                            val resultScale by animateFloatAsState(if (shown) 1f else 0.72f, spring(0.6f, 300f), label = "rollResultScale")
                            if (shown || resultAlpha > 0.01f) {
                                Text("Rolled ${value ?: ""}", Modifier.scale(resultScale).alpha(resultAlpha).shadow(5.dp, CircleShape)
                                    .tavernCapsuleRim().defaultMinSize(minHeight = 46.dp).padding(3.dp).tavernFill(TavernMaterial.PARCHMENT, CircleShape)
                                    .padding(horizontal = 23.dp, vertical = 5.dp),
                                    color = D20Ink.brown, style = sf(24f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
                            }
                            if (!landed && nextWaitingSeatID != null) {
                                if (nextWaitingSeatID == localSeatID) {
                                    TavernButton(onRollTap, enabled = !rollPending, fontSize = 17f, fullWidth = true) {
                                        TavernButtonText(if (rollPending) "Sharing your roll…" else "Tap to roll D20")
                                    }
                                } else {
                                    Text("Waiting for ${seatNames[nextWaitingSeatID] ?: "the next player"} to roll…", Modifier.tavernCapsuleRim(thin = true)
                                        .defaultMinSize(minHeight = 36.dp).padding(1.5.dp).tavernFill(TavernMaterial.LEATHER, CircleShape)
                                        .padding(horizontal = 18.dp, vertical = 7.dp),
                                        color = D20Ink.brass, style = sf(15f, SfWeight.bold, SfDesign.SERIF), textAlign = TextAlign.Center)
                                }
                            }
                        }
                    }
                    // Seat plates
                    playerIDs.chunked(maxOf(1, columnCount)).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (wide) 10.dp else 12.dp)) {
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
                                val ink = if (isWinner) D20Ink.cream else if (isOut) D20Ink.muted else D20Ink.brown
                                val secondary = if (isWinner) D20Ink.cream.copy(alpha = 0.85f) else if (isOut) D20Ink.muted.copy(alpha = 0.8f) else D20Ink.brownSoft
                                Row(Modifier.weight(1f).alpha(if (isOut) 0.78f else 1f)
                                    .shadow(if (isWinner) 10.dp else 5.dp, RoundedCornerShape(10.dp), ambientColor = if (isWinner) TavernPalette.ember else Color.Black,
                                        spotColor = if (isWinner) TavernPalette.ember else Color.Black)
                                    .tavernBrassFrame(0.5f).padding(2.dp)
                                    .tavernFill(if (isWinner) TavernMaterial.EMBER else if (isOut) TavernMaterial.LEATHER else TavernMaterial.PARCHMENT, RoundedCornerShape(10.dp))
                                    .defaultMinSize(minHeight = if (wide) 50.dp else 62.dp)
                                    .padding(horizontal = if (wide) 12.dp else 14.dp, vertical = if (wide) 5.dp else 10.dp)
                                    .semantics { contentDescription = if (isRolling) "$name is rolling a twenty-sided die" else value?.let { "$name rolled $it on a twenty-sided die" } ?: "$name, waiting to roll" },
                                    horizontalArrangement = Arrangement.spacedBy(if (wide) 8.dp else 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    SeatCoin(if (isRolling) null else value, if (wide) 38.dp else 46.dp, isWinner)
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text(name, color = ink, style = sf(if (wide) 15f else 17f, SfWeight.heavy, SfDesign.SERIF), maxLines = 2)
                                        Text(status, color = secondary, style = sf(12f, SfWeight.semibold, SfDesign.SERIF), maxLines = 2)
                                    }
                                }
                            }
                            repeat(maxOf(1, columnCount) - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Swift StartingRollCover: the starting roll's full-screen cover on dark walnut, so nothing behind it
 * (such as "Select a starting player") shows through or takes a tap. The cover is full-bleed (the table
 * runs under the system bars); each screen on it keeps its own controls inside the safe area.
 */
@Composable
fun StartingRollCover(content: @Composable BoxScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Color(0.09f, 0.05f, 0.03f)).clickable(remember { MutableInteractionSource() }, null) {},
        contentAlignment = Alignment.Center, content = content)
}
