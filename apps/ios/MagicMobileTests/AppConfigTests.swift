import XCTest
@testable import MagicMobile

/// AppConfig (mm_app_config, docs/SERVER_CONTROLS.md): the reply read safely, switches on unless named off, the notice
/// remembered once closed, and a server name fix used only for a card the catalogue has.
final class AppConfigTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testTheReplyIsReadAndSwitchesDefaultOn() throws {
        let config = try XCTUnwrap(AppConfig.parse(data(#"{"notice": {"id": "update-64", "text": "Update to build 64."}, "nameFixes": {"A": "B", "": "C", "D": 3}, "switches": {"leaveVote": false, "odd": "yes"}}"#)))
        XCTAssertEqual(config.notice, AppConfig.Notice(id: "update-64", text: "Update to build 64."))
        XCTAssertEqual(config.nameFixes, ["A": "B"])
        XCTAssertFalse(config.isOn("leaveVote"))
        XCTAssertTrue(config.isOn("stackAutoTuck"))
        XCTAssertTrue(config.isOn("odd"))
        XCTAssertNil(try XCTUnwrap(AppConfig.parse(data(#"{"notice": null, "nameFixes": {}, "switches": {}}"#))).notice)
        XCTAssertNil(AppConfig.parse(data("[1, 2]")))
    }

    func testADeckFileIsReadOnlyWhenComplete() throws {
        let sha = String(repeating: "a", count: 64)
        let config = try XCTUnwrap(AppConfig.parse(data(#"{"aiDecks": {"good": {"revision": 2, "url": "https://example.com/a.json", "sha256": "\#(sha)"}, "http": {"revision": 2, "url": "http://example.com/a.json", "sha256": "\#(sha)"}, "short": {"revision": 2, "url": "https://example.com/a.json", "sha256": "abc"}}}"#)))
        XCTAssertEqual(Array(config.deckFiles.keys), ["good"])
        XCTAssertEqual(config.deckFiles["good"]?.revision, 2)
    }

    func testTheStoreKeepsTheLastCopyAndRemembersAClosedNotice() throws {
        let suite = "AppConfigTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = AppConfigStore(defaults: defaults)
        store.store(data(#"{"notice": {"id": "n1", "text": "Hello"}, "nameFixes": {}, "switches": {"leaveVote": false}}"#))
        store.store(data("not json"))
        XCTAssertFalse(store.current.isOn("leaveVote"))
        let notice = try XCTUnwrap(store.shownNotice)
        store.dismissNotice(notice)
        XCTAssertNil(store.shownNotice)
        XCTAssertFalse(AppConfigStore(defaults: defaults).current.isOn("leaveVote"), "the copy survives a relaunch")
    }

    func testAServerNameFixFindsACardTheCatalogueHas() throws {
        let saved = UserDefaults.standard.data(forKey: AppConfigStore.defaultsKey)
        addTeardownBlock {
            AppConfigStore.shared.store(saved ?? Data(#"{"notice": null, "nameFixes": {}, "switches": {}}"#.utf8))
            if saved == nil { UserDefaults.standard.removeObject(forKey: AppConfigStore.defaultsKey) }
        }
        let resolver = try OnDeviceDeckResolver.bundled()
        XCTAssertNil(resolver.canonicalCardName("Bolt of Lightning (Archidekt)"))
        AppConfigStore.shared.store(data(#"{"nameFixes": {"Bolt of Lightning (Archidekt)": "Lightning Bolt", "Nothing Here": "Not A Card"}}"#))
        XCTAssertEqual(resolver.canonicalCardName("Bolt of Lightning (Archidekt)"), "Lightning Bolt")
        XCTAssertNil(resolver.canonicalCardName("Nothing Here"))
    }

    func testAwardsParseWhatTheServerSends() {
        let rows: [[String: Any]] = [
            ["id": "first-mythic", "name": "First to Mythic", "description": "The first.", "imageUrl": "https://example.com/a.png",
             "tint": "#FF7338", "rarity": 3, "note": "Season 1", "awardedAt": "2026-10-30T17:55:30.075436+00:00", "seen": false],
            ["id": "plain", "name": "Plain", "imageUrl": "http://example.com/a.png", "tint": "orange", "rarity": 9],
            ["id": "", "name": "No id"], ["id": "no-name"],
        ]
        let awards = Award.parse(rows)
        XCTAssertEqual(awards.map(\.id), ["first-mythic", "plain"])
        XCTAssertEqual(awards[0].imageURL?.absoluteString, "https://example.com/a.png")
        XCTAssertEqual(awards[0].rarity, 3)
        XCTAssertFalse(awards[0].seen)
        XCTAssertNotNil(awards[0].awardedAt)
        XCTAssertNil(awards[1].imageURL, "art only over https")
        XCTAssertEqual(awards[1].tint, Award.gold)
        XCTAssertEqual(awards[1].rarity, 3)
        XCTAssertTrue(awards[1].seen, "a profile's awards carry no seen flag")
    }
}
