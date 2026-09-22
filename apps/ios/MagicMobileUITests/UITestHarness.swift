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
            + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
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
