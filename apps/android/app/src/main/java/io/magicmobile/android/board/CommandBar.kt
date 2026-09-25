package io.magicmobile.android.board

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.ui.zIndex
import io.magicmobile.android.game.BattlefieldAttachments
import io.magicmobile.android.game.CompactPromptPopup
import io.magicmobile.android.game.GameActionDockModel
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameplayActionPresentation
import io.magicmobile.android.game.GameplayAffordances
import io.magicmobile.android.game.LegalAction
import io.magicmobile.android.game.ManaPool
import io.magicmobile.android.game.PlayerGameState
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** On-device turn skipping (Swift NativeTurnControl), provided by the session owner. */
data class NativeTurnControl(val canEndTurn: Boolean, val canSkipResponses: Boolean, val canSkipToMyTurn: Boolean, val isAutoPassing: Boolean,
                             val status: String?, val endTurn: () -> Unit, val skipResponses: () -> Unit, val skipToMyTurn: () -> Unit,
                             val stop: () -> Unit)

val LocalNativeTurnControl = compositionLocalOf<NativeTurnControl?> { null }

/** GameplayDockButtonStyle: an ember capsule for the primary action, iron for the rest. */
@Composable
private fun DockButton(onClick: () -> Unit, isPrimary: Boolean, enabled: Boolean, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    PressableBox(onClick, modifier, enabled, pressSound = GameSound.UI_TAP) { pressed ->
        val scale by animateFloatAsState(if (pressed && !BoardMotion.reduceMotion) 0.96f else 1f, tween(140), label = "dockPress")
        val colors = if (isPrimary) {
            if (pressed) listOf(rgb(0.66, 0.28, 0.08), rgb(0.40, 0.12, 0.03)) else listOf(rgb(0.78, 0.31, 0.065), rgb(0.64, 0.20, 0.05))
        } else listOf(MagicPalette.iron.copy(alpha = 0.88f), MagicPalette.leather.copy(alpha = 0.76f))
        Box(Modifier.scale(scale).fillMaxWidth().defaultMinSize(minHeight = 44.dp)
            .glow(if (isPrimary && enabled) Color(0xFFFFA500).copy(alpha = 0.35f) else Color.Transparent, 8.dp, 22.dp)
            .background(Brush.linearGradient(colors), CircleShape)
            .border(if (isPrimary) 1.5.dp else 1.dp, if (isPrimary) rgb(1.0, 0.79, 0.39) else MagicPalette.parchment.copy(alpha = 0.25f), CircleShape)
            .alpha(if (enabled) 1f else 0.42f).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides if (isPrimary) Color.White else MagicPalette.parchment) {
                content()
            }
        }
    }
}

/** GameplayDockMenuButtonStyle: a 44-point iron circle. */
@Composable
private fun DockCircle(pressed: Boolean = false, content: @Composable () -> Unit) {
    Box(Modifier.size(44.dp).background(if (pressed) MagicPalette.brass.copy(alpha = 0.62f) else MagicPalette.iron.copy(alpha = 0.84f), CircleShape)
        .iosCircleOutline(), contentAlignment = Alignment.Center) { content() }
}

@Composable
fun YieldActionsControl(snapshot: GameSnapshot, actions: List<LegalAction>, fontSize: Float, runAction: (LegalAction) -> Unit, iconOnly: Boolean = false) {
    @Composable
    fun label(title: String, disclosure: Boolean) {
        if (iconOnly) SfImage("forward.end", MagicPalette.parchment, 18.dp)
        else Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = Color.White, style = sf(fontSize, SfWeight.black, SfDesign.SERIF), textAlign = TextAlign.Center)
            if (disclosure) SfImage("chevron.up.chevron.down", Color.White, maxOf(fontSize - 2, 7f).dp)
        }
    }
    val single = actions.singleOrNull()
    if (single != null) {
        val title = GameplayActionPresentation.title(single, snapshot)
        if (iconOnly) PressableBox({ runAction(single) }, Modifier.semantics { contentDescription = title }) { pressed -> DockCircle(pressed) { label(title, false) } }
        else CompactActionButton({ runAction(single) }, Modifier.semantics { contentDescription = title }) { label(title, false) }
    } else {
        BoardMenu({ actions.map { action -> MenuEntry.Item(GameplayActionPresentation.title(action, snapshot)) { runAction(action) } } },
            Modifier.semantics { contentDescription = if (actions.isEmpty()) "No timing options available" else "Open timing options" },
            enabled = actions.isNotEmpty()) {
            Box(Modifier.alpha(if (actions.isEmpty()) 0.5f else 1f)) {
                if (iconOnly) DockCircle { label("Timing Options", true) }
                else Box(Modifier.defaultMinSize(94.dp, 44.dp).background(MagicPalette.iron.copy(alpha = 0.58f), CircleShape).padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center) { label("Timing Options", true) }
            }
        }
    }
}

