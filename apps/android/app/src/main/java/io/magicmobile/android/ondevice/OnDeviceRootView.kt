package io.magicmobile.android.ondevice

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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewModelScope
import io.magicmobile.android.Artwork
import io.magicmobile.android.ArtworkDownloadsScreen
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.BoardAppearancePicker
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
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.board.NativeGameView
import io.magicmobile.android.board.NativeTurnControl
import io.magicmobile.android.board.PortraitModePreference
import io.magicmobile.android.board.PortraitModeToggle
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckTextImport
import io.magicmobile.android.game.CardChoiceCommandFailure
import io.magicmobile.android.game.EngineError
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

private val setupInk = BrandTheme.ink
private val setupSecondary = BrandTheme.inkSecondary
private val setupAccent = BrandTheme.ember

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
    var showDecks by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    var bannerError by remember { mutableStateOf<String?>(null) }
    var didDismissStartingRoll by remember { mutableStateOf(false) }
    var attemptedStartingPromptID by remember { mutableStateOf<String?>(null) }
    var aiStartingRoll by remember { mutableStateOf<OnDeviceStartingRoll?>(null) }
    var aiRevealedRollCount by remember { mutableIntStateOf(0) }
    var aiRollSeatNames by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var versusIntro by remember { mutableStateOf<Pair<VersusSeat, List<VersusSeat>>?>(null) }
    val selection = remember { BoardSelection() }

    val activeGame = session.matchID != null
    val precons = setup.precons
    val aiIDs = listOf(aiPreconID, aiPrecon2ID, aiPrecon3ID)
    val aiPrecons = aiIDs.take(opponentCount.coerceIn(1, 3)).mapNotNull { id -> precons.firstOrNull { it.id == id } }
    val selectedDeck: Deck? = setup.deck(selectedDeckID)
    val validName = runCatching { OnDeviceSetupModel.playerName(playerDisplayName) }.isSuccess
    val mayStart = validName && selectedDeck != null && (playWithFriends || aiPrecons.size == opponentCount) &&
        setup.identity != null && !setup.isBusy && !setup.needsLeave

    fun restoreSetupPreferences() {
        val deckIDs = setup.deckIDs
        if (deckIDs.isEmpty()) return
        selectedDeckID = OnDeviceSetupPreferences.normalizedDeckID(selectedDeckID, deckIDs)
        val available = precons.map { it.id }
        val ids = OnDeviceSetupPreferences.normalizedAIDeckIDs(listOf(aiPreconID, aiPrecon2ID, aiPrecon3ID), available)
        aiPreconID = ids[0]; aiPrecon2ID = ids[1]; aiPrecon3ID = ids[2]
        opponentCount = opponentCount.coerceIn(1, 3); playerCount = playerCount.coerceIn(2, 4); aiSkill = aiSkill.coerceIn(1, 10)
    }

    fun makeVersusIntro(): Pair<VersusSeat, List<VersusSeat>> {
        val name = playerDisplayName.trim()
        val you = VersusSeat("you", name.ifEmpty { "You" }, selectedDeck?.commanderName)
        session.snapshot?.let { snapshot ->
            val others = snapshot.players.filter { !snapshot.isViewer(it.playerId) }.take(3).map {
                VersusSeat(it.playerId, it.displayName ?: "Opponent", it.zones.command.firstOrNull()?.card?.name)
            }
            if (others.isNotEmpty()) return you to others
        }
        if (playWithFriends) return you to listOf(VersusSeat("friends", "Challengers", null))
        return you to aiPrecons.take(maxOf(1, opponentCount)).mapIndexed { index, deck -> VersusSeat("ai-$index", deck.name, deck.commander) }
    }

    fun closeGame() {
        scope.launch { if (setup.close()) { selection.selectedCard = null; selection.inspectedCard = null } }
    }

    fun requestLeave() { if (!setup.isBusy && !session.isWorking) confirmLeave = true }

    fun startAI() {
        val deck = selectedDeck ?: return
        if (aiPrecons.size != opponentCount) return
        val opponentDecks = aiPrecons.map { it.deck }
        scope.launch {
            try { playerDisplayName = OnDeviceSetupModel.playerName(playerDisplayName) }
            catch (error: EngineError) { setup.errorMessage = error.message; return@launch }
            setup.startAI(playerDisplayName, deck, opponentDecks, aiSkill)
        }
    }

    fun refresh() { scope.launch { setup.perform { session.refresh(); setup.updateSessionForeground() } } }

    fun rematchOrLeave() {
        if (session.snapshot?.isCompleted != true || setup.usingMultiplayer) return requestLeave()
        scope.launch {
            if (!setup.close()) return@launch
            selection.selectedCard = null; selection.inspectedCard = null
            startAI()
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
            try { session.concede() }
            catch (error: EngineError.Rejected) {
                if (error.code == "unknown_operation" || error.code == "concede_unavailable") { showSetup = false; closeGame() }
                else setup.errorMessage = error.message
            } catch (error: Throwable) { setup.errorMessage = error.message }
        }
    }

    fun submitStartingChoiceIfNeeded() {
        if (!didDismissStartingRoll || setup.isBusy || session.isWorking || !setup.canUseSession) return
        val snapshot = session.snapshot ?: return
        val promptID = snapshot.promptEnvelopeV2?.id ?: return
        if (attemptedStartingPromptID == promptID) return
        val table = setup.multiplayer as? RelayTable
        val winnerName: String
        val command = if (setup.usingMultiplayer && table != null) {
            val roll = table.startingRoll ?: return
            winnerName = table.seatNames[roll.winnerSeatID] ?: return
            OnDeviceStartingPlayerChoice.commandForName(snapshot, winnerName)
        } else {
            val roll = aiStartingRoll ?: return
            if (aiStartingPlayerMode != "roll") return
            winnerName = aiRollSeatNames[roll.winnerSeatID] ?: "winner"
            OnDeviceStartingPlayerChoice.command(snapshot, winnerPlayerID = roll.winnerSeatID)
        } ?: return
        attemptedStartingPromptID = promptID
        scope.launch { setup.perform { session.send(command, "Start with $winnerName", "starting-roll-$promptID") } }
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
        if (setup.usingMultiplayer || aiStartingPlayerMode != "roll" || session.matchID == null || aiStartingRoll != null || didDismissStartingRoll) return
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
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> { setup.setSceneActive(true); GameAudio.resume() }
                Lifecycle.Event.ON_PAUSE -> setup.setSceneActive(false)
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(portraitModeEnabled, activeGame) { OrientationController.apply(activity, portraitModeEnabled, activeGame) }
    LaunchedEffect(activeGame) {
        GameAudio.setScene(if (activeGame) GameMusic.GAME else GameMusic.MENU)
        if (!activeGame) { versusIntro = null; return@LaunchedEffect }
        if (reduceMotion) GameAudio.play(GameSound.VERSUS, after = 0.2)
        else { versusIntro = makeVersusIntro(); GameAudio.play(GameSound.VERSUS, after = 0.05) }
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
        didDismissStartingRoll = false; attemptedStartingPromptID = null; aiStartingRoll = null; aiRevealedRollCount = 0; aiRollSeatNames = emptyMap()
        prepareAIRollIfNeeded()
    }
    val table = setup.multiplayer as? RelayTable
    LaunchedEffect(table?.endpoint?.matchID) { if (table?.endpoint != null) setup.attachTable(table) }
    LaunchedEffect(table?.isConnected, table?.isSuspended) { setup.updateSessionForeground() }
    // Relay tables carry quick chat between phones; solo games only answer from the AI.
    LaunchedEffect(session.snapshot?.id, table) {
        vm.emotes.reset()
        vm.emotes.send = table?.let { current -> { emote -> current.sendEmote(emote) } }
        table?.onEmote = { name, emote -> vm.emotes.receive(emote, name, session.snapshot) }
    }

    // Deck Studio handles Back itself while it is open.
    BackHandler(enabled = !activeGame && showSetup && !showDecks) {
        GameAudio.play(GameSound.UI_BACK)
        if (!setup.isBusy && !setup.needsLeave) showSetup = false
    }
    BackHandler(enabled = activeGame) { requestLeave() }

    val turnControl = NativeTurnControl(session.canEndTurn, session.canEndTurnSkippingResponses, session.canSkipToMyTurn, session.isAutoPassing,
        session.autoPassStatus, { session.endTurn() }, { session.endTurnSkippingResponses() }, { session.skipToMyTurn() }, { session.stopAutoPass() })

    MaterialTheme(colorScheme = darkColorScheme()) {
        CompositionLocalProvider(LocalBrandAmbientMotion provides !(showDecks || showAppearance || showUpdates || showDownloads),
            LocalNativeTurnControl provides turnControl) {
            Box(Modifier.fillMaxSize().background(BrandTheme.canvas)) {
                if (activeGame) {
                    CompositionLocalProvider(
                        LocalInspectorBattlefield provides (session.snapshot?.players?.flatMap { it.zones.battlefield } ?: emptyList()),
                        LocalGameRematchTitle provides if (setup.usingMultiplayer) null else "Rematch",
                        LocalGameConcede provides GameConcedeHandler { concede() },
                        LocalEmoteCenter provides vm.emotes) {
                        Box(Modifier.fillMaxSize().alpha(if (setup.isBusy) 0.999f else 1f)) {
                            NativeGameView(session.snapshot, selection, session.pendingActionID, session.pendingCardID,
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
                        }
                    }
                    versusIntro?.let { (you, opponents) ->
                        VersusIntroOverlay(you, opponents) { versusIntro = null }
                    }
                } else if (showSetup || setup.needsLeave) {
                    SetupScreen(setup, selectedDeck, aiPrecons, playerDisplayName, { playerDisplayName = it.take(24) }, portraitModeEnabled,
                        { portraitModeEnabled = it }, selectedDeckID, { selectedDeckID = it }, aiIDs, { index, id ->
                            when (index) { 0 -> aiPreconID = id; 1 -> aiPrecon2ID = id; else -> aiPrecon3ID = id }
                        }, opponentCount, { opponentCount = it }, aiSkill, { aiSkill = it }, aiStartingPlayerMode, { aiStartingPlayerMode = it },
                        playWithFriends, { playWithFriends = it }, mayStart,
                        onlinePlayers = playerCount, setOnlinePlayers = { playerCount = it },
                        hostOnline = {
                            val deck = selectedDeck
                            if (deck != null) scope.launch {
                                val aiCount = onlineAICount(playerCount)
                                setup.hostOnline(playerDisplayName, deck, playerCount, aiIDs.take(aiCount).mapNotNull { id -> precons.firstOrNull { it.id == id }?.deck }, aiSkill)
                            }
                        },
                        joinOnline = { code -> selectedDeck?.let { setup.joinOnline(code, playerDisplayName, it) } },
                        readyOnline = { selectedDeck?.let { setup.readyForMatch(playerDisplayName, it) } },
                        back = { GameAudio.play(GameSound.UI_BACK); showSetup = false },
                        openSettings = { GameAudio.play(GameSound.UI_OPEN); showAppearance = true },
                        openDecks = { showDecks = true }, start = ::startAI, leave = { confirmLeave = true })
                } else {
                    TavernMainMenu(selectedDeck?.name ?: "Choose a deck", playerDisplayName, play = { showSetup = true },
                        decks = { showDecks = true }, settings = { showAppearance = true }, news = { showUpdates = true },
                        commanderName = selectedDeck?.commanderName, downloads = { showDownloads = true })
                }

                // Recovery banner
                if (setup.isBusy || bannerError != null || (activeGame && (session.snapshot == null || !setup.canUseSession))) {
                    Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(horizontal = 12.dp).padding(bottom = 8.dp)
                        .magicPanel(MagicPanelMaterial.IRON, MagicPanelProminence.ELEVATED, cornerRadius = 12.dp, padding = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (setup.isBusy) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = MagicPalette.parchment, strokeWidth = 2.dp)
                            Text(setup.status, color = MagicPalette.parchment, style = SfText.body())
                        }
                        val message = bannerError
                        if (message != null) {
                            Row(verticalAlignment = Alignment.Top) {
                                Text(message, Modifier.weight(1f), color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold), maxLines = 3)
                                Box(Modifier.size(44.dp).clickable { bannerError = null }.semantics { contentDescription = "Dismiss notification" },
                                    contentAlignment = Alignment.Center) { SfImage("xmark", MagicPalette.parchment, 14.dp) }
                            }
                        } else if (activeGame && !setup.canUseSession) {
                            Text(setup.liveStatus, color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold))
                        } else if (activeGame && session.snapshot == null) {
                            Text("Waiting for the first game update.", color = MagicPalette.parchment, style = SfText.caption(SfWeight.semibold))
                        }
                        if (activeGame) {
                            val enabled = !setup.isBusy && !session.isWorking
                            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.alpha(if (enabled) 1f else 0.45f)) {
                                BannerButton("Refresh", enabled && setup.canUseSession) { refresh() }
                                if (session.pendingActionID != null) BannerButton("Retry response", enabled && setup.canUseSession) {
                                    scope.launch { setup.perform { session.retryPending() } }
                                }
                                BannerButton(if (setup.closeFailed) "Retry closing" else "Leave", enabled) { if (setup.closeFailed) closeGame() else confirmLeave = true }
                            }
                        }
                    }
                }

                // A relay table's starting roll: the host's recorded dice, played back on every phone.
                if (setup.usingMultiplayer && table != null && table.endpoint != null && table.isConnected && !didDismissStartingRoll) {
                    val sharedRoll = table.startingRoll
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (sharedRoll == null) 0.82f else 0.58f))
                        .windowInsetsPadding(WindowInsets.safeDrawing), contentAlignment = Alignment.Center) {
                        if (sharedRoll != null) {
                            MultiplayerD20View(sharedRoll, table.seatNames, sharedRoll.winnerSeatID == table.localSeatID, table.rollRevealedCount,
                                table.localSeatID, rollPending = table.hasRolled,
                                onRollTap = { runCatching { table.rollStartingPlayer() }.onFailure { bannerError = it.message } },
                                onStepPlayed = { runCatching { table.advanceAISeatIfNeeded() }.onFailure { bannerError = it.message } }) {
                                didDismissStartingRoll = true
                                submitStartingChoiceIfNeeded()
                            }
                        }
                    }
                }

                // The AI table's starting roll
                val roll = aiStartingRoll
                if (!setup.usingMultiplayer && session.matchID != null && aiStartingPlayerMode == "roll" && roll != null && !didDismissStartingRoll) {
                    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.58f)).windowInsetsPadding(WindowInsets.safeDrawing)) {
                        MultiplayerD20View(roll, aiRollSeatNames, roll.winnerSeatID == session.snapshot?.viewerID, aiRevealedRollCount,
                            session.snapshot?.viewerID, onRollTap = ::advanceLocalAIRoll, onStepPlayed = ::advanceAIRollIfNeeded) {
                            didDismissStartingRoll = true
                            submitStartingChoiceIfNeeded()
                        }
                    }
                }
            }

            if (showAppearance) BoardSheet({ showAppearance = false }) {
                AppearanceSettings(portraitModeEnabled, { portraitModeEnabled = it }, inGame = activeGame) { showAppearance = false }
            }
            if (showUpdates) BoardSheet({ showUpdates = false }) { UpdatesSheet(setup.identity?.upstreamCommit) { showUpdates = false } }
            // DeckStudioRootView, full screen over the menu (fullScreenCover on iOS).
            io.magicmobile.android.studio.StudioCover(showDecks) {
                io.magicmobile.android.studio.DeckStudioRootView(setup, selectedDeckID, { selectedDeckID = it },
                    preparePlay = { showSetup = true }, dismiss = { showDecks = false })
            }
            if (showDownloads) {
                LaunchedEffect(Unit) { setup.loadCatalogue() }
                val catalogueNames = setup.catalogue?.cards?.map { it.name }
                BoardSheet({ showDownloads = false }, skipPartiallyExpanded = true) {
                    NativeDownloadsView(setup.localDecks.map { NativeDownloadDeck.of("local:${it.id}", it.deck) } +
                        precons.map { NativeDownloadDeck.of("precon:${it.id}", it.deck) }, selectedDeckID, setup.identity != null,
                        catalogueNames, setup.errorMessage?.takeIf { setup.catalogue == null }) { showDownloads = false }
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
private fun BannerButton(title: String, enabled: Boolean, action: () -> Unit) {
    Text(title, Modifier.heightIn(min = 44.dp).wrapContentSize(Alignment.CenterStart).clickable(enabled = enabled, onClick = action),
        color = if (enabled) BrandTheme.ember else BrandTheme.ember.copy(alpha = 0.45f), style = SfText.body())
}

/** Port of TavernMainMenu (ContentView.swift). */
@Composable
fun TavernMainMenu(deckName: String, playerName: String, play: () -> Unit, decks: () -> Unit, settings: () -> Unit, news: (() -> Unit)? = null,
                   commanderName: String? = null, downloads: (() -> Unit)? = null) {
    val reduceMotion = LaunchEnvironment.reduceMotion
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val alpha by animateFloatAsState(if (appeared) 1f else 0f, tween(if (reduceMotion) 0 else 450), label = "menuAppear")
    val offset by animateFloatAsState(if (appeared || reduceMotion) 0f else 14f, tween(if (reduceMotion) 0 else 450), label = "menuOffset")
    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize())
        BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            val horizontal = maxWidth > maxHeight
            val cardWidth = if (horizontal) minOf(150.dp, maxHeight * 0.36f) else minOf(168.dp, maxWidth * 0.41f, maxHeight * 0.2f)
            val height = maxHeight
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                val content: @Composable () -> Unit = {
                    Column(Modifier.widthIn(max = 400.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (!horizontal) MenuIdentity(compact = false, playerName)
                        HeroCommanderCard(commanderName, cardWidth)
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.semantics { contentDescription = commanderName?.let { "Your deck: $deckName, commander $it" } ?: "Your deck: $deckName" }) {
                            Text("YOUR DECK", color = BrandTheme.ember, style = sf(11f, SfWeight.heavy, tracking = 2.4f))
                            Text(deckName, color = BrandTheme.ink, style = sf(22f, SfWeight.heavy).copy(shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(alpha = 0.7f),
                                androidx.compose.ui.geometry.Offset(0f, 1f), 2f)), textAlign = TextAlign.Center)
                            if (!commanderName.isNullOrEmpty()) Text(commanderName, color = BrandTheme.inkSecondary, style = SfText.footnote(), textAlign = TextAlign.Center)
                        }
                    }
                    Column(Modifier.widthIn(max = 400.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        if (horizontal) Box(Modifier.padding(bottom = 8.dp)) { MenuIdentity(compact = true, playerName) }
                        BrandButton({ GameAudio.play(GameSound.MENU_PLAY); play() }, Modifier.semantics { contentDescription = "Play Commander" }) {
                            SfImage("flame.fill", BrandTheme.emberInk, 19.dp)
                            Text("Play Commander", Modifier.weight(1f).padding(start = 4.dp), color = BrandTheme.emberInk, style = sf(19f, SfWeight.heavy))
                            SfImage("chevron.right", BrandTheme.emberInk, 15.dp)
                        }
                        BrandButton({ GameAudio.play(GameSound.UI_OPEN); decks() }, Modifier.semantics { contentDescription = "Decks" }, kind = BrandButtonKind.SECONDARY) {
                            SfImage("rectangle.stack.fill", BrandTheme.ink, 17.dp)
                            Text("Decks", Modifier.weight(1f).padding(start = 4.dp), color = BrandTheme.ink, style = sf(17f, SfWeight.bold))
                            SfImage("chevron.right", BrandTheme.ink, 14.dp)
                        }
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterHorizontally)) {
                            BrandIconButton("Settings", "gearshape.fill", { GameAudio.play(GameSound.UI_OPEN); settings() })
                            news?.let { BrandIconButton("Updates", "scroll.fill", { GameAudio.play(GameSound.PAGE_FLIP); it() }) }
                            downloads?.let { BrandIconButton("Downloads", "arrow.down.to.line.circle.fill", { GameAudio.play(GameSound.UI_OPEN); it() }) }
                        }
                    }
                }
                Box(Modifier.fillMaxWidth().heightIn(min = height).alpha(alpha).offset(y = offset.dp)
                    .padding(horizontal = if (horizontal) 36.dp else 26.dp, vertical = if (horizontal) 16.dp else 12.dp), contentAlignment = Alignment.Center) {
                    if (horizontal) Row(horizontalArrangement = Arrangement.spacedBy(44.dp), verticalAlignment = Alignment.CenterVertically) { content() }
                    else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) { content() }
                }
            }
        }
    }
}

