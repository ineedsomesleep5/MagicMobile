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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
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
import io.magicmobile.android.board.BoardMenu
import io.magicmobile.android.board.ManaSymbolView
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** DeckStudioDesignTokens.swift: a quiet ivory workspace lets real card artwork supply the colour. */
object DeckStudioPalette {
    val background = rgb(0.94, 0.935, 0.91)
    val surface = rgb(0.98, 0.976, 0.96)
    val surfaceElevated = Color.White
    val ink = rgb(0.13, 0.15, 0.15)
    val secondaryInk = rgb(0.34, 0.36, 0.35)
    // The menu's ember hue, darkened for readable text on ivory.
    val accent = rgb(0.57, 0.25, 0.15)
    val success = rgb(0.17, 0.36, 0.26)
    val warning = rgb(0.48, 0.27, 0.07)
    val danger = rgb(0.64, 0.15, 0.15)
    val separator = rgb(0.83, 0.83, 0.81)
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

/** DeckStudioButtonStyle: ink capsule (primary) or white with a hairline (secondary). */
@Composable
fun StudioButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = true, enabled: Boolean = true,
                 icon: String? = null, fillWidth: Boolean = false, compactText: Boolean = false) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.985f else 1f, tween(140), label = "studioPress")
    val shape = RoundedCornerShape(DeckStudioMetrics.controlRadius)
    val foreground = if (primary) Color.White else DeckStudioPalette.ink
    Row(modifier.scale(scale).alpha(if (!enabled) 0.45f else if (pressed) 0.8f else 1f)
        .defaultMinSize(minHeight = DeckStudioMetrics.controlHeight)
        .background(if (primary) DeckStudioPalette.ink else DeckStudioPalette.surfaceElevated, shape)
        .border(1.dp, if (primary) Color.Transparent else DeckStudioPalette.separator, shape)
        .clip(shape)
        .clickable(interaction, null, enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onClick() }
        .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { SfImage(it, foreground, 17.dp) }
        Text(title, color = foreground, style = if (compactText) StudioText.subheadline.weight(SfWeight.semibold) else StudioText.body.weight(SfWeight.semibold),
            maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (fillWidth) Spacer(Modifier.width(0.dp))
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
fun Modifier.studioPanel(): Modifier = fillMaxWidth()
    .background(DeckStudioPalette.surface, RoundedCornerShape(DeckStudioMetrics.panelRadius))
    .padding(DeckStudioMetrics.panelPadding)

@Composable
fun StudioPanel(modifier: Modifier = Modifier, spacing: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.studioPanel(), verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}

@Composable
fun DeckStudioNotice(title: String, message: String, icon: String = "info.circle", modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SfImage(icon, DeckStudioPalette.ink, 18.dp, Modifier.padding(top = 1.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            Text(message, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        }
    }
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

/** DeckStudioArtwork: the commander's art cropped as a cover (hero) or a whole card. */
@Composable
fun DeckStudioArtwork(name: String, modifier: Modifier = Modifier, hero: Boolean = false, colors: List<String>? = null) {
    CardArtwork(name, modifier, artOnly = hero) {
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

/** An iOS DisclosureGroup: title row with a chevron that turns, content below. */
@Composable
fun StudioDisclosure(title: String, modifier: Modifier = Modifier, initiallyExpanded: Boolean = false, titleStyle: TextStyle = StudioText.body,
                     color: Color = DeckStudioPalette.ink, icon: String? = null, label: (@Composable RowScope.() -> Unit)? = null,
                     content: @Composable ColumnScope.() -> Unit) {
    var expanded by rememberSaveable(title) { mutableStateOf(initiallyExpanded) }
    val rotation by animateFloatAsState(if (expanded) 90f else 0f, tween(180), label = "disclosure")
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 32.dp).clickable(role = Role.Button) { expanded = !expanded }
            .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (label != null) Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = label)
            else {
                icon?.let { SfImage(it, color, (titleStyle.fontSize.value + 1f).dp) }
                Text(title, Modifier.weight(1f), color = color, style = titleStyle)
            }
            SfImage("chevron.right", DeckStudioPalette.ink, 14.dp, Modifier.rotate(rotation))
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
    Column(modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp))
        .border(1.dp, DeckStudioPalette.separator, RoundedCornerShape(12.dp)).padding(12.dp)) {
        StudioDisclosure("Online card images are off", label = {
            SfImage("photo.on.rectangle.angled", DeckStudioPalette.ink, 15.dp)
            Text("Online card images are off", color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
        }) {
            Text("Turn on artwork across the app to send displayed card names and your IP address to Scryfall. Saved images remain available offline. Change this anytime in Artwork & privacy.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
            StudioPlainButton("Turn on", { setRemote(true) }, style = StudioText.caption.weight(SfWeight.semibold),
                modifier = Modifier.semantics { contentDescription = "deckStudio.artwork.enable" })
        }
    }
}

/** NativeArtworkPreferenceView in its light Form. */
@Composable
fun NativeArtworkPreferenceRows() {
    val (remote, setRemote) = rememberArtworkConsent()
    Column(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        StudioToggle("Scryfall live images", remote, setRemote)
        Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Text("Scryfall receives card names—including your hand—and your IP address.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
    }
}

/** An iOS switch in the light appearance: green track when on, light grey when off. */
@Composable
fun StudioToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                 style: TextStyle = StudioText.body, tint: Color = rgb(0.2, 0.78, 0.35)) {
    val track by animateColorAsState(if (isOn) tint else rgb(0.91, 0.91, 0.92), label = "studioToggle")
    val knob by animateDpAsState(if (isOn) 22.dp else 2.dp, spring(0.8f, 600f), label = "studioKnob")
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f)
        .clickable(enabled = enabled, interactionSource = remember { MutableInteractionSource() }, indication = null) { onChange(!isOn) }
        .semantics { role = Role.Switch; stateDescription = if (isOn) "On" else "Off"; contentDescription = title },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, Modifier.weight(1f), color = DeckStudioPalette.ink, style = style)
        Box(Modifier.size(51.dp, 31.dp).background(track, CircleShape)) {
            Box(Modifier.offset(x = knob, y = 2.dp).size(27.dp).shadow(3.dp, CircleShape).background(Color.White, CircleShape))
        }
    }
}

/** A Stepper in the light appearance: the label, then a −|+ capsule. */
@Composable
fun StudioStepper(label: String, value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                  style: TextStyle = StudioText.body) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = DeckStudioPalette.ink, style = style)
        Row(Modifier.size(94.dp, 32.dp).background(rgb(0.46, 0.46, 0.5).copy(alpha = 0.12f), RoundedCornerShape(8.dp)), verticalAlignment = Alignment.CenterVertically) {
            val canDecrease = enabled && value > range.first; val canIncrease = enabled && value < range.last
            Box(Modifier.weight(1f).height(32.dp).clickable(enabled = canDecrease) { onChange(value - 1) }
                .semantics { contentDescription = "Decrement $label" }, contentAlignment = Alignment.Center) {
                SfImage("minus", DeckStudioPalette.ink.copy(alpha = if (canDecrease) 1f else 0.3f), 14.dp)
            }
            Box(Modifier.width(1.dp).height(18.dp).background(DeckStudioPalette.ink.copy(alpha = 0.15f)))
            Box(Modifier.weight(1f).height(32.dp).clickable(enabled = canIncrease) { onChange(value + 1) }
                .semantics { contentDescription = "Increment $label" }, contentAlignment = Alignment.Center) {
                SfImage("plus", DeckStudioPalette.ink.copy(alpha = if (canIncrease) 1f else 0.3f), 14.dp)
            }
        }
    }
}

