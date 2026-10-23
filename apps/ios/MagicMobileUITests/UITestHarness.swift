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
            // The Hearth board unless a test asks for Arena (Arena is the app's default since 2026-10-23; these
            // fixtures were written against Hearth's board).
            + (extraArguments.contains("-magicmobile.boardMode") ? [] : ["-magicmobile.boardMode", "hearth"])
            // Classic board unless a test asks for another (Walnut Tavern is the default).
            + (extraArguments.contains("-magicmobile.boardAppearance") ? [] : ["-magicmobile.boardAppearance", "arena"])
            // The deck's cards as a list unless a test asks for the grid (the full-art grid is the default).
            + (extraArguments.contains("-deckStudio.cards.layout.v1") ? [] : ["-deckStudio.cards.layout.v1", "List"])
            + extraArguments
    }

    /// The Decks page opens scrolled to the playing deck's open box (Arena's way), so the "+" box at the top of the
    /// shelf may sit above the view: scroll back to it. Returns the "+" box, hittable.
    @discardableResult
    static func revealCreateDeck(_ app: XCUIApplication, timeout: TimeInterval = 15) -> XCUIElement {
        let create = app.buttons["deckStudio.create"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if create.exists && create.isHittable { break }
            // The Decks page opens scrolled to the playing deck; scroll its grid back to the top, where "+" stands first.
            let grid = app.scrollViews["deckStudio.library.grid"]
            if grid.exists {
                grid.swipeDown()
            } else {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTAssertTrue(create.exists && create.isHittable, "The new-deck box can be reached")
        return create
    }

    /// Play opens Arena's panel; Custom then Set Up Table opens the custom table, the setup screen the older tests
    /// drive.
    static func chooseCustomTable(_ app: XCUIApplication) {
        let custom = app.buttons["play.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10), "Play opens the panel")
        custom.tap()
        let start = app.buttons["play.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Custom offers Set Up Table")
        start.tap()
    }

    /// Opens a deck from Deck Studio's boxes, Arena's way: the first tap opens its box and shows it beside the
    /// others, Edit Deck opens it (a deck already chosen opens on the first tap).
    static func openDeck(_ app: XCUIApplication, _ deck: XCUIElement) {
        deck.tap()
        let workspace = app.buttons["deckStudio.close"]
        if workspace.waitForExistence(timeout: 2) { return }
        let edit = app.buttons["deckStudio.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "A chosen deck offers Edit Deck")
        edit.tap()
    }

    /// The first touch after launch moves keyboard focus to the app. On the iOS 26.5
    /// simulator a system-gesture change follows about 0.12 s later and cancels any touch
    /// still down (UIKit EventDispatch logs "systemGestureStateChange: 1"): a 0.15 s press,
    /// or a tap synthesized slowly under load, then shows its pressed state but never
    /// fires. Spend that first touch on the menu's static brand text, which has no action.
    static func settleFirstTouch(_ app: XCUIApplication) {
        // The menu's brand text; on a board fixture, the bare table edge beside the mat (the
        // development label sits over the opponent's medallion, which would open its zones).
        // The Arena menus' mark in the top bar (it has no action); older builds' brand text.
        let mark = app.images["menu.brand"].exists ? app.images["menu.brand"] : app.otherElements["menu.brand"]
        let brand = app.staticTexts["MAGICMOBILE"]
        if mark.waitForExistence(timeout: 2) {
            mark.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if brand.exists {
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
