package io.magicmobile.android.menus

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.AutoPassAfterCast
import io.magicmobile.android.board.BoardEffectsPicker
import io.magicmobile.android.board.LocalArenaOptionsFlat
import io.magicmobile.android.board.PhaseStopsGrid
import io.magicmobile.android.board.PortraitModeToggle
import io.magicmobile.android.board.SoundLabView
import io.magicmobile.android.board.GameAudioSettings
import io.magicmobile.android.board.tavernSettingsPanel
import io.magicmobile.android.game.BoardFocusTracker
import io.magicmobile.android.game.OnDeviceSmartPass
import io.magicmobile.android.ondevice.GamePerformancePanel
import io.magicmobile.android.ondevice.SupportProject
import io.magicmobile.android.ondevice.SupportSettingsPanel
import io.magicmobile.android.studio.rememberArtworkConsent
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight

/*
 * Port of Menus/ArenaPanels.swift: menu pages as Arena's glass panels over the dimmed menu (Caleb, 2026-10-22: no sheets in
 * the menus), Options in Arena's layout, and Arena's menu question.
 */

/** Closes a menu page shown as an Arena panel (in place of dismissing a sheet). */
val LocalArenaPanelClose = compositionLocalOf<(() -> Unit)?> { null }

/** Opens the Sound Lab as a page of Options (Audio's Sound Lab button) instead of a sheet. */
val LocalArenaOpenSoundLab = compositionLocalOf<(() -> Unit)?> { null }

/** Opens Phase Stops as a page of Options (Gameplay's Phase Stops button). */
val LocalArenaOpenPhaseStops = compositionLocalOf<(() -> Unit)?> { null }

/** Where a menu panel stands: centred like Arena's Options, along the leading edge like its social panel, or along the trailing edge like its inbox. */
enum class ArenaPanelPlacement { CENTER, LEADING, TRAILING }

/**
 * A menu page as Arena's glass panel over the dimmed menu, below the top bar. A tap on the dimmed menu (or Back) closes it;
 * the page closes itself through [LocalArenaPanelClose]. `dismissable` false: the page must be answered (the first launch's
 * welcome). `fitsContent`: a centred panel only as tall as its page, up to the screen. Place it last in a full-screen Box.
 */
