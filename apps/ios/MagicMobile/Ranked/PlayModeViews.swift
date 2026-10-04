import SwiftUI

/// The leather title bar of a full-screen lobby page: back to where you came from, the title, and
/// an optional trailing control.
struct TavernScreenHeader<Trailing: View>: View {
    let title: String
    let backTitle: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button {
                GameAudio.shared.play(.uiBack)
                back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(BrandTheme.brassGradient)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backTitle)
            .accessibilityIdentifier("lobby.back")
            TavernPanelTitle(text: title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .modifier(TavernTitleBar())
    }
}

extension TavernScreenHeader where Trailing == EmptyView {
    init(title: String, backTitle: String, back: @escaping () -> Void) {
        self.init(title: title, backTitle: backTitle, back: back) { EmptyView() }
    }
}

/// A parchment card on the leather, in brass trim: the lobby's sections.
struct TavernParchmentCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                TavernFill(material: .parchment)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .overlay { TavernBrassFrame(scale: 1) }
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            .foregroundStyle(TavernPalette.ink)
    }
}

/// A leather card in brass trim, for controls that read in parchment-coloured text.
struct TavernLeatherCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                TavernFill(material: .leather)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .overlay { TavernBrassFrame(scale: 1) }
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            .foregroundStyle(TavernPalette.parchment)
    }
}

/// The scrolling page every lobby screen uses: header pinned on top, content centred and capped.
struct TavernLobbyPage<Content: View>: View {
    let title: String
    var backTitle = String(localized: "Main menu")
    let back: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            TavernScreenHeader(title: title, backTitle: backTitle, back: back)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(BrandBackdrop(cards: false).ignoresSafeArea())
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Mode chooser

/// Play: Quick Match, Ranked or a custom table.
struct PlayModeChooser: View {
    let rank: RankPosition
    let seasonName: String
    let quick: () -> Void
    let ranked: () -> Void
    let custom: () -> Void
    let back: () -> Void

    var body: some View {
        TavernLobbyPage(title: String(localized: "Play Commander"), back: back) {
            mode(title: String(localized: "Quick Match"),
                 detail: String(localized: "One AI opponent at your deck's bracket. Choose the bracket, deck and skill, or let the tavern pick."),
                 identifier: "play.quick", action: quick) {
                Image(systemName: "bolt.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            }
            mode(title: String(localized: "Ranked"),
                 detail: String(localized: "1v1 from Bronze to Mythic. Win to climb, lose and you slip. Season: \(seasonName)."),
                 identifier: "play.ranked", action: ranked) {
                RankBadge(position: rank, size: 52, showsPips: false)
            }
            mode(title: String(localized: "Custom Table"),
                 detail: String(localized: "Up to three AI opponents, Game Center, or an online table with friends on iPhone and Android."),
                 identifier: "play.custom", action: custom) {
                Image(systemName: "person.3.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            }
        }
    }

    private func mode<Icon: View>(title: String, detail: String, identifier: String, action: @escaping () -> Void,
                                  @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            GameAudio.shared.play(.uiOpen)
            action()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                icon()
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(TavernPalette.leather.opacity(0.9)).overlay(Circle().strokeBorder(TavernPalette.brassLine, lineWidth: 2)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 21, weight: .black, design: .serif))
                    Text(detail).font(.system(size: 14, weight: .medium, design: .serif)).opacity(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(DeckStudioPalette.accent)
            }
            .multilineTextAlignment(.leading)
            .modifier(TavernParchmentCard())
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Deck + bracket

/// The deck slot every play screen shares: commander art, name, bracket tag, and the picker.
struct PlayDeckSection: View {
    let deckName: String?
    let commander: String?
    let bracket: CommanderBracket?
    /// The bracket can be changed (the player's own decks); included decks have a fixed bracket.
    let canDeclare: Bool
    @Binding var deckID: String
    let sections: [TavernPicker<String>.Section]
    let editDecks: () -> Void
    let explainBracket: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CommanderDeckPortrait(name: commander, namespace: nil)
                    .frame(width: 84, height: 117)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "YOUR DECK")).font(.system(size: 10, weight: .heavy, design: .serif)).tracking(1.6)
                        .foregroundStyle(DeckStudioPalette.accent)
                    Text(deckName ?? String(localized: "Choose a deck"))
                        .font(.system(size: 19, weight: .black, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    if let commander { Text(commander).font(.system(size: 13, design: .serif)).italic().opacity(0.75) }
                    if let bracket {
                        Button(action: explainBracket) {
                            HStack(spacing: 6) {
                                BracketTag(bracket: bracket)
                                Image(systemName: canDeclare ? "slider.horizontal.3" : "info.circle")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(DeckStudioPalette.accent)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "\(bracket.title). Bracket details"))
                        .accessibilityIdentifier("play.deck.bracket")
                    }
                }
                Spacer(minLength: 0)
            }
            TavernPicker(title: String(localized: "Your deck"), selection: $deckID, sections: sections, identifier: "play.deck")
            Button(action: editDecks) { Label(String(localized: "Browse, import or edit decks"), systemImage: "rectangle.stack.badge.plus") }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
        }
        .modifier(TavernParchmentCard())
    }
}

/// Why a deck is in its bracket, and the player's own label for it.
struct DeckBracketSheet: View {
    let deckName: String
    let report: BracketReport
    /// nil for included decks, whose bracket is fixed.
    let declared: Binding<CommanderBracket?>?
    let fixedBracket: CommanderBracket?
    @Environment(\.dismiss) private var dismiss

