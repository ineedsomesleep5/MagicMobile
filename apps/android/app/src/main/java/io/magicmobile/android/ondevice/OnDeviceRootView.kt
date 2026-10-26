package io.magicmobile.android.ondevice

import androidx.compose.material3.LocalContentColor
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.tavernPanelChrome
import io.magicmobile.android.ui.engraved
import io.magicmobile.android.ui.tavernBrassFrame
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernTextField
import io.magicmobile.android.ui.TavernToggle
import io.magicmobile.android.ui.TavernStepper
import io.magicmobile.android.ui.TavernPickerSection
import io.magicmobile.android.ui.TavernPicker
import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewModelScope
import io.magicmobile.android.Artwork
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.BoardEffectsPicker
import io.magicmobile.android.board.FollowTurnsToggle
import io.magicmobile.android.board.BoardSelection
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.EmoteCenter
import io.magicmobile.android.board.GameConcedeHandler
import io.magicmobile.android.board.LocalEmoteCenter
import io.magicmobile.android.board.LocalGameConcede
import io.magicmobile.android.board.LocalGameRematchTitle
import io.magicmobile.android.board.LocalInspectorBattlefield
import io.magicmobile.android.board.LocalNativeTurnControl
import io.magicmobile.android.board.LocalStartingRollVisible
import io.magicmobile.android.board.TableChatPanel
import io.magicmobile.android.social.FriendsSheet
import io.magicmobile.android.social.LocalPlayerAccount
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.board.NativeGameView
import io.magicmobile.android.board.NativeTurnControl
import io.magicmobile.android.board.PortraitModePreference
import io.magicmobile.android.board.PortraitModeToggle
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckTextImport
import io.magicmobile.android.game.CardChoiceCommandFailure
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.GameCommand
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.GameResumeSettings
import io.magicmobile.android.game.GuidedGameCoach
import io.magicmobile.android.game.GuidedGameLaunch
import io.magicmobile.android.game.GuidedGameSetup
import io.magicmobile.android.game.GuidedGameTip
import io.magicmobile.android.game.HowToPlayLaunch
import io.magicmobile.android.game.OfflineArtLaunch
import io.magicmobile.android.game.TableJoinLink
import io.magicmobile.android.game.HowToPlayText
import io.magicmobile.android.session.OnDeviceSession
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.BrandButton
import io.magicmobile.android.ui.BrandButtonKind
import io.magicmobile.android.ui.BrandButtonText
import io.magicmobile.android.ui.BrandDivider
import io.magicmobile.android.ui.BrandIconButton
import io.magicmobile.android.ui.BrandMark
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.BrandTitle
import io.magicmobile.android.ui.CommanderDeckPortrait
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameMusic
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.HeroCommanderCard
import io.magicmobile.android.ui.GuidedGameCoachCard
import io.magicmobile.android.ui.GuidedGameWelcomeView
import io.magicmobile.android.ui.HowToPlayView
import io.magicmobile.android.ui.IosListRow
import io.magicmobile.android.ui.IosListSection
import io.magicmobile.android.ui.IosMenuPicker
import io.magicmobile.android.ui.IosSegmented
import io.magicmobile.android.ui.IosSheetHeader
import io.magicmobile.android.ui.IosStepper
import io.magicmobile.android.ui.IosTextButton
import io.magicmobile.android.ui.IosTextField
import io.magicmobile.android.ui.IosToggle
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.LocalBrandAmbientMotion
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.MagicPanelMaterial
import io.magicmobile.android.ui.MagicPanelProminence
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.VersusIntroOverlay
import io.magicmobile.android.ui.VersusMedallion
import io.magicmobile.android.ui.VersusSeat
import io.magicmobile.android.ui.brandPanel
import io.magicmobile.android.ui.magicPanel
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Holds the session and setup across configuration changes, like the iOS root's @StateObjects. */
class OnDeviceViewModel(application: Application) : AndroidViewModel(application) {
    val session = OnDeviceSession(viewModelScope)
    val setup = OnDeviceSetupModel(application, session, viewModelScope)
    val emotes = EmoteCenter(viewModelScope)
    /** The instant profile: player name, friends and presence (PlayerAccount.swift). */
    val account = PlayerAccount(application, viewModelScope)
    /** A table invite link waiting for the root view to open it. */
    var joinLinkCode by mutableStateOf<String?>(null)
    /** Your decks on every phone and browser signed in to this profile (docs/DECK_SYNC.md). */
    private val deckSync by lazy {
        io.magicmobile.android.studio.DeckSync(io.magicmobile.android.studio.DeckLibrarySyncAdapter(setup.library), setup.deckSyncState,
            account.deckSyncAPI) { io.magicmobile.android.social.SupabaseLite.code(it) }
    }

    /** One deck sync in the background; errors stay quiet and the next sync tries again. Concurrent calls share one run. */
    fun syncDecks() {
        if (account.phase != PlayerAccount.Phase.READY) return
        viewModelScope.launch {
            val profile = account.profileID() ?: return@launch
            try { deckSync.sync(profile) } catch (error: kotlinx.coroutines.CancellationException) { throw error } catch (error: Exception) { /* offline or refused: the next sync tries again */ }
        }
    }

    /** A deck changed here or a tombstone waits to go up. */
    fun deckSyncPending(): Boolean = runCatching { deckSync.hasPending() }.getOrDefault(false)

    override fun onCleared() {
        // The engine must stop its workers even when the activity is finished for good.
        MainScope().launch { runCatching { setup.close() } }
        super.onCleared()
    }
}

/**
 * On Android, iOS's orientation lock (GameOrientationMode.supportedOrientations): Auto-Rotate
 * allows portrait and landscape, off keeps landscape. The board follows with its landscape layout.
 */
object OrientationController {
    fun apply(activity: Activity?, portraitEnabled: Boolean, @Suppress("UNUSED_PARAMETER") inGame: Boolean) {
        activity ?: return
        activity.requestedOrientation = if (portraitEnabled) ActivityInfo.SCREEN_ORIENTATION_FULL_USER else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    }
}

