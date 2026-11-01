import SwiftUI
import Combine
import UIKit
import GameKit
import MagicMobileOnDevice

/// Native setup and lifecycle wiring around the existing portrait/landscape board.
@MainActor
struct OnDeviceRootView: View {
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @ObservedObject private var account = PlayerAccount.shared
    @State private var showFriends = false
    /// A player opened from the table chat: their public profile covers the chat.
    @State private var chatProfile: ChatProfileTarget?
    /// A friend's message that arrived during a game (the banner), and the Messages sheet it opens.
    @State private var messageBanner: MessageBannerItem?
    @State private var messagesHub: MessagesHubTarget?
    @AppStorage(PortraitModePreference.key) private var portraitModeEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @StateObject private var session: OnDeviceSession
    @StateObject private var setup: OnDeviceSetupModel
    @StateObject private var library = DeckLibraryStore()
    /// Deck sync (docs/DECK_SYNC.md), made on first appearance so the player's deletes become tombstones from then on.
    @State private var deckSync: DeckSync?
    @StateObject private var diagnostics: OnDeviceDiagnostics
    @StateObject private var resume: GameResumeCoordinator
    @State private var selectedCard: ZoneCard?
    @State private var inspectedCard: ZoneCard?
    @State private var zone: InspectedZone?
    @AppStorage(OnDeviceSetupPreferences.deckKey) private var selectedDeckID = OnDeviceSetupPreferences.defaultDeckID
    @AppStorage(OnDeviceSetupPreferences.aiDeckKey) private var aiPreconID = OnDeviceSetupPreferences.defaultAIDeckID
    @AppStorage(OnDeviceSetupPreferences.aiDeck2Key) private var aiPrecon2ID = ""
    @AppStorage(OnDeviceSetupPreferences.aiDeck3Key) private var aiPrecon3ID = ""
    @AppStorage(OnDeviceSetupPreferences.aiCountKey) private var opponentCount = 1
    @AppStorage(OnDeviceSetupPreferences.aiSkillKey) private var aiSkill = 2
    @AppStorage("magicmobile.ai.startingPlayerMode") private var aiStartingPlayerMode = "choose"
    @AppStorage(OnDeviceSetupPreferences.humanCountKey) private var playerCount = 2
    @AppStorage("magicmobile.gamecenter.aiOpponentCount") private var gameCenterAIStoredCount = 0
    @AppStorage(OnDeviceSetupPreferences.friendsKey) private var playWithFriends = false
    @AppStorage(AutoPassAfterCast.key) private var autoPassAfterCast = true
    @AppStorage(OnDeviceSmartPass.enabledKey) private var smartAutoPass = true
    @AppStorage(OnDeviceSmartPass.stopsKey) private var phaseStops = OnDeviceSmartPass.Settings.encode(OnDeviceSmartPass.defaultStops)
    @AppStorage(OnDeviceSmartPass.stopForOwnSpellsKey) private var stopForOwnSpells = false
    @AppStorage(OnDeviceSmartPass.stopForThreatsKey) private var stopForThreats = true
    @AppStorage("magicmobile.onlineMode") private var playOnline = false
    @Environment(\.openURL) private var openURL
    /// The menus are Arena's everywhere; in a game the Hearth board keeps its own look.
    @AppStorage(BoardMode.key) private var boardMode = BoardMode.defaultValue
    @State private var showSetup = false
    @State private var showAppearance = false
    @State private var showUpdates = false
    @State private var showDownloads = false
    @State private var showHowToPlay = false
    @State private var howToPlayOpensTable = false
    @State private var showImport = false
    @State private var studioFocus: DeckStudioPlaySelection.FixRequest?
    @State private var confirmLeave = false
    /// When this game's engine match began, for the game's length on the profile.
    @State private var gameStartedAt: Date?
    @StateObject private var emotes = EmoteCenter()
    /// Voice chat for this online game (VoiceRoom); nil in solo games and while the server's switch is off.
    @State private var voiceRoom: VoiceRoom?
    @State private var showDiagnostics = false
    @State private var confirmDeleteReport = false
    @State private var bannerError: String?
    /// The session error the player closed; a different error shows again.
    @State private var dismissedSessionError: String?
    @State private var didDismissStartingRoll = false
    @State private var showOfflineArtPrompt = false
    /// The first launch's welcome: a guided game, How to Play, or straight to the menu.
    @State private var showGuidedWelcome = false
    /// The game on the table is the guided first game: its coach shows notes (GuidedGame.swift).
    @State private var guidedGame = false
    @State private var guidedTip: GuidedGameTip?
    /// The game on the table is a lesson (Lessons.swift): recorded, coached, never counted.
    @State private var lessonRun: LessonRun?
    /// The table code typed or opened from a join link; a link that arrives before the
    /// catalogue is ready waits in `pendingJoinCode`.
    @State private var relayJoinCode = ""
    @State private var pendingJoinCode: String?
    @State private var attemptedStartingPromptID: String?
    @State private var startingChoiceFailedPromptID: String?
    @State private var aiStartingRoll: OnDeviceStartingRoll?
    @State private var aiRevealedRollCount = 0
    @State private var aiRollSeatNames: [String: String] = [:]
    @State private var versusIntro: VersusIntro?
    /// A resumed game skips the versus intro: it is already under way.
    @State private var skipNextVersusIntro = false
    // Quick Match, Ranked and the profile (Ranked/).
    @ObservedObject private var profileRecord = PlayerRecordStore.shared
    @StateObject private var matchmaker = RankedMatchmaker(service: nil)
    /// The freeze log's launch question and its answer (docs/FREEZE_LOG.md).
    @State private var freezePrompt: FreezeIncident?
    @State private var freezeResult: String?
    @StateObject private var challenges = FriendChallengeCoordinator(service: nil)
    /// The friend a challenge is waiting on, and its mode.
    @State private var challengeTarget: (name: String, mode: PlayMode)?
    @State private var lobby: LobbyScreen?
    /// The Play panel over the menu (Arena's blade), its way to play and its tab.
    @State private var playPanel = false
    @AppStorage(ArenaPlayMode.storageKey) private var playModeRaw = ArenaPlayMode.quick.rawValue
    @State private var playTab: ArenaPlayTab = .find
    /// Bumped once your decks' colours are read from the card catalogue (their boxes' pips).
    @State private var deckColorsRevision = 0
    /// Development fixture: the Options page to open on (MAGICMOBILE_UI_TEST_OPEN=settings:board).
    @State private var optionsStartPage: ArenaOptionsView.Page?
    @AppStorage("magicmobile.quick.opponentBracket") private var quickBracket = 0
    @AppStorage("magicmobile.quick.opponentDeck") private var quickDeckID = ""
    @AppStorage("magicmobile.quick.aiSkill") private var quickSkill = 3
    /// Easy, Medium or Hard pick the AI's deck by Power and set its skill; "advanced" keeps the bracket, deck and skill controls.
    @AppStorage("magicmobile.quick.level") private var quickLevel = "medium"
    /// The game being played from Quick Match or Ranked, for its result.
    @State private var activeMatch: ActiveMatch?
    /// How the last ranked result moved the ladder (the result screen's rank strip).
    @State private var rankChange: RankChange?
    /// Why the last ranked win left the ladder alone, once the server answers.
    @State private var rankNote: String?
    /// A division or tier change waiting for its full-screen moment.
    @State private var ceremony: RankChange?
    @State private var showBracketSheet = false
    /// Bumped when a deck's declared bracket changes, so the screens re-read it.
    @State private var bracketRevision = 0
    @State private var rankedConnectTask: Task<Void, Never>?

    /// The pages under the menu's top bar besides home (Play is the panel over them).
    private enum LobbyScreen: Equatable { case rankedHall, leaderboard, profile }

    private struct ActiveMatch: Equatable {
        let mode: PlayMode
        let deckID: String
        let deckName: String
        let commander: String?
        let colors: [String]
        let deckBracket: Int
        let opponents: [MatchRecord.Opponent]
        let opponentBracket: Int?
        let aiSkill: Int?
        let aiDeckID: String?
        /// A ranked game against a person: the server's match, for both sides' reports.
        var rankedMatchID: UUID?
        /// A table for one particular person (a friend challenge): readied automatically, never shown to friends.
        var privateTable = false
        var recorded = false

        var isPersonTable: Bool { rankedMatchID != nil || privateTable }
    }

    private struct VersusIntro {
        let you: VersusIntroOverlay.Seat
        let opponents: [VersusIntroOverlay.Seat]
    }

    /// Seats for the intro: the table's own players when known, else the chosen decks.
    private func makeVersusIntro() -> VersusIntro {
        let name = playerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = profileRecord.rank.position.tier
        let you = VersusIntroOverlay.Seat(id: "you", name: name.isEmpty ? "You" : name,
                                          commander: selectedDeck?.commander?.cardName, tier: tier)
        // A table knows everyone's commander before its first snapshot shows the command zones.
        if setup.usingMultiplayer, let seats = setup.multiplayer?.tableSeats, seats.contains(where: \.isLocal) {
            let opponents = seats.filter { !$0.isLocal }.prefix(3).map {
                VersusIntroOverlay.Seat(id: $0.id, name: $0.name, commander: $0.commanders.first)
            }
            if !opponents.isEmpty {
                let local = seats.first(where: \.isLocal)
                let tableYou = VersusIntroOverlay.Seat(id: "you", name: local?.name ?? you.name,
                                                       commander: local?.commanders.first ?? you.commander, tier: tier)
                return VersusIntro(you: tableYou, opponents: Array(opponents))
            }
        }
        if let snapshot = session.snapshot {
            let others = snapshot.players.filter { !snapshot.isViewer($0.playerId) }.prefix(3).map {
                VersusIntroOverlay.Seat(id: $0.playerId, name: $0.displayName ?? "Opponent",
                                        commander: $0.zones.command.first?.card.name)
            }
            if !others.isEmpty { return VersusIntro(you: you, opponents: Array(others)) }
        }
        if let match = activeMatch, !match.opponents.isEmpty {
            return VersusIntro(you: you, opponents: match.opponents.enumerated().map { index, foe in
                VersusIntroOverlay.Seat(id: "foe-\(index)", name: foe.name, commander: foe.commander)
            })
        }
        if playWithFriends {
            return VersusIntro(you: you, opponents: [VersusIntroOverlay.Seat(id: "friends", name: "Challengers", commander: nil)])
        }
        let opponents = aiPrecons.prefix(max(1, opponentCount)).enumerated().map { index, deck in
            VersusIntroOverlay.Seat(id: "ai-\(index)", name: deck.name, commander: deck.deckList.commander?.cardName)
        }
        return VersusIntro(you: you, opponents: opponents)
    }

    init() {
        let session = OnDeviceSession()
        let resume = Self.makeResumeCoordinator()
        _session = StateObject(wrappedValue: session)
        _resume = StateObject(wrappedValue: resume)
        _setup = StateObject(wrappedValue: OnDeviceSetupModel(session: session, resume: resume))
        var diagnosticDirectory: URL?
        #if DEBUG
        if OnDeviceAppConfiguration.entryPoint == .setupPreview,
           let value = ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PREFERENCES"],
           let id = UUID(uuidString: value) {
            diagnosticDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostics-UITests-\(id.uuidString)")
        }
        #endif
        _diagnostics = StateObject(wrappedValue: OnDeviceDiagnostics(directory: diagnosticDirectory))
    }

    /// Only the embedded app outside XCTest uses Application Support/Resume; tests and
    /// previews get a fresh temporary directory.
    private static func makeResumeCoordinator() -> GameResumeCoordinator {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let directory = GameResumeStore.directory(entryPoint: OnDeviceAppConfiguration.entryPoint,
                                                  testing: NSClassFromString("XCTestCase") != nil,
                                                  applicationSupport: support)
        let resume = GameResumeCoordinator(store: GameResumeStore(directory: directory, protectsFiles: true))
        // Lower the chance that iOS ends the app in the background; everything reloads lazily.
        resume.backgroundPurges = [{ GameAudio.shared.unloadBuffers() }, { NativeDeckArtwork.purgeMemoryCaches() },
                                   { NativeArtworkMemory.shared.purge() }, { NativeDeckMetadataCatalogue.purgeShared() }]
        resume.runBackgroundTask = { name, body in ResumeBackgroundTask.run(name, body) }
        resume.backgroundTimeRemaining = { UIApplication.shared.backgroundTimeRemaining }
        return resume
    }

