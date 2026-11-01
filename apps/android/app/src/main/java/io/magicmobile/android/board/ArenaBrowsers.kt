package io.magicmobile.android.board

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import io.magicmobile.android.R
import io.magicmobile.android.game.ArenaGameResult
import io.magicmobile.android.game.ArenaLoyalty
import io.magicmobile.android.game.ArenaScreens
import io.magicmobile.android.game.ArenaSplit
import io.magicmobile.android.game.ArenaTableRules
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.ChoicePromptOption
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameStats
import io.magicmobile.android.game.GameBoardInteractionState
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.LegalActionDisplay
import io.magicmobile.android.game.PromptCommandBuilder
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.game.PromptEnvelopeV2
import io.magicmobile.android.game.RankChange
import io.magicmobile.android.game.StackTargetPresentation
import io.magicmobile.android.game.XmagePromptAbility
import io.magicmobile.android.game.XmagePromptMultiAmount
import io.magicmobile.android.game.XmagePromptPile
import io.magicmobile.android.game.XmageStackObject
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.LocalArenaSafeArea
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.menus.arenaShadow
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.TavernTextField
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min

/*
 * Port of Board/ArenaBoardViews.swift's full-table screens (phase D): ArenaBrowserFrame and ArenaAnswerRow, the ability,
 * stack, mode, zone, choice, player, split and pile browsers, the question stage and ArenaGameResultView. Their rules (which
 * screen takes a question, its title and lines, the trigger order) are core's ArenaScreens; every answer is the Hearth panel's
 * command. Each layer dims the whole table and keeps its content inside LocalArenaSafeArea (docs/ARENA_STYLE.md, "Browser anatomy").
 */

/** One of XMage's own answers beside a screen's (Cancel, Done). */
data class ArenaAnswer(val id: String, val title: String, val action: () -> Unit)

/** A browser's main answer: the orange plaque, with an optional count under its word ("2 OF 3"). */
data class ArenaPrimaryAnswer(val title: String, val subtitle: String? = null, val enabled: Boolean = true, val action: () -> Unit)

private val arenaPickGold = rgb(1.0, 0.82, 0.4)
private val arenaLabelGold = rgb(0.98, 0.84, 0.52)

/**
 * Measures the phone's safe area for the Arena layers drawn outside the board itself (card choices, the opening hand, the
 * result, the starting roll): an inset box's place in its parent, never the window read in a layer (LESSONS 2026-10-22).
 */
@Composable
fun MeasureArenaSafeArea(onChange: (io.magicmobile.android.menus.ArenaSafeArea) -> Unit) {
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    val report by rememberUpdatedState(onChange)
    Box(Modifier.fillMaxSize().windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.safeDrawing).clearAndSetSemantics { }
        .onGloballyPositioned { coordinates ->
            val parent = coordinates.parentLayoutCoordinates?.size ?: return@onGloballyPositioned
            val position = coordinates.positionInParent()
            report(io.magicmobile.android.menus.ArenaSafeArea(top = (position.y / density).dp,
                bottom = ((parent.height - position.y - coordinates.size.height) / density).coerceAtLeast(0f).dp,
                leading = (position.x / density).dp, trailing = ((parent.width - position.x - coordinates.size.width) / density).coerceAtLeast(0f).dp))
        })
}

/** A tap and a hold on the same card: the hold reads it. */
internal fun Modifier.arenaTapHold(onTap: () -> Unit, onHold: (() -> Unit)? = null): Modifier = composed {
    val tap by rememberUpdatedState(onTap)
    val hold by rememberUpdatedState(onHold)
    pointerInput(Unit) { detectTapGestures(onTap = { tap() }, onLongPress = { hold?.invoke() }) }
}

/** The table dimmed under a full-table layer; it takes taps (or closes) unless the layer is stepped aside. */
@Composable
internal fun ArenaDim(peeking: Boolean = false, alpha: Float = 0.8f, onTap: (() -> Unit)? = null) {
    val shade by animateFloatAsState(if (peeking) 0f else alpha, tween(if (BoardMotion.reduceMotion) 0 else 200), label = "arenaDim")
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = shade)).clearAndSetSemantics { }
        .then(if (peeking) Modifier else Modifier.clickable(remember { MutableInteractionSource() }, null) { onTap?.invoke() }))
}

/** A row of cards that scrolls sideways once it is wider than `minWidth`, and sits centred while it isn't. */
@Composable
internal fun ArenaCenteredRow(minWidth: Dp, modifier: Modifier = Modifier, spacing: Dp = 16.dp, horizontal: Dp = 24.dp, vertical: Dp = 18.dp,
                              alignment: Alignment.Vertical = Alignment.Top, content: @Composable () -> Unit) {
    Row(modifier.horizontalScroll(rememberScrollState()).widthIn(min = minWidth).padding(horizontal = horizontal, vertical = vertical),
        horizontalArrangement = Arrangement.spacedBy(spacing, Alignment.CenterHorizontally), verticalAlignment = alignment) { content() }
}

/** "View Battlefield", top right: clear of the gear in landscape (120 left of it), padded before it is placed. */
@Composable
internal fun BoxScope.ArenaViewBattlefield(peeking: Boolean, toggle: () -> Unit, landscape: Boolean, identifier: String,
                                           back: String = "Back to the choice") {
    val safe = LocalArenaSafeArea.current
    Box(Modifier.align(Alignment.TopEnd).padding(top = if (landscape) 4.dp else safe.top(50.dp) - 6.dp, end = if (landscape) 120.dp else 16.dp)
        .heightIn(min = 44.dp).clickable(onClick = toggle).semantics { testTag = identifier }, contentAlignment = Alignment.Center) {
        Box(Modifier.height(32.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape).border(1.dp, ArenaGlass.hairline, CircleShape)
            .padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
            Text(if (peeking) back else "View Battlefield", color = ArenaGlass.text, style = ArenaMenuStyle.font(12f, SfWeight.bold), maxLines = 1)
        }
    }
}

/** The spell or ability asking, as the reference shows it beside its browsers. */
@Composable
internal fun ArenaSourceView(source: XmageStackObject?, sourceCard: ZoneCard?, inspect: (ZoneCard) -> Unit, size: DpSize = DpSize(124.dp, 172.dp)) {
    val card = source?.displaySourceCard ?: sourceCard
    val ability = source != null && (ArenaTableRules.isAbility(source) || source.displaySourceCard == null)
    Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp).clickable(enabled = card != null) { card?.let(inspect) }
        .semantics { contentDescription = "Source: ${source?.displayName ?: card?.card?.name ?: ""}" }) {
        if (ability) ArenaAbilityCard(source!!.displaySourceCard, name = if (source.displaySourceCard == null) source.displayName else null,
            text = source.rulesText ?: source.displayName, size = size)
        else if (card != null) CardTile(card, false, zoneName = "Stack", width = size.width, height = size.height, ignoreTappedRotation = true)
    }
}