/** Port of OnDeviceRootView.swift: setup and lifecycle around the on-device board. */
@Composable
fun OnDeviceRoot(vm: OnDeviceViewModel) {
    val session = vm.session
    val setup = vm.setup
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()
    val reduceMotion = LaunchEnvironment.reduceMotion
    var playerDisplayName by OnDeviceSetupModel.savedPlayerName
    var portraitModeEnabled by AppPreferences.boolean(PortraitModePreference.key, true)
    var selectedDeckID by AppPreferences.string(OnDeviceSetupPreferences.deckKey, OnDeviceSetupPreferences.defaultDeckID)
    var aiPreconID by AppPreferences.string(OnDeviceSetupPreferences.aiDeckKey, OnDeviceSetupPreferences.defaultAIDeckID)
    var aiPrecon2ID by AppPreferences.string(OnDeviceSetupPreferences.aiDeck2Key, "")
    var aiPrecon3ID by AppPreferences.string(OnDeviceSetupPreferences.aiDeck3Key, "")
    var opponentCount by AppPreferences.int(OnDeviceSetupPreferences.aiCountKey, 1)
    var aiSkill by AppPreferences.int(OnDeviceSetupPreferences.aiSkillKey, 2)
    var aiStartingPlayerMode by AppPreferences.string(OnDeviceSetupPreferences.startingPlayerModeKey, "choose")
    var playerCount by AppPreferences.int(OnDeviceSetupPreferences.humanCountKey, 2)
    var playWithFriends by AppPreferences.boolean(OnDeviceSetupPreferences.friendsKey, false)
    var showSetup by remember { mutableStateOf(false) }
    var showAppearance by remember { mutableStateOf(false) }
    var showUpdates by remember { mutableStateOf(false) }
    var showDownloads by remember { mutableStateOf(false) }
    var showHowToPlay by rememberSaveable { mutableStateOf(false) }
    var howToPlayOpensTable by rememberSaveable { mutableStateOf(false) }
    var howToPlaySeenVersion by AppPreferences.int(HowToPlayLaunch.SEEN_VERSION_KEY, 0)
    var offlineArtPromptSeen by AppPreferences.boolean(OfflineArtLaunch.SEEN_KEY, false)
    var showOfflineArtPrompt by remember { mutableStateOf(false) }
    // The guided first game (GuidedGame.kt): the first launch's welcome, and the coach on the table.
    var showGuidedWelcome by remember { mutableStateOf(false) }
    var guidedWelcomeSeen by AppPreferences.boolean(GuidedGameLaunch.WELCOME_SEEN_KEY, false)
    var guidedActive by AppPreferences.boolean(GuidedGameLaunch.ACTIVE_KEY, false)
    var guidedShownTips by AppPreferences.string(GuidedGameLaunch.SHOWN_TIPS_KEY, "")
    var guidedGame by rememberSaveable { mutableStateOf(false) }
    var guidedTipID by rememberSaveable { mutableStateOf<String?>(null) }
    var showFriends by remember { mutableStateOf(false) }
    // A friend's message during a game (the banner) and the Messages sheet it opens (a name, or "" for the list).
    var messageBanner by remember { mutableStateOf<Pair<String, String>?>(null) }
    var messagesHub by remember { mutableStateOf<String?>(null) }
    var chatProfile by remember { mutableStateOf<String?>(null) }
    // The profile name is the name at every table; friends see the table this phone hosts while it has open seats.
    LaunchedEffect(vm.account.username) { vm.account.username?.let { playerDisplayName = it } }
    var showDecks by remember { mutableStateOf(false) }
    // Deck Studio's editor or importer is open over the whole screen (the Decks tab's fullScreenCover).
    var decksCovered by remember { mutableStateOf(false) }
    // The Play panel over the menu (Arena's blade), its way to play and its tab (OnDeviceRootView.swift's Arena menus).
    var playPanel by rememberSaveable { mutableStateOf(false) }
    var playModeRaw by AppPreferences.string(io.magicmobile.android.game.ArenaPlayMode.STORAGE_KEY, io.magicmobile.android.game.ArenaPlayMode.QUICK.raw)
    var playTabRaw by rememberSaveable { mutableStateOf(io.magicmobile.android.game.ArenaPlayTab.FIND.raw) }
    val playTab = io.magicmobile.android.game.ArenaPlayTab.entries.firstOrNull { it.raw == playTabRaw } ?: io.magicmobile.android.game.ArenaPlayTab.FIND
    var optionsStartPage by remember { mutableStateOf<io.magicmobile.android.menus.ArenaOptionsPage?>(null) }
    // Decks is the Arena menus' Decks tab (Caleb, 2026-10-22; it was a spell book that opened on the table, film and all).
    fun openDecks() { if (!showDecks) { playPanel = false; showDecks = true } }
    fun openPlayPanel(mode: io.magicmobile.android.game.ArenaPlayMode? = null) {
        if (mode != null) { playModeRaw = mode.raw; playTabRaw = io.magicmobile.android.game.ArenaPlayTab.FIND.raw }
        GameAudio.play(GameSound.UI_OPEN)
        playPanel = true
    }
    var studioOpen by remember { mutableStateOf<io.magicmobile.android.studio.DeckStudioOpen?>(null) }
    var confirmLeave by remember { mutableStateOf(false) }
    // The freeze log (docs/FREEZE_LOG.md): the game menu's Report a freeze, and the launch question once answered.
    var confirmFreezeReport by remember { mutableStateOf(false) }
    var freezeOfferClosed by remember { mutableStateOf<String?>(null) }
    var bannerError by remember { mutableStateOf<String?>(null) }
    /** The session error the player closed; a different error shows again. */
    var dismissedSessionError by remember { mutableStateOf<String?>(null) }
    var didDismissStartingRoll by remember { mutableStateOf(false) }
    var attemptedStartingPromptID by remember { mutableStateOf<String?>(null) }
    var startingChoiceFailedPromptID by remember { mutableStateOf<String?>(null) }
    var aiStartingRoll by remember { mutableStateOf<OnDeviceStartingRoll?>(null) }
    var aiRevealedRollCount by remember { mutableIntStateOf(0) }
    var aiRollSeatNames by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var versusIntro by remember { mutableStateOf<Pair<VersusSeat, List<VersusSeat>>?>(null) }
    val selection = remember { BoardSelection() }
    // Quick Match, Ranked and the profile (ranked/).
    val record = remember { io.magicmobile.android.ranked.PlayerRecordStore.shared(context) }
    var lobby by rememberSaveable { mutableStateOf<String?>(null) }
    // Development fixtures (SocialFixtures): open the profile or the friends sheet at launch.
    LaunchedEffect(Unit) {
        val screen = io.magicmobile.android.ranked.SocialFixtures.openScreen
        when (screen?.substringBefore(":")) {
            "profile" -> lobby = "profile"
            "rankedHall" -> lobby = "rankedHall"
            "leaderboard" -> lobby = "leaderboard"
            "play" -> openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.QUICK)
            "play-ranked", "queue" -> openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.RANKED)
            "play-custom" -> openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.CUSTOM)
            "play-friends" -> { playTabRaw = io.magicmobile.android.game.ArenaPlayTab.FRIENDS.raw; playPanel = true }
            "play-recent" -> { playTabRaw = io.magicmobile.android.game.ArenaPlayTab.RECENT.raw; playPanel = true }
            "decks", "deck" -> openDecks()
            "custom" -> showSetup = true
            "settings" -> { optionsStartPage = io.magicmobile.android.menus.ArenaOptionsPage.of(screen.substringAfter(":", "")); showAppearance = true }
            "updates" -> showUpdates = true
            "downloads" -> showDownloads = true
            "learn" -> showHowToPlay = true
            "learn-table" -> { howToPlayOpensTable = true; showHowToPlay = true }
            "friends", "public", "search", "messages", "conversation" -> showFriends = true
        }
    }
    var quickBracket by AppPreferences.int("magicmobile.quick.opponentBracket", 0)
    var quickDeckID by AppPreferences.string("magicmobile.quick.opponentDeck", "")
    var quickSkill by AppPreferences.int("magicmobile.quick.aiSkill", 3)
    /** Easy, Medium or Hard pick the AI's deck by Power and set its skill; "advanced" keeps the bracket, deck and skill controls. */
    var quickLevel by AppPreferences.string("magicmobile.quick.level", "medium")
    var activeMatch by remember { mutableStateOf<ActiveMatch?>(null) }
    // Who goes first in this AI game: Ranked always rolls, other games follow the player's choice.
    fun startingPlayerMode(): String = activeMatch?.mode?.startingPlayerMode(aiStartingPlayerMode) ?: aiStartingPlayerMode
    var rankChange by remember { mutableStateOf<io.magicmobile.android.game.RankChange?>(null) }
    /** Why the last ranked win left the ladder alone, once the server answers. */
    var rankNote by remember { mutableStateOf<String?>(null) }
    var ceremony by remember { mutableStateOf<io.magicmobile.android.game.RankChange?>(null) }
    var showBracketSheet by remember { mutableStateOf(false) }
    var bracketRevision by remember { mutableIntStateOf(0) }
    var matchPhase by remember { mutableStateOf<io.magicmobile.android.game.RankedMatchmaker.Phase>(io.magicmobile.android.game.RankedMatchmaker.Phase.Idle) }
    val matchmaker = remember { io.magicmobile.android.game.RankedMatchmaker(null).also { m -> m.onPhase = { matchPhase = it } } }
    var rankedConnectJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    // Friend challenges (FriendChallenges.kt): what the coordinator shows, mirrored into Compose state.
    var challengeWaiting by remember { mutableStateOf(false) }
    var challengeIncoming by remember { mutableStateOf<List<io.magicmobile.android.game.FriendChallenge>>(emptyList()) }
    val challenges = remember {
        io.magicmobile.android.game.FriendChallengeCoordinator(null, codeOf = { io.magicmobile.android.social.SupabaseLite.code(it) }).also { c ->
            c.onChange = { challengeWaiting = c.isWaiting; challengeIncoming = c.incoming }
        }
    }
    var challengeTarget by remember { mutableStateOf<Pair<String, io.magicmobile.android.game.PlayMode>?>(null) }
    var appForeground by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        record.publish = { rank, title, commander -> scope.launch { vm.account.publishRank(rank, title, commander) } }
        // Finished games go to the profile server too: now, and again whenever the app is open and online (GameUploader).
        val uploader = io.magicmobile.android.game.GameUploader(java.io.File(context.filesDir, "Profile/uploaded-games.json"))
        val upload: suspend () -> Unit = { uploader.flush(record.file.matches) { vm.account.recordGame(it) } }
        // A ranked game goes up after its result counts on the server, which records its rank points then.
        record.didRecord = { match -> if (match.mode != io.magicmobile.android.game.PlayMode.RANKED) scope.launch { upload() } }
        vm.account.afterRefresh = { vm.account.syncRank(record); upload() }
        // Debug: MAGICMOBILE_UI_TEST_CEREMONY=tierUp|tierDown|divisionUp|divisionDown plays a rank moment (as on iOS).
        val P = io.magicmobile.android.game.RankPosition
        val win = io.magicmobile.android.game.RankOutcome.WIN; val loss = io.magicmobile.android.game.RankOutcome.LOSS
        when (LaunchEnvironment["MAGICMOBILE_UI_TEST_CEREMONY"]) {
            "tierUp" -> io.magicmobile.android.game.RankChange(win, P.make(io.magicmobile.android.game.RankTier.SILVER, 1, 3), P.make(io.magicmobile.android.game.RankTier.GOLD, 4, 0), emptyList())
            "tierDown" -> io.magicmobile.android.game.RankChange(loss, P.make(io.magicmobile.android.game.RankTier.GOLD, 4, 0), P.make(io.magicmobile.android.game.RankTier.SILVER, 1, 3), emptyList())
            "divisionUp" -> io.magicmobile.android.game.RankChange(win, P.make(io.magicmobile.android.game.RankTier.DIAMOND, 3, 3), P.make(io.magicmobile.android.game.RankTier.DIAMOND, 2, 0), emptyList())
            "divisionDown" -> io.magicmobile.android.game.RankChange(loss, P.make(io.magicmobile.android.game.RankTier.PLATINUM, 2, 0), P.make(io.magicmobile.android.game.RankTier.PLATINUM, 3, 3), emptyList())
            else -> null
        }?.let { ceremony = it }
    }

    val activeGame = session.matchID != null
    val precons = setup.precons
    val aiIDs = listOf(aiPreconID, aiPrecon2ID, aiPrecon3ID)
    val aiPool = setup.aiPool
    val aiPrecons = aiIDs.take(opponentCount.coerceIn(1, 3)).mapNotNull { id -> aiPool.firstOrNull { it.id == id } }
    val bracketPrefs = AppPreferences.string(io.magicmobile.android.game.DeckBracketPreference.KEY, "{}")
    fun declaredBracket(deckID: String): io.magicmobile.android.game.CommanderBracket? = runCatching {
        kotlinx.serialization.json.Json.parseToJsonElement(bracketPrefs.value).let { it as kotlinx.serialization.json.JsonObject }[deckID]
            ?.let { (it as kotlinx.serialization.json.JsonPrimitive).content.toIntOrNull() }?.let(io.magicmobile.android.game.CommanderBracket::of)
    }.getOrNull()
    fun setDeclaredBracket(deckID: String, bracket: io.magicmobile.android.game.CommanderBracket?) {
        val current = runCatching { kotlinx.serialization.json.Json.parseToJsonElement(bracketPrefs.value) as kotlinx.serialization.json.JsonObject }.getOrNull() ?: kotlinx.serialization.json.JsonObject(emptyMap())
        val next = current.toMutableMap().apply { if (bracket == null) remove(deckID) else put(deckID, kotlinx.serialization.json.JsonPrimitive(bracket.level)) }
        bracketPrefs.value = kotlinx.serialization.json.JsonObject(next).toString(); bracketRevision++
    }
    val selectedDeck: Deck? = setup.deck(selectedDeckID)
    val selectedBracketReport = remember(selectedDeck, setup.bracketRules) { selectedDeck?.let { setup.bracketRules.evaluate(it) } }
    val selectedDeckBracket: io.magicmobile.android.game.CommanderBracket? = run {
        bracketRevision
        setup.bracketDecks.firstOrNull { it.playerDeckID == selectedDeckID }?.bracket
            ?: if (selectedDeckID.startsWith("precon:")) io.magicmobile.android.game.CommanderBracket.CORE
            else selectedBracketReport?.let { io.magicmobile.android.game.DeckBracketPreference.effective(it.minimum, declaredBracket(selectedDeckID)) }
    }
    val selectedDeckColors: List<String> = setup.bracketDecks.firstOrNull { it.playerDeckID == selectedDeckID }?.colors?.map { it.toString() }
        ?: selectedDeck?.let { deck -> io.magicmobile.android.game.ArenaDeckColors.colors(deck.entries.filter { it.section == "commanders" }.map { it.name }) { setup.catalogue?.find(it)?.identity } }
        ?: emptyList()
    val aiDeckPickerSections = io.magicmobile.android.game.CommanderBracket.entries.mapNotNull { bracket ->
        aiPool.filter { it.bracket == bracket }.takeIf { it.isNotEmpty() }?.let { decks -> TavernPickerSection(bracket.title, decks.map { it.name to it.id }) }
    }
    val validName = runCatching { OnDeviceSetupModel.playerName(playerDisplayName) }.isSuccess
    val mayStart = validName && selectedDeck != null && (playWithFriends || aiPrecons.size == opponentCount) &&
        setup.identity != null && !setup.isBusy && !setup.needsLeave

    fun restoreSetupPreferences() {
        val deckIDs = setup.deckIDs
        if (deckIDs.isEmpty()) return
        selectedDeckID = OnDeviceSetupPreferences.normalizedDeckID(selectedDeckID, deckIDs)
        val available = setup.aiPool.map { it.id }
        val ids = OnDeviceSetupPreferences.normalizedAIDeckIDs(listOf(aiPreconID, aiPrecon2ID, aiPrecon3ID), available)
        aiPreconID = ids[0]; aiPrecon2ID = ids[1]; aiPrecon3ID = ids[2]
        opponentCount = opponentCount.coerceIn(1, 3); playerCount = playerCount.coerceIn(2, 4); aiSkill = aiSkill.coerceIn(1, 10)
    }

    fun makeVersusIntro(): Pair<VersusSeat, List<VersusSeat>> {
        val name = playerDisplayName.trim()
        val tier = record.file.rank.position.tier
        val you = VersusSeat("you", name.ifEmpty { "You" }, selectedDeck?.commanderName, tier)
        // A table knows everyone's commander before its first snapshot shows the command zones.
        val tableSeats = (setup.multiplayer as? RelayTable)?.tableSeats.orEmpty()
        if (setup.usingMultiplayer && tableSeats.any { it.isLocal } && tableSeats.any { !it.isLocal }) {
            val local = tableSeats.first { it.isLocal }
            return VersusSeat("you", local.name, local.commanders.firstOrNull() ?: you.commander, tier) to
                tableSeats.filter { !it.isLocal }.take(3).map { VersusSeat(it.id, it.name, it.commanders.firstOrNull()) }
        }
        session.snapshot?.let { snapshot ->
            val others = snapshot.players.filter { !snapshot.isViewer(it.playerId) }.take(3).map {
                VersusSeat(it.playerId, it.displayName ?: "Opponent", it.zones.command.firstOrNull()?.card?.name)
            }
            if (others.isNotEmpty()) return you to others
        }
        activeMatch?.takeIf { it.opponents.isNotEmpty() }?.let { match ->
            return you to match.opponents.mapIndexed { index, foe -> VersusSeat("foe-$index", foe.name, foe.commander) }
        }
        if (playWithFriends) return you to listOf(VersusSeat("friends", "Challengers", null))
        return you to aiPrecons.take(maxOf(1, opponentCount)).mapIndexed { index, deck -> VersusSeat("ai-$index", deck.name, deck.commander) }
    }

    // MARK: Quick Match and Ranked (OnDeviceRootView.swift)
    val mayStartSolo = validName && selectedDeck != null && selectedDeckBracket != null && setup.identity != null &&
        !setup.isBusy && !setup.needsLeave && matchPhase == io.magicmobile.android.game.RankedMatchmaker.Phase.Idle

    fun startSolo(mode: io.magicmobile.android.game.PlayMode, deck: Deck, deckBracket: io.magicmobile.android.game.CommanderBracket,
                  opponent: io.magicmobile.android.game.AIDeck, skill: Int) {
        try { playerDisplayName = OnDeviceSetupModel.playerName(playerDisplayName) }
        catch (error: EngineError) { setup.errorMessage = error.message; return }
        activeMatch = ActiveMatch(mode, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, deckBracket.level,
            listOf(io.magicmobile.android.game.MatchOpponent(opponent.name, opponent.commander, true)), opponent.bracket.level, skill, opponent.id)
        rankChange = null; rankNote = null
        if (mode == io.magicmobile.android.game.PlayMode.RANKED) record.beginRankedAIGame(null)
        val settings = GameResumeSettings(selectedDeckID, listOf(opponent.id), skill, mode.startingPlayerMode(aiStartingPlayerMode), mode.raw, deckBracket.level)
        scope.launch {
            // The server's ticket for a ranked game, so its result counts there too; its seed deals this game.
            var seed: Long? = null
            if (mode == io.magicmobile.android.game.PlayMode.RANKED) {
                val ticket = vm.account.startRankedAIGame(deckBracket.level)
                record.beginRankedAIGame(ticket?.id, seeded = ticket != null)
                seed = ticket?.seed
            }
            setup.startAI(playerDisplayName, deck, listOf(opponent.deck), skill, settings, deckID = selectedDeckID, seed = seed)
            if (session.matchID == null) activeMatch = null
        }
    }

    // MARK: Guided first game (OnDeviceRootView.swift)

    fun endGuidedTips() { guidedTipID = null; guidedGame = false; guidedActive = false }

    /** Token Triumph against Grave Danger at skill 1, casual, with the coach on; the player's own deck and settings stay as they are. */
    fun startGuidedGame() {
        val deck = setup.deck(GuidedGameSetup.PLAYER_DECK_ID) ?: return
        val opponent = aiPool.firstOrNull { it.id == GuidedGameSetup.OPPONENT_DECK_ID } ?: return
        val colors = aiPool.firstOrNull { it.id == GuidedGameSetup.PLAYER_PRECON_ID }?.colors?.map { it.toString() } ?: emptyList()
        val name = runCatching { OnDeviceSetupModel.playerName(playerDisplayName) }.getOrNull() ?: "You"
        guidedShownTips = ""; guidedActive = true; guidedWelcomeSeen = true
        howToPlaySeenVersion = HowToPlayLaunch.seenVersionAfterClosing(howToPlaySeenVersion)
        guidedGame = true; guidedTipID = null
        lobby = null; showSetup = false
        val core = io.magicmobile.android.game.CommanderBracket.CORE
        activeMatch = ActiveMatch(io.magicmobile.android.game.PlayMode.CASUAL, GuidedGameSetup.PLAYER_DECK_ID, deck.name, deck.commanderName, colors,
            core.level, listOf(io.magicmobile.android.game.MatchOpponent(opponent.name, opponent.commander, true)), opponent.bracket.level,
            GuidedGameSetup.AI_SKILL, opponent.id)
        rankChange = null; rankNote = null
        val settings = GameResumeSettings(GuidedGameSetup.PLAYER_DECK_ID, listOf(opponent.id), GuidedGameSetup.AI_SKILL, aiStartingPlayerMode,
            io.magicmobile.android.game.PlayMode.CASUAL.raw, core.level)
        scope.launch {
            setup.startAI(name, deck, listOf(opponent.deck), GuidedGameSetup.AI_SKILL, settings, deckID = GuidedGameSetup.PLAYER_DECK_ID)
            if (session.matchID == null) { activeMatch = null; endGuidedTips() }
        }
    }

    fun answerGuidedWelcome() {
        guidedWelcomeSeen = true
        howToPlaySeenVersion = HowToPlayLaunch.seenVersionAfterClosing(howToPlaySeenVersion)
        showGuidedWelcome = false
    }

    fun startQuickMatch() {
        val deck = selectedDeck ?: return
        val bracket = selectedDeckBracket ?: return
        val level = setup.deckPower?.quickMatch?.get(quickLevel)
        if (level != null) {
            io.magicmobile.android.game.AIDeckPool.pickByPower(level.power, null, deck.commanderName, record.file.recentAIDecks, aiPool,
                setup.deckPower?.closest ?: 3)?.let { return startSolo(io.magicmobile.android.game.PlayMode.QUICK, deck, bracket, it, level.skill) }
        }
        val opponentBracket = if (quickBracket == 0) minOf(4, bracket.level) else quickBracket
        val opponent = quickDeckID.takeIf { it.isNotEmpty() }?.let { id -> aiPool.firstOrNull { it.id == id } }
            // "Match my deck" at Core or below meets a precon: the Core AI decks are tuned tribal lists.
            ?: io.magicmobile.android.game.AIDeckPool.pick(opponentBracket, deck.commanderName, record.file.recentAIDecks, aiPool,
                preconsOnly = quickBracket == 0 && opponentBracket <= 2) ?: return
        startSolo(io.magicmobile.android.game.PlayMode.QUICK, deck, bracket, opponent, quickSkill.coerceIn(1, 10))
    }

    fun startRankedAI(deck: Deck, bracket: io.magicmobile.android.game.CommanderBracket) {
        val position = record.file.rank.position
        // The deck nearest the division's Power from the tier's bracket or lower (docs/DECK_POWER.md); by bracket if unrated.
        val power = setup.deckPower
        val opponent = power?.let {
            io.magicmobile.android.game.AIDeckPool.pickByPower(io.magicmobile.android.game.AIDeckPool.rankedTarget(position.tier.ordinal, position.division, it.rankedTiers),
                position.tier.maxDeckBracket, deck.commanderName, record.file.recentAIDecks, aiPool, it.closest)
        } ?: io.magicmobile.android.game.AIDeckPool.pick(position.opponentBracket, deck.commanderName, record.file.recentAIDecks, aiPool,
            preconsOnly = position.tier.preconOpponentsOnly,
            onlyPrecons = if (position.tier.preconOpponentsOnly) io.magicmobile.android.game.AIDeckPool.gentlestPrecons else null) ?: return
        startSolo(io.magicmobile.android.game.PlayMode.RANKED, deck, bracket, opponent, position.tier.aiSkill)
    }

    /** The host opens a two-seat relay table and shares its code; the guest joins. A table that never fills hands the seat to an AI. */
    suspend fun startRankedHuman(ticket: io.magicmobile.android.game.RankedTicket, deck: Deck, bracket: io.magicmobile.android.game.CommanderBracket) {
        val matchID = ticket.matchId ?: return startRankedAI(deck, bracket)
        activeMatch = ActiveMatch(io.magicmobile.android.game.PlayMode.RANKED, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, bracket.level,
            listOf(io.magicmobile.android.game.MatchOpponent(ticket.opponent ?: "Challenger", null, false)), null, null, null, matchID)
        rankChange = null; rankNote = null
        if (ticket.isHost) {
            setup.hostOnline(playerDisplayName, deck, 2, emptyList(), 2)
            (setup.multiplayer as? RelayTable)?.tableCode?.let { matchmaker.shareTable(matchID, it) }
        } else ticket.tableCode?.let { setup.joinOnline(it, playerDisplayName, deck) }
        rankedConnectJob?.cancel()
        rankedConnectJob = scope.launch {
            delay(75_000)
            if (session.matchID != null || activeMatch?.rankedMatchID != matchID) return@launch
            // Nobody arrived: close the empty table and play the AI instead; nothing was ranked.
            setup.close(); matchmaker.finish(); activeMatch = null
            bannerError = "Your opponent didn't connect. An AI took the seat."
            startRankedAI(deck, bracket)
        }
    }

    /** Phones share a table only with the same engine build (the ranked queue and challenges check it). */
    fun relayProtocol(): String = (setup.identity?.let { "${it.upstreamCommit}/${it.catalogueHash}/$RELAY_ADAPTER_VERSION" } ?: "offline").take(200)

    fun findRankedMatch() {
        val deck = selectedDeck ?: return
        val bracket = selectedDeckBracket ?: return
        if (bracket.level > record.file.rank.position.tier.maxDeckBracket || !mayStartSolo) return
        try { playerDisplayName = OnDeviceSetupModel.playerName(playerDisplayName) } catch (error: EngineError) { setup.errorMessage = error.message; return }
        record.refreshSeason()
        matchmaker.service = vm.account.rankedQueue
        scope.launch {
            when (val outcome = matchmaker.search(relayProtocol(), record.file.rank.position.step, bracket.level)) {
                io.magicmobile.android.game.RankedSearch.Cancelled -> {}
                io.magicmobile.android.game.RankedSearch.AI -> startRankedAI(deck, bracket)
                is io.magicmobile.android.game.RankedSearch.Human -> startRankedHuman(outcome.ticket, deck, bracket)
            }
        }
    }

    /** The deck for a game against a person, or null (with the reason shown). Ranked also needs a deck your tier allows. */
    fun personGameDeck(ranked: Boolean): Pair<Deck, io.magicmobile.android.game.CommanderBracket>? {
        val deck = selectedDeck; val bracket = selectedDeckBracket
        if (deck == null || bracket == null || !mayStartSolo) { bannerError = "Choose a deck and let the engine finish loading, then try again."; return null }
        if (ranked && bracket.level > record.file.rank.position.tier.maxDeckBracket) { bannerError = "Your deck's bracket is above what your rank allows in Ranked."; return null }
        try { playerDisplayName = OnDeviceSetupModel.playerName(playerDisplayName) } catch (error: EngineError) { setup.errorMessage = error.message; return null }
        return deck to bracket
    }

    suspend fun closeChallengeTable(message: String?) {
        setup.close(); activeMatch = null
        if (message != null) bannerError = message
    }

    /** A challenge table that never starts closes after a while; nothing is recorded. */
    fun watchPersonTable(friend: String) {
        rankedConnectJob?.cancel()
        rankedConnectJob = scope.launch {
            delay(75_000)
            if (session.matchID != null || activeMatch?.privateTable != true) return@launch
            closeChallengeTable("$friend didn't connect. Try the challenge again.")
        }
    }

    /** Challenges a friend: opens a two-seat table, sends its code and waits for the answer. Ranked counts like any ranked game. */
    fun challengeFriend(friend: String, mode: io.magicmobile.android.game.PlayMode) {
        record.refreshSeason()
        val (deck, bracket) = personGameDeck(mode == io.magicmobile.android.game.PlayMode.RANKED) ?: return
        challenges.service = vm.account.challenges
        matchmaker.service = vm.account.rankedQueue
        scope.launch {
            delay(450)  // after the friends sheet closes
            activeMatch = ActiveMatch(mode, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, bracket.level,
                listOf(io.magicmobile.android.game.MatchOpponent(friend, null, false)), null, null, null, privateTable = true)
            rankChange = null; rankNote = null
            challengeTarget = friend to mode
            setup.hostOnline(playerDisplayName, deck, 2, emptyList(), 2)
            val code = (setup.multiplayer as? RelayTable)?.tableCode
            if (code == null) { activeMatch = null; challengeTarget = null; return@launch }
            val answer = challenges.challenge(friend, mode, relayProtocol(), record.file.rank.position.step, code)
            challengeTarget = null
            when (answer) {
                is io.magicmobile.android.game.ChallengeAnswer.Accepted -> {
                    activeMatch = activeMatch?.copy(rankedMatchID = answer.challenge.matchId)
                    watchPersonTable(friend)
                }
                io.magicmobile.android.game.ChallengeAnswer.Declined -> closeChallengeTable("$friend declined your challenge.")
                io.magicmobile.android.game.ChallengeAnswer.Expired -> closeChallengeTable("$friend didn't answer your challenge.")
                io.magicmobile.android.game.ChallengeAnswer.Cancelled -> closeChallengeTable(null)
                is io.magicmobile.android.game.ChallengeAnswer.Failed -> closeChallengeTable(io.magicmobile.android.game.FriendChallengeRules.message(answer.code))
            }
        }
    }

    /** Accepts a friend's challenge and joins their table. */
    fun acceptChallenge(challenge: io.magicmobile.android.game.FriendChallenge) {
        record.refreshSeason()
        val step = record.file.rank.position.step
        if (challenge.isRanked && !io.magicmobile.android.game.FriendChallengeRules.mayRank(step, challenge.challengerStep)) {
            bannerError = io.magicmobile.android.game.FriendChallengeRules.message("rank_mismatch")
            scope.launch { challenges.decline(challenge) }
            return
        }
        val (deck, bracket) = personGameDeck(challenge.isRanked) ?: return
        matchmaker.service = vm.account.rankedQueue
        val friend = challenge.challenger ?: "Friend"
        scope.launch {
            try {
                val accepted = challenges.accept(challenge, relayProtocol(), step)
                val code = accepted.tableCode ?: throw io.magicmobile.android.social.SupabaseLite.Failure("challenge_closed")
                activeMatch = ActiveMatch(challenge.playMode, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, bracket.level,
                    listOf(io.magicmobile.android.game.MatchOpponent(friend, null, false)), null, null, null, accepted.matchId, privateTable = true)
                rankChange = null; rankNote = null
                setup.joinOnline(code, playerDisplayName, deck)
                watchPersonTable(friend)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                bannerError = io.magicmobile.android.game.FriendChallengeRules.message(io.magicmobile.android.social.SupabaseLite.code(e))
            }
        }
    }

    fun saveResult(match: ActiveMatch, outcome: io.magicmobile.android.game.RankOutcome, turns: Int, snapshot: GameSnapshot?,
                   gameRecordFile: String? = null) {
        val colors = match.colors.ifEmpty { io.magicmobile.android.game.PlayerStats.colors(snapshot?.human?.zones?.command?.firstOrNull()?.card?.manaCost) }
        val change = record.record(match.mode, outcome, match.opponents, match.opponentBracket, match.aiSkill, match.deckID, match.deckName,
            match.commander, colors, match.deckBracket, turns, match.aiDeckID, session.matchID, gameRecordFile)
        rankChange = change
        rankNote = null
        val ranked = match.mode == io.magicmobile.android.game.PlayMode.RANKED
        val recordedID = if (ranked) record.file.matches.firstOrNull()?.id else null
        scope.launch {
            match.rankedMatchID?.let { id -> matchmaker.report(id, outcome) }
            // The server keeps score: send the result and take its standing (the phone's own count shows meanwhile),
            // then upload the game so its rank history point is the standing after it.
            if (ranked) vm.account.afterRefresh?.invoke()
            // The server's word replaces the phone's guess on the result screen still showing this game.
            val settled = recordedID?.let { id -> record.file.matches.firstOrNull { it.id == id } }
            if (settled != null && rankChange == change) { rankChange = settled.rankChange; rankNote = settled.rankNote }
        }
        if (change != null && change.isMilestone) scope.launch { delay(1500); if (rankChange == change) ceremony = change }
    }

    /** Records a finished game once: every game goes into the profile, ranked games move the ladder. */
    fun recordFinishedGameIfNeeded() {
        val snapshot = session.snapshot ?: return
        if (!snapshot.isCompleted && !snapshot.isSpectating) return
        val current = activeMatch ?: selectedDeck?.let { deck ->
            ActiveMatch(io.magicmobile.android.game.PlayMode.CASUAL, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors,
                selectedDeckBracket?.level ?: 2, snapshot.players.filter { !snapshot.isViewer(it.playerId) }.map {
                    io.magicmobile.android.game.MatchOpponent(it.displayName ?: "Opponent", it.zones.command.firstOrNull()?.card?.name, !setup.usingMultiplayer)
                }, null, if (setup.usingMultiplayer) null else aiSkill, null)
        } ?: return
        if (current.recorded) return
        val winners = snapshot.winnerPlayerIds.orEmpty()
        val outcome = when {
            snapshot.viewerID in winners -> io.magicmobile.android.game.RankOutcome.WIN
            snapshot.isCompleted && winners.isEmpty() -> io.magicmobile.android.game.RankOutcome.DRAW
            else -> io.magicmobile.android.game.RankOutcome.LOSS
        }
        activeMatch = current.copy(recorded = true)
        // The engine's game record first (solo games, before the match is destroyed), so a ranked result goes with it.
        scope.launch {
            val file = setup.finishedGameRecord()?.let(record::keepGameRecord)
            saveResult(current, outcome, snapshot.turn, snapshot, file)
        }
    }

    /** Leaving a ranked game before it ends counts as a loss. */
    fun recordAbandonedRankedGame() {
        val match = activeMatch ?: return
        if (match.mode != io.magicmobile.android.game.PlayMode.RANKED || match.recorded || session.matchID == null) return
        saveResult(match, io.magicmobile.android.game.RankOutcome.LOSS, session.snapshot?.turn ?: 0, session.snapshot)
        activeMatch = match.copy(recorded = true)
    }

    /** The player leaves: the board closes and its saved checkpoint is deleted. */
    fun closeGame() {
        recordAbandonedRankedGame()
        scope.launch {
            if (setup.leave()) {
                if (guidedGame) endGuidedTips()
                selection.selectedCard = null; selection.inspectedCard = null
                activeMatch = null; rankChange = null; rankNote = null; ceremony = null; matchmaker.finish(); rankedConnectJob?.cancel()
            }
        }
    }

    fun requestLeave() { if (!setup.isBusy && !session.isWorking) confirmLeave = true }


    fun startAI() {
        val deck = selectedDeck ?: return
        if (aiPrecons.size != opponentCount) return
        activeMatch = null; rankChange = null; rankNote = null
        val opponentDecks = aiPrecons.map { it.deck }
        val settings = GameResumeSettings(selectedDeckID, aiIDs.take(opponentCount.coerceIn(1, 3)), aiSkill, aiStartingPlayerMode)
        scope.launch {
            try { playerDisplayName = OnDeviceSetupModel.playerName(playerDisplayName) }
            catch (error: EngineError) { setup.errorMessage = error.message; return@launch }
            setup.startAI(playerDisplayName, deck, opponentDecks, aiSkill, settings, deckID = selectedDeckID)
        }
    }

    /** Resume puts the saved game's setup back, so the menu and Rematch match the restored board. */
    fun resumeSavedGame() {
        // A guided game picks its coach up again and keeps the player's own deck and settings.
        val guided = setup.resume.offer?.sidecar?.settings?.deckID == GuidedGameSetup.PLAYER_DECK_ID && guidedActive
        guidedGame = guided; guidedTipID = null
        if (!guided) setup.resume.offer?.sidecar?.settings?.let { saved ->
            if (saved.deckID in setup.deckIDs) selectedDeckID = saved.deckID
            val ids = saved.aiDeckIDs.filter { id -> aiPool.any { it.id == id } }
            val mode = saved.mode?.let { raw -> io.magicmobile.android.game.PlayMode.entries.firstOrNull { it.raw == raw } }
            activeMatch = mode?.let { m ->
                val foes = ids.mapNotNull { id -> aiPool.firstOrNull { it.id == id } }
                ActiveMatch(m, saved.deckID, setup.deck(saved.deckID)?.name ?: "Deck", setup.deck(saved.deckID)?.commanderName, emptyList(),
                    saved.deckBracket ?: 2, foes.map { io.magicmobile.android.game.MatchOpponent(it.name, it.commander, true) },
                    foes.firstOrNull()?.bracket?.level, saved.aiSkill, foes.firstOrNull()?.id)
            }
            rankChange = null; rankNote = null
            if (mode == null && ids.size == saved.aiDeckIDs.size && ids.size in 1..3) {
                opponentCount = ids.size
                ids.getOrNull(0)?.let { aiPreconID = it }; ids.getOrNull(1)?.let { aiPrecon2ID = it }; ids.getOrNull(2)?.let { aiPrecon3ID = it }
            }
            aiSkill = saved.aiSkill.coerceIn(1, 10)
            // A ranked game always rolls, so its saved "roll" is not the player's own choice.
            if (mode != io.magicmobile.android.game.PlayMode.RANKED && saved.startingPlayerMode in setOf("choose", "roll")) aiStartingPlayerMode = saved.startingPlayerMode
        }
        scope.launch { setup.resumeGame() }
    }

    fun refresh() { scope.launch { setup.perform { session.refresh(); setup.updateSessionForeground() } } }

    fun rematchOrLeave() {
        if (session.snapshot?.isCompleted != true || setup.usingMultiplayer) return requestLeave()
        val mode = activeMatch?.mode
        val guided = guidedGame
        scope.launch {
            if (!setup.close()) return@launch
            if (guided) return@launch startGuidedGame()
            selection.selectedCard = null; selection.inspectedCard = null
            activeMatch = null; rankChange = null; rankNote = null
            // Quick Match deals a new opponent; Ranked looks for the next match.
            when (mode) {
                io.magicmobile.android.game.PlayMode.QUICK -> startQuickMatch()
                io.magicmobile.android.game.PlayMode.RANKED -> { playModeRaw = io.magicmobile.android.game.ArenaPlayMode.RANKED.raw; findRankedMatch() }
                else -> startAI()
            }
        }
    }

    fun leaveFinishedOrAsk() {
        val spectatingSolo = session.snapshot?.isSpectating == true && !setup.usingMultiplayer
        if (session.snapshot?.isCompleted != true && !spectatingSolo) return requestLeave()
        showSetup = false
        closeGame()
    }

    fun concede() {
        scope.launch {
            // A conceded game is never resumed.
            try { session.concede(); setup.resume.discard() }
            catch (error: EngineError.Rejected) {
                if (error.code == "unknown_operation" || error.code == "concede_unavailable") { showSetup = false; closeGame() }
                else setup.errorMessage = error.message
            } catch (error: Throwable) { setup.errorMessage = error.message }
        }
    }

    /** The engine's "starting player" answer for the roll's winner, if this is that prompt. */
    fun startingChoice(snapshot: GameSnapshot): Pair<GameCommand, String>? {
        val table = setup.multiplayer as? RelayTable
        return if (setup.usingMultiplayer && table != null) {
            val roll = table.startingRoll ?: return null
            val winnerName = table.seatNames[roll.winnerSeatID] ?: return null
            OnDeviceStartingPlayerChoice.commandForName(snapshot, winnerName)?.let { it to winnerName }
        } else if (!setup.usingMultiplayer && startingPlayerMode() == "roll") {
            val roll = aiStartingRoll ?: return null
            OnDeviceStartingPlayerChoice.command(snapshot, winnerPlayerID = roll.winnerSeatID)?.let { it to (aiRollSeatNames[roll.winnerSeatID] ?: "winner") }
        } else null
    }

    /** A table answers as soon as every die is shown (the host is the one XMage asks); an AI game when the roll is closed. */
    fun submitStartingChoiceIfNeeded() {
        val tableRollShown = setup.usingMultiplayer && (setup.multiplayer as? RelayTable)?.rollShown == true
        if (!didDismissStartingRoll && !tableRollShown) return
        val snapshot = session.snapshot ?: return
        val promptID = snapshot.promptEnvelopeV2?.id ?: return
        if (attemptedStartingPromptID == promptID || startingChoice(snapshot) == null) return
        attemptedStartingPromptID = promptID
        scope.launch {
            // An automatic reply is never dropped: a busy session, a paused table or a stale
            // snapshot only delays it. A new prompt means it went through.
            repeat(12) { attempt ->
                if (attempt > 0) delay(minOf(250L * attempt, 1500L))
                val current = session.snapshot
                if (attemptedStartingPromptID != promptID || current?.promptEnvelopeV2?.id != promptID) return@launch
                val choice = if (!setup.isBusy && !session.isWorking && setup.canUseSession) startingChoice(current) else null
                if (choice != null && runCatching { session.send(choice.first, "Start with ${choice.second}", "starting-roll-$promptID") }.isSuccess) return@launch
            }
            if (attemptedStartingPromptID == promptID && session.snapshot?.promptEnvelopeV2?.id == promptID) {
                startingChoiceFailedPromptID = promptID
                setup.errorMessage = "The roll's winner couldn't be sent. Choose the starting player."
            }
        }
    }

    fun advanceAIRollIfNeeded() {
        val roll = aiStartingRoll ?: return
        val viewerID = session.snapshot?.viewerID ?: return
        val step = roll.steps.getOrNull(aiRevealedRollCount) ?: return
        if (step.seatID == viewerID) return
        val expected = aiRevealedRollCount
        scope.launch {
            delay(650)
            if (session.matchID != null && aiStartingRoll == roll && aiRevealedRollCount == expected && !didDismissStartingRoll) aiRevealedRollCount += 1
        }
    }

    fun prepareAIRollIfNeeded() {
        if (setup.usingMultiplayer || startingPlayerMode() != "roll" || session.matchID == null || aiStartingRoll != null || didDismissStartingRoll) return
        val snapshot = session.snapshot ?: return
        val targetIDs = OnDeviceStartingPlayerChoice.candidateIDs(snapshot) ?: return
        try {
            val viewerFirst = listOf(snapshot.viewerID) + targetIDs.filter { it != snapshot.viewerID }
            aiStartingRoll = OnDeviceStartingRoll.generate(viewerFirst)
            aiRevealedRollCount = 0
            aiRollSeatNames = snapshot.players.associate { it.playerId to if (it.playerId == snapshot.viewerID) "You" else it.displayName ?: "AI opponent" }
            advanceAIRollIfNeeded()
        } catch (error: Throwable) { bannerError = "Could not roll for the starting player: ${error.message}" }
    }

    fun advanceLocalAIRoll() {
        val roll = aiStartingRoll ?: return
        val viewerID = session.snapshot?.viewerID ?: return
        if (roll.steps.getOrNull(aiRevealedRollCount)?.seatID == viewerID) aiRevealedRollCount += 1
    }

    // Lifecycle: prepare once, pause input and polling in the background.
    LaunchedEffect(Unit) { setup.prepare() }
    LaunchedEffect(setup.identity, setup.localDecks) { if (!activeGame) restoreSetupPreferences() }
    // Cards drawn by name (the board, the opening hand, profile art) show the art chosen in the playing deck first.
    LaunchedEffect(selectedDeckID) { io.magicmobile.android.ArtChoices.shared.select(selectedDeckID) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> { setup.returnedToApp(); setup.setSceneActive(true); GameAudio.resume() }
                // The player may be leaving (perhaps to close the app from Recents): the engine saves at its next safe point.
                Lifecycle.Event.ON_PAUSE -> { setup.setSceneActive(false); setup.armSaveForLeaving() }
                Lifecycle.Event.ON_START -> { setup.returnedToApp(); vm.account.setForeground(true); appForeground = true }
                // Leaving starts the saved game's 10 minutes and saves it, and a smaller app is less likely to be ended.
                Lifecycle.Event.ON_STOP -> {
                    setup.saveForBackground(); Artwork.releaseMemory(); GameAudio.releaseForBackground(); vm.account.setForeground(false)
                    appForeground = false
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    // Deck sync (docs/DECK_SYNC.md): when the profile is ready or its name changes, on returning to the app and every
    // 5 minutes while it is open; a change here goes up a few seconds after the last one, when something waits to go up.
    val accountReady = vm.account.phase == PlayerAccount.Phase.READY
    LaunchedEffect(accountReady, vm.account.username, appForeground) {
        if (!accountReady || !appForeground) return@LaunchedEffect
        while (true) { vm.syncDecks(); delay(5 * 60_000L) }
    }
    LaunchedEffect(setup.localDecks, accountReady) {
        if (!accountReady || !vm.deckSyncPending()) return@LaunchedEffect
        delay(3_000); vm.syncDecks()
    }
    LaunchedEffect(portraitModeEnabled, activeGame) { OrientationController.apply(activity, portraitModeEnabled, activeGame) }
    LaunchedEffect(session.snapshot?.isCompleted, session.snapshot?.isSpectating) { recordFinishedGameIfNeeded() }
    LaunchedEffect(session.snapshot?.turn) { io.magicmobile.android.ui.GamePerformanceRecorder.noteTurn(session.snapshot?.turn) }
    // During a game, friends' messages are checked every 15 seconds (the menu's heartbeat is slower), and a new one shows a banner.
    LaunchedEffect(activeGame, vm.account.messagesAvailable) {
        if (!activeGame || !vm.account.messagesAvailable) return@LaunchedEffect
        var seen = vm.account.unreadMessages
        while (true) {
            delay(15_000)
            if (!appForeground) continue
            vm.account.refreshUnread()
            if (vm.account.unreadMessages > seen && messagesHub == null) {
                vm.account.conversations()?.firstOrNull { it.unread > 0 && !it.last.fromMe }?.let {
                    messageBanner = it.username to io.magicmobile.android.game.FriendMessageRules.shown(it.last)
                }
            }
            seen = vm.account.unreadMessages
        }
    }
    // A hot phone shortens AI thinking in games its engine runs: never ranked (the same AI for everyone) or online.
    LaunchedEffect(activeGame, io.magicmobile.android.ui.DeviceHeat.isHot, activeMatch?.mode) {
        session.devicePaceHot = activeGame && !setup.usingMultiplayer && activeMatch?.mode != io.magicmobile.android.game.PlayMode.RANKED &&
            io.magicmobile.android.ui.DeviceHeat.isHot
    }
    LaunchedEffect(activeGame) {
        // The combo loop shortcut: solo games only.
        session.comboLoopsAllowed = activeGame && !setup.usingMultiplayer
        if (activeGame) { matchmaker.finish(); rankedConnectJob?.cancel() }
        if (activeGame) io.magicmobile.android.ui.GamePerformanceRecorder.begin(activeMatch?.mode?.raw ?: if (setup.usingMultiplayer) "online" else "custom", activeMatch?.aiSkill)
        else io.magicmobile.android.ui.GamePerformanceRecorder.end()
        if (activeGame) {
            FreezeLog.mode = activeMatch?.mode?.raw ?: if (setup.usingMultiplayer) "table" else "custom"
            FreezeLog.crumb("Game started (${FreezeLog.mode}${if (setup.resume.resumedGame) ", resumed" else ""})")
        } else FreezeLog.mode = "none"
        GameAudio.setScene(if (activeGame) GameMusic.GAME else GameMusic.MENU)
        // A resumed game is not a new matchup: no versus intro.
        if (!activeGame || setup.resume.resumedGame) { versusIntro = null; return@LaunchedEffect }
        if (reduceMotion) GameAudio.play(GameSound.VERSUS, after = 0.2)
        else { versusIntro = makeVersusIntro(); GameAudio.play(GameSound.VERSUS, after = 0.05) }
    }
    LaunchedEffect(matchPhase) {
        when (val phase = matchPhase) {
            io.magicmobile.android.game.RankedMatchmaker.Phase.Idle -> {}
            is io.magicmobile.android.game.RankedMatchmaker.Phase.Searching -> FreezeLog.crumb("Ranked: searching")
            is io.magicmobile.android.game.RankedMatchmaker.Phase.Matched ->
                FreezeLog.crumb("Ranked: matched (${if (phase.ticket.matchId == null) "AI" else if (phase.ticket.isHost) "host" else "guest"})")
        }
    }
    // Session errors log themselves; these are the setup's and the menus' own.
    LaunchedEffect(bannerError) { bannerError?.takeIf { it != session.errorMessage }?.let { FreezeLog.crumb("Notice: $it") } }
    fun sendFreezeReport(incident: io.magicmobile.android.game.FreezeIncident) {
        scope.launch {
            val sent = FreezeLog.send(incident) { kind, report -> vm.account.sendDiagnostic(kind, report) }
            val notice = if (sent) "Freeze report sent. Thank you." else "The freeze report couldn't be sent. It's still saved on this phone."
            bannerError = notice
            delay(5_000)
            if (bannerError == notice) bannerError = null
        }
    }
    val errorKey = setup.errorMessage ?: session.errorMessage
    LaunchedEffect(errorKey) {
        bannerError = errorKey
        if (bannerError == null) return@LaunchedEffect
        delay(8000)
        bannerError = null
    }
    LaunchedEffect(session.snapshot?.bridgeRevision) {
        val snapshot = session.snapshot
        if (snapshot == null) selection.inspectedCard = null
        else selection.inspectedCard?.let { current -> selection.inspectedCard = snapshot.players.flatMap { p -> p.zones.battlefield + p.zones.hand + p.zones.graveyard + p.zones.exile + p.zones.command }.firstOrNull { it.id == current.id } }
        prepareAIRollIfNeeded()
    }
    LaunchedEffect(session.snapshot?.promptEnvelopeV2?.id) { prepareAIRollIfNeeded(); submitStartingChoiceIfNeeded() }
    LaunchedEffect(session.isWorking, setup.isBusy) { if (!session.isWorking && !setup.isBusy) submitStartingChoiceIfNeeded() }
    LaunchedEffect(session.matchID) {
        // A table's roll outlives the session attaching to its match; resetting it here replayed a
        // finished roll. Tables reset on a new roll instead (below).
        if (!setup.usingMultiplayer) { didDismissStartingRoll = false; attemptedStartingPromptID = null }
        aiStartingRoll = null; aiRevealedRollCount = 0; aiRollSeatNames = emptyMap()
        prepareAIRollIfNeeded()
    }
    val table = setup.multiplayer as? RelayTable
    val turnClockFeed = remember(table, setup.usingMultiplayer) {
        table?.takeIf { setup.usingMultiplayer }?.let { io.magicmobile.android.board.TurnClockFeed({ it.turnClock }, { it.localSeatID }, { it.seatNames }) }
    }
    LaunchedEffect(table?.startingRoll) { didDismissStartingRoll = false; attemptedStartingPromptID = null; startingChoiceFailedPromptID = null }
    LaunchedEffect(table?.rollShown) { submitStartingChoiceIfNeeded() }
    // A ranked or challenge table is for that one player only, never shown to friends.
    LaunchedEffect(table?.openHostedTable) { vm.account.hosting = if (activeMatch?.isPersonTable != true) table?.openHostedTable else null }
    // A ranked or challenge table readies both players by itself once the room forms.
    LaunchedEffect(table?.room != null) {
        val room = table?.room ?: return@LaunchedEffect
        if (activeMatch?.isPersonTable == true && !room.localReady) selectedDeck?.let { setup.readyForMatch(playerDisplayName, it) }
    }
    LaunchedEffect(table?.endpoint?.matchID) { if (table?.endpoint != null) setup.attachTable(table, selectedDeckID, selectedDeck) }
    LaunchedEffect(table?.isConnected, table?.isSuspended) { setup.updateSessionForeground() }
    // Relay tables carry quick chat between phones; solo games only answer from the AI.
    LaunchedEffect(session.snapshot?.id, table) {
        vm.emotes.reset()
        vm.emotes.send = table?.let { current -> { emote -> current.sendEmote(emote) } }
        table?.onEmote = { name, emote -> vm.emotes.receive(emote, name, session.snapshot) }
        vm.emotes.sendText = table?.let { current -> { text -> current.sendChat(text) } }
        vm.account.blocked.forEach(vm.emotes::mute)
        table?.onChat = { name, text -> vm.emotes.receiveText(text, name) }
    }

    // Deck Studio handles Back itself while it is open.
    BackHandler(enabled = !activeGame && showSetup && !showDecks) {
        GameAudio.play(GameSound.UI_BACK)
        // Back from the custom table returns to the Play panel's Custom page, as its header's chevron does.
        if (!setup.isBusy && !setup.needsLeave) { showSetup = false; openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.CUSTOM) }
    }
    BackHandler(enabled = activeGame) { requestLeave() }

    val turnControl = NativeTurnControl(session.canEndTurn, session.canEndTurnSkippingResponses, session.canSkipToMyTurn, session.isAutoPassing,
        session.autoPassStatus, { session.endTurn() }, { session.endTurnSkippingResponses() }, { session.skipToMyTurn() }, { session.stopAutoPass() },
        session.isFullControl, { session.toggleFullControl() })

    // One flag for everything the starting roll covers (iOS startingRollVisible): a relay table's
    // shared roll or its "Who goes first?" panel, or an AI table's local roll.
    val multiplayerRollVisible = setup.usingMultiplayer && table != null && table.endpoint != null && table.isConnected && !didDismissStartingRoll
    val aiRoll = aiStartingRoll
    val aiRollVisible = !setup.usingMultiplayer && session.matchID != null && startingPlayerMode() == "roll" && aiRoll != null && !didDismissStartingRoll
    val startingRollVisible = multiplayerRollVisible || aiRollVisible
    // The roll's own answer to "Select a starting player" stays quiet while it is on its way.
    val startingChoicePending = session.snapshot?.let { snapshot ->
        val promptID = snapshot.promptEnvelopeV2?.id
        promptID != null && startingChoiceFailedPromptID != promptID && OnDeviceStartingPlayerChoice.candidateIDs(snapshot) != null &&
            (if (setup.usingMultiplayer) table?.startingRoll != null else startingPlayerMode() == "roll" && aiStartingRoll != null)
    } == true
    val boardQuiet = startingRollVisible || startingChoicePending

    // A join link (iOS openJoinLink): the online table setup with its code, joining right away with the
    // chosen deck. During a game the code waits in the field instead; before the catalogue loads it waits here.
    var pendingJoinCode by remember { mutableStateOf<String?>(null) }
    fun openJoinLink(code: String) {
        setup.relayJoinCode = code
        if (activeGame || setup.needsLeave || (setup.multiplayer as? RelayTable)?.tableCode != null) {
            bannerError = "Finish or leave this game, then join table $code."
            return
        }
        playWithFriends = true
        showSetup = true
        if (setup.identity == null) { pendingJoinCode = code; return }
        val deck = selectedDeck ?: return
        if (!setup.isBusy && runCatching { OnDeviceSetupModel.playerName(playerDisplayName) }.isSuccess) setup.joinOnline(code, playerDisplayName, deck)
    }
    LaunchedEffect(vm.joinLinkCode) { vm.joinLinkCode?.let { code -> vm.joinLinkCode = null; openJoinLink(code) } }
    LaunchedEffect(setup.identity) { if (setup.identity != null) pendingJoinCode?.let { code -> pendingJoinCode = null; openJoinLink(code) } }

    // The main menu is showing with nothing over it (no game, setup, saved-game offer or sheet).
    val menuIsFree = !activeGame && !showSetup && !setup.needsLeave && setup.resume.offer == null && !startingRollVisible &&
        !(showDecks || showAppearance || showUpdates || showDownloads || showHowToPlay || showGuidedWelcome || showFriends)
    // Friends' challenges arrive while the menu or a lobby is open (never during a game), and only for a player with
    // friends: nobody else can send one.
    val watchesChallenges = appForeground && vm.account.phase == io.magicmobile.android.social.PlayerAccount.Phase.READY &&
        vm.account.username != null && !activeGame && !setup.needsLeave && vm.account.friends.any { it.isFriend }
    LaunchedEffect(watchesChallenges) {
        if (!watchesChallenges) return@LaunchedEffect
        challenges.service = vm.account.challenges
        challenges.watch { vm.account.onlineFriendCount > 0 }
    }
    // First visit to the menu after this update: the walkthrough opens once by itself.
    LaunchedEffect(menuIsFree) {
        if (!menuIsFree) return@LaunchedEffect
        delay(700)
        if (GuidedGameLaunch.shouldShowWelcome(guidedWelcomeSeen, howToPlaySeenVersion, LaunchEnvironment.values)) showGuidedWelcome = true
        else if (HowToPlayLaunch.shouldShowAutomatically(howToPlaySeenVersion, LaunchEnvironment.values)) { howToPlayOpensTable = true; showHowToPlay = true }
        else if (OfflineArtLaunch.shouldShowAutomatically(howToPlaySeenVersion, offlineArtPromptSeen, LaunchEnvironment.values)) showOfflineArtPrompt = true
    }
    fun closeHowToPlay() {
        showHowToPlay = false; howToPlayOpensTable = false
        howToPlaySeenVersion = HowToPlayLaunch.seenVersionAfterClosing(howToPlaySeenVersion)
    }

    // MARK: Arena menus (OnDeviceRootView.swift)

    /** A deck's colours from its commanders' identities in the card catalogue (empty until it is loaded). */
    val catalogue = setup.catalogue
    fun deckColors(deck: Deck): List<String> = io.magicmobile.android.game.ArenaDeckColors.colors(
        deck.entries.filter { it.section == "commanders" || it.section == "commander" }.map { it.name }) { name -> catalogue?.find(name)?.identity }

    /** The top bar's lit tab for what the menu shows; a utility panel lights its own icon instead. */
    val menuTab = io.magicmobile.android.game.ArenaMenuTab.lit(showAppearance || showUpdates || showDownloads || showFriends, showDecks, showHowToPlay, lobby)

    fun selectMenuTab(tab: io.magicmobile.android.game.ArenaMenuTab) {
        // A table being set up or left keeps its page until it's done.
        if ((setup.isBusy || setup.needsLeave) && tab != io.magicmobile.android.game.ArenaMenuTab.LEARN) return
        when (tab) {
            io.magicmobile.android.game.ArenaMenuTab.LEARN -> { showHowToPlay = true; return }
            io.magicmobile.android.game.ArenaMenuTab.DECKS -> { openDecks(); return }
            io.magicmobile.android.game.ArenaMenuTab.HOME -> lobby = null
            io.magicmobile.android.game.ArenaMenuTab.PROFILE -> lobby = "profile"
            io.magicmobile.android.game.ArenaMenuTab.RANKED -> lobby = "rankedHall"
        }
        showSetup = false
        showDecks = false
        if (matchPhase == io.magicmobile.android.game.RankedMatchmaker.Phase.Idle && !challengeWaiting) playPanel = false
    }

    /** The chosen deck as a deck box. */
    val selectedDeckBox = selectedDeck?.let { deck ->
        io.magicmobile.android.menus.ArenaDeckBoxModel(selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, selectedDeckBracket?.label ?: "")
    }

    /** Every deck as a box, by shelf: your own, the precons, then the included decks by bracket. */
    val deckBoxSections = remember(setup.localDecks, setup.precons, setup.bracketDecks, setup.bracketRules, bracketRevision, catalogue) {
        val mine = setup.localDecks.map { saved ->
            val id = "local:${saved.id}"
            val bracket = io.magicmobile.android.game.DeckBracketPreference.effective(setup.bracketRules.evaluate(saved.deck).minimum, declaredBracket(id))
            io.magicmobile.android.menus.ArenaDeckBoxModel(id, saved.deck.name, saved.deck.commanderName, deckColors(saved.deck), bracket.label)
        }
        val preconBoxes = setup.precons.map {
            io.magicmobile.android.menus.ArenaDeckBoxModel("precon:${it.id}", it.name, it.commander, deckColors(it.deck), io.magicmobile.android.game.CommanderBracket.CORE.label)
        }
        val included = io.magicmobile.android.game.CommanderBracket.entries.mapNotNull { bracket ->
            setup.bracketDecks.filter { it.bracket == bracket }.takeIf { it.isNotEmpty() }?.let { decks ->
                io.magicmobile.android.menus.ArenaDeckSection("included-${bracket.level}", "Included · ${bracket.label}", decks.map {
                    io.magicmobile.android.menus.ArenaDeckBoxModel(it.playerDeckID, it.name, it.commander, it.colors.map(Char::toString), bracket.label)
                })
            }
        }
        listOf(io.magicmobile.android.menus.ArenaDeckSection("mine", "My Decks", mine, offersNewDeck = true),
            io.magicmobile.android.menus.ArenaDeckSection("precons", "Precons", preconBoxes)) + included
    }
    // The boxes' pips read the catalogue; it loads once the Play panel opens.
    LaunchedEffect(playPanel) { if (playPanel) setup.loadCatalogue() }

    fun homeContent(): io.magicmobile.android.menus.ArenaHomeContent {
        val rank = record.file.rank
        val season = io.magicmobile.android.game.RankLadder.seasonName(rank.season)
        val art = { id: Int, x: Float, y: Float -> io.magicmobile.android.menus.ArenaHomeArt(id, x, y) }
        return io.magicmobile.android.menus.ArenaHomeContent(
            features = listOf(
                io.magicmobile.android.menus.ArenaFeature("ranked", "Ranked season", "Ranked · $season", art(io.magicmobile.android.R.drawable.home_art_ur_dragon, 0.62f, 0.3f)) {
                    selectMenuTab(io.magicmobile.android.game.ArenaMenuTab.RANKED)
                },
                io.magicmobile.android.menus.ArenaFeature("board", "New", "The Arena board", art(io.magicmobile.android.R.drawable.home_art_edgar_markov, 0.55f, 0.22f)) {
                    showUpdates = true
                },
                io.magicmobile.android.menus.ArenaFeature("friends", "Friends", "Bring a friend to the table", art(io.magicmobile.android.R.drawable.home_art_yshtola, 0.62f, 0.25f)) {
                    showFriends = true
                },
                // The tip jar (it was a strip at the foot of the old menu): the support page, in the browser.
                io.magicmobile.android.menus.ArenaFeature("support", "Support", "Enjoying MagicMobile?", art(io.magicmobile.android.R.drawable.home_art_atraxa, 0.5f, 0.2f)) {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SupportProject.URL))) }
                }),
            tiles = listOf(
                io.magicmobile.android.menus.ArenaHomeTile("quick", "Quick Match", "", art(io.magicmobile.android.R.drawable.home_art_krenko, 0.5f, 0.38f)) {
                    openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.QUICK)
                },
                // The rank shows on the rail and the top bar; the tile names the mode only (the judge, 2026-10-22).
                io.magicmobile.android.menus.ArenaHomeTile("ranked", "Ranked", "",
                    art(io.magicmobile.android.R.drawable.home_art_miirym, 0.55f, 0.4f)) { openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.RANKED) },
                io.magicmobile.android.menus.ArenaHomeTile("learn", HowToPlayText.TITLE, "", art(io.magicmobile.android.R.drawable.home_art_giada, 0.6f, 0.3f)) {
                    showHowToPlay = true
                }),
            deck = selectedDeckBox, rank = rank.position, wins = rank.wins, losses = rank.losses,
            friendsOnline = vm.account.onlineFriendCount, unread = vm.account.incomingCount + vm.account.unreadMessages > 0,
            play = { openPlayPanel() }, friends = { showFriends = true }, updates = { showUpdates = true }, downloads = { showDownloads = true },
            openDeck = { openPlayPanel() }, openRank = { selectMenuTab(io.magicmobile.android.game.ArenaMenuTab.RANKED) })
    }

    fun playModel(): io.magicmobile.android.menus.ArenaPlayPanelModel = io.magicmobile.android.menus.ArenaPlayPanelModel(
        sections = deckBoxSections, selectedDeckID = selectedDeckID, selectDeck = { selectedDeckID = it }, deckBracket = selectedDeckBracket,
        mode = io.magicmobile.android.game.ArenaPlayMode.of(playModeRaw), setMode = { playModeRaw = it.raw },
        tab = playTab, setTab = { playTabRaw = it.raw },
        quickBracket = quickBracket, setQuickBracket = { quickBracket = it }, quickDeckID = quickDeckID, setQuickDeckID = { quickDeckID = it },
        quickSkill = quickSkill, setQuickSkill = { quickSkill = it }, quickLevel = quickLevel, setQuickLevel = { quickLevel = it }, startingPlayer = aiStartingPlayerMode, setStartingPlayer = { aiStartingPlayerMode = it },
        aiPool = aiPool, rank = record.file.rank, canSearchPeople = vm.account.rankedQueue != null,
        search = matchPhase.takeIf { it != io.magicmobile.android.game.RankedMatchmaker.Phase.Idle }
            ?: if (io.magicmobile.android.ranked.SocialFixtures.openScreen == "queue") io.magicmobile.android.game.RankedMatchmaker.Phase.Searching(fixtureLaunch) else null,
        waitingFor = if (challengeWaiting) challengeTarget?.first else null,
        playWithFriends = playWithFriends, setPlayWithFriends = { playWithFriends = it },
        mayStart = mayStartSolo, status = if (setup.identity == null || setup.isBusy) setup.status else null,
        recent = io.magicmobile.android.game.ArenaPlayRules.recentGames(record.file.matches, setup.deckIDs),
        close = { playPanel = false }, newDeck = ::openDecks, explainBracket = { showBracketSheet = true },
        startQuick = ::startQuickMatch, findRanked = ::findRankedMatch,
        cancelSearch = { matchmaker.cancel() }, playAINow = { matchmaker.skipToAI() }, cancelChallenge = { challenges.cancelOutgoing() },
        openCustom = { playPanel = false; showSetup = true },
        rankedHall = { playPanel = false; lobby = "rankedHall" }, leaderboard = { playPanel = false; lobby = "leaderboard" },
        challengeFriend = { showFriends = true },
        hostOnline = { playWithFriends = true; playPanel = false; showSetup = true },
        joinOnline = { playWithFriends = true; playPanel = false; showSetup = true },
        chooseRecent = { game ->
            selectedDeckID = game.deckID
            playModeRaw = io.magicmobile.android.game.ArenaPlayMode.of(game.mode).raw
        })

    /** The custom table shows, or a table being left keeps its page (OnDeviceRootView.swift arenaMenu). */
    val setupShown = showSetup || (setup.needsLeave && activeMatch?.isPersonTable != true)

    fun setAISeats(ids: List<String>, count: Int) {
        aiPreconID = ids[0]; aiPrecon2ID = ids[1]; aiPrecon3ID = ids[2]; opponentCount = count
    }

    fun customTableModel() = CustomTableModel(
        setup = setup, deck = selectedDeck, deckID = selectedDeckID, deckBox = selectedDeckBox, bracket = selectedDeckBracket,
        playerName = playerDisplayName, setPlayerName = { playerDisplayName = it.take(24) }, validName = validName,
        online = playWithFriends, setOnline = { playWithFriends = it },
        aiPool = aiPool, aiIDs = aiIDs, aiSections = aiDeckPickerSections,
        selectAIDeck = { index, id -> when (index) { 0 -> aiPreconID = id; 1 -> aiPrecon2ID = id; else -> aiPrecon3ID = id } },
        opponentCount = opponentCount,
        // A seat comes back with the deck it last had; an empty one gets a precon.
        addSeat = {
            io.magicmobile.android.game.ArenaCustomTable.addSeat(aiIDs, opponentCount, aiPool.map { it.id }.toSet(),
                aiPool.filter { it.isPrecon }.map { it.id }, aiPreconID)?.let { (ids, count) -> setAISeats(ids, count) }
        },
        removeSeat = { index -> io.magicmobile.android.game.ArenaCustomTable.removeSeat(aiIDs, opponentCount, index)?.let { (ids, count) -> setAISeats(ids, count) } },
        aiSkill = aiSkill, setAISkill = { aiSkill = it }, startingMode = aiStartingPlayerMode, setStartingMode = { aiStartingPlayerMode = it },
        mayStart = mayStart, onlinePlayers = playerCount, setOnlinePlayers = { playerCount = it },
        back = { GameAudio.play(GameSound.UI_BACK); showSetup = false; openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.CUSTOM) },
        changeDeck = { showSetup = false; openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.CUSTOM) },
        explainBracket = { showBracketSheet = true },
        openStudio = { studioOpen = it; openDecks() },
        start = ::startAI, leave = { confirmLeave = true },
        hostOnline = {
            val deck = selectedDeck
            if (deck != null) scope.launch {
                val aiCount = onlineAICount(playerCount)
                setup.hostOnline(playerDisplayName, deck, playerCount, aiIDs.take(aiCount).mapNotNull { id -> aiPool.firstOrNull { it.id == id }?.deck }, aiSkill)
            }
        },
        joinOnline = { code -> selectedDeck?.let { setup.joinOnline(code, playerDisplayName, it) } },
        readyOnline = { selectedDeck?.let { setup.readyForMatch(playerDisplayName, it) } })

    // A search or a challenge waits in the Play panel (Arena's blade: Play turns into Cancel under a timer).
    LaunchedEffect(matchPhase != io.magicmobile.android.game.RankedMatchmaker.Phase.Idle) {
        if (matchPhase != io.magicmobile.android.game.RankedMatchmaker.Phase.Idle && !activeGame) playPanel = true
    }
    LaunchedEffect(challengeWaiting) { if (challengeWaiting) { playTabRaw = io.magicmobile.android.game.ArenaPlayTab.FRIENDS.raw; playPanel = true } }
    LaunchedEffect(activeGame) { if (activeGame) playPanel = false }
    BackHandler(enabled = !activeGame && playPanel && !showSetup) {
        if (matchPhase == io.magicmobile.android.game.RankedMatchmaker.Phase.Idle && !challengeWaiting) { GameAudio.play(GameSound.UI_BACK); playPanel = false }
    }
    BackHandler(enabled = !activeGame && !playPanel && !showSetup && lobby != null) {
        GameAudio.play(GameSound.UI_BACK)
        lobby = if (lobby == "leaderboard") "rankedHall" else null
    }

    MaterialTheme(colorScheme = darkColorScheme()) {
        CompositionLocalProvider(LocalBrandAmbientMotion provides !(showDecks || showAppearance || showUpdates || showDownloads || showHowToPlay || showGuidedWelcome
                || showFriends || showBracketSheet || showOfflineArtPrompt),
            LocalNativeTurnControl provides turnControl, LocalPlayerAccount provides vm.account) {
            Box(Modifier.fillMaxSize().background(BrandTheme.canvas)) {
                if (activeGame) {
                    CompositionLocalProvider(
                        LocalInspectorBattlefield provides (session.snapshot?.players?.flatMap { it.zones.battlefield } ?: emptyList()),
                        LocalGameRematchTitle provides when {
                            setup.usingMultiplayer -> null
                            activeMatch?.mode == io.magicmobile.android.game.PlayMode.QUICK -> "Play Again"
                            activeMatch?.mode == io.magicmobile.android.game.PlayMode.RANKED -> "Next Match"
                            else -> "Rematch"
                        },
                        io.magicmobile.android.board.LocalGameRankChange provides rankChange,
                        io.magicmobile.android.board.LocalGameRankNote provides rankNote,
                        LocalGameConcede provides GameConcedeHandler { concede() },
                        LocalFreezeReport provides { confirmFreezeReport = true },
                        LocalEmoteCenter provides vm.emotes,
                        // Messages from friends inside a game too: the game menu's Messages button.
                        io.magicmobile.android.social.LocalFriendMessages provides
                            if (vm.account.phase == io.magicmobile.android.social.PlayerAccount.Phase.READY && vm.account.username != null && vm.account.messagesAvailable)
                                io.magicmobile.android.social.FriendMessagesEntry(vm.account.unreadMessages) { messagesHub = "" } else null,
                        io.magicmobile.android.board.LocalBoardAnswerActions provides io.magicmobile.android.board.BoardAnswerActions(
                            session.supportedAnswerActions, session.rememberedAnswers, session.rememberedTriggerOrders,
                            { session.forgetRememberedAnswers() }, { session.forgetTriggerOrder() }),
                        LocalStartingRollVisible provides boardQuiet,
                        // The online turn timer's rings; solo games have no clock.
                        io.magicmobile.android.board.LocalTurnClock provides turnClockFeed) {
                        // Settings → Pass After Casting, sent with this seat's next answer when it changes.
                        val autoPassAfterCast by io.magicmobile.android.ui.AppPreferences.boolean(io.magicmobile.android.board.AutoPassAfterCast.KEY, true)
                        androidx.compose.runtime.LaunchedEffect(autoPassAfterCast) { session.setAutoPassAfterCast(autoPassAfterCast) }
                        // Settings → Smart Auto-Pass and its phase stops, from the next prompt.
                        val smartAutoPass by io.magicmobile.android.ui.AppPreferences.boolean(io.magicmobile.android.game.OnDeviceSmartPass.ENABLED_KEY, true)
                        val phaseStops by io.magicmobile.android.ui.AppPreferences.string(io.magicmobile.android.game.OnDeviceSmartPass.STOPS_KEY,
                            io.magicmobile.android.game.OnDeviceSmartPass.Settings.encode(io.magicmobile.android.game.OnDeviceSmartPass.defaultStops))
                        val stopForOwnSpells by io.magicmobile.android.ui.AppPreferences.boolean(io.magicmobile.android.game.OnDeviceSmartPass.STOP_FOR_OWN_SPELLS_KEY, false)
                        val stopForThreats by io.magicmobile.android.ui.AppPreferences.boolean(io.magicmobile.android.game.OnDeviceSmartPass.STOP_FOR_THREATS_KEY, true)
                        androidx.compose.runtime.LaunchedEffect(smartAutoPass, phaseStops, stopForOwnSpells, stopForThreats) {
                            session.setSmartPass(io.magicmobile.android.game.OnDeviceSmartPass.Settings(smartAutoPass,
                                io.magicmobile.android.game.OnDeviceSmartPass.Settings.decode(phaseStops), stopForOwnSpells, stopForThreats))
                        }
                        // Hidden from TalkBack while the starting roll covers it.
                        Box(Modifier.fillMaxSize().alpha(if (setup.isBusy) 0.999f else 1f)
                            .then(if (boardQuiet) Modifier.clearAndSetSemantics {} else Modifier)) {
                            NativeGameView(session.presentedSnapshot, selection, session.pendingActionID, session.pendingCardID,
                                CardChoiceCommandFailure.of(setup.errorMessage ?: session.errorMessage,
                                    if (setup.errorMessage != null) CardChoiceCommandFailure.Source.SETUP else CardChoiceCommandFailure.Source.SESSION),
                                setup.liveStatus, { setup.feedback = it },
                                runAction = { action ->
                                    if (action.type == "mulligan") GameAudio.play(GameSound.SHUFFLE)
                                    scope.launch { setup.perform { session.send(action) } }
                                },
                                runCommand = { command, label, id ->
                                    scope.launch {
                                        // A card plan answers XMage's next one-card prompt as soon as it lands.
                                        if (id.startsWith("card-plan-")) setup.waitUntilSessionIdle()
                                        setup.perform(reportingBusy = id.startsWith("card-plan-")) { session.send(command, label, id) }
                                    }
                                },
                                refreshGame = ::refresh, reconnectGame = ::refresh, checkBridgeHealth = { setup.localHealth() },
                                newGame = ::rematchOrLeave, quitGame = ::leaveFinishedOrAsk,
                                portraitModeEnabled = portraitModeEnabled, setPortraitModeEnabled = { portraitModeEnabled = it })
                            // Each snapshot may bring the guided game's next note, or retire the one on screen.
                            LaunchedEffect(session.snapshot, guidedGame) {
                                val snapshot = session.snapshot
                                if (!guidedGame || snapshot == null) return@LaunchedEffect
                                val step = GuidedGameCoach.advance(guidedTipID?.let(GuidedGameTip::fromId), snapshot,
                                    GuidedGameLaunch.shownTips(guidedShownTips))
                                step.newlyShown?.let { guidedShownTips = GuidedGameLaunch.remember(it, guidedShownTips) }
                                guidedTipID = step.current?.id
                                if (snapshot.isCompleted) guidedActive = false
                            }
                            // The combo loop shortcut: the offer, the repeats and their result.
                            if (!boardQuiet) ComboLoopOverlay(session)
                            // A friend's new message: a banner at the top for a few seconds; a tap opens the conversation.
                            androidx.compose.animation.AnimatedVisibility(messageBanner != null && !boardQuiet,
                                Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(horizontal = 16.dp).padding(top = 6.dp)) {
                                messageBanner?.let { (name, text) ->
                                    io.magicmobile.android.social.FriendMessageBanner(name, text, { messageBanner = null; messagesHub = name }, { messageBanner = null })
                                    LaunchedEffect(name, text) { delay(6_000); if (messageBanner == name to text) messageBanner = null }
                                }
                            }
                            val tip = guidedTipID?.let(GuidedGameTip::fromId)
                            androidx.compose.animation.AnimatedVisibility(guidedGame && tip != null && !boardQuiet,
                                Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 6.dp)) {
                                if (tip != null) GuidedGameCoachCard(tip, dismiss = { guidedTipID = null }, turnOff = ::endGuidedTips)
                            }
                        }
                    }
                } else {
                    // Every menu page under Arena's top bar, over the 3D tavern room (OnDeviceRootView.swift arenaMenu).
                    CompositionLocalProvider(io.magicmobile.android.menus.LocalArenaBoard provides true,
                        io.magicmobile.android.menus.LocalArenaMenuBackdrop provides true) {
                        BoxWithConstraints(Modifier.fillMaxSize()) {
                            val compact = maxWidth < maxHeight
                            io.magicmobile.android.menus.ArenaRoomBackdrop(if (showDecks) 0.62f else if (lobby == null && !setupShown) 0f else 0.55f)
                            // Only the room shows behind the Play panel, darkened.
                            // Deck Studio's editor covers the whole screen, top bar too (a fullScreenCover on iOS).
                            val studioCovered = showDecks && decksCovered
                            if (!playPanel) Box(Modifier.fillMaxSize().then(if (studioCovered) Modifier else Modifier.windowInsetsPadding(WindowInsets.statusBars)
                                .padding(top = io.magicmobile.android.menus.ArenaMenuStyle.barHeight))) {
                                // The Decks tab: Deck Studio under the top bar, as Arena's Decks page (DeckStudioRootView).
                                if (showDecks) io.magicmobile.android.studio.DeckStudioRootView(setup, selectedDeckID, { selectedDeckID = it },
                                    preparePlay = { showDecks = false; studioOpen = null; openPlayPanel() }, dismiss = { showDecks = false; studioOpen = null }, open = studioOpen,
                                    covered = { decksCovered = it })
                                // The custom table: Arena's event page under the top bar (OnDeviceRootView.swift setupContent).
                                else if (setupShown) CustomTablePage(customTableModel())
                                else when (lobby) {
                                    "rankedHall" -> io.magicmobile.android.ranked.RankedHallScreen(vm.account, record.file.rank,
                                        play = { openPlayPanel(io.magicmobile.android.game.ArenaPlayMode.RANKED) },
                                        leaderboard = { lobby = "leaderboard" }, profile = { lobby = "profile" }, back = { lobby = null })
                                    "leaderboard" -> io.magicmobile.android.ranked.RankedLeaderboardScreen(vm.account) { lobby = "rankedHall" }
                                    "profile" -> io.magicmobile.android.ranked.PlayerProfileScreen(record, vm.account, vm.account.username ?: playerDisplayName,
                                        setup.localDecks.mapNotNull { saved -> saved.deck.entries.firstOrNull { it.section == "commander" }?.name } + setup.aiPool.map { it.commander },
                                        loadMetadata = { runCatching { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { io.magicmobile.android.studio.NativeDeckMetadataCatalogue(setup.awaitCatalogue()) } }.getOrNull() }) { lobby = null }
                                    else -> io.magicmobile.android.menus.ArenaHomeView(homeContent(), compact)
                                }
                            }
                            androidx.compose.animation.AnimatedVisibility(playPanel,
                                enter = if (reduceMotion) fadeIn() else androidx.compose.animation.slideIn { full -> if (compact) androidx.compose.ui.unit.IntOffset(0, full.height) else androidx.compose.ui.unit.IntOffset(full.width, 0) } + fadeIn(),
                                exit = if (reduceMotion) fadeOut() else androidx.compose.animation.slideOut { full -> if (compact) androidx.compose.ui.unit.IntOffset(0, full.height) else androidx.compose.ui.unit.IntOffset(full.width, 0) } + fadeOut()) {
                                Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).padding(top = io.magicmobile.android.menus.ArenaMenuStyle.barHeight)) {
                                    io.magicmobile.android.menus.ArenaPlayPanel(playModel(), compact)
                                }
                            }
                            if (!studioCovered) io.magicmobile.android.menus.ArenaTopBar(menuTab, compact, ::selectMenuTab, settings = { showAppearance = true },
                                rank = record.file.rank.position, openRank = { selectMenuTab(io.magicmobile.android.game.ArenaMenuTab.RANKED) },
                                unread = vm.account.incomingCount + vm.account.unreadMessages > 0, messages = { showFriends = true },
                                updates = { showUpdates = true }, downloads = { showDownloads = true },
                                lit = io.magicmobile.android.game.ArenaTopBarLit.of(showAppearance, showUpdates, showDownloads, showFriends))
                        }
                    }
                }

                // The starting roll, on an opaque cover: a relay table's shared roll (the host's recorded dice,
                // played back on every phone) or its "Who goes first?" panel, or the AI table's local roll.
                // The roll follows the board: on the Arena board it rolls on the board (dimmed, no tavern table).
                val boardModeValue by io.magicmobile.android.ui.AppPreferences.string(io.magicmobile.android.game.BoardMode.key, io.magicmobile.android.game.BoardMode.defaultValue)
                androidx.compose.runtime.CompositionLocalProvider(io.magicmobile.android.menus.LocalArenaBoard provides
                    (io.magicmobile.android.game.BoardMode.resolved(boardModeValue) == io.magicmobile.android.game.BoardMode.ARENA)) {
                if (multiplayerRollVisible) {
                    val sharedRoll = table.startingRoll
                    StartingRollCover {
                        if (sharedRoll != null) {
                            MultiplayerD20View(sharedRoll, table.seatNames, sharedRoll.winnerSeatID == table.localSeatID, table.rollRevealedCount,
                                table.localSeatID, rollPending = table.hasRolled,
                                onRollTap = { runCatching { table.rollStartingPlayer() }.onFailure { bannerError = it.message } },
                                onStepPlayed = { runCatching { table.advanceAISeatIfNeeded() }.onFailure { bannerError = it.message } }) {
                                didDismissStartingRoll = true
                                submitStartingChoiceIfNeeded()
                            }
                        } else {
                            // Until the host shares the dice: the same leather and brass the roll itself wears.
                            Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing), contentAlignment = Alignment.Center) {
                                Column(Modifier.padding(horizontal = 16.dp).widthIn(max = 440.dp).fillMaxWidth()
                                    .shadow(10.dp, RoundedCornerShape(14.dp)).tavernBrassFrame(1f).padding(2.dp)
                                    .tavernFill(io.magicmobile.android.ui.TavernMaterial.LEATHER, RoundedCornerShape(14.dp)).padding(24.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                    Text("Who goes first?", color = Color(0.98f, 0.92f, 0.80f), style = sf(22f, SfWeight.heavy, SfDesign.SERIF), textAlign = TextAlign.Center)
                                    Text(table.rollStatus, color = Color(0.84f, 0.72f, 0.52f), style = sf(15f, SfWeight.medium, SfDesign.SERIF), textAlign = TextAlign.Center)
                                    Text(table.hostAISeatSummary ?: "Each player rolls a D20. Highest starts; ties reroll.", color = Color(0.84f, 0.72f, 0.52f),
                                        style = sf(12f, SfWeight.regular, SfDesign.SERIF), textAlign = TextAlign.Center)
                                    io.magicmobile.android.ui.TavernButton({ runCatching { table.rollStartingPlayer() }.onFailure { bannerError = it.message } },
                                        enabled = !table.hasRolled, fontSize = 17f, fullWidth = true) {
                                        io.magicmobile.android.ui.TavernButtonText(if (table.hasRolled) "Waiting for other players…" else "Roll D20")
                                    }
                                }
                            }
                        }
                    }
                } else if (aiRollVisible) {
                    StartingRollCover {
                        MultiplayerD20View(aiRoll, aiRollSeatNames, aiRoll.winnerSeatID == session.snapshot?.viewerID, aiRevealedRollCount,
                            session.snapshot?.viewerID, onRollTap = ::advanceLocalAIRoll, onStepPlayed = ::advanceAIRollIfNeeded) {
                            didDismissStartingRoll = true
                            submitStartingChoiceIfNeeded()
                        }
                    }
                }
                }

                // Recovery banner. On the starting roll's cover only a roll error shows, still readable and dismissible.
                // A session error stays up until updates resume or it is dismissed: polling has stopped, and a
                // board that only says "waiting" reads as frozen.
                val sessionError = session.errorMessage?.takeIf { activeGame && it != dismissedSessionError }
                val message = bannerError ?: sessionError
                if ((!startingRollVisible || bannerError != null) &&
                    (setup.isBusy || message != null || (activeGame && (session.snapshot == null || !setup.canUseSession)))) {
                    val bannerText = sf(15f, SfWeight.semibold, SfDesign.SERIF)
                    Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(horizontal = 12.dp).padding(bottom = 8.dp)
                        .glow(Color.Black.copy(alpha = 0.45f), 6.dp, 12.dp)
                        .tavernPanelChrome(true).padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (setup.isBusy) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = TavernPalette.parchment, strokeWidth = 2.dp)
                            Text(setup.status, color = TavernPalette.parchment, style = bannerText)
                        }
                        if (message != null) {
                            Row(verticalAlignment = Alignment.Top) {
                                Text(message, Modifier.weight(1f), color = TavernPalette.parchment, style = bannerText, maxLines = 3)
                                io.magicmobile.android.ui.TavernSealButton({ if (message == session.errorMessage) dismissedSessionError = message; bannerError = null },
                                    contentDescription = "Dismiss notification")
                            }
                        } else if (activeGame && !setup.canUseSession) {
                            Text(setup.liveStatus, color = TavernPalette.parchment, style = bannerText)
                        } else if (activeGame && session.snapshot == null) {
                            Text("Waiting for the first game update.", color = TavernPalette.parchment, style = bannerText)
                        }
                        if (activeGame) {
                            val enabled = !setup.isBusy && !session.isWorking
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                BannerButton("Refresh", io.magicmobile.android.ui.TavernButtonKind.PRIMARY, enabled && setup.canUseSession) { refresh() }
                                if (session.pendingActionID != null) BannerButton("Retry response", io.magicmobile.android.ui.TavernButtonKind.SECONDARY,
                                    enabled && setup.canUseSession) { scope.launch { setup.perform { session.retryPending() } } }
                                BannerButton(if (setup.closeFailed) "Retry closing" else "Leave", io.magicmobile.android.ui.TavernButtonKind.DANGER, enabled) {
                                    if (setup.closeFailed) closeGame() else confirmLeave = true
                                }
                            }
                        }
                    }
                }

                val invite = challengeIncoming.firstOrNull()
                if (menuIsFree && lobby == null && !challengeWaiting && activeMatch == null && invite != null) {
                    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 6.dp), contentAlignment = Alignment.TopCenter) {
                        io.magicmobile.android.ranked.ChallengeInviteBanner(invite, { acceptChallenge(invite) }, { scope.launch { challenges.decline(invite) } })
                    }
                }
                ceremony?.let { change -> io.magicmobile.android.ranked.RankCeremonyOverlay(change) { ceremony = null } }

                // The versus intro plays first, over the opaque starting roll that follows it.
                if (activeGame) versusIntro?.let { (you, opponents) ->
                    VersusIntroOverlay(you, opponents) { versusIntro = null }
                }

                // Save/resume: the launch prompt over the menu, and one-time notices.
                val resumeOffer = setup.resume.offer
                if (resumeOffer != null && !activeGame) {
                    ResumeGamePrompt(resumeOffer.detail, enabled = setup.identity != null && !setup.isBusy && !setup.needsLeave,
                        resume = ::resumeSavedGame, abandon = { setup.resume.abandon() })
                }
                setup.resume.notice?.let { notice ->
                    ResumeNoticeBanner(notice, Modifier.align(Alignment.TopCenter)) { setup.resume.notice = null }
                }
            }

            // Panels, not sheets: the menu's pages open as Arena's glass over the dimmed menu (ArenaPanels.kt).
            io.magicmobile.android.menus.ArenaPanel(showAppearance, { showAppearance = false; optionsStartPage = null }, maxWidth = 560.dp, fitsContent = true) {
                io.magicmobile.android.menus.ArenaOptionsView(portraitModeEnabled, { portraitModeEnabled = it }, setup.identity?.upstreamCommit, optionsStartPage)
            }
            io.magicmobile.android.menus.ArenaPanel(showUpdates, { showUpdates = false }, io.magicmobile.android.menus.ArenaPanelPlacement.TRAILING) {
                NativeUpdateNewsView(setup.identity?.upstreamCommit)
            }
            io.magicmobile.android.menus.ArenaPanel(showHowToPlay, ::closeHowToPlay, fitsContent = true) {
                // The first visit opens straight into the table's tutorial; the menu offers both.
                HowToPlayView(::closeHowToPlay, Modifier.fillMaxWidth().fillMaxHeight(), tutorialID = if (howToPlayOpensTable) HowToPlayText.tutorials[0].id else null,
                    playGuided = if (howToPlayOpensTable) null else ::startGuidedGame)
            }
            io.magicmobile.android.menus.ArenaPanel(showGuidedWelcome, ::answerGuidedWelcome, maxWidth = 560.dp, dismissable = false, fitsContent = true) {
                GuidedGameWelcomeView(playGuided = { answerGuidedWelcome(); startGuidedGame() },
                    readHowToPlay = {
                        answerGuidedWelcome()
                        scope.launch { delay(450); howToPlayOpensTable = true; showHowToPlay = true }
                    }, skip = ::answerGuidedWelcome, modifier = Modifier.fillMaxWidth())
            }
            if (showDownloads) LaunchedEffect(Unit) { setup.loadCatalogue() }
            io.magicmobile.android.menus.ArenaPanel(showDownloads, { showDownloads = false }, fitsContent = true) {
                val catalogueNames = setup.catalogue?.cards?.map { it.name }
                NativeDownloadsView(setup.localDecks.map { NativeDownloadDeck.of("local:${it.id}", it.deck) } +
                    precons.map { NativeDownloadDeck.of("precon:${it.id}", it.deck) }, selectedDeckID, setup.identity != null,
                    catalogueNames, setup.errorMessage?.takeIf { setup.catalogue == null }) { showDownloads = false }
            }
            if (activeGame && vm.emotes.isChatOpen) BoardSheet({ vm.emotes.openChat(false) }, skipPartiallyExpanded = true) {
                val profileReady = vm.account.phase == PlayerAccount.Phase.READY
                TableChatPanel(vm.emotes, session.snapshot,
                    report = if (profileReady) { line -> scope.launch { vm.account.report(line.name, line.text, "chat") } } else null,
                    block = if (profileReady) { name -> vm.emotes.mute(name); scope.launch { vm.account.block(name) } } else null,
                    viewProfile = if (profileReady) { name -> chatProfile = name } else null) { vm.emotes.openChat(false) }
                // A player opened from the table chat: their public profile covers the chat.
                chatProfile?.let { name ->
                    androidx.compose.ui.window.Dialog({ chatProfile = null }, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
                        io.magicmobile.android.ranked.PublicProfileScreen(vm.account, name, null, null) { chatProfile = null }
                    }
                }
            }
            io.magicmobile.android.menus.ArenaPanel(showBracketSheet, { showBracketSheet = false }, maxWidth = 560.dp, fitsContent = true) {
                val deck = selectedDeck; val report = selectedBracketReport
                if (deck != null && report != null) {
                    val fixed = setup.bracketDecks.firstOrNull { it.playerDeckID == selectedDeckID }?.bracket
                        ?: if (selectedDeckID.startsWith("precon:")) io.magicmobile.android.game.CommanderBracket.CORE else null
                    io.magicmobile.android.ranked.DeckBracketSheet(deck.name, report, run { bracketRevision; declaredBracket(selectedDeckID) }, fixed,
                        if (fixed == null) { b -> setDeclaredBracket(selectedDeckID, b) } else null) { showBracketSheet = false }
                }
            }
            messagesHub?.let { initial ->
                androidx.compose.ui.window.Dialog({ messagesHub = null }, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false,
                    decorFitsSystemWindows = false, dismissOnBackPress = false)) {
                    BackHandler { messagesHub = null }
                    io.magicmobile.android.social.FriendMessagesHub(vm.account, initial.ifEmpty { null }) { messagesHub = null }
                }
            }
            io.magicmobile.android.menus.ArenaPanel(showFriends, { showFriends = false }, io.magicmobile.android.menus.ArenaPanelPlacement.LEADING) {
                FriendsSheet(vm.account, join = { code -> scope.launch { delay(450); openJoinLink(code) } }, myRankStep = record.file.rank.position.step,
                    challenge = { friend, mode -> challengeFriend(friend.username, mode) }) { showFriends = false }
            }
            // An Arena question, not the system dialog (the menus have no Android dialogs).
            io.magicmobile.android.menus.ArenaPanel(showOfflineArtPrompt, { offlineArtPromptSeen = true; showOfflineArtPrompt = false }, maxWidth = 460.dp,
                fitsContent = true) {
                io.magicmobile.android.menus.ArenaPromptPanel("Play offline with card art?",
                    "Card art loads from Scryfall while you're online. Save your decks' images now so they show without a connection too.",
                    "Choose downloads", "Not now", "offlineArt") {
                    offlineArtPromptSeen = true; showOfflineArtPrompt = false
                    scope.launch { delay(350); showDownloads = true }
                }
            }
            // An Arena question on the main menu after a freeze in an earlier run; nothing is sent without Send.
            val freezeOffer = FreezeLog.launchOffer?.takeIf { it.id != freezeOfferClosed }
            io.magicmobile.android.menus.ArenaPanel(freezeOffer != null && menuIsFree && !showOfflineArtPrompt,
                { freezeOffer?.let { freezeOfferClosed = it.id; FreezeLog.decline(it) } }, maxWidth = 460.dp, fitsContent = true) {
                io.magicmobile.android.menus.ArenaPromptPanel("The last game froze. Send the report?",
                    "It holds the game's state and your recent actions, not your account or decks.", "Send", "Not now", "freezeReport") {
                    freezeOffer?.let { freezeOfferClosed = it.id; sendFreezeReport(it) }
                }
            }
            if (confirmFreezeReport) {
                io.magicmobile.android.ranked.ArenaConfirmation("Send a freeze report with this game's state?", null, "Send", destructive = false,
                    confirm = { sendFreezeReport(FreezeLog.record(io.magicmobile.android.game.FreezeRules.REPORTED, game = session.freezeContext())) }) {
                    confirmFreezeReport = false
                }
            }
            if (confirmLeave) {
                val message = when {
                    setup.multiplayer?.endpoint?.isHost == true -> "You are hosting. Leaving ends this match for everyone; it cannot be resumed."
                    else -> "This closes the current match. It cannot be resumed after leaving."
                }
                ConfirmationDialog("Leave this game?", message, listOf(ConfirmationAction("Leave game", destructive = true) { closeGame() })) { confirmLeave = false }
            }
        }
    }
}

