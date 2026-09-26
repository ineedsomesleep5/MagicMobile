package io.magicmobile.android.board

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardOpponentFocus
import io.magicmobile.android.game.BoardPlayerStatus
import io.magicmobile.android.game.BoardResponseCue
import io.magicmobile.android.game.BoardZoneReference
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.ManaPool
import io.magicmobile.android.game.PhaseTitles
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.XmageStackObject
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.capitalizedWords
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.delay

/** Increments when a phase pill lands in the top bar, which then flashes its turn label. */
val LocalBoardHUDPulse = compositionLocalOf { 0 }
/** Opens a zone inspector scoped to a snapshot reference (Swift `boardZoneInspectionAction`). */
val LocalBoardZoneInspectionAction = compositionLocalOf<((BoardZoneReference) -> Unit)?> { null }

object BoardTurnColors {
    val opponent = rgb(0.62, 0.74, 1.0)
}

data class CommanderHudSummary(val life: Int, val commanderTax: Int?, val handCount: Int, val libraryCount: Int, val graveyardCount: Int,
                               val exileCount: Int, val commanderDamage: Int?) {
    val commanderTaxLabel: String get() = commanderTax?.toString() ?: "—"
    val commanderDamageLabel: String get() = commanderDamage?.toString() ?: "—"
    val commandZoneLabel: String get() = commanderTax?.let { "Command ($it)" } ?: "Command"

    companion object {
        fun of(player: PlayerGameState, opponentId: String?) = CommanderHudSummary(player.life,
            if (player.hasKnownCommanderTax) player.commanderTax else null, player.zones.visibleHandCount, player.zones.visibleLibraryCount,
            player.zones.graveyard.size, player.zones.exile.size, player.commanderDamage?.let { damage -> opponentId?.let { damage[it] } ?: 0 })
    }
}

/**
 * A player's face at the table: their commander's art in a ring that turns gold on their
 * turn, spins while an AI decides, and greys out with a skull once they are out.
 */
@Composable
fun PlayerPortrait(player: PlayerGameState, size: Dp = 44.dp, active: Boolean = false, thinking: Boolean = false, modifier: Modifier = Modifier) {
    val commanderName = player.commanders?.mapNotNull { it.name }?.firstOrNull { it.isNotEmpty() }
    val ring = when { player.isOut -> Color.Gray.copy(alpha = 0.6f); active -> MagicPalette.antiqueGold; else -> MagicPalette.borderBronze.copy(alpha = 0.8f) }
    Box(modifier.requiredSize(size), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().glow(if (active) MagicPalette.antiqueGold.copy(alpha = 0.55f) else Color.Transparent, 6.dp, size / 2)
            .clip(CircleShape).background(Brush.verticalGradient(listOf(MagicPalette.iron, MagicPalette.leather)))
            .colorAdjust(if (player.isOut) 0f else 1f).alpha(if (player.isOut) 0.5f else 1f), contentAlignment = Alignment.Center) {
            val initials: @Composable () -> Unit = {
                Text((player.displayName ?: "?").take(1).uppercase(), color = MagicPalette.parchment, style = sf(size.value * 0.44f, SfWeight.black, SfDesign.ROUNDED))
            }
            if (commanderName != null && !BoardArtwork.forcePlaceholders) {
                CardArtwork(commanderName, Modifier.fillMaxSize().background(Color.Transparent), artOnly = true) {
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(MagicPalette.iron, MagicPalette.leather))), contentAlignment = Alignment.Center) { initials() }
                }
            } else initials()
        }
        Box(Modifier.fillMaxSize().border(if (active) 2.5.dp else 1.3.dp, ring, CircleShape))
        if (thinking && !player.isOut) ThinkingRing(BoardTurnColors.opponent, BoardMotion.reduceMotion, Modifier.requiredSize(size + 7.dp))
        if (player.isOut) {
            Box(Modifier.align(Alignment.BottomCenter).offset(y = size * 0.14f).background(MagicPalette.oxblood, CircleShape).padding(3.dp)) {
                SfImage("skull.fill", Color.White, size * 0.3f)
            }
        }
    }
}

