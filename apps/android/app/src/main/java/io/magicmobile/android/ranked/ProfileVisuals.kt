package io.magicmobile.android.ranked

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.Achievement
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.PlayerStats
import io.magicmobile.android.game.ProfileGame
import io.magicmobile.android.game.ProfileRankPoint
import io.magicmobile.android.game.ProfileShare
import io.magicmobile.android.game.ProfileWeek
import io.magicmobile.android.game.RankOutcome
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.game.RankTier
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

// The pictures of a profile, drawn in the tavern's brass and leather (ProfileVisuals.swift): the own
// profile and other players' public profiles share them.

object ProfilePalette {
    /** Wins: the tavern's gold. */
    val win = rgb(0.98, 0.78, 0.36)
    val winDeep = rgb(0.93, 0.50, 0.22)
    val loss = rgb(0.62, 0.16, 0.12)
    val draw = rgb(0.62, 0.58, 0.50)
    val track = Color.Black.copy(alpha = 0.42f)
    val winBrush: Brush get() = Brush.verticalGradient(listOf(win, winDeep))

    fun mana(symbol: String): Color = when (symbol) {
        "W" -> rgb(0.97, 0.92, 0.74); "U" -> rgb(0.30, 0.55, 0.90); "B" -> rgb(0.46, 0.36, 0.52)
        "R" -> rgb(0.89, 0.30, 0.22); "G" -> rgb(0.32, 0.68, 0.36); else -> rgb(0.6, 0.6, 0.6)
    }
}

private val parchment = TavernPalette.parchment
private val brassBrush get() = TavernPalette.goldText
private val emberInk = rgb(1.0, 0.91, 0.66)

private val utcDay: DateTimeFormatter get() = DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()).withZone(ZoneOffset.UTC)
private val utcDayLong: DateTimeFormatter get() = DateTimeFormatter.ofPattern("MMMM d", Locale.getDefault()).withZone(ZoneOffset.UTC)
private val shortDate: DateTimeFormatter get() = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()).withZone(java.time.ZoneId.systemDefault())
private val longDate: DateTimeFormatter get() = DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy, h:mm a", Locale.getDefault()).withZone(java.time.ZoneId.systemDefault())

internal fun formatShortDate(millis: Long): String = shortDate.format(Instant.ofEpochMilli(millis))

/** A section's title: brass capitals. */
@Composable
fun ProfileSectionTitle(text: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(text.uppercase(), Modifier.weight(1f).semantics { heading() }, color = TavernPalette.brass,
            style = sf(11f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.4f).copy(brush = brassBrush))
        trailing?.let { Text(it, Modifier.alpha(0.7f), color = parchment, style = sf(11f, SfWeight.semibold, SfDesign.SERIF)) }
    }
}

/** Our own chip: leather with a thin brass rim, ember glass when chosen. Filters use it. */
@Composable
fun ProfileChip(title: String, selected: Boolean, tag: String, onClick: () -> Unit, detail: String? = null) {
    Box(Modifier.defaultMinSize(minHeight = 44.dp).clickable(onClick = onClick)
        .semantics(mergeDescendants = true) {
            contentDescription = if (detail != null) "$title, $detail" else title
            role = Role.Button; this.selected = selected
        }.testTag(tag), contentAlignment = Alignment.Center) {
        Row(Modifier.defaultMinSize(minHeight = 34.dp).tavernCapsuleRim(thin = true).padding(1.5.dp)
            .tavernFill(if (selected) TavernMaterial.EMBER else TavernMaterial.LEATHER, CircleShape,
                overlay = if (selected) Color.Transparent else Color.Black.copy(alpha = 0.2f))
            .padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = if (selected) emberInk else parchment, style = sf(12f, SfWeight.heavy, SfDesign.SERIF), maxLines = 1)
            detail?.let { Text(it, Modifier.alpha(0.7f), color = if (selected) emberInk else parchment, style = sf(11f, SfWeight.semibold, SfDesign.SERIF)) }
        }
    }
}

data class SegmentOption<T>(val value: T, val title: String, val icon: String, val tag: String)

