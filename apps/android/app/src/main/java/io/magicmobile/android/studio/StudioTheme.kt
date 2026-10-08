package io.magicmobile.android.studio

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.board.BoardMenu
import io.magicmobile.android.board.ManaSymbolView
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb

/** DeckStudioDesignTokens.swift: a quiet ivory workspace lets real card artwork supply the colour. */
/** Walnut & Ember's workbench: aged parchment pages in dark brown ink, so real card artwork still supplies the colour. */
object DeckStudioPalette {
    val background = rgb(0.87, 0.79, 0.64)
    val surface = rgb(0.95, 0.90, 0.79)
    val surfaceElevated = rgb(0.98, 0.95, 0.87)
    val ink = rgb(0.20, 0.11, 0.05)
    val secondaryInk = rgb(0.40, 0.29, 0.18)
    // The menu's ember hue, darkened for readable text on parchment.
    val accent = rgb(0.60, 0.23, 0.10)
    val success = rgb(0.17, 0.36, 0.20)
    val warning = rgb(0.50, 0.28, 0.06)
    val danger = rgb(0.62, 0.13, 0.10)
    val separator = rgb(0.74, 0.60, 0.38)
    /** The iOS system blue, for plain toolbar and link buttons in the light appearance. */
    val link = ink
}

object DeckStudioMetrics {
    val controlRadius = 16.dp
    val panelRadius = 22.dp
    val cardRadius = 6.dp
    val controlHeight = 48.dp
    val touchTarget = 44.dp
    val panelPadding = 16.dp
}

/**
 * Inside the book all type is serif unless a style asks otherwise (SwiftUI `.fontDesign(.serif)` on the page).
 * Deck Studio's files use this `sf`, not the app-wide one.
 */
fun sf(size: Float, weight: androidx.compose.ui.text.font.FontWeight = SfWeight.regular, design: SfDesign = SfDesign.SERIF, tracking: Float = 0f): TextStyle =
    io.magicmobile.android.ui.sf(size, weight, design, tracking)

/** SwiftUI text styles at the default Dynamic Type size (Large). */
object StudioText {
    val largeTitle get() = sf(34f, SfWeight.regular)
    val title get() = sf(28f)
    val title2 get() = sf(22f)
    val title3 get() = sf(20f)
    val headline get() = sf(17f, SfWeight.semibold)
    val body get() = sf(17f)
    val callout get() = sf(16f)
    val subheadline get() = sf(15f)
    val footnote get() = sf(13f)
    val caption get() = sf(12f)
    val caption2 get() = sf(11f)
}

fun TextStyle.weight(weight: androidx.compose.ui.text.font.FontWeight): TextStyle = copy(fontWeight = weight)

/** DeckStudioButtonStyle in Walnut & Ember: riveted plaques, ember glass for the main action and leather for the rest. */
@Composable
fun StudioButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = true, enabled: Boolean = true,
                 icon: String? = null, fillWidth: Boolean = false, compactText: Boolean = false) {
    io.magicmobile.android.ui.TavernButton({ GameAudio.play(GameSound.UI_TICK); onClick() }, modifier.semantics { contentDescription = title },
        if (primary) io.magicmobile.android.ui.TavernButtonKind.PRIMARY else io.magicmobile.android.ui.TavernButtonKind.SECONDARY,
        fontSize = if (compactText) 14f else 15f, fullWidth = fillWidth, enabled = enabled) {
        icon?.let { SfImage(it, androidx.compose.material3.LocalContentColor.current, 17.dp) }
        io.magicmobile.android.ui.TavernButtonText(title)
    }
}

/** A plain SwiftUI `Button` in the light appearance: ink text, 44-point touch target. */
@Composable
fun StudioPlainButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: String? = null, enabled: Boolean = true,
                      color: Color = DeckStudioPalette.ink, style: TextStyle = StudioText.body, destructive: Boolean = false) {
    val tint = if (destructive) DeckStudioPalette.danger else color
    Row(modifier.defaultMinSize(minHeight = DeckStudioMetrics.touchTarget).alpha(if (enabled) 1f else 0.35f)
        .clickable(enabled = enabled, role = Role.Button) { onClick() },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { SfImage(it, tint, (style.fontSize.value + 1f).dp) }
        Text(title, color = tint, style = style)
    }
}

