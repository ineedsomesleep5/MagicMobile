package io.magicmobile.android.studio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.inset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernCoin
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.tavernFill
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.drawscope.withTransform
import io.magicmobile.android.R
import io.magicmobile.android.ui.drawNineSlice
import io.magicmobile.android.ui.drawStretched
import io.magicmobile.android.ui.tavernImage

/*
 * GrimoireBinder.swift: Deck Studio as a collector's binder (Caleb chose concept B of three, 2026-10-06).
 * An oxblood leather binder with brass corners holds the parchment pages; a deck's chapters are leather
 * index tabs on its outer edge; Done is a leather strap with a buckle, Save a brass plaque; the tools sit
 * on a brass rail; every card is in a sleeve with brass corner mounts and a minus, count and plus strip.
 */
object Binder {
    val oxblood = rgb(0.40, 0.09, 0.07)
    val leatherDark = rgb(0.17, 0.07, 0.045)
    val thread = rgb(0.90, 0.70, 0.40).copy(alpha = 0.55f)
    val brassLight = rgb(1.0, 0.88, 0.58)
    val brassDeep = rgb(0.50, 0.32, 0.11)
    val engraved = rgb(0.24, 0.13, 0.05)
    val emberText = rgb(1.0, 0.92, 0.70)
    /** How wide the index tabs stand out from the page (the chosen one stands further out). */
    val tabWidth = 40.dp
    /** How far each tab's leather runs in under the page's edge. */
    val tabTuck = 12.dp
    val brass: Brush get() = Brush.verticalGradient(listOf(brassLight, TavernPalette.brass, brassDeep))
    val brassPressed: Brush get() = Brush.verticalGradient(listOf(brassDeep, TavernPalette.brass, brassLight.copy(alpha = 0.8f)))
    val chapterIcons = mapOf("Cards" to "rectangle.portrait.on.rectangle.portrait.fill", "Ideas" to "lightbulb.fill",
        "Analysis" to "chart.bar.fill")
}

private fun TextStyle.onLeather(): TextStyle = copy(shadow = Shadow(Color.Black.copy(alpha = 0.7f), Offset(0f, 1.5f), 1f))
private fun TextStyle.onBrass(): TextStyle = copy(shadow = Shadow(Binder.brassLight.copy(alpha = 0.7f), Offset(0f, 1.5f), 0f))

/** Leather with a colour multiplied into it (oxblood for the cover and the strap, darker for tucked tabs). */
fun Modifier.binderLeather(dye: Color, amount: Float, shape: androidx.compose.ui.graphics.Shape = androidx.compose.ui.graphics.RectangleShape): Modifier =
    tavernFill(TavernMaterial.LEATHER, shape).drawWithContent {
        drawRect(dye.copy(alpha = amount), blendMode = BlendMode.Multiply)
        drawContent()
    }

/** The binder's oxblood leather, under the whole screen, darker towards its edges. */
fun Modifier.binderCover(): Modifier = binderLeather(Binder.oxblood, 0.55f).drawBehind {
    drawRect(Brush.radialGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.45f)), center = center,
        radius = maxOf(size.width, size.height) * 0.75f))
}

/** Which corner mounts: ornate L-shaped guards on pages, a finer L on cards, gilded acanthus leaves on plates. */
enum class BinderCornerStyle { GUARD, CARD, LEAF, BOOK }

/**
 * Brass mounts over the four corners (BinderCorners on iOS): Meshy-made art (scripts/brand/binder_parts.py) mirrored
 * for each corner. Cards wear a finer L (Caleb, 2026-10-06: "we want an L shape corner").
 */
fun Modifier.binderCorners(size: Dp, style: BinderCornerStyle = BinderCornerStyle.GUARD): Modifier = composed {
    val art = tavernImage(when (style) {
        BinderCornerStyle.CARD -> R.drawable.tavern_binder_card_corner
        BinderCornerStyle.LEAF -> R.drawable.tavern_binder_leaf_corner
        BinderCornerStyle.BOOK -> R.drawable.tavern_binder_book_corner
        BinderCornerStyle.GUARD -> R.drawable.tavern_binder_corner
    })
    drawWithContent {
        drawContent()
        val side = size.toPx() * 1.35f
        for ((fx, fy) in listOf(1f to 1f, -1f to 1f, 1f to -1f, -1f to -1f)) {
            val left = if (fx > 0f) 0f else this.size.width - side
            val top = if (fy > 0f) 0f else this.size.height - side
            withTransform({ scale(fx, fy, pivot = Offset(left + side / 2, top + side / 2)) }) {
                drawStretched(art, Offset(left, top), Size(side, side))
            }
        }
    }
}

