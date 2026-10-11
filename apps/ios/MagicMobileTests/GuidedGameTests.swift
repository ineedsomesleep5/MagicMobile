import XCTest
@testable import MagicMobile

/// The guided first game's stored state and first-launch welcome. The coach's notes and words are
/// checked against Android in ParityGoldenTests.testGuidedGameCasesOnBothPlatforms.
final class GuidedGameTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let player: [String] = ["MagicMobile"]

    override func setUpWithError() throws {
        suiteName = "GuidedGameTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testWelcomeShowsOnceOnAFirstLaunch() {
        XCTAssertTrue(GuidedGameLaunch.shouldShowWelcome(defaults: defaults, arguments: player, environment: [:]))
        GuidedGameLaunch.markWelcomeSeen(in: defaults)
        XCTAssertFalse(GuidedGameLaunch.shouldShowWelcome(defaults: defaults, arguments: player, environment: [:]))
    }

    func testPlayersWhoSawHowToPlayNeverGetTheWelcome() {
        HowToPlayLaunch.markSeen(in: defaults)
        XCTAssertFalse(GuidedGameLaunch.shouldShowWelcome(defaults: defaults, arguments: player, environment: [:]))
        XCTAssertFalse(GuidedGameLaunch.shouldShowWelcome(defaults: UserDefaults(suiteName: suiteName)!,
                                                          arguments: ["MagicMobile", "--ondevice-setup-ui-test"], environment: [:]))
    }

    func testEachNoteIsRememberedOnceAndANewGameStartsOver() {
        GuidedGameLaunch.remember(.land, in: defaults)
        GuidedGameLaunch.remember(.land, in: defaults)
        GuidedGameLaunch.remember(.cast, in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: GuidedGameLaunch.shownTipsKey), ["land", "cast"])
        XCTAssertEqual(GuidedGameLaunch.shownTips(in: defaults), [.land, .cast])

        GuidedGameLaunch.begin(in: defaults)
        XCTAssertTrue(GuidedGameLaunch.shownTips(in: defaults).isEmpty)
        XCTAssertTrue(defaults.bool(forKey: GuidedGameLaunch.activeKey))
        XCTAssertTrue(defaults.bool(forKey: GuidedGameLaunch.welcomeSeenKey))
        GuidedGameLaunch.end(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: GuidedGameLaunch.activeKey))
    }

    func testNotesAreShort() {
        for tip in GuidedGameTip.allCases {
            XCTAssertLessThanOrEqual(GuidedGameText.title(tip).count, 26, tip.rawValue)
            XCTAssertLessThanOrEqual(GuidedGameText.body(tip).count, 160, tip.rawValue)
        }
    }
}