/** Picker(.segmented) in the light appearance: grey track, white raised segment. */
@Composable
fun <T> StudioSegmented(options: List<T>, selected: T, onSelect: (T) -> Unit, title: (T) -> String, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Row(modifier.fillMaxWidth().height(32.dp).alpha(if (enabled) 1f else 0.45f)
        .background(rgb(0.46, 0.46, 0.5).copy(alpha = 0.12f), RoundedCornerShape(9.dp)).padding(2.dp)) {
        for (option in options) {
            val isSelected = option == selected
            Box(Modifier.weight(1f).height(28.dp)
                .then(if (isSelected) Modifier.shadow(2.dp, RoundedCornerShape(7.dp)).background(Color.White, RoundedCornerShape(7.dp)) else Modifier)
                .clickable(enabled = enabled) { onSelect(option) }.semantics { stateDescription = if (isSelected) "Selected" else "" },
                contentAlignment = Alignment.Center) {
                Text(title(option), color = Color.Black, style = sf(13f, if (isSelected) SfWeight.semibold else SfWeight.medium), maxLines = 1)
            }
        }
    }
}

/** A light pull-down Menu. */
@Composable
fun StudioMenu(entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true, label: @Composable () -> Unit) =
    BoardMenu(entries, modifier, enabled, light = true, label = label)

/** A menu-style Picker label: the selected title and ⌃⌄. */
@Composable
fun StudioMenuPicker(selectedTitle: String, entries: () -> List<MenuEntry>, modifier: Modifier = Modifier, enabled: Boolean = true,
                     style: TextStyle = StudioText.body) {
    StudioMenu(entries, modifier, enabled) {
        Row(Modifier.defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(selectedTitle, color = DeckStudioPalette.ink, style = style, maxLines = 1, overflow = TextOverflow.Ellipsis)
            SfImage("chevron.up.chevron.down", DeckStudioPalette.ink, 12.dp)
        }
    }
}