/**
 * A page held in the binder: parchment with a dark edge, a stitched seam around it in the leather and brass
 * corner plates. [gutterStart] shades the edge that runs into the binder's spine (true: the start edge).
 */
@Composable
fun BinderPage(modifier: Modifier = Modifier, gutterStart: Boolean? = null, screen: Any? = null, content: @Composable BoxScope.() -> Unit) {
    val outer = RoundedCornerShape(13.dp); val inner = RoundedCornerShape(9.dp)
    // A page turn moves only this paper; the binder around it stays still (GrimoireStage).
    val stage = LocalGrimoireStage.current
    val page = remember { Any() }
    if (stage != null && screen != null) DisposableEffect(stage, screen) { onDispose { stage.removeBinderPage(page, screen) } }
    Box(modifier.then(if (stage != null && screen != null) Modifier.onGloballyPositioned { stage.setBinderPage(it.boundsInRoot(), page, screen) } else Modifier)
        .shadow(5.dp, outer, clip = false).background(Color.Black.copy(alpha = 0.18f), outer)
        .drawWithContent {
            drawContent()
            val inset = 0.6.dp.toPx()
            drawRoundRect(Binder.thread, Offset(inset, inset), Size(size.width - 2 * inset, size.height - 2 * inset), CornerRadius(13.dp.toPx()),
                style = Stroke(1.2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
        }.padding(5.dp)) {
        Box(Modifier.fillMaxSize().clip(inner).grimoirePaper().drawWithContent {
            drawContent()
            gutterStart?.let { start ->
                val width = 18.dp.toPx(); val ink = DeckStudioPalette.ink
                val left = if (start) 0f else size.width - width
                drawRect(Brush.horizontalGradient(if (start) listOf(ink.copy(alpha = 0.28f), ink.copy(alpha = 0.08f), Color.Transparent)
                    else listOf(Color.Transparent, ink.copy(alpha = 0.08f), ink.copy(alpha = 0.28f)), left, left + width), Offset(left, 0f), Size(width, size.height))
            }
            drawRoundRect(Color.Black.copy(alpha = 0.45f), cornerRadius = CornerRadius(9.dp.toPx()), style = Stroke(1.dp.toPx()))
        }.binderCorners(30.dp), content = content)
    }
}

/** A panel set into the page (the deck's title plate, a deck in the library): lighter paper in a thin brass edge. */
fun Modifier.binderPlate(corners: BinderCornerStyle = BinderCornerStyle.LEAF): Modifier {
    val shape = RoundedCornerShape(8.dp)
    return shadow(3.dp, shape, ambientColor = Color.Black.copy(alpha = 0.18f), spotColor = Color.Black.copy(alpha = 0.18f))
        .grimoirePaper(DeckStudioPalette.surface, grain = 0.2f, shape = shape)
        .clip(shape)
        .border(1.5.dp, Binder.brass, shape)
        .binderCorners(20.dp, corners)
}

/** Lays a child out turned a quarter clockwise, taking the turned size (a tab's label). */
private fun Modifier.quarterTurn(): Modifier = layout { measurable, _ ->
    val placeable = measurable.measure(Constraints())
    layout(placeable.height, placeable.width) {
        placeable.placeWithLayer(-(placeable.width - placeable.height) / 2, (placeable.width - placeable.height) / 2) { rotationZ = 90f }
    }
}

/**
 * The deck's chapters as leather index tabs standing out of the binder's outer edge (Caleb, 2026-10-06: "make the tabs
 * on the right look more like tabs maybe a 3d effect"): the Meshy-made stitched leather tab with its brass rivet
 * (scripts/brand/binder_parts.py), 9-sliced to each tab's height. Each tab's leather runs [Binder.tabTuck] in under the
 * page, which lies over it (give the page a higher zIndex); the chosen tab is the leather's own lively red and stands
 * furthest out, the others are dyed down to the binder's oxblood and sit further in.
 */
@Composable
fun BinderIndexTabs(chapters: List<String>, selected: String, modifier: Modifier = Modifier, tabHeight: Dp = 102.dp, choose: (String) -> Unit) {
    val art = tavernImage(R.drawable.tavern_binder_tab)
    val chosenTint = remember { ColorFilter.tint(rgb(1.0, 0.93, 0.88), BlendMode.Modulate) }
    val restingTint = remember { ColorFilter.tint(rgb(0.6, 0.52, 0.5), BlendMode.Modulate) }
    BoxWithConstraints(modifier.width(Binder.tabWidth)) {
    val gap = if (tabHeight < 100.dp) 4.dp else 6.dp
    // On a short spread the tabs share the page's height rather than running off its foot.
    val height = if (constraints.hasBoundedHeight) minOf(tabHeight, (maxHeight - gap * (chapters.size - 1)) / maxOf(1, chapters.size)) else tabHeight
    Column(Modifier.width(Binder.tabWidth).semantics { contentDescription = "Deck workspace" }, verticalArrangement = Arrangement.spacedBy(gap)) {
        for (chapter in chapters) {
            val chosen = chapter == selected
            val shape = RoundedCornerShape(topStart = 0.dp, bottomStart = 0.dp, topEnd = 11.dp, bottomEnd = 11.dp)
            Column(Modifier.width(Binder.tabWidth - if (chosen) 0.dp else 6.dp).height(height)
                .shadow(if (chosen) 4.dp else 1.5.dp, shape, clip = false)
                // The art's top cap keeps the rounded corner and the rivet whole; only plain leather stretches.
                .drawBehind {
                    inset(left = -Binder.tabTuck.toPx(), top = 0f, right = 0f, bottom = 0f) {
                        drawNineSlice(art, intArrayOf(36, 186, 42, 42), floatArrayOf(12f, 62f, 14f, 14f), colorFilter = if (chosen) chosenTint else restingTint)
                    }
                }
                .clickable(role = Role.Tab) { choose(chapter) }
                .semantics(mergeDescendants = true) { contentDescription = chapter; this.selected = chosen },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (height < 100.dp) 5.dp else 8.dp, Alignment.CenterVertically)) {
                val tint = if (chosen) Binder.brassLight else TavernPalette.parchment.copy(alpha = 0.8f)
                SfImage(Binder.chapterIcons[chapter] ?: "book.closed.fill", tint, 13.dp)
                Text(chapter, Modifier.quarterTurn().clearAndSetSemantics {}, color = tint, maxLines = 1,
                    style = sf(13f, SfWeight.bold, SfDesign.SERIF).onLeather())
            }
        }
    }
    }
}

/** "Done" (or "Cancel") as a leather strap with a brass buckle. */
@Composable
fun BinderStrapButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(topStart = 4.dp, bottomStart = 4.dp, topEnd = 12.dp, bottomEnd = 12.dp)
    Row(modifier.defaultMinSize(minHeight = 44.dp).alpha(if (!enabled) 0.45f else if (pressed) 0.8f else 1f)
        .clickable(interaction, null, enabled = enabled, role = Role.Button) { onClick() }, verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.defaultMinSize(minHeight = 40.dp).shadow(3.dp, shape).binderLeather(Binder.oxblood, 0.55f, shape)
            .drawWithContent {
                drawContent()
                val inset = 3.dp.toPx()
                drawRoundRect(Binder.thread, Offset(inset, inset), Size(size.width - 2 * inset, size.height - 2 * inset), CornerRadius(9.dp.toPx()),
                    style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))))
            }.padding(start = 10.dp, end = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // The buckle: a brass frame with its pin.
            Box(Modifier.size(16.dp, 22.dp).drawBehind {
                drawRoundRect(Binder.brass, Offset(1.5.dp.toPx(), 1.5.dp.toPx()), Size(size.width - 3.dp.toPx(), size.height - 3.dp.toPx()),
                    CornerRadius(3.dp.toPx()), style = Stroke(3.dp.toPx()))
                drawRoundRect(Binder.brass, Offset(size.width / 2 - 1.25.dp.toPx(), 4.dp.toPx()), Size(2.5.dp.toPx(), size.height - 8.dp.toPx()),
                    CornerRadius(1.25.dp.toPx()))
            })
            Text(title, color = TavernPalette.parchment, style = sf(15f, SfWeight.bold, SfDesign.SERIF).onLeather(), maxLines = 1)
        }
    }
}