/** A serif title over the dimmed table. */
@Composable
internal fun ArenaScreenTitle(text: String, size: Float, modifier: Modifier = Modifier, maxLines: Int = 2) {
    FitText(text, ArenaMenuStyle.title(size, SfWeight.bold).arenaShadow(), modifier.semantics { heading() }, color = ArenaGlass.text,
        maxLines = maxLines, minimumScale = 0.8f, textAlign = TextAlign.Center)
}

@Composable
internal fun ArenaScreenLine(text: String, modifier: Modifier = Modifier, size: Float = 13f) {
    Text(text, modifier, color = ArenaGlass.text.copy(alpha = 0.8f), style = ArenaMenuStyle.font(size, SfWeight.medium), textAlign = TextAlign.Center, maxLines = 2)
}

/**
 * The frame every Arena browser shares: the table dims, a title and one line sit at the top (below the cutout, and in
 * landscape below the opponent's medallion), the content in the middle, answers at the bottom, the source card on the right
 * in landscape and "View Battlefield" top right, which steps the browser aside.
 */
@Composable
fun ArenaBrowserFrame(title: String, modifier: Modifier = Modifier, detail: String? = null, source: XmageStackObject? = null,
                      sourceCard: ZoneCard? = null, identifier: String = "arena.browser", inspect: (ZoneCard) -> Unit = {},
                      footer: @Composable () -> Unit, content: @Composable BoxScope.(landscape: Boolean, screen: BoardSize) -> Unit) {
    var peeking by remember { mutableStateOf(false) }
    val safe = LocalArenaSafeArea.current
    BoxWithConstraints(modifier.fillMaxSize().semantics { testTag = identifier }) {
        val landscape = maxWidth > maxHeight
        val screen = BoardSize(maxWidth.value, maxHeight.value)
        val showsSource = landscape && (source != null || sourceCard != null)
        val side = if (landscape) safe.side else 0.dp
        val screenWidth = maxWidth
        ArenaDim(peeking)
        if (!peeking) {
            Column(Modifier.fillMaxSize().padding(top = safe.top(if (landscape) 50.dp else 96.dp), start = side,
                end = side + if (showsSource) 150.dp else 0.dp, bottom = maxOf(if (landscape) 10.dp else 28.dp, safe.bottom)),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (landscape) 8.dp else 12.dp)) {
                Column(Modifier.padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ArenaScreenTitle(title, if (landscape) 22f else 24f, Modifier.semantics { testTag = "$identifier.title" })
                    if (!detail.isNullOrEmpty()) ArenaScreenLine(detail)
                }
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { content(landscape, screen) }
                footer()
            }
            if (showsSource) Box(Modifier.align(Alignment.CenterEnd).padding(end = 14.dp + side)) { ArenaSourceView(source, sourceCard, inspect) }
        }
        ArenaViewBattlefield(peeking, { peeking = !peeking }, landscape, "$identifier.viewBattlefield")
    }
}

