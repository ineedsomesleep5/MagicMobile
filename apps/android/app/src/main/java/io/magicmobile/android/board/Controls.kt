package io.magicmobile.android.board

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.magicmobile.android.R
import io.magicmobile.android.game.GameLogPresentation
import io.magicmobile.android.game.GameRulesPresentation
import io.magicmobile.android.game.GameRulesSymbols
import io.magicmobile.android.game.PromptDisplayText
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfSymbols
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/**
 * The board's button styles and text helpers from ContentView.swift (CompactActionButtonStyle,
 * PanelActionButtonStyle, PrimaryButtonStyle, SecondaryButtonStyle, IconButtonStyle,
 * PromptButtonLabel, PromptMiniLabel, SurfaceChip) and GameLogPresentation.swift's views.
 */

/** A button that knows it is pressed, and plays a press sound like the iOS `.pressSound` modifier. */
@Composable
fun PressableBox(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, pressSound: GameSound? = null,
                 content: @Composable (pressed: Boolean) -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    LaunchedEffect(pressed) { if (pressed && pressSound != null) GameAudio.play(pressSound) }
    Box(modifier.clickable(interaction, null, enabled, onClick = onClick), contentAlignment = Alignment.Center) { content(pressed) }
}

/** CompactActionButtonStyle: a capsule that reads as disabled (dimmed, desaturated) wherever it is used. */
@Composable
fun CompactActionButton(onClick: () -> Unit, modifier: Modifier = Modifier, isPrimary: Boolean = false, isDanger: Boolean = false,
                        enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    PressableBox(onClick, modifier, enabled) { pressed ->
        val background = when {
            isDanger -> if (pressed) MagicPalette.oxblood.copy(alpha = 0.66f) else MagicPalette.oxblood.copy(alpha = 0.84f)
            isPrimary -> if (pressed) MagicPalette.brass.copy(alpha = 0.70f) else MagicPalette.antiqueGold.copy(alpha = 0.88f)
            else -> if (pressed) MagicPalette.panelParchment.copy(alpha = 0.18f) else MagicPalette.iron.copy(alpha = 0.58f)
        }
        CompositionLocalProvider(LocalContentColor provides Color.White.copy(alpha = if (enabled) 1f else 0.55f)) {
            Row(Modifier.defaultMinSize(minWidth = if (isPrimary) 112.dp else 94.dp, minHeight = 44.dp)
                .colorAdjust(if (enabled) 1f else 0.1f)
                .alpha(if (pressed) 0.82f else if (enabled) 1f else 0.5f)
                .background(background, CircleShape)
                .padding(horizontal = if (isPrimary) 15.dp else 12.dp, vertical = if (isPrimary) 10.dp else 8.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically, content = content)
        }
    }
}

/** Text styled like a compact action label (rounded, black weight). */
@Composable
fun CompactActionText(text: String, isPrimary: Boolean = false, color: Color = LocalContentColor.current) {
    FitText(text, sf(if (isPrimary) 15f else 13f, SfWeight.black, SfDesign.ROUNDED), color = color, minimumScale = 0.7f)
}

/** PanelActionButtonStyle: full-width option rows in prompt panels. */
@Composable
fun PanelActionButton(onClick: () -> Unit, modifier: Modifier = Modifier, isPrimary: Boolean = false, isDanger: Boolean = false,
                      compact: Boolean = false, enabled: Boolean = true, content: @Composable () -> Unit) {
    PressableBox(onClick, modifier, enabled) { pressed ->
        val shape = RoundedCornerShape(7.dp)
        val background: Brush = when {
            isDanger -> Brush.linearGradient(listOf(MagicPalette.oxblood.copy(alpha = if (pressed) 0.68f else 0.86f), MagicPalette.oxblood.copy(alpha = if (pressed) 0.68f else 0.86f)))
            // Deep bronze keeps white labels readable (light gold behind white text was not).
            isPrimary -> if (pressed) Brush.verticalGradient(listOf(rgb(0.36, 0.24, 0.08), rgb(0.36, 0.24, 0.08)))
            else Brush.verticalGradient(listOf(rgb(0.56, 0.40, 0.15), rgb(0.36, 0.24, 0.08)))
            else -> Brush.linearGradient(List(2) { if (pressed) MagicPalette.panelParchment.copy(alpha = 0.18f) else MagicPalette.iron.copy(alpha = 0.58f) })
        }
        CompositionLocalProvider(LocalContentColor provides Color.White) {
            Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (pressed) 0.82f else if (enabled) 1f else 0.5f)
                .background(background, shape)
                .border(if (isPrimary) 1.4.dp else 1.dp, if (isPrimary && !isDanger) MagicPalette.antiqueGold.copy(alpha = 0.95f) else Color.White.copy(alpha = 0.10f), shape)
                .padding(horizontal = if (compact) 6.dp else 7.dp, vertical = if (compact) 4.dp else 5.dp), contentAlignment = Alignment.CenterStart) { content() }
        }
    }
}