/**
 * A brass plaque with engraved lettering (Save), or a square brass toggle with an engraved symbol (the rail's
 * tools). [on] presses it in. With [onClick] null it is only a label (a menu's).
 */
@Composable
fun BinderPlaque(modifier: Modifier = Modifier, title: String? = null, icon: String? = null, square: Boolean = false, on: Boolean = false,
                 enabled: Boolean = true, label: String? = null, onClick: (() -> Unit)? = null) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val sunk = pressed || on
    val shape = RoundedCornerShape(if (square) 7.dp else 8.dp)
    Box(modifier.defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
        .then(if (onClick != null) Modifier.clickable(interaction, null, enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onClick() } else Modifier)
        .semantics(mergeDescendants = true) {
            (label ?: title)?.let { contentDescription = it }
            if (on) selected = true
        }, contentAlignment = Alignment.Center) {
        Row(Modifier.then(if (square) Modifier.size(38.dp) else Modifier.height(34.dp).padding(horizontal = 0.dp))
            .alpha(if (enabled) 1f else 0.55f)
            .shadow(if (sunk) 1.dp else 2.5.dp, shape)
            .background(if (sunk) Binder.brassPressed else Binder.brass, shape)
            .border(0.8.dp, Color.Black.copy(alpha = 0.5f), shape)
            .drawWithContent {
                drawContent()
                val inset = 2.5.dp.toPx()
                drawRoundRect(Binder.brassDeep.copy(alpha = 0.55f), Offset(inset, inset), Size(size.width - 2 * inset, size.height - 2 * inset),
                    CornerRadius(5.dp.toPx()), style = Stroke(0.8.dp.toPx()))
            }
            .padding(horizontal = if (square) 0.dp else 14.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            val ink = if (enabled) Binder.engraved else Binder.engraved.copy(alpha = 0.6f)
            icon?.let { SfImage(it, ink, if (square) 16.dp else 14.dp) }
            title?.let { Text(it, color = ink, style = sf(15f, SfWeight.heavy, SfDesign.SERIF).onBrass(), maxLines = 1) }
        }
    }
}

