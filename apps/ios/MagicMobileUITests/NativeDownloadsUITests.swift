import XCTest

@MainActor
final class NativeDownloadsUITests: XCTestCase {
    func testDownloadSelectionSurvivesLeavingAndReopening() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["menu.downloads"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        let scope = app.buttons["downloads.scope"], quality = app.buttons["downloads.quality"]
        XCTAssertTrue(scope.waitForExistence(timeout: 10))
        scope.tap()
        XCTAssertTrue(app.buttons["One deck"].waitForExistence(timeout: 5))
        app.buttons["One deck"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["downloads.deck"].waitForExistence(timeout: 5))
        quality.tap()
        XCTAssertTrue(app.buttons["Compact"].waitForExistence(timeout: 5))
        app.buttons["Compact"].press(forDuration: 0.15)
        let tokens = app.switches["Include tokens"]
        XCTAssertTrue(tokens.exists)
        if tokens.value as? String == "1" { tokens.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(tokens.value as? String, "0")
        app.buttons["Done"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["downloads.deck"].exists, "One-deck scope must survive leaving Downloads")
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Compact", "Compact").evaluate(with: quality))
        XCTAssertEqual(app.switches["Include tokens"].value as? String, "0")
        XCTAssertFalse(app.buttons["downloads.cancel"].exists, "Navigation and selection changes must not start transfers")
    }

    func testLiveImagePreferenceIsSharedBetweenSettingsAndLobby() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        app.launchArguments = ["--ondevice-setup-ui-test"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 20))
        app.buttons["menu.settings"].press(forDuration: 0.15)
        let consent = app.switches["nativeArtwork.downloads"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 10))
        app.buttons["menu.play"].press(forDuration: 0.15)
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        for _ in 0..<3 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
        XCTAssertEqual(consent.value as? String, "1", "Lobby must share the settings preference")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "0")
    }

    func testDownloadsShowsLocalCoverageAndRequiresConsentWithoutStartingBulkDownload() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        menu.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Card catalogue included"].isHittable, "Technical details start collapsed")
        XCTAssertTrue(app.buttons["downloads.scope"].exists)
        XCTAssertTrue(app.buttons["downloads.quality"].exists)
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
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Download ")).matching(NSPredicate(format: "label CONTAINS %@", "cards · Standard")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["downloads.cancel"].exists, "Full-catalogue confirmation must precede network work")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["downloads.cancel"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Downloads coverage and explicit consent"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
    }
}