    /// Once the build identity is known: offer a saved game or explain why it is gone.
    private func evaluateResumeLaunch() {
        guard let identity = setup.identity,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return }
        resume.evaluateLaunch(appBuild: GameResumeIdentity.appBuild(version: version, build: build),
                              engineIdentity: GameResumeIdentity.engine(identity))
    }

    private func resumeSavedGame() {
        guard let record = resume.acceptOffer() else { return }
        // A guided game picks its coach up again and keeps the player's own deck and settings.
        guidedGame = record.setup.deckID == GuidedGameSetup.playerDeckID
            && MagicMobilePreferences.current.bool(forKey: GuidedGameLaunch.activeKey)
        guidedTip = nil
        if !guidedGame { applyResumeSetup(record.setup) }
        activeMatch = resumedMatch(record.setup, deckName: record.playerDeckName)
        rankChange = nil; rankNote = nil
        showSetup = false
        skipNextVersusIntro = true
        Task {
            if !(await setup.resumeAI(record)) { skipNextVersusIntro = false }
        }
    }

    /// The saved game's own choices, so Rematch replays the same table.
    private func applyResumeSetup(_ saved: GameResumeSetup) {
        let precons = Set(AIDeckPool.all.map(\.id))
        let decks = allDeckIDs
        if decks.contains(saved.deckID) { selectedDeckID = saved.deckID }
        let aiIDs = saved.aiDeckIDs.filter(precons.contains)
        if saved.mode == nil, (1...3).contains(aiIDs.count), aiIDs.count == saved.aiDeckIDs.count {
            aiPreconID = aiIDs[0]
            if aiIDs.count > 1 { aiPrecon2ID = aiIDs[1] }
            if aiIDs.count > 2 { aiPrecon3ID = aiIDs[2] }
            opponentCount = aiIDs.count
        }
        aiSkill = min(10, max(1, saved.aiSkill))
        // A ranked game always rolls, so its saved "roll" is not the player's own choice.
        if saved.mode != PlayMode.ranked.rawValue, ["choose", "roll"].contains(saved.startingPlayerMode) {
            aiStartingPlayerMode = saved.startingPlayerMode
        }
        playWithFriends = false; playOnline = false
    }

    private var activeGame: Bool { session.matchID != nil }
    private var aiPrecon: AIDeck? { AIDeckPool.deck(id: aiPreconID) }
    private var aiPrecons: [AIDeck] {
        [aiPreconID, aiPrecon2ID, aiPrecon3ID].prefix(min(3, max(1, opponentCount)))
            .compactMap { id in AIDeckPool.deck(id: id) }
    }
    private func aiDeckSelection(_ index: Int) -> Binding<String> {
        Binding(get: { [aiPreconID, aiPrecon2ID, aiPrecon3ID][index] }, set: { id in
            switch index {
            case 0: aiPreconID = id
            case 1: aiPrecon2ID = id
            default: aiPrecon3ID = id
            }
        })
    }
    /// What every game start and match room sends (AI, Game Center host and joiner, Online):
    /// sideboard, maybeboard and considering cards stay in the saved deck and out of play.
    private var selectedDeck: DeckList? { selectedSourceDeck.map(DeckStudioPlaySelection.playingDeck) }
    private var selectedSourceDeck: DeckList? {
        if let precon = PreconCatalog.all.first(where: { "precon:\($0.id)" == selectedDeckID }) {
            return precon.deckList
        }
        if let included = AIDeckPool.playerDeck(id: selectedDeckID) { return included.deckList }
        return library.decks.first(where: { "local:\($0.id)" == selectedDeckID })?.deckList
    }

    /// Every deck a player can pick: precons, the included bracket decks and saved decks.
    private var allDeckIDs: Set<String> {
        Set(PreconCatalog.all.map { "precon:\($0.id)" } + AIDeckPool.bracketDecks.map(\.playerDeckID) + library.decks.map { "local:\($0.id)" })
    }

    /// The deck pickers' sections: precons, then the included decks by bracket, then saved decks.
    private var deckPickerSections: [TavernPicker<String>.Section] {
        [.init(title: String(localized: "Included precons"), options: PreconCatalog.all.map { ($0.name, "precon:\($0.id)") })]
        + CommanderBracket.allCases.compactMap { bracket in
            let decks = AIDeckPool.bracketDecks.filter { $0.bracket == bracket }
            return decks.isEmpty ? nil : .init(title: String(localized: "Included · \(bracket.title)"),
                                               options: decks.map { ("\($0.name) · \($0.commander)", $0.playerDeckID) })
        }
        + [.init(title: String(localized: "Saved on this device"), options: library.decks.map { ($0.name, "local:\($0.id)") })]
    }

    /// The AI deck pickers of the custom table: every AI deck, by bracket.
    private var aiDeckPickerSections: [TavernPicker<String>.Section] {
        CommanderBracket.allCases.compactMap { bracket in
            let decks = AIDeckPool.all.filter { $0.bracket == bracket }
            return decks.isEmpty ? nil : .init(title: bracket.title, options: decks.map { ($0.name, $0.id) })
        }
    }

    /// The selected deck's bracket: fixed for included decks, else the list check with the player's own call.
    private var selectedBracketReport: BracketReport? {
        _ = bracketRevision
        return selectedDeck.map { BracketRules.bundled.evaluate($0) }
    }
    private var selectedDeckBracket: CommanderBracket? {
        _ = bracketRevision
        if let included = AIDeckPool.playerDeck(id: selectedDeckID) { return included.bracket }
        if selectedDeckID.hasPrefix("precon:") { return .core }
        guard let report = selectedBracketReport else { return nil }
        return DeckBracketPreference.effective(minimum: report.minimum,
                                               declared: DeckBracketPreference.declared(selectedDeckID, in: MagicMobilePreferences.current))
    }
    private var selectedDeckColors: [String] {
        if let included = AIDeckPool.playerDeck(id: selectedDeckID) { return included.colors.map(String.init) }
        if let precon = PreconCatalog.all.first(where: { "precon:\($0.id)" == selectedDeckID }) { return precon.colors.map(String.init) }
        return DeckStudioDeckColors.colors(for: selectedDeck?.commander.map { [$0.cardName] } ?? []) ?? []
    }
    /// In the match room, deck and name stay editable until the player is ready.
    private var editableInRoom: Bool { setup.multiplayer?.room.map { !$0.localReady } ?? false }

    private var validName: Bool { (try? OnDeviceSetupModel.playerName(playerDisplayName)) != nil }
    private var gameCenterAICount: Int { min(max(0, gameCenterAIStoredCount), max(0, 4 - playerCount)) }
    private var gameCenterAICountBinding: Binding<Int> {
        Binding(get: { gameCenterAICount }, set: { gameCenterAIStoredCount = min(max(0, $0), max(0, 4 - playerCount)) })
    }
    private var gameCenterAIDecks: [DeckList] {
        [aiPreconID, aiPrecon2ID, aiPrecon3ID].prefix(gameCenterAICount)
            .compactMap { id in AIDeckPool.deck(id: id)?.deckList }
    }
    private var mayStart: Bool {
        validName && selectedDeck != nil && (playWithFriends || aiPrecons.count == opponentCount)
            && (!playWithFriends || gameCenterAIDecks.count == gameCenterAICount)
            && setup.identity != nil && !setup.isBusy && !setup.needsLeave
    }
    private var playerMode: Binding<String> {
        Binding(get: { playWithFriends ? (playOnline ? "online" : "gamecenter") : "ai" }, set: { mode in
            playWithFriends = mode != "ai"
            playOnline = mode == "online"
        })
    }

    private var turnControl: NativeTurnControl {
        NativeTurnControl(
            canEndTurn: session.canEndTurn, canSkipResponses: session.canEndTurnSkippingResponses,
            canSkipToMyTurn: session.canSkipToMyTurn, isAutoPassing: session.isAutoPassing,
            status: session.autoPassStatus, endTurn: { session.endTurn() },
            skipResponses: { session.endTurnSkippingResponses() }, skipToMyTurn: { session.skipToMyTurn() },
            stop: { session.stopAutoPass() },
            isFullControl: session.isFullControl, toggleFullControl: { session.toggleFullControl() }
        )
    }

    private var presentedContent: some View {
        // Split in three so the compiler can type-check the long modifier chain in reasonable time.
        let menu = ZStack {
            if activeGame {
                game
                    .environment(\.arenaBoard, BoardMode.resolved(boardMode) == .arena)
            } else {
                BrandTheme.canvas.ignoresSafeArea()
                arenaMenu
            }
        }
        // The roll's own answer to "Select a starting player" stays quiet while it is on its way.
        .startingRollCovered(startingRollVisible || startingChoicePending)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.26), value: showSetup)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.26), value: lobby)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88), value: playPanel)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: activeGame)
        // Menu ambience pauses while anything covers the menu.
        // The profile is a long page of cards scrolling over the room, dimmed: the room holds still under it.
        .environment(\.brandAmbientMotion, !menuSheetOpen && lobby != .profile)
        let social = learningSheets(menu)
        .arenaPanel(isPresented: $showAppearance, maxWidth: 560, fitsContent: true) {
            ArenaOptionsView(portraitModeEnabled: $portraitModeEnabled, upstreamCommit: setup.identity?.upstreamCommit,
                             startPage: optionsStartPage)
        }
        .arenaPanel(isPresented: $showUpdates, placement: .trailing) { NativeUpdateNewsView(upstreamCommit: setup.identity?.upstreamCommit) }
        .arenaPanel(isPresented: $showFriends, placement: .leading) {
            FriendsView(account: account, join: { code in
                // After the sheet closes, so the table setup can open.
                Task { try? await Task.sleep(for: .milliseconds(450)); openJoinLink(code) }
            }, myRankStep: profileRecord.rank.position.step, challenge: { friend, mode in challengeFriend(friend.username, mode: mode) })
        }
        // An Arena prompt, not the system alert (the menus have no iPhone dialogs).
        .arenaPanel(isPresented: $showOfflineArtPrompt, maxWidth: 460, fitsContent: true,
                    onDismiss: { OfflineArtLaunch.markSeen(in: MagicMobilePreferences.current) }) {
            ArenaPromptPanel(title: String(localized: "Play offline with card art?"),
                             message: String(localized: "Card art loads from Scryfall while you're online. Save your decks' images now so they show without a connection too."),
                             primary: String(localized: "Choose downloads"), secondary: String(localized: "Not now"),
                             identifier: "offlineArt") {
                showOfflineArtPrompt = false
                Task { try? await Task.sleep(for: .milliseconds(350)); showDownloads = true }
            }
        }
        .arenaPanel(isPresented: $showDownloads, fitsContent: true) {
            NativeDownloadsView(decks: downloadDecks, selectedDeckID: selectedDeckID,
                                engineReady: setup.identity != nil)
        }
        // A search or a challenge waits in the Play panel (Arena's blade: Play turns into Cancel under a timer).
        .onChange(of: matchmaker.isSearching) { _, searching in if searching { playPanel = true } }
        .onChange(of: activeGame) { _, live in if live { playPanel = false } }
        .onChange(of: challenges.isWaiting) { _, waiting in
            if waiting { playTab = .friends; playPanel = true }
        }
        .overlay(alignment: .top) {
            if menuIsFree, lobby == nil, !challenges.isWaiting, activeMatch == nil,
               let invite = challenges.incoming.first {
                ChallengeInviteBanner(challenge: invite, accept: { acceptChallenge(invite) },
                                      decline: { Task { await challenges.decline(invite) } })
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: challenges.incoming.first?.id)
        .animation(.easeOut(duration: 0.25), value: challenges.isWaiting)
        .overlay {
            if let ceremony {
                RankCeremonyOverlay(change: ceremony) { self.ceremony = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: matchmaker.isSearching)
        .animation(.easeOut(duration: 0.3), value: ceremony)
        .arenaPanel(isPresented: $showBracketSheet, maxWidth: 560, fitsContent: true) { bracketSheet }
        return social
        .overlay(alignment: .bottom) { if !startingRollVisible { recoveryBanner } }
        // The roll belongs to the table: it wears the chosen board's look.
        .overlay { startingRollOverlay.environment(\.arenaBoard, BoardMode.resolved(boardMode) == .arena) }
        // The versus intro plays first, over the opaque starting roll that follows it.
        .overlay {
            if activeGame, let versusIntro {
                VersusIntroOverlay(you: versusIntro.you, opponents: versusIntro.opponents) { self.versusIntro = nil }
                    .transition(.opacity)
            }
        }
        .overlay {
            if !activeGame, let offer = resume.offer {
                GameResumePrompt(offer: offer, resume: resumeSavedGame, abandon: {
                    GameAudio.shared.play(.uiBack)
                    resume.abandon()
                })
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let notice = resume.notice {
                GameResumeNoticeBanner(message: notice) { resume.notice = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: resume.notice)
        .task(id: resume.notice) {
            guard resume.notice != nil else { return }
            do { try await Task.sleep(for: .seconds(GameResumeText.noticeSeconds)) } catch { return }
            resume.notice = nil
        }
        // A player left the table and the others play on (TableLeaveRules); on the menu, the server's notice (AppConfig).
        .overlay(alignment: .top) {
            if activeGame, let notice = setup.multiplayer?.tableNotice {
                GameResumeNoticeBanner(message: notice, symbol: "figure.walk.departure") { setup.multiplayer?.tableNotice = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if !activeGame && !showSetup && lobby == nil && resume.notice == nil {
                AppNoticeBanner()
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: setup.multiplayer?.tableNotice)
        .task(id: setup.multiplayer?.tableNotice) {
            guard setup.multiplayer?.tableNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(GameResumeText.noticeSeconds)) } catch { return }
            setup.multiplayer?.tableNotice = nil
        }
        .modifier(AwardCeremonyHost(account: account, busy: activeGame || showSetup || lobby != nil || ceremony != nil))
        .environment(\.nativeTurnControl, turnControl)
        .arenaPanel(isPresented: $showDiagnostics, fitsContent: true) { diagnosticSheet }
        .background {
            if let multiplayer = setup.multiplayer {
                OnDeviceGameCenterPresentation(multiplayer: multiplayer)
            }
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave game", role: .destructive) { closeGame() }
        } message: {
            Text(setup.multiplayer?.endpoint?.isHost == true
                 ? "You are hosting. Leaving ends this match for everyone; it cannot be resumed."
                 : setup.multiplayer?.endpoint != nil
                 ? "You leave the table and the others play on without you. You can't come back to this game."
                 : "This closes the current match. It cannot be resumed after leaving.")
        }
        // Every menu, sheet and overlay wears the Arena look (the game sets its own board's).
        .environment(\.arenaBoard, true)
        // A friend's profile can join their open table: every page over the menu closes first, then the table setup opens.
        .environment(\.joinFriendTable, { code in
            showFriends = false; lobby = nil; chatProfile = nil
            Task { try? await Task.sleep(for: .milliseconds(450)); openJoinLink(code) }
        })
    }

    /// Decks is the Arena menus' Decks tab (Caleb, 2026-10-22; it was a spell book that opened on the table).
    private func openDecks() {
        guard !showImport else { return }
        playPanel = false
        showImport = true
    }

    private func closeDecks() {
        showImport = false
    }

    /// A join link: open the online table setup with its code and join right away with the
    /// chosen deck. During a game the code waits in the field instead.
    private func openJoinLink(_ code: String) {
        relayJoinCode = code
        guard !activeGame, !setup.needsLeave, setup.multiplayer?.tableCode == nil else {
            bannerError = String(localized: "Finish or leave this game, then join table \(code).")
            return
        }
        playerMode.wrappedValue = "online"
        showSetup = true
        guard setup.identity != nil else { pendingJoinCode = code; return }
        if mayStart, !setup.isBusy, let deck = selectedDeck {
            setup.joinRelay(code: code, name: playerDisplayName, deck: deck)
        }
    }

    /// A sheet or cover is open over the menu (its ambience pauses).
    private var menuSheetOpen: Bool {
        showImport || showAppearance || showUpdates || showDownloads || showDiagnostics || showHowToPlay || showGuidedWelcome || showFriends
    }

    /// How to Play and the first launch's welcome, which can start the guided first game.
    private func learningSheets<Content: View>(_ content: Content) -> some View {
        content
            .arenaPanel(isPresented: $showHowToPlay, fitsContent: true, onDismiss: closeHowToPlay) { howToPlaySheet }
            .arenaPanel(isPresented: $showGuidedWelcome, maxWidth: 560, dismissable: false, fitsContent: true) {
                GuidedGameWelcomeView(playGuided: { playGuidedFromWelcome() },
                                      readHowToPlay: { readHowToPlayFromWelcome() },
                                      skip: { answerGuidedWelcome() })
            }
    }

    /// The first visit opens straight into the table's tutorial; the menu offers both.
    private var howToPlaySheet: HowToPlayView {
        if howToPlayOpensTable {
            return HowToPlayView(tutorialID: HowToPlayText.tutorials[0].id, playGuided: nil)
        }
        return HowToPlayView(tutorialID: nil, playGuided: { startGuidedGame() }, playLesson: { startLesson($0) })
    }

    private func closeHowToPlay() {
        HowToPlayLaunch.markSeen(in: MagicMobilePreferences.current)
        howToPlayOpensTable = false
    }

    /// The main menu is showing with nothing over it (no game, setup, saved-game offer or sheet).
    private var menuIsFree: Bool {
        !activeGame && !showSetup && !setup.needsLeave && resume.offer == nil && !startingRollVisible
            && !menuSheetOpen
    }

    /// First visit to the menu after this update: the walkthrough opens once by itself.
    private func showHowToPlayIfFirstLaunch() async {
        do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
        guard menuIsFree else { return }
        if GuidedGameLaunch.shouldShowWelcome(defaults: MagicMobilePreferences.current) {
            showGuidedWelcome = true
        } else if HowToPlayLaunch.shouldShowAutomatically(defaults: MagicMobilePreferences.current) {
            howToPlayOpensTable = true
            showHowToPlay = true
        } else if OfflineArtLaunch.shouldShowAutomatically(defaults: MagicMobilePreferences.current) {
            showOfflineArtPrompt = true
        }
    }

    private func preparePresentation() async {
        MagicMobileOrientationController.shared.setPortraitModeEnabled(portraitModeEnabled)
        restoreSetupPreferences()
        setup.prepare()
        evaluateResumeLaunch()
        setup.setSceneActive(scenePhase == .active)
        #if DEBUG
        if OnDeviceAppConfiguration.entryPoint == .setupPreview,
           ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_ENGINE_ERROR"] == "1" {
            try? diagnostics.save(engineReport: "UI TEST FIXTURE: Sample engine incident", status: "Presentation test")
            setup.errorMessage = "UI test fixture: engine incident."
        }
        // UI tests and screenshots: MAGICMOBILE_UI_TEST_LESSON=<id> opens that lesson; it needs no engine.
        if OnDeviceAppConfiguration.entryPoint == .setupPreview,
           let lesson = ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_LESSON"] {
            startLesson(lesson)
        }
        // UI tests: MAGICMOBILE_UI_TEST_CEREMONY=tierUp|tierDown|divisionUp|divisionDown plays a rank moment.
        if OnDeviceAppConfiguration.entryPoint == .setupPreview,
           let kind = ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_CEREMONY"] {
            let samples: [String: (RankPosition, RankPosition, RankOutcome)] = [
                "tierUp": (RankPosition(tier: .silver, division: 1, pips: 3), RankPosition(tier: .gold, division: 4, pips: 0), .win),
                "tierDown": (RankPosition(tier: .gold, division: 4, pips: 0), RankPosition(tier: .silver, division: 1, pips: 3), .loss),
                "divisionUp": (RankPosition(tier: .diamond, division: 3, pips: 3), RankPosition(tier: .diamond, division: 2, pips: 0), .win),
                "divisionDown": (RankPosition(tier: .platinum, division: 2, pips: 0), RankPosition(tier: .platinum, division: 3, pips: 3), .loss)]
            if let (before, after, outcome) = samples[kind] {
                ceremony = RankChange(outcome: outcome, before: before, after: after, bonuses: [])
            }
        }
        #endif
    }

    /// The presented content with deck sync, preferences and the app's comings and goings (split from lifecycleContent
    /// to keep each modifier chain inside the type checker's budget).
    private var syncedContent: some View {
        presentedContent.holdInspectionScope().task { await preparePresentation() }
        .onChange(of: library.decks.map(\.id)) { _, _ in
            if !activeGame { restoreSetupPreferences() }
        }
        .task(id: library.decks.map(\.id)) { await rememberDeckColors() }
        // Deck sync: when the account is ready or its name changes, on coming back to the app and every 5 minutes while open.
        .task(id: "\(account.phase == .ready)|\(account.username ?? "")|\(scenePhase == .active)") {
            guard account.phase == .ready, scenePhase == .active else { return }
            while !Task.isCancelled {
                await syncDecks()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        // A change here goes up a few seconds after the last one, when something waits to go up.
        .task(id: library.decks) {
            // The first run (on appearance) also makes the sync, which then notes the player's deletes.
            let sync = deckSyncer()
            guard account.phase == .ready, sync.hasPendingChanges else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { await syncDecks() }
        }
        // Cards drawn by name (the board, the opening hand, profile art) show the art chosen in the playing deck first.
        .onChange(of: selectedDeckID, initial: true) { _, id in CardArtChoices.shared.select(deckID: id) }
        .onChange(of: portraitModeEnabled) { _, enabled in
            MagicMobileOrientationController.shared.setPortraitModeEnabled(enabled)
        }
        .onChange(of: scenePhase) { previous, phase in
            setup.setSceneActive(phase == .active)
            // Leaving: the app switcher (from which the app may be closed) or on to the background.
            if previous == .active, phase == .inactive { resume.willLeave() }
            if phase == .background { resume.enteredBackground() }
            if phase == .active { resume.enteredForeground(); GameAudio.shared.resume() }
            account.setForeground(phase == .active)
            MainThreadWatchdog.shared.setPaused(phase != .active)
        }
        .onAppear { if scenePhase == .active { account.setForeground(true) } }
        // Each engine match's start, for the game's length on the profile.
        .onChange(of: session.matchID) { _, id in gameStartedAt = id == nil ? nil : Date() }
    }

    private var lifecycleContent: some View {
        syncedContent
        // Freeze log (docs/FREEZE_LOG.md): what the game is, the ranked search's steps, and last session's freeze.
        .onChange(of: activeMatch, initial: true) { _, match in
            session.freezeMode = match.map { "\($0.mode.rawValue)\($0.opponents.contains { $0.isAI } ? " vs AI" : " vs people")" }
                ?? (setup.usingMultiplayer ? "table" : "custom")
        }
        .onChange(of: matchmaker.phase) { _, phase in
            switch phase {
            case .idle: FreezeLog.shared.note("Ranked search: idle")
            case .searching: FreezeLog.shared.note("Ranked search: looking for a player")
            case .matched: FreezeLog.shared.note("Ranked search: matched with a player")
            }
        }
        .task(id: account.phase == .ready) {
            // The server's settings for this build (AppConfig): the menu's notice, name fixes, feature switches.
            await account.refreshAppConfig()
            guard account.phase == .ready, !activeGame, freezePrompt == nil,
                  ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PREFERENCES"] == nil else { return }
            let now = Date().timeIntervalSince1970
            let asked = UserDefaults.standard.object(forKey: FreezeLog.askedAtKey) as? Double
            guard FreezeRules.mayAsk(secondsSinceAsked: asked.map { now - $0 }), let incident = FreezeLog.shared.unsent else { return }
            UserDefaults.standard.set(now, forKey: FreezeLog.askedAtKey)
            freezePrompt = incident
        }
        .tavernConfirmation(active: true, title: "The last game froze",
                            message: "Send the report? It holds the game's state and your recent actions, not your account or decks.",
                            isPresented: Binding(get: { freezePrompt != nil && !activeGame }, set: { if !$0 { freezePrompt = nil } }),
                            actions: [TavernDialogAction(title: "Send") {
                                guard let incident = freezePrompt else { return }
                                freezePrompt = nil
                                Task { await sendFreezeReport(incident) }
                            }],
                            cancelTitle: "Not now",
                            onCancel: { if let incident = freezePrompt { FreezeLog.shared.dismiss(incident.id) }; freezePrompt = nil })
        .tavernConfirmation(active: true, title: freezeResult ?? "", message: nil,
                            isPresented: Binding(get: { freezeResult != nil }, set: { if !$0 { freezeResult = nil } }),
                            actions: [], cancelTitle: "OK", onCancel: { freezeResult = nil })
        #if DEBUG
        // Development fixtures (SocialFixtures): open the profile or the friends sheet at launch.
        .task {
            switch SocialFixtures.openScreen?.split(separator: ":").first.map(String.init) {
            case "profile": lobby = .profile
            case "rankedHall": lobby = .rankedHall
            case "leaderboard": lobby = .leaderboard
            case "play": openPlayPanel(.quick)
            case "play-cycle":
                // The deck boxes opening and shutting, for a screen recording.
                openPlayPanel()
                let first = selectedDeckID
                for next in ["precon:\(PreconCatalog.all[1].id)", "precon:\(PreconCatalog.all[3].id)", first] {
                    try? await Task.sleep(for: .seconds(2.5))
                    selectedDeckID = next
                }
            case "play-ranked", "queue": openPlayPanel(.ranked)
            case "play-custom": openPlayPanel(.custom)
            case "play-friends": playTab = .friends; playPanel = true
            case "play-recent": playTab = .recent; playPanel = true
            case "decks", "deck": openDecks()
            case "custom": showSetup = true
            case "settings":
                optionsStartPage = SocialFixtures.openScreen?.split(separator: ":").dropFirst().first.flatMap { ArenaOptionsView.Page(rawValue: String($0)) }
                showAppearance = true
            case "learn-table": howToPlayOpensTable = true; showHowToPlay = true
            case "updates": showUpdates = true
            case "downloads": showDownloads = true
            case "learn": showHowToPlay = true
            case "friends", "public", "search", "messages", "conversation": showFriends = true
            default: break
            }
        }
        #endif
        // The profile name is the name at every table.
        .onChange(of: account.username) { _, name in if let name { playerDisplayName = name } }
        // Friends see the table this phone hosts while it has open seats.
        .onChange(of: setup.multiplayer?.openHostedTable.map { "\($0.code):\($0.openSeats)" }) { _, _ in
            // A ranked or challenge table is for that one player only, never shown to friends.
            account.hosting = activeMatch?.isPersonTable != true ? setup.multiplayer?.openHostedTable : nil
        }
        .onChange(of: setup.identity) { _, _ in
            evaluateResumeLaunch()
            if let code = pendingJoinCode { pendingJoinCode = nil; openJoinLink(code) }
        }
        .onOpenURL { url in if let code = TableJoinLink.code(from: url) { openJoinLink(code) } }
        .onChange(of: session.snapshot?.turn) { _, turn in GamePerformanceLog.shared.noteTurn(turn) }
        // Memory warnings free the caches that reload by themselves (not the sounds or music, which would cut out).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            GamePerformanceLog.shared.noteMemoryWarning()
            NativeDeckArtwork.purgeMemoryCaches()
            NativeArtworkMemory.shared.purge()
            NativeDeckMetadataCatalogue.purgeShared()
        }
        .task(id: menuIsFree) { if menuIsFree { await showHowToPlayIfFirstLaunch() } }
        // Friends' challenges arrive while the menu or lobby is open (never during a game).
        .task(id: watchesChallenges) {
            guard watchesChallenges else { return }
            challenges.service = account.challenges
            await challenges.watch(friendOnline: { [account] in account.onlineFriendCount > 0 })
        }
        .onAppear { GameAudio.shared.setScene(activeGame ? .game : .menu) }
        .onChange(of: activeGame) { _, playing in
            GameAudio.shared.setScene(playing ? .game : .menu)
            session.comboLoopsAllowed = playing && !setup.usingMultiplayer
            updateDevicePace()
            if playing {
                GamePerformanceLog.shared.begin(mode: activeMatch?.mode.rawValue ?? (setup.usingMultiplayer ? "online" : "custom"),
                                                aiSkill: activeMatch?.aiSkill)
            } else {
                GamePerformanceLog.shared.end()
            }
            if playing { matchmaker.finish(); rankedConnectTask?.cancel() }
            guard playing else { versusIntro = nil; return }
            if skipNextVersusIntro { skipNextVersusIntro = false; return }
            if reduceMotion {
                GameAudio.shared.play(.versus, after: 0.2)
            } else {
                versusIntro = makeVersusIntro()
                GameAudio.shared.play(.versus, after: 0.05)
            }
        }
        .onChange(of: session.errorMessage) { _, message in
            if message != nil { Task { await setup.captureDiagnostics(in: diagnostics) } }
        }
        .onChange(of: setup.errorMessage) { _, message in
            if message != nil { Task { await setup.captureDiagnostics(in: diagnostics) } }
        }
        .task(id: setup.errorMessage ?? session.errorMessage) {
            bannerError = setup.errorMessage ?? session.errorMessage
            guard bannerError != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            bannerError = nil
        }
    }

    var body: some View {
        lifecycleContent
        .onChange(of: setup.multiplayer?.isConnected) { _, _ in setup.updateSessionForeground() }
        .onChange(of: setup.multiplayer?.isSuspended) { _, _ in setup.updateSessionForeground() }
        .onChange(of: setup.multiplayer?.endpoint?.matchID) { _, matchID in
            if matchID != nil { Task { await setup.attachMultiplayer(deckID: selectedDeckID, deck: selectedDeck) } }
            syncVoiceRoom()
        }
        .onChange(of: session.snapshot?.bridgeRevision) { _, _ in
            refreshInspections()
            prepareAIRollIfNeeded()
        }
        .onChange(of: session.snapshot?.promptEnvelopeV2?.id) { _, _ in
            prepareAIRollIfNeeded()
            submitStartingChoiceIfNeeded()
        }
        .onChange(of: session.isWorking) { _, working in
            if !working { submitStartingChoiceIfNeeded() }
        }
        .onChange(of: session.snapshot?.isCompleted) { _, _ in recordFinishedGameIfNeeded() }
        .onChange(of: session.isOverForSeat) { _, _ in recordFinishedGameIfNeeded() }
        // A ranked or challenge table readies both players by itself once the room forms.
        .onChange(of: setup.multiplayer?.room != nil) { _, hasRoom in
            guard hasRoom, activeMatch?.isPersonTable == true, setup.multiplayer?.room?.localReady == false,
                  let deck = selectedDeck else { return }
            setup.readyForMatch(name: playerDisplayName, deck: deck)
        }
        .onAppear {
            profileRecord.publish = { [account] rank, stats, title, commander in
                Task { await account.publishRank(rank, stats: stats, title: title, commander: commander) }
            }
            // Finished games go to the profile server too: now, and again whenever the app is open and online.
            let upload: () async -> Void = { [account, profileRecord] in
                await GameUploader.shared.flush(matches: profileRecord.matches) { await account.recordGame($0) }
            }
            // A ranked game goes up after its result counts on the server, which records its rank points then.
            profileRecord.didRecord = { match in if match.mode != .ranked { Task { await upload() } } }
            account.afterRefresh = { [account, profileRecord] in
                await account.syncRank(profileRecord)
                await upload()
            }
        }
        .onChange(of: setup.isBusy) { _, busy in
            if !busy { submitStartingChoiceIfNeeded() }
        }
        .onChange(of: setup.multiplayer?.startingRoll) { _, _ in
            didDismissStartingRoll = false
            attemptedStartingPromptID = nil
            startingChoiceFailedPromptID = nil
        }
        .onChange(of: setup.multiplayer?.rollProgress?.isComplete) { _, _ in submitStartingChoiceIfNeeded() }
        .onChange(of: session.matchID) { _, _ in
            // A table's roll outlives the session attaching to its match; resetting it here
            // replayed a finished roll. Tables reset on a new roll instead (below).
            if !setup.usingMultiplayer {
                didDismissStartingRoll = false
                attemptedStartingPromptID = nil
            }
            aiStartingRoll = nil
            aiRevealedRollCount = 0
            aiRollSeatNames = [:]
            prepareAIRollIfNeeded()
        }
    }

    private func refreshInspections() {
        guard let snapshot = session.snapshot else { zone = nil; inspectedCard = nil; return }
        let cards = PortraitInteractionPolicy.authorizedCards(snapshot)
        // Unscoped legacy callbacks must reopen after a state change rather than
        // keep a moved card under a stale zone heading. The board uses exact refs.
        zone = nil
        if let current = inspectedCard { inspectedCard = cards.first { $0.id == current.id } }
    }

    /// A Game Center table's shared roll (or its "Who goes first?" panel) is up.
    private var multiplayerRollVisible: Bool {
        guard setup.usingMultiplayer, let multiplayer = setup.multiplayer else { return false }
        return multiplayer.endpoint != nil && multiplayer.isConnected && !didDismissStartingRoll
    }

    /// Who goes first in this AI game: Ranked always rolls, other games follow the player's choice.
    private var startingPlayerMode: String {
        activeMatch?.mode.startingPlayerMode(preference: aiStartingPlayerMode) ?? aiStartingPlayerMode
    }

    /// An AI table's local roll is up.
    private var aiRollVisible: Bool {
        !setup.usingMultiplayer && session.matchID != nil && startingPlayerMode == "roll"
            && aiStartingRoll != nil && !didDismissStartingRoll
    }

    /// One flag for everything the starting roll covers (StartingRollCover, startingRollCovered).
    private var startingRollVisible: Bool { multiplayerRollVisible || aiRollVisible }

    @ViewBuilder
    private var startingRollOverlay: some View {
        if startingRollVisible {
            StartingRollCover {
                GeometryReader { proxy in
                    startingRollContent
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                // A roll error stays readable, and dismissible, on the opaque cover.
                if bannerError != nil {
                    VStack { Spacer(minLength: 0); recoveryBanner }
                }
            }
        }
    }

    @ViewBuilder
    private var startingRollContent: some View {
        if multiplayerRollVisible, let multiplayer = setup.multiplayer {
            if let roll = multiplayer.startingRoll {
                MultiplayerD20View(roll: roll, seatNames: multiplayer.seatNames,
                                   isLocalWinner: roll.winnerSeatID == multiplayer.endpoint?.seatID,
                                   revealedStepCount: multiplayer.rollProgress?.revealedCount ?? 0,
                                   localSeatID: multiplayer.endpoint?.seatID,
                                   rollPending: multiplayer.hasRolled,
                                   onRollTap: {
                                       do { try multiplayer.rollStartingPlayer() }
                                       catch { bannerError = error.localizedDescription }
                                   }, onStepPlayed: {
                                       do { try multiplayer.advanceAISeatIfNeeded() }
                                       catch { bannerError = error.localizedDescription }
                                   }) {
                    didDismissStartingRoll = true
                    submitStartingChoiceIfNeeded()
                }
            } else {
                // Until the host shares the dice: the same leather and brass the roll itself wears; dark glass and one
                // line of status on the Arena board.
                let arena = BoardMode.resolved(boardMode) == .arena
                VStack(spacing: 14) {
                    Text("Who goes first?")
                        .font(arena ? ArenaMenuStyle.title(26, .bold) : .system(.title2, design: .serif, weight: .heavy))
                        .foregroundStyle(Color(red: 0.98, green: 0.92, blue: 0.80))
                        .shadow(color: .black.opacity(0.7), radius: 0, y: 1)
                    Text(multiplayer.rollStatus)
                        .font(arena ? ArenaMenuStyle.font(14, .medium) : .system(.subheadline, design: .serif, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(arena ? ArenaGlass.text.opacity(0.8) : Color(red: 0.84, green: 0.72, blue: 0.52))
                    if !arena || multiplayer.hostAISeatSummary != nil {
                        Text(multiplayer.hostAISeatSummary ?? "Each player rolls a D20. Highest starts; ties reroll.")
                            .font(arena ? ArenaMenuStyle.font(12, .regular) : .system(.caption, design: .serif)).multilineTextAlignment(.center)
                            .foregroundStyle(arena ? ArenaGlass.text.opacity(0.7) : Color(red: 0.84, green: 0.72, blue: 0.52))
                    }
                    Button(multiplayer.hasRolled ? "Waiting for other players…" : "Roll D20") {
                        do { try multiplayer.rollStartingPlayer() }
                        catch { bannerError = error.localizedDescription }
                    }
                    .buttonStyle(ArenaButtonStyle(kind: .primary, fontSize: 17, fullWidth: true))
                    .disabled(multiplayer.hasRolled)
                    .accessibilityIdentifier("ondevice.multiplayer.roll")
                }
                .padding(24)
                .frame(maxWidth: 440)
                .background {
                    if arena {
                        RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                    } else {
                        TavernFill(material: .leather).clipShape(RoundedRectangle(cornerRadius: 14)).padding(2)
                            .overlay { TavernBrassFrame() }
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                .padding(.horizontal, 16)
            }
        } else if let roll = aiStartingRoll {
            MultiplayerD20View(roll: roll, seatNames: aiRollSeatNames,
                               isLocalWinner: roll.winnerSeatID == session.snapshot?.viewerID,
                               revealedStepCount: aiRevealedRollCount,
                               localSeatID: session.snapshot?.viewerID,
                               onRollTap: advanceLocalAIRoll,
                               onStepPlayed: advanceAIRollIfNeeded) {
                didDismissStartingRoll = true
                submitStartingChoiceIfNeeded()
            }
        }
    }

    private func prepareAIRollIfNeeded() {
        guard !setup.usingMultiplayer,
              startingPlayerMode == "roll", session.matchID != nil,
              aiStartingRoll == nil, !didDismissStartingRoll,
              let snapshot = session.snapshot,
              let targetIDs = OnDeviceStartingPlayerChoice.candidateIDs(snapshot: snapshot) else { return }
        do {
            let viewerFirst = [snapshot.viewerID] + targetIDs.filter { $0 != snapshot.viewerID }
            aiStartingRoll = try OnDeviceStartingRoll.generate(seatIDs: viewerFirst)
            aiRevealedRollCount = 0
            aiRollSeatNames = Dictionary(uniqueKeysWithValues: snapshot.players.map {
                ($0.playerId, $0.playerId == snapshot.viewerID ? "You" : ($0.displayName ?? "AI opponent"))
            })
            advanceAIRollIfNeeded()
        } catch {
            bannerError = "Could not roll for the starting player: \(error.localizedDescription)"
        }
    }

    private func advanceLocalAIRoll() {
        guard let roll = aiStartingRoll, let viewerID = session.snapshot?.viewerID,
              roll.steps.indices.contains(aiRevealedRollCount),
              roll.steps[aiRevealedRollCount].seatID == viewerID else { return }
        aiRevealedRollCount += 1
    }

    private func advanceAIRollIfNeeded() {
        guard let roll = aiStartingRoll, let viewerID = session.snapshot?.viewerID,
              roll.steps.indices.contains(aiRevealedRollCount),
              roll.steps[aiRevealedRollCount].seatID != viewerID else { return }
        let expectedCount = aiRevealedRollCount
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, session.matchID != nil, aiStartingRoll == roll,
                  aiRevealedRollCount == expectedCount, !didDismissStartingRoll else { return }
            aiRevealedRollCount += 1
        }
    }

    /// The engine's "starting player" answer for the roll's winner, if this is that prompt.
    private func startingChoice(for snapshot: GameSnapshot) -> (command: GameCommand, winnerName: String)? {
        if setup.usingMultiplayer, let multiplayer = setup.multiplayer,
           let roll = multiplayer.startingRoll,
           let name = multiplayer.seatNames[roll.winnerSeatID] {
            return OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerName: name).map { ($0, name) }
        } else if !setup.usingMultiplayer, startingPlayerMode == "roll", let roll = aiStartingRoll {
            return OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerPlayerID: roll.winnerSeatID)
                .map { ($0, aiRollSeatNames[roll.winnerSeatID] ?? "winner") }
        }
        return nil
    }

    /// The table answers as soon as every die is shown (the host is the one XMage asks);
    /// an AI game answers when the player closes the roll.
    private func submitStartingChoiceIfNeeded() {
        let tableRollShown = setup.usingMultiplayer && setup.multiplayer?.rollProgress?.isComplete == true
        guard didDismissStartingRoll || tableRollShown,
              let snapshot = session.snapshot,
              let promptID = snapshot.promptEnvelopeV2?.id,
              attemptedStartingPromptID != promptID,
              startingChoice(for: snapshot) != nil else { return }
        attemptedStartingPromptID = promptID
        Task { @MainActor in
            // An automatic reply is never dropped: a busy session, a paused table or a stale
            // snapshot only delays it. A new prompt means it went through.
            for attempt in 0..<12 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(min(250 * attempt, 1500))) }
                guard attemptedStartingPromptID == promptID,
                      let current = session.snapshot, current.promptEnvelopeV2?.id == promptID else { return }
                guard !setup.isBusy, !session.isWorking, setup.canUseSession,
                      let choice = startingChoice(for: current) else { continue }
                do {
                    try await session.send(choice.command, label: "Start with \(choice.winnerName)",
                                           actionID: "starting-roll-\(promptID)")
                    return
                } catch { continue }
            }
            guard attemptedStartingPromptID == promptID, session.snapshot?.promptEnvelopeV2?.id == promptID else { return }
            startingChoiceFailedPromptID = promptID
            setup.errorMessage = String(localized: "The roll's winner couldn't be sent. Choose the starting player.")
        }
    }

    /// The roll's automatic answer is on its way, so the board hides the prompt it answers.
    private var startingChoicePending: Bool {
        guard let snapshot = session.snapshot, let promptID = snapshot.promptEnvelopeV2?.id,
              startingChoiceFailedPromptID != promptID,
              OnDeviceStartingPlayerChoice.candidateIDs(snapshot: snapshot) != nil else { return false }
        return setup.usingMultiplayer ? setup.multiplayer?.startingRoll != nil
            : (startingPlayerMode == "roll" && aiStartingRoll != nil)
    }

    private var game: some View {
        ImmersivePlayShell(
            // While a combo loop repeats, the board shows its quiet copy: no flickering prompts.
            snapshot: session.presentedSnapshot,
            selectedCard: $selectedCard, inspectedCard: $inspectedCard,
            playerDisplayName: playerDisplayName, avatarData: nil,
            pendingActionId: session.pendingActionID, pendingCardInstanceId: session.pendingCardID,
            lastActionRejection: nil,
            commandFailure: CardChoiceCommandFailure(setup.errorMessage ?? session.errorMessage,
                source: setup.errorMessage != nil ? .setup : .session),
            liveUpdateStatus: setup.liveStatus,
            onInteractionFeedback: { setup.feedback = $0 },
            runAction: { action in
                if action.type == "mulligan" { GameAudio.shared.play(.shuffle) }
                Task { await setup.perform { try await session.send(action: action) } }
            },
            runCommand: { command, label, id in
                Task {
                    // A card plan answers XMage's next one-card prompt as soon as it lands,
                    // while the previous answer's refresh is still finishing.
                    if id.hasPrefix("card-plan-") { await setup.waitUntilSessionIdle() }
                    await setup.perform(reportingBusy: id.hasPrefix("card-plan-")) {
                        try await session.send(command, label: label, actionID: id)
                    }
                }
            },
            refreshGame: refresh, reconnectGame: refresh,
            checkBridgeHealth: { setup.localHealth() },
            newGame: rematchOrLeave, quitGame: leaveFinishedOrAsk,
            loadProtocolDebug: { _ in
                throw EngineError.invalidMessage("Protocol debug export is not available for this on-device session.")
            },
            portraitModeEnabled: $portraitModeEnabled,
            viewZone: { title, cards in zone = InspectedZone(title: title, cards: cards) }
        )
        // The online turn timer's ring around the pass button; solo games have no clock.
        .environment(\.turnClockFeed, setup.usingMultiplayer ? setup.multiplayer?.clockFeed : nil)
        .overlay { zoneOverlay }
        .overlay(alignment: .top) {
            if guidedGame, let guidedTip {
                GuidedGameCoachCard(tip: guidedTip, dismiss: { self.guidedTip = nil }, turnOff: { endGuidedTips() })
                    .environment(\.arenaBoard, BoardMode.resolved(boardMode) == .arena)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: guidedTip)
        .onReceive(session.$snapshot) { snapshot in advanceGuidedTip(snapshot) }
        .overlay(alignment: .top) {
            // A lesson that ends in a win hands over to the result screen, whose button goes on to the next lesson.
            if let lessonRun, session.snapshot?.isCompleted != true {
                LessonCoachCard(run: lessonRun, nextTitle: LessonCatalog.next(after: lessonRun.script.id) == nil ? LessonText.guided : LessonText.next,
                                next: { nextLesson() }, done: { finishLesson() })
                    .environment(\.arenaBoard, BoardMode.resolved(boardMode) == .arena)
                    .padding(.top, 6)
            }
        }
        .modifier(LessonFocusIfAny(run: lessonRun))
        .environment(\.inspectorBattlefield, session.snapshot?.visibleBattlefield ?? [])
        .disabled(setup.isBusy)
        .environment(\.gameRematchTitle, lessonRun.map { LessonCatalog.next(after: $0.script.id) == nil ? LessonText.guided : LessonText.next }
                     ?? (setup.usingMultiplayer ? nil
                     : activeMatch?.mode == .quick ? String(localized: "Play Again")
                     : activeMatch?.mode == .ranked ? String(localized: "Next Match") : "Rematch"))
        .environment(\.gameRankChange, rankChange)
        .environment(\.gameRankNote, rankNote)
        .environment(\.boardAnswerActions, BoardAnswerActions(
            supported: session.supportedAnswerActions, rememberedAnswers: session.rememberedAnswers,
            rememberedTriggerOrders: session.rememberedTriggerOrders,
            forgetAnswers: { session.forgetRememberedAnswers() }, forgetTriggerOrder: { session.forgetTriggerOrder() }))
        .onChange(of: autoPassAfterCast) { _, enabled in session.setAutoPassAfterCast(enabled) }
        .onReceive(DeviceHeat.shared.$thermal) { _ in updateDevicePace() }
        .onChange(of: smartAutoPass) { _, _ in session.setSmartPass(.load()) }
        .onChange(of: phaseStops) { _, _ in session.setSmartPass(.load()) }
        .onChange(of: stopForOwnSpells) { _, _ in session.setSmartPass(.load()) }
        .onChange(of: stopForThreats) { _, _ in session.setSmartPass(.load()) }
        .environment(\.gameConcede, GameConcedeHandler(concede: concede))
        .environment(\.gameFreezeReport, GameFreezeReportHandler(report: reportFreezeNow))
        .environment(\.emoteCenter, emotes)
        .environment(\.voiceRoom, voiceRoom)
        // Messages from friends inside a game too: the game menu's Messages button, and a banner for a new one.
        .environment(\.friendMessages, account.phase == .ready && account.username != nil && account.messagesAvailable
                     ? FriendMessagesEntry(unread: account.unreadMessages, hub: { [account] in AnyView(FriendMessagesHub(account: account)) })
                     : nil)
        .overlay(alignment: .top) {
            if let banner = messageBanner {
                FriendMessageBanner(name: banner.name, text: banner.text,
                                    open: { messageBanner = nil; messagesHub = MessagesHubTarget(name: banner.name) },
                                    dismiss: { messageBanner = nil })
                    .padding(.horizontal, 16).padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner.id) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        if messageBanner?.id == banner.id { withAnimation { messageBanner = nil } }
                    }
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.25), value: messageBanner?.id)
        // The combo loop shortcut (solo games): the offer, the repeats and their result.
        .overlay(alignment: .top) { ComboLoopOverlay(session: session) }
        .sheet(item: $messagesHub) { target in FriendMessagesHub(account: account, initial: target.name) }
        // Checked more often during a game than the menu's heartbeat, so a friend's message shows within seconds.
        .task(id: activeGame && account.messagesAvailable) {
            guard activeGame, account.messagesAvailable else { return }
            var seen = account.unreadMessages
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard UIApplication.shared.applicationState == .active else { continue }
                await account.refreshUnread()
                if account.unreadMessages > seen, messagesHub == nil,
                   let newest = await account.conversations()?.first(where: { $0.unread > 0 && !$0.last.fromMe }) {
                    withAnimation { messageBanner = MessageBannerItem(name: newest.username, text: FriendMessageRules.shown(newest.last)) }
                }
                seen = account.unreadMessages
            }
        }
        .sheet(isPresented: $emotes.isChatOpen) {
            TableChatPanel(center: emotes, snapshot: session.snapshot,
                           report: account.phase == .ready ? { line in
                               Task { await account.report(line.name, message: line.text, context: "chat") }
                           } : nil,
                           block: account.phase == .ready ? { name in
                               emotes.mute(name)
                               Task { await account.block(name) }
                           } : nil,
                           viewProfile: account.phase == .ready ? { name in chatProfile = ChatProfileTarget(name: name) } : nil)
                .fullScreenCover(item: $chatProfile) { target in
                    PublicProfileView(account: account, username: target.name) { chatProfile = nil }
                }
                .presentationDetents([.medium, .large])
        }
        .onAppear { connectEmotes() }
        .onChange(of: session.snapshot?.id) { _, _ in emotes.reset(); connectEmotes() }
    }

    /// Voice chat (VoiceRoom; docs/VOICE_CHAT.md): one room per online game once it has its channel and the server's
    /// voiceChat switch is on. Nobody is in voice until they tap the mic; leaving the game leaves the channel.
    private func syncVoiceRoom() {
        let multiplayer = setup.usingMultiplayer ? setup.multiplayer : nil
        let channel = multiplayer?.voiceChannel
        let seat = VoiceChatRules.account(seat: multiplayer?.endpoint?.seatID)
        let on = AppConfigStore.shared.current.isOn(VoiceChatRules.switchName, default: false)
        if let room = voiceRoom, on, room.channel == channel, room.account == seat { return }
        voiceRoom?.close()
        voiceRoom = nil
        guard on, let channel, let seat else { return }
        let room = VoiceRoom(channel: channel, account: seat) { [account] channel, seat in
            try await account.voiceToken(channel: channel, account: seat)
        }
        room.table = multiplayer
        voiceRoom = room
    }

    /// Game Center games carry quick chat between devices; solo games only answer from the AI.
    private func connectEmotes() {
        let multiplayer = setup.usingMultiplayer ? setup.multiplayer : nil
        emotes.send = multiplayer.map { match in { emote in match.sendEmote(emote) } }
        multiplayer?.onEmote = { [weak emotes = self.emotes, weak session = self.session] name, emote in
            emotes?.receive(emote, fromName: name, in: session?.snapshot)
        }
        emotes.sendText = multiplayer.map { match in { text in match.sendChat(text) } }
        account.blocked.forEach(emotes.mute)
        multiplayer?.onChat = { [weak emotes = self.emotes] name, text in emotes?.receive(text: text, fromName: name) }
    }

    /// XMage records the loss. In a pod the others play on and you can watch.
    private func concede() {
        Task {
            do {
                try await session.concede()
                resume.gameFinished()
            } catch let EngineError.rejected(code, _) where code == "unknown_operation" || code == "concede_unavailable" {
                // An engine from before concede existed: leaving the match is the forfeit.
                showSetup = false
                closeGame()
            } catch {
                setup.errorMessage = error.localizedDescription
            }
        }
    }

    /// After a solo game: close it and start again with the same deck, opponents and
    /// settings, no confirmation. During a game (or with other players) this still asks.
    private func rematchOrLeave() {
        guard session.snapshot?.isCompleted == true, !setup.usingMultiplayer else { return requestLeave() }
        let mode = activeMatch?.mode
        let guided = guidedGame
        if lessonRun != nil { return nextLesson() }
        Task {
            guard await setup.close() else { return }
            if guided { return startGuidedGame() }
            selectedCard = nil; inspectedCard = nil; zone = nil
            activeMatch = nil; rankChange = nil; rankNote = nil
            // Quick Match deals a new opponent; Ranked looks for the next match.
            switch mode {
            case .quick: startQuickMatch()
            case .ranked: openPlayPanel(.ranked); findRankedMatch()
            default: startAI()
            }
        }
    }

    /// A finished game closes straight to the main menu; a live one still asks first.
    private func leaveFinishedOrAsk() {
        // Solo games you already conceded leave at once; a host still warns the table.
        let spectatingSolo = session.snapshot?.isSpectating == true && !setup.usingMultiplayer
        guard session.snapshot?.isCompleted == true || spectatingSolo else { return requestLeave() }
        showSetup = false
        closeGame()
    }

    // The shell owns its normal board inspections. Its external zone callback (for
    // secondary details) uses the same inspector components and geometry here.
    @ViewBuilder
    private var zoneOverlay: some View {
        if let zone {
            GeometryReader { proxy in
                let rect = GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled)
                    ? PortraitBattlefieldLayoutMetrics(proxy: proxy).detailSheetRect
                    : BattlefieldLayoutMetrics(proxy: proxy).detailSheetRect
                CompactZoneInspectorOverlay(
                    title: zone.title, cards: zone.cards, legalActions: session.snapshot?.legalActions ?? [],
                    pendingActionId: session.pendingActionID, selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                    runAction: { action in Task { await setup.perform { try await session.send(action: action) } } },
                    closeAction: { self.zone = nil }
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                if let inspectedCard {
                    Color.black.opacity(0.01).ignoresSafeArea().onTapGesture { self.inspectedCard = nil }
                        .inspectionTouchPassthrough()
                    CardInspector(card: inspectedCard)
                        .inspectionTouchPassthrough()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    // MARK: - Quick Match, Ranked, profile

    @ViewBuilder
    private func lobbyContent(_ screen: LobbyScreen) -> some View {
        switch screen {
        case .rankedHall:
            RankedHallView(account: account, rank: profileRecord.rank, play: { openPlayPanel(.ranked) }, leaderboard: { lobby = .leaderboard },
                           profile: { lobby = .profile }, back: { lobby = nil })
        case .leaderboard:
            RankedLeaderboardView(account: account, back: { lobby = .rankedHall })
        case .profile:
            PlayerProfileView(record: profileRecord, account: account, playerName: account.username ?? playerDisplayName,
                              deckCommanders: library.decks.compactMap { $0.deckList.commander?.cardName } + AIDeckPool.all.map(\.commander),
                              back: { lobby = nil })
        }
    }

    // MARK: - Arena menus

    /// Every menu page under Arena's top bar, over the 3D tavern room (Caleb, 2026-10-22).
    private var arenaMenu: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < proxy.size.height
            ZStack(alignment: .top) {
                ArenaRoomBackdrop(dim: lobby == nil && !showSetup && !showImport ? 0 : (showImport ? 0.62 : 0.55))
                Group {
                    if showImport {
                        // The Decks tab: Deck Studio under the top bar, as Arena's Decks page.
                        DeckStudioRootView(library: library, selectedDeckID: $selectedDeckID,
                                           isGameLive: { [setup = self.setup] in setup.needsLeave || setup.isBusy }, focus: studioFocus,
                                           preparePlay: { showImport = false; openPlayPanel() }, close: closeDecks)
                            .onDisappear { studioFocus = nil }
                            .transition(.opacity)
                    } else if showSetup || (setup.needsLeave && activeMatch?.isPersonTable != true) {
                        setupContent
                    } else if let lobby {
                        lobbyContent(lobby)
                            .transition(.opacity)
                    } else {
                        ArenaHomeView(content: homeContent, compact: compact)
                    }
                }
                .padding(.top, ArenaMenuStyle.barHeight)
                .environment(\.arenaMenuBackdrop, true)
                // Only the room shows behind the Play panel, darkened.
                .opacity(playPanel ? 0 : 1)
                if playPanel {
                    ArenaPlayPanel(model: playModel, compact: compact)
                        .padding(.top, ArenaMenuStyle.barHeight)
                        .transition(reduceMotion ? .opacity : .move(edge: compact ? .bottom : .trailing).combined(with: .opacity))
                }
                ArenaTopBar(selected: menuTab, compact: compact, select: selectMenuTab, rank: profileRecord.rank.position,
                            openRank: { selectMenuTab(.ranked) },
                            unread: account.incomingCount + account.unreadMessages > 0,
                            messages: { showFriends = true }, updates: { showUpdates = true },
                            downloads: { showDownloads = true },
                            lit: showAppearance ? "menu.settings" : showUpdates ? "menu.updates" : showDownloads ? "menu.downloads"
                                : showFriends ? "menu.friends" : nil,
                            settings: { showAppearance = true })
            }
        }
    }

    /// The top bar's lit tab for what the menu shows.
    private var menuTab: ArenaMenuTab? {
        // A utility panel lights its own icon instead of a tab (the judge, 2026-10-22).
        if showAppearance || showUpdates || showDownloads || showFriends { return nil }
        if showImport { return .decks }
        if showHowToPlay { return .learn }
        switch lobby {
        case .profile: return .profile
        case .rankedHall, .leaderboard: return .ranked
        case nil: return .home
        }
    }

    private func selectMenuTab(_ tab: ArenaMenuTab) {
        // A table being set up or left keeps its page until it's done.
        if (setup.isBusy || setup.needsLeave), tab != .learn { return }
        switch tab {
        case .learn:
            showHowToPlay = true
            return
        case .decks:
            openDecks()
            return
        case .home: lobby = nil
        case .profile: lobby = .profile
        case .ranked: lobby = .rankedHall
        }
        showSetup = false
        showImport = false
        if !matchmaker.isSearching && !challenges.isWaiting { playPanel = false }
    }

    private func openPlayPanel(_ mode: ArenaPlayMode? = nil) {
        if let mode { playModeRaw = mode.rawValue; playTab = .find }
        GameAudio.shared.play(.uiOpen)
        playPanel = true
    }

    private var homeContent: ArenaHomeContent {
        let rank = profileRecord.rank
        let season = RankLadder.seasonName(rank.season)
        return ArenaHomeContent(
            features: [
                ArenaFeature(id: "ranked", kicker: String(localized: "Ranked season"), title: String(localized: "Ranked · \(season)"),
                             art: ArenaHomeArt(asset: "home-art-ur-dragon", focus: UnitPoint(x: 0.62, y: 0.3)),
                             action: { selectMenuTab(.ranked) }),
                ArenaFeature(id: "board", kicker: String(localized: "New"), title: String(localized: "The Arena board"),
                             art: ArenaHomeArt(asset: "home-art-edgar-markov", focus: UnitPoint(x: 0.55, y: 0.22)),
                             action: { showUpdates = true }),
                ArenaFeature(id: "friends", kicker: String(localized: "Friends"), title: String(localized: "Bring a friend to the table"),
                             art: ArenaHomeArt(asset: "home-art-yshtola", focus: UnitPoint(x: 0.62, y: 0.25)),
                             action: { showFriends = true }),
                // The tip jar (it was a strip at the foot of the old menu): the support page, in the browser.
                ArenaFeature(id: "support", kicker: String(localized: "Support"), title: String(localized: "Enjoying MagicMobile?"),
                             art: ArenaHomeArt(asset: "home-art-atraxa", focus: UnitPoint(x: 0.5, y: 0.2)),
                             action: { openURL(SupportProject.url) }),
            ],
            tiles: [
                ArenaHomeTile(id: "quick", title: String(localized: "Quick Match"), subtitle: "",
                              art: ArenaHomeArt(asset: "home-art-krenko", focus: UnitPoint(x: 0.5, y: 0.38)),
                              action: { openPlayPanel(.quick) }),
                // The rank shows on the rail and the top bar; the tile names the mode only (the judge, 2026-10-22).
                ArenaHomeTile(id: "ranked", title: String(localized: "Ranked"), subtitle: "",
                              art: ArenaHomeArt(asset: "home-art-miirym", focus: UnitPoint(x: 0.55, y: 0.4)),
                              action: { openPlayPanel(.ranked) }),
                ArenaHomeTile(id: "learn", title: HowToPlayText.title, subtitle: "",
                              art: ArenaHomeArt(asset: "home-art-giada", focus: UnitPoint(x: 0.6, y: 0.3)),
                              action: { showHowToPlay = true }),
            ],
            deck: selectedDeckBox,
            rank: rank.position, wins: rank.wins, losses: rank.losses,
            friendsOnline: account.onlineFriendCount, unread: account.incomingCount + account.unreadMessages > 0,
            play: { openPlayPanel() }, friends: { showFriends = true }, updates: { showUpdates = true },
            downloads: { showDownloads = true }, openDeck: { openPlayPanel() }, openRank: { selectMenuTab(.ranked) })
    }

    /// The chosen deck as a deck box.
    private var selectedDeckBox: ArenaDeckBoxModel? {
        guard let deck = selectedDeck else { return nil }
        return ArenaDeckBoxModel(id: selectedDeckID, name: deck.name, commander: deck.commander?.cardName, colors: selectedDeckColors,
                                 subtitle: selectedDeckBracket?.name ?? "")
    }

    /// Every deck as a box, by shelf: your own, the precons, then the included decks by bracket.
    private var deckBoxSections: [ArenaDeckSection] {
        _ = bracketRevision
        _ = deckColorsRevision
        let mine = library.decks.map { record -> ArenaDeckBoxModel in
            let id = "local:\(record.id)"
            let report = BracketRules.bundled.evaluate(record.deckList)
            let bracket = DeckBracketPreference.effective(minimum: report.minimum,
                                                          declared: DeckBracketPreference.declared(id, in: MagicMobilePreferences.current))
            let commanders = DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: record.deckList))
            return ArenaDeckBoxModel(id: id, name: record.name, commander: record.deckList.commander?.cardName,
                                     colors: DeckStudioDeckColors.colors(for: commanders) ?? [], subtitle: bracket.name)
        }
        let precons = PreconCatalog.all.map {
            ArenaDeckBoxModel(id: "precon:\($0.id)", name: $0.name, commander: $0.commander, colors: $0.colors.map(String.init),
                              subtitle: CommanderBracket.core.name)
        }
        let included = CommanderBracket.allCases.compactMap { bracket -> ArenaDeckSection? in
            let decks = AIDeckPool.bracketDecks.filter { $0.bracket == bracket }
            guard !decks.isEmpty else { return nil }
            return ArenaDeckSection(id: "included-\(bracket.rawValue)", title: String(localized: "Included · \(bracket.name)"),
                                    decks: decks.map { ArenaDeckBoxModel(id: $0.playerDeckID, name: $0.name, commander: $0.commander,
                                                                         colors: $0.colors.map(String.init), subtitle: bracket.name) })
        }
        return [ArenaDeckSection(id: "mine", title: String(localized: "My Decks"), decks: mine, offersNewDeck: true),
                ArenaDeckSection(id: "precons", title: String(localized: "Precons"), decks: precons)] + included
    }

    /// Development fixture (MAGICMOBILE_UI_TEST_OPEN=queue): the Play panel as a ranked search runs.
    private var fixtureSearch: RankedMatchmaker.Phase? {
        #if DEBUG
        if SocialFixtures.openScreen == "queue" { return .searching(since: Self.fixtureLaunch) }
        #endif
        return nil
    }
    private static let fixtureLaunch = Date()

    private func deckSyncer() -> DeckSync {
        if let deckSync { return deckSync }
        let made = DeckSync(library: library, api: account.deckSyncAPI)
        deckSync = made
        return made
    }

    /// One deck sync for the signed-in profile. Errors stay quiet: the next sync tries again.
    private func syncDecks() async {
        let sync = deckSyncer()
        guard let profile = await account.deckSyncProfile() else { return }
        try? await sync.sync(account: profile)
        // Your own card pictures travel on the same schedule (docs/CARD_ART_SYNC.md).
        await CardArtSyncCoordinator.shared.sync()
        // A deck changed elsewhere may bring a commander whose colours this phone hasn't remembered yet.
        await rememberDeckColors()
    }

    /// Reads your decks' colours from the card catalogue once, off the main thread, for their boxes' pips.
    private func rememberDeckColors() async {
        let decks = library.decks.map { DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: $0.deckList)) }
        guard decks.contains(where: { DeckStudioDeckColors.colors(for: $0) == nil }),
              let metadata = try? await Task.detached(priority: .utility, operation: { try NativeDeckMetadataCatalogue.bundled() }).value
        else { return }
        for commanders in decks { DeckStudioDeckColors.remember(commanders: commanders, metadata: metadata) }
        deckColorsRevision += 1
    }

    /// The last few games, to set up again.
    private var recentGames: [ArenaRecentGame] {
        let decks = allDeckIDs
        var seen = Set<String>()
        return profileRecord.matches.sorted { $0.date > $1.date }.compactMap { match -> ArenaRecentGame? in
            let key = "\(match.mode.rawValue)|\(match.deckID)"
            guard decks.contains(match.deckID), seen.insert(key).inserted else { return nil }
            let foe = match.opponents.first?.name ?? String(localized: "the table")
            return ArenaRecentGame(id: match.id.uuidString, mode: match.mode, deckID: match.deckID, deckName: match.deckName,
                                   commander: match.commander, colors: match.colors, detail: String(localized: "vs \(foe)"),
                                   won: match.outcome == .draw ? nil : match.outcome == .win)
        }
        .prefix(6).map { $0 }
    }

    private var playModel: ArenaPlayPanelModel {
        ArenaPlayPanelModel(
            sections: deckBoxSections, selectedDeckID: $selectedDeckID, deckName: selectedDeck?.name, deckBracket: selectedDeckBracket,
            mode: Binding(get: { ArenaPlayMode(rawValue: playModeRaw) ?? .quick }, set: { playModeRaw = $0.rawValue }),
            tab: $playTab,
            quickBracket: $quickBracket, quickDeckID: $quickDeckID, quickSkill: $quickSkill, quickLevel: $quickLevel, startingPlayer: $aiStartingPlayerMode,
            rank: profileRecord.rank, canSearchPeople: account.rankedQueue != nil,
            search: matchmaker.isSearching ? matchmaker.phase : fixtureSearch,
            waitingFor: challenges.isWaiting ? challengeTarget?.name : nil,
            playerMode: playerMode, mayStart: mayStartSolo,
            status: setup.identity == nil || setup.isBusy ? setup.status : nil,
            recent: recentGames,
            close: { playPanel = false },
            newDeck: { openDecks() },
            explainBracket: { showBracketSheet = true },
            startQuick: startQuickMatch, findRanked: findRankedMatch,
            cancelSearch: { matchmaker.cancel() }, playAINow: { matchmaker.skipToAI() },
            cancelChallenge: { challenges.cancelOutgoing() },
            openCustom: { playPanel = false; showSetup = true },
            rankedHall: { playPanel = false; lobby = .rankedHall },
            leaderboard: { playPanel = false; lobby = .leaderboard },
            challengeFriend: { showFriends = true },
            hostOnline: { playerMode.wrappedValue = "online"; playPanel = false; showSetup = true },
            joinOnline: { playerMode.wrappedValue = "online"; playPanel = false; showSetup = true },
            gameCenter: { playerMode.wrappedValue = "gamecenter"; playPanel = false; showSetup = true },
            chooseRecent: { game in
                selectedDeckID = game.deckID
                switch game.mode {
                case .quick: playModeRaw = ArenaPlayMode.quick.rawValue
                case .ranked: playModeRaw = ArenaPlayMode.ranked.rawValue
                case .casual: playModeRaw = ArenaPlayMode.custom.rawValue
                }
            })
    }

    @ViewBuilder
    private var bracketSheet: some View {
        if let deck = selectedDeck, let report = selectedBracketReport {
            let fixed: CommanderBracket? = AIDeckPool.playerDeck(id: selectedDeckID)?.bracket
                ?? (selectedDeckID.hasPrefix("precon:") ? .core : nil)
            DeckBracketSheet(deckName: deck.name, report: report,
                             declared: fixed == nil ? Binding(
                                get: { _ = bracketRevision; return DeckBracketPreference.declared(selectedDeckID, in: MagicMobilePreferences.current) },
                                set: { DeckBracketPreference.setDeclared($0, for: selectedDeckID, in: MagicMobilePreferences.current); bracketRevision += 1 })
                                : nil,
                             fixedBracket: fixed)
        }
    }

    /// A one-AI game can start: a valid name and deck, the engine ready, nothing else running.
    private var mayStartSolo: Bool {
        validName && selectedDeck != nil && selectedDeckBracket != nil && setup.identity != nil
            && !setup.isBusy && !setup.needsLeave && !matchmaker.isSearching
    }

    private func startQuickMatch() {
        guard let deck = selectedDeck, let bracket = selectedDeckBracket else { return }
        if let level = AIDeckPool.power?.quickMatch[quickLevel],
           let opponent = AIDeckPool.pick(targetPower: level.power, maxBracket: nil, avoidingCommander: deck.commander?.cardName,
                                          recent: profileRecord.recentAIDecks) {
            return startSolo(mode: .quick, deck: deck, deckBracket: bracket, opponent: opponent, skill: level.skill)
        }
        let opponentBracket = quickBracket == 0 ? min(4, bracket.rawValue) : quickBracket
        let chosen = quickDeckID.isEmpty ? nil : AIDeckPool.deck(id: quickDeckID)
        // "Match my deck" at Core or below meets a precon: the Core AI decks are tuned tribal lists.
        guard let opponent = chosen ?? AIDeckPool.pick(bracket: opponentBracket, avoidingCommander: deck.commander?.cardName,
                                                       recent: profileRecord.recentAIDecks,
                                                       preconsOnly: quickBracket == 0 && opponentBracket <= 2) else { return }
        startSolo(mode: .quick, deck: deck, deckBracket: bracket, opponent: opponent, skill: min(10, max(1, quickSkill)))
    }

    /// Ranked: a person from the queue when one is searching near your rank, else an AI at your tier.
    private func findRankedMatch() {
        guard let deck = selectedDeck, let bracket = selectedDeckBracket,
              bracket.rawValue <= profileRecord.rank.position.tier.maxDeckBracket, mayStartSolo else { return }
        do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
        catch { setup.errorMessage = error.localizedDescription; return }
        profileRecord.refreshSeason()
        matchmaker.service = account.rankedQueue
        Task {
            let outcome = await matchmaker.search(protocol: relayProtocol, rankStep: profileRecord.rank.position.step,
                                                  deckBracket: bracket.rawValue)
            switch outcome {
            case .cancelled: break
            case .ai: startRankedAI(deck: deck, bracket: bracket)
            case .human(let ticket): await startRankedHuman(ticket, deck: deck, bracket: bracket)
            }
        }
    }

    private func startRankedAI(deck: DeckList, bracket: CommanderBracket) {
        let position = profileRecord.rank.position
        // The deck nearest the division's Power from the tier's bracket or lower (docs/DECK_POWER.md); by bracket if unrated.
        // The server's ticket can name the Power instead (ranked_ai_tuning), when the game starts.
        let recent = profileRecord.recentAIDecks
        let pickByPower = { (target: Double) -> AIDeck? in
            AIDeckPool.power.flatMap { power in
                AIDeckPool.pick(targetPower: target, maxBracket: position.tier.maxDeckBracket, avoidingCommander: deck.commander?.cardName,
                                recent: recent, closest: power.closest(tier: position.tier.rawValue))
            }
        }
        let byPower = AIDeckPool.power.flatMap { power in
            pickByPower(AIDeckPool.rankedTarget(tier: position.tier.rawValue, division: position.division, tiers: power.rankedTiers))
        }
        guard let opponent = byPower ?? AIDeckPool.pick(bracket: position.opponentBracket, avoidingCommander: deck.commander?.cardName,
                                             recent: profileRecord.recentAIDecks,
                                             preconsOnly: position.tier.preconOpponentsOnly,
                                             onlyPrecons: position.tier.preconOpponentsOnly ? AIDeckPool.gentlestPrecons : nil) else { return }
        startSolo(mode: .ranked, deck: deck, deckBracket: bracket, opponent: opponent, skill: position.tier.aiSkill, repick: pickByPower)
    }

    /// The host opens a two-seat relay table and shares its code; the guest joins it. Both ready up
    /// on their own. A table that never fills hands the seat to an AI.
    private func startRankedHuman(_ ticket: RankedTicket, deck: DeckList, bracket: CommanderBracket) async {
        guard let matchID = ticket.matchId else { return startRankedAI(deck: deck, bracket: bracket) }
        activeMatch = ActiveMatch(mode: .ranked, deckID: selectedDeckID, deckName: deck.name, commander: deck.commander?.cardName,
                                  colors: selectedDeckColors, deckBracket: bracket.rawValue,
                                  opponents: [.init(name: ticket.opponent ?? String(localized: "Challenger"), commander: nil, isAI: false)],
                                  opponentBracket: nil, aiSkill: nil, aiDeckID: nil, rankedMatchID: matchID)
        rankChange = nil; rankNote = nil
        diagnostics.beginAttempt()
        if ticket.isHost {
            await setup.hostRelay(name: playerDisplayName, deck: deck, playerCount: 2, aiDecks: [], aiSkill: 2)
            if let code = setup.multiplayer?.tableCode { await matchmaker.shareTable(match: matchID, code: code) }
        } else if let code = ticket.tableCode {
            setup.joinRelay(code: code, name: playerDisplayName, deck: deck)
        }
        rankedConnectTask?.cancel()
        rankedConnectTask = Task {
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, session.matchID == nil, activeMatch?.rankedMatchID == matchID else { return }
            // Nobody arrived: close the empty table and play the AI instead; nothing was ranked.
            _ = await setup.close()
            matchmaker.finish()
            activeMatch = nil
            bannerError = String(localized: "Your opponent didn't connect. An AI took the seat.")
            startRankedAI(deck: deck, bracket: bracket)
        }
    }

    /// Phones share a table only with the same engine build (the ranked queue and challenges check it).
    private var relayProtocol: String {
        String((setup.relayIdentity.map { "\($0.upstreamCommit)/\($0.catalogueHash)/\($0.adapterVersion)" } ?? "offline").prefix(200))
    }

    /// Challenges check for incoming challenges while the app is open on the menu or a lobby, and
    /// only for a player with friends: nobody else can send one.
    private var watchesChallenges: Bool {
        scenePhase == .active && account.phase == .ready && account.username != nil && !activeGame && !setup.needsLeave
            && account.friends.contains(where: \.isFriend)
    }

    /// The deck for a game against a person, or why there is none. Ranked also needs a deck your tier allows.
    private func personGameDeck(ranked: Bool) -> (deck: DeckList, bracket: CommanderBracket)? {
        guard let deck = selectedDeck, let bracket = selectedDeckBracket, mayStartSolo else {
            bannerError = String(localized: "Choose a deck and let the engine finish loading, then try again.")
            return nil
        }
        if ranked, bracket.rawValue > profileRecord.rank.position.tier.maxDeckBracket {
            bannerError = String(localized: "Your deck's bracket is above what your rank allows in Ranked.")
            return nil
        }
        do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
        catch { setup.errorMessage = error.localizedDescription; return nil }
        return (deck, bracket)
    }

    /// Challenges a friend from the friends list: opens a two-seat table, sends its code and waits for
    /// the answer. A ranked challenge counts like any ranked game (same tier only).
    private func challengeFriend(_ friend: String, mode: PlayMode) {
        profileRecord.refreshSeason()
        guard let picked = personGameDeck(ranked: mode == .ranked) else { return }
        let (deck, bracket) = picked
        challenges.service = account.challenges
        matchmaker.service = account.rankedQueue
        Task {
            // After the friends sheet closes.
            try? await Task.sleep(for: .milliseconds(450))
            activeMatch = ActiveMatch(mode: mode, deckID: selectedDeckID, deckName: deck.name, commander: deck.commander?.cardName,
                                      colors: selectedDeckColors, deckBracket: bracket.rawValue,
                                      opponents: [.init(name: friend, commander: nil, isAI: false)],
                                      opponentBracket: nil, aiSkill: nil, aiDeckID: nil, privateTable: true)
            rankChange = nil; rankNote = nil
            challengeTarget = (friend, mode)
            diagnostics.beginAttempt()
            await setup.hostRelay(name: playerDisplayName, deck: deck, playerCount: 2, aiDecks: [], aiSkill: 2)
            guard let code = setup.multiplayer?.tableCode else { activeMatch = nil; challengeTarget = nil; return }
            let answer = await challenges.challenge(friend, mode: mode, protocol: relayProtocol,
                                                    rankStep: profileRecord.rank.position.step, tableCode: code)
            challengeTarget = nil
            switch answer {
            case .accepted(let accepted):
                activeMatch?.rankedMatchID = accepted.matchId
                watchPersonTable(friend)
            case .declined: await closeChallengeTable(String(localized: "\(friend) declined your challenge."))
            case .expired: await closeChallengeTable(String(localized: "\(friend) didn't answer your challenge."))
            case .cancelled: await closeChallengeTable(nil)
            case .failed(let code): await closeChallengeTable(FriendChallengeRules.message(for: code))
            }
        }
    }

    /// Accepts a friend's challenge and joins their table.
    private func acceptChallenge(_ challenge: FriendChallenge) {
        profileRecord.refreshSeason()
        let step = profileRecord.rank.position.step
        if challenge.isRanked, !FriendChallengeRules.mayRank(myStep: step, friendStep: challenge.challengerStep) {
            bannerError = FriendChallengeRules.message(for: "rank_mismatch")
            Task { await challenges.decline(challenge) }
            return
        }
        guard let picked = personGameDeck(ranked: challenge.isRanked) else { return }
        let (deck, bracket) = picked
        matchmaker.service = account.rankedQueue
        let friend = challenge.challenger ?? String(localized: "Friend")
        Task {
            do {
                let accepted = try await challenges.accept(challenge, protocol: relayProtocol, rankStep: step)
                guard let code = accepted.tableCode else { throw SupabaseLite.Failure(code: "challenge_closed") }
                activeMatch = ActiveMatch(mode: challenge.playMode, deckID: selectedDeckID, deckName: deck.name,
                                          commander: deck.commander?.cardName, colors: selectedDeckColors, deckBracket: bracket.rawValue,
                                          opponents: [.init(name: friend, commander: nil, isAI: false)],
                                          opponentBracket: nil, aiSkill: nil, aiDeckID: nil, rankedMatchID: accepted.matchId,
                                          privateTable: true)
                rankChange = nil; rankNote = nil
                diagnostics.beginAttempt()
                setup.joinRelay(code: code, name: playerDisplayName, deck: deck)
                watchPersonTable(friend)
            } catch {
                bannerError = FriendChallengeRules.message(for: SupabaseLite.code(of: error))
            }
        }
    }

    /// A challenge table that never starts closes after a while; nothing is recorded.
    private func watchPersonTable(_ friend: String) {
        rankedConnectTask?.cancel()
        rankedConnectTask = Task {
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, session.matchID == nil, activeMatch?.privateTable == true else { return }
            await closeChallengeTable(String(localized: "\(friend) didn't connect. Try the challenge again."))
        }
    }

    private func closeChallengeTable(_ message: String?) async {
        _ = await setup.close()
        activeMatch = nil
        if let message { bannerError = message }
    }

    // MARK: Guided first game

    /// The guided first game: Token Triumph against Grave Danger at skill 1, casual, with the
    /// coach on. It uses its own decks, so the player's chosen deck and settings stay as they are.
    private func startGuidedGame() {
        guard let precon = PreconCatalog.all.first(where: { $0.id == GuidedGameSetup.playerPreconID }),
              let opponent = AIDeckPool.deck(id: GuidedGameSetup.opponentDeckID) else { return }
        diagnostics.beginAttempt()
        let name = (try? OnDeviceSetupModel.playerName(playerDisplayName)) ?? String(localized: "You")
        GuidedGameLaunch.begin(in: MagicMobilePreferences.current)
        HowToPlayLaunch.markSeen(in: MagicMobilePreferences.current)
        guidedGame = true; guidedTip = nil
        lobby = nil; showSetup = false
        activeMatch = ActiveMatch(mode: .casual, deckID: GuidedGameSetup.playerDeckID, deckName: precon.name,
                                  commander: precon.commander, colors: precon.colors.map(String.init),
                                  deckBracket: CommanderBracket.core.rawValue,
                                  opponents: [.init(name: opponent.name, commander: opponent.commander, isAI: true)],
                                  opponentBracket: opponent.bracket.rawValue, aiSkill: GuidedGameSetup.aiSkill, aiDeckID: opponent.id)
        rankChange = nil; rankNote = nil
        Task {
            await setup.startAI(name: name, deck: precon.deckList, aiDecks: [opponent.deckList], aiSkill: GuidedGameSetup.aiSkill,
                                deckID: GuidedGameSetup.playerDeckID, aiDeckIDs: [opponent.id],
                                startingPlayerMode: aiStartingPlayerMode, mode: .casual,
                                deckBracket: CommanderBracket.core.rawValue)
            if session.matchID == nil { activeMatch = nil; endGuidedGame() }
        }
    }

    // MARK: Lessons

    /// A lesson (Lessons.swift): the recorded game on the real board, with Maren's notes. Nothing is saved or counted.
    private func startLesson(_ id: String) {
        guard let info = LessonCatalog.all.first(where: { $0.id == id }) else { return }
        let script: LessonScript
        do { script = try LessonScript.load(id: id) } catch { setup.errorMessage = error.localizedDescription; return }
        HowToPlayLaunch.markSeen(in: MagicMobilePreferences.current)
        endGuidedGame()
        let run = LessonRun(script: info, defaults: MagicMobilePreferences.current)
        run.refresh = { [session] in Task { try? await session.refresh() } }
        lessonRun = run
        lobby = nil; showSetup = false
        activeMatch = nil; rankChange = nil; rankNote = nil
        Task {
            await setup.startLesson(script, run: run)
            if session.matchID == nil { lessonRun = nil }
        }
    }

    /// The next lesson, or after the last one the guided game.
    private func nextLesson() {
        guard let run = lessonRun else { return }
        let next = LessonCatalog.next(after: run.script.id)
        Task {
            guard await setup.close() else { return }
            selectedCard = nil; inspectedCard = nil; zone = nil
            lessonRun = nil
            if let next { startLesson(next.id) } else { startGuidedGame() }
        }
    }

    /// Back to the lessons.
    private func finishLesson() {
        Task {
            guard await setup.close() else { return }
            selectedCard = nil; inspectedCard = nil; zone = nil
            lessonRun = nil
            showHowToPlay = true
        }
    }

    /// Each snapshot may bring the next note, or retire the one on screen.
    private func advanceGuidedTip(_ snapshot: GameSnapshot?) {
        guard guidedGame, let snapshot else { return }
        let defaults = MagicMobilePreferences.current
        let step = GuidedGameCoach.advance(current: guidedTip, snapshot: snapshot, shown: GuidedGameLaunch.shownTips(in: defaults))
        if let shown = step.newlyShown { GuidedGameLaunch.remember(shown, in: defaults) }
        if step.current != guidedTip { guidedTip = step.current }
        if snapshot.isCompleted { GuidedGameLaunch.end(in: defaults) }
    }

    /// Turn off tips: the game plays on without the coach.
    private func endGuidedTips() {
        guidedTip = nil
        guidedGame = false
        GuidedGameLaunch.end(in: MagicMobilePreferences.current)
    }

    private func endGuidedGame() {
        guard guidedGame else { return }
        endGuidedTips()
    }

    private func answerGuidedWelcome() {
        GuidedGameLaunch.markWelcomeSeen(in: MagicMobilePreferences.current)
        HowToPlayLaunch.markSeen(in: MagicMobilePreferences.current)
        showGuidedWelcome = false
    }

    /// The welcome's main button: the first lesson (the guided game follows the last one).
    private func playGuidedFromWelcome() {
        answerGuidedWelcome()
        if let first = LessonCatalog.all.first { startLesson(first.id) } else { startGuidedGame() }
    }

    /// The slideshow opens once the welcome has slid away, straight into the table's tutorial.
    private func readHowToPlayFromWelcome() {
        answerGuidedWelcome()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            howToPlayOpensTable = true
            showHowToPlay = true
        }
    }

    /// `repick`: a ranked game's AI deck for the Power its server ticket names (ranked_ai_tuning).
    private func startSolo(mode: PlayMode, deck: DeckList, deckBracket: CommanderBracket, opponent: AIDeck, skill: Int,
                           repick: ((Double) -> AIDeck?)? = nil) {
        diagnostics.beginAttempt()
        do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
        catch { setup.errorMessage = error.localizedDescription; return }
        activeMatch = ActiveMatch(mode: mode, deckID: selectedDeckID, deckName: deck.name, commander: deck.commander?.cardName,
                                  colors: selectedDeckColors, deckBracket: deckBracket.rawValue,
                                  opponents: [.init(name: opponent.name, commander: opponent.commander, isAI: true)],
                                  opponentBracket: opponent.bracket.rawValue, aiSkill: skill, aiDeckID: opponent.id)
        rankChange = nil; rankNote = nil
        if mode == .ranked { profileRecord.beginRankedAIGame(ticket: nil) }
        Task {
            // The server's ticket for a ranked game, so its result counts there too; its seed deals this game.
            var seed: Int64?
            var foe = opponent, aiSkill = skill
            var mistakes: Int?
            if mode == .ranked {
                let ticket = await account.startRankedAIGame(deckBracket: deckBracket.rawValue)
                profileRecord.beginRankedAIGame(ticket: ticket?.id, seeded: ticket != nil)
                seed = ticket?.seed
                // The server tunes the AI without an app build: its skill, mistakes and the deck's Power.
                if let tuned = ticket?.ai {
                    foe = repick?(tuned.power) ?? opponent
                    aiSkill = tuned.skill; mistakes = tuned.mistakePercent
                    activeMatch = ActiveMatch(mode: mode, deckID: selectedDeckID, deckName: deck.name, commander: deck.commander?.cardName,
                                              colors: selectedDeckColors, deckBracket: deckBracket.rawValue,
                                              opponents: [.init(name: foe.name, commander: foe.commander, isAI: true)],
                                              opponentBracket: foe.bracket.rawValue, aiSkill: aiSkill, aiDeckID: foe.id)
                }
            }
            await setup.startAI(name: playerDisplayName, deck: deck, aiDecks: [foe.deckList], aiSkill: aiSkill,
                                deckID: selectedDeckID, aiDeckIDs: [foe.id],
                                startingPlayerMode: mode.startingPlayerMode(preference: aiStartingPlayerMode),
                                mode: mode, deckBracket: deckBracket.rawValue, seed: seed, aiMistakePercent: mistakes)
            if session.matchID == nil { activeMatch = nil }
        }
    }

    /// A saved Quick Match or Ranked game picks up its context again.
    private func resumedMatch(_ saved: GameResumeSetup, deckName: String) -> ActiveMatch? {
        guard let raw = saved.mode, let mode = PlayMode(rawValue: raw) else { return nil }
        let foes = saved.aiDeckIDs.compactMap(AIDeckPool.deck(id:))
        return ActiveMatch(mode: mode, deckID: saved.deckID, deckName: deckName, commander: selectedDeck?.commander?.cardName,
                           colors: selectedDeckColors, deckBracket: saved.deckBracket ?? selectedDeckBracket?.rawValue ?? 2,
                           opponents: foes.map { .init(name: $0.name, commander: $0.commander, isAI: true) },
                           opponentBracket: foes.first?.bracket.rawValue, aiSkill: saved.aiSkill, aiDeckID: foes.first?.id)
    }

    /// Records a finished game once: every game goes into the profile, ranked games move the ladder.
    /// A hot phone shortens AI thinking in games its engine runs: never ranked (the same AI for everyone) or online.
    private func updateDevicePace() {
        session.devicePaceHot = activeGame && !setup.usingMultiplayer && activeMatch?.mode != .ranked && DeviceHeat.shared.isHot
    }

    private func recordFinishedGameIfNeeded() {
        guard lessonRun == nil, let snapshot = session.snapshot, snapshot.isCompleted || session.isOverForSeat else { return }
        var match = activeMatch ?? casualMatch(snapshot)
        guard let current = match, !current.recorded else { return }
        let winners = snapshot.winnerPlayerIds ?? []
        let outcome: RankOutcome = winners.contains(snapshot.viewerID) ? .win
            : (snapshot.isCompleted && winners.isEmpty ? .draw : .loss)
        match?.recorded = true
        activeMatch = match
        // The engine's game record first (solo games, before the match is destroyed), so a ranked result goes with it.
        Task {
            let file = await setup.finishedGameRecord().flatMap(profileRecord.keepGameRecord)
            saveResult(current, outcome: outcome, turns: snapshot.turn, snapshot: snapshot, gameRecordFile: file)
        }
    }

    /// Leaving a ranked game before it ends counts as a loss.
    private func recordAbandonedRankedGame() {
        guard var match = activeMatch, match.mode == .ranked, !match.recorded, session.matchID != nil else { return }
        saveResult(match, outcome: .loss, turns: session.snapshot?.turn ?? 0, snapshot: session.snapshot)
        match.recorded = true
        activeMatch = match
    }

    private func saveResult(_ match: ActiveMatch, outcome: RankOutcome, turns: Int, snapshot: GameSnapshot?, gameRecordFile: String? = nil) {
        let colors = match.colors.isEmpty ? PlayerStats.colors(manaCost: snapshot?.human?.zones.command.first?.card.manaCost) : match.colors
        let change = profileRecord.record(mode: match.mode, outcome: outcome, opponents: match.opponents, opponentBracket: match.opponentBracket,
                                   aiSkill: match.aiSkill, deckID: match.deckID, deckName: match.deckName, commander: match.commander,
                                   colors: colors, deckBracket: match.deckBracket, turns: turns,
                                   durationSeconds: gameStartedAt.map { Int(Date().timeIntervalSince($0)) }, aiDeckID: match.aiDeckID,
                                   engineMatchID: session.matchID, gameRecordFile: gameRecordFile)
        rankChange = change
        rankNote = nil
        let rankedMatchID = match.rankedMatchID, ranked = match.mode == .ranked
        let recordedID = ranked ? profileRecord.matches.first?.id : nil
        Task { [account] in
            if let rankedMatchID { await matchmaker.report(match: rankedMatchID, outcome: outcome) }
            // The server keeps score: send the result and take its standing (the phone's own count shows meanwhile),
            // then upload the game so its rank history point is the standing after it.
            if ranked { await account.afterRefresh?() }
            // The server's word replaces the phone's guess on the result screen still showing this game.
            if let recordedID, rankChange == change, let settled = profileRecord.matches.first(where: { $0.id == recordedID }) {
                rankChange = settled.rankChange
                rankNote = settled.rankNote
            }
        }
        if let change, [.divisionUp, .divisionDown, .tierUp, .tierDown].contains(change.kind) {
            // After the result screen's own reveal.
            Task { try? await Task.sleep(for: .milliseconds(1500)); if rankChange == change { ceremony = change } }
        }
    }

    /// A custom-table game, recorded for the profile only.
    private func casualMatch(_ snapshot: GameSnapshot) -> ActiveMatch? {
        guard let deck = selectedDeck else { return nil }
        let foes = snapshot.players.filter { !snapshot.isViewer($0.playerId) }.map { player in
            MatchRecord.Opponent(name: player.displayName ?? String(localized: "Opponent"), commander: player.zones.command.first?.card.name,
                                 isAI: !setup.usingMultiplayer)
        }
        return ActiveMatch(mode: .casual, deckID: selectedDeckID, deckName: deck.name, commander: deck.commander?.cardName,
                           colors: selectedDeckColors, deckBracket: selectedDeckBracket?.rawValue ?? 2, opponents: foes,
                           opponentBracket: nil, aiSkill: setup.usingMultiplayer ? nil : aiSkill, aiDeckID: nil)
    }

    private var downloadDecks: [NativeDownloadDeck] {
        PreconCatalog.all.map { NativeDownloadDeck(id: "precon:\($0.id)", deck: $0.deckList) }
        + AIDeckPool.bracketDecks.map { NativeDownloadDeck(id: $0.playerDeckID, deck: $0.deckList) }
        + library.decks.map { NativeDownloadDeck(id: "local:\($0.id)", deck: $0.deckList) }
    }

    /// The custom table as Arena's event page (Caleb, 2026-10-22): your deck on the left, the seats on the right, and Start
    /// pinned in the corner.
    private var setupContent: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height && !dynamicType.isAccessibilitySize
            VStack(spacing: 0) {
                TavernScreenHeader(title: String(localized: "Custom Table"), backTitle: String(localized: "Main menu"), back: {
                    showSetup = false
                    openPlayPanel(.custom)
                })
                .disabled(setup.isBusy || setup.needsLeave)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                // Arena's event page: your seat on one plate, the table on the other, Start on the strip below them
                // (the judge, 2026-10-22: nothing scrolls under the strip, and nothing sits bare on the room).
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 14) {
                            // Each plate keeps its frame; what doesn't fit scrolls inside it and fades at its foot.
                            ScrollView { setupSeat(wide: true).padding(12).padding(.bottom, 20) }
                                .scrollIndicators(.hidden)
                                .scrollBounceBehavior(.basedOnSize)
                                .mask(ArenaScrollFade(depth: 28))
                                .arenaCard(padding: 0)
                                .frame(width: 300)
                            ScrollView { setupTable(wide: true).frame(maxWidth: .infinity, alignment: .leading).padding(14).padding(.bottom, 20) }
                                .scrollDismissesKeyboard(.interactively)
                                .scrollBounceBehavior(.basedOnSize)
                                .mask(ArenaScrollFade(depth: 28))
                                .arenaCard(padding: 0)
                                .accessibilityIdentifier("lobby.scroll")
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                setupSeat(wide: false)
                                setupRule
                                setupTable(wide: false).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .padding(.bottom, 20)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .mask(ArenaScrollFade(depth: 28))
                        .arenaCard(padding: 0)
                        .accessibilityIdentifier("lobby.scroll")
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: 940)
                .frame(maxWidth: .infinity)
                setupStartBar
            }
        }
        .foregroundStyle(ArenaMenuStyle.text)
        .tint(ArenaMenuStyle.gold)
    }

    /// Your seat: what the table is, your deck as an open box, your name on a plate, the deck's check.
    private func setupSeat(wide: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let box = selectedDeckBox {
                let width: CGFloat = wide ? 124 : 118
                ArenaDeckBox(deck: box, selected: true, width: width)
                    .padding(.top, ArenaBoxGeometry(width: width).rise * 1.6 + 4)
            }
            setupSeatDetails
        }
        .frame(maxWidth: .infinity)
        .disabled(setup.isBusy || (setup.needsLeave && !editableInRoom))
    }

    private var setupSeatDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bracket = selectedDeckBracket {
                Button { showBracketSheet = true } label: {
                    HStack(spacing: 4) {
                        Text(bracket.title).font(ArenaMenuStyle.font(11, .bold)).foregroundStyle(ArenaMenuStyle.gold)
                        Image(systemName: "info.circle").font(.system(size: 10, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
                    }
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("play.deck.bracket")
            }
            OnDeviceSetupDeckDetails(deckID: selectedDeckID, deck: selectedDeck, resolver: setup.deckResolver,
                                     startIssues: setup.startIssues) { cards in
                studioFocus = DeckStudioPlaySelection.FixRequest(deckID: selectedDeckID, cards: cards); openDecks()
            }.disabled(setup.isBusy)
            setupNamePlate
            Button(String(localized: "Change deck")) {
                showSetup = false
                openPlayPanel(.custom)
            }
            .buttonStyle(ArenaPillButtonStyle())
            .disabled(setup.isBusy || setup.needsLeave)
            .accessibilityIdentifier("setup.changeDeck")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Your name written on the plate, as Arena shows it on an event page; until you sign in it can be written on, with
    /// a pencil and a gold line under it.
    private var setupNamePlate: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Player name", text: $playerDisplayName)
                    .textContentType(.nickname).autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(ArenaMenuStyle.font(17, .bold))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .disabled(account.username != nil)
                    .accessibilityIdentifier("ondevice.playerName")
                if account.username == nil {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(ArenaMenuStyle.gold)
                }
            }
            .frame(minHeight: 30)
            .overlay(alignment: .bottom) {
                if account.username == nil { Rectangle().fill(ArenaMenuStyle.gold.opacity(0.45)).frame(height: 1) }
            }
            // Only a name that can't be used says why (AGENTS.md: no helper lines the layout can carry).
            if account.username == nil && !validName {
                setupNote("Choose a name with 1–24 characters.")
            }
        }
    }

    /// The table: who sits at it, then for the AI the seats, its skill and who goes first.
    private func setupTable(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if wide && !playWithFriends {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) { setupPlayers; setupRule; ArenaCaps(text: String(localized: "Seats")); setupSeats }
                        .padding(.bottom, 20)
                    VStack(alignment: .leading, spacing: 10) { setupSkill; setupRule; setupFirst }
                        .frame(maxWidth: 240)
                }
            } else {
                setupPlayers
                if playWithFriends {
                    setupFriendsTable
                } else {
                    setupRule
                    ArenaCaps(text: String(localized: "Seats"))
                    setupSeats
                    setupRule
                    setupSkill
                    setupRule
                    setupFirst
                }
            }
            setupRecovery
        }
    }

    private var setupPlayers: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArenaCaps(text: String(localized: "Players"))
            HStack(spacing: 10) {
                setupTile("AI", symbol: "cpu", on: playerMode.wrappedValue == "ai", identifier: "setup.mode.ai") { playerMode.wrappedValue = "ai" }
                setupTile("Online", symbol: "globe", on: playerMode.wrappedValue == "online", identifier: "setup.mode.online") { playerMode.wrappedValue = "online" }
                setupTile("Game Center", symbol: "gamecontroller.fill", on: playerMode.wrappedValue == "gamecenter",
                          identifier: "setup.mode.gamecenter") { playerMode.wrappedValue = "gamecenter" }
            }
            .disabled(setup.isBusy || setup.needsLeave)
        }
    }

    private var setupSkill: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ArenaCaps(text: String(localized: "AI skill"))
                Spacer()
                Text("\(aiSkill)").font(ArenaMenuStyle.font(15, .bold)).monospacedDigit().foregroundStyle(ArenaMenuStyle.gold)
            }
            ArenaSlider(value: Binding(get: { Double(aiSkill) }, set: { aiSkill = min(10, max(1, Int($0.rounded()))) }),
                        range: 1...10, label: "AI skill", identifier: "onDevice.aiSkill", valueText: "AI skill: \(aiSkill)")
                .disabled(setup.isBusy || setup.needsLeave)
        }
    }

    private var setupFirst: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArenaCaps(text: String(localized: "Who goes first"))
            HStack(spacing: 10) {
                setupTile("Choose", symbol: "hand.point.up.left.fill", on: aiStartingPlayerMode == "choose",
                          identifier: "setup.first.choose") { aiStartingPlayerMode = "choose" }
                setupTile("Roll D20", symbol: "dice.fill", on: aiStartingPlayerMode == "roll",
                          identifier: "setup.first.roll") { aiStartingPlayerMode = "roll" }
            }
            .disabled(setup.isBusy || setup.needsLeave)
        }
    }

    @ViewBuilder private var setupRecovery: some View {
        if setup.needsLeave {
            Button("Leave / retry closing", role: .destructive) { confirmLeave = true }
                .buttonStyle(ArenaPillButtonStyle())
                .disabled(setup.isBusy || session.isWorking)
        }
        if setup.identity == nil {
            Button("Retry loading local catalogue") { setup.prepare() }
                .buttonStyle(ArenaPillButtonStyle())
        }
        if diagnostics.report != nil {
            Button("Engine error report") { showDiagnostics = true }
                .buttonStyle(ArenaPillButtonStyle())
                .accessibilityIdentifier("ondevice.diagnostics")
        }
    }

    /// Online and Game Center: the table code or the room, and the people at the table.
    @ViewBuilder private var setupFriendsTable: some View {
        if !(playOnline && setup.multiplayer?.isRelayTable == true) {
            TavernPicker(title: "Human players", selection: $playerCount,
                         sections: [.init(options: (2...4).map { ("\($0) players", $0) })])
                .disabled(setup.isBusy || setup.needsLeave)
        }
        if playOnline {
            RelayTablePanel(multiplayer: setup.multiplayer, code: $relayJoinCode, mayEnter: mayStart && !setup.needsLeave,
                            locked: setup.isBusy || setup.needsLeave,
                            aiCount: gameCenterAICountBinding, maxAI: max(0, 4 - playerCount),
                            aiDeckSelection: aiDeckSelection, aiSkill: $aiSkill,
                            deckName: selectedDeck?.name, localCommander: selectedDeck?.commander?.cardName,
                            host: {
                                guard let deck = selectedDeck else { return }
                                Task { await setup.hostRelay(name: playerDisplayName, deck: deck, playerCount: playerCount,
                                                             aiDecks: gameCenterAIDecks, aiSkill: aiSkill) }
                            },
                            join: { code in
                                guard let deck = selectedDeck else { return }
                                setup.joinRelay(code: code, name: playerDisplayName, deck: deck)
                            },
                            ready: {
                                guard let deck = selectedDeck else { return }
                                setup.readyForMatch(name: playerDisplayName, deck: deck)
                            })
        } else {
            TavernStepper(title: "AI opponents: \(gameCenterAICount)", value: gameCenterAICountBinding,
                          range: 0...max(0, 4 - playerCount), identifier: "ondevice.gameCenterAI.count")
                .disabled(setup.isBusy || setup.needsLeave)
            ForEach(0..<gameCenterAICount, id: \.self) { index in
                TavernPicker(title: "AI \(index + 1) deck", selection: aiDeckSelection(index),
                             sections: aiDeckPickerSections,
                             identifier: "ondevice.gameCenterAI.deck.\(index + 1)")
                    .disabled(setup.isBusy || setup.needsLeave)
            }
            if gameCenterAICount > 0 {
                TavernStepper(title: "AI skill: \(aiSkill)", value: $aiSkill, range: 1...10)
                    .disabled(setup.isBusy || setup.needsLeave)
            }
            setupNote("Every player needs the same app version and must keep the app open during the match.")
            if let room = setup.multiplayer?.room {
                MatchRoomView(room: room, deckName: selectedDeck?.name,
                              localCommander: selectedDeck?.commander?.cardName) {
                    guard let deck = selectedDeck else { return }
                    setup.readyForMatch(name: playerDisplayName, deck: deck)
                }
            }
            if setup.multiplayer?.isAuthenticated != true {
                Button("Sign in to Game Center") { setup.multiplayer?.authenticate() }
                    .buttonStyle(ArenaPillButtonStyle())
                    .disabled(setup.multiplayer == nil || setup.isBusy || setup.needsLeave)
            }
        }
    }

    /// The AI seats as deck boxes: tap one for its deck, its × empties it, and a + seat adds an opponent.
    private var setupSeats: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<min(3, max(1, opponentCount)), id: \.self) { index in
                    setupSeat(index)
                }
                if opponentCount < 3 {
                    Button { addAISeat() } label: {
                        // The box is the seat; its name plate and the "+" say enough (no captions under them).
                        ArenaNewDeckBox(width: 70)
                    }
                    .buttonStyle(BrandPressStyle())
                    .accessibilityLabel(String(localized: "Add an AI opponent"))
                    .accessibilityIdentifier("ondevice.aiSeat.add")
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .disabled(setup.isBusy || setup.needsLeave)
    }

    private func setupSeat(_ index: Int) -> some View {
        let deck = AIDeckPool.deck(id: aiDeckSelection(index).wrappedValue)
        return VStack(spacing: 4) {
            TavernMenu(arrowEdge: .top, scrollHeight: 420, scrollAnchor: AnyHashable(aiDeckSelection(index).wrappedValue)) {
                ForEach(Array(aiDeckPickerSections.enumerated()), id: \.offset) { _, section in
                    if let heading = section.title { ArenaCaps(text: heading, size: 9.5).padding(.top, 4) }
                    ForEach(Array(section.options.enumerated()), id: \.offset) { _, option in
                        TavernMenuItem(title: option.label, systemImage: option.value == aiDeckSelection(index).wrappedValue ? "checkmark" : nil) {
                            aiDeckSelection(index).wrappedValue = option.value
                        }
                        .id(AnyHashable(option.value))
                    }
                }
            } label: {
                ArenaDeckBox(deck: ArenaDeckBoxModel(id: deck?.id ?? "seat-\(index)", name: deck?.name ?? String(localized: "Choose a deck"),
                                                     commander: deck?.deckList.commander?.cardName,
                                                     colors: deck.map { $0.colors.map(String.init) } ?? [],
                                                     subtitle: deck?.bracket.name ?? ""),
                             width: 70)
            }
            .accessibilityLabel("AI \(index + 1) deck, \(deck?.name ?? "Choose")")
            .accessibilityIdentifier("ondevice.aiDeck.\(index + 1)")
        }
        .overlay(alignment: .topTrailing) {
            if opponentCount > 1 {
                Button { removeAISeat(index) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(ArenaMenuStyle.text)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.8))
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 10, y: -10)
                .accessibilityLabel(String(localized: "Remove AI \(index + 1)"))
                .accessibilityIdentifier("ondevice.aiSeat.remove.\(index + 1)")
            }
        }
    }

    /// A seat comes back with the deck it last had; an empty one gets a precon.
    private func addAISeat() {
        guard opponentCount < 3 else { return }
        let index = opponentCount
        if AIDeckPool.deck(id: aiDeckSelection(index).wrappedValue) == nil {
            let taken = Set((0..<index).map { aiDeckSelection($0).wrappedValue })
            aiDeckSelection(index).wrappedValue = (PreconCatalog.all.map(\.id).first { !taken.contains($0) }) ?? aiPreconID
        }
        opponentCount = index + 1
    }

    /// Empties a seat; its deck waits just past the remaining seats, so adding a seat brings it back.
    private func removeAISeat(_ index: Int) {
        guard opponentCount > 1, index < opponentCount else { return }
        var ids = [aiPreconID, aiPrecon2ID, aiPrecon3ID]
        let removed = ids.remove(at: index)
        ids.insert(removed, at: opponentCount - 1)
        aiPreconID = ids[0]; aiPrecon2ID = ids[1]; aiPrecon3ID = ids[2]
        opponentCount -= 1
    }

    /// A choice as a tile: an emblem in a glass circle over its name, lit when chosen.
    private func setupTile(_ title: String, symbol: String, on: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            GameAudio.shared.play(.uiTap)
            action()
        } label: {
            VStack(spacing: 5) {
                ArenaEmblem(symbol: symbol, size: 17, lit: on)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().strokeBorder(on ? AnyShapeStyle(ArenaMenuStyle.metal) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: on ? 1.6 : 0.9))
                Text(title).font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(on ? Color.white : ArenaMenuStyle.dim)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: 110)
            .padding(.vertical, 8)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    private var setupRule: some View {
        Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.3).padding(.vertical, 2)
    }

    /// The pinned bar: what the table is doing, and Start (or Find players) in the corner, as Arena pins Play.
    private var setupStartBar: some View {
        HStack(spacing: 12) {
            // The idle line said only what the page shows; the strip speaks when the table is doing something.
            Text(setup.status == "Choose your deck and players." ? "" : setup.status).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                .lineLimit(2)
            Spacer(minLength: 8)
            if !playWithFriends {
                Button { startAI() } label: { Text(String(localized: "Start")) }
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 21))
                    .frame(width: 200, height: 46)
                    .disabled(!mayStart)
                    .accessibilityLabel("Start game")
            } else if !playOnline {
                Button { startMatchmaking() } label: { Text(String(localized: "Find players")) }
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 19))
                    .frame(width: 200, height: 46)
                    .disabled(!mayStart || setup.multiplayer?.isAuthenticated != true)
                    .accessibilityLabel("Find players")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        // A solid dark strip along the foot of the page, edged in the hairline, below the plates.
        .background {
            LinearGradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.075), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.6) }
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
    }

    private func setupNote(_ text: String) -> some View {
        Text(text).font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A session error stays up until updates resume or it is dismissed: polling has stopped, and a
    /// board that only says "waiting" reads as frozen.
    private var stickySessionError: String? {
        guard activeGame, let message = session.errorMessage, message != dismissedSessionError else { return nil }
        return message
    }

    @ViewBuilder
    private var recoveryBanner: some View {
        let message = bannerError ?? stickySessionError
        if setup.isBusy || message != nil ||
            (activeGame && (session.snapshot == nil || !setup.canUseSession)) {
            VStack(alignment: .leading, spacing: 10) {
                if setup.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().tint(TavernPalette.parchment)
                        Text(setup.status)
                    }
                }
                if let message {
                    HStack(alignment: .top) {
                        Text(message).lineLimit(3)
                        Spacer(minLength: 8)
                        Button {
                            if message == session.errorMessage { dismissedSessionError = message }
                            bannerError = nil
                        } label: { TavernSealLabel() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss notification")
                        .accessibilityIdentifier("ondevice.dismissNotification")
                    }
                } else if activeGame && !setup.canUseSession {
                    Text(setup.liveStatus)
                    // Everyone still at the table may vote to go on without a player who is away (TableLeaveRules).
                    if let vote = setup.multiplayer?.continueVote {
                        Button(vote.voted ? String(localized: "Waiting for the others (\(vote.voters.count)/\(vote.needed))")
                               : TableLeaveRules.buttonTitle(vote)) { setup.multiplayer?.voteToContinue() }
                            .buttonStyle(ArenaButtonStyle(kind: .primary, compact: true))
                            .disabled(vote.voted)
                            .accessibilityIdentifier("ondevice.continueWithout")
                    }
                } else if activeGame && session.snapshot == nil {
                    Text("Waiting for the first game update.")
                }
                if activeGame {
                    HStack(spacing: 8) {
                        Button("Refresh", action: refresh).disabled(!setup.canUseSession)
                            .buttonStyle(ArenaButtonStyle(kind: .primary, compact: true))
                        if session.pendingActionID != nil {
                            Button("Retry response") { Task { await setup.perform { try await session.retryPending() } } }
                                .disabled(!setup.canUseSession)
                                .buttonStyle(ArenaButtonStyle(kind: .secondary, compact: true))
                        }
                        Button(setup.closeFailed ? "Retry closing" : "Leave") {
                            if setup.closeFailed { closeGame() } else { confirmLeave = true }
                        }
                        .buttonStyle(ArenaButtonStyle(kind: .danger, compact: true))
                    }
                    .disabled(setup.isBusy || session.isWorking)
                }
                if message != nil && diagnostics.report != nil {
                    Button("Review engine error report") { showDiagnostics = true }
                        .buttonStyle(ArenaButtonStyle(kind: .secondary, compact: true))
                        .accessibilityIdentifier("ondevice.failureReport")
                }
            }
            .font(ArenaMenuStyle.font(15, .semibold))
            .foregroundStyle(TavernPalette.parchment)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TavernPanelChrome(tavern: true))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// Sends one freeze incident with the phone's crash and hang summaries (docs/FREEZE_LOG.md), only when the player chose to.
    private func sendFreezeReport(_ incident: FreezeIncident) async {
        let sections = [FreezeLog.text(incident), OnDeviceSystemReports.section(OnDeviceSystemReports.load(directory: OnDeviceDiagnostics.defaultDirectory))]
        let sent = await account.sendDiagnostic(kind: incident.kind, report: sections.compactMap { $0 }.joined(separator: "\n\n"))
        if sent { FreezeLog.shared.markSent(incident.id) }
        freezeResult = sent ? String(localized: "Report sent. Thank you.") : String(localized: "Couldn't send the report. It will ask again next time.")
    }

    /// The game menu's Report a freeze: record this moment with the game around it, then send it.
    private func reportFreezeNow() {
        session.refreshFreezeContext()
        let id = FreezeLog.shared.record(kind: "reported", extra: FreezeDevice.summary(foreground: scenePhase == .active))
        guard let incident = FreezeLog.shared.incidents.first(where: { $0.id == id }) else { return }
        Task { await sendFreezeReport(incident) }
    }

    private func startAI() {
        diagnostics.beginAttempt()
        guard let deck = selectedDeck, aiPrecons.count == opponentCount else { return }
        activeMatch = nil; rankChange = nil; rankNote = nil
        let opponentDecks = aiPrecons.map(\.deckList)
        Task {
            do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
            catch { setup.errorMessage = error.localizedDescription; return }
            await setup.startAI(name: playerDisplayName, deck: deck, aiDecks: opponentDecks, aiSkill: aiSkill,
                                deckID: selectedDeckID, aiDeckIDs: aiPrecons.map(\.id),
                                startingPlayerMode: aiStartingPlayerMode)
        }
    }

    /// The engine error report, on an Arena panel.
    private var diagnosticSheet: some View {
        VStack(spacing: 0) {
            ArenaPanelHeader(title: String(localized: "Engine error report"), closeIdentifier: "diagnostics.close")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only the latest engine error report is kept on this phone, excluded from backups. Error text may contain private card information. Nothing is uploaded automatically; review it before sharing.")
                    if let error = diagnostics.errorMessage { Text(error).foregroundStyle(ArenaMenuStyle.loss) }
                    if let report = diagnostics.report {
                        Text(diagnostics.isHistorical ? "Saved report from an earlier session" : "Latest local incident")
                            .font(ArenaMenuStyle.font(15, .bold))
                        ShareLink(item: report) { Label("Share report", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("ondevice.shareReport")
                    }
                    if diagnostics.report != nil || diagnostics.errorMessage != nil {
                        Button("Delete saved report", role: .destructive) { confirmDeleteReport = true }
                    }
                    if let report = diagnostics.report {
                        Text(report).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArenaMenuStyle.dim).textSelection(.enabled)
                    } else if diagnostics.errorMessage == nil {
                        Text("No engine exception has been captured yet. Try starting the match again, then return here if it stops.")
                    }
                    // Developer replays (scripts/dev/replay_record.sh): the record shows every hand and library order.
                    if let latest = profileRecord.gameRecordFiles().first {
                        Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.4)
                        Text("Your last game's record lists every decision so it can be replayed on a computer. It shows your hands and library order.")
                            .font(ArenaMenuStyle.font(12, .medium))
                        ShareLink(item: latest) { Label("Share last game record", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("ondevice.shareGameRecord")
                    }
                    // Memory peak and heat per game, to compare builds on this phone. Nothing about cards or players.
                    if let performance = GamePerformanceLog.section(GamePerformanceLog.shared.entries) {
                        Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.4)
                        Text("Recent games' memory and heat, to compare app versions on this phone.").font(ArenaMenuStyle.font(12, .medium))
                        ShareLink(item: performance) { Label("Share game performance", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("ondevice.sharePerformance")
                        Text(performance).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArenaMenuStyle.dim).textSelection(.enabled)
                    }
                }
                .font(ArenaMenuStyle.font(14, .medium))
                .tint(ArenaMenuStyle.gold)
                .padding(16)
            }
            .task { await setup.captureDiagnostics(in: diagnostics) }
            .confirmationDialog("Delete the local engine report?", isPresented: $confirmDeleteReport, titleVisibility: .visible) {
                Button("Delete report", role: .destructive) {
                    Task { await setup.clearDiagnostics(in: diagnostics) }
                }
            } message: { Text("This removes the saved report and its in-memory copy. Reports you already shared are not removed.") }
        }
    }

    private func startMatchmaking() {
        guard let deck = selectedDeck else { return }
        do {
            playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName)
            diagnostics.beginAttempt()
            try setup.startMatchmaking(name: playerDisplayName, deck: deck, playerCount: playerCount,
                                      aiDecks: gameCenterAIDecks, aiSkill: aiSkill)
        } catch { setup.errorMessage = error.localizedDescription }
    }

    private func refresh() {
        Task { await setup.perform { try await session.refresh(); setup.updateSessionForeground() } }
    }

    private func restoreSetupPreferences() {
        let selected = OnDeviceSetupPreferences.normalize(
            .init(deckID: selectedDeckID, aiDeckID: aiPreconID, aiOpponents: opponentCount,
                  humanPlayers: playerCount, friends: playWithFriends, aiSkill: OnDeviceSetupPreferences.readAISkill(from: MagicMobilePreferences.current)),
            deckIDs: allDeckIDs,
            aiDeckIDs: AIDeckPool.all.map(\.id)
        )
        selectedDeckID = selected.deckID; aiPreconID = selected.aiDeckID
        let aiIDs = OnDeviceSetupPreferences.normalizedAIDeckIDs([aiPreconID, aiPrecon2ID, aiPrecon3ID], available: AIDeckPool.all.map(\.id))
        aiPrecon2ID = aiIDs[1]; aiPrecon3ID = aiIDs[2]
        opponentCount = selected.aiOpponents; playerCount = selected.humanPlayers
        aiSkill = selected.aiSkill
    }

    private func requestLeave() {
        guard !setup.isBusy, !session.isWorking else { return }
        confirmLeave = true
    }

    private func closeGame() {
        recordAbandonedRankedGame()
        Task {
            if await setup.close() {
                endGuidedGame()
                lessonRun = nil
                selectedCard = nil; inspectedCard = nil; zone = nil
                activeMatch = nil; rankChange = nil; ceremony = nil
                matchmaker.finish(); rankedConnectTask?.cancel()
            }
        }
    }

    private struct InspectedZone {
        let title: String
        let cards: [ZoneCard]
    }
}

