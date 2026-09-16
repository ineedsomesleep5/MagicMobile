import Foundation

@main
struct RoleChecks {
    static var assertions = 0
    static func check(_ condition: Bool, _ label: String) {
        assertions += 1
        guard condition else { fatalError("FAIL: \(label)") }
    }
    static func rejected(_ label: String, _ body: () throws -> Void) {
        do { try body(); check(false, label) } catch { check(true, label) }
    }
    static func roles(_ text: String?, types: [String]? = ["INSTANT"], reviewed: Set<DeckStudioRole>? = nil) -> Set<DeckStudioRole> {
        Set(DeckStudioRoleClassifier.classify(text: text, types: types, reviewed: reviewed).map(\.role))
    }
    static func main() throws {
        let examples: [(String, DeckStudioRole)] = [
            ("{T}: Add {C}{C}.", .ramp),
            ("{T}: Add one mana of any color in your commander's color identity.", .ramp),
            ("Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.", .ramp),
            ("Search your library for up to two basic land cards, reveal them, put one of them onto the battlefield tapped and the other into your hand, then shuffle.", .ramp),
            ("Draw a card.", .cardFlow), ("Draw two cards. Then discard a card.", .cardFlow),
            ("Destroy target creature.", .interaction), ("Exile target permanent.", .interaction),
            ("Counter target spell.", .interaction), ("Counter target noncreature spell.", .interaction),
            ("Destroy all creatures.", .boardWipe), ("Exile all creatures.", .boardWipe),
            ("Permanents you control gain hexproof and indestructible until end of turn.", .protection),
            ("Exile all cards from all graveyards.", .graveyardHate), ("Exile target player's graveyard.", .graveyardHate),
            ("Return target creature card from your graveyard to your hand.", .recursion),
            ("Search your library for a card, put that card into your hand, then shuffle.", .tutor)
        ]
        for (text, expected) in examples {
            check(roles(text) == [expected], "direct pattern \(expected)")
            let evidence = DeckStudioRoleClassifier.classify(text: text, types: ["INSTANT"])
            check(evidence.first?.source == .textPattern && !(evidence.first?.explanation.isEmpty ?? true), "hints explained, not authoritative")
        }
        check(roles(" \nDraw   two cards.\n") == [.cardFlow], "whitespace normalized")
        check(roles("Exile target player’s graveyard.") == [.graveyardHate], "typographic apostrophe")
        check(roles("{T}: Add {G}.", types: ["LAND"]).isEmpty, "lands not automatic ramp")
        check(roles("{T}: Add {G}.", types: nil).isEmpty, "unknown types not asserted nonland")
        check(roles(nil).isEmpty, "unknown rules remain unknown")
        for text in ["Whenever an opponent draws a card, you gain 1 life.",
                     "If you control a Dragon, draw two cards.",
                     "Choose one —\n• Draw two cards.\n• Create a token.",
                     "Creatures you control have \"{T}: Add {G}.\"",
                     "At the beginning of your upkeep, destroy all creatures.",
                     "Destroy target creature unless its controller pays {3}.",
                     "Exile target creature you control.",
                     String(repeating: "x", count: 32769)] {
            check(roles(text).isEmpty, "complex/conditional effect not misread as direct role")
        }
        check(roles("Draw two cards.", reviewed: []).isEmpty, "explicit empty review overrides hint")
        check(roles(nil, reviewed: [.ramp, .protection]) == [.ramp, .protection], "manual multi-role supported without guessed metadata")
        check(DeckStudioRoleClassifier.classify(text: nil, types: nil, reviewed: [.tutor]).first?.source == .reviewed, "manual attribution")
        let entries: [DeckStudioRoleAnalysis.Entry] = [
            .init(name: "Draw", quantity: 2, text: "Draw two cards.", types: ["SORCERY"]),
            .init(name: "Draw", quantity: 1, text: "Draw two cards.", types: ["SORCERY"]),
            .init(name: "Unknown", quantity: 2, text: nil, types: nil),
            .init(name: "Land", quantity: 37, text: "{T}: Add {G}.", types: ["LAND"])
        ]
        let summary = try DeckStudioRoleAnalysis(entries: entries, overrides: [:])
        check(summary.mainCount == 42 && summary.cards.count == 3, "quantity weighted, stable grouped names")
        check(summary.count(.cardFlow) == 3 && summary.count(.ramp) == 0, "role quantities not row counts")
        check(summary.unclassifiedCount == 39 && summary.missingMetadataCount == 2, "unknowns and untagged distinguished")
        let manual = try DeckStudioRoleAnalysis(entries: entries, overrides: ["Unknown": [.protection, .recursion], "Draw": []])
        check(manual.count(.protection) == 2 && manual.count(.recursion) == 2 && manual.count(.cardFlow) == 0, "multi-role overrides replace detection")
        check(manual.cards.first(where: { $0.name == "Draw" })?.userReviewed == true, "empty review still explicit")
        rejected("invalid quantity bounded") { _ = try DeckStudioRoleAnalysis(entries: [.init(name: "Bad", quantity: Int.max, text: nil, types: nil)], overrides: [:]) }
        rejected("inconsistent metadata not silently merged") { _ = try DeckStudioRoleAnalysis(entries: entries + [.init(name: "Draw", quantity: 1, text: nil, types: nil)], overrides: [:]) }
        var prefs = DeckStudioRolePreferences()
        check(prefs.targets.isEmpty, "no universal target imposed")
        let range = DeckStudioRolePreferences.Target(enabled: true, lower: 8, upper: 12)
        check(range.comparison(7) == "Below your target", "personal lower comparison")
        check(range.comparison(8) == "Within your target" && range.comparison(12) == "Within your target", "inclusive personal range")
        check(range.comparison(13) == "Above your target", "personal upper comparison")
        check(DeckStudioRolePreferences.Target().comparison(0) == nil, "disabled target never grades")
        prefs.overrides = ["Example": [.tutor, .ramp], "Explicitly none": []]
        prefs.targets = [.cardFlow: range]
        let suite = "deck-studio-role-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "deckStudio.roles.v1.deck-a"
        try prefs.save(key: key, defaults: defaults)
        check(try DeckStudioRolePreferences.load(key: key, defaults: defaults) == prefs, "role/preferences persistence roundtrip")
        check(try DeckStudioRolePreferences.load(key: key + "other", defaults: defaults) == DeckStudioRolePreferences(), "deck preferences isolated")
        var bad = prefs; bad.targets[.ramp] = .init(enabled: true, lower: 20, upper: 10)
        rejected("reversed range does not replace valid preferences") { try bad.save(key: key, defaults: defaults) }
        check(try DeckStudioRolePreferences.load(key: key, defaults: defaults) == prefs, "valid stored settings preserved after rejection")
        bad = prefs; bad.schema = 9
        rejected("future schema not overwritten") { _ = try bad.validated() }
        let corrupted = Data("not json".utf8)
        defaults.set(corrupted, forKey: key)
        rejected("corrupt settings reported") { _ = try DeckStudioRolePreferences.load(key: key, defaults: defaults) }
        check(defaults.data(forKey: key) == corrupted, "corrupt original preserved")
        defaults.set(Data(repeating: 0, count: 512 * 1024 + 1), forKey: key)
        rejected("oversized preferences rejected before decode") { _ = try DeckStudioRolePreferences.load(key: key, defaults: defaults) }
        print("PASS: \(assertions) role-analysis and preference assertions. Pattern/fixture coverage, not full-card strategic or phone validation.")
    }
}
