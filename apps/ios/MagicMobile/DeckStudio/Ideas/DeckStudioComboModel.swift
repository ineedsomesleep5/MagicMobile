#if canImport(Combine)
import Foundation
import Combine

/// Workspace-owned so tab switches retain results. Network is never started by
/// initialization, observation, draft changes, or a cache read.
@MainActor
final class DeckStudioComboModel: ObservableObject {
    @Published private(set) var input: SpellbookDeck?
    @Published private(set) var snapshot: SpellbookSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var cacheNote: String?
    private let client: CommanderSpellbookClient
    private var token = UUID()
    private var task: Task<Void, Never>?

    init(client: CommanderSpellbookClient = .shared) { self.client = client }
    func setInput(_ deck: SpellbookDeck?) async {
        guard input != deck else { return }
        cancel(); input = deck; snapshot = nil; error = nil; cacheNote = nil
        let captured = token
        if let deck, let stored = await client.cached(for: deck), token == captured, input == deck {
            snapshot = stored; cacheNote = "Previously saved lookup for this exact deck. The provider may have newer data."
        }
    }
    @discardableResult func analyze(approvedDeck: SpellbookDeck, more: Bool = false) -> Task<Void, Never>? {
        guard input == approvedDeck, !loading else { return nil }
        let previous = more ? snapshot : nil
        if more && (previous?.deck != approvedDeck || previous?.nextOffset == nil) { return nil }
        token = UUID(); let captured = token
        loading = true; error = nil
        task = Task { [weak self, client] in
            do {
                let result = try await client.lookup(deck: approvedDeck, continuing: previous)
                try Task.checkCancellation()
                guard let self, self.token == captured, self.input == approvedDeck else { return }
                self.snapshot = result.snapshot; self.loading = false
                self.cacheNote = result.savedToDisk ? "Saved on this device for offline review. iOS may clear cached results." : "Available in this session; the disk cache could not be saved."
                self.task = nil
            } catch is CancellationError {
                guard let self, self.token == captured else { return }
                self.loading = false; self.task = nil
            } catch {
                guard let self, self.token == captured, self.input == approvedDeck else { return }
                self.error = (error as? SpellbookError)?.localizedDescription ?? SpellbookError.unavailable.localizedDescription
                self.loading = false; self.task = nil
            }
        }
        return task
    }
    func cancel() { token = UUID(); task?.cancel(); task = nil; loading = false }
    func clear() async {
        cancel(); snapshot = nil; cacheNote = nil; error = nil
        do { try await client.clearCache() }
        catch { self.error = "The local combo cache could not be fully removed. Your deck is unchanged." }
    }
}
#endif