/** A brass rail: the strip the binder's tools are mounted on, with a rivet at each end. */
@Composable
fun BinderRail(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Column(modifier.fillMaxWidth().shadow(3.dp, shape).binderLeather(Binder.leatherDark, 0.35f, shape)
        .border(3.dp, Binder.brass, shape)
        .drawWithContent {
            drawContent()
            val r = 2.5.dp.toPx()
            for (x in listOf(6.5.dp.toPx(), size.width - 6.5.dp.toPx())) {
                drawCircle(Binder.brass, r, Offset(x, size.height / 2)); drawCircle(Binder.brassDeep, r, Offset(x, size.height / 2), style = Stroke(0.6.dp.toPx()))
            }
        }.padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

/** The rail's search field: a dark inset well with a brass magnifying glass. */
@Composable
fun BinderSearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, tag: String? = null,
                      clearLabel: String = "Clear search") {
    val focus = LocalFocusManager.current
    val shape = RoundedCornerShape(8.dp)
    Row(modifier.fillMaxWidth().height(40.dp).background(Color.Black.copy(alpha = 0.5f), shape).border(1.dp, Color.Black.copy(alpha = 0.6f), shape)
        .padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(24.dp).drawBehind {
            val c = Offset(size.width * 0.42f, size.height * 0.42f)
            drawCircle(Binder.brass, 6.5.dp.toPx(), c, style = Stroke(2.5.dp.toPx()))
            drawLine(Binder.brass, Offset(c.x + 5.dp.toPx(), c.y + 5.dp.toPx()), Offset(c.x + 10.dp.toPx(), c.y + 10.dp.toPx()), 3.dp.toPx())
        }.clearAndSetSemantics {})
        val style = sf(15f, SfWeight.regular, SfDesign.SERIF)
        BasicTextField(value, onChange, Modifier.weight(1f).then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .semantics { contentDescription = placeholder }, singleLine = true,
            textStyle = style.copy(color = TavernPalette.parchment), cursorBrush = SolidColor(Binder.brassLight),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onAny = { focus.clearFocus() }),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) Text(placeholder, color = TavernPalette.parchment.copy(alpha = 0.5f), style = style, maxLines = 1)
                    inner()
                }
            })
        if (value.isNotEmpty()) Box(Modifier.size(32.dp, 40.dp).clickable(role = Role.Button) { onChange("") }.semantics { contentDescription = clearLabel },
            contentAlignment = Alignment.Center) { SfImage("xmark.circle.fill", TavernPalette.parchment.copy(alpha = 0.7f), 17.dp) }
    }
}

