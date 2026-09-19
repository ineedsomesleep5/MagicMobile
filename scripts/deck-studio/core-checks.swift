import Foundation

@main enum DeckStudioCoreChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            precondition(condition(), message)
        }
        let items: [DeckStudioShelfItem] = [
            .init(id: "local:b", name: "Élan Tokens", commanders: ["Emmara", "Partner"], tags: ["Squirrels"], origin: .local, updatedAt: Date(timeIntervalSince1970: 30)),
            .init(id: "local:a", name: "Alpha", commanders: ["Kardur"], tags: [], origin: .local, updatedAt: Date(timeIntervalSince1970: 20)),
            .init(id: "precon:a", name: "Alpha", commanders: ["Atarka"], tags: [], origin: .included, updatedAt: nil)
        ]
        var query = DeckStudioLibraryQuery()
        check(query.apply(to: items, favorites: []).map(\.id) == ["local:b", "local:a", "precon:a"], "Stable recently-edited order")
        query.text = "  ELAN  partner "
        check(query.apply(to: items, favorites: []).map(\.id) == ["local:b"], "Diacritics and partner names")
        query.text = "squirrels"
        check(query.apply(to: items, favorites: []).count == 1, "Tags are searchable")
        query.text = "missing"
        check(query.apply(to: items, favorites: []).isEmpty, "No fabricated match")
        query.text = ""; query.filter = .favorites
        check(query.apply(to: items, favorites: ["local:a"]).map(\.id) == ["local:a"], "Namespaced favorites")
        query.filter = .included
        check(query.apply(to: items, favorites: []).map(\.id) == ["precon:a"], "Included isolation")
        query.filter = .local
        check(query.apply(to: items, favorites: []).count == 2, "Local isolation")
        query.filter = .all; query.sort = .name
        check(query.apply(to: items.reversed(), favorites: []).map(\.id) == ["local:a", "precon:a", "local:b"], "Deterministic tie-break")
        query.sort = .commander
        check(query.apply(to: items, favorites: []).first?.id == "precon:a", "Commander order")

        var history = DeckStudioEditHistory([1], limit: 2)
        check(!history.isDirty && !history.canUndo && !history.canRedo, "Initial history")
        let initial = history.generation
        history.edit { $0.append(2) }
        check(history.isDirty && history.canUndo && history.generation != initial, "Atomic edit")
        let token = history.generation
        history.edit { _ in }
        check(history.generation == token, "No-op does not stale results")
        enum Expected: Error { case failure }
        do { try history.edit { $0.append(99); throw Expected.failure }; preconditionFailure("Expected error") }
        catch Expected.failure { }
        check(history.value == [1, 2] && history.generation == token, "Throw preserves draft and generation")
        history.undo()
        check(history.value == [1] && !history.isDirty && history.canRedo && history.generation != initial, "Undo still invalidates async results")
        history.redo(); history.markSaved()
        check(!history.isDirty && history.value == [1, 2], "Saved baseline")
        history.undo(); history.edit { $0.append(3) }
        check(!history.canRedo && history.value == [1, 3], "New edit clears redo")
        history.edit { $0.append(4) }; history.edit { $0.append(5) }
        history.undo(); history.undo(); history.undo()
        check(history.value == [1, 3], "History memory bounded")
        history.restore([8]); history.undo()
        check(history.value == [1, 3], "Recovery itself undoable")

        for n in 0...12 {
            for k in 0...n {
                for draws in 0...n {
                    var previous = 1.0
                    for target in 0...(min(k, draws) + 1) {
                        let result = try DeckStudioProbability.atLeast(target, successes: k, population: n, draws: draws)
                        check(result >= 0 && result <= 1 && result <= previous + 1e-10, "Probability monotonic and bounded")
                        previous = result
                    }
                }
            }
        }
        for successes in 0...6 {
            for draws in 0...6 {
                let samples = (0..<64).filter { $0.nonzeroBitCount == draws }
                for threshold in -1...7 {
                    let expected = Double(samples.filter { ($0 & ((1 << successes) - 1)).nonzeroBitCount >= threshold }.count) / Double(samples.count)
                    let actual = try DeckStudioProbability.atLeast(threshold, successes: successes, population: 6, draws: draws)
                    check(abs(expected - actual) < 1e-12, "Independent subset enumeration")
                }
            }
        }
        let probability = try DeckStudioProbability.atLeast(2, successes: 2, population: 4, draws: 2)
        check(abs(probability - 1.0 / 6) < 1e-12, "Exact known hypergeometric case")
        let large = try DeckStudioProbability.atLeast(18, successes: 800, population: 2000, draws: 50)
        check(large.isFinite && large > 0 && large < 1, "Large bounded draft stable")
        do { _ = try DeckStudioProbability.atLeast(1, successes: 8, population: 7, draws: 7); preconditionFailure("Invalid accepted") }
        catch DeckStudioProbability.InputError.invalidPopulation { count += 1 }

        for address in ["https://edhrec.com/commanders", "https://www.edhrec.com/recs", "https://edhrec.com:443/articles/example"] {
            check(DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(URL(string: address)!), "EDHREC HTTPS allowed")
        }
        for address in ["http://edhrec.com", "https://edhrec.com.evil.example", "https://evil.example/edhrec.com", "https://user@edhrec.com", "https://edhrec.com:8443", "file:///tmp/report", "javascript:alert(1)"] {
            check(!DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(URL(string: address)!), "Unsafe top-level navigation rejected")
        }
        check(DeckStudioEDHRECPolicy.allowsExternalBrowser(URL(string: "https://example.org")!), "User-approved HTTPS Safari fallback")
        check(!DeckStudioEDHRECPolicy.allowsExternalBrowser(URL(string: "data:text/html,hello")!), "Nonweb external scheme denied")
        print("PASS: \(count) Deck Studio core assertions. Production pure Swift; no iOS, native-engine, or phone execution.")
    }
}
