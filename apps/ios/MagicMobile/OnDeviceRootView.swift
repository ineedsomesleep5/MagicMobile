import SwiftUI
import Combine
import UIKit
import GameKit
import MagicMobileOnDevice

/// Native setup and lifecycle wiring around the existing portrait/landscape board.
@MainActor
struct OnDeviceRootView: View {
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @AppStorage(PortraitModePreference.key) private var portraitModeEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Namespace private var commanderTransition
    @StateObject private var session: OnDeviceSession
    @StateObject private var setup: OnDeviceSetupModel
    @StateObject private var library = DeckLibraryStore()
    @StateObject private var diagnostics: OnDeviceDiagnostics
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
    @AppStorage("magicmobile.onlineMode") private var playOnline = false
    @State private var showSetup = false
    @State private var showAppearance = false
    @State private var showUpdates = false
    @State private var showDownloads = false
    @State private var showImport = false
    @State private var confirmLeave = false
    @StateObject private var emotes = EmoteCenter()
    @State private var showDiagnostics = false
    @State private var confirmDeleteReport = false
    @State private var bannerError: String?
    @State private var didDismissStartingRoll = false
    @State private var attemptedStartingPromptID: String?
    @State private var aiStartingRoll: OnDeviceStartingRoll?
    @State private var aiRevealedRollCount = 0
    @State private var aiRollSeatNames: [String: String] = [:]
    @State private var versusIntro: VersusIntro?

    private struct VersusIntro {
        let you: VersusIntroOverlay.Seat
        let opponents: [VersusIntroOverlay.Seat]
    }

