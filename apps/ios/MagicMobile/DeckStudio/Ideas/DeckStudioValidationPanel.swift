import SwiftUI
import MagicMobileOnDevice

@MainActor
struct DeckStudioValidationPanel: View {
    @ObservedObject var state: DeckStudioValidationState
    let deck: DeckList?
    let resolver: OnDeviceDeckResolver?
    var play: ((DeckList) -> Void)? = nil
    @ObservedObject private var service = DeckStudioValidationService.shared
    @State private var acknowledgeExclusions = false
    private var prepared: DeckStudioPlayProjection? { deck.flatMap { try? DeckStudioPlayProjection($0) } }
    private var request: MagicMobileOnDevice.JSONValue? {
        guard let prepared, let resolver else { return nil }
        return try? prepared.resolve(resolver)
    }
    private var currentReceipt: DeckStudioValidationReceipt? {
        guard let request, let encoded = try? request.encoded(), let resolver, let receipt = state.receipt,
              receipt.matches(request: encoded, upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash,
                              appBuild: DeckStudioValidationService.appBuild) else { return nil }
        return receipt
    }
    private var exclusionsAccepted: Bool { prepared?.excluded.isEmpty == true || acknowledgeExclusions }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Ready to play?", systemImage: "checkmark.shield").font(.title2.weight(.semibold))
                Text("Check Commander rules, then start a game against AI.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let prepared, !prepared.excluded.isEmpty {
                    Toggle("Validate the playing deck only", isOn: $acknowledgeExclusions).font(.subheadline)
                    Text("\(prepared.excluded.reduce(0) { $0 + $1.quantity }) sideboard/maybeboard cards stay in this draft. Playing creates a separate playable copy; your original remains intact.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                }
                if let value = currentReceipt {
                    Label(value.valid ? "Commander validation passed" : "Commander validation found issues",
                          systemImage: value.valid ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    DisclosureGroup("Validation details") {
                        Text("\(value.checkedAt.formatted(date: .abbreviated, time: .shortened)) · installed XMage · app \(value.appBuild). Applies to these playing cards and this engine build.")
                    }.font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    ForEach(value.issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            if let card = issue.cardName, !card.isEmpty { Text(card).font(.subheadline.weight(.semibold)) }
                            Text(issue.message).font(.caption).textSelection(.enabled)
                            Text([issue.type, issue.group].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                        }
                    }
                } else { Text("Not checked yet").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk) }
                if let error = state.error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger).textSelection(.enabled) }
                if state.checking {
                    ProgressView("Checking Commander rules…")
                    Button("Cancel check") { state.cancelPending() }
                    Text("Please wait for the engine to finish closing before playing.").font(.caption2)
                }
                if service.cleanupRequired {
                    Button("Finish closing") {
                        Task { do { try await service.retryCleanup(); state.error = nil } catch { state.error = error.localizedDescription } }
                    }.buttonStyle(DeckStudioButtonStyle(primary: false)).disabled(service.busy)
                } else {
                    Button(currentReceipt == nil ? "Validate deck" : "Validate again") { validate() }
                        .buttonStyle(DeckStudioButtonStyle()).disabled(request == nil || service.busy || !exclusionsAccepted)
                        .accessibilityIdentifier("deckStudio.validate")
                    if let play, let prepared {
                        Button("Play against AI", systemImage: "play.fill") { play(prepared.playing) }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                            .disabled(currentReceipt?.valid != true || service.busy || !exclusionsAccepted)
                            .accessibilityIdentifier("deckStudio.playtestValidated")
                    }
                }
                if request == nil, let deck, let resolver { Text(preparationError(deck, resolver)).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
            }
        }
        .onAppear { state.prepare(request) }
        .onChange(of: request) { _, value in state.prepare(value) }
        .onChange(of: deck) { _, _ in acknowledgeExclusions = false }
        .onDisappear { state.cancelPending() }
    }
    private func preparationError(_ deck: DeckList, _ resolver: OnDeviceDeckResolver) -> String {
        do { _ = try DeckStudioPlayProjection(deck).resolve(resolver); return "" }
        catch { return error.localizedDescription }
    }
    private func validate() {
        guard let request, let resolver, exclusionsAccepted else { return }
        state.validate(request, resolver: resolver)
    }
}
