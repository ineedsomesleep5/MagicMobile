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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.core.CardInfo
import io.magicmobile.android.menus.ArenaButtonFace
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaEmblem
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaRoomBackdrop
import io.magicmobile.android.menus.LocalArenaMenuBackdrop
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.tavernFill

/*
 * GrimoireBinder.swift: Deck Studio's parts. They were a collector's binder (oxblood leather, parchment pages, brass corners,
 * 2026-10-06); since the Arena menus (Caleb, 2026-10-22: Deck Studio follows Arena, nothing carried over) the same parts draw
 * Arena's deck builder: dark glass panels in the gold hairline over the darkened tavern room, glass tabs, Arena's pills and
 * plaques, and cards without sleeves. The names stay, so every screen keeps its layout and its TalkBack and test contract.
 */
object Binder {
    val oxblood = rgb(0.40, 0.09, 0.07)
    val leatherDark = rgb(0.17, 0.07, 0.045)
    val thread = rgb(0.90, 0.70, 0.40).copy(alpha = 0.55f)
    val brassLight = rgb(1.0, 0.88, 0.58)
    val brassDeep = rgb(0.50, 0.32, 0.11)
    val engraved = rgb(0.24, 0.13, 0.05)
    val emberText = rgb(1.0, 0.92, 0.70)
    /** How wide the chapter tabs are. */
    val tabWidth = 50.dp
    /** How far each tab used to run in under the page; kept for the layouts that leave room for it. */
    val tabTuck = 12.dp
    val brass: Brush get() = Brush.verticalGradient(listOf(brassLight, TavernPalette.brass, brassDeep))
    val brassPressed: Brush get() = Brush.verticalGradient(listOf(brassDeep, TavernPalette.brass, brassLight.copy(alpha = 0.8f)))
    val chapterIcons = mapOf("Cards" to "rectangle.portrait.on.rectangle.portrait.fill", "Ideas" to "lightbulb.fill",
        "Analysis" to "chart.bar.fill")
}

/** The gold hairline at a strength (iOS `ArenaGlass.hairline` with `.opacity(alpha)`). */
fun binderHairline(alpha: Float = 1f): Brush = Brush.verticalGradient(listOf(
    ArenaGlass.hairlineTop.copy(alpha = ArenaGlass.hairlineTop.alpha * alpha), ArenaGlass.hairlineBottom.copy(alpha = ArenaGlass.hairlineBottom.alpha * alpha)))

/** Leather with a colour multiplied into it (the tavern's; Deck Studio no longer uses it). */
fun Modifier.binderLeather(dye: Color, amount: Float, shape: androidx.compose.ui.graphics.Shape = androidx.compose.ui.graphics.RectangleShape): Modifier =
    tavernFill(TavernMaterial.LEATHER, shape).drawWithContent {
        drawRect(dye.copy(alpha = amount), blendMode = BlendMode.Multiply)
        drawContent()
    }

/**
 * Under the whole screen (BinderCover on iOS): the tavern room, darkened as behind Arena's deck builder. Inside the menu shell
 * (Deck Studio as its Decks tab, or a cover that drew the room already) the shell's own room shows and this draws nothing.
 */
@Composable
fun BinderCover() {
    if (!LocalArenaMenuBackdrop.current) ArenaRoomBackdrop(0.45f)
}

/** Which corner mounts a panel once had; Arena's panels have plain corners, so the style only stays for callers. */
enum class BinderCornerStyle { GUARD, CARD, LEAF, BOOK }

/** Arena's panels have plain corners: nothing is drawn (BinderCorners on iOS). */
@Suppress("UNUSED_PARAMETER")
fun Modifier.binderCorners(size: Dp, style: BinderCornerStyle = BinderCornerStyle.GUARD): Modifier = this

/**
 * A page of Deck Studio: a dark glass panel in the gold hairline. Its content keeps its own layout; the page only frames and
 * clips it. (`gutterStart` was the binder's spine shadow; Arena's panels have none.)
 */
