import XCTest

/// DEBUG, unlinked presentation target only. These are actual simulator UI captures
/// of supplied design fixtures, NOT real XMage gameplay, legality, privacy, or device acceptance.
/// Artwork is deliberately replaced with placeholders; review layout, not downloaded art.
@MainActor
final class BoardPolishUITests: XCTestCase {
    private var app: XCUIApplication?
    private var currentCapture = "board-polish"
    private var stackDragX: CGFloat = 0.9
    private var modalOffers = false

    func testPortraitModalOfferGlows() {
        modalOffers = true
        runMatrix(portrait: true, selectedFixtures: ["normal-battlefield"])
    }

    func testLandscapeModalOfferGlows() {
        modalOffers = true
        runMatrix(portrait: false, selectedFixtures: ["normal-battlefield"])
    }

    func testSharedD20FitsPortraitAndLandscape() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_MULTIPLAYER_D20_FIXTURE"] = "1"
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        application.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-magicmobile.portraitModeEnabled", "YES"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        capture(application, name: "shared-d20-rolling-fixture")
        XCTAssertFalse(application.buttons["multiplayerD20.continue"].exists)
        let tapToRoll = application.buttons["multiplayerD20.tapToRoll"]
        XCTAssertTrue(tapToRoll.waitForExistence(timeout: 5))
        XCTAssertFalse(application.staticTexts["Rolled 12"].exists, "No die may roll before the first tap")
        tapToRoll.tap()
        XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll))
        currentCapture = "shared-d20-portrait-fixture"
        capture(application, name: currentCapture)
        let result = application.staticTexts["Rolled 12"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        // The reveal is intentionally brief. Read its frame before slower
        // accessibility queries can outlive the result animation.
        let resultFrame = result.frame
        let playerSquare = application.otherElements["multiplayerD20.seat.player1"]
        XCTAssertTrue(playerSquare.exists)
        let playerSquareFrame = playerSquare.frame
        XCTAssertLessThan(abs(resultFrame.midX - application.frame.midX), 20)
        XCTAssertLessThanOrEqual(resultFrame.maxY + 12, playerSquareFrame.minY,
                                 "Rolled result must have a visible gap above player squares")
        let rollArea = application.otherElements["multiplayerD20.rollArea"]
        XCTAssertTrue(rollArea.exists)
        XCTAssertEqual(rollArea.value as? String, "Rebounded from screen edge")
        capture(application, name: "shared-d20-result-above-player-squares")
        for _ in 0..<4 {
            XCTAssertTrue(tapToRoll.waitForExistence(timeout: 12))
            tapToRoll.tap()
            XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll), "Each tap must start a distinct roll")
        }
        XCTAssertTrue(application.staticTexts["Starting roll preview complete"].waitForExistence(timeout: 45))
        application.terminate()

        application.launchEnvironment["MAGICMOBILE_D20_LANDSCAPE_FIXTURE"] = "1"
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        let landscape = NSPredicate { _, _ in
            let frame = application.frame
            return frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: application)],
                                    timeout: 10), .completed)
        currentCapture = "shared-d20-landscape-fixture"
        capture(application, name: currentCapture)
        let landscapeSeats = (1...3).map { application.otherElements["multiplayerD20.seat.player\($0)"] }
        for seat in landscapeSeats {
            XCTAssertTrue(seat.exists)
            XCTAssertLessThan(seat.frame.maxY, application.frame.maxY - 12,
                              "The full player square should be visible without scrolling in landscape")
        }
        XCTAssertTrue(application.buttons["multiplayerD20.skipAnimation"].exists)
        tapToRoll.tap()
        XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll))
        application.buttons["multiplayerD20.skipAnimation"].tap()
        for _ in 0..<4 {
            XCTAssertTrue(tapToRoll.waitForExistence(timeout: 8))
            tapToRoll.tap()
        }
        XCTAssertTrue(application.staticTexts["Starting roll preview complete"].waitForExistence(timeout: 8))
    }

    /// The starting roll covers the board: XMage's pending starting-player choice (You or AI)
    /// neither shows through nor can be reached until the roll is dismissed.
    func testStartingRollHidesTheStartingPlayerChoice() {
        let application = XCUIApplication()
        app = application
        currentCapture = "starting-roll-covers-choice"
        application.launchEnvironment["MAGICMOBILE_STARTING_ROLL_FIXTURE"] = "1"
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        application.launchArguments = ["-magicmobile.boardAppearance", "arena", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-magicmobile.portraitModeEnabled", "YES"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        let tapToRoll = application.buttons["multiplayerD20.tapToRoll"]
        let you = application.buttons["You"]
        let ai = application.buttons["AI"]
        let question = application.staticTexts["Select a starting player"]
        // The board keeps its compact prompt quiet under the roll, so You and AI are not there to hit.
        // XCUITest still lists SwiftUI's accessibilityHidden elements, so the board's own question
        // under the opaque cover counts as covered when it is not hittable.
        func assertChoiceCovered(_ moment: String) {
            XCTAssertTrue(tapToRoll.exists, moment)
            XCTAssertFalse(you.exists, "You must not be reachable under the roll (\(moment))")
            XCTAssertFalse(ai.exists, "AI must not be reachable under the roll (\(moment))")
            XCTAssertFalse(question.exists && question.isHittable, "The question must not show through (\(moment))")
        }
        XCTAssertTrue(tapToRoll.waitForExistence(timeout: 20))
        assertChoiceCovered("before the first roll")
        capture(application, name: currentCapture)
        tapToRoll.tap()
        XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll))
        application.buttons["multiplayerD20.skipAnimation"].tap()
        XCTAssertTrue(tapToRoll.waitForExistence(timeout: 8))
        assertChoiceCovered("before the AI roll")
        tapToRoll.tap()
        // Once the roll is dismissed the same choice is back on the board (the fixture never answers
        // it), so its absence above came from the roll. The final capture shows it.
        currentCapture = "starting-roll-dismissed"
        XCTAssertTrue(you.waitForExistence(timeout: 12), "The fixture's starting-player choice must appear after the roll")
        XCTAssertTrue(ai.exists)
        XCTAssertFalse(tapToRoll.exists)
    }

    private func waitForRollButtonToDisappear(_ button: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
        return XCTWaiter.wait(for: [gone], timeout: 4) == .completed
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
    }

    override func tearDownWithError() throws {
        if let app {
            capture(app, name: currentCapture + "-final")
            app.terminate()
        }
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    // Independent cases keep one failed control from hiding the remaining surfaces.
    func testRelayTablePreservesAIAndGameCenterSetup() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        application.launchArguments = ["-magicmobile.boardAppearance", "arena", "--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.playerDisplayName", "Test Player"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.buttons["menu.play"].waitForExistence(timeout: 20))
        application.buttons["menu.play"].press(forDuration: 0.15)
        UITestHarness.chooseCustomTable(application)
        let ai = application.segmentedControls.buttons["AI"]
        for _ in 0..<5 {
            if ai.isHittable { break }
            application.swipeUp()
        }
        visible(ai, in: application)
        ai.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Start game"].exists)
        let gameCenter = application.segmentedControls.buttons["Game Center"]
        gameCenter.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Sign in to Game Center"].waitForExistence(timeout: 10))
        XCTAssertTrue(application.buttons["Find players"].exists)
        // "Online" is the iPhone + Android relay table; there is no hosted sign-in or lobby.
        application.segmentedControls.buttons["Online"].press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["ondevice.relay.host"].waitForExistence(timeout: 10))
        XCTAssertFalse(application.textFields["Email"].exists)
        XCTAssertFalse(application.secureTextFields["Password"].exists)
        XCTAssertFalse(application.buttons["Create lobby"].exists)
        XCTAssertFalse(application.buttons["Join"].exists)
        currentCapture = "relay-table-portrait-setup-fixture"
        capture(application, name: currentCapture)
        gameCenter.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Find players"].waitForExistence(timeout: 5))
        ai.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Start game"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Start game"].isEnabled)
        let rollMode = application.segmentedControls.buttons["Roll D20"]
        for _ in 0..<5 where !rollMode.isHittable { application.swipeUp() }
        XCTAssertTrue(rollMode.isHittable)
        rollMode.tap()
        XCTAssertTrue(rollMode.isSelected)
        XCTAssertTrue(application.staticTexts["Everyone rolls a D20. The highest roll starts; ties reroll."].exists)
    }

    func testPortraitCrowdedBattlefield() { runMatrix(portrait: true, selectedFixtures: ["crowded-battlefield"]) }
    func testLandscapeCrowdedBattlefield() { runMatrix(portrait: false, selectedFixtures: ["crowded-battlefield"]) }
    func testPortraitAttachments() { runMatrix(portrait: true, selectedFixtures: ["attached-permanents"]) }
    func testLandscapeAttachments() { runMatrix(portrait: false, selectedFixtures: ["attached-permanents"]) }
    func testEveryBattlefieldBackgroundInPortraitAndLandscape() {
        for theme in ["arena", "midnight", "wood", "moss", "ember", "tide", "tavern"] {
            app?.terminate()
            let application = XCUIApplication()
            app = application
            application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", theme]
            application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = "crowded-battlefield"
            application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
            XCUIDevice.shared.orientation = .portrait
            application.launch()
            XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
            for portrait in [true, false] {
                currentCapture = "background-\(theme)-\(portrait ? "portrait" : "landscape")"
                XCTContext.runActivity(named: currentCapture) { _ in
                    XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
                    let orientation = NSPredicate { _, _ in
                        let frame = application.frame
                        return frame.width > 0 && frame.height > 0 && (portrait ? frame.height > frame.width : frame.width > frame.height)
                    }
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orientation, object: application)], timeout: 10), .completed)
                    let firstRow = card(in: application, identifierPrefix: "card-your-board-isamaru")
                    visible(firstRow, in: application)
                    // Crowded creatures scroll horizontally; later cards need not
                    // be visible before scrolling. Backgrounds must preserve lanes.
                    XCTAssertGreaterThanOrEqual(firstRow.frame.width, 44)
                    visible(application.scrollViews["board.battlefield.Your lands"], in: application)
                    visible(card(in: application, identifierPrefix: "card-your-lands-plains"), in: application)
                    // The tavern's hand rests on the table with no expand button (its design since build 23).
                    if theme == "tavern" {
                        visible(application.scrollViews["board.hand.scroll"], in: application)
                    } else {
                        visible(application.buttons["board.hand.expand"], in: application)
                    }
                    visible(application.buttons["board.action.primary"], in: application)
                    XCTAssertFalse(application.staticTexts["YOUR DECISION"].exists)
                    capture(application, name: currentCapture)
                }
            }
        }
    }

    func testSettingsOffersEveryBattlefieldBackground() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        // A launch-argument appearance pins the argument domain, so a tap could never change it.
        application.launchEnvironment["MAGICMOBILE_UI_TEST_BOARD_APPEARANCE"] = "arena"
        application.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.buttons["menu.settings"].waitForExistence(timeout: 20))
        // A deliberate short press avoids the observed dropped synthesized 50ms
        // taps. Still assert the destination; no retry conceals a failed action.
        XCTAssertTrue(application.buttons["menu.settings"].isHittable)
        application.buttons["menu.settings"].press(forDuration: 0.15)
        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 10))
        for title in ["Stone Arena", "Midnight", "Classic Wood", "Moss Sanctuary", "Obsidian Ember", "Tidal Slate", "Walnut Tavern"] {
            let choice = application.buttons[title + " battlefield"]
            for _ in 0..<3 {
                if choice.isHittable { break }
                application.swipeUp()
            }
            visible(choice, in: application)
            choice.tap()
            let selected = NSPredicate(format: "selected == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: choice)], timeout: 5), .completed)
        }
        currentCapture = "settings-six-battlefield-backgrounds"
        capture(application, name: currentCapture)
    }
    func testPortraitOffscreenCombatInspection() { runMatrix(portrait: true, selectedFixtures: ["combat-arrows"]) }
    func testLandscapeOffscreenCombatInspection() { runMatrix(portrait: false, selectedFixtures: ["combat-arrows"]) }
    func testPortraitManaPayment() { runMatrix(portrait: true, selectedFixtures: ["mana-payment-prompt"]) }
    func testLandscapeManaPayment() { runMatrix(portrait: false, selectedFixtures: ["mana-payment-prompt"]) }
    func testPortraitOpponentFocus() { runMatrix(portrait: true, selectedFixtures: ["four-player-focus"]) }
    func testLandscapeOpponentFocus() { runMatrix(portrait: false, selectedFixtures: ["four-player-focus"]) }
    func testPortraitPlayerTarget() { runMatrix(portrait: true, selectedFixtures: ["player-target-prompt"]) }
    func testLandscapePlayerTarget() { runMatrix(portrait: false, selectedFixtures: ["player-target-prompt"]) }
    func testPortraitZoneInspection() { runMatrix(portrait: true, selectedFixtures: ["zone-inspection"]) }
    func testLandscapeZoneInspection() { runMatrix(portrait: false, selectedFixtures: ["zone-inspection"]) }
    func testPortraitHandInspection() { runMatrix(portrait: true, selectedFixtures: ["full-hand-inspection"]) }
    func testLandscapeHandInspection() { runMatrix(portrait: false, selectedFixtures: ["full-hand-inspection"]) }
    func testPortraitHandArtworkScroll() { runMatrix(portrait: true, selectedFixtures: ["normal-battlefield"]) }
    func testLandscapeHandArtworkScroll() { runMatrix(portrait: false, selectedFixtures: ["normal-battlefield"]) }
    func testPortraitLargeHandScrubber() { runMatrix(portrait: true, selectedFixtures: ["hand-scrubber"]) }
    func testLandscapeLargeHandScrubber() { runMatrix(portrait: false, selectedFixtures: ["hand-scrubber"]) }
    func testPortraitHandDrag() { runMatrix(portrait: true, selectedFixtures: ["hand-drag"]) }
    func testLandscapeHandDrag() { runMatrix(portrait: false, selectedFixtures: ["hand-drag"]) }
    func testPortraitCardBackedAbilityChoice() { runMatrix(portrait: true, selectedFixtures: ["ability-choice"]) }
    func testLandscapeCardBackedAbilityChoice() { runMatrix(portrait: false, selectedFixtures: ["ability-choice"]) }
    func testPortraitPhaseAnnouncement() { runMatrix(portrait: true, selectedFixtures: ["phase-announcement"]) }
    func testLandscapePhaseAnnouncement() { runMatrix(portrait: false, selectedFixtures: ["phase-announcement"]) }
    func testPortraitLifeChange() { runMatrix(portrait: true, selectedFixtures: ["life-change"]) }
    func testLandscapeLifeChange() { runMatrix(portrait: false, selectedFixtures: ["life-change"]) }
    func testPortraitMixedChoices() { runMatrix(portrait: true, selectedFixtures: ["mixed-card-choice"]) }
    func testLandscapeMixedChoices() { runMatrix(portrait: false, selectedFixtures: ["mixed-card-choice"]) }
    func testPortraitScryChoices() { runMatrix(portrait: true, selectedFixtures: ["scry-choice"]) }
    func testLandscapeScryChoices() { runMatrix(portrait: false, selectedFixtures: ["scry-choice"]) }
    func testPortraitLibraryChoices() { runMatrix(portrait: true, selectedFixtures: ["library-choice", "empty-library-choice"]) }
    func testLandscapeLibraryChoices() { runMatrix(portrait: false, selectedFixtures: ["library-choice", "empty-library-choice"]) }

    func testPortraitStackPresentation() {
        runMatrix(portrait: true, selectedFixtures: ["stack-response-prompt"])
    }

    func testPortraitStackArtworkScroll() {
        stackDragX = 0.25
        runMatrix(portrait: true, selectedFixtures: ["stack-response-prompt"])
    }

    func testLandscapeStackPresentation() {
        runMatrix(portrait: false, selectedFixtures: ["stack-response-prompt"])
    }

    func testRotateToLandscapeStackPresentation() {
        runMatrix(portrait: false, selectedFixtures: ["stack-response-prompt"], rotateDuringTest: true)
    }

    /// The tavern pass button turns its glass disc over on a tap (a gesture layered over the
    /// button); the tap must still send the pass.
    func testTavernPassButtonTurnsOverAndStillPasses() {
        app?.terminate()
        let application = XCUIApplication()
        app = application
        application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", "tavern"]
        application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = "normal-battlefield"
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        let pass = application.buttons["board.action.primary"]
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        UITestHarness.settleFirstTouch(application)
        captureImage(name: "tavern-pass-before")
        // A full-screen accessibility container (see the board's overlay layer) makes
        // isHittable unreliable here; tap the button's centre like a finger.
        pass.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Frames across the turn (0.45 s each way) for review; the pass itself is asserted.
        for index in 0..<6 {
            captureImage(name: "tavern-pass-turn-\(index)")
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(application.staticTexts["preview.captured-command"].waitForExistence(timeout: 5),
                      "Tapping the turning pass button must still send the pass")
        captureImage(name: "tavern-pass-after")
    }

    /// The tavern's controls ring and medallion open leather pop-overs instead of system menus,
    /// and a chosen row still does its job once the pop-over has closed.
    func testTavernMenusOpenAndTheirRowsAct() {
        app?.terminate()
        let application = XCUIApplication()
        app = application
        application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", "tavern"]
        application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = "normal-battlefield"
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))

        let controls = application.buttons["Game controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        UITestHarness.settleFirstTouch(application)
        controls.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let log = application.buttons["Game Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "The controls ring opens its menu")
        captureImage(name: "tavern-controls-menu")
        log.tap()
        XCTAssertTrue(application.buttons["Close game log"].waitForExistence(timeout: 5), "A menu row still opens the game log")
        captureImage(name: "tavern-game-log")
        application.buttons["Close game log"].tap()
        XCTAssertTrue(application.buttons["Close game log"].waitForNonExistence(timeout: 5))

        let medallion = application.buttons["board.lifeOrb"]
        XCTAssertTrue(medallion.waitForExistence(timeout: 5))
        medallion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(application.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Graveyard")).firstMatch
            .waitForExistence(timeout: 5), "Your medallion opens your zones")
        captureImage(name: "tavern-zone-menu")
    }

    /// A player's medallion pop-over shows what they carry as icons (counters, commander damage
    /// taken) and, in a pod, swaps between opponents without closing.
    func testTavernPlayerPopoverShowsStatusIconsAndSwapsOpponents() {
        app?.terminate()
        let application = XCUIApplication()
        app = application
        application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", "tavern"]
        application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = "four-player-focus"
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        UITestHarness.settleFirstTouch(application)

        let opponent = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.zones.ai")).firstMatch
        XCTAssertTrue(opponent.waitForExistence(timeout: 10))
        opponent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let swapToKozilek = application.buttons["board.zones.swap.ai-2"]
        XCTAssertTrue(swapToKozilek.waitForExistence(timeout: 5), "A pod's opponent pop-over offers a swap")
        captureImage(name: "tavern-opponent-popover")
        swapToKozilek.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Kozilek carries poison and experience and took Aurelia's commander damage: icons only.
        XCTAssertTrue(application.descendants(matching: .any)["Poison 4"].waitForExistence(timeout: 5),
                      "The swap shows the other opponent's counters in the same pop-over")
        XCTAssertTrue(application.descendants(matching: .any)["Experience 2"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["Aurelia, the Warleader dealt 3 commander damage"].exists)
        XCTAssertFalse(application.staticTexts["Poison"].exists, "Counters are icons, not words")
        captureImage(name: "tavern-opponent-popover-swapped")

        // Close it the way a finger does, on the pop-over's dismiss region outside it.
        let outside = application.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(outside.waitForExistence(timeout: 5))
        outside.tap()
        XCTAssertTrue(swapToKozilek.waitForNonExistence(timeout: 5))
        let mine = application.buttons["board.lifeOrb"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(application.descendants(matching: .any)["Kozilek, the Great Distortion dealt 17 commander damage"]
            .waitForExistence(timeout: 5), "Your own pop-over shows the commander damage you took")
        XCTAssertFalse(application.buttons["board.zones.swap.ai-2"].exists, "Only an opponent's pop-over swaps")
        captureImage(name: "tavern-own-popover")
    }

    /// Walnut Tavern held sideways: the landscape plate with the medallions up the left column,
    /// the phase plate and pass button down the right and the battlefield on the mat.
    func testTavernLandscapeTableKeepsItsControls() {
        for fixture in ["normal-battlefield", "crowded-battlefield", "four-player-focus", "attached-permanents"] {
            app?.terminate()
            let application = XCUIApplication()
            app = application
            application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", "tavern"]
            application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = fixture
            XCUIDevice.shared.orientation = .landscapeLeft
            application.launch()
            XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
            let landscape = NSPredicate { _, _ in application.frame.width > application.frame.height }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: application)], timeout: 10), .completed)
            XCTAssertTrue(application.buttons["board.lifeOrb"].waitForExistence(timeout: 10), "Your medallion in \(fixture)")
            XCTAssertTrue(application.buttons["board.action.primary"].exists, "The pass button in \(fixture)")
            XCTAssertTrue(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.zones.ai")).firstMatch.exists,
                          "The opponent's medallion in \(fixture)")
            XCTAssertTrue(application.otherElements["board.phase.plate"].exists || application.staticTexts["board.phase.plate"].exists
                          || application.descendants(matching: .any)["board.phase.plate"].exists, "The phase plate in \(fixture)")
            let lifeOrb = application.buttons["board.lifeOrb"].frame
            let pass = application.buttons["board.action.primary"].frame
            XCTAssertLessThan(lifeOrb.midX, application.frame.width * 0.25, "Your medallion sits in the left column")
            XCTAssertGreaterThan(pass.midX, application.frame.width * 0.75, "The pass button sits in the right column")
            captureImage(name: "tavern-landscape-\(fixture)")
        }
        // Leave the simulator upright for the next test.
        XCUIDevice.shared.orientation = .portrait
        if let application = app {
            let portrait = NSPredicate { _, _ in application.frame.height > application.frame.width }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: application)], timeout: 10)
        }
    }

    private func runMatrix(portrait: Bool, selectedFixtures: [String], rotateDuringTest: Bool = false) {
        for fixture in selectedFixtures {
            XCTContext.runActivity(named: "\(portrait ? "portrait" : "landscape") / \(fixture)") { _ in
                app?.terminate()
                let application = XCUIApplication()
                app = application
                currentCapture = "\(portrait ? "portrait" : "landscape")-\(fixture)"
                application.launchArguments = ["-magicmobile.boardAppearance", "arena", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                               "-magicmobile.portraitModeEnabled", portrait || rotateDuringTest ? "YES" : "NO"]
                application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = fixture
                application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
                if modalOffers { application.launchEnvironment["MAGICMOBILE_MDFC_UI_TEST"] = "1" }
                XCUIDevice.shared.orientation = portrait || rotateDuringTest ? .portrait : .landscapeLeft
                application.launch()
                XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
                XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
                // Check rendered orientation, not just the requested simulator orientation.
                let orientation = NSPredicate { _, _ in
                    let frame = application.frame
                    return frame.width > 0 && frame.height > 0 && (portrait ? frame.height > frame.width : frame.width > frame.height)
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orientation, object: application)], timeout: 10), .completed)
                verify(fixture, in: application, portrait: portrait)
                capture(application, name: currentCapture)
            }
        }
    }

    private func verify(_ fixture: String, in app: XCUIApplication, portrait: Bool) {
        if modalOffers {
            let values = ["Play land or cast spell available", "Cast spell available", "Play land available"]
            for value in values {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", value)).firstMatch.waitForExistence(timeout: 5))
            }
            capture(app, name: "\(portrait ? "portrait" : "landscape")-modal-offers")
            return
        }
        switch fixture {
        case "attached-permanents":
            visible(app.buttons["board.action.primary"], in: app)
            visible(app.buttons["board.hand.expand"], in: app)
            let lane = app.scrollViews["board.battlefield.Opponent board"]
            let host = card(in: app, identifierPrefix: "card-opponent-board-silvercoat-lion-ai-1-pre")
            for _ in 0..<3 {
                if host.exists && host.isHittable && lane.frame.contains(host.frame) { break }
                lane.swipeLeft()
            }
            visible(host, in: app)
            // Since build 19, Auras and Equipment tuck behind their creature, each peeking above it
            // as a named tab. Two tabs keep the creature near full size; the rest count on the top
            // tab, and the inspector lists every attachment (Build19FeatureUITests).
            let aura = card(in: app, identifierPrefix: "card-opponent-board-karametra-s-favor-human-at")
            let secondAura = card(in: app, identifierPrefix: "card-opponent-board-karametra-s-favor-ai-1-att")
            visible(aura, in: app)
            visible(secondAura, in: app)
            for tucked in [aura, secondAura] {
                XCTAssertEqual(tucked.frame.midX, host.frame.midX, accuracy: 2, "An attachment stays with its host")
                XCTAssertLessThan(tucked.frame.minY, host.frame.minY, "Its tab peeks above the host")
            }
            XCTAssertFalse(card(in: app, identifierPrefix: "card-opponent-board-short-sword").exists,
                           "The third attachment is counted on the top tab, not drawn beside the host")
            XCTAssertFalse(card(in: app, identifierPrefix: "card-your-board-short-sword").exists)
            XCTAssertFalse(card(in: app, identifierPrefix: "card-your-board-karametra-s-favor").exists,
                           "Cross-controller Aura follows its public host, without a duplicate in the controller lane")
            // Touch the Aura where it shows: its tab strip, down to the next card drawn over it.
            let covering = [host, secondAura].map(\.frame.minY).filter { $0 > aura.frame.minY + 1 }.min() ?? host.frame.minY
            let tab = aura.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: aura.frame.width / 2, dy: (covering - aura.frame.minY) / 2))
            tab.tap()
            XCTAssertTrue(aura.label.hasSuffix(", selected"))
            tab.press(forDuration: 0.7)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-karametra-s-favor").waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
            // Landscape keeps mana rocks such as Sol Ring in the resource lane beside the lands.
            let phased = card(in: app, identifierPrefix: portrait ? "card-your-board-sol-ring" : "card-your-lands-sol-ring")
            visible(phased, in: app)
            XCTAssertTrue((phased.value as? String)?.contains("Phased out") == true)
            phased.tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Phased-out card never activates")
            let effects = app.buttons["board.player.effects.ai-1"]
            visible(effects, in: app)
            XCTAssertTrue(effects.label.contains("poison") || effects.label.contains("Poison"))
            effects.tap()
            app.buttons["Curse of Opulence · attached"].tap()
            visible(app.buttons["Inspect Curse of Opulence"], in: app)
            app.buttons["Close Enchanting Aurelia"].tap()
            // Let the viewer finish closing: a tap during its dismissal can land on the viewer.
            XCTAssertTrue(app.buttons["Close Enchanting Aurelia"].waitForNonExistence(timeout: 5))
            advancePreview(app)
            XCTAssertFalse((phased.value as? String)?.contains("Phased out") == true)
            XCTAssertTrue(app.buttons["board.player.effects.human"].label.contains("Poison 5"))
            XCTAssertTrue(app.buttons["board.player.effects.human"].label.contains("Curse of Opulence attached"))
        case "phase-announcement":
            advancePreview(app)
            captureImage(name: currentCapture + "-visible")
            let cue = app.staticTexts["Declare blockers"].firstMatch
            XCTAssertTrue(cue.exists || cue.waitForExistence(timeout: 6))
            // A compact pill under the top HUD keeps the middle of the board clear for combat effects.
            XCTAssertLessThan(cue.frame.midY, app.frame.height * 0.35)
            XCTAssertTrue(cue.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["board.hand.expand"].isHittable)
        case "life-change":
            advancePreview(app)
            captureImage(name: currentCapture + "-loss")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "35 life")).firstMatch.waitForExistence(timeout: 5))
            advancePreview(app)
            captureImage(name: currentCapture + "-gain")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "43 life")).firstMatch.waitForExistence(timeout: 5))
        case "ability-choice":
            // Two sources, Sol Ring then Pitiless Plunderer, each a card-backed choice (fixture since build 26).
            let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@ AND label != %@",
                                                         "Choose ", " ability", "Choose ability"))
            visible(cards.firstMatch, in: app)
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "CHOOSE ABILITY")).count, 1,
                           "Ability details should have only the outer heading")
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", "Choose ability"))
            XCTAssertEqual(choices.count, 2, "Identical abilities retain separate engine choices")
            if app.frame.width > app.frame.height {
                XCTAssertLessThanOrEqual(choices.firstMatch.frame.maxY, app.scrollViews["prompt.details.scroll"].frame.maxY,
                                  "Short ability actions should fit the landscape sheet")
            }
            capture(app, name: currentCapture + "-cards")
            let swipeStart = cards.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            swipeStart.press(forDuration: 0.05, thenDragTo: swipeStart.withOffset(CGVector(dx: 0, dy: -60)))
            XCTAssertFalse(app.buttons["Close card"].exists, "Scrolling must not inspect or select an ability")
            app.buttons["Cancel prompt details"].tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Scrolling must not submit an ability")
            app.buttons["board.action.primary"].tap()
            visible(cards.firstMatch, in: app)
            // Leave margin for simulator scroll-view touch-delivery delay.
            // The app's recognition threshold remains 0.35 seconds.
            cards.firstMatch.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Close card"].waitForNonExistence(timeout: 2), "Releasing a held ability source must close inspection")
            capture(app, name: currentCapture + "-after-hold")
            app.buttons["Cancel prompt details"].tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Inspection must not submit an ability")
            app.buttons["board.action.primary"].tap()
            visible(cards.element(boundBy: 1), in: app)
            // A tap on the card-backed choice must submit, not open a second
            // inspector that makes the user choose the same ability again.
            cards.element(boundBy: 1).tap()
            XCTAssertFalse(app.buttons["Close card"].exists, "Tapping a choice should not open inspection")
            // Fixtures capture commands without advancing an engine snapshot.
            // Dismiss the sheet to expose the capture on the underlying board.
            app.buttons["Cancel prompt details"].tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("22222222-2222-4222-8222-222222222222"))
        case "combat-arrows":
            let lane = app.scrollViews["board.battlefield.Your board"]
            visible(lane, in: app)
            let edge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.combat.offscreen.")).firstMatch
            for _ in 0..<5 {
                if edge.exists && edge.isHittable { break }
                lane.swipeLeft()
            }
            visible(edge, in: app)
            capture(app, name: currentCapture + "-edge")
            edge.tap()
            let inspect = app.buttons["Inspect Silvercoat Lion"].firstMatch
            visible(inspect, in: app)
            inspect.tap()
            visible(card(in: app, identifierPrefix: "card-inspector-silvercoat-lion"), in: app)
        case "hand-scrubber":
            let scrubber = app.descendants(matching: .any)["board.hand.scrubber"].firstMatch
            visible(scrubber, in: app)
            XCTAssertGreaterThanOrEqual(scrubber.frame.height, 44)
            let hand = app.scrollViews["board.hand.scroll"]
            let first = card(in: app, identifierPrefix: "card-hand-sol-ring")
            let last = card(in: app, identifierPrefix: "card-hand-spirited-companion-last-han")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            visible(last, in: app)
            XCTAssertEqual(scrubber.value as? String, "100 percent")
            // The fan tilts the end cards, so their bounding box reaches past the row; the hand's mask
            // shows 12 pt either side for exactly that (PortraitHand's .mask padding).
            let fanTilt: CGFloat = 12
            XCTAssertGreaterThanOrEqual(last.frame.minX, hand.frame.minX - fanTilt)
            XCTAssertLessThanOrEqual(last.frame.maxX, hand.frame.maxX + fanTilt)
            app.buttons["board.hand.expand"].tap()
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            visible(last, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -fanTilt, dy: -1).contains(last.frame))
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertEqual(scrubber.value as? String, "50 percent")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)))
            visible(first, in: app)
            XCTAssertEqual(scrubber.value as? String, "0 percent")
            hand.swipeLeft()
            XCTAssertNotEqual(scrubber.value as? String, "0 percent", "Card swipes update the same slider")
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Scrubbing must not cast a card")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
            first.press(forDuration: 0.6)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-sol-ring").waitForNonExistence(timeout: 2), "Hand inspection ends on release")
        case "hand-drag":
            app.buttons["board.hand.expand"].tap()
            let source = card(in: app, identifierPrefix: "card-hand-sol-ring")
            let destination = card(in: app, identifierPrefix: "card-your-board-isamaru")
            visible(source, in: app)
            visible(destination, in: app)
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            let capture = app.staticTexts["preview.captured-command"]
            XCTAssertTrue(capture.waitForExistence(timeout: 5))
            XCTAssertTrue(capture.label.contains("Cast Sol Ring"))
        case "mixed-card-choice":
            visible(app.buttons["board.choice.target.ai-1"], in: app)
            app.buttons["board.choice.target.ai-1"].tap()
            XCTAssertTrue(app.buttons["board.choice.confirm"].isEnabled)
            app.buttons["board.choice.confirm"].tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
        case "scry-choice", "library-choice", "empty-library-choice":
            let header = app.staticTexts["board.choice.header"].firstMatch
            let close = app.buttons["Close card choices"]
            let confirm = app.buttons["board.choice.confirm"]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            // SwiftUI exposes a modal ancestor with a full-screen AX frame.
            // Measure the visible content instead of that inherited container.
            func contentBounds() -> CGRect {
                header.frame.union(close.frame).union(confirm.frame)
            }
            XCTAssertLessThan(abs(contentBounds().midX - app.frame.midX), 35, "Card dialog stays horizontally centered")
            XCTAssertLessThan(abs(contentBounds().midY - app.frame.midY), 60, "Card dialog stays vertically centered")
            XCTAssertLessThanOrEqual(contentBounds().width, portrait ? 430 : 660, "Dialog must not stretch edge-to-edge")
            let choice = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
            visible(choice, in: app)
            XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Keep-all is a valid scry draft")
            if fixture == "empty-library-choice" {
                choice.tap()
                XCTAssertFalse(confirm.isEnabled, "No-match searches must not enable an invalid response")
            } else {
                choice.tap()
                XCTAssertTrue(confirm.isEnabled)
                choice.tap()
                XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Tap again removes the draft choice")
                choice.press(forDuration: 0.6)
                XCTAssertTrue(app.buttons["board.choice.inspection.close"].waitForNonExistence(timeout: 2), "Card-choice inspection ends on release")
                XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Holding a card must not change the draft")
            }
            if fixture != "scry-choice" {
                let invalid = app.descendants(matching: .any)["board.choice.card.choice-1"].firstMatch
                invalid.tap()
                XCTAssertFalse(confirm.isEnabled)
                visible(app.textFields["board.choice.search"], in: app)
                let search = app.textFields["board.choice.search"]
                search.press(forDuration: 0.15)
                search.typeText("zzzznotacard")
                XCTAssertTrue(app.staticTexts["board.choice.search.empty"].waitForExistence(timeout: 5))
                let clearSearch = app.buttons["board.choice.search.clear"]
                XCTAssertTrue(clearSearch.isHittable)
                clearSearch.press(forDuration: 0.15)
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "Clearing a search restores the supplied cards")
                search.typeText("graveyard")
                XCTAssertTrue(choice.waitForExistence(timeout: 5))
                XCTAssertTrue(choice.isHittable, "Search results remain usable with the keyboard open")
                capture(app, name: currentCapture + "-search-keyboard")
                search.typeText("\n")
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "Rules-only matches remain visible after keyboard dismissal")
                XCTAssertFalse(invalid.exists, "Cards without the rules keyword are filtered out")
                XCTAssertTrue(choice.isHittable, "A matching card stays reachable after search")
                XCTAssertLessThan(abs(contentBounds().midY - app.frame.midY), 60, "Search dismissal restores centered presentation")
                choice.press(forDuration: 0.15)
                XCTAssertEqual(confirm.isEnabled, fixture == "library-choice",
                               "Searching must preserve the engine's eligibility constraints")
            }
            if fixture != "scry-choice" { visible(app.buttons["board.choice.done"], in: app) }
            capture(app, name: currentCapture + "-chooser")
            app.buttons["Close card choices"].tap()
            XCTAssertFalse(app.buttons["board.choice.confirm"].exists)
        case "normal-battlefield":
            app.buttons[portrait ? "Game log" : "Open game log"].firstMatch.tap()
            visible(app.staticTexts["Caleb plays Temple of Plenty"], in: app)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "object_id=")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "<font")).firstMatch.exists)
            capture(app, name: currentCapture + "-formatted-log")
            let logCard = app.links["Temple of Plenty"].firstMatch
            visible(logCard, in: app)
            logCard.tap()
            visible(app.staticTexts["From the game log"], in: app)
            let historicalCard = card(in: app, identifierPrefix: "card-inspector-temple-of-plenty-36fc54d7")
            visible(historicalCard, in: app)
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
            capture(app, name: currentCapture + "-log-card-inspection")
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(historicalCard.waitForNonExistence(timeout: 5))
            app.buttons["Close game log"].tap()
            XCTAssertTrue(app.buttons["Close game log"].waitForNonExistence(timeout: 5))
            let expandHand = app.buttons["board.hand.expand"]
            XCTAssertTrue(expandHand.isHittable)
            expandHand.tap()
            XCTAssertEqual(expandHand.label, "Tuck hand")
            let first = card(in: app, identifierPrefix: "card-hand-sol-ring")
            visible(first, in: app)
            let last = card(in: app, identifierPrefix: "card-hand-spirited-companion")
            let hand = app.scrollViews["board.hand.scroll"]
            let scrubber = app.descendants(matching: .any)["board.hand.scrubber"].firstMatch
            visible(scrubber, in: app)
            XCTAssertGreaterThanOrEqual(scrubber.frame.height, 44)
            // Drag the thumb to the end, then tap the track to return to the start.
            // The actual cards must move, not merely the indicator.
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
            visible(last, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame))
            XCTAssertEqual(scrubber.value as? String, "100 percent")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
            visible(first, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(first.frame))
            XCTAssertEqual(scrubber.value as? String, "0 percent")
            for _ in 0..<5 {
                if last.isHittable && hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame) { break }
                hand.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
                    .press(forDuration: 0.05, thenDragTo: hand.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65)))
            }
            visible(last, in: app)
            // Accessibility rounds subpixel card/viewport edges independently.
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame), "Last hand card must scroll fully into hand viewport: hand=\(hand.frame), last=\(last.frame)")
            last.press(forDuration: 0.6)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-spirited-companion").waitForNonExistence(timeout: 2), "Hand inspection ends on release")
        case "crowded-battlefield":
            XCTAssertFalse(app.staticTexts["YOUR DECISION"].exists, "Routine priority must not cover the battlefield with a redundant banner")
            let firstRow = card(in: app, identifierPrefix: "card-your-board-isamaru")
            let secondRow = card(in: app, identifierPrefix: "card-your-board-sun-titan")
            visible(firstRow, in: app)
            visible(secondRow, in: app)
            XCTAssertGreaterThan(secondRow.frame.minY, firstRow.frame.midY, "Crowded permanents use the reclaimed height for a second row")
            XCTAssertGreaterThanOrEqual(secondRow.frame.width, 44)
            XCTAssertFalse(app.buttons["Close game log"].exists, "Log must start closed")
            let log = app.buttons[portrait ? "Game log" : "Open game log"].firstMatch
            visible(log, in: app)
            log.tap()
            visible(app.buttons["Close game log"], in: app)
            capture(app, name: currentCapture + "-log")
            app.buttons["Close game log"].tap()
            XCTAssertTrue(app.buttons["Close game log"].waitForNonExistence(timeout: 5))
            let commander = card(in: app, identifierPrefix: "card-your-board-isamaru")
            visible(commander, in: app)
            commander.tap() // This fixture's creature has no actionable ability.
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "An ordinary tap must still select")
            capture(app, name: currentCapture + "-board")
            // Inspect rather than activate: no synthetic legal action is sent to a server.
            commander.press(forDuration: 5)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-isamaru").waitForNonExistence(timeout: 2), "Battlefield inspection ends on release")
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Holding must not activate the card")
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "Inspection preserves the existing selection")
            commander.tap()
            XCTAssertFalse(commander.label.hasSuffix(", selected"), "A tap still clears selection after inspection")
            commander.tap()
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "Selection remains available after inspection")
            capture(app, name: currentCapture + "-after-inspection-release")
        case "mana-payment-prompt":
            visible(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pay")).firstMatch, in: app)
            if portrait {
                let floatingMana = app.buttons["board.mana.spend.W"]
                visible(floatingMana, in: app)
                floatingMana.tap()
                XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Spend floating {W}"))
            }
            // A mana rock sits with the lands in landscape (BattlefieldRowArrangement.landscapeResources).
            let solRing = card(in: app, identifierPrefix: portrait ? "card-your-board-sol-ring" : "card-your-lands-sol-ring")
            visible(solRing, in: app)
            solRing.tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Tap Sol Ring"))
        case "stack-response-prompt":
            if portrait {
                XCTAssertEqual(app.staticTexts["board.response.status"].label, "Respond to the stack")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)["board.response.window"].firstMatch.waitForExistence(timeout: 5))
            }
            if !portrait && !app.buttons["board.stack.done"].exists {
                let inspectStack = app.buttons["Inspect stack"]
                visible(inspectStack, in: app)
                inspectStack.press(forDuration: 0.15)
            }
            // Portrait auto-opens this fixture; both orientations use BoardStackInspector.
            visible(app.buttons["board.stack.done"], in: app)
            XCTAssertTrue(app.frame.contains(app.buttons["board.stack.done"].frame))
            // design-preview stacks are reversed by stackTopFirst: the spell is first.
            visible(app.staticTexts["Source: Swords to Plowshares"], in: app)
            let stackScroll = app.scrollViews["board.stack.items"]
            XCTAssertTrue(stackScroll.exists)
            // The underlying quick peek uses the same card identity; scope to the modal.
            let spell = stackScroll.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-stack-swords-to-plowshares")).firstMatch
            visible(spell, in: app)
            capture(app, name: currentCapture + "-stack-inspector")
            let abilitySource = app.staticTexts["Source: Prodigal Pyromancer"]
            let abilityCard = stackScroll.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-stack-prodigal-pyromancer")).firstMatch
            for _ in 0..<6 {
                if abilitySource.isHittable && abilityCard.isHittable { break }
                // Short strokes avoid jumping past the source caption on tall rows.
                stackScroll.coordinate(withNormalizedOffset: CGVector(dx: stackDragX, dy: 0.7))
                    .press(forDuration: 0.1, thenDragTo: stackScroll.coordinate(withNormalizedOffset: CGVector(dx: stackDragX, dy: 0.4)))
            }
            visible(abilitySource, in: app)
            visible(abilityCard, in: app)
            capture(app, name: currentCapture + "-stack-ability")
            app.buttons["board.stack.done"].tap()
            XCTAssertTrue(app.buttons["board.stack.done"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["board.action.primary"].label.contains("Pass Priority"))
        case "four-player-focus":
            let focus = app.buttons["board.opponentFocus"]
            visible(focus, in: app)
            focus.tap()
            visible(app.buttons["Kozilek"], in: app)
            visible(app.buttons["Meren"], in: app)
            capture(app, name: currentCapture + "-opponent-menu")
            app.buttons["Meren"].tap()
            let changed = NSPredicate(format: "value == %@", "Meren")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: focus)], timeout: 5), .completed)
            visible(focus, in: app)
        case "player-target-prompt":
            visible(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose a player")).firstMatch, in: app)
            // Target controls must be present; selecting one would invoke a preview command.
            visible(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Aurelia")).firstMatch, in: app)
        case "zone-inspection":
            if portrait {
                // portraitGameContent automatically opens the viewer's graveyard fixture.
                visible(app.buttons["Close You · Graveyard"], in: app)
                visible(app.buttons["Inspect Spirited Companion"], in: app)
                capture(app, name: currentCapture + "-viewer-graveyard")
                app.buttons["Close You · Graveyard"].tap()
            }
            // Exercise the same seat-specific menu route in both layouts, including
            // an empty supplied zone rather than accidentally retaining the viewer's cards.
            let zones = app.buttons["Aurelia zones"]
            visible(zones, in: app)
            zones.tap()
            let graveyard = app.buttons["Graveyard · 0"]
            visible(graveyard, in: app)
            graveyard.tap()
            visible(app.buttons["Close Aurelia · Graveyard"], in: app)
            visible(app.staticTexts["Aurelia · Graveyard · 0"], in: app)
            visible(app.staticTexts["No cards here."], in: app)
            XCTAssertFalse(app.buttons["Inspect Spirited Companion"].exists)
            app.buttons["Close Aurelia · Graveyard"].tap()
            // A revealed top card shows beside your zones, castable; night and the storm count show on the table.
            let top = app.buttons["board.topOfLibrary"]
            visible(top, in: app)
            XCTAssertTrue(top.label.contains("Llanowar Elves") && top.label.contains("you can play it"), top.label)
            XCTAssertTrue(app.staticTexts["NIGHT"].exists || app.descendants(matching: .any)["board.tableHints"].exists)
            capture(app, name: currentCapture + "-top-of-library")
            let ownZones = app.buttons["board.zones.human"]
            visible(ownZones, in: app)
            XCTAssertTrue(ownZones.label.contains("commander cast available"))
            ownZones.tap()
            app.buttons["Command · Cast available"].tap()
            visible(app.buttons["Close You · Command"], in: app)
            app.buttons["Cast"].tap()
            XCTAssertTrue(app.buttons["Close You · Command"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Cast commander"))
        case "full-hand-inspection":
            // ContentView sets the first supplied hand card as inspected on this fixture.
            visible(card(in: app, identifierPrefix: "card-inspector-sol-ring"), in: app)
            // GameRulesText draws {T} and {C} as symbols and reads them by name
            // (GameLogPresentationTests pins the spoken form), so match that label.
            let rules = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "tap : Add colorless mana colorless mana .")).firstMatch
            visible(rules, in: app)
        default:
            XCTFail("Unreviewed fixture: \(fixture)")
        }
    }

    /// The development fixture's advance button. In portrait it sits over the top bar, and on
    /// iOS 27 XCUITest picks a hit point in its padding, which the button does not own, so the
    /// tap did nothing. Tap the middle of its label instead.
    private func advancePreview(_ app: XCUIApplication) {
        let advance = app.buttons["preview.advance"]
        XCTAssertTrue(advance.waitForExistence(timeout: 5))
        advance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func card(in app: XCUIApplication, identifierPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)).firstMatch
    }

    private func visible(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, file: file, line: line)
        XCTAssertTrue(app.frame.intersects(element.frame), "Control is outside the screen", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Control/label is obscured", file: file, line: line)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        captureImage(name: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    // Capture short-lived feedback before the slower accessibility-tree export.
    private func captureImage(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