/** An icon-only toolbar or row button with a 44-point target. */
@Composable
fun StudioIconButton(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                     tint: Color = DeckStudioPalette.ink, size: Dp = 20.dp) {
    Box(modifier.size(44.dp).alpha(if (enabled) 1f else 0.35f).clickable(enabled = enabled, role = Role.Button) { onClick() }
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        SfImage(icon, tint, size)
    }
}

/** DeckStudioPanel: 16-point padding on the surface colour, 22-point corners. */
/** A plate of the book's own paper, a shade lighter than the page, edged with a hairline of ink. */
fun Modifier.studioPanel(): Modifier = fillMaxWidth()
    .grimoirePaper(DeckStudioPalette.surface, 0.2f, RoundedCornerShape(DeckStudioMetrics.panelRadius))
    .border(0.8.dp, DeckStudioPalette.ink.copy(alpha = 0.14f), RoundedCornerShape(DeckStudioMetrics.panelRadius))
    .padding(DeckStudioMetrics.panelPadding)

@Composable
fun StudioPanel(modifier: Modifier = Modifier, spacing: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.studioPanel(), verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}

/** Something to tell the player, written on the page in the binder's hand (BinderNote). */
@Composable
fun DeckStudioNotice(title: String, message: String, icon: String = "info.circle", modifier: Modifier = Modifier) {
    BinderNote(title, message, modifier, icon)
}

@Composable
fun DeckStudioColorIdentity(colors: List<String>?, modifier: Modifier = Modifier, pipSize: Dp = 22.dp) {
    val names = mapOf("W" to "white", "U" to "blue", "B" to "black", "R" to "red", "G" to "green")
    Row(modifier.defaultMinSize(minHeight = pipSize).semantics {
        contentDescription = colors?.let { "Color identity: " + if (it.isEmpty()) "colorless" else it.joinToString(", ") { c -> names[c] ?: c } }
            ?: "Color identity unavailable"
    }, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (colors != null) {
            if (colors.isEmpty()) ManaSymbolView("C", minOf(pipSize, 26.dp))
            for (symbol in listOf("W", "U", "B", "R", "G").filter { it in colors }) ManaSymbolView(symbol, minOf(pipSize, 26.dp))
        } else Text("Identity unknown", color = DeckStudioPalette.ink, style = StudioText.caption2, maxLines = 1)
    }
}

/** NativeDeckManaCost: symbols in a row, generic and hybrid costs as grey capsules. */
@Composable
fun NativeDeckManaCost(cost: String?, modifier: Modifier = Modifier) {
    val symbols = cost?.split("{")?.mapNotNull { token -> token.indexOf('}').takeIf { it >= 0 }?.let { token.substring(0, it) } } ?: emptyList()
    Row(modifier.semantics { contentDescription = cost?.let { "Mana cost ${it.replace("{*}", " // ")}" } ?: "Mana cost unavailable" },
        horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        for (symbol in symbols) {
            when {
                symbol == "*" -> Text("//", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                symbol in setOf("W", "U", "B", "R", "G", "C") -> ManaSymbolView(symbol, 19.dp)
                else -> Box(Modifier.defaultMinSize(19.dp, 19.dp).background(Color.Gray.copy(alpha = 0.7f), CircleShape)
                    .padding(horizontal = if (symbol.length > 1) 3.dp else 0.dp), contentAlignment = Alignment.Center) {
                    Text(symbol, color = Color.Black, style = sf(11f, SfWeight.bold, SfDesign.ROUNDED))
                }
            }
        }
    }
}

/**
 * DeckStudioArtwork: the commander's art cropped as a cover (hero) or a whole card. A deck's own row passes the printing
 * it chose as `art`; anywhere else the player's choice for the card name shows.
 */
@Composable
fun DeckStudioArtwork(name: String, modifier: Modifier = Modifier, hero: Boolean = false, colors: List<String>? = null,
                      art: io.magicmobile.android.CardArtSelection = io.magicmobile.android.CardArtSelection.Active) {
    CardArtwork(name, modifier, artOnly = hero, art = art) {
        if (hero) DeckCoverPlaceholder(name, colors)
        else Box(Modifier.fillMaxSize().background(DeckStudioPalette.background), contentAlignment = Alignment.Center) {
            SfImage("sparkle", DeckStudioPalette.secondaryInk, 17.dp)
        }
    }
}

/** A deck cover without artwork: the deck's colours as light through glass, its commander's name and pips. */
@Composable
fun DeckCoverPlaceholder(commander: String, colors: List<String>?) {
    val tints = mapOf("W" to rgb(0.93, 0.86, 0.66), "U" to rgb(0.2, 0.46, 0.78), "B" to rgb(0.3, 0.22, 0.34),
        "R" to rgb(0.8, 0.28, 0.18), "G" to rgb(0.22, 0.55, 0.32))
    val chosen = listOf("W", "U", "B", "R", "G").filter { colors?.contains(it) == true }.mapNotNull { tints[it] }
    val palette = when (chosen.size) {
        0 -> listOf(rgb(0.42, 0.44, 0.47), rgb(0.2, 0.21, 0.23))
        1 -> listOf(chosen[0], chosen[0].copy(alpha = 0.55f))
        else -> chosen
    }
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat().coerceAtLeast(1f); val h = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(palette, Offset.Zero, Offset(w, h))))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.35f), Color.Transparent),
            Offset(w * 0.3f, h * 0.2f), 180f * (w / 160f).coerceIn(1f, 3f))))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)), h / 2f, h)))
        Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Spacer(Modifier.weight(1f))
                if (colors != null) {
                    Row(Modifier.background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(5.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        for (symbol in listOf("W", "U", "B", "R", "G").filter { it in colors }) ManaSymbolView(symbol, 18.dp)
                        if (colors.isEmpty()) ManaSymbolView("C", 18.dp)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Text(commander.ifEmpty { "Choose a commander" }, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
                style = sf(19f, SfWeight.bold, SfDesign.SERIF).copy(shadow = Shadow(Color.Black.copy(alpha = 0.5f), Offset(0f, 2f), 8f)))
        }
    }
}