/** Plaques under a browser: XMage's own answers beside the browser's main one. */
@Composable
fun ArenaAnswerRow(answers: List<ArenaAnswer> = emptyList(), primary: ArenaPrimaryAnswer? = null, pending: Boolean = false, modifier: Modifier = Modifier) {
    Row(modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        for (answer in answers) ArenaPlaqueButton(answer.title, answer.action, Modifier.size(140.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY,
            fontSize = 15f, enabled = !pending)
        primary?.let { ArenaPlaqueButton(it.title, it.action, Modifier.size(170.dp, 46.dp), it.subtitle, fontSize = 16f, enabled = it.enabled && !pending,
            identifier = "arena.browser.primary") }
        if (pending) CircularProgressIndicator(Modifier.size(18.dp), color = ArenaGlass.text, strokeWidth = 2.dp)
    }
}

// MARK: - Abilities

/**
 * The Arena board's ability browser: the abilities as Arena ability cards in a row over the dimmed table. Ordering triggers,
 * you tap them in the order they should resolve (1 resolves first) and press Done; choosing an ability, a tap picks it. A hold
 * reads the source card.
 */
@Composable
fun ArenaAbilityBrowser(prompt: PromptEnvelopeV2, abilities: List<XmagePromptAbility>, ordering: Boolean, pending: Boolean, canRemember: Boolean,
                        cancel: ArenaAnswer?, choose: (XmagePromptAbility) -> Unit, order: (List<XmagePromptAbility>, Boolean) -> Unit,
                        inspect: (ZoneCard) -> Unit) {
    var picked by remember { mutableStateOf(listOf<String>()) }
    var rememberPick by remember { mutableStateOf(false) }
    val view = LocalView.current
    val safe = LocalArenaSafeArea.current
    BoxWithConstraints(Modifier.fillMaxSize().semantics { testTag = "arena.abilityBrowser" }) {
        val landscape = maxWidth > maxHeight
        val height = min(if (landscape) maxHeight.value * 0.5f else 230f, 250f)
        val size = DpSize((height * 0.72f).dp, height.dp)
        val side = if (landscape) safe.side else 0.dp
        val screenWidth = maxWidth
        ArenaDim()
        Column(Modifier.fillMaxSize().padding(top = safe.top(if (landscape) 50.dp else 56.dp), start = side, end = side,
            bottom = maxOf(10.dp, safe.bottom)).alpha(if (pending) 0.7f else 1f),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) {
            ArenaScreenTitle(if (ordering) "Order your triggers" else "Choose an ability", 22f)
            ArenaScreenLine(if (ordering) "Tap them in the order they resolve: 1 resolves first." else PromptDisplayText.clean(prompt.message),
                Modifier.padding(horizontal = 24.dp), 14f)
            ArenaCenteredRow(screenWidth - side * 2) {
                for (ability in abilities) {
                    val number = picked.indexOf(ability.id).takeIf { it >= 0 }?.plus(1)
                    val loyalty = ArenaLoyalty.split(ability.rulesText ?: ability.label)
                    val scale by animateFloatAsState(if (number != null) 1.04f else 1f, spring(0.75f, 500f), label = "abilityPick")
                    Box(Modifier.graphicsLayer { scaleX = scale; scaleY = scale }.glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp)
                        .arenaTapHold({
                            if (!pending) {
                                if (!ordering) choose(ability)
                                else { picked = if (ability.id in picked) picked - ability.id else picked + ability.id; GameHaptics.selection(view) }
                            }
                        }, { ability.sourceCard?.let(inspect) })
                        .semantics {
                            contentDescription = "${ability.sourceName ?: ability.sourceCard?.card?.name ?: "Ability"}: ${PromptDisplayText.clean(ability.rulesText ?: ability.label)}"
                            number?.let { stateDescription = "Resolves $it" }
                            testTag = "arena.ability.${ability.id}"
                        }) {
                        ArenaAbilityCard(ability.sourceCard, name = ability.sourceName, text = loyalty?.second ?: ability.rulesText ?: ability.label,
                            size = size, loyalty = loyalty?.first)
                        if (number != null) {
                            Box(Modifier.matchParentSize().glow(rgb(1.0, 0.75, 0.3).copy(alpha = 0.6f), 8.dp, 10.dp).border(3.dp, arenaPickGold, ArenaAbilityShape))
                            ArenaCountBadge(number, Modifier.align(Alignment.TopCenter).offset(y = (-17).dp), size = 34.dp)
                        }
                    }
                }
            }
            if (ordering && canRemember) RememberChoiceToggle("Always put my last-resolving pick first", rememberPick, { rememberPick = it })
            if (!ordering && cancel != null) ArenaPlaqueButton(cancel.title, cancel.action, Modifier.size(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY,
                fontSize = 16f, enabled = !pending, identifier = "arena.abilities.cancel")
            if (ordering) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ArenaPlaqueButton("Auto Order", { order(abilities, false) }, Modifier.size(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY,
                    fontSize = 16f, enabled = !pending, identifier = "arena.triggers.auto")
                val ready = picked.size >= abilities.size - 1
                ArenaPlaqueButton(if (ready) "Done" else "${picked.size} of ${abilities.size}", {
                    val chosen = picked.mapNotNull { id -> abilities.firstOrNull { it.id == id } }
                    order(chosen + abilities.filter { it.id !in picked }, rememberPick)
                }, Modifier.size(150.dp, 44.dp), fontSize = 16f, enabled = ready && !pending, identifier = "arena.triggers.done")
            }
        }
    }
}

// MARK: - The stack

/**
 * The whole stack the Arena way: its cards side by side over the dimmed table, the one that resolves next first. Spells show
 * as their card, abilities as ability cards; whose each is and what it targets sits underneath. A tap reads a card.
 */
@Composable
fun ArenaStackBrowser(snapshot: GameSnapshot, resolveAll: (() -> Unit)?, stopSkipping: (() -> Unit)?, inspect: (ZoneCard) -> Unit,
                      choosable: Set<String> = emptySet(), choose: ((String) -> Unit)? = null, answers: List<ArenaAnswer> = emptyList(),
                      close: () -> Unit) {
    val objects = snapshot.stackTopFirst
    // A target question's choices on the stack (ArenaTargetReach; Gogo copying Zur's trigger): its message is the title,
    // the choices glow, the rest dim, and a tap chooses.
    val choosing = choose != null && choosable.isNotEmpty()
    val safe = LocalArenaSafeArea.current
    BoxWithConstraints(Modifier.fillMaxSize().semantics { testTag = "arena.stackBrowser" }) {
        val landscape = maxWidth > maxHeight
        val size = if (landscape) { val h = min(maxHeight.value * 0.5f, 230f); DpSize((h * 0.72f).dp, h.dp) }
            else { val w = min((maxWidth.value - 48f - 18f) / 2f, 180f); DpSize(w.dp, (w / 0.72f).dp) }
        val side = if (landscape) safe.side else 0.dp
        val screenWidth = maxWidth
        ArenaDim(onTap = close)
        Column(Modifier.fillMaxSize().padding(top = safe.top(if (landscape) 50.dp else 56.dp), start = side, end = side,
            bottom = maxOf(if (landscape) 10.dp else 28.dp, safe.bottom)),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (landscape) 8.dp else 12.dp)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    // Choosing, the question is the title and each card wears its place.
                    if (choosing) ArenaScreenTitle(PromptDisplayText.clean(snapshot.promptEnvelopeV2?.message ?: "Choose one"), 19f, maxLines = 2,
                        modifier = Modifier.padding(horizontal = 24.dp))
                    else {
                        ArenaScreenTitle("The Stack", 22f, maxLines = 1)
                        val count = snapshot.xmage?.stack?.size ?: objects.size
                        ArenaCountBadge(count, Modifier.semantics { contentDescription = "$count on the stack" }, size = 28.dp)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (objects.size > 1) "Resolves left to right" else "Resolves next", color = ArenaGlass.text.copy(alpha = 0.75f),
                        style = ArenaMenuStyle.font(13f, SfWeight.medium))
                    val responding = ArenaScreens.stackResponding(snapshot)
                    TavernTag(if (choosing) "CHOOSE ONE" else if (responding) "YOUR RESPONSE" else "WAITING", leather = true,
                        accent = if (choosing || responding) TavernPalette.ember else null)
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (landscape) ArenaCenteredRow(screenWidth - side * 2, spacing = 18.dp, horizontal = 28.dp, vertical = 20.dp) {
                    objects.forEachIndexed { index, item -> ArenaStackEntry(item, index, size, snapshot, inspect, choosing, item.id in choosable, choose) }
                } else Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(26.dp)) {
                    objects.withIndex().chunked(2).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.Top) {
                            row.forEach { (index, item) -> ArenaStackEntry(item, index, size, snapshot, inspect, choosing, item.id in choosable, choose) }
                            if (row.size == 1 && objects.size > 1) Spacer(Modifier.width(size.width))
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                stopSkipping?.let { ArenaPlaqueButton("Stop skipping", it, Modifier.size(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY, fontSize = 15f) }
                resolveAll?.takeUnless { choosing }?.let { ArenaPlaqueButton("Resolve All", it, Modifier.size(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY, fontSize = 16f,
                    identifier = "board.stack.sheet.resolveAll") }
                if (choosing) answers.forEach { ArenaPlaqueButton(it.title, it.action, Modifier.size(150.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY, fontSize = 16f) }
                ArenaPlaqueButton(if (choosing) "View Battlefield" else "Done", close, Modifier.size(150.dp, 44.dp), fontSize = if (choosing) 15f else 16f,
                    kind = if (choosing) ArenaPlaqueKind.SECONDARY else ArenaPlaqueKind.PRIMARY, identifier = "board.stack.done")
            }
        }
    }
}

@Composable
private fun ArenaStackEntry(item: XmageStackObject, position: Int, size: DpSize, snapshot: GameSnapshot, inspect: (ZoneCard) -> Unit,
                            choosing: Boolean = false, choice: Boolean = false, choose: ((String) -> Unit)? = null) {
    val next = position == 0
    val ability = ArenaTableRules.isAbility(item) || item.displaySourceCard == null
    val owner = ArenaScreens.stackOwner(item, snapshot)
    val view = LocalView.current
    Column(Modifier.width(size.width).semantics(mergeDescendants = true) {
        contentDescription = "${position + 1}. ${item.displayName}, $owner. ${PromptDisplayText.clean(item.rulesText ?: "")}"
        testTag = "arena.stack.${item.id}"
        if (choice) selected = true
    }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        // The glow (a choice's, the next one's) sits behind the card; only its border goes on top, or the glow tints the card.
        Box(Modifier.alpha(if (choosing && !choice) 0.5f else 1f)
            .glow(if (choice) ArenaPalette.targetGlow.copy(alpha = 0.75f) else if (next && !choosing) rgb(1.0, 0.75, 0.3).copy(alpha = 0.6f)
                else Color.Black.copy(alpha = 0.6f), if (choice) 12.dp else 8.dp, 8.dp)
            .pointerInput(item.id, choice) {
                detectTapGestures(onLongPress = { item.displaySourceCard?.let(inspect) }) {
                    if (choice && choose != null) { GameHaptics.selection(view); choose(item.id) } else item.displaySourceCard?.let(inspect)
                }
            }) {
            if (ability) ArenaAbilityCard(item.displaySourceCard, name = if (item.displaySourceCard == null) item.displayName else null,
                text = item.rulesText ?: item.displayName, size = size)
            else item.displaySourceCard?.let { CardTile(it, false, zoneName = "Stack", width = size.width, height = size.height, ignoreTappedRotation = true) }
            if (choice) Box(Modifier.matchParentSize().border(3.dp, ArenaPalette.targetGlow, RoundedCornerShape(size.width * 0.05f)))
            else if (next && !choosing) Box(Modifier.matchParentSize().border(3.dp, arenaPickGold, RoundedCornerShape(size.width * 0.05f)))
            ArenaCountBadge(position + 1, Modifier.align(Alignment.TopCenter).offset(y = (-15).dp), size = 30.dp)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(if (next) "RESOLVES NEXT" else owner.uppercase(), ArenaMenuStyle.font(10f, SfWeight.heavy).copy(letterSpacing = 0.08.em),
                color = if (next) rgb(0.98, 0.72, 0.4) else ArenaGlass.text.copy(alpha = 0.65f), minimumScale = 0.75f)
            if (next) FitText(owner, ArenaMenuStyle.font(11f, SfWeight.regular).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic),
                color = ArenaGlass.text.copy(alpha = 0.75f), minimumScale = 0.75f)
            val targets = item.targetIds
            if (!targets.isNullOrEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("scope", ArenaGlass.text, 11.dp)
                FitText(StackTargetPresentation.labels(targets, snapshot).joinToString(", "), ArenaMenuStyle.font(11f, SfWeight.semibold),
                    color = ArenaGlass.text, minimumScale = 0.75f)
            }
        }
    }
}

// MARK: - The question stage

/**
 * A question the Arena way (the reference's "Pay 2 life?"): the table dims, the question is the title (never cut off, never
 * said twice), the card it's about stands in the middle (an ability as its ability card), and the answers sit under it as
 * Arena's pills. "View Battlefield" steps it aside.
 */
@Composable
fun ArenaQuestionStage(title: String, stackObject: XmageStackObject?, card: ZoneCard?, inspect: (ZoneCard) -> Unit, answers: @Composable () -> Unit) {
    var peeking by remember { mutableStateOf(false) }
    val safe = LocalArenaSafeArea.current
    val headline = remember(title, stackObject?.id, card?.id) { ArenaScreens.headline(title, stackObject, card) }
    val art = stackObject?.displaySourceCard ?: card
    val named = stackObject?.displaySourceName ?: card?.card?.name
    BoxWithConstraints(Modifier.fillMaxSize().semantics { testTag = "arena.question" }) {
        val landscape = maxWidth > maxHeight
        val height = if (landscape) min(maxHeight.value * 0.48f, 220f) else min(maxHeight.value * 0.36f, 330f)
        val size = DpSize((height * 0.72f).dp, height.dp)
        val side = if (landscape) safe.side else 0.dp
        val screenWidth = maxWidth
        ArenaDim(peeking)
        if (!peeking) Column(Modifier.fillMaxSize().padding(top = safe.top(if (landscape) 50.dp else 40.dp), start = side, end = side,
            bottom = maxOf(10.dp, safe.bottom)),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (landscape) 10.dp else 18.dp, Alignment.CenterVertically)) {
            Column(Modifier.widthIn(max = 600.dp).padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                GameRulesText(headline.title, Modifier.semantics { testTag = "arena.question.title"; heading() }, cardName = named, symbolSize = 18.dp,
                    style = ArenaMenuStyle.title(if (landscape) 20f else 22f, SfWeight.bold).arenaShadow().copy(textAlign = TextAlign.Center), color = ArenaGlass.text)
                headline.detail?.let {
                    GameRulesText(it, Modifier.semantics { testTag = "arena.question.detail" }, cardName = named, symbolSize = 13.dp,
                        style = ArenaMenuStyle.font(13f, SfWeight.medium).copy(textAlign = TextAlign.Center), color = ArenaGlass.text.copy(alpha = 0.8f), maxLines = 3)
                }
            }
            Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 10.dp, 10.dp).clickable(enabled = art != null) { art?.let(inspect) }) {
                if (stackObject != null && (ArenaTableRules.isAbility(stackObject) || stackObject.displaySourceCard == null)) {
                    // Its permanent's art from the table when XMage sent no card.
                    ArenaAbilityCard(art, name = if (art == null) stackObject.displayName else null, text = stackObject.rulesText ?: stackObject.displayName, size = size)
                } else if (art != null) CardTile(art, false, zoneName = "Question", width = size.width, height = size.height, ignoreTappedRotation = true)
            }
            answers()
        }
        ArenaViewBattlefield(peeking, { peeking = !peeking }, landscape, "arena.question.viewBattlefield", "Back to the question")
    }
}

