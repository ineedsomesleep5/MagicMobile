import SwiftUI
import UIKit

enum MagicMobilePreferences {
    static let current: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ondevice-setup-ui-test"),
           let value = ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_PREFERENCES"],
           let id = UUID(uuidString: value),
           let store = UserDefaults(suiteName: "MagicMobile.UITests.\(id.uuidString)") {
            return store
        }
        #endif
        return .standard
    }()
}

enum PortraitModePreference {
    static let key = "magicmobile.portraitModeEnabled"
}

enum GameOrientationMode {
    static func isPortraitLayout(size: CGSize, portraitEnabled: Bool) -> Bool {
        portraitEnabled && size.height > size.width
    }

    static func supportedOrientations(portraitEnabled: Bool) -> UIInterfaceOrientationMask {
        portraitEnabled ? [.portrait, .landscapeLeft, .landscapeRight] : [.landscapeLeft, .landscapeRight]
    }
}

@MainActor
final class MagicMobileOrientationController {
    static let shared = MagicMobileOrientationController()

    private(set) var portraitEnabled: Bool

    private init() {
        if MagicMobilePreferences.current.object(forKey: PortraitModePreference.key) == nil {
            portraitEnabled = true
        } else {
            portraitEnabled = MagicMobilePreferences.current.bool(forKey: PortraitModePreference.key)
        }
    }

    var supportedOrientations: UIInterfaceOrientationMask {
        GameOrientationMode.supportedOrientations(portraitEnabled: portraitEnabled)
    }

    func setPortraitModeEnabled(_ enabled: Bool) {
        portraitEnabled = enabled
        MagicMobilePreferences.current.set(enabled, forKey: PortraitModePreference.key)
        updateSupportedOrientations()
    }

    private func updateSupportedOrientations() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations)) { _ in }
        }
    }
}

final class MagicMobileAppDelegate: NSObject, UIApplicationDelegate {
    private var artworkConsentObserver: NSObjectProtocol?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        TavernAppearance.apply()
        MainActor.assumeIsolated {
            // Live Scryfall art is on unless the player turned it off; UI tests keep their own store,
            // offline. Registered here, before the observer below: registering posts a change
            // notification, and doing it inside MagicMobilePreferences.current's initializer
            // re-entered that initializer through the observer and crashed.
            if MagicMobilePreferences.current === UserDefaults.standard {
                UserDefaults.standard.register(defaults: [NativeArtworkPreference.key: true])
            }
            _ = NativeAssetDownloads.shared
            // Local crash and hang summaries for the report sheet; nothing is uploaded.
            OnDeviceCrashReporter.shared.start()
            artworkConsentObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if !MagicMobilePreferences.current.bool(forKey: NativeArtworkPreference.key) {
                        NativeAssetDownloads.shared.cancel()
                    }
                }
            }
        }
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            guard identifier == NativeArtworkBackgroundQueue.sessionIdentifier else { completionHandler(); return }
            NativeArtworkBackgroundQueue.shared.reconnectBackgroundSession(completion: completionHandler)
        }
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            MagicMobileOrientationController.shared.supportedOrientations
        }
    }
}

final class OrientationHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            MagicMobileOrientationController.shared.supportedOrientations
        }
    }
}