/** The artwork preference, shared with the whole app (NativeArtworkPreference.key). */
@Composable
fun rememberArtworkConsent(): Pair<Boolean, (Boolean) -> Unit> {
    val context = androidx.compose.ui.platform.LocalContext.current
    val revision = io.magicmobile.android.Artwork.consentRevision
    val enabled = remember(revision) { io.magicmobile.android.Artwork.enabled(context) }
    return enabled to { value: Boolean -> io.magicmobile.android.Artwork.setEnabled(context, value) }
}

/** A disclosure in the book's hand (BinderDisclosureStyle on iOS): the title in ink and a brass chevron that turns. */
@Composable
fun StudioDisclosure(title: String, modifier: Modifier = Modifier, initiallyExpanded: Boolean = false, titleStyle: TextStyle = StudioText.body,
                     color: Color = DeckStudioPalette.ink, icon: String? = null, label: (@Composable RowScope.() -> Unit)? = null,
                     content: @Composable ColumnScope.() -> Unit) {
    var expanded by rememberSaveable(title) { mutableStateOf(initiallyExpanded) }
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, tween(180), label = "disclosure")
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) { expanded = !expanded }
            .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (label != null) Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = label)
            else {
                icon?.let { SfImage(it, color, (titleStyle.fontSize.value + 1f).dp) }
                Text(title, Modifier.weight(1f), color = color, style = titleStyle)
            }
            Box(Modifier.size(22.dp).background(Binder.brass, CircleShape).border(0.8.dp, Binder.brassDeep, CircleShape), contentAlignment = Alignment.Center) {
                SfImage("chevron.down", Binder.engraved, 10.dp, Modifier.rotate(rotation))
            }
        }
        if (expanded) Column(Modifier.fillMaxWidth().padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

/**
 * DeckStudioArtworkInvitation: remote card art is off until the player opts in. The setting
 * otherwise lives behind a toolbar button, so an empty-looking list reads as a choice.
 */
@Composable
fun DeckStudioArtworkInvitation(modifier: Modifier = Modifier) {
    val (remote, setRemote) = rememberArtworkConsent()
    if (remote) return
    Column(modifier.fillMaxWidth().binderPlate().padding(horizontal = 12.dp, vertical = 4.dp)) {
        StudioDisclosure("Online card images are off", label = {
            BinderStamp("photo.on.rectangle.angled")
            Text("Online card images are off", color = DeckStudioPalette.ink, style = sf(15f, SfWeight.bold))
        }) {
            Text("Turn on artwork across the app to send displayed card names and your IP address to Scryfall. Saved images remain available offline. Change this anytime in Artwork & privacy.",
                color = DeckStudioPalette.secondaryInk, style = sf(13f))
            BinderPlaque(Modifier.testTag("deckStudio.artwork.enable"), title = "Turn on") { setRemote(true) }
        }
    }
}

/** NativeArtworkPreferenceView in its light Form. */
@Composable
fun NativeArtworkPreferenceRows() {
    val (remote, setRemote) = rememberArtworkConsent()
    Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        io.magicmobile.android.ui.TavernToggle("Scryfall live images", remote, setRemote,
            Modifier.semantics { contentDescription = "nativeArtwork.downloads" }, color = DeckStudioPalette.ink)
        Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Text("Scryfall receives card names—including your hand—and your IP address.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
    }
}

/** A switch in the tavern's brass (TavernToggle) beside its title in ink, in place of the system's switch. */
@Composable
fun StudioToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                 style: TextStyle = StudioText.body, @Suppress("UNUSED_PARAMETER") tint: Color = rgb(1.0, 0.5, 0.35)) {
    io.magicmobile.android.ui.TavernToggle(title, isOn, onChange, modifier, enabled = enabled, color = DeckStudioPalette.ink)
}

