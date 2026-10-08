import XCTest

/// Friends search as you type, public profiles and the privacy setting, against the debug fixture account
/// (`MAGICMOBILE_UI_TEST_SOCIAL`, see SocialFixtures.swift): no network, no real profile.
@MainActor
final class SocialUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func launch(open: String? = nil, signedIn: Bool = false) {
        app = XCUIApplication()
        UITestHarness.configure(app, extraArguments: ["-magicmobile.boardAppearance", "tavern"])
        app.launchEnvironment["MAGICMOBILE_UI_TEST_SOCIAL"] = "1"
        if signedIn { app.launchEnvironment["MAGICMOBILE_UI_TEST_SIGNED_IN"] = "1" }
        if let open { app.launchEnvironment["MAGICMOBILE_UI_TEST_OPEN"] = open }
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func tapSteady(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(target)")
        Thread.sleep(forTimeInterval: 0.6)
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testFriendsSearchShowsPlayersAsYouType() {
        launch(open: "friends")
        let field = app.textFields["friends.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        capture("Friends")
        tapSteady(field)
        field.typeText("d")
        XCTAssertTrue(element("friends.search.hint").waitForExistence(timeout: 5), "One letter is not enough to search")
        field.typeText("a")
        // Live results: public players that start with "da", never the private one.
        XCTAssertTrue(element("friends.result.DarthMulligan").waitForExistence(timeout: 10))
        XCTAssertTrue(element("friends.result.DaCommander").exists)
        XCTAssertTrue(element("friends.result.Dagger99").exists, "A friends-only profile can be found")
        XCTAssertFalse(element("friends.result.DaPrivate").exists, "A private profile is never listed")
        capture("Search da")
        field.typeText("rt")
        XCTAssertTrue(element("friends.result.DarthMulligan").waitForExistence(timeout: 10))
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                                         object: element("friends.result.DaCommander"))], timeout: 10) == .completed,
                      "Typing narrows the list")
        // Adding from a result turns the button into a "Requested" tag.
        let add = app.buttons["friends.result.add.DarthMulligan"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: add)], timeout: 10) == .completed)
        XCTAssertTrue(element("friends.notice").waitForExistence(timeout: 5))
        capture("Request sent from a search result")
    }

    func testPublicProfileOpensFromASearchResultAndFollowsOpponents() {
        launch(open: "search:Dar")
        let result = element("friends.result.DarthMulligan")
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        tapSteady(result)
        XCTAssertTrue(element("publicProfile.name").waitForExistence(timeout: 10))
        for id in ["publicProfile.header", "publicProfile.rank", "publicProfile.stats", "publicProfile.history"] {
            let target = element(id)
            for _ in 0..<10 where !target.exists { app.swipeUp() }
            XCTAssertTrue(target.exists, id)
        }
        capture("Public profile")
        XCTAssertTrue(app.buttons["lobby.back"].isHittable)
        app.buttons["lobby.back"].tap()
        XCTAssertTrue(element("friends.search").waitForExistence(timeout: 10), "Back returns to the search")
    }

    func testAPrivateProfileShowsOnlyALock() {
        launch(open: "public:DaPrivate")
        XCTAssertTrue(element("publicProfile.restricted").waitForExistence(timeout: 20))
        XCTAssertFalse(element("publicProfile.stats").exists)
        capture("Private profile")
    }

    func testPrivacySettingOnTheOwnProfile() {
        launch(open: "profile")
        let note = element("profile.privacy.note")
        for _ in 0..<14 where !(note.exists && note.isHittable) { app.swipeUp() }
        XCTAssertTrue(note.exists)
        XCTAssertTrue(app.buttons["profile.privacy.public"].isSelected, "Profiles are public by default")
        capture("Privacy setting, public")
        app.buttons["profile.privacy.friends"].tap()
        XCTAssertTrue(app.buttons["profile.privacy.friends"].waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "friends").evaluate(with: element("profile.privacy.note")), "The note explains the choice")
        app.buttons["profile.privacy.private"].tap()
        XCTAssertTrue(app.buttons["profile.privacy.private"].isSelected)
        capture("Privacy setting, private")
    }

    func testAccountCardOffersAppleAndGoogleThenShowsTheAccount() {
        launch(open: "profile")
        let apple = element("profile.account.apple")
        for _ in 0..<14 where !(apple.exists && apple.isHittable) { app.swipeUp() }
        XCTAssertTrue(apple.exists)
        XCTAssertTrue(element("profile.account.google").exists)
        XCTAssertFalse(element("profile.account.signOut").exists)
        capture("Account card, not signed in")
        app.terminate()

        launch(open: "profile", signedIn: true)
        let signOut = element("profile.account.signOut")
        for _ in 0..<14 where !(signOut.exists && signOut.isHittable) { app.swipeUp() }
        XCTAssertTrue(signOut.exists)
        XCTAssertFalse(element("profile.account.google").exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "player@gmail.com")).firstMatch.exists)
        capture("Account card, signed in with Google")
    }
}
