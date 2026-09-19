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
    static func roles(_ text: String?, types: [String]? = ["INSTANT"], curated: [DeckStudioRole] = [],
                      reviewed: Set<DeckStudioRole>? = nil) -> [DeckStudioRole] {
        DeckStudioRoleClassifier.classify(text: text, types: types, curated: curated, reviewed: reviewed).map(\.role)
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
        // Curated Scryfall oracle tags, bundled at build time, are the primary source.
        check(roles(nil, curated: [.boardWipe]) == [.boardWipe], "curated tag classifies without any rules text")
        check(DeckStudioRoleClassifier.classify(text: nil, types: nil, curated: [.protection]).first?.source == .curated,
              "curated attribution distinguishable from a text pattern")
        check(DeckStudioRoleClassifier.classify(text: nil, types: nil, curated: [.protection]).first.map { !$0.explanation.isEmpty } == true,
              "curated hints stay explained")
        // A card the taggers reached for one role can still match a pattern for another.
        check(roles("Draw two cards.", curated: [.boardWipe]) == [.cardFlow, .boardWipe],
              "curated and pattern roles combine, in declared role order")
        // The same role from both sources is reported once, and credited to the curated data.
        let both = DeckStudioRoleClassifier.classify(text: "Draw two cards.", types: ["SORCERY"], curated: [.cardFlow])
        check(both.count == 1 && both.first?.source == .curated, "curated wins over an equivalent pattern, without duplicating")
        // Your own review still overrides everything, including curated data.
        check(roles("Draw two cards.", curated: [.boardWipe], reviewed: [.tutor]) == [.tutor], "review overrides curated tags")
        check(roles("Draw two cards.", curated: [.boardWipe], reviewed: []).isEmpty, "explicit empty review clears curated tags")
        // Oversized or absent text must not discard curated data.
        check(roles(String(repeating: "x", count: 32769), curated: [.ramp]) == [.ramp], "oversized text still keeps curated roles")

        // Clause extraction: an effect is found after a cost or an earlier sentence, but a
        // triggered or conditional effect is still left for curated data and manual review.
        check(roles("Sacrifice a creature: Draw two cards.") == [.cardFlow], "effect after an activation cost is found")
        check(roles("Flying.\nDraw two cards.") == [.cardFlow], "effect in a later sentence is found")
        check(roles("Draw two cards. Destroy all creatures.") == [.cardFlow, .boardWipe], "several effects in one card")
        check(roles("Cycling {2} (Draw two cards.)").isEmpty, "reminder text never creates a match")
        check(roles("At the beginning of your upkeep, draw two cards.").isEmpty, "triggered effect still not guessed")
        check(roles("If you control a Dragon, draw two cards.").isEmpty, "conditional effect still not guessed")
        for text in [
            "Creatures you control have \"{T}: Draw two cards.\"",
            "Creatures you control have “{T}: Draw two cards.”",
            "Whenever this creature attacks, you may pay {1}. Draw two cards.",
            "If you control a Dragon, gain 2 life. Draw two cards.",
            "Choose one —\n• Gain 2 life. Draw two cards.\n• Create a token.",
            "Cycling {2} (Discard this card (from your hand): Draw two cards.)",
            "{T}: Draw two cards. Activate only if you control a Dragon."
        ] {
            check(roles(text).isEmpty, "scoped or granted instructions are not standalone effects: \(text)")
            check(roles(text, curated: [.protection]) == [.protection], "conservative fallback preserves curated evidence")
        }
        check(roles("Whenever this creature attacks, gain 1 life.\n{T}: Draw two cards.") == [.cardFlow],
              "independent activated ability survives a triggered paragraph")
        check(DeckStudioRoleClassifier.clauses(in: "Draw a card.\nDestroy all creatures.").contains("destroy all creatures."),
              "clauses split on sentence and line boundaries")
        check(DeckStudioRoleClassifier.clauses(in: "{T}: Add {G}.").contains("{t}: add {g}."),
              "an activated ability is also offered whole, so cost-shaped patterns still match")

        // Entries carry curated roles through grouping and quantity weighting.
        let curatedEntries: [DeckStudioRoleAnalysis.Entry] = [
            .init(name: "Wipe", quantity: 1, text: "Some text.", types: ["SORCERY"], curated: [.boardWipe]),
            .init(name: "Wipe", quantity: 1, text: "Some text.", types: ["SORCERY"], curated: [.boardWipe]),
            .init(name: "Shield", quantity: 1, text: "Other text.", types: ["INSTANT"], curated: [.protection])
        ]
        let curatedSummary = try DeckStudioRoleAnalysis(entries: curatedEntries, overrides: [:])
        check(curatedSummary.count(.boardWipe) == 2 && curatedSummary.count(.protection) == 1, "curated roles counted by quantity")
        check(curatedSummary.unclassifiedCount == 0, "curated cards are not reported as unclassified")
        rejected("the same name may not arrive with conflicting curated roles") {
            _ = try DeckStudioRoleAnalysis(entries: [
                .init(name: "Same", quantity: 1, text: "t", types: ["INSTANT"], curated: [.ramp]),
                .init(name: "Same", quantity: 1, text: "t", types: ["INSTANT"], curated: [.tutor])
            ], overrides: [:])
        }

        print("PASS: \(assertions) role-analysis and preference assertions. Pattern/fixture coverage, not full-card strategic or phone validation.")
    }
}