struct OrientationHostingRoot<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> OrientationHostingController<Content> {
        OrientationHostingController(rootView: content)
    }

    func updateUIViewController(_ controller: OrientationHostingController<Content>, context: Context) {
        controller.rootView = content
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

@main
struct MagicMobileApp: App {
    @UIApplicationDelegateAdaptor(MagicMobileAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            OrientationHostingRoot {
                #if DEBUG
                if ProcessInfo.processInfo.environment["MAGICMOBILE_MULTIPLAYER_D20_FIXTURE"] == "1" {
                    MultiplayerD20FixtureScreen()
                } else if ProcessInfo.processInfo.environment["MAGICMOBILE_STARTING_ROLL_FIXTURE"] == "1" {
                    StartingRollFixtureScreen()
                } else if ProcessInfo.processInfo.environment["MAGICMOBILE_VERSUS_FIXTURE"] == "1" {
                    VersusFixtureScreen()
                } else if ProcessInfo.processInfo.environment["MAGICMOBILE_SOUND_LAB_FIXTURE"] == "1" {
                    SoundLabView()
                } else if let preview = ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"], !preview.isEmpty {
                    DesignPreviewFixtureScreen(fixture: preview)
                } else {
                    productionRoot
                }
                #else
                productionRoot
                #endif
            }
            // The UIKit host owns the real safe-area insets. Let its surface
            // reach the window edges instead of clipping it to SwiftUI's inset.
            .ignoresSafeArea(.container)
        }
    }

    @ViewBuilder
    private var productionRoot: some View {
        switch OnDeviceAppConfiguration.entryPoint {
        case .embedded, .setupPreview:
            OnDeviceRootView()
                .defaultAppStorage(MagicMobilePreferences.current)
        case .engineMissing:
            ContentUnavailableView(
                "Native engine missing",
                systemImage: "exclamationmark.triangle",
                description: Text("This build does not include the on-device XMage engine. Install a complete native build; no remote engine or simulator will be substituted.")
            )
        }
    }
}

#if DEBUG
/// Opt-in visual fixture only. It never creates a Game Center or XMage match.
private struct MultiplayerD20FixtureScreen: View {
    @State private var dismissed = false
    @State private var revealedStepCount = 0

    private static let roll: OnDeviceStartingRoll? = {
        var values = [12, 12, 7, 20, 14].makeIterator()
        return try? OnDeviceStartingRoll.generate(seatIDs: ["player1", "player2", "player3"],
                                                  draw: { values.next() ?? 1 })
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text("DEVELOPMENT FIXTURE · NO ENGINE")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.yellow)
            if dismissed {
                Text("Starting roll preview complete")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
            } else if let roll = Self.roll {
                MultiplayerD20View(roll: roll,
                                   seatNames: ["player1": "Caleb", "player2": "Ruthie", "player3": "AI 1"],
                                   isLocalWinner: true,
                                   revealedStepCount: revealedStepCount,
                                   // The fixture drives one local tap at a time; it is
                                   // not a substitute for Game Center transport.
                                   localSeatID: roll.steps.indices.contains(revealedStepCount)
                                       ? roll.steps[revealedStepCount].seatID : nil,
                                   onRollTap: { revealedStepCount += 1 }) {
                    dismissed = true
                }
            } else {
                Text("Starting roll fixture unavailable")
            }
        }
        .background {
            GeometryReader { geometry in
                Image("battlefield-wood")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(0.58))
            }
            .ignoresSafeArea()
        }
        .onAppear {
            MagicMobileOrientationController.shared.setPortraitModeEnabled(
                ProcessInfo.processInfo.environment["MAGICMOBILE_D20_LANDSCAPE_FIXTURE"] != "1")
        }
    }
}
#endif

#if DEBUG
/// Opt-in visual fixture only: the design-preview board with XMage's pending starting-player
/// question, under the AI table's starting roll exactly as OnDeviceRootView covers it
/// (StartingRollCover over a startingRollCovered board). It never creates an XMage match,
/// and the prompt stays unanswered after the roll.
private struct StartingRollFixtureScreen: View {
    @State private var selectedCard: ZoneCard?
    @State private var inspectedCard: ZoneCard?
    @State private var portraitModeEnabled = true
    @State private var revealedStepCount = 0
    @State private var dismissed = false
    @State private var snapshot = GameBoardPreviewFixtures.startingPlayerPrompt()

    private static let roll: OnDeviceStartingRoll? = {
        var values = [17, 6].makeIterator()
        return try? OnDeviceStartingRoll.generate(seatIDs: ["human", "ai-1"], draw: { values.next() ?? 1 })
    }()