/** PrimaryButtonStyle (gold, confirm press sound). */
@Composable
fun PrimaryGameButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    PressableBox(onClick, modifier, enabled, pressSound = GameSound.UI_CONFIRM) { pressed ->
        val shape = RoundedCornerShape(8.dp)
        CompositionLocalProvider(LocalContentColor provides Color.White) {
            Row(Modifier.defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f)
                .background(if (pressed) MagicPalette.brass.copy(alpha = 0.70f) else MagicPalette.antiqueGold.copy(alpha = 0.88f), shape)
                .border(1.dp, MagicPalette.borderBronze.copy(alpha = 0.50f), shape).padding(horizontal = 15.dp, vertical = 11.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically, content = content)
        }
    }
}

@Composable
fun SecondaryGameButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    PressableBox(onClick, modifier, enabled) { pressed ->
        val shape = RoundedCornerShape(8.dp)
        CompositionLocalProvider(LocalContentColor provides Color.White) {
            Row(Modifier.defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.5f)
                .background(Color.White.copy(alpha = if (pressed) 0.18f else 0.09f), shape).border(1.dp, Color.White.copy(alpha = 0.14f), shape)
                .padding(horizontal = 15.dp, vertical = 11.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically, content = content)
        }
    }
}

val gameButtonTextStyle: TextStyle get() = SfText.callout(SfWeight.black)

/** IconButtonStyle: a dark circle in a 44 pt touch target. */
@Composable
fun GameIconButton(symbol: String, onClick: () -> Unit, modifier: Modifier = Modifier, small: Boolean = false, contentDescription: String? = null) {
    PressableBox(onClick, modifier.size(44.dp).semantics { if (contentDescription != null) this.contentDescription = contentDescription }) { pressed ->
        Box(Modifier.size(if (small) 28.dp else 42.dp).background(if (pressed) Color.White.copy(alpha = 0.18f) else Color.Black.copy(alpha = 0.45f), CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.16f), CircleShape), contentAlignment = Alignment.Center) {
            SfImage(symbol, Color.White, if (small) 13.dp else 18.dp)
        }
    }
}

@Composable
fun PromptMiniLabel(title: String) {
    Text(title.uppercase(), color = Color.White.copy(alpha = 0.54f), style = sf(7f, SfWeight.black))
}

@Composable
fun PromptButtonLabel(title: String, subtitle: String? = null, systemImage: String? = null, isPending: Boolean = false,
                      cardName: String? = null, large: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = if (large) 6.dp else 0.dp), horizontalArrangement = Arrangement.spacedBy(if (large) 10.dp else 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (isPending) {
            CircularProgressIndicator(Modifier.size(if (large) 16.dp else 12.dp), color = Color.White, strokeWidth = 1.5.dp)
        } else if (systemImage != null) {
            SfImage(systemImage, MagicPalette.parchment, if (large) 17.dp else 13.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val text = PromptDisplayText.clean(title)
            val style = sf(if (large) 15f else 12f, if (large) SfWeight.semibold else SfWeight.bold)
            // Mana, tap and other symbols render as icons, never as {T}.
            if (text.contains("{")) GameRulesText(text, cardName = cardName, symbolSize = if (large) 17.dp else 13.dp, style = style,
                maxLines = if (large) 8 else 3, color = Color.White)
            else FitText(text, style, color = Color.White, maxLines = if (large) 8 else 3, minimumScale = if (large) 0.9f else 0.7f)
            if (!subtitle.isNullOrEmpty()) {
                FitText(PromptDisplayText.clean(subtitle), sf(if (large) 12f else 9f, SfWeight.semibold), Modifier.alpha(0.72f), color = Color.White,
                    maxLines = if (large) 3 else 1, minimumScale = 0.7f)
            }
        }
    }
}

@Composable
fun SurfaceChip(title: String, value: String, systemImage: String? = null, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(7.dp)
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 32.dp).background(MagicPalette.iron.copy(alpha = 0.54f), shape)
        .border(1.dp, MagicPalette.borderBronze.copy(alpha = 0.34f), shape).padding(horizontal = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (systemImage != null) SfImage(systemImage, MagicPalette.antiqueGold.copy(alpha = 0.86f), 10.dp)
        Column(Modifier.weight(1f)) {
            FitText(value, sf(10f, SfWeight.black), color = MagicPalette.parchment, minimumScale = 0.6f)
            Text(title.uppercase(), color = MagicPalette.parchment.copy(alpha = 0.56f), style = sf(6f, SfWeight.black), maxLines = 1)
        }
    }
}

