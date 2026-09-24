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
        MainActor.assumeIsolated {
            _ = NativeAssetDownloads.shared
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
                } else if ProcessInfo.processInfo.environment["MAGICMOBILE_VERSUS_FIXTURE"] == "1" {
                    VersusFixtureScreen()
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
        case .referencePreview:
            ContentView()
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