/** A count with brass minus and plus coins (BinderStepper on iOS). */
@Composable
fun StudioStepper(label: String, value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                  style: TextStyle = StudioText.body) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = DeckStudioPalette.ink, style = style)
        val canDecrease = enabled && value > range.first; val canIncrease = enabled && value < range.last
        for ((symbol, active, step, name) in listOf(Quad("minus", canDecrease, -1, "Decrement $label"), Quad("plus", canIncrease, 1, "Increment $label"))) {
            Box(Modifier.size(47.dp, 44.dp).clickable(enabled = active, role = Role.Button) { onChange(value + step) }
                .semantics { contentDescription = name }, contentAlignment = Alignment.Center) {
                Box(Modifier.size(30.dp).alpha(if (active) 1f else 0.45f).shadow(1.5.dp, CircleShape).background(Binder.brass, CircleShape)
                    .border(0.8.dp, Binder.brassDeep, CircleShape), contentAlignment = Alignment.Center) { SfImage(symbol, Binder.engraved, 12.dp) }
            }
        }
    }
}

private data class Quad(val symbol: String, val active: Boolean, val step: Int, val name: String)

/** A choice as the binder's switch (GrimoireChoice on iOS): a dark inset in a brass edge, the chosen option ember glass. */
@Composable
fun <T> StudioSegmented(options: List<T>, selected: T, onSelect: (T) -> Unit, title: (T) -> String, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val outer = RoundedCornerShape(9.dp); val inner = RoundedCornerShape(7.dp)
    Row(modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.45f).background(rgb(0.12, 0.06, 0.035).copy(alpha = 0.88f), outer)
        .border(1.5.dp, Binder.brass, outer).padding(3.dp)) {
        for (option in options) {
            val isSelected = option == selected
            Box(Modifier.weight(1f).height(36.dp)
                .then(if (isSelected) Modifier.tavernFill(io.magicmobile.android.ui.TavernMaterial.EMBER, inner).border(1.dp, Binder.brassLight.copy(alpha = 0.6f), inner) else Modifier)
                .clickable(enabled = enabled, role = Role.Button) { onSelect(option) }
                .semantics { this.selected = isSelected }.padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center) {
                Text(title(option), color = if (isSelected) Binder.emberText else io.magicmobile.android.ui.TavernPalette.parchment.copy(alpha = 0.72f),
                    style = sf(14f, SfWeight.bold).copy(shadow = Shadow(Color.Black.copy(alpha = 0.7f), Offset(0f, 1.5f), 1f)), maxLines = 1)
            }
        }
    }
}

/** A run-in heading on a page (a section of the deck's cards): small capitals, an inked rule, a count (GrimoireSubheading on iOS). */
@Composable
fun GrimoireSubheading(title: String, count: Int? = null, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), color = DeckStudioPalette.ink, style = sf(12f, SfWeight.semibold, SfDesign.SERIF, tracking = 1.6f), maxLines = 1)
        Box(Modifier.weight(1f).height(1.dp).background(DeckStudioPalette.ink.copy(alpha = 0.28f)))
        count?.let {
            Text("$it", Modifier.semantics { contentDescription = CardCountText.label(it) }, color = DeckStudioPalette.secondaryInk,
                style = sf(12f, SfWeight.semibold, SfDesign.SERIF))
        }
    }
}

/** A light pull-down Menu. */
@Composable
fun StudioMenu(entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable () -> Unit) =
    BoardMenu(entries, modifier, enabled, light = true, label = label)

