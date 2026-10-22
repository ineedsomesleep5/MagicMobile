import XCTest

@MainActor
final class NativeDownloadsUITests: XCTestCase {
    func testTokenOnlyScopeRequiresConsentAndPersistsWithoutDownloading() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["menu.downloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        // The first touch after launch only moves focus on this simulator (UITestHarness).
        UITestHarness.settleFirstTouch(app)
        menu.press(forDuration: 0.15)
        // Arena's panel: the scope is a list of diamond rows under the status card.
        let tokens = app.buttons["downloads.scope.tokens"]
        XCTAssertTrue(tokens.waitForExistence(timeout: 10))
        for _ in 0..<4 where !tokens.isHittable { app.swipeUp() }
        tokens.tap()
        XCTAssertTrue(tokens.isSelected)
        XCTAssertFalse(app.switches["Include tokens"].exists)
        XCTAssertFalse(app.buttons["downloads.deck"].exists)
        let start = app.buttons["downloads.start"]
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled, "Selecting tokens must not opt into online artwork")
        XCTAssertFalse(app.buttons["downloads.cancel"].exists)
        app.buttons["downloads.close"].tap()
        // Home fades back in once the panel closes (it steps away behind panels); press when it can take the touch.
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed)
        menu.press(forDuration: 0.15)
        XCTAssertTrue(tokens.waitForExistence(timeout: 5))
        XCTAssertTrue(tokens.isSelected, "The token-only scope survives leaving Downloads")
        XCTAssertFalse(app.buttons["downloads.cancel"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Token-only artwork scope with offline consent preserved"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testDownloadSelectionSurvivesLeavingAndReopening() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["menu.downloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        // The first touch after launch only moves focus on this simulator (UITestHarness).
        UITestHarness.settleFirstTouch(app)
        menu.press(forDuration: 0.15)
        // Arena's panel: the scope as diamond rows, the quality as a tab strip.
        let oneDeck = app.buttons["downloads.scope.deck"], compact = app.buttons["downloads.quality.Compact"]
        XCTAssertTrue(oneDeck.waitForExistence(timeout: 10))
        for _ in 0..<4 where !oneDeck.isHittable { app.swipeUp() }
        oneDeck.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["downloads.deck"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !compact.isHittable { app.swipeUp() }
        compact.press(forDuration: 0.15)
        XCTAssertTrue(compact.isSelected)
        let tokens = app.switches["Include tokens"]
        XCTAssertTrue(tokens.exists)
        if tokens.value as? String == "1" { tokens.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(tokens.value as? String, "0")
        app.buttons["downloads.close"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.press(forDuration: 0.15)
        XCTAssertTrue(oneDeck.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["downloads.deck"].exists, "One-deck scope must survive leaving Downloads")
        XCTAssertTrue(compact.isSelected, "The quality must survive leaving Downloads")
        XCTAssertEqual(app.switches["Include tokens"].value as? String, "0")
        XCTAssertFalse(app.buttons["downloads.cancel"].exists, "Navigation and selection changes must not start transfers")
    }

    func testLiveImagePreferenceIsSharedBetweenOptionsAndDownloads() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        app.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 20))
        // The first touch after launch only moves focus on this simulator (UITestHarness).
        UITestHarness.settleFirstTouch(app)
        app.buttons["menu.settings"].press(forDuration: 0.15)
        // Arena's Options: the artwork choice is on the Display & Artwork page.
        let display = app.buttons["settings.open.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        display.tap()
        let consent = app.switches["nativeArtwork.downloads"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        app.buttons["settings.close"].tap()
        XCTAssertTrue(app.buttons["menu.downloads"].waitForExistence(timeout: 10))
        // Downloads shows the same choice.
        app.buttons["menu.downloads"].press(forDuration: 0.15)
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        for _ in 0..<3 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
        XCTAssertEqual(consent.value as? String, "1", "Downloads must share the Options preference")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "0")
    }

    func testDownloadsShowsLocalCoverageAndRequiresConsentWithoutStartingBulkDownload() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Downloads final state"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        let menu = app.buttons["menu.downloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        if !menu.isHittable { app.swipeUp() }
        // The first touch after launch only moves focus on this simulator (UITestHarness).
        UITestHarness.settleFirstTouch(app)
        menu.press(forDuration: 0.15)
        XCTAssertTrue(app.descendants(matching: .any)["downloads.summary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Card catalogue included"].isHittable, "Technical details start collapsed")
        XCTAssertTrue(app.buttons["downloads.scope.catalogue"].exists)
        XCTAssertTrue(app.buttons["downloads.quality.Standard"].exists)
        let check = app.buttons["downloads.check"]
        for _ in 0..<4 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.isHittable)
        let download = app.buttons["downloads.start"]
        for _ in 0..<4 where !download.isHittable { app.swipeUp() }
        XCTAssertTrue(download.exists)
        XCTAssertFalse(download.isEnabled)
        let consent = app.switches["nativeArtwork.downloads"]
        XCTAssertTrue(consent.isHittable)
        // SwiftUI exposes the entire row as the switch; target the visible thumb.
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1", "Artwork consent must actually turn on")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: download)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        // Enabling consent alone must never start a bulk download.
        XCTAssertFalse(app.buttons["downloads.cancel"].exists)
        download.tap()
        XCTAssertTrue(app.buttons["Download missing images · Standard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["downloads.cancel"].exists, "Full-catalogue confirmation must precede network work")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["downloads.cancel"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Downloads coverage and explicit consent"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["downloads.close"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
    }
}
