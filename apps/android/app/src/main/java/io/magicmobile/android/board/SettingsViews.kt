package io.magicmobile.android.board

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.R
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BrandDivider
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameBoardDesignTokens
import io.magicmobile.android.ui.GameBoardTheme
import io.magicmobile.android.ui.GameMusic
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.GameSoundCategory
import io.magicmobile.android.ui.IosSegmented
import io.magicmobile.android.ui.IosSlider
import io.magicmobile.android.ui.IosTextButton
import io.magicmobile.android.ui.IosToggle
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.MagicPanelMaterial
import io.magicmobile.android.ui.MagicPanelProminence
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.brandPanel
import io.magicmobile.android.ui.magicPanel
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/** The swatch frame shared by the battlefield and menu pickers. */
@Composable
private fun AppearanceSwatch(title: String, selected: Boolean, modifier: Modifier = Modifier, art: @Composable () -> Unit) {
    Column(modifier.background(Color.Black.copy(alpha = 0.3f), RoundedCornerShape(10.dp))
        .border(2.dp, if (selected) MagicPalette.antiqueGold else Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp)).padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.fillMaxWidth().height(68.dp).clip(RoundedCornerShape(GameBoardDesignTokens.Radius.panel))) { art() }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            FitText(title, SfText.caption(SfWeight.semibold), Modifier.weight(1f), color = MagicPalette.parchment, minimumScale = 0.7f)
            SfImage(if (selected) "checkmark.circle.fill" else "circle", MagicPalette.parchment, 13.dp)
        }
    }
}

@Composable
fun BoardAppearancePicker() {
    var appearance by AppPreferences.string(BoardAppearancePreference.key, BoardAppearancePreference.defaultValue)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Battlefield", color = MagicPalette.parchment, style = SfText.headline())
        BoxWithConstraints {
            val columns = maxOf(1, ((maxWidth.value + 12) / (140 + 12)).toInt())
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                BattlefieldBackdrop.entries.chunked(columns).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { theme ->
                            AppearanceSwatch(theme.title, appearance == theme.rawValue, Modifier.weight(1f).clickable { appearance = theme.rawValue }
                                .semantics { contentDescription = "${theme.title} battlefield" }) {
                                BattlefieldBackdropArt(theme, Modifier.fillMaxSize())
                            }
                        }
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        Text("Works in portrait and landscape.", color = MagicPalette.parchment.copy(alpha = 0.65f), style = SfText.caption())
    }
}

@Composable
fun MenuAppearanceArt(value: String, modifier: Modifier = Modifier) {
    when (value) {
        "arena" -> Image(painterResource(R.drawable.commander_stone_arena), null, modifier, contentScale = ContentScale.Crop)
        "midnight" -> Box(modifier.background(midnightGradient))
        else -> Image(painterResource(R.drawable.mage_mobile_menu_background), null, modifier, contentScale = ContentScale.Crop)
    }
}

/** The menu background picker, independent of the battlefield's. */
@Composable
fun MenuAppearancePicker() {
    var appearance by AppPreferences.string(MenuAppearancePreference.key, MenuAppearancePreference.defaultValue)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Menu", color = MagicPalette.parchment, style = SfText.headline())
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            for ((title, value) in listOf("Tavern" to "tavern", "Stone Arena" to "arena", "Midnight" to "midnight")) {
                AppearanceSwatch(title, appearance == value, Modifier.weight(1f).clickable { appearance = value }
                    .semantics { contentDescription = "$title menu background" }) { MenuAppearanceArt(value, Modifier.fillMaxSize()) }
            }
        }
        Text("Saved on this device. The battlefield keeps its own setting.", color = MagicPalette.parchment.copy(alpha = 0.65f), style = SfText.caption())
    }
}

object PortraitModePreference { const val key = "magicmobile.portraitModeEnabled" }

@Composable
fun PortraitModeToggle(isOn: Boolean, onChange: (Boolean) -> Unit) {
    Box(Modifier.fillMaxWidth().magicPanel(MagicPanelMaterial.IRON, MagicPanelProminence.QUIET, cornerRadius = 9.dp, padding = 10.dp)) {
        IosToggle(isOn, onChange) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Auto-Rotate", color = Color.White, style = SfText.callout(SfWeight.black))
                Text("Portrait and landscape", color = Color.White.copy(alpha = 0.58f), style = SfText.caption2(SfWeight.semibold), maxLines = 2)
            }
        }
    }
}

