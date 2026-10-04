import XCTest

/// UI fixtures are local presentation checks. Keep each launch's preferences isolated
/// and avoid artwork network/cache state affecting unrelated assertions.
@MainActor
enum UITestHarness {
    static func configure(_ app: XCUIApplication, preview: String? = nil, extraArguments: [String] = []) {
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        if let preview {
            app.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = preview
        }
        app.launchArguments = (preview == nil ? ["--ondevice-setup-ui-test"] : [])
            + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            // Classic board unless a test asks for another (Walnut Tavern is the default).
            + (extraArguments.contains("-magicmobile.boardAppearance") ? [] : ["-magicmobile.boardAppearance", "arena"])
            + extraArguments
    }

    /// Play opens the mode chooser (Quick Match, Ranked, Custom Table); the custom table is the
    /// setup screen the older tests drive.
    static func chooseCustomTable(_ app: XCUIApplication) {
        let custom = app.buttons["play.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10), "Play opens the mode chooser")
        custom.tap()
    }

    /// The first touch after launch moves keyboard focus to the app. On the iOS 26.5
    /// simulator a system-gesture change follows about 0.12 s later and cancels any touch
    /// still down (UIKit EventDispatch logs "systemGestureStateChange: 1"): a 0.15 s press,
    /// or a tap synthesized slowly under load, then shows its pressed state but never
    /// fires. Spend that first touch on the menu's static brand text, which has no action.
    static func settleFirstTouch(_ app: XCUIApplication) {
        // The menu's brand text; on a board fixture, the bare table edge beside the mat (the
        // development label sits over the opponent's medallion, which would open its zones).
        let brand = app.staticTexts["MAGICMOBILE"]
        if brand.waitForExistence(timeout: 2) {
            brand.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if app.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        } else {
            return
        }
        Thread.sleep(forTimeInterval: 0.3) // Let the focus change land before the real touch.
    }

    /// Search only the owning scroll view. Querying the full app repeatedly can
    /// traverse every lazy card and turn one failure into a long timeout.
    @discardableResult
    static func reveal(_ element: XCUIElement, in scrollView: XCUIElement,
                       swipes: Int = 6, upward: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard scrollView.waitForExistence(timeout: 5) else {
            XCTFail("Missing scroll view: \(scrollView.identifier)", file: file, line: line)
            return false
        }
        for attempt in 0...swipes {
            if element.exists && element.isHittable { return true }
            if attempt < swipes {
                if upward { scrollView.swipeUp() } else { scrollView.swipeDown() }
            }
        }
        XCTFail("Could not reveal \(element.identifier) in \(scrollView.identifier) after \(swipes) swipes", file: file, line: line)
        return false
    }
}