@Composable
private fun MenuIdentity(compact: Boolean, playerName: String) {
    Column(horizontalAlignment = if (compact) Alignment.Start else Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BrandMark(if (compact) 52.dp else 64.dp)
        Text("MAGICMOBILE", color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.heavy, tracking = 3f))
        BrandTitle("Your next\ngreat game.", if (compact) 32f else 36f, textAlign = if (compact) TextAlign.Start else TextAlign.Center)
        if (playerName.isNotBlank()) Text("Welcome back, ${playerName.trim()}", color = BrandTheme.inkSecondary, style = SfText.subheadline(),
            textAlign = if (compact) TextAlign.Start else TextAlign.Center)
    }
}

/** The setup screen (OnDeviceRootView.setupContent). */
@Composable
private fun SetupScreen(setup: OnDeviceSetupModel, selectedDeck: Deck?, aiPrecons: List<PreconDeck>, playerName: String, setPlayerName: (String) -> Unit,
                        portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit, selectedDeckID: String, selectDeck: (String) -> Unit,
                        aiIDs: List<String>, selectAIDeck: (Int, String) -> Unit, opponentCount: Int, setOpponentCount: (Int) -> Unit,
                        aiSkill: Int, setAISkill: (Int) -> Unit, startingMode: String, setStartingMode: (String) -> Unit,
                        playWithFriends: Boolean, setPlayWithFriends: (Boolean) -> Unit, mayStart: Boolean,
                        onlinePlayers: Int, setOnlinePlayers: (Int) -> Unit, hostOnline: () -> Unit, joinOnline: (String) -> Unit,
                        readyOnline: () -> Unit,
                        back: () -> Unit, openSettings: () -> Unit, openDecks: () -> Unit, start: () -> Unit, leave: () -> Unit) {
    // In a match room, the deck and name stay editable until the player taps Ready.
    val editableInRoom = (setup.multiplayer as? RelayTable)?.room?.let { !it.localReady } ?: false
    val seatLocked = setup.isBusy || (setup.needsLeave && !editableInRoom)
    val locked = setup.isBusy || setup.needsLeave
    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.safeDrawing),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Row(Modifier.heightIn(min = 44.dp).clickable(enabled = !locked, onClick = back).alpha(if (locked) 0.45f else 1f),
                        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("chevron.left", setupAccent, 17.dp)
                        Text("Main menu", color = setupAccent, style = SfText.body(SfWeight.semibold))
                    }
                    Spacer(Modifier.weight(1f))
                    Box(Modifier.size(44.dp).clickable(onClick = openSettings).semantics { contentDescription = "Settings" }, contentAlignment = Alignment.Center) {
                        SfImage("gearshape.fill", setupAccent, 17.dp)
                    }
                }
                BrandTitle("Your next game.", 34f)
                Text("Choose your deck. Take your seat.", color = setupSecondary, style = SfText.subheadline())
                // The two sides of the table.
                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.Top) {
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            CommanderDeckPortrait(selectedDeck?.commanderName, Modifier.size(112.dp, 156.dp))
                            Text("Your deck", color = setupSecondary, style = SfText.caption())
                            Text(selectedDeck?.name ?: "Choose a deck", color = setupInk, style = SfText.headline(), textAlign = TextAlign.Center)
                        }
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (playWithFriends) {
                                Box(Modifier.size(112.dp, 156.dp).background(BrandTheme.surface, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                                    SfImage("person.2.fill", setupSecondary, 34.dp)
                                }
                                Text("iPhone + Android", color = setupSecondary, style = SfText.caption())
                                Text("${(setup.multiplayer as? RelayTable)?.seatsWanted?.takeIf { it > 0 } ?: 2} seats", color = setupInk, style = SfText.headline())
                            } else {
                                CommanderDeckPortrait(aiPrecons.firstOrNull()?.commander, Modifier.size(112.dp, 156.dp))
                                Text("$opponentCount AI ${if (opponentCount == 1) "opponent" else "opponents"}", color = setupSecondary, style = SfText.caption())
                                Text(if (opponentCount == 1) aiPrecons.firstOrNull()?.name ?: "Choose opponents" else "Choose each deck below",
                                    color = setupInk, style = SfText.headline(), textAlign = TextAlign.Center)
                            }
                        }
                    }
                    VersusMedallion(50.dp, Modifier.align(Alignment.TopCenter).padding(top = (156 / 2 - 25).dp))
                }
                // Your seat
                Column(Modifier.fillMaxWidth().brandPanel(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    BrandDivider(Modifier.fillMaxWidth(), title = "Your seat")
                    IosTextField(playerName, setPlayerName, "Player name", Modifier.semantics { contentDescription = "Player name" }, enabled = !seatLocked)
                    Text("Choose a name with 1–24 characters.", color = setupSecondary, style = SfText.caption())
                    IosToggle(portraitModeEnabled, setPortraitModeEnabled, tint = setupAccent) {
                        Text("Auto-Rotate", color = setupInk, style = SfText.subheadline())
                    }
                    val deckTitle = setup.deck(selectedDeckID)?.name ?: "Choose a deck"
                    IosMenuPicker(deckTitle, {
                        buildList {
                            add(MenuEntry.Section("Included precons"))
                            setup.precons.forEach { precon -> add(MenuEntry.Item(precon.name, checked = selectedDeckID == "precon:${precon.id}") { selectDeck("precon:${precon.id}") }) }
                            if (setup.localDecks.isNotEmpty()) {
                                add(MenuEntry.Section("Saved on this device"))
                                setup.localDecks.forEach { saved -> add(MenuEntry.Item(saved.deck.name, checked = selectedDeckID == "local:${saved.id}") { selectDeck("local:${saved.id}") }) }
                            }
                        }
                    }, enabled = !seatLocked, label = "Your deck")
                    BrandButton(openDecks, kind = BrandButtonKind.SECONDARY, enabled = !seatLocked) {
                        SfImage("rectangle.stack.badge.plus", BrandTheme.ink, 17.dp)
                        BrandButtonText("Browse, import or edit decks", BrandButtonKind.SECONDARY)
                    }
                    ArtworkPreferenceToggle()
                }
                // Players
                Column(Modifier.fillMaxWidth().brandPanel(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    IosSegmented(listOf("ai", "online"), if (playWithFriends) "online" else "ai", { mode -> if (!locked) setPlayWithFriends(mode == "online") },
                        { if (it == "ai") "AI" else "Online" })
                    if (playWithFriends) {
                        OnlineTablePanel(setup, selectedDeck, onlinePlayers, setOnlinePlayers, aiIDs, selectAIDeck, aiSkill, setAISkill,
                            mayHost = selectedDeck != null && runCatching { OnDeviceSetupModel.playerName(playerName) }.isSuccess &&
                                setup.identity != null && !setup.isBusy && !setup.needsLeave,
                            hostOnline, joinOnline, readyOnline)
                    } else {
                        IosStepper("AI opponents: $opponentCount", opponentCount, 1..3, setOpponentCount, enabled = !locked, color = setupInk)
                        for (index in 0 until opponentCount.coerceIn(1, 3)) {
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("AI ${index + 1} deck", color = setupSecondary, style = SfText.caption())
                                IosMenuPicker(setup.precons.firstOrNull { it.id == aiIDs[index] }?.name ?: "Choose a deck", {
                                    setup.precons.map { precon -> MenuEntry.Item(precon.name, checked = precon.id == aiIDs[index]) { selectAIDeck(index, precon.id) } }
                                }, enabled = !locked, label = "AI ${index + 1} deck")
                            }
                        }
                        IosStepper("AI skill: $aiSkill", aiSkill, 1..10, setAISkill, enabled = !locked, color = setupInk)
                        Text("Higher skill levels allow more thinking and may slow turns.", color = setupSecondary, style = SfText.caption())
                        IosSegmented(listOf("choose", "roll"), startingMode, { if (!locked) setStartingMode(it) }, { if (it == "roll") "Roll D20" else "Choose" })
                        Text(if (startingMode == "roll") "Everyone rolls a D20. The highest roll starts; ties reroll." else "Choose the starting player when the match begins.",
                            color = setupSecondary, style = SfText.caption())
                        BrandButton(start, Modifier.semantics { contentDescription = "Start game" }, enabled = mayStart) { BrandButtonText("Start game") }
                    }
                }
                Text(setup.status, color = setupSecondary, style = SfText.caption())
                if (setup.needsLeave) BrandButton(leave, kind = BrandButtonKind.SECONDARY, enabled = !setup.isBusy && !setup.session.isWorking) {
                    Text("Leave / retry closing", color = Color(1f, 0.27f, 0.23f), style = sf(17f, SfWeight.bold))
                }
                if (setup.identity == null) BrandButton({ setup.prepare() }, kind = BrandButtonKind.SECONDARY) { BrandButtonText("Retry loading local catalogue", BrandButtonKind.SECONDARY) }
                OnDeviceDiagnosticsEntry(setup)
                if (!BuildConfig.NATIVE_ENGINE) Text("This build has no native engine. Install the full APK to play.", color = Color(1f, 0.6f, 0.3f), style = SfText.caption(SfWeight.semibold))
            }
        }
    }
}

