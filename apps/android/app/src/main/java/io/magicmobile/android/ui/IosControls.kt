package io.magicmobile.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.border
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp

/** An iOS `Toggle` with the switch style: label on the left, a 51×31 switch on the right. */
@Composable
fun IosToggle(isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, tint: Color = GameBoardTheme.emeraldPriority,
              label: @Composable RowScope.() -> Unit) {
    val track by animateColorAsState(if (isOn) tint else Color.White.copy(alpha = 0.16f), label = "toggleTrack")
    val knob by animateDpAsState(if (isOn) 22.dp else 2.dp, spring(0.8f, 600f), label = "toggleKnob")
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
        .clickable(remember { MutableInteractionSource() }, null) { onChange(!isOn) }
        .semantics { role = Role.Switch; stateDescription = if (isOn) "On" else "Off" },
        verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, content = label)
        Box(Modifier.size(51.dp, 31.dp).background(track, CircleShape)) {
            Box(Modifier.offset(x = knob, y = 2.dp).size(27.dp).glow(Color.Black.copy(alpha = 0.25f), 3.dp, 14.dp).background(Color.White, CircleShape))
        }
    }
}

/** A `Picker(.segmented)`: dark capsule track, the selected segment raised. */
@Composable
fun <T> IosSegmented(options: List<T>, selected: T, onSelect: (T) -> Unit, title: (T) -> String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(32.dp).background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(9.dp)).padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(0.dp)) {
        for (option in options) {
            val isSelected = option == selected
            Box(Modifier.weight(1f).height(28.dp).background(if (isSelected) Color.White.copy(alpha = 0.28f) else Color.Transparent, RoundedCornerShape(7.dp))
                .clickable { onSelect(option) }.semantics { contentDescription = title(option); stateDescription = if (isSelected) "Selected" else "" },
                contentAlignment = Alignment.Center) {
                Text(title(option), color = Color.White, style = sf(13f, if (isSelected) SfWeight.semibold else SfWeight.medium), maxLines = 1)
            }
        }
    }
}

/** A `Slider` tinted like the iOS one (gold fill, white thumb). */
@Composable
fun IosSlider(value: Float, onChange: (Float) -> Unit, modifier: Modifier = Modifier, tint: Color = GameBoardTheme.antiqueGold, label: String = "") {
    Slider(value, onChange, modifier.fillMaxWidth().semantics { if (label.isNotEmpty()) contentDescription = label },
        colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = tint, inactiveTrackColor = Color.White.copy(alpha = 0.2f)))
}

/** A plain text button in the system blue (iOS toolbar "Done"). */
@Composable
fun IosTextButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = rgb(0.04, 0.52, 1.0), bold: Boolean = false,
                  enabled: Boolean = true) {
    Box(modifier.defaultMinSize(44.dp, 44.dp).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
        Text(title, color = if (enabled) color else color.copy(alpha = 0.4f), style = sf(17f, if (bold) SfWeight.semibold else SfWeight.regular))
    }
}

/** A `Stepper`: the label on the left, a −|+ capsule on the right. */
@Composable
fun IosStepper(label: String, value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
               color: Color = Color.White) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = color, style = sf(17f))
        Row(Modifier.size(94.dp, 32.dp).background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp)), verticalAlignment = Alignment.CenterVertically) {
            val canDecrease = enabled && value > range.first
            val canIncrease = enabled && value < range.last
            Box(Modifier.weight(1f).height(32.dp).clickable(enabled = canDecrease) { GameAudio.play(GameSound.UI_TICK); onChange(value - 1) }
                .semantics { contentDescription = "Decrement $label" }, contentAlignment = Alignment.Center) {
                SfImage("minus", Color.White.copy(alpha = if (canDecrease) 1f else 0.3f), 14.dp)
            }
            Box(Modifier.width(1.dp).height(18.dp).background(Color.White.copy(alpha = 0.2f)))
            Box(Modifier.weight(1f).height(32.dp).clickable(enabled = canIncrease) { GameAudio.play(GameSound.UI_TICK); onChange(value + 1) }
                .semantics { contentDescription = "Increment $label" }, contentAlignment = Alignment.Center) {
                SfImage("plus", Color.White.copy(alpha = if (canIncrease) 1f else 0.3f), 14.dp)
            }
        }
    }
}

/** A menu-style `Picker` outside a Form: the selected title and ⌃⌄ in the tint colour. */
@Composable
fun IosMenuPicker(selectedTitle: String, entries: () -> List<io.magicmobile.android.board.MenuEntry>, modifier: Modifier = Modifier,
                  tint: Color = BrandTheme.ember, enabled: Boolean = true, label: String = "") {
    io.magicmobile.android.board.BoardMenu(entries, modifier.semantics { if (label.isNotEmpty()) contentDescription = "$label, $selectedTitle" }, enabled) {
        Row(Modifier.defaultMinSize(minHeight = 44.dp).alpha(if (enabled) 1f else 0.45f), horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(selectedTitle, color = tint, style = sf(17f), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false))
            SfImage("chevron.up.chevron.down", tint, 12.dp)
        }
    }
}