/** A short arc orbiting a portrait while that player decides. */
@Composable
fun ThinkingRing(color: Color, still: Boolean, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "thinking")
    val angle by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(1100, easing = LinearEasing)), label = "thinkingAngle")
    Canvas(modifier) {
        val stroke = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round)
        val inset = stroke.width / 2
        val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke.width, size.height - stroke.width)
        if (still) drawArc(color.copy(alpha = 0.7f), 0f, 360f, false, Offset(inset, inset), arcSize, style = stroke)
        else drawArc(color, angle - 90f, 108f, false, Offset(inset, inset), arcSize, style = stroke)
    }
}

/** "Aurelia is thinking" with three pulsing dots. */
@Composable
fun ThinkingLabel(name: String, color: Color, style: androidx.compose.ui.text.TextStyle, modifier: Modifier = Modifier) {
    var phase by remember { mutableIntStateOf(0) }
    val reduceMotion = BoardMotion.reduceMotion
    LaunchedEffect(reduceMotion) { if (!reduceMotion) while (true) { delay(320); phase = (phase + 1) % 3 } }
    Row(modifier.semantics { contentDescription = "$name is thinking" }, horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("$name is thinking", color = color, style = style, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            repeat(3) { index -> Box(Modifier.size(3.5.dp).alpha(if (reduceMotion) 0.8f else if (phase == index) 1f else 0.3f).background(color, CircleShape)) }
        }
    }
}

/** Changes are visual feedback only; life always comes from the current snapshot. */
@Composable
fun BoardLifeTotal(life: Int, style: androidx.compose.ui.text.TextStyle, modifier: Modifier = Modifier, suffix: String = "",
                   baseColor: Color = MagicPalette.antiqueGold) {
    val boardEffects by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val showsBadge = BoardFXLevel.of(boardEffects) == BoardFXLevel.OFF
    var previous by remember { mutableIntStateOf(life) }
    var delta by remember { mutableIntStateOf(0) }
    var token by remember { mutableIntStateOf(0) }
    val reduceMotion = BoardMotion.reduceMotion
    LaunchedEffect(life) {
        if (life != previous) { delta = life - previous; previous = life; token += 1 }
    }
    LaunchedEffect(token) { if (delta != 0) { delay(1200); delta = 0 } }
    val color by animateColorAsState(if (delta == 0) baseColor else if (delta < 0) Color.Red else Color.Green, tween(200), label = "lifeColor")
    val scale by animateFloatAsState(if (delta == 0 || reduceMotion) 1f else 1.16f, if (reduceMotion) tween(0) else spring(0.65f, 440f), label = "lifeScale")
    Box(modifier.semantics { contentDescription = "$life life" }) {
        Text("$life$suffix", Modifier.scale(scale), color = color, style = style.copy(fontFeatureSettings = "tnum"), maxLines = 1)
        if (delta != 0 && showsBadge) {
            Text(if (delta > 0) "+$delta" else "$delta", Modifier.align(Alignment.TopEnd).offset(x = 18.dp, y = (-16).dp)
                .background(Color.Black.copy(alpha = 0.9f), CircleShape).padding(3.dp),
                color = if (delta < 0) Color.Red else Color.Green, style = SfText.caption(SfWeight.bold))
        }
    }
}

/**
 * Public player effects remain next to that player's HUD and use the same zone inspector as
 * battlefield permanents.
 */