/** Which cards the binder's pages show: the deck's own, or every card there is to add. */
enum class BinderShelf { DECK, ALL }

/** The two shelves as a switch on the rail. */
@Composable
fun BinderShelfSwitch(shelf: BinderShelf, onChange: (BinderShelf) -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    val shape = RoundedCornerShape(9.dp)
    // compact: symbols only, for a short sideways page (the titles stay for TalkBack).
    Row((if (compact) modifier else modifier.fillMaxWidth()).background(Color.Black.copy(alpha = 0.5f), shape).border(1.5.dp, Binder.brass, shape).padding(3.dp)
        .semantics { contentDescription = "Show cards" }) {
        for ((value, title, icon) in listOf(Triple(BinderShelf.DECK, "My deck", "rectangle.stack.fill"), Triple(BinderShelf.ALL, "All cards", "books.vertical.fill"))) {
            val chosen = shelf == value
            val inner = RoundedCornerShape(7.dp)
            Row((if (compact) Modifier.width(42.dp).height(34.dp) else Modifier.weight(1f).height(36.dp))
                .then(if (chosen) Modifier.tavernFill(TavernMaterial.EMBER, inner).border(1.dp, Binder.brassLight.copy(alpha = 0.6f), inner) else Modifier)
                .clickable(role = Role.Tab) { onChange(value) }
                .semantics(mergeDescendants = true) { contentDescription = title; selected = chosen },
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                val tint = if (chosen) Binder.emberText else TavernPalette.parchment.copy(alpha = 0.7f)
                SfImage(icon, tint, 14.dp)
                if (!compact) Text(title, color = tint, style = sf(14f, SfWeight.bold, SfDesign.SERIF).onLeather(), maxLines = 1)
            }
        }
    }
}

/** Mana values 0 to 7+ as brass coins: tap one or more to see only those costs; none shows all. */
@Composable
fun BinderManaFilter(selection: Set<Int>, onChange: (Set<Int>) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().semantics { contentDescription = "Mana value filter" }) {
        for (value in 0..7) {
            val on = value in selection
            Box(Modifier.weight(1f).height(44.dp).clickable(role = Role.Button) { onChange(if (on) selection - value else selection + value) }
                .semantics(mergeDescendants = true) { contentDescription = if (value == 7) "Mana value 7 or more" else "Mana value $value"; selected = on },
                contentAlignment = Alignment.Center) {
                if (on) Box(Modifier.size(36.dp).drawBehind {
                    drawCircle(Brush.radialGradient(listOf(TavernPalette.ember.copy(alpha = 0.65f), Color.Transparent)))
                })
                Box(Modifier.scale(if (on) 1.08f else 1f).alpha(if (on || selection.isEmpty()) 1f else 0.55f)) {
                    TavernCoin(value, 30.dp, Modifier.clearAndSetSemantics {})
                    if (value == 7) Text("+", Modifier.align(Alignment.BottomEnd).padding(end = 0.dp), color = Binder.engraved,
                        style = sf(12f, SfWeight.black, SfDesign.SERIF))
                }
            }
        }
    }
}

object BinderMana {
    /** Whether a card of this mana value passes the coins. */
    fun matches(manaValue: Double?, selection: Set<Int>): Boolean {
        if (selection.isEmpty()) return true
        if (manaValue == null || !manaValue.isFinite()) return false
        return minOf(7, kotlin.math.floor(manaValue).toInt()) in selection
    }
}

