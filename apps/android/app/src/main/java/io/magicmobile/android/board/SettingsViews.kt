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
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaCloseButton
import io.magicmobile.android.menus.ArenaDiamond
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaSegmented
import io.magicmobile.android.menus.LocalArenaBoard
import io.magicmobile.android.menus.LocalArenaPanelClose
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaGlassBackground
import io.magicmobile.android.menus.arenaScrollFade
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
import io.magicmobile.android.game.BoardFocusTracker
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
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernSlider
import io.magicmobile.android.ui.TavernToggle
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.tavernPanelChrome

/** On the menu's Options pages the settings lie flat on the panel's glass, as Arena's do, instead of in cards (`\.arenaOptionsFlat`). */
val LocalArenaOptionsFlat = compositionLocalOf { false }

/**
 * One group of settings (TavernSettingsPanel): a leather panel in brass trim with parchment text; in the Arena menus a
 * lighter pane in the gold hairline on the panel's glass, and flat on the glass on Options' pages.
 */
fun Modifier.tavernSettingsPanel(): Modifier = composed {
    val arena = LocalArenaBoard.current
    val flat = LocalArenaOptionsFlat.current
    val shape = RoundedCornerShape(12.dp)
    when {
        arena && flat -> Modifier.fillMaxWidth().padding(vertical = 2.dp)
        arena -> Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.045f), shape)
            .border(0.8.dp, ArenaGlass.hairlineTop.copy(alpha = 0.47f), shape).padding(horizontal = 14.dp, vertical = 10.dp)
        else -> Modifier.fillMaxWidth().tavernPanelChrome(true, 10.dp).padding(horizontal = 14.dp, vertical = 10.dp)
    }
}

object PortraitModePreference { const val key = "magicmobile.portraitModeEnabled" }

@Composable
fun PortraitModeToggle(isOn: Boolean, onChange: (Boolean) -> Unit) {
    Box(Modifier.tavernSettingsPanel()) {
        TavernToggle("Auto-Rotate", isOn, onChange, subtitle = "Portrait and landscape", color = TavernPalette.parchment)
    }
}

/** The top of the board switches to whoever's turn starts (BoardFocusTracker). On by default. */
@Composable
fun FollowTurnsToggle() {
    var isOn by AppPreferences.boolean(BoardFocusTracker.followTurnsKey, true)
    Box(Modifier.tavernSettingsPanel().semantics { contentDescription = "settings.followTurns" }) {
        TavernToggle("Follow Turns", isOn, { isOn = it }, subtitle = "Show whose turn it is at the top. A tap on an opponent holds until the next turn.",
            color = TavernPalette.parchment)
    }
}

/** `includesAudio` off where sound has a page of its own (the menu's Options). */
@Composable
fun BoardEffectsPicker(includesAudio: Boolean = true) {
    var level by AppPreferences.string(BoardFXLevel.key, BoardFXLevel.defaultValue)
    val arena = LocalArenaBoard.current
    val ink = if (arena) ArenaMenuStyle.text else TavernPalette.parchment
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // The Arena look names the choice and nothing more (no helper line).
            Text(if (arena) "Effects" else "Board Effects", color = ink, style = sf(16f, SfWeight.semibold, SfDesign.SERIF))
            if (!arena) Text("Spell, combat and life animations. Reduce Motion always limits them.", Modifier.alpha(0.65f), color = ink,
                style = sf(12f, design = SfDesign.SERIF), maxLines = 2)
        }
        if (arena) ArenaSegmented(BoardFXLevel.entries.map { it.title to it }, BoardFXLevel.of(level) ?: BoardFXLevel.FULL, { level = it.rawValue },
            Modifier.fillMaxWidth(), identifier = "settings.boardEffects", stretch = true)
        else IosSegmented(BoardFXLevel.entries.toList(), BoardFXLevel.of(level) ?: BoardFXLevel.FULL, { level = it.rawValue }, { it.title },
            Modifier.semantics { contentDescription = "settings.boardEffects" })
        if (includesAudio) GameAudioSettings()
    }
}