/** A menu-style Picker as a brass plaque naming the current choice (BinderMenuPicker on iOS). */
@Composable
fun StudioMenuPicker(selectedTitle: String, entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true,
                     @Suppress("UNUSED_PARAMETER") style: TextStyle = StudioText.body) {
    StudioMenu(entries, modifier, enabled) {
        BinderPlaque(title = selectedTitle, icon = "chevron.up.chevron.down", enabled = enabled)
    }
}

/** A search field: magnifying glass, text, clear button, on a white rounded fill. */
@Composable
fun StudioSearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, radius: Dp = 14.dp,
                      padding: Dp = 14.dp, clearLabel: String = "Clear search", trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().grimoireField(RoundedCornerShape(radius)).padding(horizontal = padding, vertical = if (padding > 12.dp) padding else 0.dp)
        .defaultMinSize(minHeight = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        SfImage("magnifyingglass", DeckStudioPalette.ink, 18.dp)
        StudioTextInput(value, onChange, placeholder, Modifier.weight(1f), imeAction = ImeAction.Search)
        if (value.isNotEmpty()) Box(Modifier.size(if (padding > 12.dp) 24.dp else 44.dp).clickable { onChange("") }.semantics { contentDescription = clearLabel },
            contentAlignment = Alignment.Center) { SfImage("xmark.circle.fill", DeckStudioPalette.secondaryInk.copy(alpha = 0.7f), 17.dp) }
        trailing?.invoke()
    }
}

/** A bare text input in the studio's ink with a grey placeholder. */
@Composable
fun StudioTextInput(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, style: TextStyle = StudioText.body,
                    singleLine: Boolean = true, imeAction: ImeAction = ImeAction.Done, keyboardType: KeyboardType = KeyboardType.Text,
                    capitalization: KeyboardCapitalization = KeyboardCapitalization.None, enabled: Boolean = true, onSubmit: (() -> Unit)? = null) {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    BasicTextField(value, onChange, modifier, enabled = enabled, singleLine = singleLine, textStyle = style.copy(color = DeckStudioPalette.ink),
        cursorBrush = SolidColor(DeckStudioPalette.ink),
        keyboardOptions = KeyboardOptions(capitalization = capitalization, autoCorrectEnabled = false, keyboardType = keyboardType, imeAction = imeAction),
        keyboardActions = KeyboardActions(onAny = { onSubmit?.invoke(); focus.clearFocus() }),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, color = rgb(0.24, 0.24, 0.26).copy(alpha = 0.3f), style = style, maxLines = if (singleLine) 1 else Int.MAX_VALUE)
                inner()
            }
        })
}

/** TextField(.roundedBorder) in the light appearance. */
@Composable
fun StudioRoundedField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier,
                       keyboardType: KeyboardType = KeyboardType.Text, capitalization: KeyboardCapitalization = KeyboardCapitalization.None,
                       enabled: Boolean = true, onSubmit: (() -> Unit)? = null) {
    Box(modifier.grimoireField(RoundedCornerShape(6.dp))
        .defaultMinSize(minHeight = 34.dp).padding(horizontal = 8.dp, vertical = 7.dp), contentAlignment = Alignment.CenterStart) {
        StudioTextInput(value, onChange, placeholder, Modifier.fillMaxWidth(), keyboardType = keyboardType, capitalization = capitalization,
            enabled = enabled, onSubmit = onSubmit, imeAction = if (onSubmit != null) ImeAction.Search else ImeAction.Done)
    }
}

/** ContentUnavailableView as an empty page in the book's hand (BinderEmptyLeaf): a brass-stamped symbol, a title and a line. */
@Composable
fun StudioContentUnavailable(title: String, systemImage: String, description: String, modifier: Modifier = Modifier) {
    BinderEmptyLeaf(title, systemImage, description, modifier)
}

/** A ProgressView with a label, in the light appearance. */
@Composable
fun StudioProgress(label: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        androidx.compose.material3.CircularProgressIndicator(Modifier.size(22.dp), color = DeckStudioPalette.secondaryInk, strokeWidth = 2.5.dp)
        Text(label, color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
    }
}

/** A Box that fills the screen with the studio background, for full-screen covers. */
@Composable
fun StudioScreen(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    // Every full screen of Deck Studio is a page of the spell book.
    Box(modifier.fillMaxSize().grimoirePage(), content = content)
}