    /// Seats for the intro: the table's own players when known, else the chosen decks.
    private func makeVersusIntro() -> VersusIntro {
        let name = playerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let you = VersusIntroOverlay.Seat(id: "you", name: name.isEmpty ? "You" : name,
                                          commander: selectedDeck?.commander?.cardName)
        if let snapshot = session.snapshot {
            let others = snapshot.players.filter { !snapshot.isViewer($0.playerId) }.prefix(3).map {
                VersusIntroOverlay.Seat(id: $0.playerId, name: $0.displayName ?? "Opponent",
                                        commander: $0.zones.command.first?.card.name)
            }
            if !others.isEmpty { return VersusIntro(you: you, opponents: Array(others)) }
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
        _session = StateObject(wrappedValue: session)
        _setup = StateObject(wrappedValue: OnDeviceSetupModel(session: session))
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

    private var activeGame: Bool { session.matchID != nil }
    private var aiPrecon: PreconDeck? { PreconCatalog.all.first { $0.id == aiPreconID } }
    private var aiPrecons: [PreconDeck] {
        [aiPreconID, aiPrecon2ID, aiPrecon3ID].prefix(min(3, max(1, opponentCount)))
            .compactMap { id in PreconCatalog.all.first { $0.id == id } }
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
    private var selectedDeck: DeckList? {
        if let precon = PreconCatalog.all.first(where: { "precon:\($0.id)" == selectedDeckID }) {
            return precon.deckList
        }
        return library.decks.first(where: { "local:\($0.id)" == selectedDeckID })?.deckList
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
            .compactMap { id in PreconCatalog.all.first { $0.id == id }?.deckList }
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
            stop: { session.stopAutoPass() }
        )
    }

    private var presentedContent: some View {
        ZStack {
            if activeGame {
                game
                if let versusIntro {
                    VersusIntroOverlay(you: versusIntro.you, opponents: versusIntro.opponents) { self.versusIntro = nil }
                        .transition(.opacity)
                        .zIndex(10)
                }
            } else {
                BrandTheme.canvas.ignoresSafeArea()
                if showSetup || setup.needsLeave {
                    setupContent
                } else {
                    TavernMainMenu(deckName: selectedDeck?.name ?? "Choose a deck", playerName: playerDisplayName,
                                   play: { showSetup = true }, decks: { showImport = true },
                                   settings: { showAppearance = true }, news: { showUpdates = true },
                                   commanderName: selectedDeck?.commander?.cardName,
                                   commanderNamespace: reduceMotion ? nil : commanderTransition,
                                   downloads: { showDownloads = true })
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.26), value: showSetup)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: activeGame)
        // Menu ambience pauses while anything covers the menu.
        .environment(\.brandAmbientMotion, !(showImport || showAppearance || showUpdates || showDownloads || showDiagnostics))
        .sheet(isPresented: $showAppearance) { AppearanceSettingsView(portraitModeEnabled: $portraitModeEnabled) }
        .sheet(isPresented: $showUpdates) { NativeUpdateNewsView(upstreamCommit: setup.identity?.upstreamCommit) }
        .sheet(isPresented: $showDownloads) {
            NativeDownloadsView(decks: downloadDecks, selectedDeckID: selectedDeckID,
                                engineReady: setup.identity != nil)
        }
        .overlay(alignment: .bottom) { recoveryBanner }
        .overlay { startingRollOverlay }
        .environment(\.nativeTurnControl, turnControl)
        .fullScreenCover(isPresented: $showImport) {
            DeckStudioRootView(library: library, selectedDeckID: $selectedDeckID, preparePlay: {
                showImport = false; showSetup = true
            })
        }
        .sheet(isPresented: $showDiagnostics) { diagnosticSheet }
        .background {
            if let multiplayer = setup.multiplayer {
                OnDeviceGameCenterPresentation(multiplayer: multiplayer)
            }
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave game", role: .destructive) { closeGame() }
        } message: {
            Text(setup.usingOnline ? "Leaving ends this online match for every player."
                 : setup.multiplayer?.endpoint?.isHost == true
                 ? "You are hosting. Leaving ends this match for everyone; it cannot be resumed."
                 : "This closes the current match. It cannot be resumed after leaving.")
        }
    }

    private func preparePresentation() async {
        MagicMobileOrientationController.shared.setPortraitModeEnabled(portraitModeEnabled)
        restoreSetupPreferences()
        setup.prepare()
        setup.setSceneActive(scenePhase == .active)
        #if DEBUG
        if OnDeviceAppConfiguration.entryPoint == .setupPreview,
           ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_ENGINE_ERROR"] == "1" {
            try? diagnostics.save(engineReport: "UI TEST FIXTURE: Sample engine incident", status: "Presentation test")
            setup.errorMessage = "UI test fixture: engine incident."
        }
        #endif
    }

    private var lifecycleContent: some View {
        presentedContent.holdInspectionScope().task { await preparePresentation() }
        .onChange(of: library.decks.map(\.id)) { _, _ in
            if !activeGame { restoreSetupPreferences() }
        }
        .onChange(of: portraitModeEnabled) { _, enabled in
            MagicMobileOrientationController.shared.setPortraitModeEnabled(enabled)
        }
        .onChange(of: scenePhase) { _, phase in
            setup.setSceneActive(phase == .active)
            if phase == .active { GameAudio.shared.resume() }
        }
        .onAppear { GameAudio.shared.setScene(activeGame ? .game : .menu) }
        .onChange(of: activeGame) { _, playing in
            GameAudio.shared.setScene(playing ? .game : .menu)
            guard playing else { versusIntro = nil; return }
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
            if matchID != nil { Task { await setup.attachMultiplayer() } }
        }
        .onChange(of: setup.online.lobby?.matchId) { _, matchID in
            if matchID != nil { Task { await setup.attachOnline() } }
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
        .onChange(of: setup.isBusy) { _, busy in
            if !busy { submitStartingChoiceIfNeeded() }
        }
        .onChange(of: session.matchID) { _, _ in
            didDismissStartingRoll = false
            attemptedStartingPromptID = nil
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

    @ViewBuilder
    private var startingRollOverlay: some View {
        if setup.usingMultiplayer, let multiplayer = setup.multiplayer,
           multiplayer.endpoint != nil, multiplayer.isConnected,
           !didDismissStartingRoll {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(multiplayer.startingRoll == nil ? 0.82 : 0.58).ignoresSafeArea()
                    Group {
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
                            VStack(spacing: 16) {
                                Text("Who goes first?")
                                    .font(.title2.bold())
                                Text(multiplayer.rollStatus)
                                    .font(.subheadline).multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                Text(multiplayer.hostAISeatSummary ?? "Each player rolls a D20. Highest starts; ties reroll.")
                                    .font(.caption).multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                Button(multiplayer.hasRolled ? "Waiting for other players…" : "Roll D20") {
                                    do { try multiplayer.rollStartingPlayer() }
                                    catch { bannerError = error.localizedDescription }
                                }
                                .buttonStyle(CommanderActionStyle())
                                .disabled(multiplayer.hasRolled)
                                .accessibilityIdentifier("ondevice.multiplayer.roll")
                            }
                            .foregroundStyle(CommanderPresentation.ink)
                            .padding(24)
                            .frame(maxWidth: 440)
                            .background(CommanderPresentation.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        } else if !setup.usingMultiplayer, !setup.usingOnline,
                  session.matchID != nil, aiStartingPlayerMode == "roll",
                  let roll = aiStartingRoll, !didDismissStartingRoll {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.58).ignoresSafeArea()
                    MultiplayerD20View(roll: roll, seatNames: aiRollSeatNames,
                                       isLocalWinner: roll.winnerSeatID == session.snapshot?.viewerID,
                                       revealedStepCount: aiRevealedRollCount,
                                       localSeatID: session.snapshot?.viewerID,
                                       onRollTap: advanceLocalAIRoll,
                                       onStepPlayed: advanceAIRollIfNeeded) {
                        didDismissStartingRoll = true
                        submitStartingChoiceIfNeeded()
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
    }

    private func prepareAIRollIfNeeded() {
        guard !setup.usingMultiplayer, !setup.usingOnline,
              aiStartingPlayerMode == "roll", session.matchID != nil,
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

    private func submitStartingChoiceIfNeeded() {
        guard didDismissStartingRoll,
              !setup.isBusy, !session.isWorking, setup.canUseSession,
              let snapshot = session.snapshot,
              let promptID = snapshot.promptEnvelopeV2?.id,
              attemptedStartingPromptID != promptID else { return }
        let command: GameCommand?
        let winnerName: String
        if setup.usingMultiplayer, let multiplayer = setup.multiplayer,
           let roll = multiplayer.startingRoll,
           let name = multiplayer.seatNames[roll.winnerSeatID] {
            winnerName = name
            command = OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerName: name)
        } else if !setup.usingOnline, aiStartingPlayerMode == "roll", let roll = aiStartingRoll {
            winnerName = aiRollSeatNames[roll.winnerSeatID] ?? "winner"
            command = OnDeviceStartingPlayerChoice.command(snapshot: snapshot, winnerPlayerID: roll.winnerSeatID)
        } else {
            return
        }
        guard let command else { return }
        attemptedStartingPromptID = promptID
        Task { await setup.perform {
            try await session.send(command, label: "Start with \(winnerName)", actionID: "starting-roll-\(promptID)")
        } }
    }

    private var game: some View {
        ImmersivePlayShell(
            snapshot: session.snapshot, startupStatus: nil,
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
        .overlay { zoneOverlay }
        .environment(\.inspectorBattlefield, session.snapshot?.visibleBattlefield ?? [])
        .disabled(setup.isBusy)
        .environment(\.gameRematchTitle, setup.usingMultiplayer || setup.usingOnline ? nil : "Rematch")
        .environment(\.gameConcede, setup.usingOnline ? nil : GameConcedeHandler(concede: concede))
        .environment(\.emoteCenter, setup.usingOnline ? nil : emotes)
        .onAppear { connectEmotes() }
        .onChange(of: session.snapshot?.id) { _, _ in emotes.reset(); connectEmotes() }
    }

    /// Game Center games carry quick chat between devices; solo games only answer from the AI.
    private func connectEmotes() {
        let multiplayer = setup.usingMultiplayer ? setup.multiplayer : nil
        emotes.send = multiplayer.map { match in { emote in match.sendEmote(emote) } }
        multiplayer?.onEmote = { [weak emotes = self.emotes, weak session = self.session] name, emote in
            emotes?.receive(emote, fromName: name, in: session?.snapshot)
        }
    }

    /// XMage records the loss. In a pod the others play on and you can watch.
    private func concede() {
        Task {
            do {
                try await session.concede()
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
        guard session.snapshot?.isCompleted == true, !setup.usingMultiplayer, !setup.usingOnline else { return requestLeave() }
        Task {
            guard await setup.close() else { return }
            selectedCard = nil; inspectedCard = nil; zone = nil
            startAI()
        }
    }

    /// A finished game closes straight to the main menu; a live one still asks first.
    private func leaveFinishedOrAsk() {
        // Solo games you already conceded leave at once; a host still warns the table.
        let spectatingSolo = session.snapshot?.isSpectating == true && !setup.usingMultiplayer && !setup.usingOnline
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

    private var downloadDecks: [NativeDownloadDeck] {
        PreconCatalog.all.map { NativeDownloadDeck(id: "precon:\($0.id)", deck: $0.deckList) }
        + library.decks.map { NativeDownloadDeck(id: "local:\($0.id)", deck: $0.deckList) }
    }

    private var setupContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        GameAudio.shared.play(.uiBack)
                        showSetup = false
                    } label: { Label("Main menu", systemImage: "chevron.left") }
                        .font(.body.weight(.semibold))
                        .disabled(setup.isBusy || setup.needsLeave)
                    Spacer()
                    Button {
                        GameAudio.shared.play(.uiOpen)
                        showAppearance = true
                    } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
                Text("Your next game.").brandTitle(34)
                Text("Choose your deck. Take your seat.")
                    .font(.subheadline).foregroundStyle(CommanderPresentation.secondary)
                setupDecks
                VStack(alignment: .leading, spacing: 12) {
                    BrandDivider(title: "Your seat")
                    TextField("Player name", text: $playerDisplayName)
                        .textContentType(.nickname).autocorrectionDisabled()
                        .padding(12).background(CommanderPresentation.canvas, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BrandTheme.border, lineWidth: 1))
                        .accessibilityIdentifier("ondevice.playerName")
                    Text("Choose a name with 1–24 characters.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Auto-Rotate", isOn: $portraitModeEnabled)
                        .font(.subheadline).tint(CommanderPresentation.accent)
                    Picker("Your deck", selection: $selectedDeckID) {
                        Section("Included precons") {
                            ForEach(PreconCatalog.all) { Text($0.name).tag("precon:\($0.id)") }
                        }
                        Section("Saved on this device") {
                            ForEach(library.decks) { Text($0.name).tag("local:\($0.id)") }
                        }
                    }
                    Button { showImport = true } label: { Label("Browse, import or edit decks", systemImage: "rectangle.stack.badge.plus") }
                        .buttonStyle(CommanderActionStyle(primary: false))
                    NativeArtworkPreferenceView()
                }
                .commanderPanel()
                .disabled(setup.isBusy || (setup.needsLeave && !editableInRoom))

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Players", selection: playerMode) {
                        Text("AI").tag("ai")
                        Text("Game Center").tag("gamecenter")
                        Text("Online").tag("online")
                    }.pickerStyle(.segmented).disabled(setup.isBusy || setup.needsLeave)
                    if playWithFriends {
                        if !(playOnline && setup.multiplayer?.isRelayTable == true) {
                            Picker("Human players", selection: $playerCount) {
                                ForEach(2...4, id: \.self) { Text("\($0) players").tag($0) }
                            }.disabled(setup.isBusy || setup.needsLeave)
                        }
                        if playOnline {
                            RelayTablePanel(multiplayer: setup.multiplayer, mayEnter: mayStart && !setup.needsLeave,
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
                            Stepper("AI opponents: \(gameCenterAICount)", value: gameCenterAICountBinding,
                                    in: 0...max(0, 4 - playerCount))
                                .disabled(setup.isBusy || setup.needsLeave)
                                .accessibilityIdentifier("ondevice.gameCenterAI.count")
                            ForEach(0..<gameCenterAICount, id: \.self) { index in
                                Picker("AI \(index + 1) deck", selection: aiDeckSelection(index)) {
                                    ForEach(PreconCatalog.all) { Text($0.name).tag($0.id) }
                                }
                                .disabled(setup.isBusy || setup.needsLeave)
                                .accessibilityIdentifier("ondevice.gameCenterAI.deck.\(index + 1)")
                            }
                            if gameCenterAICount > 0 {
                                Stepper("AI skill: \(aiSkill)", value: $aiSkill, in: 1...10)
                                    .disabled(setup.isBusy || setup.needsLeave)
                                Text("The Game Center host's AI choices apply to everyone. Higher skill may slow turns.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Every player needs the same app version and must keep the app open during the match.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(setup.multiplayer?.status ?? setup.status).font(.callout)
                            if let room = setup.multiplayer?.room {
                                MatchRoomView(room: room, deckName: selectedDeck?.name,
                                              localCommander: selectedDeck?.commander?.cardName) {
                                    guard let deck = selectedDeck else { return }
                                    setup.readyForMatch(name: playerDisplayName, deck: deck)
                                }
                            }
                            if setup.multiplayer?.isAuthenticated != true {
                                Button("Sign in to Game Center") { setup.multiplayer?.authenticate() }
                                    .buttonStyle(CommanderActionStyle(primary: false))
                                    .disabled(setup.multiplayer == nil || setup.isBusy || setup.needsLeave)
                            }
                            Button("Find players") { startMatchmaking() }
                                .buttonStyle(CommanderActionStyle())
                                .disabled(!mayStart || setup.multiplayer?.isAuthenticated != true)
                        }
                    } else {
                        Stepper("AI opponents: \(opponentCount)", value: $opponentCount, in: 1...3)
                            .disabled(setup.isBusy || setup.needsLeave)
                            .accessibilityIdentifier("ondevice.aiCount")
                        ForEach(0..<min(3, max(1, opponentCount)), id: \.self) { index in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI \(index + 1) deck").font(.caption).foregroundStyle(CommanderPresentation.secondary)
                                Picker("AI \(index + 1) deck", selection: aiDeckSelection(index)) {
                                    ForEach(PreconCatalog.all) { Text($0.name).tag($0.id) }
                                }
                                .accessibilityIdentifier("ondevice.aiDeck.\(index + 1)")
                                .disabled(setup.isBusy || setup.needsLeave)
                            }
                        }
                        Stepper("AI skill: \(aiSkill)", value: $aiSkill, in: 1...10)
                            .disabled(setup.isBusy || setup.needsLeave)
                            .accessibilityIdentifier("onDevice.aiSkill")
                        Text("Higher skill levels allow more thinking and may slow turns.").font(.caption).foregroundStyle(.secondary)
                        Picker("Who goes first?", selection: $aiStartingPlayerMode) {
                            Text("Choose").tag("choose")
                            Text("Roll D20").tag("roll")
                        }
                        .pickerStyle(.segmented)
                        .disabled(setup.isBusy || setup.needsLeave)
                        .accessibilityIdentifier("ondevice.ai.startingPlayerMode")
                        Text(aiStartingPlayerMode == "roll"
                             ? "Everyone rolls a D20. The highest roll starts; ties reroll."
                             : "Choose the starting player when the match begins.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Start game") { startAI() }
                            .buttonStyle(CommanderActionStyle()).disabled(!mayStart)
                    }
                }
                .commanderPanel()
                Text(setup.status).font(.caption).foregroundStyle(.secondary)
                if setup.needsLeave {
                    Button("Leave / retry closing", role: .destructive) { confirmLeave = true }
                        .buttonStyle(CommanderActionStyle(primary: false))
                        .disabled(setup.isBusy || session.isWorking)
                }
                if setup.identity == nil {
                    Button("Retry loading local catalogue") { setup.prepare() }
                        .buttonStyle(CommanderActionStyle(primary: false))
                }
                if diagnostics.report != nil {
                    Button("Engine error report") { showDiagnostics = true }
                        .accessibilityIdentifier("ondevice.diagnostics")
                }
            }
            .foregroundStyle(CommanderPresentation.ink)
            .tint(CommanderPresentation.accent)
            .frame(maxWidth: 640).padding(16).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BrandBackdrop(cards: false).ignoresSafeArea())
    }

    private var setupDecks: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        return layout {
            VStack(alignment: .center, spacing: 10) {
                CommanderDeckPortrait(name: selectedDeck?.commander?.cardName,
                                       namespace: reduceMotion ? nil : commanderTransition)
                    .frame(width: 112, height: 156)
                Text("Your deck").font(.caption).foregroundStyle(CommanderPresentation.secondary)
                Text(selectedDeck?.name ?? "Choose a deck").font(.headline).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
            VStack(alignment: .center, spacing: 10) {
                if playWithFriends {
                    Image(systemName: "person.2.fill")
                        .font(.largeTitle).foregroundStyle(CommanderPresentation.secondary)
                        .frame(width: 112, height: 156)
                        .background(CommanderPresentation.surface, in: RoundedRectangle(cornerRadius: 12))
                    Text(playOnline ? "iPhone + Android" : "Game Center")
                        .font(.caption).foregroundStyle(CommanderPresentation.secondary)
                    Text("\(playerCount) seats").font(.headline)
                } else {
                    CommanderDeckPortrait(name: aiPrecon?.deckList.commander?.cardName)
                        .frame(width: 112, height: 156)
                    Text("\(opponentCount) AI \(opponentCount == 1 ? "opponent" : "opponents")")
                        .font(.caption).foregroundStyle(CommanderPresentation.secondary)
                    Text(opponentCount == 1 ? (aiPrecon?.name ?? "Choose opponents") : "Choose each deck below")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if !dynamicType.isAccessibilitySize {
                VersusMedallion(size: 50).padding(.top, 12 + 156 / 2 - 25)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected decks")
    }

    @ViewBuilder
    private var recoveryBanner: some View {
        if setup.isBusy || bannerError != nil ||
            (activeGame && (session.snapshot == nil || !setup.canUseSession)) {
            VStack(alignment: .leading, spacing: 8) {
                if setup.isBusy { ProgressView(setup.status) }
                if let message = bannerError {
                    HStack(alignment: .top) {
                        Text(message).font(.caption.weight(.semibold)).lineLimit(3)
                        Spacer(minLength: 8)
                        Button { bannerError = nil } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Dismiss notification")
                        .accessibilityIdentifier("ondevice.dismissNotification")
                    }
                } else if activeGame && !setup.canUseSession {
                    Text(setup.liveStatus).font(.caption.weight(.semibold))
                } else if activeGame && session.snapshot == nil {
                    Text("Waiting for the first game update.").font(.caption.weight(.semibold))
                }
                if activeGame {
                    HStack {
                        Button("Refresh", action: refresh).disabled(!setup.canUseSession)
                        if session.pendingActionID != nil {
                            Button("Retry response") { Task { await setup.perform { try await session.retryPending() } } }
                                .disabled(!setup.canUseSession)
                        }
                        Button(setup.closeFailed ? "Retry closing" : "Leave") {
                            if setup.closeFailed { closeGame() } else { confirmLeave = true }
                        }
                    }
                    .disabled(setup.isBusy || session.isWorking)
                }
                if bannerError != nil && diagnostics.report != nil {
                    Button("Review engine error report") { showDiagnostics = true }
                        .accessibilityIdentifier("ondevice.failureReport")
                }
            }
            .foregroundStyle(MagicPalette.parchment)
            .magicPanel(.iron, prominence: .elevated, cornerRadius: 12, padding: 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func startAI() {
        diagnostics.beginAttempt()
        guard let deck = selectedDeck, aiPrecons.count == opponentCount else { return }
        let opponentDecks = aiPrecons.map(\.deckList)
        Task {
            do { playerDisplayName = try OnDeviceSetupModel.playerName(playerDisplayName) }
            catch { setup.errorMessage = error.localizedDescription; return }
            await setup.startAI(name: playerDisplayName, deck: deck, aiDecks: opponentDecks, aiSkill: aiSkill)
        }
    }

    private var diagnosticSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only the latest engine error report is kept on this phone, excluded from backups. Error text may contain private card information. Nothing is uploaded automatically; review it before sharing.")
                    if let error = diagnostics.errorMessage { Text(error).foregroundStyle(.red) }
                    if let report = diagnostics.report {
                        Text(diagnostics.isHistorical ? "Saved report from an earlier session" : "Latest local incident")
                            .font(.headline)
                        ShareLink(item: report) { Label("Share report", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("ondevice.shareReport")
                    }
                    if diagnostics.report != nil || diagnostics.errorMessage != nil {
                        Button("Delete saved report", role: .destructive) { confirmDeleteReport = true }
                    }
                    if let report = diagnostics.report {
                        Text(report).font(.caption.monospaced()).textSelection(.enabled)
                    } else if diagnostics.errorMessage == nil {
                        Text("No engine exception has been captured yet. Try starting the match again, then return here if it stops.")
                    }
                }.padding()
            }
            .navigationTitle("Engine error report").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showDiagnostics = false } } }
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
            deckIDs: Set(PreconCatalog.all.map { "precon:\($0.id)" } + library.decks.map { "local:\($0.id)" }),
            aiDeckIDs: PreconCatalog.all.map(\.id)
        )
        selectedDeckID = selected.deckID; aiPreconID = selected.aiDeckID
        let aiIDs = OnDeviceSetupPreferences.normalizedAIDeckIDs([aiPreconID, aiPrecon2ID, aiPrecon3ID], available: PreconCatalog.all.map(\.id))
        aiPrecon2ID = aiIDs[1]; aiPrecon3ID = aiIDs[2]
        opponentCount = selected.aiOpponents; playerCount = selected.humanPlayers
        aiSkill = selected.aiSkill
    }

    private func requestLeave() {
        guard !setup.isBusy, !session.isWorking else { return }
        confirmLeave = true
    }

    private func closeGame() {
        Task {
            if await setup.close() {
                selectedCard = nil; inspectedCard = nil; zone = nil
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
    @Published private(set) var usingOnline = false
    let online = OnlineSession()
    @Published private(set) var closeFailed = false
    @Published private(set) var status = "Preparing local decks"
    @Published var errorMessage: String?
    @Published var feedback: String?
    private let session: OnDeviceSession
    private let runtime = OnDeviceRuntimeManager()
    private var resolver: OnDeviceDeckResolver?
    private var multiplayerObservation: AnyCancellable?
    private var onlineObservation: AnyCancellable?
    private var aiClient: EngineClient?
    private var aiMatchID: String?
    private var sceneActive = true

    init(session: OnDeviceSession) {
        self.session = session
        onlineObservation = online.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var needsLeave: Bool { usingOnline || online.lobby != nil || usingMultiplayer || runtime.isOpen || session.matchID != nil || multiplayer?.needsCleanup == true }
    var canUseSession: Bool {
        sceneActive && (!usingMultiplayer || (multiplayer?.isConnected == true && multiplayer?.isSuspended == false))
    }
    var liveStatus: String {
        if usingOnline, online.status == "Reconnecting…" { return online.status }
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
                                         adapterVersion: "ondevice-0.1/app-\(version)/build-\(build)/rollstep-2/room-1/concede-1/emote-1")
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

    func startAI(name: String, deck: DeckList, aiDecks: [DeckList], aiSkill: Int = 2) async {
        guard !isBusy, !needsLeave, let resolver, let identity else { return }
        isBusy = true; errorMessage = nil; feedback = nil; status = "Starting XMage"
        defer { isBusy = false }
        do {
            let name = try Self.playerName(name)
            let humanDeck = try resolver.resolve(deck)
            let opponentDecks = try aiDecks.map { try resolver.resolve($0) }
            let seats = try OnDeviceAppConfiguration.aiGameSeats(name: name, humanDeck: humanDeck,
                aiDecks: opponentDecks, aiSkill: aiSkill)
            let client = try await runtime.makeClient(identity: identity)
            aiClient = client
            let created = try await runtime.create(client: client, configuration: .object(["seats": .array(seats)]))
            guard let matchID = created["matchId"]?.string, !matchID.isEmpty else {
                throw EngineError.invalidMessage("XMage did not return a match ID. Close the runtime before trying again.")
            }
            aiMatchID = matchID
            updateSessionForeground()
            try await session.attach(client: client, matchID: matchID, seatID: "player1", allowsSeatScopedAutoYield: true, close: { [self] in try await closeAI() })
            status = "Game started"
        } catch {
            errorMessage = error.localizedDescription
            if !runtime.isOpen, aiMatchID == nil { aiClient = nil }
            status = needsLeave ? "Game startup interrupted. Refresh or leave before starting again." : "Unable to start local game"
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
                                     adapterVersion: "ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1") }
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

    func enterOnline(code: String?, name: String, deck: DeckList, playerCount: Int) async {
        guard !isBusy, !needsLeave, let resolver, let identity else { return }
        isBusy = true; errorMessage = nil
        do {
            let name = try Self.playerName(name)
            let resolved = try resolver.resolve(deck)
            await online.enter(code: code, name: name, playerCount: playerCount, identity: identity, deck: resolved)
        } catch { errorMessage = error.localizedDescription }
        isBusy = false
        if online.lobby?.matchId != nil { await attachOnline() }
    }

    func attachOnline() async {
        guard !isBusy, !runtime.isOpen, session.matchID == nil, let api = online.api,
              let lobby = online.lobby, lobby.status == "active", let matchID = lobby.matchId,
              let seatID = lobby.seatId, seatID == online.userID else { return }
        isBusy = true; usingOnline = true; errorMessage = nil; feedback = nil
        defer { isBusy = false }
        do {
            updateSessionForeground()
            let client = EngineClient(transport: OnlineEngineTransport(api: api, matchID: matchID))
            try await session.attach(client: client, matchID: matchID, seatID: seatID, reconnectsAutomatically: true,
                                     close: { [online] in try await online.leave() })
            status = "Online match connected"
        } catch { errorMessage = error.localizedDescription }
    }

    func attachMultiplayer() async {
        guard usingMultiplayer, !isBusy, session.matchID == nil,
              let multiplayer, let endpoint = multiplayer.endpoint else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            updateSessionForeground()
            try await session.attach(client: endpoint.client, matchID: endpoint.matchID, seatID: endpoint.seatID,
                                     allowsSeatScopedAutoYield: true,
                                     close: { try await multiplayer.leave() })
            status = multiplayer.isRelayTable ? "Table connected" : "Game Center match connected"
        } catch { errorMessage = error.localizedDescription }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { multiplayer?.onResumed() } else { multiplayer?.onSuspended() }
        online.setForeground(active)
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
        do { try await operation() } catch { errorMessage = error.localizedDescription }
    }

    /// Waits up to 3 seconds for the current response and its refresh to finish.
    func waitUntilSessionIdle() async {
        for _ in 0..<150 where isBusy || session.isWorking { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func close() async -> Bool {
        guard !isBusy, !session.isWorking else { return false }
        isBusy = true; status = "Closing game"; errorMessage = nil
        defer { isBusy = false }
        do {
            if session.matchID != nil { try await session.close() }
            else if usingOnline || online.lobby != nil { try await online.leave() }
            else if usingMultiplayer { try await multiplayer?.leave() }
            else { try await closeAI() }
            // A failed host factory can retain its handle before Game Center owns
            // an EngineClient. Leave succeeds in that case; the root still owns cleanup.
            if runtime.isOpen { try await runtime.close() }
            usingMultiplayer = false; usingOnline = false; closeFailed = false; feedback = nil
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
        if usingOnline {
            return EngineHealth(status: online.status == "Reconnecting…" ? "unavailable" : "ok",
                reason: "Online connection: \(online.status)", checkedAt: ISO8601DateFormatter().string(from: Date()), recoveryAction: nil)
        }
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
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let multiplayer, multiplayer.isRelayTable, multiplayer.tableCode != nil {
                activeTable(multiplayer)
            } else {
                Stepper("AI opponents: \(aiCount)", value: $aiCount, in: 0...maxAI)
                    .disabled(locked)
                    .accessibilityIdentifier("ondevice.relay.aiCount")
                ForEach(0..<aiCount, id: \.self) { index in
                    Picker("AI \(index + 1) deck", selection: aiDeckSelection(index)) {
                        ForEach(PreconCatalog.all) { Text($0.name).tag($0.id) }
                    }
                    .disabled(locked)
                }
                if aiCount > 0 {
                    Stepper("AI skill: \(aiSkill)", value: $aiSkill, in: 1...10).disabled(locked)
                    Text("The host’s AI choices apply to everyone. Higher skill may slow turns.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("iPhone and Android players join with the table code. Every player needs this app version and keeps it open during the match.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Host a table", action: host)
                    .buttonStyle(CommanderActionStyle())
                    .disabled(!mayEnter)
                    .accessibilityIdentifier("ondevice.relay.host")
                BrandDivider(title: "or join")
                TextField("Table code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(12).background(CommanderPresentation.canvas, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BrandTheme.border, lineWidth: 1))
                    .onChange(of: code) { _, value in
                        let clean = String(value.uppercased().filter { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }.prefix(6))
                        if clean != value { code = clean }
                    }
                    .disabled(locked)
                    .accessibilityIdentifier("ondevice.relay.code")
                Button("Join table") { join(code) }
                    .buttonStyle(CommanderActionStyle(primary: false))
                    .disabled(!mayEnter || code.count != 6)
                    .accessibilityIdentifier("ondevice.relay.join")
            }
        }
    }

    @ViewBuilder
    private func activeTable(_ multiplayer: OnDeviceMultiplayer) -> some View {
        if let tableCode = multiplayer.tableCode {
            VStack(spacing: 6) {
                Text("TABLE CODE").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(CommanderPresentation.secondary)
                Text(stride(from: 0, to: tableCode.count, by: 3).map { start -> String in
                    let from = tableCode.index(tableCode.startIndex, offsetBy: start)
                    return String(tableCode[from..<tableCode.index(from, offsetBy: min(3, tableCode.count - start))])
                }.joined(separator: " "))
                    .font(.system(size: 34, weight: .black, design: .monospaced)).tracking(2)
                    .accessibilityLabel("Table code \(tableCode)")
                    .accessibilityIdentifier("ondevice.relay.tableCode")
                if multiplayer.room == nil, multiplayer.endpoint == nil, !multiplayer.isFailed {
                    Text("Players \(multiplayer.seatsTaken)/\(max(2, multiplayer.seatsWanted))")
                        .font(.caption).foregroundStyle(CommanderPresentation.secondary)
                    ShareLink(item: "Join my MagicMobile table with code \(tableCode)") {
                        Label("Share code", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(CommanderPresentation.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        Text(multiplayer.status).font(.callout)
        if let room = multiplayer.room {
            MatchRoomView(room: room, deckName: deckName, localCommander: localCommander, ready: ready)
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
            Text("MATCH ROOM").font(.caption.weight(.bold)).tracking(1.4)
                .foregroundStyle(CommanderPresentation.secondary)
            ForEach(room.players) { player in
                let commanders = player.isLocal && !room.localReady ? (localCommander.map { [$0] } ?? []) : player.commanders
                HStack(spacing: 10) {
                    CommanderDeckPortrait(name: commanders.first, namespace: nil)
                        .frame(width: 40, height: 56)
                        .opacity(player.isReady ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.headline)
                            if player.isHost {
                                Text("HOST").font(.caption2.weight(.black))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(CommanderPresentation.accent.opacity(0.25), in: Capsule())
                            }
                        }
                        Text(commanders.isEmpty ? (player.isReady ? "Ready" : "Choosing a deck…")
                             : commanders.joined(separator: " & "))
                            .font(.caption).foregroundStyle(CommanderPresentation.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: player.isReady ? "checkmark.circle.fill" : "hourglass")
                        .font(.title3)
                        .foregroundStyle(player.isReady ? Color.green : CommanderPresentation.secondary)
                        .accessibilityLabel(player.isReady ? "Ready" : "Not ready")
                }
                .accessibilityElement(children: .combine)
            }
            if let aiSummary = room.aiSummary { Text(aiSummary).font(.caption).foregroundStyle(.secondary) }
            if room.localReady {
                Label("You're ready. The game starts when everyone is.", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.green)
            } else {
                Text("Pick your deck above, then ready up\(deckName.map { " with \($0)" } ?? "").")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Ready") { ready() }
                    .buttonStyle(CommanderActionStyle())
                    .disabled(deckName == nil)
                    .accessibilityIdentifier("ondevice.matchRoom.ready")
            }
        }
        .padding(12)
        .background(CommanderPresentation.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
