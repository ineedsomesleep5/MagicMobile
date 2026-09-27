import XCTest
@testable import MagicMobile

/// The "How to play" walkthrough's first-launch flag and page rules. The shared words are
/// checked against Android in ParityGoldenTests.testHowToPlayCasesOnBothPlatforms.
final class HowToPlayTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "HowToPlayTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private let player: [String] = ["MagicMobile"]

    func testOpensOnFirstLaunchAndNotAfterItWasClosed() {
        XCTAssertTrue(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: player, environment: [:]))
        HowToPlayLaunch.markSeen(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: HowToPlayLaunch.seenVersionKey), HowToPlayLaunch.contentVersion)
        XCTAssertFalse(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: player, environment: [:]))
    }

    func testClosingNeverLowersANewerStoredVersion() {
        defaults.set(HowToPlayLaunch.contentVersion + 1, forKey: HowToPlayLaunch.seenVersionKey)
        HowToPlayLaunch.markSeen(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: HowToPlayLaunch.seenVersionKey), HowToPlayLaunch.contentVersion + 1)
        XCTAssertFalse(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: player, environment: [:]))
    }

    func testAnOlderStoredVersionShowsTheWalkthroughAgain() {
        XCTAssertTrue(HowToPlayLaunch.shouldShowAutomatically(seenVersion: HowToPlayLaunch.contentVersion - 1, automated: false, forced: false))
    }

    func testAutomationNeverSeesItUnlessATestAsks() {
        let uiTest = ["MagicMobile", "--ondevice-setup-ui-test"]
        XCTAssertTrue(HowToPlayLaunch.isAutomated(arguments: uiTest, environment: [:]))
        XCTAssertTrue(HowToPlayLaunch.isAutomated(arguments: player, environment: ["MAGICMOBILE_DESIGN_PREVIEW": "menu"]))
        XCTAssertTrue(HowToPlayLaunch.isAutomated(arguments: player, environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        XCTAssertTrue(HowToPlayLaunch.isAutomated(arguments: player, environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        XCTAssertFalse(HowToPlayLaunch.isAutomated(arguments: player, environment: [:]))

        XCTAssertFalse(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: uiTest, environment: [:]))
        let forced = uiTest + [HowToPlayLaunch.firstLaunchArgument]
        XCTAssertTrue(HowToPlayLaunch.isForced(arguments: forced))
        XCTAssertTrue(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: forced, environment: [:]))
        HowToPlayLaunch.markSeen(in: defaults)
        XCTAssertFalse(HowToPlayLaunch.shouldShowAutomatically(defaults: defaults, arguments: forced, environment: [:]),
                       "A forced first launch still shows only once")
    }

    func testPagesAreShortAndDistinct() {
        let pages = HowToPlayText.pages
        XCTAssertEqual(pages.count, 10)
        XCTAssertEqual(Set(pages.map(\.id)).count, pages.count)
        for page in pages {
            XCTAssertFalse(page.title.isEmpty, page.id)
            let sentences = page.body.matches(of: #/[.!?](\s|$)/#).count
            XCTAssertTrue((1...3).contains(sentences), "\(page.id) has \(sentences) sentences")
        }
        XCTAssertEqual(HowToPlayText.progress(page: 1, of: pages.count), "Page 1 of 10")
    }
}