@Composable
fun BinderPage(modifier: Modifier = Modifier, @Suppress("UNUSED_PARAMETER") gutterStart: Boolean? = null, screen: Any? = null,
               content: @Composable BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    // The stage still knows the page (a chapter swipe begins below its head).
    val stage = LocalGrimoireStage.current
    val page = remember { Any() }
    if (stage != null && screen != null) DisposableEffect(stage, screen) { onDispose { stage.removeBinderPage(page, screen) } }
    Box(modifier.then(if (stage != null && screen != null) Modifier.onGloballyPositioned { stage.setBinderPage(it.boundsInRoot(), page, screen) } else Modifier)
        .padding(4.dp).shadow(10.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f))) {
        Box(Modifier.fillMaxSize().clip(shape).grimoirePaper().border(1.dp, ArenaGlass.hairline, shape), content = content)
    }
}

/** A panel set into the page (the deck's title plate): a lighter pane of glass in the gold hairline. */
@Suppress("UNUSED_PARAMETER")
fun Modifier.binderPlate(corners: BinderCornerStyle = BinderCornerStyle.LEAF): Modifier {
    val shape = RoundedCornerShape(10.dp)
    return grimoirePaper(DeckStudioPalette.surface, shape = shape).clip(shape).border(0.9.dp, binderHairline(0.8f), shape)
}

/** The deck's chapters (Cards, Ideas, Analysis) as Arena tabs: an emblem over the name, the chosen one lit with an ember bar. */
@Composable
fun BinderIndexTabs(chapters: List<String>, selected: String, modifier: Modifier = Modifier, tabHeight: Dp = 102.dp, choose: (String) -> Unit) {
    BoxWithConstraints(modifier.width(Binder.tabWidth)) {
        val gap = 6.dp
        val fitted = if (constraints.hasBoundedHeight) minOf(tabHeight, (maxHeight - gap * (chapters.size - 1)) / maxOf(1, chapters.size)) else tabHeight
        val height = minOf(fitted, 64.dp)
        Column(Modifier.width(Binder.tabWidth).semantics { contentDescription = "Deck workspace" }, verticalArrangement = Arrangement.spacedBy(gap)) {
            for (chapter in chapters) {
                val chosen = chapter == selected
                val shape = RoundedCornerShape(8.dp)
                Box(Modifier.width(Binder.tabWidth).height(height)
                    .background(if (chosen) Color.White.copy(alpha = 0.08f) else Color.Black.copy(alpha = 0.35f), shape)
                    .border(0.8.dp, binderHairline(if (chosen) 0.8f else 0.35f), shape)
                    .clickable(role = Role.Tab) { choose(chapter) }
                    .semantics(mergeDescendants = true) { contentDescription = chapter; this.selected = chosen }) {
                    if (chosen) Box(Modifier.align(Alignment.CenterStart).padding(vertical = 8.dp).width(3.dp).fillMaxHeight()
                        .glow(ArenaMenuStyle.ember, 5.dp, 2.dp).background(ArenaMenuStyle.ember, CircleShape))
                    Column(Modifier.fillMaxSize().padding(horizontal = 3.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically)) {
                        ArenaEmblem(Binder.chapterIcons[chapter] ?: "book.closed.fill", 15.dp, chosen)
                        FitText(chapter, ArenaMenuStyle.font(9.5f, SfWeight.semibold), Modifier.clearAndSetSemantics {},
                            color = if (chosen) Color.White else ArenaMenuStyle.dim, minimumScale = 0.6f)
                    }
                }
            }
        }
    }
}

/** "Done" and "Cancel": Arena's dark glass pill. */
@Composable
fun BinderStrapButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(modifier.defaultMinSize(minHeight = 44.dp)
        .clickable(interaction, null, enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_BACK); onClick() }
        .semantics { contentDescription = title }, contentAlignment = Alignment.Center) {
        ArenaButtonFace(ArenaButtonKind.SECONDARY, ArenaMenuStyle.title(15f, SfWeight.semibold), pressed, enabled = enabled, fills = false, inset = 9.dp) {
            ArenaButtonText(title)
        }
    }
}

/**
 * A pill (Save, Sort, the rail's tools): Arena's dark glass pill, as its filter pills; [square] is a round glass button with a
 * gold symbol. [on] lights it orange. With [onClick] null it is only a label (a menu's).
 */