    private var effective: CommanderBracket {
        fixedBracket ?? DeckBracketPreference.effective(minimum: report.minimum, declared: declared?.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TavernPanelTitle(text: String(localized: "Bracket"))
                Spacer(minLength: 8)
                Button { dismiss() } label: { TavernSealLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Done"))
                    .accessibilityIdentifier("bracket.close")
            }
            .modifier(TavernTitleBar())
            .padding(.horizontal, 16).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(deckName).font(.system(size: 20, weight: .black, design: .serif))
                        BracketTag(bracket: effective, leather: false)
                        Text(effective.blurb).font(.system(size: 14, design: .serif)).opacity(0.8)
                    }
                    .modifier(TavernParchmentCard())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "WHAT THE LIST SHOWS")).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                            .foregroundStyle(BrandTheme.brassGradient)
                        if report.reasons.isEmpty {
                            Text(String(localized: "No Game Changers, mass land denial, chained extra turns or two-card combos: Bracket 2 at most."))
                                .font(.system(size: 14, design: .serif))
                        } else {
                            ForEach(report.reasons, id: \.self) { line in
                                Label(line, systemImage: "diamond.fill").font(.system(size: 14, design: .serif))
                                    .labelStyle(BracketReasonLabelStyle())
                            }
                        }
                        Text(String(localized: "Lowest bracket for this list: \(report.minimum.title)."))
                            .font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.8)
                    }
                    .modifier(TavernLeatherCard())
                    if let declared {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "YOUR CALL")).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                                .foregroundStyle(BrandTheme.brassGradient)
                            Text(String(localized: "Brackets are also about intent. Raise the bracket if the deck plays stronger than its list shows. A Core list may be called Exhibition."))
                                .font(.system(size: 13, design: .serif)).opacity(0.8)
                            TavernPicker(title: String(localized: "Bracket"), selection: declared, sections: [
                                .init(options: [(String(localized: "Use the list (\(report.minimum.title))"), nil)]
                                      + DeckBracketPreference.choices(minimum: report.minimum)
                                        .filter { $0 != report.minimum }
                                        .map { ($0.title, Optional($0)) })
                            ], identifier: "bracket.declare")
                        }
                        .modifier(TavernLeatherCard())
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(TavernSheetBackground())
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
    }
}

private struct BracketReasonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 8)).foregroundStyle(TavernPalette.brass)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Quick Match

/// One AI, no rank change. Defaults: an AI deck at your deck's bracket, skill 3.
struct QuickMatchView<DeckSlot: View>: View {
    let deckBracket: CommanderBracket?
    @Binding var opponentBracket: Int
    @Binding var opponentDeckID: String
    @Binding var aiSkill: Int
    @Binding var startingPlayerMode: String
    let mayStart: Bool
    let status: String?
    let start: () -> Void
    let back: () -> Void
    @ViewBuilder var deckSlot: DeckSlot

