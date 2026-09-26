import CoreGraphics
import XCTest
@testable import MagicMobile

/// Mirrored by Android's core BoardCardPresentationTest.kt with the same cases.
final class BoardCardPresentationTests: XCTestCase {
    private func card(isToken: Bool?, source: String?) -> ZoneCard {
        ZoneCard(instanceId: "token", card: CardIdentity(name: "Sun Titan", typeLine: "Creature — Giant", oracleText: "Vigilance",
                                                         isToken: isToken, copySourceArtworkName: source),
                 tapped: false, summoningSickness: false, cardIcons: nil, counters: ["+1/+1": 1], power: 7, toughness: 7,
                 isCreaturePermanent: true, damage: nil, isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
    }

    func testOnlyAnExplicitTokenCopyGetsTheCopyFrame() {
        XCTAssertEqual(card(isToken: true, source: "Sun Titan").tokenCopySourceName, "Sun Titan")
        XCTAssertNil(card(isToken: true, source: nil).tokenCopySourceName, "a plain token keeps its token art")
        XCTAssertNil(card(isToken: true, source: "  ").tokenCopySourceName)
        XCTAssertNil(card(isToken: false, source: "Sun Titan").tokenCopySourceName, "a nontoken copy is its own printed card")
        XCTAssertNil(card(isToken: nil, source: "Sun Titan").tokenCopySourceName)
    }

    func testTagNamesTheSourceWhenThereIsRoomToReadIt() {
        XCTAssertEqual(TokenCopyPresentation.tag(source: "Sun Titan", cardWidth: 82), "Token copy")
        XCTAssertEqual(TokenCopyPresentation.tag(source: "Sun Titan", cardWidth: 120), "Token copy · Sun Titan")
        XCTAssertEqual(TokenCopyPresentation.tag(source: "Sun Titan", cardWidth: 300), "Token copy · Sun Titan")
    }

    func testTokenCopyFrameRegionsStackWithoutOverlapAndKeepTheArtInTheCompactCrop() {
        for size in [CGSize(width: 40, height: 56), CGSize(width: 82, height: 112), CGSize(width: 150, height: 210), CGSize(width: 300, height: 419)] {
            let frame = TokenCopyFrameLayout(size: size)
            let bounds = CGRect(origin: .zero, size: size)
            let context = "\(size)"
            for region in [frame.nameBar, frame.art, frame.typeBar, frame.textBox, frame.powerToughnessBox, frame.tagSlot] {
                XCTAssertTrue(bounds.contains(region), context)
                XCTAssertGreaterThan(region.height, 0, context)
            }
            XCTAssertLessThanOrEqual(frame.nameBar.maxY, frame.art.minY, context)
            XCTAssertLessThanOrEqual(frame.art.maxY, frame.typeBar.minY, context)
            XCTAssertLessThanOrEqual(frame.typeBar.maxY, frame.textBox.minY, context)
            XCTAssertTrue(frame.textBox.contains(frame.powerToughnessBox.insetBy(dx: 0.5, dy: 0.5)), context)
            XCTAssertLessThanOrEqual(frame.rulesArea(showsPowerToughness: true).maxY, frame.powerToughnessBox.minY, context)
            XCTAssertTrue(frame.art.contains(frame.tagSlot), context)
            let lines = CGFloat(frame.rulesLineLimit(showsPowerToughness: true))
            XCTAssertTrue(lines == 1 || lines * frame.rulesFontSize * 1.25 <= frame.rulesArea(showsPowerToughness: true).height, context)
            XCTAssertEqual(frame.showsRules, size.width >= 60, context)
            guard size.width >= 82 else { continue }
            // ArenaBattlefieldCard shows the tile from 0.19 w of a 1.51 w tall tile, about 12.6% down.
            XCTAssertLessThanOrEqual(frame.art.minY / size.height, 0.15, context)
            XCTAssertGreaterThanOrEqual(frame.art.maxY / size.height, 0.5, context)
            // The tag sits in that visible band, clear of the face's P/T footer.
            XCTAssertGreaterThanOrEqual(frame.tagSlot.minY / size.height, 0.19 / 1.51, context)
            XCTAssertLessThanOrEqual(frame.tagSlot.maxY / size.height, 0.3, context)
        }
        // Same numbers as Android for the inspector-sized frame.
        let inspector = TokenCopyFrameLayout(size: CGSize(width: 300, height: 419))
        XCTAssertEqual(inspector.border, 13.5, accuracy: 0.001)
        XCTAssertEqual(inspector.art.maxY, 232.545, accuracy: 0.001)
        XCTAssertEqual(inspector.rulesLineLimit(showsPowerToughness: true), 4)
    }

    func testIllustrationCropFillsTheBoxWithTheArtWindowCentered() {
        for box in [CGSize(width: 70, height: 46), CGSize(width: 270, height: 130), CGSize(width: 120, height: 120)] {
            let image = CardIllustrationCrop.imageFrame(filling: box)
            let window = CGRect(x: image.minX + image.width * 0.08, y: image.minY + image.height * 0.145,
                                width: image.width * 0.84, height: image.height * 0.385)
            XCTAssertLessThanOrEqual(window.minX, 0.001, "\(box)")
            XCTAssertLessThanOrEqual(window.minY, 0.001, "\(box)")
            XCTAssertGreaterThanOrEqual(window.maxX, box.width - 0.001, "\(box)")
            XCTAssertGreaterThanOrEqual(window.maxY, box.height - 0.001, "\(box)")
            XCTAssertEqual(window.midX, box.width / 2, accuracy: 0.001)
            XCTAssertEqual(window.midY, box.height / 2, accuracy: 0.001)
            XCTAssertEqual(image.height / image.width, CardIllustrationCrop.printedImageAspect, accuracy: 0.0001)
        }
    }

    func testPortraitInspectorGivesRulesTheirRoomAndShrinksTheCardInstead() {
        let available = CGSize(width: 342, height: 582)
        var previous = CGFloat.infinity
        for needed in stride(from: CGFloat(40), through: 700, by: 30) {
            let fit = CardInspectorFit.plan(available: available, hasFooter: true) { _ in needed }
            XCTAssertFalse(fit.horizontal)
            XCTAssertLessThanOrEqual(fit.cardSize.height, previous, "the card only shrinks as the text grows")
            previous = fit.cardSize.height
            XCTAssertLessThanOrEqual(fit.cardSize.height + CardInspectorFit.spacing + fit.footerSize.height, available.height + 0.001)
            XCTAssertLessThanOrEqual(fit.cardSize.width, available.width + 0.001)
            XCTAssertGreaterThanOrEqual(fit.cardSize.height, available.height * CardInspectorFit.minimumCardFraction - 0.001)
            XCTAssertEqual(fit.cardSize.height / fit.cardSize.width, 88.0 / 63.0, accuracy: 0.001)
            if fit.footerFits { XCTAssertEqual(fit.footerSize.height, needed, accuracy: 0.001) }
        }
        // The old footer capped rules at min(200, 38%) in a ScrollView; 300 points now fit unscaled.
        let long = CardInspectorFit.plan(available: available, hasFooter: true) { _ in 300 }
        XCTAssertTrue(long.footerFits)
        XCTAssertEqual(long.footerSize.height, 300, accuracy: 0.001)
        XCTAssertEqual(long.cardSize.height, 582 - 8 - 300, accuracy: 0.001)
        // Only past the card's floor does the text have to shrink.
        let huge = CardInspectorFit.plan(available: available, hasFooter: true) { _ in 900 }
        XCTAssertFalse(huge.footerFits)
        XCTAssertEqual(huge.cardSize.height, 582 * CardInspectorFit.minimumCardFraction, accuracy: 0.001)
        XCTAssertEqual(huge.footerSize.height, 582 - 8 - 582 * CardInspectorFit.minimumCardFraction, accuracy: 0.001)
        // Short text leaves the card at full width.
        let short = CardInspectorFit.plan(available: available, hasFooter: true) { _ in 40 }
        XCTAssertEqual(short.cardSize.width, 342, accuracy: 0.001)
        let bare = CardInspectorFit.plan(available: available, hasFooter: false) { _ in XCTFail("not measured"); return 0 }
        XCTAssertEqual(bare.footerSize, .zero)
        XCTAssertEqual(bare.cardSize.width, 342, accuracy: 0.001)
    }

    func testLandscapeInspectorNarrowsTheCardBeforeShrinkingText() {
        let available = CGSize(width: 500, height: 360)
        let largest = min(500 * CardInspectorFit.landscapeCardFraction, 360 * 63.0 / 88.0)
        let roomy = CardInspectorFit.plan(available: available, hasFooter: true) { _ in 200 }
        XCTAssertTrue(roomy.horizontal)
        XCTAssertEqual(roomy.cardSize.width, largest, accuracy: 0.001)
        XCTAssertEqual(roomy.footerSize.width, 500 - largest - 16, accuracy: 0.001)
        // Text that only fits a wider column narrows the card.
        let wide = CardInspectorFit.plan(available: available, hasFooter: true) { width in width >= 290 ? 340 : 420 }
        XCTAssertTrue(wide.footerFits)
        XCTAssertEqual(wide.cardSize.width, largest * 0.74, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(wide.footerSize.width, 290)
        let never = CardInspectorFit.plan(available: available, hasFooter: true) { _ in 999 }
        XCTAssertFalse(never.footerFits)
        XCTAssertEqual(never.cardSize.width, largest * 0.64, accuracy: 0.001)
        XCTAssertEqual(never.footerSize.height, 360, accuracy: 0.001)
    }

    func testTextScaleIsTheLargestThatFits() {
        XCTAssertEqual(CardInspectorFit.textScale(fitting: 500) { 400 * $0 }, 1)
        XCTAssertEqual(CardInspectorFit.textScale(fitting: 330) { 400 * $0 }, 0.8)
        XCTAssertEqual(CardInspectorFit.textScale(fitting: 100) { 400 * $0 }, 0.6, "the smallest when nothing fits")
    }

    func testAbilityBannerSitsBelowItsShowcaseCardAndNamesTheSource() {
        let ability: CGFloat = 106
        let bannerHalfHeight: CGFloat = 17.5 // 16 pt heavy serif line plus 14 pt padding
        let cardBottomAtHold = ability / 2 * 1.05
        XCTAssertGreaterThan(BoardFXBannerPlan.offset(showcaseHeight: ability, motion: true) - bannerHalfHeight, cardBottomAtHold)
        XCTAssertEqual(BoardFXBannerPlan.offset(showcaseHeight: 210, motion: true), 127, "spell banners keep their place")
        XCTAssertEqual(BoardFXBannerPlan.offset(showcaseHeight: ability, motion: false), 54, "no card without motion")
        XCTAssertEqual(BoardFXBannerPlan.title(name: "Ability", isAbility: true, sourceName: "Prodigal Pyromancer"), "Prodigal Pyromancer · ability")
        XCTAssertEqual(BoardFXBannerPlan.title(name: "Ability", isAbility: true, sourceName: nil), "Ability")
        XCTAssertEqual(BoardFXBannerPlan.title(name: "Deal 1 damage", isAbility: true, sourceName: " "), "Deal 1 damage · ability")
        XCTAssertEqual(BoardFXBannerPlan.title(name: "Lightning Bolt", isAbility: false, sourceName: "Lightning Bolt"), "Lightning Bolt")
    }
}

#if !SWIFT_PACKAGE
// The DEBUG board fixtures live in the app target only (Android: PreviewFixturesTest.kt).
extension BoardCardPresentationTests {
    func testTokenCopyPreviewOpensTheInspectorOnALiveTokenCopy() throws {
        let snapshot = GameBoardPreviewFixtures.snapshot(.tokenCopyInspection)
        let token = try XCTUnwrap(GameBoardPreviewFixtures.inspectedCard(for: .tokenCopyInspection, snapshot: snapshot))
        XCTAssertEqual(token.tokenCopySourceName, "Sun Titan")
        XCTAssertEqual(token.displayPower, "7")
        XCTAssertEqual(token.displayToughness, "7")
        XCTAssertTrue(snapshot.human?.zones.battlefield.contains { $0.instanceId == token.instanceId } == true)
        XCTAssertNil(GameBoardPreviewFixtures.inspectedCard(for: .normalBattlefield, snapshot: snapshot))
    }

    func testAbilityShowcasePutsAnAbilityWithItsSourceOnTheStack() throws {
        let base = GameBoardPreviewFixtures.snapshot(.abilityShowcase)
        let advanced = GameBoardPreviewFixtures.snapshot(.abilityShowcase, specialStateAdvanced: true)
        XCTAssertTrue(base.stackTopFirst.isEmpty)
        XCTAssertNotEqual(BoardFXRevisionKey(snapshot: base), BoardFXRevisionKey(snapshot: advanced), "the board observes the change")
        let events = BoardEventDiffer.events(from: BoardFXState(snapshot: base), to: BoardFXState(snapshot: advanced))
        XCTAssertEqual(events.count, 1)
        guard case let .spellCast(_, name, _, _, weight) = try XCTUnwrap(events.first) else { return XCTFail("expected a cast") }
        XCTAssertEqual(weight, .ability)
        let source = advanced.stackTopFirst.first?.displaySourceCard?.card.name
        XCTAssertEqual(BoardFXBannerPlan.title(name: name, isAbility: true, sourceName: source), "Prodigal Pyromancer · ability")
    }
}
#endif

/// Combat keyword badges; the shared cases live in combat-cases.json (ParityGoldenTests).
extension BoardCardPresentationTests {
    private func fighter(icons: [String] = [], rules: String? = nil, attacking: Bool? = nil, blocking: [String]? = nil) -> ZoneCard {
        ZoneCard(instanceId: "atarka", card: CardIdentity(name: "Atarka, World Render", typeLine: "Legendary Creature — Dragon", oracleText: rules),
                 tapped: true, summoningSickness: false,
                 cardIcons: icons.map { XmageCardIcon(iconType: $0, resourceName: nil, category: "ABILITY", text: nil, hint: nil) },
                 counters: nil, power: 6, toughness: 4, isCreaturePermanent: true, damage: nil,
                 isAttacking: attacking, blocking: blocking, attachedToInstanceId: nil)
    }

    func testGainedDoubleStrikeIsACombatKeywordOfTheLivePermanent() {
        let atarka = fighter(icons: ["ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_DOUBLE_STRIKE", "COMMANDER"],
                             rules: "Flying\nTrample\nWhenever a Dragon you control attacks, it gains double strike until end of turn.",
                             attacking: true)
        XCTAssertEqual(atarka.combatKeywords, [.doubleStrike, .trample, .flying])
        XCTAssertTrue(atarka.isInCombat)
        XCTAssertTrue(CombatKeyword.strikesFirst(Set(atarka.combatKeywords)))
        XCTAssertTrue(CombatKeyword.strikesInRegularStep(Set(atarka.combatKeywords)), "double strike hits in both steps")
        XCTAssertFalse(CombatKeyword.strikesInRegularStep([.firstStrike]), "first strike alone hits only first")
        XCTAssertFalse(CombatKeyword.strikesFirst([.deathtouch]))
    }

    func testOnlyAttackersAndBlockersAreInCombat() {
        XCTAssertFalse(fighter(rules: "Deathtouch").isInCombat)
        XCTAssertFalse(fighter(rules: "Deathtouch", attacking: false, blocking: []).isInCombat)
        XCTAssertTrue(fighter(rules: "Deathtouch", blocking: ["atarka"]).isInCombat)
    }

    func testBadgePlanAlwaysNamesTheMostImportantKeyword() {
        let tiny = CombatKeywordBadgePlan(keywords: [.firstStrike, .deathtouch, .lifelink], cardWidth: 44, cardHeight: 50)
        XCTAssertEqual(tiny.visible, [.firstStrike])
        XCTAssertEqual(tiny.hiddenCount, 2)
        XCTAssertEqual(tiny.label(.firstStrike), "1st strike")
        let roomy = CombatKeywordBadgePlan(keywords: CombatKeyword.allCases, cardWidth: 120, cardHeight: 170)
        XCTAssertEqual(roomy.visible, [.doubleStrike, .deathtouch, .trample], "at most three, first strike folded into double strike")
        XCTAssertEqual(roomy.hiddenCount, 6)
        XCTAssertEqual(roomy.label(.indestructible), "Indestructible")
    }
}