@Composable
fun BoardPlayerEffects(player: PlayerGameState, attachments: List<ZoneCard> = emptyList(), viewZone: ((String, List<ZoneCard>) -> Unit)? = null,
                       opponents: List<PlayerGameState> = emptyList(), selectOpponent: ((String) -> Unit)? = null) {
    val counters = BoardPlayerStatus.counters(player)
    if (counters.isEmpty() && attachments.isEmpty() && player.monarch != true && player.initiative != true && opponents.size <= 1) return
    val description = buildList {
        add("${player.displayName ?: "Player"} effects")
        addAll(counters.map { "${it.first} ${it.second}" })
        if (player.monarch == true) add("Monarch")
        if (player.initiative == true) add("Initiative")
        addAll(attachments.map { "${it.card.name} attached" })
    }.joinToString(", ")
    BoardMenu({
        buildList {
            counters.forEach { add(MenuEntry.Label("${capitalizedWords(it.first)}: ${it.second}")) }
            if (player.monarch == true) add(MenuEntry.Label("Monarch"))
            if (player.initiative == true) add(MenuEntry.Label("Has the initiative"))
            if (viewZone != null) attachments.forEach { card ->
                add(MenuEntry.Item("${card.card.name} · attached") { viewZone("Enchanting ${player.displayName ?: "player"}", attachments) })
            }
            if (opponents.size > 1 && selectOpponent != null) {
                add(MenuEntry.Section("View opponent"))
                opponents.forEach { opponent -> add(MenuEntry.Item(opponent.displayName ?: "Opponent") { selectOpponent(opponent.playerId) }) }
            }
        }
    }, Modifier.semantics { contentDescription = description }) {
        val first = counters.firstOrNull()
        Row(Modifier.heightIn(min = 44.dp).background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(7.dp)).padding(horizontal = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            val style = sf(10f, SfWeight.bold)
            if (opponents.size > 1) SfImage("person.2.fill", MagicPalette.antiqueGold, 10.dp)
            when {
                first != null -> Text("${capitalizedWords(first.first)} ${first.second}", color = MagicPalette.antiqueGold, style = style, maxLines = 1)
                attachments.isNotEmpty() -> { SfImage("link", MagicPalette.antiqueGold, 10.dp); Text("${attachments.size}", color = MagicPalette.antiqueGold, style = style) }
                player.monarch == true -> SfImage("crown.fill", MagicPalette.antiqueGold, 10.dp)
                player.initiative == true -> SfImage("flag.fill", MagicPalette.antiqueGold, 10.dp)
            }
        }
    }
}