@Composable
fun BoardEffectsPicker() {
    var level by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    Column(Modifier.fillMaxWidth().magicPanel(MagicPanelMaterial.IRON, MagicPanelProminence.QUIET, cornerRadius = 9.dp, padding = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Board Effects", color = Color.White, style = SfText.callout(SfWeight.black))
            Text("Spell, combat and life animations. Reduce Motion always limits them.", color = Color.White.copy(alpha = 0.58f),
                style = SfText.caption2(SfWeight.semibold), maxLines = 2)
        }
        IosSegmented(BoardFXLevel.entries.toList(), BoardFXLevel.of(level) ?: BoardFXLevel.FULL, { level = it.rawValue }, { it.title },
            Modifier.semantics { contentDescription = "settings.boardEffects" })
        GameAudioSettings()
    }
}

/** Sound effects and music, each with a level. Changes apply immediately. */
@Composable
fun GameAudioSettings() {
    var effects by AppPreferences.boolean(GameAudio.effectsKey, true)
    var music by AppPreferences.boolean(GameAudio.musicKey, true)
    var effectsVolume by AppPreferences.double(GameAudio.effectsVolumeKey, 0.9)
    var musicVolume by AppPreferences.double(GameAudio.musicVolumeKey, GameAudio.defaultMusicVolume)
    var soundLabOpen by remember { mutableStateOf(false) }
    val musicOn = music && musicVolume > 0
    val labelStyle = SfText.caption(SfWeight.bold)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        IosToggle(effects, { on -> effects = on; if (on) GameAudio.play(GameSound.UI_TOGGLE) }, tint = GameBoardTheme.antiqueGold) {
            Text("Effect Sounds", color = Color.White.copy(alpha = 0.85f), style = labelStyle)
        }
        if (effects) IosSlider(effectsVolume.toFloat(), { effectsVolume = it.toDouble(); GameAudio.play(GameSound.UI_TICK) }, label = "Effects volume")
        IosToggle(musicOn, { on ->
            // A level of zero reads as off, and switching music back on brings back a level you can hear.
            music = on
            if (on && musicVolume <= 0.02) musicVolume = GameAudio.defaultMusicVolume
            GameAudio.settingsChanged()
        }, tint = GameBoardTheme.antiqueGold) { Text("Music", color = Color.White.copy(alpha = 0.85f), style = labelStyle) }
        if (musicOn) IosSlider(musicVolume.toFloat(), { musicVolume = it.toDouble(); GameAudio.settingsChanged() }, label = "Music volume")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Sounds follow your phone's media volume.", Modifier.weight(1f), color = Color.White.copy(alpha = 0.5f), style = SfText.caption2(SfWeight.semibold))
            Row(Modifier.defaultMinSize(minHeight = 34.dp).background(Color.White.copy(alpha = 0.1f), CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape).clickable { soundLabOpen = true }.padding(horizontal = 10.dp)
                .semantics { contentDescription = "settings.soundLab" },
                horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("waveform", Color.White.copy(alpha = 0.85f), 12.dp)
                Text("Sound Lab", color = Color.White.copy(alpha = 0.85f), style = SfText.caption(SfWeight.heavy))
            }
        }
    }
    if (soundLabOpen) BoardSheet({ soundLabOpen = false }, BrandTheme.canvas, skipPartiallyExpanded = true) { SoundLabView { soundLabOpen = false } }
}

/** Orchestral stingers cut from Kevin MacLeod pieces, credited with the tracks. */
object MusicCredits { val stingers = listOf("Discovery Hit", "Greta Sting", "Danse Macabre - Big Hit 1") }

