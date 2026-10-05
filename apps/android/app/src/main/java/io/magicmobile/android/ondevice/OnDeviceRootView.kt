package io.magicmobile.android.ondevice

import androidx.compose.material3.LocalContentColor
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.glow
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
    var showHowToPlay by rememberSaveable { mutableStateOf(false) }
    var howToPlayOpensTable by rememberSaveable { mutableStateOf(false) }
    var howToPlaySeenVersion by AppPreferences.int(HowToPlayLaunch.SEEN_VERSION_KEY, 0)
    var offlineArtPromptSeen by AppPreferences.boolean(OfflineArtLaunch.SEEN_KEY, false)
    var showOfflineArtPrompt by remember { mutableStateOf(false) }
    var showFriends by remember { mutableStateOf(false) }
    // The profile name is the name at every table; friends see the table this phone hosts while it has open seats.
    LaunchedEffect(vm.account.username) { vm.account.username?.let { playerDisplayName = it } }
    var showDecks by remember { mutableStateOf(false) }
    var studioOpen by remember { mutableStateOf<io.magicmobile.android.studio.DeckStudioOpen?>(null) }
    var confirmLeave by remember { mutableStateOf(false) }
    var bannerError by remember { mutableStateOf<String?>(null) }
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
    var quickBracket by AppPreferences.int("magicmobile.quick.opponentBracket", 0)
    var quickDeckID by AppPreferences.string("magicmobile.quick.opponentDeck", "")
    var quickSkill by AppPreferences.int("magicmobile.quick.aiSkill", 3)
    var activeMatch by remember { mutableStateOf<ActiveMatch?>(null) }
    var rankChange by remember { mutableStateOf<io.magicmobile.android.game.RankChange?>(null) }
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
    val selectedDeckColors: List<String> = setup.bracketDecks.firstOrNull { it.playerDeckID == selectedDeckID }?.colors?.map { it.toString() } ?: emptyList()
    val deckPickerSections = listOfNotNull(TavernPickerSection("Included precons", precons.map { it.name to "precon:${it.id}" })) +
        io.magicmobile.android.game.CommanderBracket.entries.mapNotNull { bracket ->
            setup.bracketDecks.filter { it.bracket == bracket }.takeIf { it.isNotEmpty() }?.let { decks ->
                TavernPickerSection("Included · ${bracket.title}", decks.map { "${it.name} · ${it.commander}" to it.playerDeckID })
            }
        } + listOfNotNull(setup.localDecks.takeIf { it.isNotEmpty() }?.let { decks -> TavernPickerSection("Saved on this device", decks.map { it.deck.name to "local:${it.id}" }) })
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
        val you = VersusSeat("you", name.ifEmpty { "You" }, selectedDeck?.commanderName)
        // A table knows everyone's commander before its first snapshot shows the command zones.
        val tableSeats = (setup.multiplayer as? RelayTable)?.tableSeats.orEmpty()
        if (setup.usingMultiplayer && tableSeats.any { it.isLocal } && tableSeats.any { !it.isLocal }) {
            val local = tableSeats.first { it.isLocal }
            return VersusSeat("you", local.name, local.commanders.firstOrNull() ?: you.commander) to
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
        rankChange = null
        val settings = GameResumeSettings(selectedDeckID, listOf(opponent.id), skill, aiStartingPlayerMode, mode.raw, deckBracket.level)
        scope.launch {
            setup.startAI(playerDisplayName, deck, listOf(opponent.deck), skill, settings, deckID = selectedDeckID)
            if (session.matchID == null) activeMatch = null
        }
    }

    fun startQuickMatch() {
        val deck = selectedDeck ?: return
        val bracket = selectedDeckBracket ?: return
        val opponentBracket = if (quickBracket == 0) minOf(4, bracket.level) else quickBracket
        val opponent = quickDeckID.takeIf { it.isNotEmpty() }?.let { id -> aiPool.firstOrNull { it.id == id } }
            ?: io.magicmobile.android.game.AIDeckPool.pick(opponentBracket, deck.commanderName, record.file.recentAIDecks, aiPool) ?: return
        startSolo(io.magicmobile.android.game.PlayMode.QUICK, deck, bracket, opponent, quickSkill.coerceIn(1, 10))
    }

    fun startRankedAI(deck: Deck, bracket: io.magicmobile.android.game.CommanderBracket) {
        val position = record.file.rank.position
        val opponent = io.magicmobile.android.game.AIDeckPool.pick(position.opponentBracket, deck.commanderName, record.file.recentAIDecks, aiPool) ?: return
        startSolo(io.magicmobile.android.game.PlayMode.RANKED, deck, bracket, opponent, position.tier.aiSkill)
    }

    /** The host opens a two-seat relay table and shares its code; the guest joins. A table that never fills hands the seat to an AI. */
    suspend fun startRankedHuman(ticket: io.magicmobile.android.game.RankedTicket, deck: Deck, bracket: io.magicmobile.android.game.CommanderBracket) {
        val matchID = ticket.matchId ?: return startRankedAI(deck, bracket)
        activeMatch = ActiveMatch(io.magicmobile.android.game.PlayMode.RANKED, selectedDeckID, deck.name, deck.commanderName, selectedDeckColors, bracket.level,
            listOf(io.magicmobile.android.game.MatchOpponent(ticket.opponent ?: "Challenger", null, false)), null, null, null, matchID)
        rankChange = null
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
            rankChange = null
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
                rankChange = null
                setup.joinOnline(code, playerDisplayName, deck)
                watchPersonTable(friend)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                bannerError = io.magicmobile.android.game.FriendChallengeRules.message(io.magicmobile.android.social.SupabaseLite.code(e))
            }
        }
    }

    fun saveResult(match: ActiveMatch, outcome: io.magicmobile.android.game.RankOutcome, turns: Int, snapshot: GameSnapshot?) {
        val colors = match.colors.ifEmpty { io.magicmobile.android.game.PlayerStats.colors(snapshot?.human?.zones?.command?.firstOrNull()?.card?.manaCost) }
        val change = record.record(match.mode, outcome, match.opponents, match.opponentBracket, match.aiSkill, match.deckID, match.deckName,
            match.commander, colors, match.deckBracket, turns, match.aiDeckID)
        rankChange = change
        match.rankedMatchID?.let { id -> scope.launch { matchmaker.report(id, outcome) } }
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
        saveResult(current, outcome, snapshot.turn, snapshot)
        activeMatch = current.copy(recorded = true)
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
                selection.selectedCard = null; selection.inspectedCard = null
                activeMatch = null; rankChange = null; ceremony = null; matchmaker.finish(); rankedConnectJob?.cancel()
            }
        }
    }

    fun requestLeave() { if (!setup.isBusy && !session.isWorking) confirmLeave = true }


    fun startAI() {
        val deck = selectedDeck ?: return
        if (aiPrecons.size != opponentCount) return
        activeMatch = null; rankChange = null
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
        setup.resume.offer?.sidecar?.settings?.let { saved ->
            if (saved.deckID in setup.deckIDs) selectedDeckID = saved.deckID
            val ids = saved.aiDeckIDs.filter { id -> aiPool.any { it.id == id } }
            val mode = saved.mode?.let { raw -> io.magicmobile.android.game.PlayMode.entries.firstOrNull { it.raw == raw } }
            activeMatch = mode?.let { m ->
                val foes = ids.mapNotNull { id -> aiPool.firstOrNull { it.id == id } }
                ActiveMatch(m, saved.deckID, setup.deck(saved.deckID)?.name ?: "Deck", setup.deck(saved.deckID)?.commanderName, emptyList(),
                    saved.deckBracket ?: 2, foes.map { io.magicmobile.android.game.MatchOpponent(it.name, it.commander, true) },
                    foes.firstOrNull()?.bracket?.level, saved.aiSkill, foes.firstOrNull()?.id)
            }
            rankChange = null
            if (mode == null && ids.size == saved.aiDeckIDs.size && ids.size in 1..3) {
                opponentCount = ids.size
                ids.getOrNull(0)?.let { aiPreconID = it }; ids.getOrNull(1)?.let { aiPrecon2ID = it }; ids.getOrNull(2)?.let { aiPrecon3ID = it }
            }
            aiSkill = saved.aiSkill.coerceIn(1, 10)
            if (saved.startingPlayerMode in setOf("choose", "roll")) aiStartingPlayerMode = saved.startingPlayerMode
        }
        scope.launch { setup.resumeGame() }
    }

    fun refresh() { scope.launch { setup.perform { session.refresh(); setup.updateSessionForeground() } } }

    fun rematchOrLeave() {
        if (session.snapshot?.isCompleted != true || setup.usingMultiplayer) return requestLeave()
        val mode = activeMatch?.mode
        scope.launch {
            if (!setup.close()) return@launch
            selection.selectedCard = null; selection.inspectedCard = null
            activeMatch = null; rankChange = null
            // Quick Match deals a new opponent; Ranked looks for the next match.
            when (mode) {
                io.magicmobile.android.game.PlayMode.QUICK -> startQuickMatch()
                io.magicmobile.android.game.PlayMode.RANKED -> { lobby = "ranked"; findRankedMatch() }
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
        } else if (!setup.usingMultiplayer && aiStartingPlayerMode == "roll") {
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
    LaunchedEffect(portraitModeEnabled, activeGame) { OrientationController.apply(activity, portraitModeEnabled, activeGame) }
    LaunchedEffect(session.snapshot?.isCompleted, session.snapshot?.isSpectating) { recordFinishedGameIfNeeded() }
    LaunchedEffect(activeGame) {
        if (activeGame) { matchmaker.finish(); rankedConnectJob?.cancel() }
        GameAudio.setScene(if (activeGame) GameMusic.GAME else GameMusic.MENU)
        // A resumed game is not a new matchup: no versus intro.
        if (!activeGame || setup.resume.resumedGame) { versusIntro = null; return@LaunchedEffect }
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
        // A table's roll outlives the session attaching to its match; resetting it here replayed a
        // finished roll. Tables reset on a new roll instead (below).
        if (!setup.usingMultiplayer) { didDismissStartingRoll = false; attemptedStartingPromptID = null }
        aiStartingRoll = null; aiRevealedRollCount = 0; aiRollSeatNames = emptyMap()
        prepareAIRollIfNeeded()
    }
    val table = setup.multiplayer as? RelayTable
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
        if (!setup.isBusy && !setup.needsLeave) showSetup = false
    }
    BackHandler(enabled = activeGame) { requestLeave() }

    val turnControl = NativeTurnControl(session.canEndTurn, session.canEndTurnSkippingResponses, session.canSkipToMyTurn, session.isAutoPassing,
        session.autoPassStatus, { session.endTurn() }, { session.endTurnSkippingResponses() }, { session.skipToMyTurn() }, { session.stopAutoPass() })

    // One flag for everything the starting roll covers (iOS startingRollVisible): a relay table's
    // shared roll or its "Who goes first?" panel, or an AI table's local roll.
    val multiplayerRollVisible = setup.usingMultiplayer && table != null && table.endpoint != null && table.isConnected && !didDismissStartingRoll
    val aiRoll = aiStartingRoll
    val aiRollVisible = !setup.usingMultiplayer && session.matchID != null && aiStartingPlayerMode == "roll" && aiRoll != null && !didDismissStartingRoll
    val startingRollVisible = multiplayerRollVisible || aiRollVisible
    // The roll's own answer to "Select a starting player" stays quiet while it is on its way.
    val startingChoicePending = session.snapshot?.let { snapshot ->
        val promptID = snapshot.promptEnvelopeV2?.id
        promptID != null && startingChoiceFailedPromptID != promptID && OnDeviceStartingPlayerChoice.candidateIDs(snapshot) != null &&
            (if (setup.usingMultiplayer) table?.startingRoll != null else aiStartingPlayerMode == "roll" && aiStartingRoll != null)
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
        !(showDecks || showAppearance || showUpdates || showDownloads || showHowToPlay)
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
        if (HowToPlayLaunch.shouldShowAutomatically(howToPlaySeenVersion, LaunchEnvironment.values)) { howToPlayOpensTable = true; showHowToPlay = true }
        else if (OfflineArtLaunch.shouldShowAutomatically(howToPlaySeenVersion, offlineArtPromptSeen, LaunchEnvironment.values)) showOfflineArtPrompt = true
    }
    fun closeHowToPlay() {
        showHowToPlay = false; howToPlayOpensTable = false
        howToPlaySeenVersion = HowToPlayLaunch.seenVersionAfterClosing(howToPlaySeenVersion)
    }

    MaterialTheme(colorScheme = darkColorScheme()) {
        CompositionLocalProvider(LocalBrandAmbientMotion provides !(showDecks || showAppearance || showUpdates || showDownloads || showHowToPlay),
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
                        LocalGameConcede provides GameConcedeHandler { concede() },
                        LocalEmoteCenter provides vm.emotes,
                        LocalStartingRollVisible provides boardQuiet) {
                        // Hidden from TalkBack while the starting roll covers it.
                        Box(Modifier.fillMaxSize().alpha(if (setup.isBusy) 0.999f else 1f)
                            .then(if (boardQuiet) Modifier.clearAndSetSemantics {} else Modifier)) {
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
                } else if (showSetup || (setup.needsLeave && activeMatch?.isPersonTable != true)) {
                    SetupScreen(setup, selectedDeck, aiPrecons, deckPickerSections, aiDeckPickerSections, playerDisplayName, { playerDisplayName = it.take(24) }, portraitModeEnabled,
                        { portraitModeEnabled = it }, selectedDeckID, { selectedDeckID = it }, aiIDs, { index, id ->
                            when (index) { 0 -> aiPreconID = id; 1 -> aiPrecon2ID = id; else -> aiPrecon3ID = id }
                        }, opponentCount, { opponentCount = it }, aiSkill, { aiSkill = it }, aiStartingPlayerMode, { aiStartingPlayerMode = it },
                        playWithFriends, { playWithFriends = it }, mayStart,
                        onlinePlayers = playerCount, setOnlinePlayers = { playerCount = it },
                        hostOnline = {
                            val deck = selectedDeck
                            if (deck != null) scope.launch {
                                val aiCount = onlineAICount(playerCount)
                                setup.hostOnline(playerDisplayName, deck, playerCount, aiIDs.take(aiCount).mapNotNull { id -> aiPool.firstOrNull { it.id == id }?.deck }, aiSkill)
                            }
                        },
                        joinOnline = { code -> selectedDeck?.let { setup.joinOnline(code, playerDisplayName, it) } },
                        readyOnline = { selectedDeck?.let { setup.readyForMatch(playerDisplayName, it) } },
                        back = { GameAudio.play(GameSound.UI_BACK); showSetup = false },
                        openSettings = { GameAudio.play(GameSound.UI_OPEN); showAppearance = true },
                        openDecks = { showDecks = true }, start = ::startAI, leave = { confirmLeave = true },
                        openStudio = { studioOpen = it; showDecks = true })
                } else if (lobby != null) {
                    val deckSlot: @Composable () -> Unit = {
                        io.magicmobile.android.ranked.PlayDeckSection(selectedDeck?.name, selectedDeck?.commanderName, selectedDeckBracket,
                            selectedDeckID.startsWith("local:"), selectedDeckID, deckPickerSections, { selectedDeckID = it }, { showDecks = true },
                            { showBracketSheet = true }, enabled = !setup.isBusy && matchPhase == io.magicmobile.android.game.RankedMatchmaker.Phase.Idle)
                    }
                    BackHandler { GameAudio.play(GameSound.UI_BACK); lobby = if (lobby == "chooser" || lobby == "profile") null else "chooser" }
                    when (lobby) {
                        "quick" -> io.magicmobile.android.ranked.QuickMatchScreen(selectedDeckBracket, quickBracket, { quickBracket = it }, quickDeckID,
                            { quickDeckID = it }, quickSkill, { quickSkill = it }, aiStartingPlayerMode, { aiStartingPlayerMode = it }, aiPool, mayStartSolo,
                            if (setup.identity == null) setup.status else null, ::startQuickMatch, { lobby = "chooser" }, deckSlot)
                        "ranked" -> io.magicmobile.android.ranked.RankedLobbyScreen(record.file.rank, selectedDeckBracket, vm.account.rankedQueue != null,
                            mayStartSolo, if (setup.identity == null) setup.status else null, ::findRankedMatch, { lobby = "profile" }, { lobby = "chooser" }, deckSlot)
                        "profile" -> io.magicmobile.android.ranked.PlayerProfileScreen(record, vm.account.username ?: playerDisplayName,
                            setup.localDecks.mapNotNull { saved -> saved.deck.entries.firstOrNull { it.section == "commander" }?.name } + setup.aiPool.map { it.commander }) { lobby = null }
                        else -> io.magicmobile.android.ranked.PlayModeChooser(record.file.rank.position, io.magicmobile.android.game.RankLadder.seasonName(record.file.rank.season),
                            quick = { lobby = "quick" }, ranked = { lobby = "ranked" }, custom = { lobby = null; showSetup = true }, back = { lobby = null })
                    }
                } else {
                    TavernMainMenu(selectedDeck?.name ?: "Choose a deck", playerDisplayName, play = { lobby = "chooser" },
                        decks = { showDecks = true }, settings = { showAppearance = true }, news = { showUpdates = true },
                        commanderName = selectedDeck?.commanderName, downloads = { showDownloads = true }, howToPlay = { showHowToPlay = true },
                        friends = { showFriends = true }, friendsBadge = vm.account.onlineFriendCount + vm.account.incomingCount,
                        profile = { lobby = "profile" }, rank = record.file.rank.position)
                }

                // The starting roll, on an opaque cover: a relay table's shared roll (the host's recorded dice,
                // played back on every phone) or its "Who goes first?" panel, or the AI table's local roll.
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
                            Column(Modifier.padding(horizontal = 16.dp).widthIn(max = 440.dp).fillMaxWidth()
                                .background(BrandTheme.surface, RoundedCornerShape(22.dp)).padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                Text("Who goes first?", color = BrandTheme.ink, style = SfText.title2(SfWeight.bold), textAlign = TextAlign.Center)
                                Text(table.rollStatus, color = BrandTheme.inkSecondary, style = SfText.subheadline(), textAlign = TextAlign.Center)
                                Text(table.hostAISeatSummary ?: "Each player rolls a D20. Highest starts; ties reroll.", color = BrandTheme.inkSecondary,
                                    style = SfText.caption(), textAlign = TextAlign.Center)
                                BrandButton({ runCatching { table.rollStartingPlayer() }.onFailure { bannerError = it.message } },
                                    enabled = !table.hasRolled) {
                                    BrandButtonText(if (table.hasRolled) "Waiting for other players…" else "Roll D20")
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

                // Recovery banner. On the starting roll's cover only a roll error shows, still readable and dismissible.
                if ((!startingRollVisible || bannerError != null) &&
                    (setup.isBusy || bannerError != null || (activeGame && (session.snapshot == null || !setup.canUseSession)))) {
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

                if (!activeGame && matchPhase != io.magicmobile.android.game.RankedMatchmaker.Phase.Idle) {
                    io.magicmobile.android.ranked.RankedSearchOverlay(matchPhase, record.file.rank.position, { matchmaker.skipToAI() }, { matchmaker.cancel() })
                }
                val target = challengeTarget
                if (!activeGame && challengeWaiting && target != null) {
                    io.magicmobile.android.ranked.ChallengeWaitingOverlay(target.first, target.second, record.file.rank.position) { challenges.cancelOutgoing() }
                }
                val invite = challengeIncoming.firstOrNull()
                if (menuIsFree && (lobby == null || lobby == "chooser") && !challengeWaiting && activeMatch == null && invite != null) {
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

            if (showAppearance) BoardSheet({ showAppearance = false }) {
                AppearanceSettings(portraitModeEnabled, { portraitModeEnabled = it }, inGame = activeGame) { showAppearance = false }
            }
            if (showUpdates) BoardSheet({ showUpdates = false }) { UpdatesSheet(setup.identity?.upstreamCommit) { showUpdates = false } }
            if (showHowToPlay) BoardSheet(::closeHowToPlay, background = BrandTheme.canvas, skipPartiallyExpanded = true) {
                // The first visit opens straight into the table's tutorial; the menu offers both.
                HowToPlayView(::closeHowToPlay, Modifier.fillMaxWidth().fillMaxHeight(0.94f), tutorialID = if (howToPlayOpensTable) HowToPlayText.tutorials[0].id else null)
            }
            // DeckStudioRootView, full screen over the menu (fullScreenCover on iOS).
            io.magicmobile.android.studio.StudioCover(showDecks) {
                io.magicmobile.android.studio.DeckStudioRootView(setup, selectedDeckID, { selectedDeckID = it },
                    preparePlay = { showSetup = true }, dismiss = { showDecks = false; studioOpen = null }, open = studioOpen)
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
            if (activeGame && vm.emotes.isChatOpen) BoardSheet({ vm.emotes.openChat(false) }, skipPartiallyExpanded = true) {
                val profileReady = vm.account.phase == PlayerAccount.Phase.READY
                TableChatPanel(vm.emotes, session.snapshot,
                    report = if (profileReady) { line -> scope.launch { vm.account.report(line.name, line.text, "chat") } } else null,
                    block = if (profileReady) { name -> vm.emotes.mute(name); scope.launch { vm.account.block(name) } } else null) { vm.emotes.openChat(false) }
            }
            if (showBracketSheet) {
                val deck = selectedDeck; val report = selectedBracketReport
                if (deck != null && report != null) BoardSheet({ showBracketSheet = false }, skipPartiallyExpanded = true) {
                    val fixed = setup.bracketDecks.firstOrNull { it.playerDeckID == selectedDeckID }?.bracket
                        ?: if (selectedDeckID.startsWith("precon:")) io.magicmobile.android.game.CommanderBracket.CORE else null
                    io.magicmobile.android.ranked.DeckBracketSheet(deck.name, report, run { bracketRevision; declaredBracket(selectedDeckID) }, fixed,
                        if (fixed == null) { b -> setDeclaredBracket(selectedDeckID, b) } else null) { showBracketSheet = false }
                }
            }
            if (showFriends) BoardSheet({ showFriends = false }, skipPartiallyExpanded = true) {
                FriendsSheet(vm.account, join = { code -> scope.launch { delay(450); openJoinLink(code) } }, myRankStep = record.file.rank.position.step,
                    challenge = { friend, mode -> challengeFriend(friend.username, mode) }) { showFriends = false }
            }
            if (showOfflineArtPrompt) {
                ConfirmationDialog("Play offline with card art?",
                    "Card art loads from Scryfall while you're online. Save your decks' images now so they show without a connection too.",
                    listOf(ConfirmationAction("Choose downloads") { offlineArtPromptSeen = true; showOfflineArtPrompt = false; showDownloads = true }),
                    cancelTitle = "Not now") { offlineArtPromptSeen = true; showOfflineArtPrompt = false }
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

/** Port of TavernMainMenu (Board/MainMenuViews.swift). */
@Composable
fun TavernMainMenu(deckName: String, playerName: String, play: () -> Unit, decks: () -> Unit, settings: () -> Unit, news: (() -> Unit)? = null,
                   commanderName: String? = null, downloads: (() -> Unit)? = null, howToPlay: (() -> Unit)? = null,
                   friends: (() -> Unit)? = null, friendsBadge: Int = 0, profile: (() -> Unit)? = null,
                   rank: io.magicmobile.android.game.RankPosition? = null) {
    val reduceMotion = LaunchEnvironment.reduceMotion
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val alpha by animateFloatAsState(if (appeared) 1f else 0f, tween(if (reduceMotion) 0 else 450), label = "menuAppear")
    val offset by animateFloatAsState(if (appeared || reduceMotion) 0f else 14f, tween(if (reduceMotion) 0 else 450), label = "menuOffset")
    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize())
        BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            val horizontal = maxWidth > maxHeight
            val cardWidth = if (horizontal) minOf(150.dp, maxHeight * 0.36f) else minOf(160.dp, maxWidth * 0.38f, maxHeight * 0.19f)
            val height = maxHeight
            // No scrolling in either orientation (Caleb, 2026-10-02 landscape, 2026-10-04 portrait): short screens
            // tighten the brand block; anything still too tall scales to fit.
            val density = if (!horizontal) (if (height < 700.dp) 1 else 0) else if (height < 400.dp) 2 else if (height < 470.dp) 1 else 0
            // The deck and commander beside (landscape) or above (portrait) the actions; landscape gives each half the width.
            val deckPart: @Composable (Modifier) -> Unit = { partModifier ->
                Column(partModifier.widthIn(max = 400.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (!horizontal) MenuIdentity(compact = false, playerName, density)
                    HeroCommanderCard(commanderName, cardWidth)
                    MenuDeckTile(deckName, commanderName)
                }
            }
            val actionsPart: @Composable (Modifier) -> Unit = { partModifier ->
                Column(partModifier.widthIn(max = 400.dp).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(when (density) { 0 -> 14.dp; 1 -> 10.dp; else -> 8.dp })) {
                    if (horizontal) Box(Modifier.padding(bottom = if (density == 0) 8.dp else 2.dp)) { MenuIdentity(compact = true, playerName, density) }
                    BrandButton({ GameAudio.play(GameSound.MENU_PLAY); play() }, Modifier.semantics { contentDescription = "Play Commander" }) {
                        SfImage("flame.fill", LocalContentColor.current, 19.dp)
                        Text("Play Commander", Modifier.weight(1f).padding(start = 4.dp), color = LocalContentColor.current,
                            style = sf(19f, SfWeight.heavy, SfDesign.SERIF).engraved(0.75f))
                        SfImage("chevron.right", LocalContentColor.current, 15.dp)
                    }
                    BrandButton({ GameAudio.play(GameSound.UI_OPEN); decks() }, Modifier.semantics { contentDescription = "Decks" }, kind = BrandButtonKind.SECONDARY) {
                        SfImage("rectangle.stack.fill", LocalContentColor.current, 17.dp)
                        Text("Decks", Modifier.weight(1f).padding(start = 4.dp), color = LocalContentColor.current,
                            style = sf(17f, SfWeight.heavy, SfDesign.SERIF).engraved(0.75f))
                        SfImage("chevron.right", LocalContentColor.current, 14.dp)
                    }
                    // Friends and Profile share a row (Caleb, 2026-10-04) so the menu fits without scrolling.
                    val social: @Composable (Modifier) -> Unit = { itemModifier ->
                        friends?.let { openFriends ->
                            BrandButton({ GameAudio.play(GameSound.UI_OPEN); openFriends() }, itemModifier.semantics {
                                contentDescription = if (friendsBadge > 0) "Friends, $friendsBadge online or waiting" else "Friends"
                            }, kind = BrandButtonKind.SECONDARY) {
                                SfImage("person.2.fill", LocalContentColor.current, 17.dp)
                                Text("Friends", Modifier.weight(1f).padding(start = 4.dp), color = LocalContentColor.current, maxLines = 1,
                                    style = sf(17f, SfWeight.heavy, SfDesign.SERIF).engraved(0.75f))
                                if (friendsBadge > 0) Text("$friendsBadge", Modifier.background(BrandTheme.ember, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp),
                                    color = Color.White, style = sf(13f, SfWeight.black))
                            }
                        }
                        profile?.let { openProfile ->
                            BrandButton({ GameAudio.play(GameSound.UI_OPEN); openProfile() }, itemModifier.testTag("menu.profile").semantics {
                                contentDescription = rank?.let { "Profile, ${it.title}" } ?: "Profile"
                            }, kind = BrandButtonKind.SECONDARY) {
                                rank?.let { io.magicmobile.android.ranked.RankEmblem(it.tier, 26.dp) }
                                    ?: SfImage("person.crop.circle.fill", LocalContentColor.current, 17.dp)
                                Text("Profile", Modifier.weight(1f).padding(start = 4.dp), color = LocalContentColor.current, maxLines = 1,
                                    style = sf(17f, SfWeight.heavy, SfDesign.SERIF).engraved(0.75f))
                            }
                        }
                    }
                    if (friends != null || profile != null) {
                        if (androidx.compose.ui.platform.LocalDensity.current.fontScale > 1.3f) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { social(Modifier.fillMaxWidth()) }
                        else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) { social(Modifier.weight(1f)) }
                    }
                    // iOS ViewThatFits: one row with the widest gap that fits, else a column.
                    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                        val count = 1 + listOfNotNull(news, downloads, howToPlay).size
                        val gap = listOf(20.dp, 8.dp, 0.dp).firstOrNull { 72.dp * count + it * (count - 1) <= maxWidth }
                        val utilities: @Composable () -> Unit = {
                            BrandIconButton("Settings", "gearshape.fill", { GameAudio.play(GameSound.UI_OPEN); settings() })
                            news?.let { BrandIconButton("Updates", "scroll.fill", { GameAudio.play(GameSound.PAGE_FLIP); it() }) }
                            downloads?.let { BrandIconButton("Downloads", "arrow.down.to.line.circle.fill", { GameAudio.play(GameSound.UI_OPEN); it() }) }
                            howToPlay?.let {
                                BrandIconButton(HowToPlayText.TITLE, "questionmark.circle", { GameAudio.play(GameSound.PAGE_FLIP); it() },
                                    Modifier.testTag("menu.howToPlay"))
                            }
                        }
                        if (gap != null) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally)) { utilities() }
                        else Column { utilities() }
                    }
                }
            }
            if (horizontal) {
                // A fixed screen that never scrolls: laid out at its natural height and scaled down only if taller.
                FitsHeight(Modifier.fillMaxSize().alpha(alpha).offset(y = offset.dp)) {
                    Row(Modifier.widthIn(max = 960.dp).fillMaxWidth().padding(horizontal = 36.dp, vertical = if (density == 0) 16.dp else 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(44.dp), verticalAlignment = Alignment.CenterVertically) {
                        deckPart(Modifier.weight(1f)); actionsPart(Modifier.weight(1f))
                    }
                }
            } else {
                FitsHeight(Modifier.fillMaxSize().alpha(alpha).offset(y = offset.dp)) {
                    Column(Modifier.fillMaxWidth().padding(horizontal = 26.dp, vertical = if (density == 0) 16.dp else 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (density == 0) 14.dp else 10.dp)) {
                        deckPart(Modifier); actionsPart(Modifier)
                    }
                }
            }
        }
    }
}

/** Lays its content out at its natural height and scales it down only if that is taller than the space, keeping it centred. */
@Composable
private fun FitsHeight(modifier: Modifier, content: @Composable () -> Unit) {
    androidx.compose.ui.layout.Layout(content, modifier) { measurables, constraints ->
        val placeable = measurables.first().measure(constraints.copy(minWidth = 0, minHeight = 0, maxHeight = androidx.compose.ui.unit.Constraints.Infinity))
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth else placeable.width
        val height = if (constraints.hasBoundedHeight) constraints.maxHeight else placeable.height
        val scale = if (placeable.height > height) height.toFloat() / placeable.height else 1f
        layout(width, height) {
            placeable.placeWithLayer((width - placeable.width) / 2, (height - placeable.height) / 2) { scaleX = scale; scaleY = scale }
        }
    }
}

/** Walnut & Ember: the deck's name on a parchment label in brass trim. */
@Composable
private fun MenuDeckTile(deckName: String, commanderName: String?) {
    Column(Modifier.glow(Color.Black.copy(alpha = 0.45f), 6.dp, 9.dp)
        .tavernFill(TavernMaterial.PARCHMENT, RoundedCornerShape(9.dp)).tavernBrassFrame(0.6f)
        .padding(horizontal = 22.dp, vertical = 9.dp)
        .semantics(mergeDescendants = true) { contentDescription = commanderName?.let { "Your deck: $deckName, commander $it" } ?: "Your deck: $deckName" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("YOUR DECK", color = io.magicmobile.android.studio.DeckStudioPalette.accent, style = sf(10f, SfWeight.heavy, SfDesign.SERIF, tracking = 2.2f))
        Text(deckName, color = TavernPalette.ink, style = sf(21f, SfWeight.heavy, SfDesign.SERIF), textAlign = TextAlign.Center)
        if (!commanderName.isNullOrEmpty()) Text(commanderName, color = io.magicmobile.android.studio.DeckStudioPalette.secondaryInk,
            style = sf(13f, design = SfDesign.SERIF).copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic), textAlign = TextAlign.Center)
    }
}

/** The brand block. `density` 0 is the full layout; 1 and 2 tighten it to fit a short screen. */
@Composable
private fun MenuIdentity(compact: Boolean, playerName: String, density: Int) {
    Column(horizontalAlignment = if (compact) Alignment.Start else Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (density == 0) 8.dp else 5.dp)) {
        // Portrait leaves the mark out so the deck and actions sit higher (the app icon carries it).
        if (compact) BrandMark(when (density) { 0 -> 52.dp; 1 -> 42.dp; else -> 34.dp })
        if (density < 2) Text("MAGICMOBILE", color = BrandTheme.inkSecondary, style = sf(12f, SfWeight.heavy, tracking = 3f))
        // Portrait and tighter landscape layouts set the title on one line.
        BrandTitle(if (density == 0 && compact) "Your next\ngreat game." else "Your next great game.",
            if (compact) (when (density) { 0 -> 32f; 1 -> 27f; else -> 24f }) else (if (density == 0) 30f else 26f),
            textAlign = if (compact) TextAlign.Start else TextAlign.Center)
        if (density < 2 && playerName.isNotBlank()) Text("Welcome back, ${playerName.trim()}", color = BrandTheme.inkSecondary, style = SfText.subheadline(),
            textAlign = if (compact) TextAlign.Start else TextAlign.Center)
    }
}

/** The setup screen (OnDeviceRootView.setupContent). */
@Composable
private fun SetupScreen(setup: OnDeviceSetupModel, selectedDeck: Deck?, aiPrecons: List<io.magicmobile.android.game.AIDeck>,
                        deckSections: List<TavernPickerSection<String>>, aiSections: List<TavernPickerSection<String>>,
                        playerName: String, setPlayerName: (String) -> Unit,
                        portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit, selectedDeckID: String, selectDeck: (String) -> Unit,
                        aiIDs: List<String>, selectAIDeck: (Int, String) -> Unit, opponentCount: Int, setOpponentCount: (Int) -> Unit,
                        aiSkill: Int, setAISkill: (Int) -> Unit, startingMode: String, setStartingMode: (String) -> Unit,
                        playWithFriends: Boolean, setPlayWithFriends: (Boolean) -> Unit, mayStart: Boolean,
                        onlinePlayers: Int, setOnlinePlayers: (Int) -> Unit, hostOnline: () -> Unit, joinOnline: (String) -> Unit,
                        readyOnline: () -> Unit,
                        back: () -> Unit, openSettings: () -> Unit, openDecks: () -> Unit, start: () -> Unit, leave: () -> Unit,
                        openStudio: (io.magicmobile.android.studio.DeckStudioOpen) -> Unit) {
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
                            io.magicmobile.android.studio.DeckStudioSetupDeckStatus(setup, selectedDeckID, selectedDeck, openStudio)
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
                    val profileName = LocalPlayerAccount.current?.username
                    TavernTextField(playerName, setPlayerName, "Player name", Modifier.semantics { contentDescription = "Player name" },
                        enabled = !seatLocked && profileName == null)
                    Text(if (profileName != null) "Your profile name. Change it in Friends." else "Choose a name with 1–24 characters.",
                        color = setupSecondary, style = SfText.caption())
                    TavernToggle("Auto-Rotate", portraitModeEnabled, setPortraitModeEnabled)
                    TavernPicker("Your deck", selectedDeckID, deckSections, selectDeck, enabled = !seatLocked)
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
                        TavernStepper("AI opponents: $opponentCount", opponentCount, 1..3, setOpponentCount, enabled = !locked)
                        for (index in 0 until opponentCount.coerceIn(1, 3)) {
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("AI ${index + 1} deck", color = setupSecondary, style = SfText.caption())
                                TavernPicker("AI ${index + 1} deck", aiIDs[index], aiSections,
                                    { selectAIDeck(index, it) }, enabled = !locked, showsTitle = false)
                            }
                        }
                        TavernStepper("AI skill: $aiSkill", aiSkill, 1..10, setAISkill, enabled = !locked)
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
        TavernToggle("Scryfall live images", enabled, { value -> enabled = value; Artwork.setEnabled(context, value) })
        Text("Show saved art first, then sharper images online. Offline download quality stays unchanged.", color = setupSecondary, style = SfText.caption())
        Text("Scryfall receives card names—including your hand—and your IP address.", color = setupSecondary, style = SfText.caption())
    }
}

/** AppearanceSettingsView (Board/MainMenuViews.swift). */
@Composable
private fun AppearanceSettings(portraitModeEnabled: Boolean, setPortraitModeEnabled: (Boolean) -> Unit, inGame: Boolean, done: () -> Unit) {
    Column(Modifier.fillMaxWidth().tavernFill(TavernMaterial.LEATHER,
        overlayBrush = androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.35f))))) {
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
                IosListRow("Challenge a friend to a Quick Match, or to Ranked when you're in the same tier. Friend ranked games count.", systemImage = "figure.fencing")
                IosListRow("A real 3D tavern room behind the menu that shifts as you tilt your phone, with flickering candles.", systemImage = "flame.fill")
                IosListRow("Your profile picture is your favorite commander's art.", systemImage = "person.crop.circle")
                IosListRow("The menu fits on one screen, and Downloads matches the tavern.", systemImage = "rectangle.stack.fill")
                IosListRow("Smoother rank badge turns and lighter menu animations.", systemImage = "sparkles")
                IosListRow("Ranked: climb from Bronze to Mythic in monthly seasons, against players near your rank or an AI at your tier.", systemImage = "shield.lefthalf.filled")
                IosListRow("Quick Match: one AI at your deck's bracket, or choose its bracket, deck and skill.", systemImage = "bolt.fill")
                IosListRow("Every deck shows its Commander bracket, with the Game Changers and combos behind it.", systemImage = "checkmark.seal")
                IosListRow("Your profile: rank, season history, stats, achievements, titles and match history.", systemImage = "person.crop.circle")
                IosListRow("21 new included decks from Bracket 1 to 4, for you and for the AI.", systemImage = "rectangle.stack.fill")
                IosListRow("The Walnut Tavern: a new table, menus and painted card frames, in portrait and landscape.", systemImage = "table.furniture")
                IosListRow("Every spell is cast with its own moment at the centre of the table; your commander gets the big one.", systemImage = "sparkles")
                IosListRow("Tap a player's medallion for their counters, poison and commander damage, and swap between opponents.", systemImage = "person.crop.circle")
                IosListRow("Big boards run smoother: identical tokens stack once there are eight.", systemImage = "square.stack.3d.up")
                IosListRow("A Back button while declaring attackers and blockers.", systemImage = "arrow.uturn.backward")
                IosListRow("Friends, table chat and invite links that open straight into your table.", systemImage = "person.2.fill")
            }
            IosListSection("XMage news", footer = "Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.") {
                IosListRow("XMage release notes", systemImage = "arrow.up.right.square") { open("https://github.com/magefree/mage/releases") }
                IosListRow("Latest upstream changes", systemImage = "arrow.up.right.square") { open("https://github.com/magefree/mage/commits/master/") }
            }
            // Same notice as the download site's footer.
            IosListSection("About", footer = "Independent fan project. Not affiliated with Wizards of the Coast. Magic: The Gathering and card artwork belong to their respective owners.") {
                IosListRow("Card images", value = "Scryfall")
                IosListRow("Privacy", systemImage = "arrow.up.right.square") { open("https://magicmobile-downloads.vercel.app/privacy/") }
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
    val code = setup.relayJoinCode
    val locked = setup.isBusy || setup.needsLeave
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (table == null) {
            TavernPicker("Human players", players, listOf(TavernPickerSection(null, (2..4).map { "$it players" to it })), setPlayers, enabled = !locked)
            TavernStepper("AI opponents: $aiCount", aiCount, 0..maxOf(0, 4 - players), { storedAICount = it }, enabled = !locked)
            for (index in 0 until aiCount) {
                TavernPicker("AI ${index + 1} deck", aiIDs[index], io.magicmobile.android.game.CommanderBracket.entries.mapNotNull { bracket ->
                    setup.aiPool.filter { it.bracket == bracket }.takeIf { it.isNotEmpty() }?.let { decks -> TavernPickerSection(bracket.title, decks.map { it.name to it.id }) } },
                    { selectAIDeck(index, it) }, enabled = !locked)
            }
            if (aiCount > 0) {
                TavernStepper("AI skill: $aiSkill", aiSkill, 1..10, setAISkill, enabled = !locked)
                Text("The host’s AI choices apply to everyone. Higher skill may slow turns.", color = setupSecondary, style = SfText.caption())
            }
            Text("Share the invite link, or friends type the table code. Every player needs this app version and keeps it open during the match.",
                color = setupSecondary, style = SfText.caption())
            BrandButton(host, Modifier.semantics { contentDescription = "Host a table" }, enabled = mayHost) { BrandButtonText("Host a table") }
            BrandDivider(Modifier.fillMaxWidth(), title = "or join")
            TavernTextField(code, { value -> setup.relayJoinCode = value.uppercase().filter { it in TableJoinLink.ALPHABET }.take(6) }, "Table code",
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
                        IosTextButton("Share invite link", {
                            val link = TableJoinLink.url(tableCode) ?: return@IosTextButton
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_SUBJECT, "Join my MagicMobile table")
                                putExtra(Intent.EXTRA_TEXT, "Tap to join my MagicMobile table (code $tableCode): $link")
                            }
                            runCatching { context.startActivity(Intent.createChooser(send, "Share invite link")) }
                        }, color = setupAccent, bold = true)
                    }
                }
            }
            Text(table.status, color = setupInk, style = SfText.callout())
            if (table.room == null && table.endpoint == null && !table.isFailed && table.waitingSeats.isNotEmpty()) {
                RelayWaitingRoomView(table.waitingSeats) { table.removeFromTable(it) }
            }
            table.room?.let { room -> MatchRoomView(room, selectedDeck?.name, selectedDeck?.commanderName, ready) }
        }
    }
}