@Composable
fun ArenaPanel(visible: Boolean, onClose: () -> Unit, placement: ArenaPanelPlacement = ArenaPanelPlacement.CENTER, maxWidth: Dp = 680.dp,
               dismissable: Boolean = true, fitsContent: Boolean = false, content: @Composable () -> Unit) {
    val reduce = BoardMotionFlags.reduceMotion
    val widest = maxWidth
    val close: () -> Unit = { GameAudio.play(GameSound.UI_BACK); onClose() }
    BackHandler(visible) { if (dismissable) close() }
    val edge = placement != ArenaPanelPlacement.CENTER
    val trailing = placement == ArenaPanelPlacement.TRAILING
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(tween(if (reduce) 120 else 260)), exit = fadeOut(tween(if (reduce) 120 else 200))) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.62f))
                .clickable(remember { MutableInteractionSource() }, null) { if (dismissable) close() })
        }
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val screenWidth = maxWidth
            val landscape = maxWidth > maxHeight
            // Every panel stands below the top bar, which shows dimmed above it.
            Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)
                .padding(top = ArenaMenuStyle.barHeight + if (landscape && !edge) 4.dp else 0.dp)
                .then(if (edge) Modifier else Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom)))) {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val cap = maxHeight - if (landscape) 10.dp else 40.dp
                    val width = if (edge) (if (landscape) minOf(if (trailing) 400.dp else 360.dp, screenWidth * 0.45f) else maxWidth)
                        else minOf(maxWidth - 28.dp, widest)
                    val alignment = when (placement) {
                        ArenaPanelPlacement.CENTER -> Alignment.Center
                        ArenaPanelPlacement.LEADING -> Alignment.TopStart
                        ArenaPanelPlacement.TRAILING -> Alignment.TopEnd
                    }
                    AnimatedVisibility(visible, Modifier.align(alignment),
                        enter = if (reduce) fadeIn(tween(120)) else if (edge) slideInHorizontally(tween(320)) { if (trailing) it else -it } + fadeIn()
                            else scaleIn(tween(260), 0.95f) + fadeIn(tween(260)),
                        exit = if (reduce) fadeOut(tween(120)) else if (edge) slideOutHorizontally(tween(260)) { if (trailing) it else -it } + fadeOut()
                            else scaleOut(tween(200), 0.95f) + fadeOut(tween(200))) {
                        val radius = 20.dp
                        val shape = when (placement) {
                            ArenaPanelPlacement.CENTER -> RoundedCornerShape(radius)
                            ArenaPanelPlacement.TRAILING -> RoundedCornerShape(topStart = radius, bottomStart = radius)
                            ArenaPanelPlacement.LEADING -> RoundedCornerShape(topEnd = radius, bottomEnd = radius)
                        }
                        val sizing = when {
                            !edge && fitsContent -> Modifier.heightIn(max = cap)
                            !edge -> Modifier.height(cap)
                            !landscape -> Modifier.heightIn(max = maxHeight)
                            else -> Modifier.fillMaxHeight()
                        }
                        val fixedHeight = (!edge && !fitsContent) || (edge && landscape)
                        Box(Modifier.width(width).then(sizing)
                            .drawBehind {
                                blurredRoundRect(Color.Black.copy(alpha = 0.6f), 18.dp.toPx(), Rect(0f, 6.dp.toPx(), size.width, size.height + 6.dp.toPx()), radius.toPx())
                            }
                            // Taps on the glass stay on the panel.
                            .pointerInput(Unit) { detectTapGestures { } }) {
                            Box(Modifier.fillMaxWidth().then(if (fixedHeight) Modifier.fillMaxHeight() else Modifier)
                                .clip(shape)
                                .background(Brush.verticalGradient(listOf(ArenaGlass.top.copy(alpha = 0.98f), ArenaGlass.bottom.copy(alpha = 0.98f))))
                                .border(1.dp, ArenaGlass.hairline, shape)
                                .then(when (placement) {
                                    ArenaPanelPlacement.LEADING -> Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Start + WindowInsetsSides.Bottom))
                                    ArenaPanelPlacement.TRAILING -> Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.End + WindowInsetsSides.Bottom))
                                    ArenaPanelPlacement.CENTER -> Modifier
                                })) {
                                CompositionLocalProvider(LocalArenaPanelClose provides close, LocalArenaBoard provides true, LocalContentColor provides ArenaMenuStyle.text) {
                                    content()
                                }
                            }
                            // A blade on the right burns along its inner edge (outside the glass's clip, so its glow spills), as Arena's inbox and Play blade do.
                            if (trailing && landscape) Box(Modifier.matchParentSize()) {
                                ArenaSeam(vertical = true, Modifier.align(Alignment.CenterStart).fillMaxHeight())
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A panel's head: an optional back chevron, the title in large type, and the close button, over a gold hairline. */
@Composable
fun ArenaPanelHeader(title: String, modifier: Modifier = Modifier, back: (() -> Unit)? = null, closeIdentifier: String = "panel.close", close: (() -> Unit)? = null) {
    val panelClose = LocalArenaPanelClose.current
    Row(modifier.fillMaxWidth().padding(start = if (back == null) 18.dp else 6.dp, end = 8.dp, top = 6.dp)
        .drawBehind { drawRect(ArenaGlass.hairline, androidx.compose.ui.geometry.Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()), alpha = 0.45f) },
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        back?.let { BackChevron(it, 16.dp, 40.dp) }
        FitText(title, ArenaMenuStyle.font(22f, SfWeight.bold), Modifier.weight(1f).semantics { heading() }, color = ArenaMenuStyle.text, minimumScale = 0.7f)
        ArenaCloseButton({ (close ?: panelClose)?.invoke() }, identifier = closeIdentifier)
    }
}

@Composable
private fun BackChevron(action: () -> Unit, size: Dp, width: Dp) {
    BrandPressable({ GameAudio.play(GameSound.UI_BACK); action() }, Modifier.size(width, 44.dp).testTag("panel.back")
        .semantics { contentDescription = "Back"; role = androidx.compose.ui.semantics.Role.Button }) {
        SfImage("chevron.left", ArenaMenuStyle.text, size)
    }
}

// MARK: - Options

/** Options' pages: the column of pills, the links along the foot, and the pages opened from Audio and Gameplay. */
enum class ArenaOptionsPage(val raw: String, val title: String) {
    GAMEPLAY("gameplay", "Gameplay"), BOARD("board", "Board"), AUDIO("audio", "Audio"), DISPLAY("display", "Display & Artwork"),
    PERFORMANCE("performance", "Performance"), SUPPORT("support", "Support"), ABOUT("about", "About"), SOUND_LAB("soundLab", "Sound Lab"),
    PHASE_STOPS("phaseStops", "Phase Stops");

    /** Where the back chevron goes from this page. */
    val parent: ArenaOptionsPage? get() = when (this) { SOUND_LAB -> AUDIO; PHASE_STOPS -> GAMEPLAY; else -> null }