    /// 0 means "match my deck".
    private var resolvedBracket: Int { opponentBracket == 0 ? min(4, deckBracket?.rawValue ?? 2) : opponentBracket }
    private var poolDecks: [AIDeck] { AIDeckPool.pool(for: resolvedBracket) }

    var body: some View {
        TavernLobbyPage(title: String(localized: "Quick Match"), back: back) {
            deckSlot
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "YOUR OPPONENT")).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                    .foregroundStyle(BrandTheme.brassGradient)
                TavernPicker(title: String(localized: "Opponent bracket"), selection: $opponentBracket, sections: [
                    .init(options: [(deckBracket.map { String(localized: "Match my deck (Bracket \(min(4, $0.rawValue)))") }
                                     ?? String(localized: "Match my deck"), 0)]),
                    .init(title: String(localized: "Choose"), options: CommanderBracket.allCases.filter { $0 != .cedh }.map { ($0.title, $0.rawValue) }),
                ], identifier: "quick.bracket")
                TavernPicker(title: String(localized: "Opponent deck"), selection: $opponentDeckID, sections: [
                    .init(options: [(String(localized: "Surprise me"), "")]),
                    .init(title: String(localized: "Bracket \(resolvedBracket) decks"), options: poolDecks.map { ("\($0.name) · \($0.commander)", $0.id) }),
                ], identifier: "quick.deck")
                TavernStepper(title: String(localized: "AI skill: \(aiSkill)"), value: $aiSkill, range: 1...10, identifier: "quick.skill")
                Text(String(localized: "3 is a fair fight. Higher skill thinks longer and may slow turns."))
                    .font(.system(size: 12, design: .serif)).opacity(0.7)
                TavernPicker(title: String(localized: "Who goes first?"), selection: $startingPlayerMode, sections: [
                    .init(options: [(String(localized: "Choose at the table"), "choose"), (String(localized: "Roll a D20"), "roll")])
                ], identifier: "quick.startingPlayer")
            }
            .modifier(TavernLeatherCard())
            .onChange(of: resolvedBracket) { _, _ in
                if !opponentDeckID.isEmpty, !poolDecks.contains(where: { $0.id == opponentDeckID }) { opponentDeckID = "" }
            }
            if let status { Text(status).font(.system(size: 13, design: .serif)).foregroundStyle(TavernPalette.parchment.opacity(0.8)) }
            Button {
                GameAudio.shared.play(.menuPlay)
                start()
            } label: { Label(String(localized: "Start Quick Match"), systemImage: "flame.fill").frame(maxWidth: .infinity) }
                .buttonStyle(TavernButtonStyle(kind: .primary, fontSize: 17, fullWidth: true))
                .disabled(!mayStart)
                .accessibilityIdentifier("quick.start")
        }
    }
}

// MARK: - Ranked

struct RankedLobbyView<DeckSlot: View>: View {
    let rank: RankState
    let deckBracket: CommanderBracket?
    let canSearchPeople: Bool
    let mayStart: Bool
    let status: String?
    let find: () -> Void
    let profile: () -> Void
    let back: () -> Void
    @ViewBuilder var deckSlot: DeckSlot

    @State private var appeared = Date()
    private var tier: RankTier { rank.position.tier }
    private var eligible: Bool { (deckBracket?.rawValue ?? 99) <= tier.maxDeckBracket }