/** The deck's size as a brass gauge: a segmented ember bar in brass, with the count. */
@Composable
fun BinderGauge(count: Int, modifier: Modifier = Modifier, target: Int = 100, showsCount: Boolean = true) {
    Row(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$count of $target cards" },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(14.dp).drawBehind {
            val radius = CornerRadius(size.height / 2)
            drawRoundRect(Color.Black.copy(alpha = 0.55f), cornerRadius = radius)
            val fraction = (count.toFloat() / maxOf(1, target)).coerceIn(0f, 1f)
            drawRoundRect(Brush.verticalGradient(listOf(TavernPalette.ember, rgb(0.75, 0.25, 0.08))), size = Size(size.width * fraction, size.height), cornerRadius = radius)
            for (i in 1..9) drawRect(Color.Black.copy(alpha = 0.35f), Offset(size.width * i / 10f, 0f), Size(1.dp.toPx(), size.height))
            drawRoundRect(Binder.brass, Offset(1.dp.toPx(), 1.dp.toPx()), Size(size.width - 2.dp.toPx(), size.height - 2.dp.toPx()), radius, style = Stroke(2.dp.toPx()))
        })
        if (showsCount) Text("$count/$target", color = DeckStudioPalette.ink, style = sf(13f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum"))
    }
}

/**
 * A card in its sleeve: the art in a translucent pocket held by brass corner mounts, and under it a strip with a
 * brass minus, the count and a brass plus. Tapping the card's right or left half does the same as the strip.
 * A card that cannot be changed here (a read-only deck, or while selecting) is one button, [tapLabel].
 * A long press shows the large preview with the card's actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BinderSleeve(name: String, quantity: Int, card: CardInfo?, modifier: Modifier = Modifier, notes: List<String> = emptyList(), selected: Boolean? = null,
                 canEdit: Boolean = true, addLabel: String = "Add one $name", removeLabel: String = "Remove one $name", tapLabel: String = name,
                 add: () -> Unit, remove: () -> Unit, tap: () -> Unit, preview: () -> Unit = {}) {
    val editing = canEdit && selected == null
    val pocket = RoundedCornerShape(7.dp)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.fillMaxWidth().shadow(3.dp, pocket)
            .background(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.30f), Color.White.copy(alpha = 0.08f), Color.White.copy(alpha = 0.20f))), pocket)
            .border(0.8.dp, Color.White.copy(alpha = 0.4f), pocket)
            .binderCorners(16.dp, BinderCornerStyle.CARD)
            .padding(4.dp)) {
            DeckStudioCardImage(name, card, Modifier.fillMaxWidth())
            if (selected != null) Box(Modifier.align(Alignment.TopStart).padding(3.dp)
                .background(if (selected) DeckStudioPalette.surfaceElevated else DeckStudioPalette.ink.copy(alpha = 0.35f), CircleShape)) {
                SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) DeckStudioPalette.accent else DeckStudioPalette.surfaceElevated, 20.dp)
            } else if (notes.isNotEmpty()) Box(Modifier.align(Alignment.TopStart).padding(3.dp).size(22.dp)
                .background(DeckStudioPalette.warning.copy(alpha = 0.92f), CircleShape)
                .semantics { contentDescription = "Quick check: " + notes.joinToString(", ") }, contentAlignment = Alignment.Center) {
                SfImage("exclamationmark.triangle.fill", DeckStudioPalette.surfaceElevated, 11.dp)
            }
            if (selected == true) Box(Modifier.matchParentSize().border(3.dp, DeckStudioPalette.accent, pocket))
            if (editing) Row(Modifier.matchParentSize()) {
                // The card's halves: left takes a copy away, right adds one. The strip says the same to TalkBack.
                Box(Modifier.weight(1f).fillMaxHeight().combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview) {
                    if (quantity > 0) remove()
                }.clearAndSetSemantics {})
                Box(Modifier.weight(1f).fillMaxHeight().combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview) { add() }
                    .clearAndSetSemantics {})
            } else Box(Modifier.matchParentSize().combinedClickable(remember { MutableInteractionSource() }, null, onLongClick = preview, onClick = tap)
                .semantics { contentDescription = tapLabel; role = Role.Button; if (selected != null) this.selected = selected })
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            if (editing) SleeveCoin("minus", removeLabel, quantity > 0) { remove() }
            Text("$quantity", Modifier.widthIn(min = 28.dp).background(Color.Black.copy(alpha = 0.62f), CircleShape).border(1.dp, Binder.brass, CircleShape)
                .padding(horizontal = 6.dp, vertical = 2.dp).semantics { contentDescription = "$name, quantity $quantity" },
                color = TavernPalette.parchment, style = sf(14f, SfWeight.heavy, SfDesign.SERIF).copy(fontFeatureSettings = "tnum",
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center), maxLines = 1)
            if (editing) SleeveCoin("plus", addLabel, true) { add() }
        }
    }
}

/** A brass coin button under a sleeve; a minus with nothing to take away keeps its place but is not there. */
@Composable
private fun SleeveCoin(symbol: String, label: String, active: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(36.dp, 34.dp).alpha(if (active) 1f else 0f)
        .then(if (active) Modifier.clickable(role = Role.Button) { onClick() }.semantics { contentDescription = label }
            else Modifier.clearAndSetSemantics {}), contentAlignment = Alignment.Center) {
        Box(Modifier.size(24.dp).shadow(1.dp, CircleShape).background(Binder.brass, CircleShape).border(0.8.dp, Binder.brassDeep, CircleShape),
            contentAlignment = Alignment.Center) { SfImage(symbol, Binder.engraved, 11.dp) }
    }
}