/** Our own segmented control: a leather trough in brass with one ember-glass segment lit. */
@Composable
fun <T> ProfileSegmented(options: List<SegmentOption<T>>, selection: T, tag: String, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().testTag(tag).background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
        .border(1.2.dp, TavernPalette.brass.copy(alpha = 0.55f), RoundedCornerShape(12.dp)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (option in options) {
            val on = option.value == selection
            Column(Modifier.weight(1f).defaultMinSize(minHeight = 52.dp)
                .then(if (on) Modifier.tavernFill(TavernMaterial.EMBER, RoundedCornerShape(9.dp)).border(1.dp, TavernPalette.brassLine, RoundedCornerShape(9.dp)) else Modifier)
                .clip(RoundedCornerShape(9.dp)).clickable { if (!on) onSelect(option.value) }
                .semantics(mergeDescendants = true) { contentDescription = option.title; role = Role.Button; selected = on }.testTag(option.tag),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                SfImage(option.icon, if (on) emberInk else parchment.copy(alpha = 0.8f), 14.dp)
                FitText(option.title, sf(12f, SfWeight.heavy, SfDesign.SERIF), color = if (on) emberInk else parchment.copy(alpha = 0.8f), minimumScale = 0.7f,
                    textAlign = TextAlign.Center)
            }
        }
    }
}

// MARK: Win rate