    companion object {
        val listed = listOf(GAMEPLAY, BOARD, AUDIO, DISPLAY, PERFORMANCE)
        val links = listOf(SUPPORT, ABOUT)
        fun of(raw: String?): ArenaOptionsPage? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Arena's Options (options-1): over the dimmed menu, a centred serif title, one centred column of compact pills and small
 * underlined links along the foot (Support, About). Each pill opens its page in the same panel with a back chevron; the pages
 * lay their settings flat on the glass, in columns when held sideways.
 */
@Composable
fun ArenaOptionsView(portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit, upstreamCommit: String? = null,
                     startPage: ArenaOptionsPage? = null) {
    var pageRaw by rememberSaveable { mutableStateOf(startPage?.raw) }
    val page = ArenaOptionsPage.of(pageRaw)
    val configuration = LocalConfiguration.current
    val wide = configuration.screenWidthDp > configuration.screenHeightDp
    val panelClose = LocalArenaPanelClose.current
    if (page == ArenaOptionsPage.SOUND_LAB) { SoundLabView(back = { pageRaw = ArenaOptionsPage.AUDIO.raw }); return }
    Column(Modifier.fillMaxWidth()) {
        // Arena's head: a back chevron on the left (pages only), the title centred in serif, the close button on the right.
        Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp).padding(top = 6.dp, bottom = 2.dp)
            .drawBehind { drawRect(ArenaGlass.hairline, androidx.compose.ui.geometry.Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()), alpha = 0.45f) }) {
            FitText(page?.title ?: "Options", ArenaMenuStyle.font(26f, SfWeight.bold), Modifier.align(Alignment.Center).padding(horizontal = 56.dp).semantics { heading() },
                color = ArenaMenuStyle.text, minimumScale = 0.7f, textAlign = TextAlign.Center)
            if (page != null) Box(Modifier.align(Alignment.CenterStart)) { BackChevron({ pageRaw = page.parent?.raw }, 17.dp, 44.dp) }
            ArenaCloseButton({ panelClose?.invoke() }, Modifier.align(Alignment.CenterEnd), identifier = "settings.close")
        }
        AnimatedContent(page, transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(180)) }, label = "optionsPage") { shown ->
            if (shown == null) OptionsRoot(wide) { pageRaw = it.raw }
            else Column(Modifier.fillMaxWidth().arenaScrollFade().verticalScroll(rememberScrollState()).testTag("settings.page.${shown.raw}"),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = if (wide) 820.dp else 560.dp).fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    // The pages lay their settings flat on the glass, as Arena's do.
                    CompositionLocalProvider(LocalArenaOptionsFlat provides true, LocalArenaOpenSoundLab provides { pageRaw = ArenaOptionsPage.SOUND_LAB.raw },
                        LocalArenaOpenPhaseStops provides { pageRaw = ArenaOptionsPage.PHASE_STOPS.raw }) {
                        OptionsPage(shown, wide, portraitModeEnabled, setPortraitModeEnabled, upstreamCommit)
                    }
                }
            }
        }
    }
}

/** The column of pills, then the links along the foot. Fits a phone held sideways without scrolling. */
@Composable
private fun OptionsRoot(wide: Boolean, open: (ArenaOptionsPage) -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.padding(top = if (wide) 14.dp else 28.dp, bottom = if (wide) 14.dp else 36.dp), verticalArrangement = Arrangement.spacedBy(if (wide) 6.dp else 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            ArenaOptionsPage.listed.forEach { item -> ArenaOptionsPill(item.title, "settings.open.${item.raw}") { open(item) } }
        }
        Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            ArenaOptionsPage.links.forEach { item -> ArenaLink(item.title, { open(item) }, identifier = "settings.open.${item.raw}") }
        }
    }
}

/** Arena's Options pill: a compact dark capsule edged in a pale line, its word centred; brighter while pressed. */
@Composable
private fun ArenaOptionsPill(title: String, identifier: String, action: () -> Unit) {
    BrandPressable({ GameAudio.play(GameSound.UI_OPEN); action() }, Modifier.height(44.dp).testTag(identifier)
        .semantics { contentDescription = title; role = androidx.compose.ui.semantics.Role.Button }) {
        Box(Modifier.size(230.dp, 36.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape).border(1.2.dp, Color.White.copy(alpha = 0.45f), CircleShape),
            contentAlignment = Alignment.Center) {
            FitText(title, ArenaMenuStyle.font(15f, SfWeight.semibold), color = ArenaMenuStyle.text, minimumScale = 0.8f)
        }
    }
}