/** A row of sleeves; a short last row keeps the sleeve width. */
@Composable
fun <T> BinderSleeveRow(items: List<T>, columns: Int, modifier: Modifier = Modifier, sleeve: @Composable (T, Modifier) -> Unit) {
    Row(modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        for (item in items) sleeve(item, Modifier.weight(1f))
        repeat(columns - items.size) { Spacer(Modifier.weight(1f)) }
    }
}

/** The binder's head on the leather above its page: a strap at the start, the page's name, and its plaques. */
@Composable
fun BinderHead(strap: String, onStrap: () -> Unit, modifier: Modifier = Modifier, title: String? = null, strapTag: String? = null,
               strapEnabled: Boolean = true, trailing: @Composable RowScope.() -> Unit = {}) {
    // Written at the top of the page (Caleb, 2026-10-06: the head is part of the paper, so facing pages are the same
    // height and turn together); its title is in ink.
    Row(modifier.fillMaxWidth().padding(start = 6.dp, end = 6.dp, top = 8.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BinderStrapButton(strap, onStrap, if (strapTag != null) Modifier.testTag(strapTag) else Modifier, enabled = strapEnabled)
        Spacer(Modifier.weight(1f))
        title?.let {
            Text(it, Modifier.semantics { heading() }, color = DeckStudioPalette.ink, style = sf(18f, SfWeight.bold, SfDesign.SERIF),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.weight(1f))
        }
        trailing()
    }
}

/** The foot of a page Quick Add sits on: a strip of the binder's leather under a brass edge. */
fun Modifier.binderFoot(): Modifier = binderLeather(Binder.leatherDark, 0.3f).drawBehind {
    drawRect(Binder.brass, size = Size(size.width, 2.dp.toPx()))
}

// Tags, coins, notes and empty pages (GrimoireBinderControls.swift): the binder's own parts in place of the
// system's tinted capsules, plain icon buttons and empty-state views.

/**
 * A small tag in a thin brass rim on one of the kit's materials: the deck chosen for play is ember glass with Play's
 * jewel; a deck check is leather with a coloured jewel. Sized exactly like the bracket's TavernTag beside it on a deck
 * (Caleb, 2026-10-06: the two must be the same height, and Playing no bigger).
 */
@Composable
fun BinderTag(text: String, modifier: Modifier = Modifier, material: TavernMaterial = TavernMaterial.LEATHER, jewel: Boolean = false,
              accent: Color? = null) {
    val ink = when (material) {
        TavernMaterial.EMBER -> rgb(1.0, 0.94, 0.80)
        TavernMaterial.LEATHER -> rgb(0.98, 0.82, 0.48)
        TavernMaterial.PARCHMENT -> rgb(0.24, 0.12, 0.05)
    }
    Row(modifier.tavernCapsuleRim(thin = true).defaultMinSize(minHeight = 22.dp)
        .padding(1.5.dp).tavernFill(material, CircleShape)
        .padding(start = if (jewel) 3.5.dp else 10.5.dp, end = 10.5.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (jewel) androidx.compose.foundation.Image(tavernImage(R.drawable.tavern_binder_jewel), null, Modifier.size(14.dp))
        if (accent != null) {
            Box(Modifier.size(8.dp).glow(accent.copy(alpha = 0.9f), 3.dp, 4.dp)
                .background(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.9f), accent, accent.copy(alpha = 0.6f))), CircleShape))
        }
        Text(text, color = ink, maxLines = 1, style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 0.8f))
    }
}

