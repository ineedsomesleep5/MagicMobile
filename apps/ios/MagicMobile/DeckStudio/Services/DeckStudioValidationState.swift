import Foundation
import Combine
import MagicMobileOnDevice

@MainActor
final class DeckStudioValidationState: ObservableObject {
    @Published private(set) var receipt: DeckStudioValidationReceipt?
    @Published private(set) var checking = false
    @Published var error: String?
    /// The saved deck being checked. When set, each result is stored under it, so
    /// reopening the deck or pressing Play does not run XMage again for the same cards.
    var deckID: String?
    private let store: DeckStudioReceiptStore
    private var request: Data?
    private var token = UUID()
    private var task: Task<Void, Never>?
    init(store: DeckStudioReceiptStore? = nil) { self.store = store ?? .shared }
    func prepare(_ deck: MagicMobileOnDevice.JSONValue?) {
        let data = try? deck?.encoded()
        guard data != request else { return }
        cancelPending(); request = data; receipt = nil; error = nil
    }
    func cancelPending() { token = UUID(); task?.cancel(); task = nil; checking = false }
    func validate(_ deck: MagicMobileOnDevice.JSONValue, resolver: OnDeviceDeckResolver) {
        prepare(deck)
        guard !checking else { return }
        let captured = UUID(); token = captured; checking = true; receipt = nil; error = nil
        task = Task { [weak self] in
            do {
                let value = try await DeckStudioValidationService.shared.validate(deck, resolver: resolver)
                try Task.checkCancellation()
                guard let self, self.token == captured else { return }
                self.receipt = value; self.checking = false; self.task = nil
                if let deckID = self.deckID { self.store.record(DeckStudioStoredCheck(deckID: deckID, receipt: value)) }
            } catch {
                guard let self, self.token == captured else { return }
                self.checking = false; self.task = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