/** Hearth or Arena (BoardMode): the board's layout, chosen here and in the game menu; it changes at once, mid-game too. */
@Composable
fun BoardModePicker() {
    var mode by AppPreferences.string(io.magicmobile.android.game.BoardMode.key, io.magicmobile.android.game.BoardMode.defaultValue)
    val arena = LocalArenaBoard.current
    val ink = if (arena) ArenaMenuStyle.text else TavernPalette.parchment
    val current = io.magicmobile.android.game.BoardMode.resolved(mode)
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // Under the page's own "Board" title the picker is the table you play on (no repeated label, no helper line).
            Text(if (arena) "Table" else "Board", color = ink, style = sf(16f, SfWeight.semibold, SfDesign.SERIF))
            if (!arena) Text(current.summary, Modifier.alpha(0.65f), color = ink, style = sf(12f, design = SfDesign.SERIF), maxLines = 2)
        }
        if (arena) ArenaSegmented(io.magicmobile.android.game.BoardMode.entries.map { it.title to it }, current, { mode = it.rawValue },
            Modifier.fillMaxWidth(), identifier = "settings.boardMode", stretch = true)
        else IosSegmented(io.magicmobile.android.game.BoardMode.entries.toList(), current, { mode = it.rawValue }, { it.title },
            Modifier.semantics { contentDescription = "settings.boardMode" })
    }
}

/** Card Frames, kept per board mode (CardFramesPreference): tavern frames on battlefield cards, or the card's art without them. */
@Composable
fun CardFramesToggle() {
    val mode by AppPreferences.string(io.magicmobile.android.game.BoardMode.key, io.magicmobile.android.game.BoardMode.defaultValue)
    var hearth by AppPreferences.boolean(io.magicmobile.android.game.CardFramesPreference.hearthKey, io.magicmobile.android.game.CardFramesPreference.hearthDefault)
    var arenaFrames by AppPreferences.boolean(io.magicmobile.android.game.CardFramesPreference.arenaKey, io.magicmobile.android.game.CardFramesPreference.arenaDefault)
    val isArena = io.magicmobile.android.game.BoardMode.resolved(mode) == io.magicmobile.android.game.BoardMode.ARENA
    Box(Modifier.tavernSettingsPanel()) {
        TavernToggle("Card Frames", if (isArena) arenaFrames else hearth, { on -> if (isArena) arenaFrames = on else hearth = on },
            Modifier.semantics { contentDescription = "settings.cardFrames" },
            subtitle = if (isArena) "Tavern frames on the Arena board's battlefield cards. Off, they show the card's art without the frame."
                else "Tavern frames on Hearth's battlefield cards. Off, they show the card's art without the frame.",
            color = TavernPalette.parchment)
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
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TavernToggle("Effect Sounds", effects, { on -> effects = on }, Modifier.semantics { contentDescription = "settings.boardSounds" },
            color = TavernPalette.parchment)
        if (effects) TavernSlider(effectsVolume.toFloat(), { effectsVolume = it.toDouble(); GameAudio.play(GameSound.UI_TICK) }, label = "Effects volume")
        TavernToggle("Music", musicOn, { on ->
            // A level of zero reads as off, and switching music back on brings back a level you can hear.
            music = on
            if (on && musicVolume <= 0.02) musicVolume = GameAudio.defaultMusicVolume
            GameAudio.settingsChanged()
        }, color = TavernPalette.parchment)
        if (musicOn) TavernSlider(musicVolume.toFloat(), { musicVolume = it.toDouble(); GameAudio.settingsChanged() }, label = "Music volume")
        var pushToTalk by AppPreferences.boolean(io.magicmobile.android.game.VoiceChatRules.PUSH_TO_TALK_KEY, false)
        TavernToggle("Push to Talk", pushToTalk, { on -> pushToTalk = on }, Modifier.semantics { contentDescription = "settings.pushToTalk" },
            color = TavernPalette.parchment)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // The Arena look drops the helper line (AGENTS.md); the Hearth board's game menu keeps it.
            if (LocalArenaBoard.current) Spacer(Modifier.weight(1f))
            else Text("Sounds follow your phone's media volume.", Modifier.weight(1f).alpha(0.6f), color = TavernPalette.parchment, style = sf(12f, design = SfDesign.SERIF))
            // In Arena's Options the Sound Lab opens as a page of the panel, not a sheet.
            val openLab = io.magicmobile.android.menus.LocalArenaOpenSoundLab.current
            TavernPlaqueButton("Sound Lab", { if (openLab != null) openLab() else soundLabOpen = true }, Modifier.semantics { contentDescription = "settings.soundLab" },
                kind = TavernButtonKind.SECONDARY, systemImage = "waveform")
        }
    }
    if (soundLabOpen) BoardSheet({ soundLabOpen = false }, ArenaGlass.bottom, skipPartiallyExpanded = true) { SoundLabView(done = { soundLabOpen = false }) }
}