@Composable
fun BinderPlaque(modifier: Modifier = Modifier, title: String? = null, icon: String? = null, square: Boolean = false, on: Boolean = false,
                 enabled: Boolean = true, label: String? = null, trailingIcon: String? = null, onClick: (() -> Unit)? = null) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(modifier.defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
        .then(if (onClick != null) Modifier.clickable(interaction, null, enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onClick() } else Modifier)
        .semantics(mergeDescendants = true) {
            (label ?: title)?.let { contentDescription = it }
            if (on) selected = true
        }, contentAlignment = Alignment.Center) {
        if (square) {
            Box(Modifier.size(36.dp).alpha(if (enabled) 1f else 0.55f)
                .background(if (on) Brush.verticalGradient(listOf(rgb(1.0, 0.6, 0.3), rgb(0.75, 0.25, 0.08)))
                    else SolidColor(Color.Black.copy(alpha = if (pressed) 0.7f else 0.5f)), CircleShape)
                .border(1.dp, ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
                icon?.let { SfImage(it, if (on) Color.White else ArenaMenuStyle.gold, 15.dp) }
            }
        } else {
            ArenaButtonFace(if (on) ArenaButtonKind.PRIMARY else ArenaButtonKind.SECONDARY, ArenaMenuStyle.font(14f, SfWeight.semibold), pressed,
                enabled = enabled, fills = false, inset = 7.dp, glow = 0.4f) {
                icon?.let { SfImage(it, androidx.compose.material3.LocalContentColor.current, 13.dp) }
                title?.let { ArenaButtonText(it) }
                trailingIcon?.let { SfImage(it, androidx.compose.material3.LocalContentColor.current, 9.dp) }
            }
        }
    }
}

/** The tool bar: a strip of darker glass in the gold hairline. */
@Composable
fun BinderRail(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.42f), shape).border(0.9.dp, binderHairline(0.7f), shape)
        .padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

/** The rail's search field: a dark capsule in the gold hairline with a magnifying glass. */
@Composable
fun BinderSearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, tag: String? = null,
                      clearLabel: String = "Clear search") {
    val focus = LocalFocusManager.current
    Row(modifier.fillMaxWidth().height(38.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape).border(1.dp, binderHairline(0.7f), CircleShape)
        .padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(24.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) { SfImage("magnifyingglass", ArenaMenuStyle.dim, 13.dp) }
        val style = ArenaMenuStyle.font(15f, SfWeight.regular)
        BasicTextField(value, onChange, Modifier.weight(1f).then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .semantics { contentDescription = placeholder }, singleLine = true,
            textStyle = style.copy(color = ArenaMenuStyle.text), cursorBrush = SolidColor(ArenaMenuStyle.gold),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onAny = { focus.clearFocus() }),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) Text(placeholder, color = ArenaMenuStyle.dim, style = style, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    inner()
                }
            })
        if (value.isNotEmpty()) Box(Modifier.size(32.dp, 40.dp).clickable(role = Role.Button) { onChange("") }.semantics { contentDescription = clearLabel },
            contentAlignment = Alignment.Center) { SfImage("xmark.circle.fill", ArenaMenuStyle.dim, 16.dp) }
    }
}

/** Which cards the pages show: the deck's own, or every card there is to add. */
enum class BinderShelf { DECK, ALL }

/** The two shelves as a switch on the rail: the chosen one filled gold with dark type. */
@Composable
fun BinderShelfSwitch(shelf: BinderShelf, onChange: (BinderShelf) -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    val shape = RoundedCornerShape(9.dp)
    // compact: symbols only, for a short sideways page (the titles stay for TalkBack).
    Row((if (compact) modifier else modifier.fillMaxWidth()).background(Color.Black.copy(alpha = 0.5f), shape).border(0.9.dp, binderHairline(0.7f), shape).padding(3.dp)
        .semantics { contentDescription = "Show cards" }) {
        for ((value, title, icon) in listOf(Triple(BinderShelf.DECK, "My deck", "rectangle.stack.fill"), Triple(BinderShelf.ALL, "All cards", "books.vertical.fill"))) {
            val chosen = shelf == value
            val inner = RoundedCornerShape(7.dp)
            Row((if (compact) Modifier.width(42.dp).height(34.dp) else Modifier.weight(1f).height(36.dp))
                .then(if (chosen) Modifier.background(ArenaMenuStyle.goldFill, inner) else Modifier)
                .clickable(role = Role.Tab) { onChange(value) }
                .semantics(mergeDescendants = true) { contentDescription = title; selected = chosen },
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                val tint = if (chosen) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.dim
                SfImage(icon, tint, 14.dp)
                if (!compact) Text(title, color = tint, style = ArenaMenuStyle.font(14f, SfWeight.bold), maxLines = 1)
            }
        }
    }
}

