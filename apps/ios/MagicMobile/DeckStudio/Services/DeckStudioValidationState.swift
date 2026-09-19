import Foundation
import Combine
import MagicMobileOnDevice

@MainActor
final class DeckStudioValidationState: ObservableObject {
    @Published private(set) var receipt: DeckStudioValidationReceipt?
    @Published private(set) var checking = false
    @Published var error: String?
    private var request: Data?
    private var token = UUID()
    private var task: Task<Void, Never>?
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
            } catch {
                guard let self, self.token == captured else { return }
                self.checking = false; self.task = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