/** Orchestral stingers cut from Kevin MacLeod pieces, credited with the tracks. */
object MusicCredits { val stingers = listOf("Discovery Hit", "Greta Sting", "Danse Macabre - Big Hit 1") }

/**
 * SoundLabView.swift: every game sound and music track, auditionable, with a switch per category and the credits the music
 * license asks for. An Arena page (Caleb, 2026-10-22: no sheets in the menus): inside Options it opens from Audio with a back
 * chevron; on its own (the game menu's sheet) it closes with its own button.
 */
@Composable
fun SoundLabView(back: (() -> Unit)? = null, done: (() -> Unit)? = null) {
    var menuChoice by AppPreferences.string(GameMusic.MENU.choiceKey, "shuffle")
    var gameChoice by AppPreferences.string(GameMusic.GAME.choiceKey, "shuffle")
    var previewing by remember { mutableStateOf<String?>(null) }
    val panelClose = LocalArenaPanelClose.current
    DisposableEffect(Unit) { onDispose { GameAudio.endPreview() } }

    /** A track by its title alone: the composer is in the credits below. */
    @Composable
    fun trackRow(title: String, selected: Boolean, previewID: String?, identifier: String, action: () -> Unit) {
        BrandPressable(action, Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).testTag(identifier)
            .semantics(mergeDescendants = true) { this.selected = selected }) {
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                // Arena's chosen diamond, lit gold.
                ArenaDiamond(selected, Modifier.width(16.dp))
                Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, if (selected) SfWeight.bold else SfWeight.medium))
                if (previewID != null) Box(Modifier.size(34.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape)
                    .border(1.dp, ArenaGlass.hairline, CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                    SfImage(if (previewing == previewID) "speaker.wave.2.fill" else "play.fill", ArenaMenuStyle.gold, 13.dp)
                }
            }
        }
    }

    @Composable
    fun musicPanel(scene: GameMusic, choice: String, setChoice: (String) -> Unit) {
        Column(Modifier.arenaCard(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(scene.title, Modifier.padding(bottom = 4.dp), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(17f, SfWeight.bold))
            trackRow("Shuffle all", choice == "shuffle", null, "soundlab.music.${scene.rawValue}.shuffle") {
                setChoice("shuffle"); GameAudio.settingsChanged(true)
            }
            for (track in scene.tracks) trackRow(track.title, choice == track.file, track.file, "soundlab.music.${scene.rawValue}.${track.file}") {
                setChoice(track.file); previewing = track.file; GameAudio.preview(track, scene)
            }
        }
    }

    CompositionLocalProvider(LocalArenaBoard provides true, LocalContentColor provides ArenaMenuStyle.text) {
        // Inside a panel the panel's glass shows; on its own (the game menu's sheet) it draws its own.
        Column(Modifier.fillMaxWidth().then(if (panelClose == null) Modifier.arenaGlassBackground() else Modifier)) {
            // The Options pages' head: the back chevron on the left, the title centred in serif, the close button on the right.
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp).padding(top = 6.dp, bottom = 2.dp)
                .drawBehind { drawRect(ArenaGlass.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()), alpha = 0.45f) }) {
                FitText("Sound Lab", ArenaMenuStyle.font(26f, SfWeight.bold), Modifier.align(Alignment.Center).padding(horizontal = 56.dp).semantics { heading() },
                    color = ArenaMenuStyle.text, minimumScale = 0.7f)
                if (back != null) BrandPressable({ GameAudio.play(GameSound.UI_BACK); back() }, Modifier.align(Alignment.CenterStart).size(44.dp)
                    .testTag("panel.back").semantics { contentDescription = "Back"; role = Role.Button }) {
                    SfImage("chevron.left", ArenaMenuStyle.text, 17.dp)
                }
                ArenaCloseButton({ (panelClose ?: done)?.invoke() }, Modifier.align(Alignment.CenterEnd), identifier = "soundlab.done")
            }
            Column(Modifier.fillMaxWidth().arenaScrollFade(48.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 620.dp).fillMaxWidth().padding(16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    ArenaCaps("Music")
                    musicPanel(GameMusic.MENU, menuChoice) { menuChoice = it }
                    musicPanel(GameMusic.GAME, gameChoice) { gameChoice = it }
                    ArenaCaps("Sound effects", modifier = Modifier.padding(top = 6.dp))
                    GameSoundCategory.entries.forEach { SoundLabCategory(it) }
                    ArenaCaps("Credits", modifier = Modifier.padding(top = 6.dp))
                    Column(Modifier.arenaCard(14.dp).testTag("soundlab.credits"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        creditBlock("Music", (GameMusic.MENU.tracks + GameMusic.GAME.tracks).map { "“${it.title}” Kevin MacLeod (incompetech.com)" } +
                            MusicCredits.stingers.map { "“$it” Kevin MacLeod (incompetech.com), excerpt" } +
                            listOf("Licensed under Creative Commons: By Attribution 4.0 License", "http://creativecommons.org/licenses/by/4.0/"))
                        creditBlock("Sound effects", listOf(
                            "Recordings from the Sonniss.com GDC Game Audio Bundles (royalty-free), by David Dumais Audio, Sound Spark LLC, Gamemaster Audio, Articulated Sounds, Airborne Sound, Double Trouble Audio, Bluezone, 3maze, Timothy McHugh, Sound Ex Machina and more.",
                            "Card recordings from Kenney.nl Casino Audio (CC0)."))
                        creditBlock("Table art", listOf(
                            "3D props made with Meshy (meshy.ai). The medallion, corner ornament, candle and tankard are licensed under Creative Commons: By Attribution 4.0 License.",
                            "Wood and leather textures from Poly Haven (polyhaven.com, CC0)."))
                    }
                }
            }
        }
    }
}