/** ContentView.swift GameplayActionDock: the primary Pass/Choice button, skip options and the controls menu. */
@Composable
fun GameplayActionDock(snapshot: GameSnapshot, passAction: LegalAction?, yieldActions: List<LegalAction>, pendingActionId: String?,
                       openPromptDetails: () -> Unit, openLog: () -> Unit, openSettings: () -> Unit, runAction: (LegalAction) -> Unit,
                       modifier: Modifier = Modifier, compact: Boolean = false, landscapeSidebar: Boolean = false, horizontal: Boolean = false) {
    val nativeTurnControl = LocalNativeTurnControl.current
    val promptActions = CompactPromptPopup.compactLegalPromptActions(snapshot)
    val decision = CompactPromptPopup.shouldShow(snapshot, null)
    val model = GameActionDockModel.make(snapshot, passAction, promptActions, decision, pendingActionId)
    val hasStackForPriority = snapshot.stackTopFirst.isNotEmpty() || snapshot.players.any { it.zones.stack.isNotEmpty() }
    val showsPriorityHelp = model.mode == GameActionDockModel.Mode.PRIORITY && model.isPrimaryEnabled && model.primaryAction?.type == "pass_priority"

    @Composable
    fun primaryButton(buttonModifier: Modifier) {
        Column(buttonModifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // A finger-down on Pass must not become a new prompt's action if an engine update replaces this control.
            key("${model.primaryAction?.id ?: "none"}:${snapshot.promptEnvelopeV2?.id ?: "none"}:${model.primaryAction?.messageId ?: snapshot.promptEnvelopeV2?.messageId ?: -1}") {
                DockButton({
                    val primary = model.primaryAction
                    if (primary != null) runAction(primary) else if (model.mode == GameActionDockModel.Mode.PROMPT) openPromptDetails()
                }, true, model.isPrimaryEnabled, Modifier.semantics {
                    contentDescription = model.primaryTitle + if (showsPriorityHelp) ". " + GameplayActionPresentation.priorityHint(hasStackForPriority) else ""
                }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                        SfImage(if (model.mode == GameActionDockModel.Mode.PROMPT) "sparkles" else "forward.end.fill", Color.White, if (compact) 11.dp else 12.dp)
                        FitText(model.primaryTitle, sf(if (compact) 13f else 15f, SfWeight.bold, SfDesign.SERIF), color = Color.White,
                            maxLines = if (landscapeSidebar) 1 else 2, minimumScale = 0.62f)
                    }
                }
            }
            if (showsPriorityHelp && !landscapeSidebar) {
                FitText(GameplayActionPresentation.priorityDetail(hasStackForPriority), SfText.caption2(), color = MagicPalette.parchment.copy(alpha = 0.8f), minimumScale = 0.8f)
            }
        }
    }

    @Composable
    fun controlsMenu() {
        val many = model.mode == GameActionDockModel.Mode.PROMPT && model.promptActions.size > 1
        BoardMenu({
            buildList {
                if (model.mode == GameActionDockModel.Mode.PROMPT) {
                    model.promptActions.filter { it.id != model.primaryAction?.id }.forEach { action ->
                        add(MenuEntry.Item(action.label, enabled = pendingActionId == null) { runAction(action) })
                    }
                    add(MenuEntry.Item("All Choices", action = openPromptDetails))
                    add(MenuEntry.Divider)
                }
                add(MenuEntry.Item("Game Log", "list.bullet.rectangle", action = openLog))
                if (snapshot.source == "xmage-ondevice" && model.mode != GameActionDockModel.Mode.PROMPT) add(MenuEntry.Item("More actions", action = openPromptDetails))
                add(MenuEntry.Item("Game Settings", "gearshape.fill", action = openSettings))
            }
        }, Modifier.semantics { contentDescription = if (many) "More choices and game controls" else "Game controls" }) {
            DockCircle { SfImage(if (many) "ellipsis.circle.fill" else "slider.horizontal.3", MagicPalette.parchment, 16.dp) }
        }
    }

    @Composable
    fun secondaryLabel(title: String, icon: String) {
        Row(Modifier.defaultMinSize(minHeight = 44.dp), horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically) {
            SfImage(icon, MagicPalette.parchment, 15.dp)
            if (!horizontal) Text(title, color = MagicPalette.parchment, style = sf(14f, SfWeight.semibold), maxLines = 2)
        }
    }

    @Composable
    fun secondaryControl(controlModifier: Modifier) {
        Box(controlModifier) {
            when {
                nativeTurnControl != null && nativeTurnControl.isAutoPassing -> {
                    if (horizontal) PressableBox(nativeTurnControl.stop, Modifier.semantics { contentDescription = "Stop skipping" }) { pressed -> DockCircle(pressed) { secondaryLabel("Stop skipping", "stop.fill") } }
                    else DockButton(nativeTurnControl.stop, false, true) { secondaryLabel("Stop skipping", "stop.fill") }
                }
                nativeTurnControl != null -> {
                    val anyEnabled = nativeTurnControl.canEndTurn || nativeTurnControl.canSkipResponses || nativeTurnControl.canSkipToMyTurn
                    BoardMenu({
                        listOf(MenuEntry.Item("End turn — skip stack responses", enabled = nativeTurnControl.canSkipResponses, action = nativeTurnControl.skipResponses),
                            MenuEntry.Item("Skip to my turn — skip stack responses", enabled = nativeTurnControl.canSkipToMyTurn, action = nativeTurnControl.skipToMyTurn),
                            MenuEntry.Item("End turn — stop for responses", enabled = nativeTurnControl.canEndTurn, action = nativeTurnControl.endTurn))
                    }, Modifier.semantics { contentDescription = "Skip options" }, enabled = anyEnabled) {
                        Box(Modifier.alpha(if (anyEnabled) 1f else 0.42f)) {
                            if (horizontal) DockCircle { secondaryLabel("Skip…", "forward.end") }
                            else Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                                .background(Brush.linearGradient(listOf(MagicPalette.iron.copy(alpha = 0.88f), MagicPalette.leather.copy(alpha = 0.76f))), CircleShape)
                                .border(1.dp, MagicPalette.parchment.copy(alpha = 0.25f), CircleShape), contentAlignment = Alignment.Center) { secondaryLabel("Skip…", "forward.end") }
                        }
                    }
                }
                model.showsPromptDetails -> {
                    if (horizontal) PressableBox(openPromptDetails, Modifier.semantics { contentDescription = "View all choices" }) { pressed -> DockCircle(pressed) { secondaryLabel("Choices", "list.bullet.rectangle.portrait") } }
                    else DockButton(openPromptDetails, false, true) { secondaryLabel("Choices", "list.bullet.rectangle.portrait") }
                }
                else -> YieldActionsControl(snapshot, yieldActions, if (compact) 8f else 10f, runAction, iconOnly = horizontal)
            }
        }
    }

    if (horizontal) {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            secondaryControl(Modifier.width(44.dp))
            controlsMenu()
            primaryButton(Modifier.weight(1f))
        }
    } else {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(if (landscapeSidebar) 4.dp else 8.dp)) {
            primaryButton(Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                secondaryControl(Modifier.weight(1f)); controlsMenu()
            }
        }
    }
}