@MainActor
private final class OnDeviceSetupModel: ObservableObject {
    @Published private(set) var identity: BuildIdentity?
    @Published private(set) var multiplayer: OnDeviceMultiplayer?
    @Published private(set) var isBusy = false
    @Published private(set) var usingMultiplayer = false
    @Published private(set) var closeFailed = false
    @Published private(set) var status = "Preparing local decks"
    @Published var errorMessage: String?
    @Published var feedback: String?
    /// XMage rejected the player's deck at Start; it is stored, and the setup screen explains it.
    @Published private(set) var startIssues: DeckStudioStartIssues?
    private let session: OnDeviceSession
    private let resume: GameResumeCoordinator
    private let runtime = OnDeviceRuntimeManager()
    /// The answer actions this phone's engine accepts (docs/PROTOCOL.md); empty on an older engine.
    private var engineAnswerActions: Set<String> {
        Set(runtime.capabilities?["answerActions"]?.array?.compactMap(\.string) ?? [])
    }
    /// Settings → Pass After Casting (on by default).
    private var autoPassAfterCastSetting: Bool {
        UserDefaults.standard.object(forKey: AutoPassAfterCast.key) as? Bool ?? true
    }
    private var resolver: OnDeviceDeckResolver?
    private var multiplayerObservation: AnyCancellable?
    private var resumeObservations: [AnyCancellable] = []
    private var aiClient: EngineClient?
    private var aiMatchID: String?
    private var sceneActive = true