/** The record as a ring: wins in gold, draws in stone, losses in oxblood, the win rate in the middle. */
@Composable
fun WinRateRing(wins: Int, losses: Int, draws: Int, size: Dp = 132.dp) {
    val total = wins + losses + draws
    val progress = remember { Animatable(if (LaunchEnvironment.reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) { if (progress.value < 1f) progress.animateTo(1f, tween(900)) }
    val percent = if (total == 0) null else Math.round(wins.toDouble() / total * 100).toInt()
    val summary = if (percent == null) "Win rate: no games yet" else "Win rate $percent percent: $wins wins, $losses losses, $draws draws"
    Box(Modifier.size(size + size * 0.13f + 4.dp).testTag("profile.winRate").clearAndSetSemantics { contentDescription = summary }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val line = size.toPx() * 0.13f
            val inset = line / 2
            val arcSize = Size(this.size.width - line, this.size.height - line)
            drawArc(ProfilePalette.track, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(line))
            if (total > 0) {
                var start = 0f
                fun segment(count: Int, brush: Brush) {
                    if (count == 0) return
                    val fraction = count.toFloat() / total
                    val gap = if (fraction < 1f) 2.2f else 0f
                    val sweep = (fraction * 360f * progress.value - gap).coerceAtLeast(0.6f)
                    drawArc(brush, -90f + start * 360f + gap / 2, sweep, false, Offset(inset, inset), arcSize, style = Stroke(line, cap = StrokeCap.Butt))
                    start += fraction
                }
                segment(wins, ProfilePalette.winBrush)
                segment(draws, Brush.linearGradient(listOf(ProfilePalette.draw, ProfilePalette.draw)))
                segment(losses, Brush.linearGradient(listOf(ProfilePalette.loss, ProfilePalette.loss)))
            }
            drawCircle(TavernPalette.brass.copy(alpha = 0.5f), radius = this.size.width / 2 + 1.dp.toPx(), style = Stroke(1.dp.toPx()))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(percent?.let { "$it%" } ?: "–", style = sf((size.value * 0.27f), SfWeight.black, SfDesign.SERIF).copy(brush = brassBrush, fontFeatureSettings = "tnum"))
            Text("WIN RATE", Modifier.alpha(0.7f), color = parchment, style = sf(size.value * 0.075f, SfWeight.heavy, SfDesign.SERIF, tracking = 1.2f))
        }
    }
}

/** A big number over a small caption, in a dark inset tile. */
@Composable
fun ProfileStatTile(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().defaultMinSize(minHeight = 58.dp).background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(8.dp))
        .border(1.dp, TavernPalette.brass.copy(alpha = 0.4f), RoundedCornerShape(8.dp)).padding(6.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        FitText(value, sf(21f, SfWeight.black, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"), color = parchment, minimumScale = 0.6f)
        FitText(title.uppercase(), sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f), Modifier.alpha(0.7f), color = parchment, minimumScale = 0.7f)
    }
}

// MARK: Games over time

/** The last eight weeks as bars: wins in gold at the foot, other games in oxblood above. */
@Composable
fun WeeklyBars(weeks: List<ProfileWeek>, barHeight: Dp = 104.dp) {
    val peak = maxOf(3, weeks.maxOfOrNull { it.games } ?: 0)
    Row(Modifier.fillMaxWidth().testTag("profile.weeks"), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.Bottom) {
        for (week in weeks) {
            val label = utcDay.format(Instant.ofEpochMilli(week.start))
            Column(Modifier.weight(1f).clearAndSetSemantics {
                contentDescription = "Week of ${utcDayLong.format(Instant.ofEpochMilli(week.start))}: ${week.games} games, ${week.wins} wins"
            }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (week.games == 0) " " else "${week.games}", Modifier.alpha(0.85f), color = parchment,
                    style = sf(11f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
                Box(Modifier.fillMaxWidth().height(barHeight).background(ProfilePalette.track, CircleShape).clip(CircleShape), contentAlignment = Alignment.BottomCenter) {
                    Column(Modifier.fillMaxSize()) {
                        Spacer(Modifier.weight(1f))
                        val others = week.games - week.wins
                        if (others > 0) Box(Modifier.fillMaxWidth().height(barHeight * others / peak).background(ProfilePalette.loss))
                        if (week.wins > 0) Box(Modifier.fillMaxWidth().height(barHeight * week.wins / peak).background(ProfilePalette.winBrush))
                    }
                }
                FitText(label, sf(9f, SfWeight.semibold, SfDesign.SERIF), Modifier.alpha(0.65f), color = parchment, minimumScale = 0.6f, textAlign = TextAlign.Center)
            }
        }
    }
}

// MARK: Rank history

/** Rank over time: the standing after each ranked game, on the ladder's tiers. */
@Composable
fun RankHistoryChart(points: List<ProfileRankPoint>, height: Dp = 150.dp) {
    val measurer = rememberTextMeasurer()
    val summary = when {
        points.isEmpty() -> "Rank history: no ranked games yet"
        points.size == 1 -> "Rank history: ${points.last().position.title} after one ranked game"
        else -> "Rank history: from ${points.first().position.title} to ${points.last().position.title} over ${points.size} ranked games"
    }
    Column(Modifier.fillMaxWidth().testTag("profile.rankHistory").clearAndSetSemantics { contentDescription = summary }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.fillMaxWidth().height(height)) {
            if (points.isEmpty()) return@Canvas
            val values = points.map { it.points }
            val low = maxOf(0, (values.min()) - 3)
            val high = maxOf(low + 10, values.max() + 3)
            val left = 26.dp.toPx(); val right = 10.dp.toPx(); val top = 10.dp.toPx(); val bottom = 10.dp.toPx()
            val width = size.width - left - right; val plot = size.height - top - bottom
            fun y(value: Int) = top + (1f - (value - low).toFloat() / (high - low)) * plot
            fun x(index: Int) = if (points.size == 1) left + width / 2 else left + index.toFloat() / (points.size - 1) * width
            val perTier = RankPosition.DIVISIONS * RankPosition.PIPS_PER_DIVISION
            for (tier in RankTier.entries) {
                val start = tier.ordinal * perTier
                val visibleLow = maxOf(low, start); val visibleHigh = if (tier == RankTier.MYTHIC) high else minOf(high, start + perTier)
                if (start > low && start < high) drawLine(tier.tint.copy(alpha = 0.35f), Offset(left, y(start)), Offset(size.width - right, y(start)), 1.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx())))
                if (visibleHigh - visibleLow >= 4) {
                    val layout = measurer.measure(tier.label.take(1), sf(13f, SfWeight.black, SfDesign.SERIF).copy(color = tier.tint.copy(alpha = 0.9f)))
                    drawText(layout, topLeft = Offset(10.dp.toPx() - layout.size.width / 2f, y((visibleLow + visibleHigh) / 2) - layout.size.height / 2f))
                }
            }
            val line = Path(); val area = Path()
            values.forEachIndexed { index, value ->
                val px = x(index); val py = y(value)
                if (index == 0) { line.moveTo(px, py); area.moveTo(px, top + plot); area.lineTo(px, py) } else { line.lineTo(px, py); area.lineTo(px, py) }
            }
            area.lineTo(x(values.size - 1), top + plot); area.close()
            drawPath(area, Brush.verticalGradient(listOf(ProfilePalette.winDeep.copy(alpha = 0.38f), Color.Transparent), startY = top, endY = top + plot))
            drawPath(line, Brush.horizontalGradient(listOf(rgb(1.0, 0.88, 0.56), ProfilePalette.winDeep), startX = left, endX = left + width),
                style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            values.dropLast(1).forEachIndexed { index, value -> drawCircle(rgb(1.0, 0.9, 0.62), 2.5.dp.toPx(), Offset(x(index), y(value))) }
            val tier = points.last().position.tier
            val center = Offset(x(values.size - 1), y(values.last()))
            drawCircle(tier.tint.copy(alpha = 0.22f), 12.dp.toPx(), center); drawCircle(tier.tint.copy(alpha = 0.35f), 9.dp.toPx(), center)
            drawCircle(tier.tint, 6.dp.toPx(), center); drawCircle(Color.White.copy(alpha = 0.85f), 6.dp.toPx(), center, style = Stroke(1.5.dp.toPx()))
        }
        if (points.size > 1) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            val style = sf(10f, SfWeight.semibold, SfDesign.SERIF)
            Text(formatShortDate(points.first().date), Modifier.alpha(0.65f), color = parchment, style = style)
            Text("${points.size} ranked games", Modifier.weight(1f).alpha(0.65f), color = parchment, style = style, textAlign = TextAlign.Center)
            Text(formatShortDate(points.last().date), Modifier.alpha(0.65f), color = parchment, style = style)
        }
    }
}