/** A relay table that is still filling: who has joined and, for the host, a Remove control per joiner (RelayWaitingRoomView). */
@Composable
private fun RelayWaitingRoomView(seats: List<RelayWaitingSeat>, remove: (String) -> Unit) {
    var removal by remember { mutableStateOf<RelayWaitingSeat?>(null) }
    Column(Modifier.fillMaxWidth().background(BrandTheme.canvas.copy(alpha = 0.6f), RoundedCornerShape(12.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("AT THE TABLE", color = setupSecondary, style = sf(12f, SfWeight.bold, tracking = 1.4f))
        for (seat in seats) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(if (seat.connected) "person.crop.circle" else "wifi.exclamationmark", setupSecondary, 20.dp)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(seat.name, color = setupInk, style = SfText.headline())
                        if (seat.isHost) Text("HOST", Modifier.background(setupAccent.copy(alpha = 0.25f), RoundedCornerShape(50))
                            .padding(horizontal = 5.dp, vertical = 1.dp), color = setupInk, style = sf(11f, SfWeight.black))
                    }
                    Text(if (seat.isLocal) "You" else if (seat.connected) "Joined" else "Reconnecting…", color = setupSecondary, style = SfText.caption())
                }
                if (seat.removable) {
                    IosTextButton("Remove", { removal = seat }, Modifier.semantics { contentDescription = "Remove ${seat.name}" },
                        color = io.magicmobile.android.ui.rgb(1.0, 0.27, 0.23), bold = true)
                }
            }
        }
        if (seats.any { it.removable }) {
            Text("Remove anyone you did not invite. The match room opens when every seat is taken.", color = setupSecondary, style = SfText.caption())
        }
    }
    removal?.let { seat ->
        ConfirmationDialog("Remove ${seat.name} from the table?", "Their seat opens for someone else. Anyone with the code can still join.",
            listOf(ConfirmationAction("Remove", destructive = true) { remove(seat.id) })) { removal = null }
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

/** The game being played from Quick Match or Ranked (or a custom table, for the profile), for its result. */
private data class ActiveMatch(
    val mode: io.magicmobile.android.game.PlayMode, val deckID: String, val deckName: String, val commander: String?, val colors: List<String>,
    val deckBracket: Int, val opponents: List<io.magicmobile.android.game.MatchOpponent>, val opponentBracket: Int?, val aiSkill: Int?,
    val aiDeckID: String?, val rankedMatchID: String? = null,
    /** A table for one particular person (a friend challenge): readied automatically, never shown to friends. */
    val privateTable: Boolean = false, val recorded: Boolean = false,
) {
    val isPersonTable: Boolean get() = rankedMatchID != null || privateTable
}
