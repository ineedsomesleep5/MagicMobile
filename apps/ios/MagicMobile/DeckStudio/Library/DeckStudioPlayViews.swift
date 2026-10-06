import SwiftUI

/// The brand's ember call to action, sized for Deck Studio's ivory surfaces.
/// `settled` is the calm "✓ Playing" state: nothing left to do.
struct DeckStudioPlayButtonStyle: ButtonStyle {
    var settled = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius)
        return configuration.label.font((compact ? Font.subheadline : .body).weight(.semibold))
            .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 8 : 12)
            .frame(minHeight: compact ? DeckStudioMetrics.touchTarget : DeckStudioMetrics.controlHeight)
            .foregroundStyle(settled ? DeckStudioPalette.success : BrandTheme.emberInk)
            .background { if settled { shape.fill(DeckStudioPalette.surfaceElevated) } else { shape.fill(BrandTheme.emberGradient) } }
            .overlay(shape.stroke(settled ? DeckStudioPalette.success.opacity(0.5) : .clear))
            .opacity(settled || enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// What the workspace's Play control offers for the open draft.
@MainActor
struct DeckStudioPlayAction {
    enum Kind { case play, saveAndPlay, playing }
    let kind: Kind
    let enabled: Bool

    init(selection: DeckStudioPlaySelection, model: DeckStudioEditorModel) {
        if !model.readOnly && (model.isDirty || model.record == nil) {
            kind = .saveAndPlay
            enabled = model.canSave && selection.resolver != nil && !selection.isChecking
        } else if let id = model.playDeckID, let deck = try? model.draft.deck(), selection.isPlaying(deckID: id, deck: deck) {
            kind = .playing; enabled = false
        } else {
            kind = .play
            enabled = model.playDeckID != nil && selection.resolver != nil && !selection.isChecking
        }
    }

    var title: String {
        switch kind {
        case .play: return DeckStudioPlayText.play
        case .saveAndPlay: return DeckStudioPlayText.saveAndPlay
        case .playing: return DeckStudioPlayText.playing
        }
    }
    var icon: String { kind == .playing ? "checkmark" : "play.fill" }

    static func perform(_ selection: DeckStudioPlaySelection, model: DeckStudioEditorModel) {
        selection.play(name: model.draft.name) {
            let id = try model.preparePlayable()
            return .init(deckID: id, deck: try model.draft.deck())
        }
    }
}

/// The workspace header's primary action: "Play this deck", "Save & play" or "✓ Playing".
struct DeckStudioPlayDeckButton: View {
    @ObservedObject var selection: DeckStudioPlaySelection
    @ObservedObject var model: DeckStudioEditorModel
    var body: some View {
        let action = DeckStudioPlayAction(selection: selection, model: model)
        Button { DeckStudioPlayAction.perform(selection, model: model) } label: {
            Label(action.title, systemImage: action.icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(DeckStudioPlayButtonStyle(settled: action.kind == .playing))
        .disabled(!action.enabled)
        .accessibilityLabel(action.kind == .playing ? DeckStudioPlayText.playingAccessibility : action.title)
        .accessibilityIdentifier("deckStudio.play")
    }
}

/// The same action for the ⋯ menu, where compact layouts hide the header.
struct DeckStudioPlayMenuItem: View {
    @ObservedObject var selection: DeckStudioPlaySelection
    @ObservedObject var model: DeckStudioEditorModel
    var body: some View {
        let action = DeckStudioPlayAction(selection: selection, model: model)
        Button(action.title, systemImage: action.kind == .playing ? "checkmark.circle" : "play.circle") {
            DeckStudioPlayAction.perform(selection, model: model)
        }.disabled(!action.enabled)
    }
}

/// Marks the deck the game setup screen will use.
struct DeckStudioPlayingBadge: View {
    var body: some View {
        Label(DeckStudioPlayText.playing, systemImage: "play.circle.fill")
            .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(BrandTheme.emberInk).background(BrandTheme.ember, in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel(DeckStudioPlayText.playingAccessibility)
    }
}

/// Ready, Needs fixes or Not checked, from the stored XMage check for these cards.
struct DeckStudioPlayStatusChip: View {
    let status: DeckStudioPlayStatus
    var body: some View {
        Label(status.label, systemImage: icon)
            .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(color).background(DeckStudioPalette.surfaceElevated.opacity(0.94), in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel("Deck check: \(status.label)")
    }
    private var icon: String {
        switch status {
        case .ready: return "checkmark.seal.fill"
        case .needsFixes: return "exclamationmark.triangle.fill"
        case .notChecked: return "questionmark.circle"
        }
    }
    private var color: Color {
        switch status {
        case .ready: return DeckStudioPalette.success
        case .needsFixes: return DeckStudioPalette.warning
        case .notChecked: return DeckStudioPalette.secondaryInk
        }
    }
}

/// Pinned above the library: which deck the next game uses and whether it is ready.
struct DeckStudioNowPlayingStrip: View {
    let name: String
    let status: DeckStudioPlayStatus
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill").foregroundStyle(BrandTheme.ember).font(.title3)
                Text(DeckStudioPlayText.nowPlayingStrip(name, status)).font(.subheadline.weight(.semibold))
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            .padding(.horizontal, 20).frame(minHeight: DeckStudioMetrics.touchTarget + 8)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(DeckStudioPalette.ink)
        .background(DeckStudioPalette.surface)
        .overlay(alignment: .bottom) { DeckStudioPalette.separator.frame(height: 1) }
        .accessibilityHint("Opens your playing deck")
        .accessibilityIdentifier("deckStudio.nowPlaying")
    }
}

// MARK: - Flow feedback

extension View {
    /// Presents the play flow's sheets, alert and "Now playing" banner. `deckID` is the
    /// workspace's deck: it receives Fix deck requests and stores its manual checks.
    func deckStudioPlayFeedback(_ selection: DeckStudioPlaySelection, active: Bool = true, deckID: String? = nil,
                                validation: DeckStudioValidationState? = nil,
                                fix: @escaping (_ deckID: String?, _ cards: [String]) -> Void) -> some View {
        modifier(DeckStudioPlayFeedback(selection: selection, active: active, deckID: deckID, validation: validation, fix: fix))
    }
}

private struct DeckStudioPlayFeedback: ViewModifier {
    @ObservedObject var selection: DeckStudioPlaySelection
    let active: Bool
    let deckID: String?
    let validation: DeckStudioValidationState?
    let fix: (String?, [String]) -> Void
    @State private var afterDismiss: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Only a user dismissal ends the flow; a programmatic one already moved on.
            .sheet(isPresented: Binding(get: { active && selection.outcome?.presentsSheet == true },
                                        set: { if !$0, selection.outcome?.presentsSheet == true { selection.dismiss() } }),
                   onDismiss: { let action = afterDismiss; afterDismiss = nil; action?() }) {
                DeckStudioPlaySheet(selection: selection) { deckID, cards in
                    // Opening the deck waits until this sheet has gone.
                    afterDismiss = { fix(deckID, cards) }
                    selection.dismiss()
                }
            }
            .alert(DeckStudioPlayText.gameLive, isPresented: Binding(get: { active && selection.outcome == .gameLive },
                                                                   set: { if !$0, selection.outcome == .gameLive { selection.dismiss() } })) {
                Button("OK", role: .cancel) { selection.dismiss() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if active, case .nowPlaying(_, let name, let excluded)? = selection.outcome {
                        DeckStudioNowPlayingBanner(name: name, excludedCards: excluded,
                                                   setUp: { selection.dismiss(); selection.setUpGame() },
                                                   close: { selection.dismiss() })
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection.outcome)
            }
            .onAppear {
                validation?.deckID = deckID
                if let cards = selection.takeFix(for: deckID) { fix(deckID, cards) }
            }
            .onChange(of: deckID) { _, value in validation?.deckID = value }
            .onChange(of: selection.outcome) { _, value in
                guard active, case .nowPlaying(_, let name, _)? = value else { return }
                AccessibilityNotification.Announcement(DeckStudioPlayText.nowPlaying(name)).post()
            }
    }
}

private struct DeckStudioNowPlayingBanner: View {
    let name: String
    let excludedCards: Int
    let setUp: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(BrandTheme.ember).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DeckStudioPlayText.nowPlaying(name)).font(.subheadline.weight(.semibold)).lineLimit(2)
                if excludedCards > 0 {
                    Text(DeckStudioPlayText.excluded(excludedCards)).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(DeckStudioPlayText.setUpGame, action: setUp)
                .buttonStyle(DeckStudioPlayButtonStyle(compact: true)).fixedSize()
                .accessibilityIdentifier("deckStudio.setUpGame")
            Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 8)
        .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(DeckStudioPalette.separator))
        .shadow(color: DeckStudioPalette.ink.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .foregroundStyle(DeckStudioPalette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deckStudio.nowPlayingBanner")
    }
}

private struct DeckStudioPlaySheet: View {
    @ObservedObject var selection: DeckStudioPlaySelection
    let fix: (String?, [String]) -> Void
    var body: some View {
        Group {
            switch selection.outcome {
            case .checking(_, let name)?:
                VStack(alignment: .leading, spacing: 16) {
                    Text(DeckStudioPlayText.checkingTitle).font(.title2.weight(.bold))
                    Text(DeckStudioPlayText.checking(name)).font(.subheadline).foregroundStyle(DeckStudioPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(DeckStudioPlayText.checkingProgress).frame(maxWidth: .infinity)
                    Button("Cancel", role: .cancel) { selection.cancel() }
                        .buttonStyle(DeckStudioButtonStyle(primary: false)).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("deckStudio.play.cancel")
                    Spacer(minLength: 0)
                }.padding(24)
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
            case .cannotPlay(let deckID, let name, let message, let cards)?:
                // Without a saved deck there is nothing to open, so Fix deck is not offered.
                DeckStudioPlayIssues(title: DeckStudioPlayText.cannotPlayTitle, deckName: name, message: message,
                                     groups: [], cards: cards,
                                     fix: deckID.map { id in { fix(id, $0) } }, notNow: { selection.dismiss() })
            case .blocked(let deckID, let name, let check)?:
                DeckStudioPlayIssues(title: DeckStudioPlayText.blocked(check.issueCount), deckName: name, message: nil,
                                     groups: check.groups, cards: check.cardNames, hidden: check.issueCount - check.issues.count,
                                     fix: { fix(deckID, $0) }, notNow: { selection.dismiss() })
            default:
                Color.clear
            }
        }
        .background(GrimoirePaper().ignoresSafeArea())
        .foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
    }
}

/// Why a deck cannot be the playing deck, with the way back to its rows. The game setup
/// screen shows the same sheet when XMage rejects the deck at Start.
struct DeckStudioPlayIssues: View {
    let title: String
    let deckName: String
    let message: String?
    let groups: [DeckStudioStoredCheck.IssueGroup]
    let cards: [String]
    /// XMage's issues beyond the ones kept.
    var hidden = 0
    /// Fix deck, with the cards to show (all of them, or the one tapped); nil when
    /// there is no saved deck to open.
    let fix: (([String]) -> Void)?
    let notNow: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(title, systemImage: "exclamationmark.triangle.fill").font(.title2.weight(.bold))
                        .foregroundStyle(DeckStudioPalette.ink).accessibilityAddTraits(.isHeader)
                    Text(deckName).font(.subheadline).foregroundStyle(DeckStudioPalette.secondaryInk)
                    if let message { Text(message).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(DeckStudioPlayText.issueCount(group.issues.count)).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            }
                            ForEach(group.issues) { issue in
                                VStack(alignment: .leading, spacing: 2) {
                                    if let card = issue.cardName, !card.isEmpty { cardButton(card) }
                                    Text(issue.message).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DeckStudioPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if groups.isEmpty && !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 4) { ForEach(cards, id: \.self) { cardButton($0) } }
                    }
                    if hidden > 0 { Text(DeckStudioPlayText.notShown(hidden)).font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                if let fix {
                    Button { fix(cards) } label: { Label(DeckStudioPlayText.fixDeck, systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity) }
                        .buttonStyle(DeckStudioButtonStyle()).accessibilityIdentifier("deckStudio.play.fix")
                }
                Button(DeckStudioPlayText.notNow, action: notNow).buttonStyle(DeckStudioButtonStyle(primary: false))
                    .frame(maxWidth: .infinity).accessibilityIdentifier("deckStudio.play.notNow")
            }.padding(.horizontal, 24).padding(.vertical, 12).background(GrimoirePaper())
        }
        .presentationDetents([.medium, .large])
    }
    /// Each named card jumps to its own row.
    @ViewBuilder private func cardButton(_ card: String) -> some View {
        if let fix {
            Button { fix([card]) } label: {
                Label(card, systemImage: "magnifyingglass").font(.subheadline.weight(.semibold)).frame(minHeight: 32)
            }.buttonStyle(.plain).foregroundStyle(DeckStudioPalette.accent)
                .accessibilityHint("Shows this card in the deck")
        } else {
            Text(card).font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Colour identity outside Deck Studio

/// Commander colour identity for screens that do not hold the card catalogue. Deck
/// Studio fills the cache as it lists decks. The setup screen shows colours only once
/// the catalogue has loaded this way; it never loads the catalogue itself (Android's
/// setup screen follows the same rule).
@MainActor
enum DeckStudioDeckColors {
    private static var cache: [[String]: [String]] = [:]

    @discardableResult
    static func remember(commanders: [String], metadata: NativeDeckMetadataCatalogue?) -> [String]? {
        guard let metadata, !commanders.isEmpty else { return nil }
        var union = Set<String>()
        for name in commanders {
            guard let colors = metadata.card(named: name)?.colorIdentity else { return nil }
            union.formUnion(colors)
        }
        let colors = ["W", "U", "B", "R", "G"].filter(union.contains)
        cache[commanders.sorted()] = colors
        return colors
    }

    static func colors(for commanders: [String]) -> [String]? {
        commanders.isEmpty ? nil : cache[commanders.sorted()]
    }
}

// MARK: - Game setup

/// A Start that XMage rejected for the player's deck. The setup model has already
/// stored the failed check; the setup screen explains it with the Play issues sheet.
struct DeckStudioStartIssues: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let check: DeckStudioStoredCheck
}

/// Under the playing deck on the game setup screen: its size, colours and whether XMage
/// has checked it on this device. A failed Start is explained the same way as Play.
struct OnDeviceSetupDeckDetails: View {
    let deckID: String
    /// The playing projection that every game start sends.
    let deck: DeckList?
    let resolver: OnDeviceDeckResolver?
    let startIssues: DeckStudioStartIssues?
    /// Opens Deck Studio on this deck, showing only these cards.
    let openStudio: ([String]) -> Void
    @ObservedObject private var store = DeckStudioReceiptStore.shared
    @State private var issues: DeckStudioStartIssues?
    @State private var fixAfterDismiss: [String]?

    /// nil while the resolver loads or when it cannot read the deck.
    private var key: DeckStudioCheckKey? {
        guard let deck, let resolver else { return nil }
        return try? DeckStudioPlaySelection.key(deckID: deckID, deck: deck, resolver: resolver, appBuild: DeckStudioValidationService.appBuild)
    }
    private var commanders: [String] { deck.map { DeckStudioDraftPresentation.commanders(NativeDeckDraft(deck: $0)) } ?? [] }

    var body: some View {
        let key = key
        // A deck the resolver cannot read needs fixes, the same rule as Deck Studio's tiles.
        let status: DeckStudioPlayStatus = key.map { store.status(for: $0) } ?? (deck != nil && resolver != nil ? .needsFixes : .notChecked)
        VStack(spacing: 6) {
            if let deck {
                HStack(spacing: 6) {
                    Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(NativeDeckDraft(deck: deck))))
                        .font(.caption.monospacedDigit()).foregroundStyle(CommanderPresentation.secondary)
                    if let colors = DeckStudioDeckColors.colors(for: commanders) {
                        HStack(spacing: 2) {
                            if colors.isEmpty { ManaSymbolView(symbol: "C", size: 16) }
                            ForEach(colors, id: \.self) { ManaSymbolView(symbol: $0, size: 16) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Color identity: " + (colors.isEmpty ? "colorless" : colors.map { ["W": "white", "U": "blue", "B": "black", "R": "red", "G": "green"][$0] ?? $0 }.joined(separator: ", ")))
                    }
                }
                if status == .needsFixes {
                    Button { openStudio(fixCards(key: key, deck: deck)) } label: {
                        Label(status.setupLine, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(CommanderPresentation.accent)
                    .accessibilityIdentifier("ondevice.deckStatus.fix")
                }
                // Ready and not-checked decks show no line (Caleb, 2026-10-03): Start checks the deck anyway.
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: startIssues) { _, value in if let value { issues = value } }
        .sheet(item: $issues, onDismiss: {
            // Deck Studio opens only once this sheet has gone.
            if let cards = fixAfterDismiss { fixAfterDismiss = nil; openStudio(cards) }
        }) { presented in
            DeckStudioPlayIssues(title: DeckStudioPlayText.blocked(presented.check.issueCount), deckName: presented.name,
                                 message: nil, groups: presented.check.groups, cards: presented.check.cardNames,
                                 hidden: presented.check.issueCount - presented.check.issues.count,
                                 fix: { cards in fixAfterDismiss = cards; issues = nil }, notNow: { issues = nil })
                .background(GrimoirePaper().ignoresSafeArea())
                .foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
        }
    }

    /// The cards XMage named, or the rows the resolver cannot play.
    private func fixCards(key: DeckStudioCheckKey?, deck: DeckList) -> [String] {
        if let key, let check = store.check(for: key) { return check.cardNames }
        guard let resolver else { return [] }
        return DeckStudioPlaySelection.unplayableCards(deck, resolver: resolver)
    }
}
