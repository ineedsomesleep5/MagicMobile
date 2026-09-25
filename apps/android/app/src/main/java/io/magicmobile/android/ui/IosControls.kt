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