/**
 * Mana values 0 to 7+ as Arena's filter: a number in a glass circle, gold when chosen, each in its own outline. Tap one or more
 * to see only those costs; none shows all. [fill] spreads the circles across the width; otherwise they sit side by side.
 */
@Composable
fun BinderManaFilter(selection: Set<Int>, onChange: (Set<Int>) -> Unit, modifier: Modifier = Modifier, fill: Boolean = true) {
    Row((if (fill) modifier.fillMaxWidth() else modifier).semantics { contentDescription = "Mana value filter" }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (value in 0..7) {
            val on = value in selection
            Box((if (fill) Modifier.weight(1f) else Modifier.width(34.dp)).height(44.dp).clickable(role = Role.Button) { onChange(if (on) selection - value else selection + value) }
                .semantics(mergeDescendants = true) { contentDescription = if (value == 7) "Mana value 7 or more" else "Mana value $value"; selected = on },
                contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).alpha(if (on || selection.isEmpty()) 1f else 0.6f)
                    .then(if (on) Modifier.glow(ArenaMenuStyle.gold.copy(alpha = 0.6f), 5.dp, 15.dp) else Modifier)
                    .background(if (on) ArenaMenuStyle.goldFill else SolidColor(Color.Black.copy(alpha = 0.5f)), CircleShape)
                    .then(if (on) Modifier else Modifier.border(0.9.dp, binderHairline(0.7f), CircleShape)), contentAlignment = Alignment.Center) {
                    Text(if (value == 7) "7+" else "$value", Modifier.clearAndSetSemantics {}, color = if (on) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.text,
                        style = ArenaMenuStyle.font(if (value == 7) 12f else 14f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
                }
            }
        }
    }
}

object BinderMana {
    /** Whether a card of this mana value passes the filter. */
    fun matches(manaValue: Double?, selection: Set<Int>): Boolean {
        if (selection.isEmpty()) return true
        if (manaValue == null || !manaValue.isFinite()) return false
        return minOf(7, kotlin.math.floor(manaValue).toInt()) in selection
    }
}

/** The deck's size as a thin ember line, with the count. */
@Composable
fun BinderGauge(count: Int, modifier: Modifier = Modifier, target: Int = 100, showsCount: Boolean = true) {
    Row(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$count of $target cards" },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(5.dp).drawBehind {
            val radius = androidx.compose.ui.geometry.CornerRadius(size.height / 2)
            drawRoundRect(Color.White.copy(alpha = 0.12f), cornerRadius = radius)
            val fraction = (count.toFloat() / maxOf(1, target)).coerceIn(0f, 1f)
            if (fraction > 0f) drawRoundRect(Brush.horizontalGradient(listOf(rgb(1.0, 0.7, 0.36), ArenaMenuStyle.ember), 0f, size.width * fraction),
                size = Size(size.width * fraction, size.height), cornerRadius = radius)
        })
        if (showsCount) Text("$count/$target", color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.heavy).copy(fontFeatureSettings = "tnum"))
    }
}