    /// The human seat in a solo game (OnDeviceAppConfiguration.aiGameSeats).
    static let soloSeatID = "player1"

    init(session: OnDeviceSession, resume: GameResumeCoordinator) {
        self.session = session
        self.resume = resume
        resumeObservations = [
            // Keep the sidecar in step with the engine's latest save.
            session.$checkpoint.compactMap { $0 }.sink { [weak resume] in resume?.checkpointSaved($0) },
            // A finished game (win, loss or draw), or one this seat lost or left and now
            // spectates, is never offered again.
            session.$isOverForSeat.removeDuplicates().filter { $0 }
                .sink { [weak resume] _ in resume?.gameFinished() }
        ]
        // Saving when the player leaves goes to the live solo game's engine. The coordinator
        // asks only when that engine advertises checkpointOnDemand.
        resume.requestSave = { [weak self] wait in
            guard let client = self?.aiClient, let matchID = self?.aiMatchID else {
                return .unavailable(code: EngineSaveResume.matchUnavailableCode)
            }
            return try await client.requestCheckpoint(matchID: matchID, waitMillis: wait)
        }
        resume.cancelSave = { [weak self] in
            guard let client = self?.aiClient, let matchID = self?.aiMatchID else { return }
            try await client.cancelCheckpoint(matchID: matchID)
        }
    }