/** Every game sound and music track, auditionable, with a switch per category and the credits the music license asks for. */
@Composable
fun SoundLabView(done: () -> Unit) {
    var menuChoice by AppPreferences.string(GameMusic.MENU.choiceKey, "shuffle")
    var gameChoice by AppPreferences.string(GameMusic.GAME.choiceKey, "shuffle")
    var previewing by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { GameAudio.endPreview() } }

    @Composable
    fun trackRow(title: String, subtitle: String, selected: Boolean, previewID: String?, action: () -> Unit) {
        BrandPressable(action, Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)) {
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(if (selected) "checkmark.circle.fill" else "circle", if (selected) BrandTheme.ember else BrandTheme.border, 22.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(title, color = BrandTheme.ink, style = sf(15f, SfWeight.bold))
                    Text(subtitle, color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.semibold))
                }
                if (previewID != null) Box(Modifier.size(34.dp).background(BrandTheme.surfaceRaised, CircleShape), contentAlignment = Alignment.Center) {
                    SfImage(if (previewing == previewID) "speaker.wave.2.fill" else "play.fill", BrandTheme.ember, 14.dp)
                }
            }
        }
    }

    @Composable
    fun musicPanel(scene: GameMusic, choice: String, setChoice: (String) -> Unit) {
        Column(Modifier.fillMaxWidth().brandPanel(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(scene.title, color = BrandTheme.ink, style = sf(17f, SfWeight.heavy))
            Text(if (scene == GameMusic.MENU) "Plays in menus and while you build decks." else "Plays under the game, a little quieter.",
                Modifier.padding(bottom = 6.dp), color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.semibold))
            trackRow("Shuffle all", "A new track each time", choice == "shuffle", null) { setChoice("shuffle"); GameAudio.settingsChanged(true) }
            for (track in scene.tracks) trackRow(track.title, "Kevin MacLeod", choice == track.file, track.file) {
                setChoice(track.file); previewing = track.file; GameAudio.preview(track, scene)
            }
        }
    }

    Column(Modifier.fillMaxWidth().background(BrandTheme.canvas)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            Text("Sound Lab", color = BrandTheme.ink, style = SfText.headline())
            Spacer(Modifier.weight(1f))
            IosTextButton("Done", done, color = BrandTheme.ember, bold = true)
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text("Tap any sound to hear it. Switch off a whole group if it gets in the way. Your picks are saved on this phone.",
                color = BrandTheme.inkSecondary, style = sf(14f, SfWeight.semibold))
            BrandDivider(title = "Music")
            musicPanel(GameMusic.MENU, menuChoice) { menuChoice = it }
            musicPanel(GameMusic.GAME, gameChoice) { gameChoice = it }
            BrandDivider(title = "Sound effects")
            GameSoundCategory.entries.forEach { SoundLabCategory(it) }
            BrandDivider(title = "Credits")
            Column(Modifier.fillMaxWidth().brandPanel(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                creditBlock("Music", (GameMusic.MENU.tracks + GameMusic.GAME.tracks).map { "“${it.title}” Kevin MacLeod (incompetech.com)" } +
                    MusicCredits.stingers.map { "“$it” Kevin MacLeod (incompetech.com), excerpt" } +
                    listOf("Licensed under Creative Commons: By Attribution 4.0 License", "http://creativecommons.org/licenses/by/4.0/"))
                creditBlock("Sound effects", listOf(
                    "Recordings from the Sonniss.com GDC Game Audio Bundles (royalty-free), by David Dumais Audio, Sound Spark LLC, Gamemaster Audio, Articulated Sounds, Airborne Sound, Double Trouble Audio, Bluezone, 3maze, Timothy McHugh, Sound Ex Machina and more.",
                    "Card recordings from Kenney.nl Casino Audio (CC0)."))
            }
        }
    }
}

@Composable
private fun creditBlock(title: String, lines: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title.uppercase(), color = BrandTheme.ember, style = sf(11f, SfWeight.heavy, tracking = 1.8f))
        lines.forEach { Text(it, color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.medium)) }
    }
}

/** One group of effects: its switch and a chip per sound. */
@Composable
private fun SoundLabCategory(category: GameSoundCategory) {
    var enabled by AppPreferences.boolean(category.key, true)
    Column(Modifier.fillMaxWidth().brandPanel(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosToggle(enabled, { enabled = it }, tint = BrandTheme.ember) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(category.title, color = BrandTheme.ink, style = sf(17f, SfWeight.heavy))
                Text(category.detail, color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.semibold))
            }
        }
        val sounds = GameSound.sounds(category)
        AdaptiveGrid(138f, 8f, sounds.size) { index ->
            val sound = sounds[index]
            BrandPressable({ GameAudio.play(sound, audition = true) }, Modifier.fillMaxWidth().semantics { contentDescription = "Play ${sound.title}" }) {
                Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 40.dp).background(BrandTheme.surfaceRaised, RoundedCornerShape(10.dp))
                    .border(1.dp, BrandTheme.border, RoundedCornerShape(10.dp)).padding(horizontal = 11.dp).alpha(if (enabled) 1f else 0.6f),
                    horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfImage("play.fill", BrandTheme.ember, 11.dp)
                    FitText(sound.title, sf(13f, SfWeight.bold), Modifier.weight(1f), color = if (enabled) BrandTheme.ink else BrandTheme.inkSecondary, minimumScale = 0.8f)
                }
            }
        }
    }
}