/** NativeArtworkPreferenceView: consent for live Scryfall images. */
@Composable
private fun ArtworkPreferenceToggle() {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(Artwork.enabled(context)) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        IosToggle(enabled, { value -> enabled = value; Artwork.setEnabled(context, value) }, tint = setupAccent) {
            Text("Scryfall live images", color = setupInk, style = SfText.body())
        }
        Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.", color = setupSecondary, style = SfText.caption())
        Text("Scryfall receives card names—including your hand—and your IP address.", color = setupSecondary, style = SfText.caption())
    }
}

/** AppearanceSettingsView (ContentView.swift). */
@Composable
private fun AppearanceSettings(portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit, inGame: Boolean, done: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(io.magicmobile.android.ui.rgb(0.08, 0.07, 0.065))) {
        IosSheetHeader("Settings", done)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            if (inGame) ArtworkPreferenceToggle()
            BoardAppearancePicker()
            PortraitModeToggle(portraitModeEnabled, setPortraitModeEnabled)
            FollowTurnsToggle()
            BoardEffectsPicker()
        }
    }
}

/** NativeUpdateNewsView.swift. */
@Composable
private fun UpdatesSheet(upstreamCommit: String?, done: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
    Column(Modifier.fillMaxWidth()) {
        IosSheetHeader("Updates", done)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            IosListSection("Installed build") {
                IosListRow("MagicMobile", value = "${BuildConfig.VERSION_NAME} (${BuildConfig.RELEASE_BUILD})")
                upstreamCommit?.let { IosListRow("XMage revision", value = it.take(12), monospacedValue = true) }
            }
            IosListSection("What's new") {
                IosListRow("Edge-to-edge menus and cleaner deck covers.", systemImage = "rectangle.stack")
                IosListRow("Compact card rows and clearer combo steps.", systemImage = "list.number")
                IosListRow("Six battlefield backgrounds for both orientations.", systemImage = "photo.on.rectangle")
                IosListRow("Quieter error notices that dismiss automatically.", systemImage = "bell")
                IosListRow("Offline artwork with three quality options.", systemImage = "externaldrive")
            }
            IosListSection("XMage news", footer = "Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.") {
                IosListRow("XMage release notes", systemImage = "arrow.up.right.square") { open("https://github.com/magefree/mage/releases") }
                IosListRow("Latest upstream changes", systemImage = "arrow.up.right.square") { open("https://github.com/magefree/mage/commits/master/") }
            }
        }
    }
}

