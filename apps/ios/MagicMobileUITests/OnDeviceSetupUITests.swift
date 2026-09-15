import XCTest

/// Real setup views in a presentation-only build; no native gameplay or Game Center login.
@MainActor
final class OnDeviceSetupUITests: XCTestCase {
    private var app: XCUIApplication!
    private var createdDeckNames: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // A private preference suite stays writable and survives this test's relaunches.
        // Argument-domain game settings would override AppStorage writes during interaction.
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--ondevice-setup-ui-test"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            cleanupCreatedDecks()
            app.terminate()
        }
        app = nil
    }

    func testEmptyNameDisablesStartAndEnteringNameEnablesIt() {
        openSetup()
        let start = app.buttons["Start game"]
        reveal(start)
        XCTAssertFalse(start.isEnabled)

        let playerName = app.textFields["ondevice.playerName"]
        reveal(playerName, scrollingUp: false)
        playerName.tap()
        playerName.typeText("Setup Tester")
        reveal(start)
        waitFor(start, predicate: "enabled == true")
    }

    func testPlayButtonWholeLabelRoutesToSetup() {
        for horizontal in [0.15, 0.5, 0.85] {
            let play = app.buttons["menu.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            reveal(play)
            play.coordinate(withNormalizedOffset: CGVector(dx: horizontal, dy: 0.5)).tap()
            XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 5))
            app.buttons["Main menu"].tap()
        }
    }

    func testGameCenterSettingsAllowTwoThroughFourHumansWithoutSigningIn() {
        openSetup()
        let gameCenter = app.segmentedControls.buttons["Game Center"]
        reveal(gameCenter)
        gameCenter.tap()
        let humans = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Human players")).firstMatch
        reveal(humans)
        // Select a different value before returning to the initial two-player choice.
        for count in [3, 4, 2] {
            humans.tap()
            let option = app.buttons["\(count) players"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            waitFor(humans, predicate: "label CONTAINS '\(count) players' OR value CONTAINS '\(count) players'")
        }
        let signIn = app.buttons["Sign in to Game Center"]
        reveal(signIn)
        XCTAssertTrue(signIn.exists)
        XCTAssertFalse(app.buttons["Find players"].isEnabled)
        // Neither sign-in nor matchmaking is invoked by this test.
        let ai = app.segmentedControls.buttons["Against AI"]
        reveal(ai, scrollingUp: false)
        ai.tap()
        XCTAssertTrue(app.buttons["Start game"].waitForExistence(timeout: 5))
    }

    func testInvalidImportRetainsDraftUntilCancelled() {
        openLibrary()
        app.buttons["Import"].tap()
        let editor = app.textViews["Deck list text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let submit = app.buttons["Import and select"]
        XCTAssertFalse(submit.isEnabled)
        let deckName = app.textFields["Deck name"]
        let originalName = deckName.value as? String
        let draft = "this is not a deck entry"
        editor.tap()
        editor.typeText(draft)
        // A scroll dismisses the editor keyboard and exposes the import action.
        app.swipeUp()
        reveal(submit)
        submit.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Cannot import line 1:")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        reveal(editor, scrollingUp: false)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertEqual(deckName.value as? String, originalName)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Invalid import retains draft"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cancel"].tap()
        waitFor(editor, predicate: "exists == false")
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 5))
    }

    func testPasteValidDraftInspectEditSaveAndRelaunch() {
        let originalName = uniqueDeckName("Imported")
        let editedName = uniqueDeckName("Renamed")
        openLibrary()
        app.buttons["Import"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: originalName)
        let text = app.textViews["Deck list text"]
        text.tap()
        text.typeText("Commander\n1 Emmara, Soul of the Accord\n\nDeck\n1 Forest")
        let submit = app.buttons["Import and select"]
        reveal(submit); submit.tap()
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
        openSavedDeck(originalName)
        let inspect = app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"]
        reveal(inspect); inspect.tap()
        XCTAssertTrue(app.navigationBars["Emmara, Soul of the Accord"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let edit = app.buttons["Edit"]
        reveal(edit, scrollingUp: false); edit.tap()
        let editorName = app.textFields["Deck name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: 5))
        replaceText(editorName, with: editedName)
        app.buttons["Save"].tap()
        waitFor(editorName, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary()
        openSavedDeck(editedName)
        XCTAssertTrue(app.staticTexts["2 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"].exists)
        let forest = app.buttons["nativeDeck.inspect.Forest"]
        reveal(forest)
        // Artwork/network availability is not an acceptance condition for deck persistence.
    }

    func testIncludedDeckEditingCopyDoesNotMutateBundledDeck() {
        let copyName = uniqueDeckName("PreconCopy")
        openLibrary()
        searchLibrary("Token Triumph")
        let bundled = app.buttons["nativeDeck.bundled.Token Triumph"]
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); bundled.tap()
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"].waitForExistence(timeout: 5))
        capture("Included Commander deck grouped cards")
        let editCopy = app.buttons["Edit a local copy"]
        reveal(editCopy); editCopy.tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: copyName)
        app.buttons["Save"].tap()
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(copyName)
        XCTAssertTrue(app.staticTexts["100 cards · Saved locally"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        openLibrary(); searchLibrary("Token Triumph")
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); bundled.tap()
        XCTAssertTrue(app.staticTexts["100 cards · Included deck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit a local copy"].exists)
        XCTAssertFalse(app.buttons["Delete local deck"].exists)
    }

    func testEmptyNamedDraftPersistsWithoutClaimingPlayLegality() {
        let draftName = uniqueDeckName("EmptyDraft")
        openLibrary()
        app.buttons["New deck"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName)
        app.buttons["Save"].tap()
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["0 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["XMage checks Commander legality when you start a game. Saved drafts may be incomplete."].exists)
        // Deliberately do not select/start an incomplete draft.
    }

    func testCatalogueSearchAddAndQuantityPersistInDraft() {
        let draftName = uniqueDeckName("Catalogue")
        openLibrary()
        app.buttons["New deck"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName)
        let search = app.textFields["Search exact card names"]
        reveal(search); replaceText(search, with: "Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add); add.tap()
        let increase = app.buttons["Add one Sol Ring"]
        reveal(increase); increase.tap()
        XCTAssertTrue(app.staticTexts["Quantity 2"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["2 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Sol Ring"].exists)
    }

    func testMissingNativeLibraryReportsFailureAndKeepsSetupAvailable() {
        openSetup()
        let playerName = app.textFields["ondevice.playerName"]
        playerName.tap()
        playerName.typeText("Setup Tester")
        let start = app.buttons["Start game"]
        reveal(start)
        waitFor(start, predicate: "enabled == true")
        start.tap()
        let failure = app.staticTexts[
            "The native XMage library is not linked. No remote engine or simulator was substituted."
        ]
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Unable to start local game"].exists)
        waitFor(start, predicate: "enabled == true")
        XCTAssertTrue(playerName.exists, "A failed start must leave the real setup visible.")
        XCTAssertFalse(app.staticTexts["Game started"].exists)
    }

    func testBasicLandToolsPersistAndStatisticsUseActualQuantities() {
        let draftName = uniqueDeckName("LandTools")
        openLibrary()
        app.buttons["New deck"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName)
        let tools = app.buttons["Basic lands · manual counts"]
        reveal(tools); tools.tap()
        let addForest = app.buttons["Add one basic Forest"]
        reveal(addForest)
        waitFor(addForest, predicate: "enabled == true")
        addForest.tap(); addForest.tap()
        let removeForest = app.buttons["Remove one basic Forest"]
        removeForest.tap()
        capture("Deck builder basic-land controls")
        app.buttons["Save"].tap()
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["1 card · Saved locally"].waitForExistence(timeout: 5))
        let stats = app.segmentedControls.buttons["Stats"]
        reveal(stats); stats.tap()
        XCTAssertTrue(app.staticTexts["Main deck only · 1 card"].waitForExistence(timeout: 5))
        capture("Deck statistics from saved quantities")
        app.segmentedControls.buttons["Cards"].tap()
        let forest = app.buttons["nativeDeck.inspect.Forest"]
        reveal(forest); forest.tap()
        XCTAssertTrue(app.navigationBars["Forest"].waitForExistence(timeout: 5))
        capture("Offline card inspection")
        app.buttons["Done"].tap()
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSetup() {
        let play = app.buttons["menu.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        reveal(play); play.tap()
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gather your table"].exists)
    }

    private func openLibrary() {
        let decks = app.buttons["menu.decks"]
        XCTAssertTrue(decks.waitForExistence(timeout: 15))
        reveal(decks); decks.tap()
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 5))
    }

    private func uniqueDeckName(_ suffix: String) -> String {
        let name = "UI-\(UUID().uuidString)-\(suffix)"
        createdDeckNames.append(name)
        return name
    }

    private func searchLibrary(_ name: String) {
        let search = app.searchFields["Find a deck or commander"]
        reveal(search, scrollingUp: false)
        replaceText(search, with: name + "\n")
    }

    private func openSavedDeck(_ name: String) {
        searchLibrary(name)
        let deck = app.buttons["nativeDeck.saved.\(name)"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        reveal(deck); deck.tap()
        XCTAssertTrue(app.navigationBars["Deck details"].waitForExistence(timeout: 5))
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let existing = field.value as? String ?? ""
        if !existing.isEmpty && existing != field.placeholderValue {
            // Exercise the visible iPhone edit menu. Hardware Command-A can be
            // ignored by the simulator; backspace depends on the caret position.
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
            selectAll.tap()
        }
        field.typeText(text)
        let expected = text.trimmingCharacters(in: .newlines)
        XCTAssertEqual(field.value as? String, expected, "Verify the entered value before saving or searching.")
    }

    /// Never clears the library, defaults, app container, or another test/user's decks.
    /// Relaunch also recovers from a failed test leaving an editor/confirmation open.
    private func cleanupCreatedDecks() {
        for name in createdDeckNames {
            app.terminate(); app.launch()
            let menu = app.buttons["menu.decks"]
            guard menu.waitForExistence(timeout: 15) else {
                XCTFail("Cleanup could not reach library; retained test deck: \(name)"); continue
            }
            menu.tap()
            // Wait for the sheet's actual destination before scrolling. A swipe
            // during presentation can dismiss the sheet instead of revealing search.
            guard app.buttons["Import"].waitForExistence(timeout: 10) else {
                capture("Cleanup library navigation failure")
                XCTFail("Cleanup library did not open; retained test deck: \(name)"); continue
            }
            let search = app.searchFields["Find a deck or commander"]
            guard search.waitForExistence(timeout: 10) else {
                capture("Cleanup library search failure")
                XCTFail("Cleanup search did not appear; retained test deck: \(name)"); continue
            }
            for _ in 0..<5 {
                if search.exists && search.isHittable { break }
                app.swipeDown()
            }
            guard search.exists && search.isHittable else {
                XCTFail("Cleanup search unavailable; retained test deck: \(name)"); continue
            }
            replaceText(search, with: name + "\n")
            let deck = app.buttons["nativeDeck.saved.\(name)"]
            guard deck.waitForExistence(timeout: 3) else { continue } // Never saved, or renamed.
            deck.tap()
            // Filter card rows away so deleting a 100-card copy does not require
            // an unbounded scroll through its artwork. This only changes UI search.
            let cardSearch = app.searchFields["Find a card in this deck"]
            for _ in 0..<5 {
                if cardSearch.exists && cardSearch.isHittable { break }
                app.swipeDown()
            }
            guard cardSearch.exists && cardSearch.isHittable else {
                XCTFail("Cleanup card search unavailable; retained test deck: \(name)"); continue
            }
            replaceText(cardSearch, with: name + "\n")
            let delete = app.buttons["Delete local deck"]
            for _ in 0..<5 {
                if delete.exists && delete.isHittable { break }
                app.swipeUp()
            }
            guard delete.exists && delete.isHittable else {
                XCTFail("Cleanup delete unavailable; retained test deck: \(name)"); continue
            }
            delete.tap()
            // iOS 26 exposes the confirmation action as nested buttons with the
            // same identifier; both represent this one destructive action.
            let confirm = app.buttons.matching(identifier: "nativeDeck.confirmDelete").firstMatch
            guard confirm.waitForExistence(timeout: 5) else {
                XCTFail("Cleanup confirmation unavailable; retained test deck: \(name)"); continue
            }
            confirm.tap()
            waitFor(deck, predicate: "exists == false")
        }
        createdDeckNames.removeAll()
    }

    private func waitFor(_ element: XCUIElement, predicate: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, scrollingUp: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected accessible control: \(element)", file: file, line: line)
    }
}