// MARK: - Modes

/** A modal spell's modes the Arena way: each mode a card with the spell's art over its text; a tap chooses it. */
@Composable
fun ArenaModeBrowser(title: String, detail: String, source: ZoneCard?, modes: List<ChoicePromptOption>, pending: Boolean, answers: List<ArenaAnswer>,
                     choose: (ChoicePromptOption) -> Unit, inspect: (ZoneCard) -> Unit) {
    val view = LocalView.current
    val safe = LocalArenaSafeArea.current
    BoxWithConstraints(Modifier.fillMaxSize().semantics { testTag = "arena.modeBrowser" }) {
        val landscape = maxWidth > maxHeight
        val columns = ArenaScreens.modeColumns(modes.size, landscape)
        val size = if (landscape) { val h = min(maxHeight.value * 0.52f, 250f); DpSize((h * 0.72f).dp, h.dp) }
            else { val w = min(180f, (maxWidth.value - 48f - 16f * (columns - 1)) / columns); DpSize(w.dp, (w / 0.72f).dp) }
        val side = if (landscape) safe.side else 0.dp
        val screenWidth = maxWidth
        ArenaDim()
        Column(Modifier.fillMaxSize().padding(top = safe.top(if (landscape) 50.dp else 96.dp), start = side, end = side,
            bottom = maxOf(if (landscape) 10.dp else 28.dp, safe.bottom)).alpha(if (pending) 0.7f else 1f),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ArenaScreenTitle(title, 22f, maxLines = 1)
            if (!detail.equals(title, ignoreCase = true)) ArenaScreenLine(detail, Modifier.padding(horizontal = 24.dp), 14f)
            @Composable
            fun card(index: Int, mode: ChoicePromptOption) {
                // The card names its mode once: in the type line under the source's art, or as its name with no source card.
                Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp)
                    .arenaTapHold({ if (!pending) { GameHaptics.selection(view); choose(mode) } }, { source?.let(inspect) })
                    .semantics { contentDescription = PromptDisplayText.clean(mode.label); testTag = "arena.mode.${mode.id}" }) {
                    ArenaAbilityCard(source, name = if (source == null) "Mode ${index + 1}" else null, kind = if (source == null) "Mode" else "Mode ${index + 1}",
                        text = ArenaScreens.modeText(mode.label), size = size)
                }
            }
            Box(Modifier.weight(1f, fill = !landscape).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (landscape) ArenaCenteredRow(screenWidth - side * 2) { modes.forEachIndexed { index, mode -> card(index, mode) } }
                // Upright the cards scroll in the room left, so the title stays on screen.
                else Column(Modifier.arenaScrollFade(20.dp, 20.dp).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    modes.withIndex().chunked(columns).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) { row.forEach { (index, mode) -> card(index, mode) } }
                    }
                }
            }
            if (answers.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (answer in answers) ArenaPlaqueButton(answer.title, answer.action, Modifier.size(150.dp, 44.dp), fontSize = 16f, enabled = !pending)
            }
        }
    }
}