@Composable
private fun ColumnScope.OptionsPage(page: ArenaOptionsPage, wide: Boolean, portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit,
                                    upstreamCommit: String?) {
    when (page) {
        // Two columns sideways, so every label stays on one line.
        ArenaOptionsPage.GAMEPLAY -> GameplayOptions(if (wide) 2 else 1)
        ArenaOptionsPage.PHASE_STOPS -> Box(Modifier.widthIn(max = 520.dp).fillMaxWidth().align(Alignment.CenterHorizontally)) { PhaseStopsGrid() }
        // The board's effects; the table picker and Card Frames wait for Android's Arena board.
        ArenaOptionsPage.BOARD -> BoardEffectsPicker(includesAudio = false)
        ArenaOptionsPage.AUDIO -> Box(Modifier.tavernSettingsPanel()) { GameAudioSettings() }
        ArenaOptionsPage.SOUND_LAB -> {}
        ArenaOptionsPage.DISPLAY -> {
            PortraitModeToggle(portraitModeEnabled, setPortraitModeEnabled)
            ArtworkPreferenceOptions()
        }
        ArenaOptionsPage.PERFORMANCE -> GamePerformancePanel()
        ArenaOptionsPage.SUPPORT -> SupportSettingsPanel()
        ArenaOptionsPage.ABOUT -> Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AboutRow("MagicMobile", "${BuildConfig.VERSION_NAME} (${BuildConfig.RELEASE_BUILD})")
            upstreamCommit?.let { AboutRow("XMage revision", it.take(12)) }
            Text(SupportProject.NOTE, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))
        }
    }
}

@Composable
private fun AboutRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.semibold))
        Text(value, color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
    }
}

/** Gameplay's settings as Arena's checkboxes (MainMenuViews.swift GameplayOptions), then Phase Stops. */
@Composable
private fun GameplayOptions(columns: Int) {
    var smartPass by AppPreferences.boolean(OnDeviceSmartPass.ENABLED_KEY, true)
    var stopForOwn by AppPreferences.boolean(OnDeviceSmartPass.STOP_FOR_OWN_SPELLS_KEY, false)
    var passAfterCast by AppPreferences.boolean(AutoPassAfterCast.KEY, true)
    var followTurns by AppPreferences.boolean(BoardFocusTracker.followTurnsKey, true)
    val openStops = LocalArenaOpenPhaseStops.current
    val boxes: List<@Composable (Modifier) -> Unit> = listOf(
        { m -> ArenaCheckbox("Smart Auto-Pass", smartPass, { smartPass = it }, m, "Passes for you when you have nothing to play, and skips steps you don’t stop at.",
            "settings.smartAutoPass") },
        { m -> ArenaCheckbox("Stop for My Own Spells", stopForOwn, { stopForOwn = it }, m, "Off: your own spells and triggers resolve without a stop.",
            "settings.stopForOwnSpells", enabled = smartPass) },
        { m -> ArenaCheckbox("Pass After Casting", passAfterCast, { passAfterCast = it }, m, "Your spell resolves without another tap. Opponents can still respond.",
            "settings.autoPassAfterCast") },
        { m -> ArenaCheckbox("Follow Turns", followTurns, { followTurns = it }, m, "Show whose turn it is at the top. A tap on an opponent holds until the next turn.",
            "settings.followTurns") },
    )
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            boxes.chunked(maxOf(1, columns)).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    row.forEach { it(Modifier.weight(1f)) }
                    repeat(maxOf(1, columns) - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        ArenaPillButton("Phase Stops", { openStops?.invoke() }, enabled = smartPass, identifier = "settings.phaseStops")
    }
}

/** Display & Artwork's consent for live Scryfall images (NativeArtworkPreferenceView), flat on the glass. */
@Composable
private fun ArtworkPreferenceOptions() {
    val (remote, setRemote) = rememberArtworkConsent()
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ArenaCheckbox("Scryfall live images", remote, setRemote, identifier = "nativeArtwork.downloads")
        Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.", color = ArenaMenuStyle.dim,
            style = ArenaMenuStyle.font(12f, SfWeight.medium))
        Text("Scryfall receives card names—including your hand—and your IP address.", color = ArenaMenuStyle.dim,
            style = ArenaMenuStyle.font(12f, SfWeight.medium))
    }
}

// MARK: - Prompt

/** A question as Arena asks one in its menus: the title, a few words, a dark pill to decline and the orange one to go ahead, in a small glass panel. */
@Composable
fun ArenaPromptPanel(title: String, message: String, primary: String, secondary: String, identifier: String = "prompt", action: () -> Unit) {
    val panelClose = LocalArenaPanelClose.current
    Column(Modifier.fillMaxWidth()) {
        ArenaPanelHeader(title, closeIdentifier = "$identifier.close")
        Text(message, Modifier.padding(horizontal = 18.dp).padding(top = 14.dp), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(14f, SfWeight.medium))
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            ArenaPillButton(secondary, { panelClose?.invoke() }, identifier = "$identifier.secondary")
            Spacer(Modifier.weight(1f))
            ArenaPlayButton(primary, action, Modifier.size(210.dp, 44.dp), fontSize = 17f, identifier = "$identifier.primary")
        }
    }
}
