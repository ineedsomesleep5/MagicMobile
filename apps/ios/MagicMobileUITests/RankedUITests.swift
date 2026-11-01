import XCTest

/// Quick Match, Ranked, the profile and the rank moments, in the Arena menus (Caleb, 2026-10-04; Arena 2026-10-22).
/// Each screen is captured; no engine game is played here.
@MainActor
final class RankedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func launch(_ environment: [String: String] = [:], settle: Bool = true, arguments: [String] = []) {
        app = XCUIApplication()
        UITestHarness.configure(app, extraArguments: ["-magicmobile.boardAppearance", "tavern"] + arguments)
        environment.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 20))
        if settle { UITestHarness.settleFirstTouch(app) }
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Screens slide in: tap once the control exists and has had time to stop moving. With `until`,
    /// tap again (up to three times) while that next element hasn't appeared: the simulator can swallow a
    /// synthesized tap under load (see UITestHarness.settleFirstTouch). The caller still asserts the result.
    private func tapSteady(_ element: XCUIElement, until next: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element)", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<3 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            guard let next, element.exists else { return }
            if next.waitForExistence(timeout: 4) { return }
        }
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    /// Every game draws its table (ArenaTableDraw): only Quick Match's Advanced can pick one here.
    func testTheTableIsPickedOnlyUnderAdvanced() {
        launch(arguments: ["-magicmobile.boardMode", "arena"])
        tapSteady(app.buttons["menu.play"], until: app.buttons["play.quick"])
        tapSteady(app.buttons["play.quick"], until: app.buttons["quick.level.advanced"])
        tapSteady(app.buttons["quick.level.medium"])
        let table = app.descendants(matching: .any)["table.pick"]
        XCTAssertFalse(table.waitForExistence(timeout: 2), "Medium draws at random")
        tapSteady(app.buttons["quick.level.advanced"], until: table)
        reveal(table)
        XCTAssertTrue(table.waitForExistence(timeout: 10), "Advanced can pick a table")
        capture("Quick Match, Advanced, Table")
        tapSteady(app.buttons["play.ranked"], until: app.buttons["ranked.find"])
        XCTAssertFalse(table.exists, "Ranked draws at random")
    }

    /// Play opens Arena's panel (Caleb, 2026-10-22): the tabs, the three ways to play and each one's start in the
    /// blade; the Ranked tab opens the Ranked Hall, whose Play opens the panel on Ranked.
    func testPlayPanelOffersQuickRankedAndCustom() {
        launch()
        tapSteady(app.buttons["menu.play"], until: app.buttons["play.quick"])
        for id in ["play.quick", "play.ranked", "play.custom", "play.tab.find", "play.tab.friends", "play.tab.recent"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), id)
        }
        tapSteady(app.buttons["play.quick"], until: app.buttons["quick.bracket.0"])
        XCTAssertTrue(app.buttons["quick.bracket.0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quick.start"].exists, "Quick Match starts from the panel")
        capture("Play panel, Quick")
        tapSteady(app.buttons["play.ranked"], until: app.buttons["ranked.find"])
        XCTAssertTrue(app.buttons["ranked.find"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ranked.standing"].exists)
        capture("Play panel, Ranked")
        tapSteady(app.buttons["play.custom"], until: app.buttons["play.start"])
        XCTAssertTrue(app.buttons["play.start"].waitForExistence(timeout: 10), "Custom sets up the table")
        capture("Play panel, Custom")
        tapSteady(app.buttons["lobby.back"], until: app.buttons["menu.tab.ranked"])
        XCTAssertTrue(waitUntilHittable(app.buttons["menu.play"]), "Closing the panel returns to the home page")
        tapSteady(app.buttons["menu.tab.ranked"], until: app.buttons["ranked.hall.play"])
        XCTAssertTrue(app.buttons["ranked.hall.play"].waitForExistence(timeout: 10), "The Ranked tab opens the Ranked Hall")
        XCTAssertTrue(app.buttons["ranked.hall.leaderboard"].exists)
        capture("Ranked Hall")
        tapSteady(app.buttons["ranked.hall.play"], until: app.buttons["ranked.find"])
        XCTAssertTrue(app.buttons["ranked.find"].waitForExistence(timeout: 10), "The hall's Play opens the panel on Ranked")
        tapSteady(app.buttons["lobby.back"], until: app.buttons["ranked.hall.play"])
        tapSteady(app.buttons["menu.tab.home"], until: app.buttons["menu.play"])
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5), "Home returns to the home page")
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if element.exists && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// The fixture leaderboard (SocialFixtures.leaderboard): podium, live strip, rows, scopes and a profile from a row.
    func testLeaderboardShowsPodiumRowsAndScopes() {
        launch(["MAGICMOBILE_UI_TEST_SOCIAL": "1"])
        tapSteady(app.buttons["menu.tab.ranked"], until: app.buttons["ranked.hall.leaderboard"])
        tapSteady(app.buttons["ranked.hall.leaderboard"], until: app.descendants(matching: .any)["leaderboard.podium"])
        XCTAssertTrue(app.descendants(matching: .any)["leaderboard.podium"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["leaderboard.live"].exists)
        XCTAssertTrue(app.buttons["leaderboard.row.Dahlia_Rose"].exists, "The Mythic player leads the podium")
        XCTAssertFalse(app.buttons["leaderboard.row.DaPrivate"].exists, "Private profiles never appear")
        capture("Leaderboard everyone")
        reveal(app.buttons["leaderboard.row.CalebM"])
        XCTAssertTrue(app.buttons["leaderboard.row.CalebM"].exists, "Your own row is on the board")
        capture("Leaderboard rows")
        app.swipeDown(); app.swipeDown()
        // The scopes are Arena's tab strip (ArenaSegmented), named by their titles.
        tapSteady(app.buttons["leaderboard.scope.Friends"], until: app.buttons["leaderboard.row.Aria_Blade"])
        XCTAssertTrue(app.buttons["leaderboard.row.Aria_Blade"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["leaderboard.row.Dahlia_Rose"].exists, "Friends shows friends only")
        capture("Leaderboard friends")
        let header = app.descendants(matching: .any)["publicProfile.header"]
        tapSteady(app.buttons["leaderboard.row.Aria_Blade"], until: header)
        XCTAssertTrue(header.waitForExistence(timeout: 8), "A row opens that player's profile")
        capture("Leaderboard profile")
    }

    func testQuickMatchBracketSheetExplainsTheDeck() {
        launch()
        tapSteady(app.buttons["menu.play"], until: app.buttons["play.quick"])
        tapSteady(app.buttons["play.quick"], until: app.buttons["play.deck.bracket"])
        let bracket = app.buttons["play.deck.bracket"]
        XCTAssertTrue(bracket.waitForExistence(timeout: 10))
        tapSteady(bracket, until: app.buttons["bracket.close"])
        XCTAssertTrue(app.buttons["bracket.close"].waitForExistence(timeout: 5))
        capture("Bracket sheet")
        tapSteady(app.buttons["bracket.close"], until: app.buttons["quick.bracket.0"])
        XCTAssertTrue(app.buttons["quick.bracket.0"].waitForExistence(timeout: 5))
    }

    /// Server trophies join the shelf after the built-in coins, dark until earned (mm_trophies), and new rows need no build.
    func testServerTrophiesStandOnTheShelf() {
        let art = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("design/awards")
        launch(["MAGICMOBILE_UI_TEST_SOCIAL": "1", "MAGICMOBILE_TROPHY_ART": art.path])
        tapSteady(app.buttons["menu.profile"], until: app.descendants(matching: .any)["profile.season"])
        reveal(app.descendants(matching: .any)["profile.seasonBadges"])
        capture("Season badges")
        let earned = app.descendants(matching: .any)["profile.trophy.lightning"]
        let locked = app.descendants(matching: .any)["profile.trophy.grand-collector"]
        reveal(locked)
        XCTAssertTrue(earned.waitForExistence(timeout: 10))
        XCTAssertTrue(locked.exists)
        capture("Trophy shelf")
    }

    func testProfileShowsRankStatsAndHistory() {
        launch(["MAGICMOBILE_UI_TEST_RANK": "gold-2-3-1", "MAGICMOBILE_UI_TEST_MATCHES": "14"])
        let profile = app.buttons["menu.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.rank"].label.contains("Gold II"), "The home page's rank medallion")
        tapSteady(profile, until: app.descendants(matching: .any)["profile.season"])
        XCTAssertTrue(app.descendants(matching: .any)["profile.season"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gold II"].exists)
        capture("Profile top")
        reveal(app.descendants(matching: .any)["profile.achievements"])
        capture("Profile achievements")
        reveal(app.descendants(matching: .any)["profile.history"])
        capture("Profile history")
        // Profile is a top-bar tab with no back chevron: Home leaves it.
        XCTAssertFalse(app.buttons["lobby.back"].exists, "A tab's page has no back chevron")
        tapSteady(app.buttons["menu.tab.home"], until: app.buttons["menu.play"])
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }

    /// Placement matches hide the rank (Caleb, 2026-11-01): the panel counts the games instead.
    func testPlacementsShowTheGameInsteadOfARank() {
        launch(["MAGICMOBILE_UI_TEST_PLACEMENT": "3"], arguments: ["-magicmobile.boardMode", "arena"])
        tapSteady(app.buttons["menu.play"], until: app.buttons["play.ranked"])
        tapSteady(app.buttons["play.ranked"], until: app.buttons["ranked.find"])
        let standing = app.descendants(matching: .any)["ranked.standing"]
        XCTAssertTrue(standing.waitForExistence(timeout: 10))
        XCTAssertTrue(standing.label.contains("Placement 3 of 5"), standing.label)
        capture("Ranked panel, placing")
    }

    func testRankUpAndDownMoments() {
        for kind in ["placed", "tierUp", "tierDown", "divisionUp", "divisionDown"] {
            launch(["MAGICMOBILE_UI_TEST_CEREMONY": kind])
            let ceremony = app.descendants(matching: .any)["rank.ceremony"]
            XCTAssertTrue(ceremony.waitForExistence(timeout: 10), kind)
            capture("\(kind) mid")
            let done = app.buttons["rank.ceremony.continue"]
            XCTAssertTrue(done.waitForExistence(timeout: 8), kind)
            capture("\(kind) settled")
            tapSteady(done)
            // A swallowed synthesized tap (see tapSteady) leaves Continue up: tap it again, at most twice.
            for _ in 0..<2 where ceremony.exists && done.exists {
                if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ceremony)],
                                  timeout: 3) == .completed { break }
                done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ceremony)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "\(kind) closes on Continue")
            app.terminate()
        }
    }
}