// MARK: - Zones

/**
 * A zone opened from the table, the Arena way: graveyard, exile, the command zone, revealed or looked-at cards side by side on
 * the dimmed table, an ember plaque under each card you can use (Cast, or the action's own name), Done to close. Hold a card to
 * read it. Sends the same actions as the Hearth board's zone panel.
 */
@Composable
fun ArenaZoneBrowser(title: String, cards: List<ZoneCard>, legalActions: List<LegalAction>, pendingActionId: String?, targetableIDs: Set<String>,
                     runTargetAction: ((ZoneCard) -> Unit)?, selection: BoardSelection, runAction: (LegalAction) -> Unit, close: () -> Unit) {
    fun targetable(card: ZoneCard) = runTargetAction != null && (card.instanceId in targetableIDs || card.id in targetableIDs)
    fun perform(action: LegalAction) {
        if (pendingActionId != null || legalActions.none { it.id == action.id }) return
        if (GameplayAffordances.dismissesZone(action)) { selection.inspectedCard = null; close() }
        runAction(action)
    }
    val breath = if (BoardMotion.reduceMotion) null else rememberBoardBreath(1100, 0.55f, 1f)
    ArenaBrowserFrame(title, detail = ArenaScreens.zoneDetail(title, cards, cards.any(::targetable)), identifier = "arena.zone",
        inspect = { selection.inspectedCard = it },
        // Done always closes, even while an answer is on its way.
        footer = { ArenaAnswerRow(primary = ArenaPrimaryAnswer("Done", action = close)) }) { landscape, screen ->
        val height = if (landscape) min(220f, screen.height * 0.5f) else min(200f, (screen.width - 56f) / 3f * 1.4f)
        val size = DpSize((height / 1.4f).dp, height.dp)
        @Composable
        fun tile(card: ZoneCard) {
            val actions = GameBoardInteractionState.cardActions(card, legalActions)
            val target = targetable(card)
            Column(Modifier.width(size.width), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.then(if (target || actions.isNotEmpty()) Modifier.arenaOutlineGlow(ArenaGlowOutline.Card,
                    if (target) io.magicmobile.android.game.ArenaGlowTone.TARGET else io.magicmobile.android.game.ArenaGlowTone.PLAYABLE,
                    breath = if (target) null else breath) else Modifier)
                    .onCardInteraction(tap = { selection.inspectedCard = card }, inspect = { selection.inspectedCard = card },
                        release = { if (selection.inspectedCard?.id == card.id) selection.inspectedCard = null })
                    .semantics { contentDescription = card.card.name }) {
                    CardTile(card, false, zoneName = "Zone", width = size.width, height = size.height, ignoreTappedRotation = true)
                }
                if (target) ArenaPlaqueButton("Choose", { if (pendingActionId == null) runTargetAction?.invoke(card) }, Modifier.size(size.width, 40.dp),
                    fontSize = 14f, enabled = pendingActionId == null)
                for (action in actions.take(3)) {
                    ArenaPlaqueButton(if (actions.size == 1 && action.type == "cast_spell") "Cast" else LegalActionDisplay.displayLabel(action), { perform(action) },
                        Modifier.size(size.width, 40.dp), fontSize = 14f, enabled = pendingActionId == null, identifier = "arena.zone.action.${action.id}")
                }
            }
        }
        when {
            cards.isEmpty() -> {}
            landscape -> ArenaCenteredRow((screen.width - 48f).dp, vertical = 14.dp) { cards.forEach { tile(it) } }
            // As many columns as cards, up to three, centred on the table; it scrolls only when they don't fit.
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                cards.chunked(ArenaScreens.zoneColumns(cards.size)).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) { row.forEach { tile(it) } }
                }
            }
        }
    }
}

// MARK: - Choices and players

/**
 * A list of named choices the Arena way: choices that name a card show that card with the choice's text; colours show their
 * mana symbol; anything else is a glass tile, with a search field for long lists. XMage's "Remember answer" twins become one
 * "Remember my choice" toggle.
 */
@Composable
fun ArenaChoiceBrowser(title: String, detail: String?, options: List<ArenaScreens.ChoiceOption>, source: XmageStackObject?, pending: Boolean,
                       answers: List<ArenaAnswer>, choose: (ArenaScreens.ChoiceOption, Boolean) -> Unit, inspect: (ZoneCard) -> Unit) {
    var rememberChoice by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    val view = LocalView.current
    val look = ArenaScreens.choiceLook(options)
    val shown = if (search.isEmpty()) options else options.filter { it.label.contains(search, ignoreCase = true) }
    fun pick(option: ArenaScreens.ChoiceOption) {
        if (pending) return
        GameHaptics.selection(view)
        choose(option, rememberChoice && option.rememberID != null)
    }
    ArenaBrowserFrame(title, detail = detail, source = source, identifier = "arena.choiceBrowser", inspect = inspect,
        footer = { ArenaAnswerRow(answers, pending = pending) }) { landscape, screen ->
        Column(Modifier.alpha(if (pending) 0.7f else 1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (options.size > 12 && look != ArenaScreens.ChoiceLook.CARDS) {
                TavernTextField(search, { search = it }, "Search choices", Modifier.widthIn(max = 360.dp).semantics { testTag = "arena.choice.search" })
            }
            when (look) {
                ArenaScreens.ChoiceLook.CARDS -> {
                    val height = min(if (landscape) screen.height * 0.5f else 250f, 250f)
                    val size = DpSize((height * 0.72f).dp, height.dp)
                    ArenaCenteredRow((screen.width - if (landscape && source != null) 150f else 0f).dp, vertical = 16.dp) {
                        for (option in shown) Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp)
                            .arenaTapHold({ pick(option) }, { option.card?.let(inspect) }).arenaChoiceSemantics(option)) {
                            ArenaAbilityCard(option.card, name = if (option.card == null) (if (option.label.length < 30) option.label else "Choice") else null,
                                kind = if (option.card == null) "Choice" else "Effect", text = option.text, size = size)
                        }
                    }
                }
                ArenaScreens.ChoiceLook.SYMBOLS -> Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    for (option in shown) Column(Modifier.heightIn(min = 88.dp).widthIn(min = 64.dp).clickable { pick(option) }.arenaChoiceSemantics(option),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 6.dp, 27.dp)) { ManaSymbolView(option.symbol ?: "C", 54.dp) }
                        Text(option.label, color = ArenaGlass.text, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
                    }
                }
                ArenaScreens.ChoiceLook.TILES -> {
                    val minimum = if (landscape) 170f else 150f
                    val columns = max(1, ((screen.width - 48f + 10f) / (minimum + 10f)).toInt())
                    val tile = ((screen.width - 48f - (columns - 1) * 10f) / columns).dp
                    Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        shown.chunked(columns).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                for (option in row) Box(Modifier.width(tile).heightIn(min = 48.dp).arenaGlassRow().clickable { pick(option) }
                                    .arenaChoiceSemantics(option).padding(horizontal = 10.dp, vertical = 6.dp), contentAlignment = Alignment.Center) {
                                    GameRulesText(PromptDisplayText.clean(option.label), symbolSize = 14.dp,
                                        style = ArenaMenuStyle.font(14f, SfWeight.semibold).copy(textAlign = TextAlign.Center), color = ArenaGlass.text, maxLines = 3)
                                }
                            }
                        }
                    }
                }
            }
            if (options.any { it.rememberID != null }) RememberChoiceToggle("Remember my choice for this game", rememberChoice, { rememberChoice = it },
                Modifier.widthIn(max = 420.dp))
        }
    }
}

