import SwiftUI

/// The leather title bar of a full-screen lobby page: back to where you came from, the title, and
/// an optional trailing control.
struct TavernScreenHeader<Trailing: View>: View {
    let title: String
    let backTitle: String
    let back: () -> Void
    /// False on a page the top bar's tabs reach (Profile, Ranked Hall): Arena shows no back chevron there (Caleb,
    /// 2026-10-22). The Tavern header always keeps it, since it has no top bar to leave by.
    var showsBack = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.arenaBoard) private var arena

    var body: some View {
        if arena { arenaHeader } else { tavernHeader }
    }

    /// Arena's page title: a back chevron (where the page has somewhere to go back to) and the title in large type on the
    /// page itself, no bar.
    private var arenaHeader: some View {
        HStack(spacing: 4) {
            if showsBack {
                Button {
                    GameAudio.shared.play(.uiBack)
                    back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(ArenaMenuStyle.text)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backTitle)
                .accessibilityIdentifier("lobby.back")
            }
            Text(title)
                .font(ArenaMenuStyle.font(24, .bold))
                .foregroundStyle(ArenaMenuStyle.text)
                .shadow(color: .black, radius: 2)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 48)
    }

    private var tavernHeader: some View {
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
    init(title: String, backTitle: String, back: @escaping () -> Void, showsBack: Bool = true) {
        self.init(title: title, backTitle: backTitle, back: back, showsBack: showsBack) { EmptyView() }
    }
}

/// A parchment card on the leather, in brass trim: the lobby's sections. Glass in the Arena menus.
struct TavernParchmentCard: ViewModifier {
    @Environment(\.arenaBoard) private var arena

    func body(content: Content) -> some View {
        if arena { content.arenaCard(padding: 16) } else { parchment(content) }
    }

    private func parchment(_ content: Content) -> some View {
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

/// A leather card in brass trim, for controls that read in parchment-coloured text. Glass in the Arena menus.
struct TavernLeatherCard: ViewModifier {
    @Environment(\.arenaBoard) private var arena

    func body(content: Content) -> some View {
        if arena { content.arenaCard(padding: 16) } else { leather(content) }
    }

    private func leather(_ content: Content) -> some View {
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
    /// False on a page a top-bar tab reaches; ignored outside the Arena menus, which have no top bar.
    var showsBack = true
    /// A wider cap for a page laid out in columns when held sideways.
    var contentWidth: CGFloat? = nil
    /// False: the content fills the page below the title and scrolls in its own columns.
    var scrolls = true
    @ViewBuilder var content: Content
    @Environment(\.arenaBoard) private var arena
    @Environment(\.arenaMenuBackdrop) private var shellBackdrop

    var body: some View {
        VStack(spacing: 0) {
            // An empty title: the page heads itself (the profile's name is its headline, as Arena's is).
            if !title.isEmpty || (showsBack || !arena) {
                TavernScreenHeader(title: title, backTitle: backTitle, back: back, showsBack: showsBack || !arena)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if scrolls {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { content }
                        .padding(16)
                        .padding(.bottom, arena ? 20 : 0)
                        .frame(maxWidth: contentWidth ?? (arena ? 760 : 640))
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Rows running on past the screen's foot fade out rather than being cut (the judge, 2026-10-22).
                .mask { if arena { ArenaScrollFade() } else { Color.black } }
                .accessibilityIdentifier("lobby.scroll")
            } else {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: contentWidth ?? (arena ? 760 : 640), maxHeight: .infinity, alignment: .top)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(arena ? ArenaMenuStyle.text : TavernPalette.parchment)
        .background {
            if !arena {
                BrandBackdrop(cards: false).ignoresSafeArea()
            } else if !shellBackdrop {
                // The menu shell draws the room once; a page on its own (a sheet) brings its own.
                ArenaRoomBackdrop(dim: 0.6)
            }
        }
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
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
    @Environment(\.arenaPanelClose) private var panelClose
    /// Closes the Arena menu panel this page is shown in, or the sheet elsewhere.
    private func closePanel() { if let panelClose { panelClose() } else { dismiss() } }

    private var effective: CommanderBracket {
        fixedBracket ?? DeckBracketPreference.effective(minimum: report.minimum, declared: declared?.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TavernPanelTitle(text: String(localized: "Bracket"))
                Spacer(minLength: 8)
                Button { closePanel() } label: { TavernSealLabel() }
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