    var body: some View {
        TavernLobbyPage(title: String(localized: "Ranked"), back: back) {
            VStack(spacing: 10) {
                RankBadge(position: rank.position, size: 132, showsPips: true, showsTitle: true,
                          spin: .init(start: appeared, turns: 1, duration: 1.2))
                    .padding(.top, 4)
                Text(String(localized: "Season: \(RankLadder.seasonName(rank.season))") + daysLeft)
                    .font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.8)
                HStack(spacing: 18) {
                    stat(String(localized: "Wins"), "\(rank.wins)")
                    stat(String(localized: "Losses"), "\(rank.losses)")
                    stat(String(localized: "Peak"), rank.peak.title)
                }
                Button(action: profile) { Label(String(localized: "Your profile"), systemImage: "person.crop.circle") }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("ranked.profile")
            }
            .frame(maxWidth: .infinity)
            .modifier(TavernLeatherCard())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ranked.standing")

            deckSlot

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "AT \(tier.name.uppercased())")).font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1.4)
                    .foregroundStyle(BrandTheme.brassGradient)
                rule("person.2.fill", String(localized: "Opponents play Bracket \(bracketText(tier.opponentBrackets)) decks. AI opponents play at skill \(tier.aiSkill)."))
                rule("checkmark.seal.fill", String(localized: "Your deck may be up to Bracket \(tier.maxDeckBracket). A lower bracket earns +1 pip for each win."))
                rule("arrow.up.arrow.down", String(localized: "Each win fills a pip and each loss empties one. Four pips win a division; with none left a loss drops you a division."))
                if tier < .gold { rule("flame.fill", String(localized: "Three wins in a row below Gold earn an extra pip.")) }
                rule(canSearchPeople ? "antenna.radiowaves.left.and.right" : "cpu",
                     canSearchPeople ? String(localized: "We look for a player near your rank first. If nobody's searching, an AI takes the seat.")
                                     : String(localized: "Profiles are offline, so an AI takes the seat. AI games count the same."))
            }
            .modifier(TavernLeatherCard())

            if !eligible, let deckBracket {
                Label(String(localized: "\(deckBracket.title) is above \(tier.name)'s limit (Bracket \(tier.maxDeckBracket)). Choose another deck."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.5))
                    .accessibilityIdentifier("ranked.ineligible")
            }
            if let status { Text(status).font(.system(size: 13, design: .serif)).foregroundStyle(TavernPalette.parchment.opacity(0.8)) }
            Button {
                GameAudio.shared.play(.menuPlay)
                find()
            } label: { Label(String(localized: "Find Ranked Match"), systemImage: "shield.lefthalf.filled").frame(maxWidth: .infinity) }
                .buttonStyle(TavernButtonStyle(kind: .primary, fontSize: 17, fullWidth: true))
                .disabled(!mayStart || !eligible)
                .accessibilityIdentifier("ranked.find")
        }
    }

    private var daysLeft: String {
        guard let end = RankLadder.seasonEnd(rank.season) else { return "" }
        let days = max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        return days == 1 ? String(localized: " · 1 day left") : String(localized: " · \(days) days left")
    }

    private func bracketText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .black, design: .serif)).monospacedDigit()
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1.2).opacity(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(TavernPalette.brass).frame(width: 20)
            Text(text).font(.system(size: 14, design: .serif)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Searching the ranked queue: a turning hourglass, the time, and what happens next.
struct RankedSearchOverlay: View {
    let phase: RankedMatchmaker.Phase
    let rank: RankPosition
    let playAI: () -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                RankSpinEmblem(tier: rank.tier, size: 110, duration: 2.4, forever: true)
                switch phase {
                case .matched(let ticket):
                    Text(String(localized: "Challenger found")).font(.system(size: 22, weight: .black, design: .serif))
                    Text(ticket.opponent ?? String(localized: "Another player"))
                        .font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(TavernPalette.brass)
                    Text(String(localized: "Setting the table…")).font(.system(size: 14, design: .serif)).opacity(0.8)
                default:
                    Text(String(localized: "Looking for a challenger")).font(.system(size: 22, weight: .black, design: .serif))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let since: Date = { if case .searching(let start) = phase { return start }; return context.date }()
                        let elapsed = max(0, Int(context.date.timeIntervalSince(since)))
                        let left = max(0, Int(RankedMatchmaker.searchSeconds) - elapsed)
                        VStack(spacing: 4) {
                            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                                .font(.system(size: 30, weight: .black, design: .serif)).monospacedDigit()
                            Text(String(localized: "An AI takes the seat in \(left) s if nobody's searching."))
                                .font(.system(size: 13, design: .serif)).opacity(0.8)
                        }
                    }
                    HStack(spacing: 12) {
                        Button(String(localized: "Cancel"), action: cancel)
                            .buttonStyle(TavernButtonStyle(kind: .secondary))
                            .accessibilityIdentifier("ranked.search.cancel")
                        Button(String(localized: "Play the AI now"), action: playAI)
                            .buttonStyle(TavernButtonStyle(kind: .primary))
                            .accessibilityIdentifier("ranked.search.ai")
                    }
                }
            }
            .foregroundStyle(TavernPalette.parchment)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: 420)
            .modifier(TavernPanelChrome(tavern: true, cornerRadius: 16))
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ranked.search")
    }
}