@Composable
fun OpponentFocusMenu(snapshot: GameSnapshot, selectOpponent: (String) -> Unit) {
    val opponents = BoardOpponentFocus.opponents(snapshot)
    if (opponents.size <= 1) return
    BoardMenu({
        opponents.map { player ->
            MenuEntry.Item(snapshot.playerLabel(player.playerId), if (snapshot.opponent?.playerId == player.playerId) "checkmark.circle.fill" else "circle") {
                selectOpponent(player.playerId)
            }
        }
    }, Modifier.semantics { contentDescription = "Choose opponent to view" }) {
        Box(Modifier.size(44.dp).background(MagicPalette.iron.copy(alpha = 0.8f), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
            SfImage("person.2.fill", MagicPalette.antiqueGold, 13.dp)
        }
    }
}

/** Only the engine's authorized zone projection is ever presented. */
@Composable
fun PlayerZoneMenu(player: PlayerGameState, viewZone: (String, List<ZoneCard>) -> Unit, snapshot: GameSnapshot? = null, pendingActionID: String? = null) {
    val inspectZone = LocalBoardZoneInspectionAction.current
    val commanderReady = snapshot?.let { GameplayAffordances.commanderCastAvailable(player, it, pendingActionID) } ?: false
    fun open(zone: BoardZoneReference.PlayerZone, cards: List<ZoneCard>) {
        if (inspectZone != null) inspectZone(BoardZoneReference.Player(player.playerId, zone))
        else viewZone("${player.displayName ?: player.playerId} · ${capitalizedWords(zone.rawValue)}", cards)
    }
    BoardMenu({
        buildList {
            add(MenuEntry.Item(if (commanderReady) "Command · Cast available" else "Command · ${player.zones.command.size}") { open(BoardZoneReference.PlayerZone.COMMAND, player.zones.command) })
            add(MenuEntry.Item("Graveyard · ${player.zones.graveyard.size}") { open(BoardZoneReference.PlayerZone.GRAVEYARD, player.zones.graveyard) })
            add(MenuEntry.Item("Exile · ${player.zones.exile.size}") { open(BoardZoneReference.PlayerZone.EXILE, player.zones.exile) })
            add(MenuEntry.Item("Hand · ${player.zones.visibleHandCount}") { open(BoardZoneReference.PlayerZone.HAND, player.zones.hand) })
            add(MenuEntry.Item("Library · ${player.zones.visibleLibraryCount}") { open(BoardZoneReference.PlayerZone.LIBRARY, player.zones.library) })
            add(MenuEntry.Item("Battlefield · ${player.zones.battlefield.size}") { open(BoardZoneReference.PlayerZone.BATTLEFIELD, player.zones.battlefield) })
            if (snapshot != null) {
                val named = BoardZoneReference.namedReferences(snapshot)
                if (named.isNotEmpty()) add(MenuEntry.Divider)
                named.forEach { reference ->
                    add(MenuEntry.Item("${reference.title(snapshot)} · ${reference.cards(snapshot).size}") {
                        if (inspectZone != null) inspectZone(reference) else viewZone(reference.title(snapshot), reference.cards(snapshot))
                    })
                }
            }
        }
    }, Modifier.semantics { contentDescription = "${player.displayName ?: player.playerId} zones${if (commanderReady) ", commander cast available" else ""}" }) {
        Box(Modifier.defaultMinSize(44.dp, 44.dp)
            .glow(if (commanderReady) MagicPalette.antiqueGold.copy(alpha = 0.75f) else Color.Transparent, 7.dp, 10.dp)
            .background(if (commanderReady) MagicPalette.antiqueGold.copy(alpha = 0.22f) else Color.Transparent, RoundedCornerShape(10.dp))
            .border(1.5.dp, if (commanderReady) Color.White.copy(alpha = 0.9f) else Color.Transparent, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center) {
            SfImage("square.grid.2x2", if (commanderReady) Color.White else MagicPalette.parchment, 14.dp)
        }
    }
}

/** Whose turn it is, colored so a glance answers it: gold for you, blue for opponents. */
private fun turnOwner(snapshot: GameSnapshot): Pair<String, Color> {
    val active = snapshot.activePlayerId ?: return "" to MagicPalette.antiqueGold
    return if (snapshot.isViewer(active)) "YOUR TURN" to MagicPalette.antiqueGold
    else "${snapshot.playerLabel(active).uppercase()}’S TURN" to BoardTurnColors.opponent
}

@Composable
fun PortraitOpponentStatusBar(snapshot: GameSnapshot, opponentName: String, opponent: PlayerGameState, humanId: String, combatTargetable: Boolean,
                              combatTargetAction: () -> Unit, openLog: () -> Unit, modifier: Modifier = Modifier,
                              viewZone: ((String, List<ZoneCard>) -> Unit)? = null, selectOpponent: ((String) -> Unit)? = null) {
    val hudPulse = LocalBoardHUDPulse.current
    val emoteCenter = LocalEmoteCenter.current
    var pulse by remember { mutableStateOf(false) }
    var lastPulse by remember { mutableIntStateOf(hudPulse) }
    LaunchedEffect(hudPulse) {
        if (hudPulse != lastPulse) { lastPulse = hudPulse; pulse = true; delay(450); pulse = false }
    }
    val (owner, turnColor) = turnOwner(snapshot)
    val animatedTurnColor by animateColorAsState(turnColor, tween(350), label = "turnColor")
    val pulseScale by animateFloatAsState(if (pulse) 1.06f else 1f, if (pulse) spring(0.55f, 630f) else tween(400), label = "pulse")
    val pulseAlpha by animateFloatAsState(if (pulse) 0.35f else 0f, if (pulse) spring(0.55f, 630f) else tween(400), label = "pulseAlpha")
    val largeText = BoardMotion.largeText
    val shape = RoundedCornerShape(11.dp)
    val cue = BoardResponseCue.make(snapshot)
    Box(modifier) {
        Row(Modifier.fillMaxSize()
            .glow(animatedTurnColor.copy(alpha = 0.35f), 8.dp, 11.dp)
            .background(Brush.linearGradient(listOf(MagicPalette.iron.copy(alpha = 0.88f), MagicPalette.leather.copy(alpha = 0.76f))), shape)
            .border(1.5.dp, animatedTurnColor.copy(alpha = 0.75f), shape)
            .padding(horizontal = 5.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            PressableBox({ if (combatTargetable) combatTargetAction() }, Modifier.padding(vertical = 3.dp)
                .border(2.dp, if (combatTargetable) Color.Red else Color.Transparent, RoundedCornerShape(8.dp))
                .semantics { contentDescription = if (opponent.isOut) "$opponentName, out of the game" else "$opponentName, ${opponent.life} life" }) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    PlayerPortrait(opponent, 40.dp, snapshot.activePlayerId == opponent.playerId, snapshot.thinkingPlayerID == opponent.playerId)
                    Column(Modifier.width(if (largeText) 96.dp else 70.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        FitText(opponentName, SfText.caption2(SfWeight.bold), color = MagicPalette.parchment, minimumScale = 0.7f)
                        if (opponent.isOut) Text("Out", color = Color.Gray, style = SfText.title3(SfWeight.bold))
                        else androidx.compose.runtime.key(opponent.playerId) { BoardLifeTotal(opponent.life, SfText.title3(SfWeight.bold), suffix = " life") }
                    }
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(Modifier.graphicsLayer { scaleX = pulseScale; scaleY = pulseScale; transformOrigin = TransformOrigin(0f, 0.5f) }
                    .background(animatedTurnColor.copy(alpha = pulseAlpha), CircleShape).padding(horizontal = 4.dp, vertical = 1.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(7.dp).glow(animatedTurnColor, 3.dp, 4.dp).background(animatedTurnColor, CircleShape))
                    // The phase drops first when a pod's extra controls leave less room.
                    PhaseFittingLabel(owner, animatedTurnColor, PhaseTitles.arenaPhaseTitle(snapshot.step ?: snapshot.phase))
                }
                val statusStyle = SfText.caption2(SfWeight.bold)
                val thinker = snapshot.thinkingPlayerID
                when {
                    cue == null && thinker != null -> ThinkingLabel(snapshot.playerLabel(thinker), BoardTurnColors.opponent, statusStyle)
                    cue == null && snapshot.isSpectating -> Text("You’re watching", color = MagicPalette.parchment, style = statusStyle)
                    else -> Text(cue?.title ?: if (snapshot.isViewer(snapshot.priorityPlayerId)) "Your priority" else "Waiting on ${snapshot.playerLabel(snapshot.priorityPlayerId)}",
                        color = if (cue == null) MagicPalette.parchment else MagicPalette.antiqueGold, style = statusStyle, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            if (selectOpponent != null) OpponentFocusMenu(snapshot, selectOpponent)
            BoardPlayerEffects(opponent, BattlefieldAttachments.enchanting(opponent.playerId, snapshot.players.flatMap { it.zones.battlefield }), viewZone)
            if (viewZone != null) PlayerZoneMenu(opponent, viewZone)
            PressableBox(openLog, Modifier.size(44.dp).semantics { contentDescription = "Game log" }) {
                SfImage("text.book.closed", MagicPalette.parchment, 17.dp)
            }
        }
        if (emoteCenter != null) {
            OpponentEmoteSlot(emoteCenter, snapshot, opponent.playerId, Modifier.align(Alignment.BottomStart).offset(x = 8.dp, y = 44.dp).wrapContentSize(unbounded = true).zIndex(5f))
        }
    }
}

/** ViewThatFits: owner and phase, then owner only, then a smaller owner. */
@Composable
private fun PhaseFittingLabel(owner: String, color: Color, phase: String) {
    androidx.compose.foundation.layout.BoxWithConstraints {
        val measurer = androidx.compose.ui.text.rememberTextMeasurer()
        val ownerStyle = SfText.caption(SfWeight.black)
        val phaseStyle = SfText.caption(SfWeight.bold)
        val available = constraints.maxWidth
        val full = measurer.measure(owner, ownerStyle).size.width + measurer.measure("· $phase", phaseStyle).size.width + with(androidx.compose.ui.platform.LocalDensity.current) { 5.dp.roundToPx() }
        when {
            full <= available -> Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(owner, color = color, style = ownerStyle, maxLines = 1)
                Text("· $phase", color = MagicPalette.parchment, style = phaseStyle, maxLines = 1)
            }
            measurer.measure(owner, ownerStyle).size.width <= available -> Text(owner, color = color, style = ownerStyle, maxLines = 1)
            else -> FitText(owner, SfText.caption2(SfWeight.black), color = color, minimumScale = 0.6f)
        }
    }
}

@Composable
fun ManaPoolHUD(manaPool: ManaPool?, modifier: Modifier = Modifier, vertical: Boolean = false, compact: Boolean = false, grid: Boolean = false,
                payableSymbols: Set<String> = emptySet(), payMana: ((String) -> Unit)? = null) {
    val values = listOf("W" to (manaPool?.W ?: 0), "U" to (manaPool?.U ?: 0), "B" to (manaPool?.B ?: 0), "R" to (manaPool?.R ?: 0),
        "G" to (manaPool?.G ?: 0), "C" to (manaPool?.C ?: 0))
    val shape = RoundedCornerShape(if (vertical) 12.dp else 16.dp)
    @Composable
    fun manaValue(symbol: String, count: Int) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            ManaSymbolView(symbol, if (compact) 13.dp else 18.dp)
            Text("$count", Modifier.widthIn(min = 8.dp), color = Color.White, style = sf(11f, SfWeight.black))
        }
    }
    @Composable
    fun content() {
        for ((symbol, count) in values) {
            if (symbol in payableSymbols && !grid && payMana != null) {
                PressableBox({ payMana(symbol) }, Modifier.defaultMinSize(44.dp, 44.dp).glow(MagicPalette.antiqueGold.copy(alpha = 0.65f), 5.dp, 9.dp)
                    .background(MagicPalette.antiqueGold.copy(alpha = 0.2f), RoundedCornerShape(9.dp))
                    .border(1.5.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(9.dp))
                    .semantics { contentDescription = "Spend floating $symbol mana, $count available" }) { manaValue(symbol, count) }
            } else {
                Box(Modifier.glow(if (symbol in payableSymbols) MagicPalette.antiqueGold else Color.Transparent, 4.dp, 4.dp)
                    .background(if (symbol in payableSymbols) MagicPalette.antiqueGold.copy(alpha = 0.3f) else Color.Transparent, RoundedCornerShape(4.dp))
                    .alpha(if (count > 0) 1f else 0.45f)) { manaValue(symbol, count) }
            }
        }
    }
    val base = modifier.glow(Color.Black.copy(alpha = 0.30f), 10.dp, if (vertical) 12.dp else 16.dp)
        .background(MagicPalette.iron.copy(alpha = 0.76f), shape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.38f), shape)
    when {
        grid -> Column(base.padding(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            values.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) { row.forEach { (s, c) -> manaValue(s, c) } }
            }
        }
        vertical -> Column(base.padding(horizontal = 5.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) { content() }
        else -> Row(base.padding(horizontal = if (compact) 4.dp else 9.dp, vertical = if (payableSymbols.isEmpty()) 6.dp else 4.dp),
            horizontalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 5.dp), verticalAlignment = Alignment.CenterVertically) { content() }
    }
}

@Composable
fun FloatingZoneChip(title: String, count: Int, icon: String, action: () -> Unit) {
    PressableBox(action, Modifier.glow(Color.Black.copy(alpha = 0.4f), 4.dp, 20.dp)) {
        Row(Modifier.background(MagicPalette.iron.copy(alpha = 0.95f), CircleShape).border(1.5.dp, MagicPalette.antiqueGold.copy(alpha = 0.5f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage(icon, Color.White, 10.dp)
            Text("$title ($count)", color = Color.White, style = sf(10f, SfWeight.black))
        }
    }
}

object BoardStackTrayModel {
    data class Group(val `object`: XmageStackObject, val count: Int)

    /** Groups consecutive objects (top first) with the same name, source and rules text. */
    fun groups(objects: List<XmageStackObject>): List<Group> {
        val result = mutableListOf<Group>()
        for (item in objects) {
            val last = result.lastOrNull()
            if (last != null && key(last.`object`) == key(item)) result[result.size - 1] = last.copy(count = last.count + 1)
            else result += Group(item, 1)
        }
        return result
    }

    private fun key(item: XmageStackObject): String = listOf(item.displayName, item.sourceName ?: "", item.rulesText ?: "").joinToString("\u001F")
    fun title(group: Group): String = if (group.count > 1) "${group.`object`.displayName} ×${group.count}" else group.`object`.displayName
}

@Composable
fun BoardStackTray(objects: List<XmageStackObject>, count: Int?, open: () -> Unit) {
    val groups = BoardStackTrayModel.groups(objects)
    val total = maxOf(count ?: 0, objects.size)
    val top = groups.firstOrNull()
    PressableBox(open, Modifier.semantics {
        contentDescription = "Inspect stack. " + (top?.let { "$total ${if (total == 1) "item" else "items"}. Top: ${BoardStackTrayModel.title(it)}" } ?: "Empty")
    }) {
        androidx.compose.animation.AnimatedContent(top != null, label = "stackTray") { hasTop ->
            if (hasTop && top != null) {
                Row(Modifier.heightIn(min = 44.dp).glow(MagicPalette.antiqueGold.copy(alpha = 0.35f), 6.dp, 12.dp)
                    .background(MagicPalette.iron.copy(alpha = 0.92f), RoundedCornerShape(12.dp))
                    .border(1.5.dp, MagicPalette.antiqueGold.copy(alpha = 0.7f), RoundedCornerShape(12.dp)).padding(horizontal = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    val shown = groups.take(3)
                    Box(Modifier.width((24 + maxOf(shown.size - 1, 0) * 7).dp).height(32.dp)) {
                        shown.withIndex().reversed().forEach { (index, group) ->
                            Box(Modifier.offset(x = (index * 7).dp).rotate(index * 6f)) { StackThumbnail(group.`object`) }
                        }
                    }
                    Column(Modifier.widthIn(max = 118.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text("STACK · $total", color = MagicPalette.antiqueGold, style = sf(8f, SfWeight.black, tracking = 0.6f))
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            // The name may truncate; the trigger count never does.
                            Text(top.`object`.displayName, Modifier.weight(1f, fill = false), color = Color.White, style = sf(11f, SfWeight.bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (top.count > 1) Text("×${top.count}", color = MagicPalette.antiqueGold, style = sf(11f, SfWeight.bold), maxLines = 1)
                        }
                    }
                }
            } else {
                Row(Modifier.defaultMinSize(44.dp, 44.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    val color = MagicPalette.parchment.copy(alpha = if (total > 0) 0.9f else 0.5f)
                    SfImage("square.stack.3d.up", color, 15.dp)
                    Text("$total", color = color, style = sf(15f, SfWeight.semibold).copy(fontFeatureSettings = "tnum"))
                }
            }
        }
    }
}

@Composable
private fun StackThumbnail(item: XmageStackObject) {
    val card = item.displaySourceCard
    if (card != null) CardTile(card, false, zoneName = "Stack", width = 23.dp, height = 32.dp, ignoreTappedRotation = true)
    else SyntheticStackObjectTile(item, 23.dp, 32.dp)
}

@Composable
fun SyntheticStackObjectTile(item: XmageStackObject?, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(6.dp)
    Box(modifier.requiredSize(width, height).background(Brush.linearGradient(listOf(MagicPalette.leather.copy(alpha = 0.78f), MagicPalette.iron.copy(alpha = 0.82f))), shape)
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.55f), shape)) {
        Column(Modifier.fillMaxSize().padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally) {
            FitText((item?.syntheticTileSubtitle ?: "STACK").uppercase(), sf(6f, SfWeight.black), color = MagicPalette.antiqueGold, minimumScale = 0.55f)
            SfImage("sparkles", MagicPalette.antiqueGold, 13.dp)
            FitText(item?.syntheticTileTitle ?: "Ability", sf(7.5f, SfWeight.black), color = Color.White.copy(alpha = 0.88f), maxLines = 2, minimumScale = 0.5f,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            FitText(item?.syntheticTileDetail ?: "Source card image unavailable", sf(5.8f, SfWeight.bold), color = MagicPalette.parchment.copy(alpha = 0.7f),
                maxLines = 2, minimumScale = 0.48f, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
        Text("STACK", Modifier.align(Alignment.BottomEnd).padding(3.dp).background(MagicPalette.antiqueGold.copy(alpha = 0.88f), CircleShape)
            .padding(horizontal = 3.dp, vertical = 1.dp), color = Color.Black.copy(alpha = 0.72f), style = sf(5.5f, SfWeight.black))
    }
}

@Composable
fun BoardResponseBanner(cue: BoardResponseCue, modifier: Modifier = Modifier) {
    Column(modifier.background(MagicPalette.iron.copy(alpha = 0.94f), RoundedCornerShape(9.dp))
        .border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.8f), RoundedCornerShape(9.dp)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("bolt.circle.fill", MagicPalette.parchment, 12.dp)
            Text(cue.title, color = MagicPalette.parchment, style = SfText.caption(SfWeight.bold))
        }
        Text(cue.detail, color = MagicPalette.parchment, style = SfText.caption2())
    }
}