@Composable
private fun BannerButton(title: String, kind: io.magicmobile.android.ui.TavernButtonKind, enabled: Boolean, action: () -> Unit) {
    io.magicmobile.android.ui.TavernButton(action, kind = kind, compact = true, enabled = enabled) { io.magicmobile.android.ui.TavernButtonText(title) }
}

private fun onlineAICount(humans: Int): Int = AppPreferences.int("magicmobile.relay.aiOpponentCount", 0).value.coerceIn(0, maxOf(0, 4 - humans))

/** The game being played from Quick Match or Ranked (or a custom table, for the profile), for its result. */
/** Development fixture (MAGICMOBILE_UI_TEST_OPEN=queue): when the Play panel's search began. */
private val fixtureLaunch = System.currentTimeMillis()

private data class ActiveMatch(
    val mode: io.magicmobile.android.game.PlayMode, val deckID: String, val deckName: String, val commander: String?, val colors: List<String>,
    val deckBracket: Int, val opponents: List<io.magicmobile.android.game.MatchOpponent>, val opponentBracket: Int?, val aiSkill: Int?,
    val aiDeckID: String?, val rankedMatchID: String? = null,
    /** A table for one particular person (a friend challenge): readied automatically, never shown to friends. */
    val privateTable: Boolean = false, val recorded: Boolean = false,
) {
    val isPersonTable: Boolean get() = rankedMatchID != null || privateTable
}