/**
 * A card as in Arena's collection (no sleeve), and under it a strip with a minus, the count and a plus. Tapping the card's right
 * or left half does the same as the strip. A card that cannot be changed here (a read-only deck, or while selecting) is one
 * button, [tapLabel]. A long press shows the large preview with the card's actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BinderSleeve(name: String, quantity: Int, card: CardInfo?, modifier: Modifier = Modifier, notes: List<String> = emptyList(), selected: Boolean? = null,
                 canEdit: Boolean = true, addLabel: String = "Add one $name", removeLabel: String = "Remove one $name", tapLabel: String = name,
                 art: io.magicmobile.android.CardArtSelection = io.magicmobile.android.CardArtSelection.Active,
                 add: () -> Unit, remove: () -> Unit, tap: () -> Unit, preview: () -> Unit = {}) {
    val editing = canEdit && selected == null
    val corner = RoundedCornerShape(DeckStudioMetrics.cardRadius)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.fillMaxWidth().shadow(4.dp, corner, clip = false)) {
            DeckStudioCardImage(name, card, Modifier.fillMaxWidth(), art = art)
            if (selected != null) Box(Modifier.align(Alignment.TopStart).padding(3.dp)
                .background(if (selected) DeckStudioPalette.surfaceElevated else Color.Black.copy(alpha = 0.45f), CircleShape)) {
                SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) DeckStudioPalette.accent else DeckStudioPalette.ink, 20.dp)
            } else if (notes.isNotEmpty()) Box(Modifier.align(Alignment.TopStart).padding(3.dp).size(22.dp)
                .background(DeckStudioPalette.warning.copy(alpha = 0.92f), CircleShape)
                .semantics { contentDescription = "Quick check: " + notes.joinToString(", ") }, contentAlignment = Alignment.Center) {
                SfImage("exclamationmark.triangle.fill", ArenaGlass.bottom, 11.dp)
            }
            if (selected == true) Box(Modifier.matchParentSize().border(3.dp, DeckStudioPalette.accent, corner))
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
            Text("$quantity", Modifier.widthIn(min = 28.dp).background(Color.Black.copy(alpha = 0.62f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape)
                .padding(horizontal = 6.dp, vertical = 2.dp).semantics { contentDescription = "$name, quantity $quantity" },
                color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.heavy).copy(fontFeatureSettings = "tnum", textAlign = TextAlign.Center), maxLines = 1)
            if (editing) SleeveCoin("plus", addLabel, true) { add() }
        }
    }
}

/** A glass circle button under a card; a minus with nothing to take away keeps its place but is not there. */
@Composable
private fun SleeveCoin(symbol: String, label: String, active: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(36.dp, 34.dp).alpha(if (active) 1f else 0f)
        .then(if (active) Modifier.clickable(role = Role.Button) { onClick() }.semantics { contentDescription = label }
            else Modifier.clearAndSetSemantics {}), contentAlignment = Alignment.Center) {
        Box(Modifier.size(24.dp).background(Color.White.copy(alpha = 0.08f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape),
            contentAlignment = Alignment.Center) { SfImage(symbol, ArenaMenuStyle.text, 10.dp) }
    }
}

/** A row of cards; a short last row keeps the card width. */
@Composable
fun <T> BinderSleeveRow(items: List<T>, columns: Int, modifier: Modifier = Modifier, sleeve: @Composable (T, Modifier) -> Unit) {
    Row(modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        for (item in items) sleeve(item, Modifier.weight(1f))
        repeat(columns - items.size) { Spacer(Modifier.weight(1f)) }
    }
}

/** A page's head: a pill at the start (Done), the page's name, and its pills. */
@Composable
fun BinderHead(strap: String, onStrap: () -> Unit, modifier: Modifier = Modifier, title: String? = null, strapTag: String? = null,
               strapEnabled: Boolean = true, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(modifier.fillMaxWidth().padding(start = 6.dp, end = 6.dp, top = 8.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BinderStrapButton(strap, onStrap, if (strapTag != null) Modifier.testTag(strapTag) else Modifier, enabled = strapEnabled)
        Spacer(Modifier.weight(1f))
        title?.let {
            Text(it, Modifier.semantics { heading() }, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(20f, SfWeight.bold),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.weight(1f))
        }
        trailing()
    }
}

/** The foot of a page Quick Add sits on: a strip of dark glass under the gold hairline. */
fun Modifier.binderFoot(): Modifier = background(Color.Black.copy(alpha = 0.45f)).drawBehind {
    drawRect(binderHairline(0.6f), size = Size(size.width, 1.dp.toPx()))
}

// Tags, coins, notes and empty pages (GrimoireBinderControls.swift): Arena's own parts in place of the system's tinted
// capsules, plain icon buttons and empty-state views.

/**
 * A small tag: gold capitals on dark glass in the hairline, ember for the deck you play (`material` EMBER); a deck check keeps a
 * coloured jewel ([accent]). [jewel] is a small flame.
 */
@Composable
fun BinderTag(text: String, modifier: Modifier = Modifier, material: TavernMaterial = TavernMaterial.LEATHER, jewel: Boolean = false,
              accent: Color? = null) {
    val ember = material == TavernMaterial.EMBER
    Row(modifier.defaultMinSize(minHeight = 22.dp)
        .background(if (ember) Brush.verticalGradient(listOf(rgb(0.95, 0.45, 0.18), rgb(0.62, 0.18, 0.06))) else SolidColor(Color.Black.copy(alpha = 0.7f)), CircleShape)
        .border(0.8.dp, ArenaGlass.hairline, CircleShape)
        .padding(start = if (jewel) 6.dp else 10.dp, end = 10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        val ink = if (ember) rgb(1.0, 0.95, 0.82) else ArenaMenuStyle.gold
        if (jewel) SfImage("flame.fill", ink, 8.dp)
        if (accent != null) {
            Box(Modifier.size(8.dp).glow(accent.copy(alpha = 0.9f), 3.dp, 4.dp)
                .background(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.9f), accent, accent.copy(alpha = 0.6f))), CircleShape))
        }
        Text(text, color = ink, maxLines = 1, style = sf(10f, SfWeight.heavy, tracking = 0.8f))
    }
}