private fun Modifier.arenaChoiceSemantics(option: ArenaScreens.ChoiceOption): Modifier =
    semantics(mergeDescendants = true) { contentDescription = PromptDisplayText.clean(option.label); testTag = "arena.choice.${option.id}" }

/** Choosing a player the Arena way (who goes first, which player): each player's medallion with their name under it; a tap chooses. */
@Composable
fun ArenaPlayerChoice(title: String, seats: List<ArenaScreens.Seat>, pending: Boolean, answers: List<ArenaAnswer>, choose: (ArenaScreens.Seat) -> Unit,
                      detail: String? = null) {
    val view = LocalView.current
    ArenaBrowserFrame(title, detail = detail, identifier = "arena.playerChoice", footer = { ArenaAnswerRow(answers, pending = pending) }) { landscape, screen ->
        val diameter = (min(screen.width, screen.height) * if (seats.size > 2) 0.24f else 0.3f).dp
        val columns = ArenaScreens.playerColumns(seats.size, landscape)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(diameter * 0.3f)) {
            seats.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(diameter * 0.3f)) {
                    for (seat in row) Column(Modifier.width(diameter * 1.25f).clickable { if (!pending) { GameHaptics.selection(view); choose(seat) } }
                        .semantics(mergeDescendants = true) { contentDescription = seat.name; testTag = "arena.player.${seat.id}" },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        val player = seat.player
                        if (player != null) ArenaHeroMedallion(player, diameter)
                        else Box(Modifier.size(diameter).background(Color.White.copy(alpha = 0.08f), CircleShape).border(2.dp, ArenaGlass.hairline, CircleShape))
                        FitText(seat.name, ArenaMenuStyle.title(18f, SfWeight.bold).arenaShadow(), Modifier.padding(top = diameter * 0.1f),
                            color = ArenaGlass.text, minimumScale = 0.7f)
                    }
                }
            }
        }
    }
}

// MARK: - Splits and piles

/**
 * Splitting damage, counters or mana the Arena way: each blocker or target as its card (a player as their medallion, a colour
 * as its symbol) with a big number on it and − / + under it, lethal marked; what's left to give under the title, Done only when
 * the split is legal. XMage's own split comes in filled.
 */
@Composable
fun ArenaSplitBrowser(title: String, rows: List<ArenaScreens.SplitRow>, slots: List<XmagePromptMultiAmount>, totalMin: Int?, totalMax: Int?,
                      source: XmageStackObject?, sourceCard: ZoneCard?, pending: Boolean, answers: List<ArenaAnswer>, submit: (List<Int>) -> Unit,
                      inspect: (ZoneCard) -> Unit) {
    var values by remember { mutableStateOf<List<Int>?>(null) }
    val view = LocalView.current
    val current = values ?: rows.map { it.initial }
    val total = current.sum()
    val valid = PromptCommandBuilder.isValidMultiAmountValues(current, slots, totalMin, totalMax)
    val blood = rgb(0.55, 0.06, 0.05)
    ArenaBrowserFrame(title, detail = ArenaScreens.splitDetail(total, totalMin, totalMax), source = source, sourceCard = sourceCard,
        identifier = "arena.split", inspect = inspect, footer = {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                ArenaPlaqueButton("Reset", { values = null }, Modifier.size(110.dp, 44.dp), kind = ArenaPlaqueKind.SECONDARY, fontSize = 15f,
                    enabled = values != null && !pending)
                ArenaAnswerRow(answers, ArenaPrimaryAnswer("Done", enabled = valid) { submit(current) }, pending)
            }
        }) { landscape, screen ->
        val columns = if (landscape) max(1, rows.size) else min(3, max(rows.size, 1))
        val fitted = if (landscape) 210f else ((screen.width - 48f - (columns - 1) * 14f) / columns) / 0.72f
        val height = min(if (landscape) screen.height * 0.42f else fitted, 210f)
        val size = DpSize((height * 0.72f).dp, height.dp)
        @Composable
        fun column(index: Int, row: ArenaScreens.SplitRow) {
            val value = current.getOrElse(index) { row.initial }
            val lethal = row.lethal?.let { value >= it } ?: false
            val name = row.card?.card?.name ?: ArenaSplit.name(row.label)
            @Composable
            fun stepper(symbol: String, delta: Int) {
                val now = current.getOrElse(index) { row.initial }
                val blocked = if (delta < 0) now <= row.minimum else now >= row.maximum || (totalMax?.let { total >= it } ?: false)
                ArenaRepeatButton(Modifier.size(50.dp, 40.dp).semantics { testTag = "arena.split.${row.id}.${if (delta < 0) "minus" else "plus"}" },
                    enabled = !blocked && !pending, label = if (delta < 0) "One less to $name" else "One more to $name", action = {
                        val next = (values ?: rows.map { it.initial }).toMutableList()
                        // Never past the row's limits, nor more than the total to give.
                        if (delta > 0 && totalMax != null && next.sum() >= totalMax) false
                        else {
                            val proposed = (next[index] + delta).coerceIn(row.minimum, row.maximum)
                            if (proposed == next[index]) false else { next[index] = proposed; values = next; GameHaptics.selection(view); true }
                        }
                    }) {
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)), CircleShape)
                        .border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
                        Text(symbol, color = ArenaGlass.text.copy(alpha = if (blocked) 0.35f else 1f), style = ArenaMenuStyle.title(22f, SfWeight.heavy))
                    }
                }
            }
            Column(Modifier.semantics { contentDescription = "$name: $value${if (lethal) ", lethal" else ""}"; testTag = "arena.split.${row.id}" },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.glow(Color.Black.copy(alpha = 0.6f), 8.dp, 8.dp).arenaTapHold({}, { row.card?.let(inspect) }), contentAlignment = Alignment.Center) {
                    val card = row.card; val player = row.player; val symbol = row.symbol
                    when {
                        card != null -> CardTile(card, false, zoneName = "Split", width = size.width, height = size.height, ignoreTappedRotation = true)
                        player != null -> Box(Modifier.requiredSize(size), contentAlignment = Alignment.Center) { ArenaHeroMedallion(player, size.width * 0.9f) }
                        symbol != null -> Box(Modifier.requiredSize(size.width, size.height * 0.7f), contentAlignment = Alignment.Center) { ManaSymbolView(symbol, size.width * 0.6f) }
                        else -> ArenaAbilityCard(null, name = ArenaSplit.name(row.label), kind = "Target", text = row.label, size = size)
                    }
                    Box(Modifier.size(62.dp).alpha(if (value == 0 && !lethal) 0.75f else 1f)
                        .background(if (lethal) blood.copy(alpha = 0.92f) else Color.Black.copy(alpha = 0.6f), CircleShape)
                        .border(2.dp, if (lethal) Brush.linearGradient(listOf(rgb(1.0, 0.45, 0.3), rgb(1.0, 0.45, 0.3))) else ArenaGlass.hairline, CircleShape),
                        contentAlignment = Alignment.Center) {
                        Text("$value", color = Color.White, style = ArenaMenuStyle.title(34f, SfWeight.heavy).copy(fontFeatureSettings = "tnum").arenaShadow(1.5f))
                    }
                    if (lethal) Box(Modifier.align(Alignment.TopEnd).offset(6.dp, (-6).dp).background(blood, CircleShape).padding(6.dp)) {
                        SfImage("skull.fill", Color.White, 16.dp)
                    }
                }
                FitText(name, ArenaMenuStyle.font(12f, SfWeight.semibold), Modifier.width(size.width), color = ArenaGlass.text, minimumScale = 0.75f,
                    textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { stepper("−", -1); stepper("+", 1) }
            }
        }
        if (landscape) ArenaCenteredRow((screen.width - if (source != null || sourceCard != null) 150f else 0f).dp, spacing = 18.dp, vertical = 14.dp) {
            rows.forEachIndexed { index, row -> column(index, row) }
        } else Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            rows.withIndex().chunked(columns).forEach { line ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) { line.forEach { (index, row) -> column(index, row) } }
            }
        }
    }
}

