import SwiftUI
import UIKit

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
        portraitEnabled = UserDefaults.standard.bool(forKey: PortraitModePreference.key)
    }

    var supportedOrientations: UIInterfaceOrientationMask {
        GameOrientationMode.supportedOrientations(portraitEnabled: portraitEnabled)
    }

    func setPortraitModeEnabled(_ enabled: Bool) {
        portraitEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: PortraitModePreference.key)
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
                ContentView()
            }
        }
    }
}
