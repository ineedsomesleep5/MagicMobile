import XCTest

/// "How to play" in the presentation-only build: opened from the main menu, and shown once by
/// itself on first launch when a test asks for it (--how-to-play-first-launch). Other UI tests
/// never see it on their own.
@MainActor
final class HowToPlayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // One private preference suite per test, kept across this test's relaunches.
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ondevice-setup-ui-test"]
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        app = nil
    }

    private var progress: XCUIElement { app.descendants(matching: .any)["howToPlay.progress"] }

    func testMenuOpensWalkthroughAndPagesThroughToDone() {
        app.launch()
        let play = app.buttons["menu.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertFalse(progress.waitForExistence(timeout: 2), "UI tests must not get the first-launch walkthrough")
        UITestHarness.settleFirstTouch(app)

        let entry = app.buttons["menu.howToPlay"]
        for _ in 0..<4 where !(entry.exists && entry.isHittable) { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        waitFor(progress, "label == 'Page 1 of 10'")
        XCTAssertFalse(app.buttons["howToPlay.back"].isEnabled)
        XCTAssertTrue(app.buttons["howToPlay.skip"].isHittable)
        capture("How to play · first page")

        // A swipe turns the page like Next does.
        app.swipeLeft()
        waitFor(progress, "label == 'Page 2 of 10'")
        app.buttons["howToPlay.back"].tap()
        waitFor(progress, "label == 'Page 1 of 10'")

        for page in 2...10 {
            app.buttons["howToPlay.next"].tap()
            waitFor(progress, "label == 'Page \(page) of 10'")
            capture("How to play · page \(page)")
        }
        XCTAssertFalse(app.buttons["howToPlay.next"].exists)
        let skip = app.buttons["howToPlay.skip"]
        XCTAssertFalse(skip.exists && skip.isHittable, "The last page offers Done, not Skip")
        app.buttons["howToPlay.done"].tap()
        waitFor(progress, "exists == false")
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }

    /// The largest accessibility text size: the page scrolls and the controls stay in reach.
    func testLargestTextScrollsWithinAPage() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 15))
        UITestHarness.settleFirstTouch(app)
        let entry = app.buttons["menu.howToPlay"]
        for _ in 0..<8 where !(entry.exists && entry.isHittable) { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        waitFor(progress, "label == 'Page 1 of 10'")
        app.buttons["howToPlay.next"].tap()
        waitFor(progress, "label == 'Page 2 of 10'")
        capture("How to play · largest text, top of page")
        let page = app.descendants(matching: .any)["howToPlay.page.decks"]
        let body = page.staticTexts.containing(NSPredicate(format: "label ENDSWITH %@", "shows the Playing badge.")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        for _ in 0..<6 { page.swipeUp() }
        // Scrolled to the end, the body's last line sits inside the page, above the fixed controls.
        XCTAssertLessThanOrEqual(body.frame.maxY, page.frame.maxY + 1, "The whole body is reachable by scrolling the page")
        XCTAssertGreaterThan(body.frame.maxY, page.frame.minY)
        XCTAssertTrue(app.buttons["howToPlay.next"].isHittable)
        capture("How to play · largest text, end of page")
    }

    func testFirstLaunchShowsWalkthroughOnce() {
        app.launchArguments.append("--how-to-play-first-launch")
        app.launch()
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        waitFor(progress, "label == 'Page 1 of 10'")
        // Spend the first touch on static text (UITestHarness.settleFirstTouch explains why).
        let title = app.staticTexts["Welcome to MagicMobile"]
        if title.isHittable { title.tap() }
        capture("How to play · first launch")
        app.buttons["howToPlay.skip"].tap()
        waitFor(progress, "exists == false")
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 15))
        XCTAssertFalse(progress.waitForExistence(timeout: 3), "The walkthrough opens by itself only once")
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, predicate, file: file, line: line)
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
