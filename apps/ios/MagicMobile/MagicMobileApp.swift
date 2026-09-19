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
            // The UIKit host owns the real safe-area insets. Let its surface
            // reach the window edges instead of clipping it to SwiftUI's inset.
            .ignoresSafeArea(.container)
        }
    }
}