@Composable
private fun creditBlock(title: String, lines: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        ArenaCaps(title, 9.5f)
        lines.forEach { Text(it, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium)) }
    }
}

/** One group of effects: its switch and a chip per sound. */
@Composable
private fun SoundLabCategory(category: GameSoundCategory) {
    var enabled by AppPreferences.boolean(category.key, true)
    Column(Modifier.arenaCard(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TavernToggle(category.title, enabled, { enabled = it }, Modifier.testTag("soundlab.category.${category.rawValue}"), subtitle = category.detail)
        val sounds = GameSound.sounds(category)
        Box(Modifier.alpha(if (enabled) 1f else 0.6f)) {
            AdaptiveGrid(138f, 8f, sounds.size) { index ->
                val sound = sounds[index]
                BrandPressable({ GameAudio.play(sound, audition = true) }, Modifier.fillMaxWidth().testTag("soundlab.play.${sound.rawValue}")
                    .semantics { contentDescription = "Play ${sound.title}" }) {
                    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 40.dp).background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(10.dp))
                        .border(0.9.dp, ArenaGlass.hairline, RoundedCornerShape(10.dp)).padding(horizontal = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("play.fill", ArenaMenuStyle.gold, 10.dp)
                        FitText(sound.title, ArenaMenuStyle.font(13f, SfWeight.semibold), Modifier.weight(1f),
                            color = if (enabled) ArenaMenuStyle.text else ArenaMenuStyle.dim, minimumScale = 0.8f)
                    }
                }
            }
        }
    }
}