/** ContentView.swift PortraitBottomCommandBar: your zones, effects, mana, stack tray, life orb and the dock. */
@Composable
fun PortraitBottomCommandBar(humanName: String, human: PlayerGameState, opponentId: String, manaPool: ManaPool?, passAction: LegalAction?,
                             yieldActions: List<LegalAction>, pendingActionId: String?, snapshot: GameSnapshot, selection: BoardSelection,
                             openLog: () -> Unit, openSettings: () -> Unit, openPromptDetails: () -> Unit,
                             viewZone: (String, List<ZoneCard>) -> Unit, runAction: (LegalAction) -> Unit,
                             runCommand: (GameCommand, String, String) -> Unit, modifier: Modifier = Modifier) {
    var isStackOpen by remember { mutableStateOf(snapshot.id == "design-preview-stack-response-prompt") }
    var isEmotePickerOpen by remember { mutableStateOf(false) }
    val emoteCenter = LocalEmoteCenter.current
    val viewerActive = snapshot.isViewer(snapshot.activePlayerId)
    Column(modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerZoneMenu(human, viewZone, snapshot, pendingActionId)
            BoardPlayerEffects(human, BattlefieldAttachments.enchanting(human.playerId, snapshot.players.flatMap { it.zones.battlefield }), viewZone)
            Box(Modifier.weight(1f).horizontalScroll(rememberScrollState()).semantics { contentDescription = "Floating mana; swipe to view all colors" }) {
                ManaPoolHUD(manaPool, compact = true, payableSymbols = GameplayAffordances.floatingManaSymbols(snapshot, pendingActionId), payMana = { symbol ->
                    if (pendingActionId == null) GameplayAffordances.floatingManaCommand(symbol, snapshot)?.let { command ->
                        runCommand(command, "Spend floating {$symbol}", "floating-${snapshot.promptEnvelopeV2?.id ?: ""}-$symbol")
                    }
                })
            }
            BoardStackTray(snapshot.stackTopFirst, snapshot.xmage?.stack?.size ?: human.zones.stack.size) { isStackOpen = true }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                val ring by animateColorAsState(MagicPalette.antiqueGold.copy(alpha = if (viewerActive) 1f else 0.65f), tween(350), label = "orbRing")
                PressableBox({ if (emoteCenter != null) isEmotePickerOpen = true }, Modifier.semantics {
                    contentDescription = "Your life: ${human.life}" + if (emoteCenter != null) ". Opens quick chat" else ""
                }) {
                    Column(Modifier.size(52.dp).glow(MagicPalette.antiqueGold.copy(alpha = if (viewerActive) 0.7f else 0f), 10.dp, 26.dp)
                        .background(Color.Black.copy(alpha = 0.85f), CircleShape).border(if (viewerActive) 3.dp else 2.dp, ring, CircleShape),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        SfImage("heart.fill", MagicPalette.antiqueGold, 9.dp)
                        key(human.playerId) { BoardLifeTotal(human.life, sf(23f, SfWeight.bold, SfDesign.SERIF), baseColor = Color.White) }
                    }
                }
                if (emoteCenter != null) {
                    EmoteBubbleSlot(emoteCenter, human.playerId, modifier = Modifier.align(Alignment.BottomStart).offset(y = (-62).dp).wrapContentSize(unbounded = true).zIndex(5f))
                    if (isEmotePickerOpen) {
                        Popup(alignment = Alignment.BottomStart, offset = IntOffset(0, -170), onDismissRequest = { isEmotePickerOpen = false },
                            properties = PopupProperties(focusable = true)) {
                            EmotePicker(emoteCenter, snapshot) { isEmotePickerOpen = false }
                        }
                    }
                }
            }
            GameplayActionDock(snapshot, passAction, yieldActions, pendingActionId, openPromptDetails, openLog, openSettings, runAction,
                Modifier.weight(1f), horizontal = true)
        }
    }
    if (isStackOpen) {
        BoardSheet({ isStackOpen = false }) { BoardStackInspector(snapshot, selection) { isStackOpen = false } }
    }
}