/** Choosing a pile the Arena way (Fact or Fiction, Liliana): the piles fanned side by side in gold-rimmed wells; a tap picks one. */
@Composable
fun ArenaPileBrowser(title: String, detail: String?, piles: List<XmagePromptPile>, source: XmageStackObject?, pending: Boolean,
                     choose: (XmagePromptPile) -> Unit, inspect: (ZoneCard) -> Unit) {
    var picked by remember { mutableStateOf<String?>(null) }
    val view = LocalView.current
    val chosenPile = piles.firstOrNull { it.id == picked }
    ArenaBrowserFrame(title, detail = detail, source = source, identifier = "arena.pileBrowser", inspect = inspect, footer = {
        ArenaAnswerRow(primary = ArenaPrimaryAnswer(chosenPile?.let { "Choose ${it.label}" } ?: "Pick a pile", enabled = chosenPile != null) {
            chosenPile?.let(choose) }, pending = pending)
    }) { landscape, _ ->
        val width = if (landscape) 96.dp else 84.dp
        @Composable
        fun well(pile: XmagePromptPile) {
            val chosen = picked == pile.id
            val shape = RoundedCornerShape(16.dp)
            Column(Modifier.then(if (chosen) Modifier.glow(rgb(1.0, 0.75, 0.3).copy(alpha = 0.7f), 10.dp, 16.dp) else Modifier)
                .background(Color.Black.copy(alpha = if (chosen) 0.5f else 0.35f), shape)
                .border(if (chosen) 3.dp else 1.dp, if (chosen) Brush.linearGradient(listOf(arenaPickGold, arenaPickGold)) else ArenaGlass.hairline, shape)
                .clickable { if (!pending) { picked = pile.id; GameHaptics.selection(view) } }
                .semantics(mergeDescendants = true) {
                    contentDescription = "${pile.label}: ${pile.cards.joinToString(", ") { it.card.name }}"; selected = chosen; testTag = "arena.pile.${pile.id}"
                }.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${pile.label.uppercase()} · ${if (pile.cards.size == 1) "1 CARD" else "${pile.cards.size} CARDS"}", color = arenaLabelGold,
                    style = ArenaMenuStyle.font(13f, SfWeight.heavy).copy(letterSpacing = 0.09.em))
                Row(Modifier.padding(14.dp).widthIn(min = width * 1.6f), horizontalArrangement = Arrangement.spacedBy(-width * 0.45f, Alignment.CenterHorizontally)) {
                    pile.cards.forEachIndexed { index, card ->
                        Box(Modifier.graphicsLayer { rotationZ = (index - pile.cards.size / 2) * 4f; transformOrigin = TransformOrigin(0.5f, 1f) }
                            .glow(Color.Black.copy(alpha = 0.5f), 4.dp, 6.dp).arenaTapHold({ if (!pending) { picked = pile.id; GameHaptics.selection(view) } }, { inspect(card) })) {
                            CardTile(card, false, zoneName = pile.label, width = width, height = width * 1.4f, ignoreTappedRotation = true)
                        }
                    }
                    if (pile.cards.isEmpty()) Box(Modifier.size(width, width * 1.4f), contentAlignment = Alignment.Center) {
                        Text("Empty", color = ArenaGlass.text.copy(alpha = 0.6f), style = ArenaMenuStyle.font(14f, SfWeight.regular).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic))
                    }
                }
            }
        }
        if (landscape) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
            piles.forEach { well(it) }
        } else Column(Modifier.verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            piles.forEach { well(it) }
        }
    }
}

// MARK: - The result

/**
 * The end of a game on the Arena board, as Arena shows it: the board dims and one word lands on a flare of light behind the
 * MagicMobile mark, orange for Victory, cold steel for Defeat, violet for a draw. A tap, or a moment, lifts the word to the
 * top over your medallion, your rank, the game's numbers and the two ways on. View Battlefield lifts it all.
 */