    var body: some View {
        let roll = dismissed ? nil : Self.roll
        ZStack {
            ImmersivePlayShell(
                snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                playerDisplayName: "You", avatarData: nil, pendingActionId: nil, pendingCardInstanceId: nil,
                lastActionRejection: nil, commandFailure: nil, liveUpdateStatus: "Design Preview",
                onInteractionFeedback: { _ in }, runAction: { _ in }, runCommand: { _, _, _ in },
                refreshGame: {}, reconnectGame: {}, checkBridgeHealth: { nil }, newGame: {}, quitGame: {},
                loadProtocolDebug: { _ in throw CancellationError() },
                portraitModeEnabled: $portraitModeEnabled, viewZone: { _, _ in }
            )
            .startingRollCovered(roll != nil)
            if let roll {
                StartingRollCover {
                    MultiplayerD20View(roll: roll, seatNames: ["human": "You", "ai-1": "AI"], isLocalWinner: true,
                                       revealedStepCount: revealedStepCount,
                                       // The test taps for both seats; the fixture has no AI.
                                       localSeatID: roll.steps.indices.contains(revealedStepCount)
                                           ? roll.steps[revealedStepCount].seatID : nil,
                                       onRollTap: { revealedStepCount += 1 }) {
                        dismissed = true
                    }
                }
            }
        }
        .onAppear {
            MagicMobileOrientationController.shared.setPortraitModeEnabled(
                ProcessInfo.processInfo.environment["MAGICMOBILE_D20_LANDSCAPE_FIXTURE"] != "1")
        }
    }
}
#endif

#if DEBUG
/// Opt-in visual fixture only: `MAGICMOBILE_DESIGN_PREVIEW=<state>` shows a design-preview board
/// from GameBoardPreviewFixtures. It never creates an XMage match; taps are captured on screen
/// ("preview.captured-command") and no command leaves the app. Layout review, not gameplay proof.
private struct DesignPreviewFixtureScreen: View {
    let fixture: String
    @AppStorage("magicmobile.playerDisplayName") private var playerDisplayName = ""
    @AppStorage(PortraitModePreference.key) private var portraitModeEnabled = true
    @State private var snapshot: GameSnapshot
    @State private var selectedCard: ZoneCard?
    @State private var inspectedCard: ZoneCard?
    @State private var liveUpdateStatus = "Design Preview"
    /// The latest captured command or interaction feedback; a capture shows until the next feedback.
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var boardFXPreviewStep = 0

