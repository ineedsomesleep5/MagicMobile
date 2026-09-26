package io.magicmobile.android.board

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.BattlefieldLayoutMetrics
import io.magicmobile.android.game.BoardPoint
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.CombatArrow
import io.magicmobile.android.game.CombatArrowKind
import io.magicmobile.android.game.CombatArrowModel
import io.magicmobile.android.game.CombatEdgeCluster
import io.magicmobile.android.game.CombatPlayerIdentity
import io.magicmobile.android.game.CombatViewportAnchors
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.PortraitBattlefieldLayoutMetrics
import io.magicmobile.android.game.XmageCombatGroup
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

private fun DrawScope.drawCombatArrow(arrow: CombatArrow, start: BoardPoint, end: BoardPoint) {
    val color = when (arrow.kind) {
        CombatArrowKind.ATTACK -> MagicPalette.oxblood
        CombatArrowKind.BLOCKED_ATTACK -> Color.Gray
        CombatArrowKind.BLOCK, CombatArrowKind.PREVIEW_BLOCK -> MagicPalette.arcaneBlue
        CombatArrowKind.PREVIEW_ATTACK -> MagicPalette.warningAmber
    }
    val preview = arrow.kind == CombatArrowKind.PREVIEW_ATTACK || arrow.kind == CombatArrowKind.PREVIEW_BLOCK
    val a = Offset(start.x.dp.toPx(), start.y.dp.toPx())
    val b = Offset(end.x.dp.toPx(), end.y.dp.toPx())
    val width = (if (preview) 2f else 3f).dp.toPx()
    drawLine(color.copy(alpha = if (preview) 0.48f else 0.82f), a, b, width, StrokeCap.Round,
        if (preview) PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx())) else null)
    val angle = atan2(b.y - a.y, b.x - a.x)
    val head = 9.dp.toPx()
    val left = Offset(b.x - head * cos(angle - Math.PI.toFloat() / 6), b.y - head * sin(angle - Math.PI.toFloat() / 6))
    val right = Offset(b.x - head * cos(angle + Math.PI.toFloat() / 6), b.y - head * sin(angle + Math.PI.toFloat() / 6))
    val headColor = color.copy(alpha = if (preview) 0.56f else 0.92f)
    drawLine(headColor, b, left, width, StrokeCap.Round)
    drawLine(headColor, b, right, width, StrokeCap.Round)
}

/** Attack and block arrows between the rendered cards, and to the defending player's HUD. */
@Composable
fun PortraitCombatArrowOverlay(snapshot: GameSnapshot, groups: List<XmageCombatGroup>, previewArrows: List<CombatArrow>,
                               metrics: PortraitBattlefieldLayoutMetrics, humanBattlefield: List<ZoneCard>, opponentBattlefield: List<ZoneCard>,
                               renderedBounds: Map<String, BoardRect>, focusedOpponentID: String?, modifier: Modifier = Modifier) {
    val anchors = CombatViewportAnchors.resolve(renderedBounds, (humanBattlefield + opponentBattlefield).map { it.instanceId }.toSet(),
        listOf(metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect),
        CombatViewportAnchors.laneIndices(humanBattlefield, opponentBattlefield)).mapValues { it.value.point }
    fun playerAnchor(id: String, kind: String?): BoardPoint? {
        if (!(kind == null || kind.lowercase() == "player")) return null
        val rect = when {
            // The bottom seat: the viewer, or their stand-in while they watch.
            CombatPlayerIdentity.ids(snapshot.seatID, snapshot).contains(id) -> metrics.bottomControlsRect
            focusedOpponentID != null && CombatPlayerIdentity.ids(focusedOpponentID, snapshot).contains(id) -> metrics.topHUDRect
            else -> return null
        }
        return BoardPoint(rect.midX, rect.midY)
    }
    val arrows = CombatArrowModel.arrows(groups, previewArrows)
    if (arrows.isEmpty()) return
    Canvas(modifier.fillMaxSize()) {
        for (arrow in arrows) {
            val start = anchors[arrow.fromId] ?: continue
            val end = anchors[arrow.toId] ?: playerAnchor(arrow.toId, arrow.toKind) ?: continue
            drawCombatArrow(arrow, start, end)
        }
    }
}

/** The landscape board's arrows (CombatArrowOverlay). */
@Composable
fun CombatArrowOverlay(snapshot: GameSnapshot, groups: List<XmageCombatGroup>, previewArrows: List<CombatArrow>, metrics: BattlefieldLayoutMetrics,
                       humanBattlefield: List<ZoneCard>, opponentBattlefield: List<ZoneCard>, renderedBounds: Map<String, BoardRect>,
                       modifier: Modifier = Modifier) {
    val anchors = CombatViewportAnchors.resolve(renderedBounds, (humanBattlefield + opponentBattlefield).map { it.instanceId }.toSet(),
        listOf(metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect),
        CombatViewportAnchors.laneIndices(humanBattlefield, opponentBattlefield)).mapValues { it.value.point }
    val arrows = CombatArrowModel.arrows(groups, previewArrows)
    if (arrows.isEmpty()) return
    Canvas(modifier.fillMaxSize()) {
        for (arrow in arrows) {
            val start = anchors[arrow.fromId] ?: continue
            val end = anchors[arrow.toId] ?: defenderAnchor(arrow.toId, arrow.toKind, metrics, snapshot) ?: continue
            drawCombatArrow(arrow, start, end)
        }
    }
}

private fun defenderAnchor(defenderID: String, kind: String?, metrics: BattlefieldLayoutMetrics, snapshot: GameSnapshot): BoardPoint? {
    val side = CombatPlayerIdentity.side(defenderID, kind, snapshot) ?: return null
    val rect = if (side == CombatPlayerIdentity.Side.VIEWER) metrics.playerBattlefieldRect else metrics.opponentBattlefieldRect
    return BoardPoint(metrics.boardColumnRect.minX + 10, rect.midY)
}

/** Markers at a lane's edge for combatants scrolled out of view; tap to inspect them. */
@Composable
fun CombatEdgeIndicators(cards: List<ZoneCard>, combatIDs: Set<String>, bounds: Map<String, BoardRect>, viewports: List<BoardRect>,
                         laneIndices: Map<String, Int>, inspect: (ZoneCard) -> Unit) {
    val anchors = CombatViewportAnchors.resolve(bounds, combatIDs.intersect(cards.map { it.instanceId }.toSet()), viewports, laneIndices)
    for (cluster in CombatEdgeCluster.groups(anchors)) {
        val members = cards.filter { it.instanceId in cluster.cardIDs }
        Box(Modifier.offset { IntOffset(((cluster.point.x - 22) * density).roundToInt(), ((cluster.point.y - 22) * density).roundToInt()) }
            .semantics { contentDescription = "${members.size} offscreen combat cards. Choose a card to inspect" }) {
            BoardMenu({ members.map { card -> MenuEntry.Item("Inspect ${card.card.name}") { inspect(card) } } }) {
                Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(26.dp).background(Color.White, CircleShape))
                    SfImage("arrow.left.and.right.circle.fill", Color.Red, 26.dp)
                    if (members.size > 1) Text("${members.size}", Modifier.align(Alignment.TopEnd).background(Color.Black, CircleShape).padding(3.dp),
                        color = Color.White, style = SfText.caption2(SfWeight.bold))
                }
            }
        }
    }
}