private fun onlineAICount(humans: Int): Int = AppPreferences.int("magicmobile.relay.aiOpponentCount", 0).value.coerceIn(0, maxOf(0, 4 - humans))

/** Host or join a cross-play table, then the match room (OnDeviceRootView's Game Center section, over the relay). */
@Composable
private fun OnlineTablePanel(setup: OnDeviceSetupModel, selectedDeck: Deck?, players: Int, setPlayers: (Int) -> Unit, aiIDs: List<String>,
                             selectAIDeck: (Int, String) -> Unit, aiSkill: Int, setAISkill: (Int) -> Unit, mayHost: Boolean,
                             host: () -> Unit, join: (String) -> Unit, ready: () -> Unit) {
    val context = LocalContext.current
    val table = setup.multiplayer as? RelayTable
    var storedAICount by AppPreferences.int("magicmobile.relay.aiOpponentCount", 0)
    val aiCount = storedAICount.coerceIn(0, maxOf(0, 4 - players))
    var code by remember { mutableStateOf("") }
    val locked = setup.isBusy || setup.needsLeave
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (table == null) {
            IosMenuPicker("$players players", { (2..4).map { count -> MenuEntry.Item("$count players", checked = count == players) { setPlayers(count) } } },
                enabled = !locked, label = "Human players")
            IosStepper("AI opponents: $aiCount", aiCount, 0..maxOf(0, 4 - players), { storedAICount = it }, enabled = !locked, color = setupInk)
            for (index in 0 until aiCount) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("AI ${index + 1} deck", color = setupSecondary, style = SfText.caption())
                    IosMenuPicker(setup.precons.firstOrNull { it.id == aiIDs[index] }?.name ?: "Choose a deck", {
                        setup.precons.map { precon -> MenuEntry.Item(precon.name, checked = precon.id == aiIDs[index]) { selectAIDeck(index, precon.id) } }
                    }, enabled = !locked, label = "AI ${index + 1} deck")
                }
            }
            if (aiCount > 0) {
                IosStepper("AI skill: $aiSkill", aiSkill, 1..10, setAISkill, enabled = !locked, color = setupInk)
                Text("The host’s AI choices apply to everyone. Higher skill may slow turns.", color = setupSecondary, style = SfText.caption())
            }
            Text("iPhone and Android players join with the table code. Every player needs this app version and keeps it open during the match.",
                color = setupSecondary, style = SfText.caption())
            BrandButton(host, Modifier.semantics { contentDescription = "Host a table" }, enabled = mayHost) { BrandButtonText("Host a table") }
            BrandDivider(Modifier.fillMaxWidth(), title = "or join")
            IosTextField(code, { value -> code = value.uppercase().filter { it in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" }.take(6) }, "Table code",
                Modifier.semantics { contentDescription = "Table code" }, enabled = !locked)
            BrandButton({ join(code) }, kind = BrandButtonKind.SECONDARY, enabled = mayHost && code.length == 6) {
                BrandButtonText("Join table", BrandButtonKind.SECONDARY)
            }
        } else {
            table.tableCode?.let { tableCode ->
                Column(Modifier.fillMaxWidth().background(BrandTheme.canvas.copy(alpha = 0.6f), RoundedCornerShape(12.dp)).padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("TABLE CODE", color = setupSecondary, style = sf(12f, SfWeight.bold, tracking = 1.4f))
                    Text(tableCode.chunked(3).joinToString(" "), Modifier.semantics { contentDescription = "Table code $tableCode" },
                        color = setupInk, style = sf(34f, SfWeight.black, io.magicmobile.android.ui.SfDesign.MONOSPACED, tracking = 2f))
                    if (table.room == null && table.endpoint == null && !table.isFailed) {
                        Text("Players ${table.seatsTaken}/${table.seatsWanted.coerceAtLeast(2)}", color = setupSecondary, style = SfText.caption())
                        IosTextButton("Share code", {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, "Join my MagicMobile table with code $tableCode")
                            }
                            runCatching { context.startActivity(Intent.createChooser(send, "Share table code")) }
                        }, color = setupAccent, bold = true)
                    }
                }
            }
            Text(table.status, color = setupInk, style = SfText.callout())
            table.room?.let { room -> MatchRoomView(room, selectedDeck?.name, selectedDeck?.commanderName, ready) }
        }
    }
}