    init(fixture: String) {
        self.fixture = fixture
        let state = GameBoardDesignPreviewState(rawValue: fixture) ?? .normalBattlefield
        let snapshot = fixture == "board-fx" ? GameBoardPreviewFixtures.boardFXStep(0) : GameBoardPreviewFixtures.snapshot(state)
        var inspected = GameBoardPreviewFixtures.inspectedCard(for: state, snapshot: snapshot)
        if let id = ProcessInfo.processInfo.environment["MAGICMOBILE_PREVIEW_INSPECT"] {
            inspected = snapshot.visibleBattlefield.first { $0.instanceId == id }
        }
        _snapshot = State(initialValue: snapshot)
        _selectedCard = State(initialValue: GameBoardPreviewFixtures.selectedCard(for: state, snapshot: snapshot))
        _inspectedCard = State(initialValue: inspected)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.08), Color(red: 0.16, green: 0.25, blue: 0.13)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ImmersivePlayShell(
                snapshot: snapshot, selectedCard: $selectedCard, inspectedCard: $inspectedCard,
                playerDisplayName: playerDisplayName, avatarData: nil, pendingActionId: nil, pendingCardInstanceId: nil,
                lastActionRejection: nil, commandFailure: CardChoiceCommandFailure(errorMessage, source: .preview),
                liveUpdateStatus: liveUpdateStatus,
                onInteractionFeedback: { message in status = message; liveUpdateStatus = message },
                runAction: { action in capture(action.label) },
                runCommand: { command, label, _ in
                    capture(label + (command.abilityId.map { " [\($0)]" } ?? ""))
                    if ProcessInfo.processInfo.environment["MAGICMOBILE_UI_TEST_CARD_CHOICE_FAILURE"] == "1" {
                        errorMessage = "Development fixture: simulated command failure."
                    }
                },
                refreshGame: {}, reconnectGame: {}, checkBridgeHealth: { nil }, newGame: {}, quitGame: {},
                loadProtocolDebug: { _ in throw CancellationError() },
                portraitModeEnabled: $portraitModeEnabled, viewZone: { _, _ in }
            )
        }
        .overlay(alignment: .top) {
            if status.hasPrefix("Development fixture: captured") {
                Text(status).font(.caption2).padding(4).background(.black)
                    .accessibilityIdentifier("preview.captured-command")
                    .allowsHitTesting(false)
            }
            previewControls
        }
        .holdInspectionScope()
        .alert("MagicMobile", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: portraitModeEnabled) { _, enabled in
            MagicMobileOrientationController.shared.setPortraitModeEnabled(enabled)
        }
        .task { MagicMobileOrientationController.shared.setPortraitModeEnabled(portraitModeEnabled) }
    }

    private func capture(_ label: String) {
        status = "Development fixture: captured \(label). No engine command sent."
        print(status)
    }

    /// Scripted beats for the animated fixtures; each replays unless MAGICMOBILE_BOARD_FX_FREEZE holds it.
    @ViewBuilder private var previewControls: some View {
        if fixture == "board-fx" {
            Button("Next board FX step (\(boardFXPreviewStep))") { advanceBoardFX() }
                .font(.caption).padding(8).background(.black)
                .padding(.top, 24).accessibilityIdentifier("preview.boardFX.next")
                .task {
                    // Visual QA: MAGICMOBILE_BOARD_FX_AUTOPLAY=1 steps through the walkthrough.
                    guard ProcessInfo.processInfo.environment["MAGICMOBILE_BOARD_FX_AUTOPLAY"] == "1" else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3.6))
                        advanceBoardFX()
                    }
                }
        }
        if fixture == "phase-announcement" || fixture == "life-change" || fixture == "attached-permanents" {
            Button(fixture == "phase-announcement" ? "Advance preview phase" : "Preview life change") {
                if fixture == "phase-announcement" {
                    snapshot = GameBoardPreviewFixtures.snapshot(.phaseAnnouncement, step: "DECLARE_BLOCKERS")
                } else if fixture == "attached-permanents" {
                    snapshot = GameBoardPreviewFixtures.snapshot(.attachedPermanents, specialStateAdvanced: true)
                } else {
                    snapshot = GameBoardPreviewFixtures.snapshot(.lifeChange, life: snapshot.human?.life == 37 ? 35 : 43)
                }
            }
            .font(.caption).padding(8).background(.black)
            .padding(.top, 24).accessibilityIdentifier("preview.advance")
        }
        // First strike: declared blocks, then XMage's first-strike damage step.
        // Ability showcase: the ability goes on the stack once the board has settled.
        if let replay = replayedFixture {
            let state = replay.state
            Button(replay.label) {
                snapshot = GameBoardPreviewFixtures.snapshot(state)
                Task {
                    try? await Task.sleep(for: .seconds(0.4))
                    snapshot = GameBoardPreviewFixtures.snapshot(state, specialStateAdvanced: true)
                }
            }
            .font(.caption).padding(8).background(.black)
            .padding(.top, 24).accessibilityIdentifier("preview.advance")
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                    snapshot = GameBoardPreviewFixtures.snapshot(state, specialStateAdvanced: true)
                    if BoardFXPreviewFreeze.seconds != nil { return }
                    do { try await Task.sleep(for: .seconds(replay.hold)) } catch { return }
                    snapshot = GameBoardPreviewFixtures.snapshot(state)
                }
            }
        }
    }

    private var replayedFixture: (state: GameBoardDesignPreviewState, label: String, hold: Double)? {
        switch fixture {
        case "first-strike": return (.firstStrike, "Replay first strike", 3.6)
        case "ability-showcase": return (.abilityShowcase, "Replay ability", 2.4)
        default: return nil
        }
    }

    private func advanceBoardFX() {
        boardFXPreviewStep = (boardFXPreviewStep + 1) % GameBoardPreviewFixtures.boardFXStepCount
        snapshot = GameBoardPreviewFixtures.boardFXStep(boardFXPreviewStep)
    }
}
#endif

#if DEBUG
/// Replays the versus intro with included precons for visual checks.
private struct VersusFixtureScreen: View {
    @State private var run = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VersusIntroOverlay(you: .init(id: "you", name: "Caleb", commander: "Emmara, Soul of the Accord"),
                               opponents: [.init(id: "ai", name: "Grave Danger", commander: "Gisa and Geralf")]) {
                run += 1
            }
            .id(run)
        }
    }
}
#endif