/** A gold emblem in a glass circle (it was struck into a brass coin). */
@Composable
fun BinderStamp(icon: String, modifier: Modifier = Modifier, size: Dp = 28.dp) {
    Box(modifier.size(size).background(Color.Black.copy(alpha = 0.5f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape)
        .clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        ArenaEmblem(icon, size * 0.42f, lit = true)
    }
}

/**
 * A small glass circle with a gold symbol in a full touch target: a deck's favourite star and ⋯. [lit] is an ember symbol (a
 * favourite). With [onClick] null it is only the face (a menu's anchor).
 */
@Composable
fun BinderCoin(icon: String, label: String, modifier: Modifier = Modifier, lit: Boolean = false, onClick: (() -> Unit)? = null) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(modifier.size(44.dp)
        .then(if (onClick != null) Modifier.clickable(interaction, null, role = Role.Button) { onClick() } else Modifier)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(30.dp).background(Color.Black.copy(alpha = if (pressed) 0.7f else 0.5f), CircleShape).border(0.9.dp, binderHairline(0.8f), CircleShape),
            contentAlignment = Alignment.Center) {
            SfImage(icon, if (lit) ArenaMenuStyle.ember else ArenaMenuStyle.gold, 13.dp,
                if (lit) Modifier.glow(ArenaMenuStyle.ember.copy(alpha = 0.8f), 3.dp, 7.dp) else Modifier)
        }
    }
}

/** A chip that narrows what a page shows: Arena's filter chip, dark glass, filled gold when chosen. */
@Composable
fun BinderChip(title: String, modifier: Modifier = Modifier, icon: String? = null, chosen: Boolean = false) {
    val ink = if (chosen) ArenaMenuStyle.inkOnGold else ArenaMenuStyle.dim
    Row(modifier.defaultMinSize(minHeight = 30.dp)
        .background(if (chosen) ArenaMenuStyle.goldFill else SolidColor(Color.Black.copy(alpha = 0.5f)), CircleShape)
        .then(if (chosen) Modifier else Modifier.border(0.9.dp, binderHairline(0.7f), CircleShape)).padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { SfImage(it, ink, 11.dp) }
        Text(title, color = ink, style = ArenaMenuStyle.font(13f, SfWeight.bold), maxLines = 1)
    }
}

/** Something to tell the player: a gold emblem, a title and a line beneath. */
@Composable
fun BinderNote(title: String, message: String, modifier: Modifier = Modifier, icon: String = "info.circle") {
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        BinderStamp(icon, Modifier.padding(top = 1.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold))
            Text(message, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(13f, SfWeight.regular))
        }
    }
}

/** An empty page: a gold emblem, a serif title and a line of explanation. */
@Composable
fun BinderEmptyLeaf(title: String, icon: String, message: String?, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 28.dp, horizontal = 20.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        BinderStamp(icon, size = 56.dp)
        Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.title(20f, SfWeight.bold).copy(textAlign = TextAlign.Center))
        message?.let {
            Text(it, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(14f, SfWeight.regular).copy(textAlign = TextAlign.Center))
        }
    }
}