/** A symbol struck into a brass coin. */
@Composable
fun BinderStamp(icon: String, modifier: Modifier = Modifier, size: Dp = 28.dp) {
    val ring = size * 0.08f
    Box(modifier.size(size).shadow(1.5.dp, CircleShape).background(Binder.brass, CircleShape).border(0.8.dp, Color.Black.copy(alpha = 0.5f), CircleShape)
        .drawWithContent {
            drawContent()
            drawCircle(Binder.brassDeep.copy(alpha = 0.55f), radius = this.size.minDimension / 2 - ring.toPx(), style = Stroke(0.8.dp.toPx()))
        }.clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        SfImage(icon, Binder.engraved, size * 0.44f)
    }
}

/**
 * A small brass coin with an engraved symbol in a full touch target: a deck's favourite star and ⋯. [lit] fills the
 * symbol with ember (a favourite). With [onClick] null it is only the face (a menu's anchor).
 */
@Composable
fun BinderCoin(icon: String, label: String, modifier: Modifier = Modifier, lit: Boolean = false, onClick: (() -> Unit)? = null) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(modifier.size(44.dp)
        .then(if (onClick != null) Modifier.clickable(interaction, null, role = Role.Button) { onClick() } else Modifier)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(30.dp).shadow(if (pressed) 1.dp else 2.dp, CircleShape)
            .background(if (pressed) Binder.brassPressed else Binder.brass, CircleShape).border(0.8.dp, Color.Black.copy(alpha = 0.5f), CircleShape)
            .drawWithContent {
                drawContent()
                drawCircle(Binder.brassDeep.copy(alpha = 0.55f), radius = size.minDimension / 2 - 2.5.dp.toPx(), style = Stroke(0.8.dp.toPx()))
            }, contentAlignment = Alignment.Center) {
            SfImage(icon, if (lit) rgb(0.72, 0.20, 0.06) else Binder.engraved, 14.dp, if (lit) Modifier.glow(TavernPalette.ember.copy(alpha = 0.8f), 2.dp, 7.dp) else Modifier)
        }
    }
}

/** A chip that narrows what a page shows: dark leather in a thin brass rim, ember glass when chosen. */
@Composable
fun BinderChip(title: String, modifier: Modifier = Modifier, icon: String? = null, chosen: Boolean = false) {
    val ink = if (chosen) rgb(1.0, 0.94, 0.80) else rgb(0.98, 0.82, 0.48)
    Row(modifier.shadow(if (chosen) 1.dp else 2.dp, CircleShape).tavernCapsuleRim(thin = true).defaultMinSize(minHeight = 32.dp)
        .padding(1.5.dp).tavernFill(if (chosen) TavernMaterial.EMBER else TavernMaterial.LEATHER, CircleShape).padding(horizontal = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { SfImage(it, ink, 12.dp) }
        Text(title, color = ink, style = sf(13f, SfWeight.bold, SfDesign.SERIF).onLeather(), maxLines = 1)
    }
}

/** Something to tell the player, written on the page: a brass-stamped symbol, a title in the book's hand and a line beneath. */
@Composable
fun BinderNote(title: String, message: String, modifier: Modifier = Modifier, icon: String = "info.circle") {
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        BinderStamp(icon, Modifier.padding(top = 1.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, color = DeckStudioPalette.ink, style = sf(15f, SfWeight.bold, SfDesign.SERIF))
            Text(message, color = DeckStudioPalette.secondaryInk, style = sf(13f, SfWeight.regular, SfDesign.SERIF))
        }
    }
}

/** An empty page in the book's hand: a brass-stamped symbol, a title in ink and a line of explanation. */
@Composable
fun BinderEmptyLeaf(title: String, icon: String, message: String?, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 28.dp, horizontal = 20.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        BinderStamp(icon, size = 56.dp)
        Text(title, color = DeckStudioPalette.ink, style = sf(20f, SfWeight.bold, SfDesign.SERIF).copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center))
        message?.let {
            Text(it, color = DeckStudioPalette.secondaryInk, style = sf(14f, SfWeight.regular, SfDesign.SERIF).copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center))
        }
    }
}