/** An inline rules symbol: bundled WUBRGC art, otherwise a drawn disc (split for hybrids, Φ for Phyrexian). */
@Composable
fun RulesSymbol(code: String, size: Dp) {
    val bundled = when (code) {
        "W" -> R.drawable.mana_w; "U" -> R.drawable.mana_u; "B" -> R.drawable.mana_b; "R" -> R.drawable.mana_r
        "G" -> R.drawable.mana_g; "C" -> R.drawable.mana_c; else -> null
    }
    if (bundled != null) { Image(painterResource(bundled), null, Modifier.size(size)); return }
    val colors = mapOf("W" to rgb(0.96, 0.90, 0.72), "U" to rgb(0.55, 0.78, 0.92), "B" to rgb(0.63, 0.63, 0.63),
        "R" to rgb(0.94, 0.57, 0.44), "G" to rgb(0.57, 0.77, 0.55))
    val parts = code.split("/")
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val radius = this.size.minDimension / 2 - 0.5f
            val circle = Path().apply { addOval(androidx.compose.ui.geometry.Rect(Offset(this@Canvas.size.width / 2, this@Canvas.size.height / 2), radius)) }
            clipPath(circle) {
                drawRect(colors[parts[0]] ?: rgb(0.85, 0.85, 0.85))
                val second = if (parts.size > 1) colors[parts[1]] else null
                if (second != null) drawPath(Path().apply { moveTo(this@Canvas.size.width, 0f); lineTo(this@Canvas.size.width, this@Canvas.size.height)
                    lineTo(0f, this@Canvas.size.height); close() }, second)
            }
            drawPath(circle, Color.Black.copy(alpha = 0.65f), style = Stroke(0.7.dp.toPx()))
        }
        val glyph = mapOf("T" to "arrow.turn.down.right", "Q" to "arrow.uturn.backward", "S" to "sparkle")[code]
        if (glyph != null) SfImage(glyph, Color.Black, size * 0.64f)
        else {
            val label = if (parts.last() == "P") "Φ" else code
            Text(label, color = Color.Black, style = sf(size.value * (if (label.length > 2) 0.40f else 0.62f), SfWeight.semibold), maxLines = 1)
        }
    }
}

/** GameRulesText: rules with inline mana and tap symbols; screen readers hear the spoken symbol names. */
@Composable
fun GameRulesText(source: String, modifier: Modifier = Modifier, cardName: String? = null, isHidden: Boolean = false, symbolSize: Dp = 16.dp,
                  style: TextStyle = SfText.body(), color: Color = LocalContentColor.current, maxLines: Int = Int.MAX_VALUE) {
    val symbols = remember(source, cardName, isHidden) { GameRulesSymbols(GameRulesPresentation(source, cardName, isHidden)) }
    val inline = HashMap<String, InlineTextContent>()
    val text = buildAnnotatedString {
        symbols.fragments.forEachIndexed { index, fragment ->
            val code = fragment.code
            if (code != null) {
                val key = "symbol-$index"
                inline[key] = InlineTextContent(Placeholder(symbolSize.value.sp, symbolSize.value.sp, PlaceholderVerticalAlign.TextCenter)) { RulesSymbol(code, symbolSize) }
                appendInlineContent(key, fragment.literal)
            } else append(fragment.literal)
        }
    }
    Text(text, modifier.semantics { contentDescription = symbols.accessibilityText }, color = color, style = style, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis, inlineContent = inline)
}

/** GameLogText: engine log spans, players teal and bold, cards gold and italic; tappable card names when inspection is offered. */
@Composable
fun GameLogText(message: String, modifier: Modifier = Modifier, usesDarkBackground: Boolean = true, style: TextStyle = SfText.footnote(),
                onInspect: ((GameLogPresentation.CardReference) -> Unit)? = null) {
    val presentation = remember(message) { GameLogPresentation(message) }
    val foreground = if (usesDarkBackground) Color.White else Color.Black
    val player = if (usesDarkBackground) rgb(0.45, 0.86, 0.82) else rgb(0.0, 0.34, 0.32)
    val card = if (usesDarkBackground) rgb(1.0, 0.84, 0.46) else rgb(0.40, 0.25, 0.04)
    val text: AnnotatedString = buildAnnotatedString {
        presentation.spans.forEachIndexed { index, span ->
            val color = when (span.role) { GameLogPresentation.Role.PLAYER -> player; GameLogPresentation.Role.CARD -> card; else -> foreground }
            val link = if (onInspect != null) presentation.inspectionURL(index) else null
            if (link != null) pushStringAnnotation("inspect", link)
            withStyle(SpanStyle(color = color, fontWeight = if (span.bold || span.role == GameLogPresentation.Role.PLAYER) FontWeight.Bold else null,
                fontStyle = if (span.italic || span.role == GameLogPresentation.Role.CARD) FontStyle.Italic else null)) { append(span.text) }
            if (link != null) pop()
        }
    }
    if (onInspect == null) {
        Text(text, modifier.semantics { contentDescription = presentation.plainText }, style = style)
    } else {
        @Suppress("DEPRECATION")
        androidx.compose.foundation.text.ClickableText(text, modifier, style = style) { offset ->
            text.getStringAnnotations("inspect", offset, offset).firstOrNull()?.let { annotation ->
                presentation.cardReference(annotation.item)?.let(onInspect)
            }
        }
    }
}

