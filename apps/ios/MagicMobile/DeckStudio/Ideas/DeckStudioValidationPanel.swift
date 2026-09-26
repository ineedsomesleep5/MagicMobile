import SwiftUI
import MagicMobileOnDevice

@MainActor
struct DeckStudioValidationPanel: View {
    @ObservedObject var state: DeckStudioValidationState
    let deck: DeckList?
    let resolver: OnDeviceDeckResolver?
    var play: ((DeckList) -> Void)? = nil
    @ObservedObject private var service = DeckStudioValidationService.shared
    @ObservedObject private var store = DeckStudioReceiptStore.shared
    private var prepared: DeckStudioPlayProjection? { deck.flatMap { try? DeckStudioPlayProjection($0) } }
    private var request: MagicMobileOnDevice.JSONValue? {
        guard let prepared, let resolver else { return nil }
        return try? prepared.resolve(resolver)
    }
    /// This session's check, or a stored one for these exact playing cards and this install.
    private var currentReceipt: DeckStudioValidationReceipt? {
        guard let request, let encoded = try? request.encoded(), let resolver else { return nil }
        let appBuild = DeckStudioValidationService.appBuild
        if let receipt = state.receipt, receipt.matches(request: encoded, upstream: resolver.upstreamCommit,
                                                        catalogue: resolver.catalogueHash, appBuild: appBuild) { return receipt }
        guard let deckID = state.deckID else { return nil }
        return store.check(for: DeckStudioCheckKey(deckID: deckID, request: encoded, upstream: resolver.upstreamCommit,
                                                   catalogue: resolver.catalogueHash, appBuild: appBuild))?.receipt(request: encoded)
    }
    private var gameLive: Bool { service.isGameLive() }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Ready to play?", systemImage: "checkmark.shield").font(.title2.weight(.semibold))
                Text("Check the Commander rules on this device, then play this deck.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let prepared, !prepared.excluded.isEmpty {
                    Text(DeckStudioPlayText.excluded(prepared.excluded.reduce(0) { $0 + $1.quantity }))
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
                        .buttonStyle(DeckStudioButtonStyle()).disabled(request == nil || service.busy || gameLive)
                        .accessibilityIdentifier("deckStudio.validate")
                    // The same flow as the header button: it checks the deck when needed.
                    if let play, let prepared {
                        Button(DeckStudioPlayText.play, systemImage: "play.fill") { play(prepared.playing) }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                            .disabled(service.busy || state.checking || gameLive)
                            .accessibilityIdentifier("deckStudio.playtestValidated")
                    }
                    if gameLive { Text(DeckStudioPlayText.gameLive).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                }
                if request == nil, let deck, let resolver { Text(preparationError(deck, resolver)).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
            }
        }
        .onAppear { state.prepare(request) }
        .onChange(of: request) { _, value in state.prepare(value) }
        .onDisappear { state.cancelPending() }
    }
    private func preparationError(_ deck: DeckList, _ resolver: OnDeviceDeckResolver) -> String {
        do { _ = try DeckStudioPlayProjection(deck).resolve(resolver); return "" }
        catch { return error.localizedDescription }
    }
    private func validate() {
        guard let request, let resolver, !gameLive else { return }
        state.validate(request, resolver: resolver)
    }
}