/** A plain rounded `TextField` on the brand canvas. */
@Composable
fun IosTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, enabled: Boolean = true,
                 singleLine: Boolean = true, monospaced: Boolean = false, minHeight: androidx.compose.ui.unit.Dp = 44.dp) {
    val style = (if (monospaced) sf(15f, design = SfDesign.MONOSPACED) else sf(17f)).copy(color = BrandTheme.ink)
    androidx.compose.foundation.text.BasicTextField(value, onChange, modifier.fillMaxWidth()
        .background(BrandTheme.canvas, RoundedCornerShape(10.dp)).border(1.dp, BrandTheme.border, RoundedCornerShape(10.dp))
        .defaultMinSize(minHeight = minHeight).padding(12.dp),
        enabled = enabled, singleLine = singleLine, textStyle = style,
        cursorBrush = androidx.compose.ui.graphics.SolidColor(BrandTheme.ember),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, color = Color.White.copy(alpha = 0.3f), style = style)
                inner()
            }
        })
}

/** A sheet's navigation bar: centred title and a prominent Done capsule (iOS 26 confirmation action). */
@Composable
fun IosSheetHeader(title: String, done: () -> Unit, modifier: Modifier = Modifier, doneTitle: String = "Done", leading: (@Composable () -> Unit)? = null) {
    Box(modifier.fillMaxWidth().height(56.dp).padding(horizontal = 16.dp)) {
        leading?.let { Box(Modifier.align(Alignment.CenterStart)) { it() } }
        Text(title, Modifier.align(Alignment.Center), color = Color.White, style = sf(17f, SfWeight.semibold), maxLines = 1)
        Box(Modifier.align(Alignment.CenterEnd).defaultMinSize(minHeight = 36.dp).background(BrandTheme.ember, CircleShape)
            .clickable { GameAudio.play(GameSound.UI_CLOSE); done() }.padding(horizontal = 16.dp, vertical = 8.dp),
            contentAlignment = Alignment.Center) {
            Text(doneTitle, color = Color.White, style = sf(17f, SfWeight.semibold))
        }
    }
}

/** An inset-grouped list section: small caps header, rounded rows, optional footer. */
@Composable
fun IosListSection(header: String? = null, footer: String? = null, modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    androidx.compose.foundation.layout.Column(modifier.fillMaxWidth()) {
        header?.let { Text(it.uppercase(), Modifier.padding(start = 16.dp, bottom = 6.dp), color = Color.White.copy(alpha = 0.55f), style = sf(13f)) }
        androidx.compose.foundation.layout.Column(Modifier.fillMaxWidth().background(rgb(0.11, 0.11, 0.12), RoundedCornerShape(10.dp)), content = content)
        footer?.let { Text(it, Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), color = Color.White.copy(alpha = 0.55f), style = sf(13f)) }
    }
}

/** One row of an inset-grouped list: icon, title and an optional trailing value. */
@Composable
fun IosListRow(title: String, modifier: Modifier = Modifier, systemImage: String? = null, value: String? = null, tint: Color = Color.White,
               monospacedValue: Boolean = false, onClick: (() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .padding(horizontal = 16.dp, vertical = 11.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        systemImage?.let { SfImage(it, if (onClick != null) BrandTheme.ember else BrandTheme.ember, 17.dp) }
        Text(title, Modifier.weight(1f), color = if (onClick != null) BrandTheme.ember else tint, style = sf(17f))
        value?.let { Text(it, color = Color.White.copy(alpha = 0.55f), style = if (monospacedValue) sf(12f, design = SfDesign.MONOSPACED) else sf(17f), maxLines = 1) }
    }
}

/** An iOS 26 `.alert`: a centred rounded panel, title and message, then capsule buttons with Cancel last. */
@Composable
fun IosAlert(title: String, message: String?, actions: List<Pair<String, () -> Unit>>, cancelTitle: String = "Cancel", cancel: () -> Unit) {
    androidx.compose.ui.window.Dialog(cancel) {
        androidx.compose.foundation.layout.Column(Modifier.fillMaxWidth().background(rgb(0.16, 0.16, 0.17), RoundedCornerShape(30.dp)).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, color = Color.White, style = sf(17f, SfWeight.semibold), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            message?.let { Text(it, color = Color.White.copy(alpha = 0.75f), style = sf(13f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
            androidx.compose.foundation.layout.Spacer(Modifier.height(4.dp))
            for ((label, action) in actions) {
                Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).background(BrandTheme.ember, CircleShape).clickable { action() }
                    .padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text(label, color = Color.White, style = sf(17f, SfWeight.semibold), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }
            Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).background(Color.White.copy(alpha = 0.12f), CircleShape).clickable { cancel() },
                contentAlignment = Alignment.Center) {
                Text(cancelTitle, color = Color.White, style = sf(17f))
            }
        }
    }
}
