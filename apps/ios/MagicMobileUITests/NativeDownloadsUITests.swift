import XCTest

@MainActor
final class NativeDownloadsUITests: XCTestCase {
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
        XCTAssertTrue(app.staticTexts["Card catalogue included"].exists)
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