@Composable
fun ArenaGameResultView(snapshot: GameSnapshot, stats: GameStats?, rankChange: RankChange?, rematchTitle: String?, newGame: () -> Unit, quitGame: () -> Unit,
                        rankNote: String? = null) {
    val reduce = BoardMotion.reduceMotion
    val view = LocalView.current
    val safe = LocalArenaSafeArea.current
    val outcome = ArenaGameResult.outcome(snapshot)
    val word = ArenaGameResult.word(outcome)
    val flare = when (outcome) {
        ArenaGameResult.Outcome.VICTORY -> rgb(1.0, 0.52, 0.14)
        ArenaGameResult.Outcome.DEFEAT -> rgb(0.46, 0.58, 0.74)
        ArenaGameResult.Outcome.DRAW -> rgb(0.62, 0.40, 0.96)
    }
    var landed by remember { mutableStateOf(reduce) }
    var settled by remember { mutableStateOf(false) }
    var peeking by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        landed = true
        if (outcome == ArenaGameResult.Outcome.VICTORY) GameHaptics.success(view) else GameHaptics.warning(view)
        delay(if (reduce) 300 else 1800)
        settled = true
    }
    val land by animateFloatAsState(if (landed) 1f else 0f, if (reduce) tween(0) else spring(0.7f, 160f), label = "resultLand")
    val settle by animateFloatAsState(if (settled) 1f else 0f, if (reduce) tween(0) else spring(0.85f, 110f), label = "resultSettle")
    BoxWithConstraints(Modifier.fillMaxSize().semantics { contentDescription = "Game completed. $word" }) {
        val landscape = maxWidth > maxHeight
        ArenaDim(peeking, 0.86f) { settled = true }
        if (!peeking) {
            val size = if (landscape) 54f - 14f * settle else 60f - 16f * settle
            val restTop = safe.top(if (landscape) 50.dp else 104.dp)
            val middle = maxOf(0.dp, maxHeight / 2 - if (landscape) 70.dp else 90.dp)
            // Held to the screen: the flare is wider and spills off both sides, but it must not widen the layer.
            Column(Modifier.width(maxWidth).padding(horizontal = if (landscape) safe.side else 0.dp)
                .clickable(remember { MutableInteractionSource() }, null) { settled = true },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (landscape) 10.dp else 18.dp)) {
                Spacer(Modifier.height(middle + (restTop - middle) * settle))
                Box(Modifier.fillMaxWidth().height((size * 2).dp).graphicsLayer {
                    val s = if (reduce) 1f else 1.5f - 0.5f * land; scaleX = s; scaleY = s; alpha = if (reduce) 1f else land
                }, contentAlignment = Alignment.Center) {
                    Box(Modifier.wrapContentSize(unbounded = true).requiredSize(520.dp, (size * 1.9f).dp).drawBehind {
                        drawOval(Brush.radialGradient(0f to flare.copy(alpha = 0.85f), 0.5f to flare.copy(alpha = 0.25f), 1f to Color.Transparent,
                            radius = 220.dp.toPx()))
                    })
                    Box(Modifier.wrapContentSize(unbounded = true).offset(y = (size * 0.12f).dp).requiredSize(440.dp, 2.5.dp)
                        .background(Brush.horizontalGradient(listOf(Color.Transparent, flare, Color.White.copy(alpha = 0.9f), flare, Color.Transparent)), CircleShape))
                    Image(painterResource(R.drawable.launch_mark), null, Modifier.height((size * 1.7f).dp).alpha(0.32f)
                        .glow(flare.copy(alpha = 0.6f), 18.dp, (size * 0.85f).dp))
                    Text(word.uppercase(), Modifier.semantics { heading() }, color = if (outcome == ArenaGameResult.Outcome.DEFEAT) Color(0.86f, 0.86f, 0.86f) else Color.White,
                        style = ArenaMenuStyle.title(size, SfWeight.bold).copy(letterSpacing = 0.06.em,
                            shadow = androidx.compose.ui.graphics.Shadow(flare.copy(alpha = 0.9f), Offset.Zero, 28f)), maxLines = 1)
                }
                if (settled) Column(Modifier.alpha(settle).offset(y = (24 * (1 - settle)).dp).padding(horizontal = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (landscape) 8.dp else 14.dp)) {
                    snapshot.human?.let { viewer ->
                        Box(Modifier.clearAndSetSemantics { }) {
                            ArenaHeroMedallion(viewer, if (landscape) 84.dp else 120.dp, active = outcome == ArenaGameResult.Outcome.VICTORY, showsLife = false)
                            if (outcome == ArenaGameResult.Outcome.DEFEAT) Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.35f), CircleShape))
                        }
                    }
                    rankChange?.let { change ->
                        // While placing, the climb stays hidden: the title and a grey emblem until the last game.
                        val placement = change.placementTitle
                        Row(Modifier.semantics(mergeDescendants = true) { }, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            io.magicmobile.android.ranked.RankEmblem(if (placement != null) io.magicmobile.android.game.RankPosition.START.tier else change.after.tier,
                                if (landscape) 40.dp else 52.dp, Modifier.colorAdjust(saturation = if (placement != null) 0f else 1f))
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(placement ?: change.after.title, color = ArenaGlass.text, style = ArenaMenuStyle.title(20f, SfWeight.bold))
                                Text(ArenaGameResult.rankLine(change), color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
                            }
                        }
                    }
                    // Why a ranked win left the ladder alone, once the server says so.
                    rankNote?.let { Text(it, Modifier.semantics { testTag = "board.result.rankNote" }, color = ArenaGlass.text.copy(alpha = 0.8f),
                        style = ArenaMenuStyle.font(13f, SfWeight.semibold), textAlign = TextAlign.Center) }
                    if (stats != null && stats.turns > 0) Row(horizontalArrangement = Arrangement.spacedBy(if (landscape) 22.dp else 28.dp)) {
                        for ((value, label) in listOf("${stats.turns}" to "Turns", "${stats.combatDamage}" to "Damage", "${stats.creaturesDestroyed}" to "Destroyed")) {
                            Column(Modifier.semantics(mergeDescendants = true) { }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(value, color = ArenaGlass.text, style = ArenaMenuStyle.title(24f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
                                Text(label.uppercase(), color = ArenaGlass.text.copy(alpha = 0.65f), style = ArenaMenuStyle.font(10f, SfWeight.heavy).copy(letterSpacing = 0.12.em))
                            }
                        }
                    }
                    Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ArenaButton(quitGame, kind = ArenaButtonKind.SECONDARY) { ArenaButtonText("Main Menu") }
                        ArenaButton(newGame, identifier = "board.result.rematch") { ArenaButtonText(rematchTitle ?: "New Game") }
                    }
                }
            }
        }
        Box(Modifier.align(Alignment.TopEnd).padding(top = if (landscape) 6.dp else safe.top(50.dp) - 6.dp, end = if (landscape) 120.dp else 16.dp)) {
            ArenaButton({ peeking = !peeking }, kind = ArenaButtonKind.SECONDARY, compact = true, identifier = "board.result.viewBattlefield") {
                ArenaButtonText(if (peeking) "Back" else "View Battlefield")
            }
        }
    }
}