    var needsLeave: Bool { usingMultiplayer || runtime.isOpen || session.matchID != nil || multiplayer?.needsCleanup == true }
    var canUseSession: Bool {
        sceneActive && (!usingMultiplayer || (multiplayer?.isConnected == true && multiplayer?.isSuspended == false))
    }
    var liveStatus: String {
        if usingMultiplayer, let multiplayer, !multiplayer.isConnected || multiplayer.isSuspended { return multiplayer.status }
        return feedback ?? session.status
    }

    static func playerName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(name.count), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw EngineError.invalidMessage("Enter a player name with 1–24 characters and no line breaks.")
        }
        return name
    }

    /// Reads the deck resolver before the first screen is usable, so every screen can count on the
    /// build identity. The decoded catalogue is shared (OnDeviceDeckResolver.bundled), not read again.
    func prepare() {
        guard identity == nil else { return }
        do {
            let resolver = try OnDeviceDeckResolver.bundled()
            guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  !version.isEmpty, !build.isEmpty else {
                throw EngineError.invalidMessage("This app is missing its build identity. Install a complete app build.")
            }
            let identity = BuildIdentity(upstreamCommit: resolver.upstreamCommit, catalogueHash: resolver.catalogueHash,
                                         adapterVersion: "ondevice-0.1/app-\(version)/build-\(build)/rollstep-2/room-1/concede-1/emote-1/clock-1")
            let multiplayer = OnDeviceMultiplayer(identity: identity,
                makeHostEngine: { [runtime] in try await runtime.makeClient(identity: identity) },
                closeHostEngine: { [runtime] _ in try await runtime.close() })
            multiplayerObservation = multiplayer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            // Quiet sign-in with the phone's Game Center account; no sheet unless the player asks.
            multiplayer.authenticate(userInitiated: false)
            self.resolver = resolver; self.identity = identity; self.multiplayer = multiplayer
            errorMessage = nil; status = "Choose your deck and players."
        } catch { errorMessage = error.localizedDescription; status = "Local setup unavailable" }
    }

    /// A lesson: its recording answers for the engine (LessonTransport). No runtime, save or game record.
    func startLesson(_ script: LessonScript, run: LessonRun) async {
        guard !isBusy, !needsLeave else { return }
        isBusy = true; errorMessage = nil; feedback = nil; status = "Starting lesson"
        defer { isBusy = false }
        do {
            let client = EngineClient(transport: LessonTransport(script: script, run: run))
            updateSessionForeground()
            try await session.attach(client: client, matchID: script.matchID, seatID: script.viewer, close: {})
            status = "Lesson started"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAI(name: String, deck: DeckList, aiDecks: [DeckList], aiSkill: Int = 2,
                 deckID: String, aiDeckIDs: [String], startingPlayerMode: String,
                 mode: PlayMode? = nil, deckBracket: Int? = nil, seed: Int64? = nil, aiMistakePercent: Int? = nil) async {
        guard !isBusy, !needsLeave, let resolver, let identity else { return }
        isBusy = true; errorMessage = nil; feedback = nil; status = "Starting XMage"
        defer { isBusy = false }
        do {
            let name = try Self.playerName(name)
            let humanDeck = try resolver.resolve(deck)
            let opponentDecks = try aiDecks.map { try resolver.resolve($0) }
            let seats = try OnDeviceAppConfiguration.aiGameSeats(name: name, humanDeck: humanDeck,
                aiDecks: opponentDecks, aiSkill: aiSkill, aiMistakePercent: aiMistakePercent)
            let client = try await runtime.makeClient(identity: identity)
            aiClient = client
            // A ranked game's server seed, on engines that keep a game record (docs/PROTOCOL.md "Game record").
            var configuration: [String: MagicMobileOnDevice.JSONValue] = ["seats": .array(seats)]
            if let seed, runtime.capabilities?["gameRecord"] != nil { configuration["seed"] = .integer(seed) }
            // Checkpointed only when this engine advertises saveResume; otherwise sent unchanged.
            let plan = resume.planSoloGame(configuration: .object(configuration), capabilities: runtime.capabilities)
            let created = try await runtime.create(client: client, configuration: plan.configuration)
            guard let matchID = created["matchId"]?.string, !matchID.isEmpty else {
                throw EngineError.invalidMessage("XMage did not return a match ID. Close the runtime before trying again.")
            }
            aiMatchID = matchID
            resume.soloGameStarted(plan, setup: GameResumeSetup(
                configuration: plan.baseConfiguration, seatID: Self.soloSeatID, playerName: name, deckID: deckID,
                aiDeckIDs: aiDeckIDs, aiSkill: aiSkill, startingPlayerMode: startingPlayerMode,
                mode: mode?.rawValue, deckBracket: deckBracket), playerDeckName: deck.name)
            updateSessionForeground()
            try await session.attach(client: client, matchID: matchID, seatID: Self.soloSeatID, pollReader: runtime.clientTransport.map { OnDevicePollReader(transport: $0) },
                                     allowsSeatScopedAutoYield: true,
                                     answerActions: engineAnswerActions, autoPassAfterCast: autoPassAfterCastSetting, smartPass: .load(), close: { [self] in try await closeAI() })
            status = "Game started"
            // XMage checked every deck when it created the game: the player's deck passed.
            recordStartPass(deckID: deckID, deck: deck)
        } catch {
            errorMessage = error.localizedDescription
            // A rejection of the player's deck is stored like a Deck Studio check and explained.
            if let rejection = DeckStudioStartRejection(error),
               let check = rejection.check(deckID: deckID, deck: deck, resolver: resolver,
                                           appBuild: DeckStudioValidationService.appBuild, store: .shared) {
                DeckStudioReceiptStore.shared.record(check)
                startIssues = DeckStudioStartIssues(name: deck.name, check: check)
            }
            if !runtime.isOpen, aiMatchID == nil { aiClient = nil }
            status = needsLeave ? "Game startup interrupted. Refresh or leave before starting again." : "Unable to start local game"
        }
    }

    /// The finished solo game's record (the engine's `record` op), fetched before the match is destroyed. Nil on engines
    /// without game records, outside a solo game, or when recording stopped (`broken`). Local only: never sent to an
    /// online opponent; a ranked AI result uploads it.
    func finishedGameRecord() async -> Data? {
        guard runtime.capabilities?["gameRecord"] != nil, let aiClient, let aiMatchID,
              let record = try? await aiClient.call("record", fields: ["matchId": .string(aiMatchID)]),
              record["format"]?.string == "magicmobile-game-record", record["broken"] == nil else { return nil }
        return try? record.encoded()
    }

    /// Restores a saved solo game. On any failure the save is deleted, the player is told,
    /// and the app stays on the menu.
    func resumeAI(_ record: GameResumeRecord) async -> Bool {
        guard !isBusy, !needsLeave, let identity else { resume.restoreFailed(); return false }
        isBusy = true; errorMessage = nil; feedback = nil; status = "Resuming your game"
        defer { isBusy = false }
        do {
            let client = try await runtime.makeClient(identity: identity)
            aiClient = client
            let restored = try await resume.restore(record, capabilities: runtime.capabilities) { path in
                try await runtime.restore(client: client, checkpointPath: path)
            }
            aiMatchID = restored.matchID
            updateSessionForeground()
            try await session.attach(client: client, matchID: restored.matchID, seatID: record.setup.seatID,
                                     pollReader: runtime.clientTransport.map { OnDevicePollReader(transport: $0) },
                                     allowsSeatScopedAutoYield: true, answerActions: engineAnswerActions,
                                     autoPassAfterCast: autoPassAfterCastSetting, smartPass: .load(), close: { [self] in try await closeAI() })
            status = "Game resumed"
            return true
        } catch {
            resume.restoreFailed()
            if session.matchID != nil { try? await session.close() }
            else if aiMatchID != nil { try? await closeAI() }
            else if runtime.isOpen { try? await runtime.close() }
            if !runtime.isOpen { aiClient = nil; aiMatchID = nil }
            status = "Choose your deck and players."
            return false
        }
    }

    func startMatchmaking(name: String, deck: DeckList, playerCount: Int,
                          aiDecks: [DeckList], aiSkill: Int) throws {
        guard !isBusy, !needsLeave, let resolver, let multiplayer else {
            throw EngineError.invalidMessage("Close the current match before finding players.")
        }
        let name = try Self.playerName(name)
        let bots = try aiDecks.map { try OnDeviceMultiplayer.AISeatDescriptor(deck: resolver.resolve($0), skill: aiSkill) }
        _ = try multiplayer.makeMatchmaker(playerCount: playerCount, name: name,
                                          deck: resolver.resolve(deck), aiSeats: bots)
        usingMultiplayer = true; errorMessage = nil; feedback = nil
        status = "Connecting Game Center players"
        updateSessionForeground()
    }

    /// Cross-play tables share one identity on iPhone and Android: protocol, rules source, card
    /// registry and table features. App build numbers differ between the platforms, so they are left out.
    var relayIdentity: BuildIdentity? {
        identity.map { BuildIdentity(upstreamCommit: $0.upstreamCommit, catalogueHash: $0.catalogueHash,
                                     adapterVersion: "ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1/chat-1/clock-1") }
    }

    /// Opens a cross-play table this phone hosts: `playerCount` people plus any AI seats.
    func hostRelay(name: String, deck: DeckList, playerCount: Int, aiDecks: [DeckList], aiSkill: Int) async {
        guard !isBusy, !needsLeave, let resolver, let multiplayer, let relayIdentity else { return }
        isBusy = true; errorMessage = nil; feedback = nil
        defer { isBusy = false }
        do {
            let name = try Self.playerName(name)
            let bots = try aiDecks.map { try OnDeviceMultiplayer.AISeatDescriptor(deck: resolver.resolve($0), skill: aiSkill) }
            let resolved = try resolver.resolve(deck)
            usingMultiplayer = true
            updateSessionForeground()
            try await multiplayer.hostRelay(humans: playerCount, name: name, deck: resolved, aiSeats: bots, relayIdentity: relayIdentity)
        } catch {
            errorMessage = error.localizedDescription
            // Nothing was opened: the setup stays free to start again.
            if multiplayer.tableCode == nil { usingMultiplayer = false; updateSessionForeground() }
        }
    }

    /// Joins another player's cross-play table by its code.
    func joinRelay(code: String, name: String, deck: DeckList) {
        guard !isBusy, !needsLeave, let resolver, let multiplayer, let relayIdentity else { return }
        errorMessage = nil; feedback = nil
        do {
            let name = try Self.playerName(name)
            let resolved = try resolver.resolve(deck)
            usingMultiplayer = true
            updateSessionForeground()
            try multiplayer.joinRelay(code: code, name: name, deck: resolved, relayIdentity: relayIdentity)
        } catch {
            errorMessage = error.localizedDescription
            if multiplayer.tableCode == nil { usingMultiplayer = false; updateSessionForeground() }
        }
    }

    /// Match room: confirm the currently selected deck and ready up.
    func readyForMatch(name: String, deck: DeckList) {
        guard let resolver, let multiplayer else { return }
        do { try multiplayer.markReady(name: Self.playerName(name), deck: resolver.resolve(deck)) }
        catch { errorMessage = error.localizedDescription }
    }

    /// `deck` is the local player's playing deck; the table locks it once the game starts.
    func attachMultiplayer(deckID: String, deck: DeckList?) async {
        guard usingMultiplayer, !isBusy, session.matchID == nil,
              let multiplayer, let endpoint = multiplayer.endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            updateSessionForeground()
            // A table seats only phones with this exact build, so this phone's engine speaks for the host's.
            try await session.attach(client: endpoint.client, matchID: endpoint.matchID, seatID: endpoint.seatID,
                                     allowsSeatScopedAutoYield: true, table: endpoint.table,
                                     answerActions: engineAnswerActions, autoPassAfterCast: autoPassAfterCastSetting, smartPass: .load(),
                                     close: { try await multiplayer.leave() })
            resume.tableGameStarted()
            // Only the host's engine created this game, so only the host's deck check is local.
            if endpoint.isHost, let deck { recordStartPass(deckID: deckID, deck: deck) }
            status = multiplayer.isRelayTable ? "Table connected" : "Game Center match connected"
        } catch { errorMessage = error.localizedDescription }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { multiplayer?.onResumed() } else { multiplayer?.onSuspended() }
        updateSessionForeground()
    }

    func updateSessionForeground() { session.setForeground(canUseSession) }

    func perform(reportingBusy: Bool = false, _ operation: @MainActor () async throws -> Void) async {
        guard !isBusy, !session.isWorking, canUseSession else {
            // A dropped tap is intentional; a dropped automatic reply must not look like progress.
            if reportingBusy { errorMessage = String(localized: "The game was busy. Choose again to continue.") }
            return
        }
        errorMessage = nil; feedback = nil
        do { try await operation() } catch { if !error.isLessonNudge { errorMessage = error.localizedDescription } }
    }

    /// Waits up to 3 seconds for the current response and its refresh to finish.
    func waitUntilSessionIdle() async {
        for _ in 0..<150 where isBusy || session.isWorking { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func close() async -> Bool {
        guard !isBusy, !session.isWorking else { return false }
        // Leaving forgets the saved game, even when cleanup has to be retried.
        resume.gameFinished()
        isBusy = true; status = "Closing game"; errorMessage = nil
        defer { isBusy = false }
        do {
            if session.matchID != nil { try await session.close() }
            else if usingMultiplayer { try await multiplayer?.leave() }
            else { try await closeAI() }
            // A failed host factory can retain its handle before Game Center owns
            // an EngineClient. Leave succeeds in that case; the root still owns cleanup.
            if runtime.isOpen { try await runtime.close() }
            usingMultiplayer = false; closeFailed = false; feedback = nil
            status = "Game closed"; updateSessionForeground()
            return true
        } catch {
            closeFailed = true; errorMessage = error.localizedDescription
            status = "Closing failed. Retry closing to release the current game."
            return false
        }
    }

    private func closeAI() async throws {
        if let client = aiClient, let matchID = aiMatchID {
            try await runtime.closeMatch(client: client, matchID: matchID)
            aiMatchID = nil
        } else {
            try await runtime.close()
        }
        aiClient = nil
    }

    func localHealth() -> EngineHealth {
        let connected = usingMultiplayer
            ? multiplayer?.isConnected == true && multiplayer?.isSuspended == false
            : runtime.isOpen
        let reason = usingMultiplayer
            ? "Game Center connection: \(multiplayer?.status ?? "unavailable")"
            : "Local runtime \(runtime.isOpen ? "open" : "closed"); capabilities \(runtime.capabilities == nil ? "unavailable" : "loaded")."
        return EngineHealth(status: connected ? "ok" : "unavailable", reason: reason,
                            checkedAt: ISO8601DateFormatter().string(from: Date()), recoveryAction: nil)
    }

    func captureDiagnostics(in store: OnDeviceDiagnostics) async {
        await store.capture(status: session.status) { try await runtime.diagnosticReport() }
    }

    func clearDiagnostics(in store: OnDeviceDiagnostics) async {
        do {
            try await store.clear(engine: { try await runtime.clearDiagnostics() })
        } catch { store.errorMessage = "Could not delete the local engine report: \(error.localizedDescription)" }
    }
}

private extension OnDeviceSetupModel {
    /// The setup screen reads deck check status with the same resolver games use.
    var deckResolver: OnDeviceDeckResolver? { resolver }

    /// A game this phone's engine created is a passed Commander check for the player's deck.
    func recordStartPass(deckID: String, deck: DeckList) {
        guard let resolver, let pass = DeckStudioStartRejection.pass(deckID: deckID, deck: deck, resolver: resolver,
                                                                    appBuild: DeckStudioValidationService.appBuild) else { return }
        DeckStudioReceiptStore.shared.record(pass)
    }
}

@MainActor
private struct OnDeviceGameCenterPresentation: View {
    @ObservedObject var multiplayer: OnDeviceMultiplayer
    @State private var presentation: ControllerPresentation?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(multiplayer.$authenticationController) { controller in
                if let controller { presentation = ControllerPresentation(controller: controller) }
                else if presentation?.controller is GKMatchmakerViewController == false { presentation = nil }
            }
            .onReceive(multiplayer.$matchmakerController) { controller in
                if let controller { presentation = ControllerPresentation(controller: controller) }
                else if presentation?.controller is GKMatchmakerViewController { presentation = nil }
            }
            .sheet(item: $presentation) { item in
                OnDeviceControllerView(controller: item.controller).interactiveDismissDisabled()
            }
    }

    private struct ControllerPresentation: Identifiable {
        let controller: UIViewController
        var id: ObjectIdentifier { ObjectIdentifier(controller) }
    }
}

private struct OnDeviceControllerView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
private struct OnDeviceTextImportView: View {
    @ObservedObject var library: DeckLibraryStore
    @Binding var selectedDeckID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Imported Commander Deck"
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name", text: $name)
                    TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 220)
                        .accessibilityLabel("Deck list text")
                } header: {
                    Text("Deck")
                } footer: {
                    Text("Use Commander, Deck, and Companion headings, then one card per line, such as 1 Sol Ring. Card names must match this app’s local catalogue.")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MagicPalette.warningAmber) } }
                Button("Import and use deck") {
                    do {
                        let resolver = try OnDeviceDeckResolver.bundled()
                        let deck = try resolver.importDeck(text: text, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        let record = try library.addLocalDurably(deck)
                        selectedDeckID = "local:\(record.id)"
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .scrollContentBackground(.hidden)
            .background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Import deck text").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Host or join a cross-play table (iPhone and Android) through the relay, then the match room.
/// The root re-renders on every multiplayer change (the setup model re-publishes them).
@MainActor
private struct RelayTablePanel: View {
    let multiplayer: OnDeviceMultiplayer?
    @Binding var code: String
    let mayEnter: Bool
    let locked: Bool
    @Binding var aiCount: Int
    let maxAI: Int
    let aiDeckSelection: (Int) -> Binding<String>
    @Binding var aiSkill: Int
    let deckName: String?
    let localCommander: String?
    let host: () -> Void
    let join: (String) -> Void
    let ready: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let multiplayer, multiplayer.isRelayTable, multiplayer.tableCode != nil {
                activeTable(multiplayer)
            } else {
                TavernStepper(title: "AI opponents: \(aiCount)", value: $aiCount, range: 0...maxAI,
                              identifier: "ondevice.relay.aiCount")
                    .disabled(locked)
                ForEach(0..<aiCount, id: \.self) { index in
                    TavernPicker(title: "AI \(index + 1) deck", selection: aiDeckSelection(index),
                                 sections: [.init(options: PreconCatalog.all.map { ($0.name, $0.id) })])
                        .disabled(locked)
                }
                if aiCount > 0 {
                    TavernStepper(title: "AI skill: \(aiSkill)", value: $aiSkill, range: 1...10).disabled(locked)
                    Text("The host’s AI choices apply to everyone. Higher skill may slow turns.")
                        .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                }
                Text("Share the invite link, or friends type the table code. Every player needs this app version and keeps it open during the match.")
                    .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                Button("Host a table", action: host)
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 18))
                    .frame(height: 46)
                    .disabled(!mayEnter)
                    .accessibilityIdentifier("ondevice.relay.host")
                BrandDivider(title: "or join")
                TextField("Table code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .modifier(TavernFieldChrome(tavern: true))
                    .font(.system(size: 17, weight: .bold, design: .serif)).tracking(2)
                    .onChange(of: code) { _, value in
                        let clean = String(value.uppercased().filter { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }.prefix(6))
                        if clean != value { code = clean }
                    }
                    .disabled(locked)
                    .accessibilityIdentifier("ondevice.relay.code")
                Button("Join table") { join(code) }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                    .disabled(!mayEnter || code.count != 6)
                    .accessibilityIdentifier("ondevice.relay.join")
            }
        }
    }

    @ViewBuilder
    private func activeTable(_ multiplayer: OnDeviceMultiplayer) -> some View {
        if let tableCode = multiplayer.tableCode {
            VStack(spacing: 6) {
                Text("TABLE CODE").font(ArenaMenuStyle.font(10.5, .heavy)).tracking(1.6).foregroundStyle(ArenaMenuStyle.gold)
                Text(stride(from: 0, to: tableCode.count, by: 3).map { start -> String in
                    let from = tableCode.index(tableCode.startIndex, offsetBy: start)
                    return String(tableCode[from..<tableCode.index(from, offsetBy: min(3, tableCode.count - start))])
                }.joined(separator: " "))
                    .font(.system(size: 34, weight: .black, design: .serif)).tracking(3).foregroundStyle(ArenaMenuStyle.text)
                    .accessibilityLabel("Table code \(tableCode)")
                    .accessibilityIdentifier("ondevice.relay.tableCode")
                if multiplayer.room == nil, multiplayer.endpoint == nil, !multiplayer.isFailed {
                    Text("Players \(multiplayer.seatsTaken)/\(max(2, multiplayer.seatsWanted))")
                        .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    if let link = TableJoinLink.url(code: tableCode) {
                        ShareLink(item: link, subject: Text("Join my MagicMobile table"),
                                  message: Text("Tap to join my MagicMobile table (code \(tableCode)).")) {
                            Label("Share invite link", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("ondevice.relay.share")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
        }
        Text(multiplayer.status).font(ArenaMenuStyle.font(13, .medium))
        if multiplayer.room == nil, multiplayer.endpoint == nil, !multiplayer.isFailed, !multiplayer.waitingSeats.isEmpty {
            RelayWaitingRoomView(seats: multiplayer.waitingSeats) { multiplayer.removeFromTable($0) }
        }
        if let room = multiplayer.room {
            MatchRoomView(room: room, deckName: deckName, localCommander: localCommander, ready: ready)
        }
    }
}

/// A relay table that is still filling: who has joined and, for the host, a Remove control per joiner.
@MainActor
private struct RelayWaitingRoomView: View {
    let seats: [RelayWaitingSeat]
    let remove: (String) -> Void
    @State private var removal: RelayWaitingSeat?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AT THE TABLE").font(ArenaMenuStyle.font(10.5, .heavy)).tracking(1.6)
                .foregroundStyle(ArenaMenuStyle.gold)
            ForEach(Array(seats.enumerated()), id: \.element.id) { index, seat in
                HStack(spacing: 10) {
                    Image(systemName: seat.connected ? "person.crop.circle" : "wifi.exclamationmark")
                        .font(.system(size: 18)).foregroundStyle(ArenaMenuStyle.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(seat.name).font(ArenaMenuStyle.font(15, .bold))
                            if seat.isHost {
                                TavernTag(text: "HOST")
                            }
                        }
                        Text(seat.isLocal ? "You" : seat.connected ? "Joined" : "Reconnecting…")
                            .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    }
                    Spacer()
                    if seat.removable {
                        Button("Remove", role: .destructive) { removal = seat }
                            .font(ArenaMenuStyle.font(14, .semibold)).foregroundStyle(ArenaMenuStyle.loss)
                            .accessibilityLabel("Remove \(seat.name)")
                            .accessibilityIdentifier("ondevice.relay.remove.\(index + 1)")
                    }
                }
            }
            if seats.contains(where: \.removable) {
                Text("Remove anyone you did not invite. The match room opens when every seat is taken.")
                    .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
        .confirmationDialog("Remove \(removal?.name ?? "this player") from the table?",
                            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                            titleVisibility: .visible, presenting: removal) { seat in
            Button("Remove", role: .destructive) { remove(seat.id) }
        } message: { _ in
            Text("Their seat opens for someone else. Anyone with the code can still join.")
        }
    }
}

/// Game Center pregame room: who is here, who is ready, and their commanders.
@MainActor
private struct MatchRoomView: View {
    let room: OnDeviceMultiplayer.MatchRoom
    let deckName: String?
    let localCommander: String?
    let ready: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MATCH ROOM").font(ArenaMenuStyle.font(10.5, .heavy)).tracking(1.6)
                .foregroundStyle(ArenaMenuStyle.gold)
            ForEach(room.players) { player in
                let commanders = player.isLocal && !room.localReady ? (localCommander.map { [$0] } ?? []) : player.commanders
                HStack(spacing: 10) {
                    CommanderDeckPortrait(name: commanders.first, namespace: nil)
                        .frame(width: 40, height: 56)
                        .opacity(player.isReady ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.name).font(ArenaMenuStyle.font(15, .bold))
                            if player.isHost {
                                TavernTag(text: "HOST")
                            }
                        }
                        Text(commanders.isEmpty ? (player.isReady ? "Ready" : "Choosing a deck…")
                             : commanders.joined(separator: " & "))
                            .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: player.isReady ? "checkmark.circle.fill" : "hourglass")
                        .font(.title3)
                        .foregroundStyle(player.isReady ? ArenaMenuStyle.gold : ArenaMenuStyle.dim)
                        .accessibilityLabel(player.isReady ? "Ready" : "Not ready")
                }
                .accessibilityElement(children: .combine)
            }
            if let aiSummary = room.aiSummary { Text(aiSummary).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim) }
            if room.localReady {
                Label("You're ready. The game starts when everyone is.", systemImage: "checkmark.seal.fill")
                    .font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.gold)
            } else {
                Text("Pick your deck above, then ready up\(deckName.map { " with \($0)" } ?? "").")
                    .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                Button("Ready") { ready() }
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 18))
                    .frame(height: 46)
                    .disabled(deckName == nil)
                    .accessibilityIdentifier("ondevice.matchRoom.ready")
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
    }
}

/// iOS background time for saving the game when the player leaves the app.
@MainActor
private enum ResumeBackgroundTask {
    static func run(_ name: String, _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let token = Token()
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { token.end() }
        }
        return Task { @MainActor in
            await body()
            token.end()
        }
    }

    @MainActor
    private final class Token {
        var identifier = UIBackgroundTaskIdentifier.invalid
        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}

/// A player whose profile is open over the table chat.
private struct MessageBannerItem: Equatable {
    let id = UUID()
    let name: String
    let text: String
}

private struct MessagesHubTarget: Identifiable {
    let name: String?
    let id = UUID()
}

private struct ChatProfileTarget: Identifiable {
    let name: String
    var id: String { name }
}