// MARK: Colors

/** Color identity as a ring of the five colors, by games played with each. */
@Composable
fun ColorPie(shares: List<ProfileShare>, size: Dp = 112.dp) {
    val total = shares.sumOf { it.games }
    Row(Modifier.fillMaxWidth().testTag("profile.colors"), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(size).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val line = size.toPx() * 0.26f
                val inset = line / 2
                val arcSize = Size(this.size.width - line, this.size.height - line)
                var start = -90f
                for (share in shares) {
                    if (share.games == 0) continue
                    val sweep = 360f * share.games / maxOf(1, total)
                    val gap = if (shares.size > 1) 1.2f else 0f
                    drawArc(ProfilePalette.mana(share.id), start + gap, sweep - gap * 2, false, Offset(inset, inset), arcSize, style = Stroke(line))
                    start += sweep
                }
                drawCircle(TavernPalette.brass.copy(alpha = 0.5f), this.size.width / 2 - size.toPx() * 0.02f, style = Stroke(1.dp.toPx()))
                drawCircle(TavernPalette.brass.copy(alpha = 0.35f), this.size.width / 2 - size.toPx() * 0.28f, style = Stroke(1.dp.toPx()))
            }
            SfImage("sparkle", TavernPalette.brass, size * 0.2f)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            for (share in shares) {
                Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "${PlayerStats.colorName(share.id)}: ${share.games} games, ${share.wins} wins" },
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    io.magicmobile.android.board.TavernAwareManaSymbol(share.id, 17.dp)
                    Text(PlayerStats.colorName(share.id), Modifier.weight(1f), color = parchment, style = sf(13f, SfWeight.semibold, SfDesign.SERIF), maxLines = 1)
                    Text("${Math.round(share.games.toDouble() / maxOf(1, total) * 100)}%", Modifier.alpha(0.85f), color = parchment,
                        style = sf(12f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
                }
            }
        }
    }
}

// MARK: Commanders

/** A commander's illustration as a tile in a brass edge, with how often it was played and won. */
@Composable
fun CommanderTile(share: ProfileShare, crown: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.aspectRatio(0.78f).glow(Color.Black.copy(alpha = 0.5f), 4.dp, 10.dp).clip(RoundedCornerShape(10.dp))
        .background(Brush.verticalGradient(listOf(MagicPalette.iron, MagicPalette.leather)))
        .border(1.5.dp, TavernPalette.brassLine, RoundedCornerShape(10.dp))
        .clearAndSetSemantics { contentDescription = "${share.id}: ${share.games} games, ${share.wins} won" }) {
        CardArtwork(share.id, Modifier.fillMaxSize(), artOnly = true, placeholder = {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(share.id.take(1), color = parchment.copy(alpha = 0.25f), style = sf(40f, SfWeight.black, SfDesign.SERIF))
            }
        })
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
        Column(Modifier.align(Alignment.BottomStart).padding(7.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(share.id, color = parchment, style = sf(11f, SfWeight.heavy, SfDesign.SERIF), maxLines = 2)
            FitText("${share.games} games · ${Math.round(share.winRate * 100)}% won", sf(9f, SfWeight.semibold, SfDesign.SERIF), color = ProfilePalette.win, minimumScale = 0.7f)
        }
        if (crown) SfImage("crown.fill", TavernPalette.brass, 13.dp, Modifier.align(Alignment.TopEnd).padding(7.dp))
    }
}