/** A search field: magnifying glass, text, clear button, on a white rounded fill. */
@Composable
fun StudioSearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, radius: Dp = 14.dp,
                      padding: Dp = 14.dp, clearLabel: String = "Clear search", trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(radius)).padding(horizontal = padding, vertical = if (padding > 12.dp) padding else 0.dp)
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
    Box(modifier.background(Color.White, RoundedCornerShape(6.dp)).border(0.5.dp, rgb(0.78, 0.78, 0.8), RoundedCornerShape(6.dp))
        .defaultMinSize(minHeight = 34.dp).padding(horizontal = 8.dp, vertical = 7.dp), contentAlignment = Alignment.CenterStart) {
        StudioTextInput(value, onChange, placeholder, Modifier.fillMaxWidth(), keyboardType = keyboardType, capitalization = capitalization,
            enabled = enabled, onSubmit = onSubmit, imeAction = if (onSubmit != null) ImeAction.Search else ImeAction.Done)
    }
}

/** The iOS 26 navigation bar in the light appearance: glass capsule buttons around a centred title. */
@Composable
fun StudioNavBar(title: String, modifier: Modifier = Modifier, background: Color = DeckStudioPalette.background,
                 leading: (@Composable RowScope.() -> Unit)? = null, trailing: (@Composable RowScope.() -> Unit)? = null,
                 principal: (@Composable () -> Unit)? = null) {
    // The centred title shows only when it clears both toolbar groups, as UIKit's inline title does.
    androidx.compose.ui.layout.Layout({
        Box { leading?.let { Row(verticalAlignment = Alignment.CenterVertically, content = it) } }
        Box { if (principal != null) principal() else Text(title, color = DeckStudioPalette.ink, style = sf(17f, SfWeight.semibold), maxLines = 1) }
        Box { trailing?.let { Row(verticalAlignment = Alignment.CenterVertically, content = it) } }
    }, modifier.fillMaxWidth().background(background).statusBarsPadding().height(56.dp).padding(horizontal = 16.dp)) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val start = measurables[0].measure(loose); val end = measurables[2].measure(loose)
        val middle = measurables[1].measure(loose)
        val width = constraints.maxWidth; val height = constraints.maxHeight
        val gap = 8.dp.roundToPx()
        val titleX = (width - middle.width) / 2
        val fits = titleX >= start.width + (if (start.width > 0) gap else 0) && titleX + middle.width <= width - end.width - (if (end.width > 0) gap else 0)
        layout(width, height) {
            start.place(0, (height - start.height) / 2)
            if (fits) middle.place(titleX, (height - middle.height) / 2)
            end.place(width - end.width, (height - end.height) / 2)
        }
    }
}

/** A glass capsule holding one or more toolbar items (iOS 26 groups adjacent bar buttons). */
@Composable
fun StudioGlassGroup(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.height(44.dp).shadow(6.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.1f))
        .background(DeckStudioPalette.surface.copy(alpha = 0.96f), CircleShape).clip(CircleShape).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically, content = content)
}

/** A text item inside a glass group. */
@Composable
fun StudioGlassText(title: String, onClick: () -> Unit, enabled: Boolean = true, bold: Boolean = false, label: String? = null) {
    Box(Modifier.height(44.dp).defaultMinSize(minWidth = 44.dp).alpha(if (enabled) 1f else 0.35f)
        .clickable(enabled = enabled, role = Role.Button) { onClick() }.padding(horizontal = 12.dp)
        .semantics { label?.let { contentDescription = it } }, contentAlignment = Alignment.Center) {
        Text(title, color = DeckStudioPalette.ink, style = sf(17f, if (bold) SfWeight.semibold else SfWeight.regular), maxLines = 1)
    }
}

/** An icon item inside a glass group. */
@Composable
fun StudioGlassIcon(icon: String, label: String, onClick: () -> Unit, enabled: Boolean = true) {
    Box(Modifier.size(44.dp).alpha(if (enabled) 1f else 0.35f).clickable(enabled = enabled, role = Role.Button) { onClick() }
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) { SfImage(icon, DeckStudioPalette.ink, 20.dp) }
}

/** ContentUnavailableView: a large grey symbol, a bold title and a description. */
@Composable
fun StudioContentUnavailable(title: String, systemImage: String, description: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 24.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SfImage(systemImage, DeckStudioPalette.secondaryInk, 44.dp)
        Text(title, color = DeckStudioPalette.ink, style = sf(22f, SfWeight.bold), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Text(description, color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
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
    Box(modifier.fillMaxSize().background(DeckStudioPalette.background), content = content)
}