/** Relay pregame room: who is here, who is ready, and their commanders (MatchRoomView). */
@Composable
private fun MatchRoomView(room: RelayTable.MatchRoom, deckName: String?, localCommander: String?, ready: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(BrandTheme.canvas.copy(alpha = 0.6f), RoundedCornerShape(12.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("MATCH ROOM", color = setupSecondary, style = sf(12f, SfWeight.bold, tracking = 1.4f))
        for (player in room.players) {
            val commanders = if (player.isLocal && !room.localReady) listOfNotNull(localCommander) else player.commanders
            Row(Modifier.semantics { contentDescription = "${player.name}, ${if (player.isReady) "ready" else "not ready"}" },
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                CommanderDeckPortrait(commanders.firstOrNull(), Modifier.size(40.dp, 56.dp).alpha(if (player.isReady) 1f else 0.4f))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(player.name, color = setupInk, style = SfText.headline())
                        if (player.isHost) Text("HOST", Modifier.background(setupAccent.copy(alpha = 0.25f), RoundedCornerShape(50))
                            .padding(horizontal = 5.dp, vertical = 1.dp), color = setupInk, style = sf(11f, SfWeight.black))
                    }
                    Text(if (commanders.isEmpty()) (if (player.isReady) "Ready" else "Choosing a deck…") else commanders.joinToString(" & "),
                        color = setupSecondary, style = SfText.caption(), maxLines = 2)
                }
                SfImage(if (player.isReady) "checkmark.circle.fill" else "hourglass", if (player.isReady) Color(0.2f, 0.78f, 0.35f) else setupSecondary, 20.dp)
            }
        }
        room.aiSummary?.let { Text(it, color = setupSecondary, style = SfText.caption()) }
        if (room.localReady) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("checkmark.seal.fill", Color(0.2f, 0.78f, 0.35f), 16.dp)
                Text("You're ready. The game starts when everyone is.", color = Color(0.2f, 0.78f, 0.35f), style = SfText.callout(SfWeight.semibold))
            }
        } else {
            Text("Pick your deck above, then ready up${deckName?.let { " with $it" } ?: ""}.", color = setupSecondary, style = SfText.caption())
            BrandButton(ready, Modifier.semantics { contentDescription = "Ready" }, enabled = deckName != null) { BrandButtonText("Ready") }
        }
    }
}