/** The most played commanders as art tiles, the first with a crown. */
@Composable
fun CommanderTiles(shares: List<ProfileShare>) {
    Column(Modifier.fillMaxWidth().testTag("profile.commanders"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((rowIndex, row) in shares.chunked(3).withIndex()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((index, share) in row.withIndex()) CommanderTile(share, rowIndex == 0 && index == 0, Modifier.weight(1f))
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

// MARK: Streaks and trophies

/** Current and best streaks as flames. */
@Composable
fun StreakRow(current: Int, best: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((title, value, hot) in listOf(Triple("Streak", current, current >= 3), Triple("Best", best, false))) {
            Row(Modifier.weight(1f).defaultMinSize(minHeight = 52.dp).background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(8.dp))
                .border(1.dp, TavernPalette.brass.copy(alpha = 0.4f), RoundedCornerShape(8.dp)).padding(horizontal = 12.dp)
                .clearAndSetSemantics { contentDescription = "$title: $value wins in a row" },
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.then(if (hot) Modifier.glow(ProfilePalette.winDeep.copy(alpha = 0.7f), 6.dp, 10.dp) else Modifier)) {
                    SfImage("flame.fill", if (value > 0) ProfilePalette.win else Color.Gray.copy(alpha = 0.5f), 20.dp)
                }
                Column {
                    Text("$value", color = parchment, style = sf(22f, SfWeight.black, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
                    Text(title.uppercase(), Modifier.alpha(0.7f), color = parchment, style = sf(9f, SfWeight.heavy, SfDesign.SERIF, tracking = 1f))
                }
            }
        }
    }
}

internal fun achievementIcon(a: Achievement): String = when (a) {
    Achievement.FIRST_WIN -> "star.fill"; Achievement.FIRST_RANKED_WIN -> "shield.lefthalf.filled"
    Achievement.SILVER, Achievement.GOLD, Achievement.PLATINUM, Achievement.DIAMOND, Achievement.MYTHIC -> "crown.fill"
    Achievement.STREAK5 -> "flame.fill"; Achievement.VETERAN -> "hourglass"; Achievement.PRISMATIC -> "circle.hexagongrid.fill"
    Achievement.GIANT_SLAYER -> "bolt.shield.fill"; Achievement.QUICK_DRAW -> "hare.fill"; Achievement.HUMAN_WIN -> "person.2.fill"
}

/** The achievements as brass coins on a wooden shelf; earned ones shine, the rest wait in the dark. Tapping one reads what it is for. */
@Composable
fun TrophyShelf(unlocked: Set<Achievement>) {
    var chosen by remember { mutableStateOf<Achievement?>(null) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in Achievement.entries.chunked(5)) {
            Column {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                    for (achievement in row) {
                        val earned = achievement in unlocked
                        Column(Modifier.weight(1f).clickable { chosen = achievement }.padding(bottom = 2.dp)
                            .semantics(mergeDescendants = true) {
                                contentDescription = "${achievement.title}. ${achievement.detail}"
                                stateDescription = if (earned) "Earned" else "Locked"; role = Role.Button
                            }.testTag("profile.trophy.${achievement.name}"),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Box(Modifier.size(46.dp).glow(if (earned) ProfilePalette.win.copy(alpha = 0.4f) else Color.Black.copy(alpha = 0.4f), if (earned) 5.dp else 2.dp, 23.dp)
                                .background(if (earned) Brush.radialGradient(listOf(rgb(1.0, 0.9, 0.62), rgb(0.72, 0.48, 0.16), rgb(0.36, 0.22, 0.08)))
                                    else Brush.linearGradient(listOf(Color.Black.copy(alpha = 0.5f), Color.Black.copy(alpha = 0.5f))), CircleShape)
                                .border(2.dp, if (earned) TavernPalette.brassLine else Brush.linearGradient(listOf(Color.Gray.copy(alpha = 0.5f), Color.Gray.copy(alpha = 0.5f))), CircleShape),
                                contentAlignment = Alignment.Center) {
                                SfImage(achievementIcon(achievement), if (earned) rgb(0.30, 0.15, 0.04) else Color.Gray.copy(alpha = 0.55f), 18.dp)
                            }
                            Box(Modifier.height(24.dp).alpha(if (earned) 0.95f else 0.45f)) {
                                FitText(achievement.title, sf(9f, SfWeight.heavy, SfDesign.SERIF), color = parchment, maxLines = 2, minimumScale = 0.7f, textAlign = TextAlign.Center)
                            }
                        }
                    }
                    repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                }
                Box(Modifier.fillMaxWidth().height(7.dp).glow(Color.Black.copy(alpha = 0.6f), 3.dp, 0.dp)
                    .background(Brush.verticalGradient(listOf(rgb(0.55, 0.34, 0.16), rgb(0.28, 0.15, 0.06)))))
            }
        }
        Text(chosen?.let { "${it.title}: ${it.detail}" } ?: "Tap a coin to read what it is for.", Modifier.fillMaxWidth().defaultMinSize(minHeight = 32.dp).alpha(if (chosen == null) 0.55f else 0.9f)
            .testTag("profile.trophyNote"), color = parchment, style = sf(12f, SfWeight.semibold, SfDesign.SERIF))
    }
}

// MARK: Games

/**
 * One finished game as a card: the commander's art, the result stamp, who it was against and when. A game with a
 * detailed record opens it (`onOpenDetail`); any other opens its details in place.
 */
@Composable
fun ProfileGameCard(game: ProfileGame, tag: String, openPlayer: ((String) -> Unit)? = null, onOpenDetail: (() -> Unit)? = null) {
    var expanded by remember { mutableStateOf(false) }
    val detailed = onOpenDetail != null
    val opponentText = game.opponents.map { if (it.hidden) "a player" else it.name }.let { if (it.size <= 1) it.firstOrNull() ?: "Opponent" else "${it.size} opponents" }
    val modeText = when (game.mode) { PlayMode.QUICK -> "Quick"; PlayMode.RANKED -> if (game.vsHuman) "Ranked · Player" else "Ranked · AI"; PlayMode.CASUAL -> "Custom" }
    val (letter, resultName, color) = when (game.outcome) {
        RankOutcome.WIN -> Triple("W", "Won", rgb(0.25, 0.5, 0.2)); RankOutcome.LOSS -> Triple("L", "Lost", MagicPalette.oxblood); RankOutcome.DRAW -> Triple("D", "Drawn", rgb(0.35, 0.35, 0.35))
    }
    val deck = game.deckName.ifEmpty { game.commander ?: "" }
    val delta = game.rankDelta?.takeIf { it != 0 }
    val label = "$resultName against $opponentText, $deck, $modeText, ${formatShortDate(game.date)}" + (delta?.let { ", ${if (it > 0) "+" else ""}$it pips" } ?: "")
    Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.32f), RoundedCornerShape(12.dp)).border(1.dp, TavernPalette.brass.copy(alpha = 0.45f), RoundedCornerShape(12.dp))) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 76.dp).clip(RoundedCornerShape(12.dp))
            .clickable { if (onOpenDetail != null) onOpenDetail() else expanded = !expanded }
            .padding(10.dp).semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }.testTag(tag),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(58.dp).clip(RoundedCornerShape(9.dp)).background(Brush.verticalGradient(listOf(MagicPalette.iron, MagicPalette.leather)))
                .border(1.5.dp, TavernPalette.brassLine, RoundedCornerShape(9.dp)), contentAlignment = Alignment.Center) {
                val placeholder: @Composable () -> Unit = { SfImage("person.fill", parchment.copy(alpha = 0.4f), 20.dp) }
                if (game.commander != null) CardArtwork(game.commander!!, Modifier.fillMaxSize(), artOnly = true, placeholder = placeholder) else placeholder()
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("vs $opponentText", color = parchment, style = sf(15f, SfWeight.heavy, SfDesign.SERIF), maxLines = 1)
                Text(deck.ifEmpty { "Deck" }, Modifier.alpha(0.8f), color = parchment, style = sf(12f, SfWeight.semibold, SfDesign.SERIF), maxLines = 1)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    TavernTag(modeText.uppercase(), leather = true)
                    Text(formatShortDate(game.date), Modifier.alpha(0.65f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF), maxLines = 1)
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.size(34.dp).background(color, CircleShape).border(1.2.dp, TavernPalette.brass.copy(alpha = 0.8f), CircleShape), contentAlignment = Alignment.Center) {
                    Text(letter, color = Color.White, style = sf(17f, SfWeight.black, SfDesign.SERIF))
                }
                if (delta != null) Text(if (delta > 0) "+$delta" else "$delta", color = if (delta > 0) rgb(0.6, 0.95, 0.55) else rgb(1.0, 0.55, 0.45),
                    style = sf(12f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
                else if (detailed) SfImage("chart.bar.fill", BrandTheme.ember, 12.dp)
            }
        }
        if (expanded && !detailed) Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(TavernPalette.brass.copy(alpha = 0.35f)))
            for (opponent in game.opponents) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                opponent.commander?.let { commander ->
                    Box(Modifier.size(30.dp).clip(CircleShape).border(1.dp, TavernPalette.brass.copy(alpha = 0.6f), CircleShape).clearAndSetSemantics {}) {
                        CardArtwork(commander, Modifier.fillMaxSize(), artOnly = true)
                    }
                }
                Column(Modifier.weight(1f)) {
                    if (openPlayer != null && !opponent.isAI && !opponent.hidden) Text(opponent.name, Modifier.defaultMinSize(minHeight = 32.dp).clickable { openPlayer(opponent.name) }
                        .semantics { contentDescription = "${opponent.name}, opens their profile"; role = Role.Button }.testTag("$tag.opponent.${opponent.name}"),
                        color = BrandTheme.ember, style = sf(13f, SfWeight.heavy, SfDesign.SERIF).copy(textDecoration = TextDecoration.Underline))
                    else Text(opponent.name, color = parchment, style = sf(13f, SfWeight.heavy, SfDesign.SERIF))
                    opponent.commander?.let { Text(it, Modifier.alpha(0.7f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic), maxLines = 1) }
                }
                if (opponent.isAI) TavernTag("AI", leather = true)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                game.turns?.let { Text("$it turns", Modifier.alpha(0.7f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF)) }
                Text(longDate.format(Instant.ofEpochMilli(game.date)), Modifier.alpha(0.7f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF))
            }
            if (game.opponents.isEmpty()) Text("Opponents weren't recorded for this game.", Modifier.alpha(0.55f), color = parchment,
                style = sf(11f, SfWeight.regular, SfDesign.SERIF).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic))
        }
    }
}

/** A line of rank: the badge, the division, the season and the record, for a profile's top. */
@Composable
fun ProfileRankSummary(position: RankPosition, seasonName: String, wins: Int, losses: Int, peak: RankPosition) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        RankBadge(position, 96.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(position.title, style = sf(22f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(rgb(1.0, 0.9, 0.62), position.tier.tint))))
            Text("Season $seasonName", Modifier.alpha(0.8f), color = parchment, style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
            Text("Ranked $wins–$losses · Peak ${peak.title}", color = parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
        }
    }
}

/** An empty picture's note: a line saying what will fill it. */
@Composable
fun ProfileEmptyNote(text: String, icon: String = "sparkles") {
    Row(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.28f), RoundedCornerShape(10.dp))
        .border(1.dp, TavernPalette.brass.copy(alpha = 0.3f), RoundedCornerShape(10.dp)).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(icon, TavernPalette.brass, 16.dp)
        Text(text, Modifier.weight(1f).alpha(0.75f), color = parchment, style = sf(13f, SfWeight.regular, SfDesign.SERIF))
    }
}

/** A horizontal row of chips that scrolls. */
@Composable
fun ChipRow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).defaultMinSize(minHeight = 44.dp).padding(horizontal = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { content() }
}
