import SwiftUI
import UIKit

/// Deck Studio's parts. They were a collector's binder (oxblood leather, parchment pages, brass corners, 2026-10-06);
/// since the Arena menus (Caleb, 2026-10-22: Deck Studio follows Arena, nothing carried over) the same parts draw
/// Arena's deck builder: dark glass panels in the gold hairline over the darkened tavern room, glass tabs, Arena's
/// pills and plaques, and cards without sleeves. The names stay, so every screen keeps its layout and its
/// accessibility and UI-test contract. Android: studio/GrimoireBinder.kt (still the binder).
enum Binder {
    static let oxblood = Color(red: 0.40, green: 0.09, blue: 0.07)
    static let leatherDark = Color(red: 0.17, green: 0.07, blue: 0.045)
    static let thread = Color(red: 0.90, green: 0.70, blue: 0.40).opacity(0.55)
    static let brassLight = Color(red: 1.0, green: 0.88, blue: 0.58)
    static let brassDeep = Color(red: 0.50, green: 0.32, blue: 0.11)
    static let engraved = Color(red: 0.24, green: 0.13, blue: 0.05)
    /// How wide the index tabs stand out from the page (the chosen one stands further out).
    static let tabWidth: CGFloat = 50

    static let brass = LinearGradient(colors: [brassLight, TavernPalette.brass, brassDeep], startPoint: .top, endPoint: .bottom)
    static let brassPressed = LinearGradient(colors: [brassDeep, TavernPalette.brass, brassLight.opacity(0.8)], startPoint: .top, endPoint: .bottom)

    /// A colour multiplied into the leather under it (oxblood for the cover, darker for the tucked tabs).
    static func dye(_ color: Color, _ amount: Double) -> some View {
        Rectangle().fill(color.opacity(amount)).blendMode(.multiply)
    }
}

// MARK: - The binder itself

/// Under the whole screen: the tavern room, darkened as behind Arena's deck builder (the menu shell's own room when
/// Deck Studio is its Decks tab).
struct BinderCover: View {
    @Environment(\.arenaMenuBackdrop) private var shell

    var body: some View {
        if shell { Color.clear } else { ArenaRoomBackdrop(dim: 0.45) }
    }
}

/// A page of Deck Studio: a dark glass panel in the gold hairline. Its content keeps its own layout; the page only
/// frames and clips it. (`gutter` was the binder's spine shadow; Arena's panels have none.)
struct BinderPage<Content: View>: View {
    var gutter: Edge? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GrimoirePaper())
            .clipShape(shape)
            .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .padding(4)
    }
}

private struct BinderScreenKey: EnvironmentKey { static let defaultValue: UUID? = nil }
extension EnvironmentValues {
    /// Which binder screen a page belongs to, so a turn knows which pages are on top.
    var binderScreen: UUID? {
        get { self[BinderScreenKey.self] }
        set { self[BinderScreenKey.self] = newValue }
    }
}

private struct BinderScreenModifier: ViewModifier {
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content.environment(\.binderScreen, id)
            .binderControls()
            .binderOverlayHost()
            .scrollContentBackground(.hidden)
            .background { BinderCover().ignoresSafeArea() }
            .foregroundStyle(ArenaMenuStyle.text)
            .environment(\.arenaBoard, true)
            .preferredColorScheme(.dark)
    }
}

/// A panel set into the page (the deck's title plate): a lighter pane of glass in the gold hairline.
struct BinderPlate: ViewModifier {
    var corners: BinderCorners.Style = .leaf
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background(GrimoirePaper(tone: .plate))
            .clipShape(shape)
            .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.8).allowsHitTesting(false))
    }
}

extension View {
    func binderPlate(corners: BinderCorners.Style = .leaf) -> some View { modifier(BinderPlate(corners: corners)) }

    /// A Deck Studio screen: the darkened room under everything, serif type, light text, and lists that show the
    /// glass they sit on rather than the system's grey.
    func binderScreen() -> some View { modifier(BinderScreenModifier()) }
}

/// Brass mounts over the four corners of a page, a plate or a sleeve: Meshy-made art
/// (scripts/brand/binder_parts.py) mirrored for each corner, or drawn plates with a rivet while that art is
/// missing.
struct BinderCorners: View {
    /// Pages wear ornate L-shaped guards, cards a finer L, and the plates set into a page (the deck's title,
    /// a deck in the library) gilded acanthus leaves (Caleb, 2026-10-06: "we want an L shape corner", "for
    /// card ones it should be better ones", and his acanthus corner as inspiration).
    enum Style { case guardian, card, leaf, book }
    var size: CGFloat = 20
    var style: Style = .guardian
    private static let guardian = UIImage(named: "tavern-binder-corner")
    private static let card = UIImage(named: "tavern-binder-card-corner")
    private static let leaf = UIImage(named: "tavern-binder-leaf-corner")
    private static let book = UIImage(named: "tavern-binder-book-corner")

    /// Arena's panels have plain corners: nothing is drawn (the style stays for callers).
    var body: some View { EmptyView() }
}

/// The deck's chapters (Cards, Ideas, Analysis) down the page's edge as Arena tabs: an emblem over the name, the
/// chosen one lit with an ember bar.
struct BinderIndexTabs: View {
    let chapters: [String]
    let selected: String
    /// Shorter on a sideways spread, where the page is not as tall.
    var tabHeight: CGFloat = 102
    let choose: (String) -> Void

    static let icons = ["Cards": "rectangle.portrait.on.rectangle.portrait.fill", "Ideas": "lightbulb.fill",
                        "Analysis": "chart.bar.fill"]
    /// How far each tab used to run in under the page; kept for the layouts that leave room for it.
    static let tuck: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chapters, id: \.self) { chapter in
                let chosen = chapter == selected
                Button { choose(chapter) } label: {
                    VStack(spacing: 5) {
                        ArenaEmblem(symbol: Self.icons[chapter] ?? "book.closed.fill", size: 15, lit: chosen)
                        Text(chapter).font(ArenaMenuStyle.font(9.5, .semibold))
                            .foregroundStyle(chosen ? Color.white : ArenaMenuStyle.dim)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 3)
                    }
                    .frame(width: Binder.tabWidth, height: min(tabHeight, 64))
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(chosen ? Color.white.opacity(0.08) : Color.black.opacity(0.35))
                    }
                    .overlay(alignment: .leading) {
                        if chosen {
                            Capsule().fill(ArenaMenuStyle.ember).frame(width: 3).padding(.vertical, 8)
                                .shadow(color: ArenaMenuStyle.ember, radius: 5)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(chosen ? 0.8 : 0.35))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chapter)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .frame(width: Binder.tabWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deck workspace")
    }
}

// MARK: - The binder's controls

/// "Done" and "Cancel": Arena's dark glass pill.
struct BinderStrapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ArenaButtonFace(label: configuration.label, kind: .secondary, font: ArenaMenuStyle.title(15, .semibold),
                        pressed: configuration.isPressed, fills: false, inset: 9)
            .frame(minHeight: 44)
    }
}

/// The binder's head on the leather above its page: a strap (Done or Cancel) at the leading edge, the
/// page's name stamped in the middle, and the page's plaques at the trailing edge.
struct BinderHead<Trailing: View>: View {
    let strap: String
    let strapIdentifier: String
    var title: String? = nil
    var strapDisabled = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button(strap, action: action)
                .buttonStyle(BinderStrapButtonStyle()).disabled(strapDisabled)
                .accessibilityIdentifier(strapIdentifier)
            Spacer(minLength: 2)
            if let title {
                Text(title).font(ArenaMenuStyle.font(20, .bold))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
            }
            trailing
        }
        // Written at the top of the page (Caleb, 2026-10-06: the head is part of the paper, so facing pages
        // are the same height and turn together).
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
    }
}

/// A pill (Save, Sort, the rail's tools): Arena's dark glass pill, as its filter pills; `square` is a round glass button
/// with a gold symbol. `on` lights it orange.
struct BinderPlaque<Label: View>: View {
    var square = false
    var on = false
    var pressed = false
    @ViewBuilder var label: Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if square {
                label
                    .font(.system(size: 15, weight: .bold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(on ? Color.white : ArenaMenuStyle.gold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.6, blue: 0.3), Color(red: 0.75, green: 0.25, blue: 0.08)],
                                                                                startPoint: .top, endPoint: .bottom))
                                                 : AnyShapeStyle(Color.black.opacity(0.5))))
                    .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            } else {
                // Arena's dark glass pill, orange when lit.
                ArenaButtonFace(label: label.labelStyle(.titleAndIcon), kind: on ? .primary : .secondary,
                                font: ArenaMenuStyle.font(14, .semibold), pressed: pressed, fills: false, inset: 7, glow: 0.4)
            }
        }
        .shadow(color: .black.opacity(pressed ? 0.15 : 0.45), radius: pressed ? 1 : 2.5, y: pressed ? 0 : 2)
        .brightness(pressed ? 0.06 : 0)
        .saturation(isEnabled ? 1 : 0.2)
        .opacity(isEnabled ? 1 : 0.55)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct BinderPlaqueButtonStyle: ButtonStyle {
    var square = false
    var on = false

    func makeBody(configuration: Configuration) -> some View {
        BinderPlaque(square: square, on: on, pressed: configuration.isPressed) { configuration.label }
    }
}

/// The tool bar: a strip of darker glass in the gold hairline.
struct BinderRail<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(Color.black.opacity(0.42))
                    .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
            }
    }
}

/// The rail's search field: a dark inset well with a brass magnifying glass.
struct BinderSearchField: View {
    let placeholder: String
    @Binding var text: String
    var identifier: String
    var clearLabel = "Clear search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .bold)).foregroundStyle(ArenaMenuStyle.dim)
                .frame(width: 24, height: 24).accessibilityHidden(true)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(ArenaMenuStyle.dim))
                .font(ArenaMenuStyle.font(15, .regular))
                .foregroundStyle(ArenaMenuStyle.text)
                .tint(ArenaMenuStyle.gold)
                .autocorrectionDisabled()
                .focused(focus)
                .submitLabel(.search)
                .onSubmit { focus.wrappedValue = false }
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(ArenaMenuStyle.dim).frame(width: 32, height: 40)
                }.buttonStyle(.plain).accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 10).frame(height: 38)
        // The whole field is the place to write, not only the line of text in it.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1).opacity(0.7))
    }
}

/// Which cards the binder's pages show: the deck's own, or every card there is to add.
enum BinderShelf: String { case deck, all }

/// The two shelves as a brass switch on the rail.
struct BinderShelfSwitch: View {
    @Binding var shelf: BinderShelf
    /// Symbols only, for a short sideways page (the titles stay for VoiceOver).
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            option(.deck, title: "My deck", icon: "rectangle.stack.fill")
            option(.all, title: "All cards", icon: "books.vertical.fill")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show cards")
    }

    private func option(_ value: BinderShelf, title: String, icon: String) -> some View {
        let chosen = shelf == value
        return Button { shelf = value } label: {
            Label(title, systemImage: icon)
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .font(ArenaMenuStyle.font(14, .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(chosen ? Color(red: 0.11, green: 0.06, blue: 0.03) : ArenaMenuStyle.dim)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 34 : 36)
                .frame(width: compact ? 42 : nil)
                .background {
                    if chosen { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ArenaMenuStyle.goldFill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// A label style chosen at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Mana values 0 to 7+ as brass coins: tap one or more to see only those costs; none shows all.
struct BinderManaFilter: View {
    @Binding var selection: Set<Int>
    static let values = Array(0...7)

    var body: some View {
        // Each value keeps its own outline: never touching its neighbour (the judge, 2026-10-22).
        HStack(spacing: 4) {
            ForEach(Self.values, id: \.self) { value in
                let on = selection.contains(value)
                Button { if on { selection.remove(value) } else { selection.insert(value) } } label: {
                    // Arena's mana value filter: a number in a glass circle, gold when chosen.
                    Text(value == 7 ? "7+" : "\(value)")
                        .font(ArenaMenuStyle.font(value == 7 ? 12 : 14, .heavy)).monospacedDigit()
                        .foregroundStyle(on ? Color(red: 0.11, green: 0.06, blue: 0.03) : ArenaMenuStyle.text)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(on ? AnyShapeStyle(ArenaMenuStyle.goldFill) : AnyShapeStyle(Color.black.opacity(0.5))))
                        .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(on ? 0 : 0.7))
                        .shadow(color: on ? ArenaMenuStyle.gold.opacity(0.6) : .clear, radius: 5)
                        .opacity(on || selection.isEmpty ? 1 : 0.6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == 7 ? "Mana value 7 or more" : "Mana value \(value)")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mana value filter")
    }

    /// Whether a card of this mana value passes the filter.
    nonisolated static func matches(_ manaValue: Double?, _ selection: Set<Int>) -> Bool {
        guard !selection.isEmpty else { return true }
        guard let manaValue, manaValue.isFinite else { return false }
        return selection.contains(min(7, Int(manaValue.rounded(.down))))
    }
}

/// The deck's size as a brass gauge: a segmented ember bar in brass, with the count.
struct BinderGauge: View {
    let count: Int
    var target = 100
    /// The count beside the gauge (off where the count is written elsewhere).
    var showsCount = true

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                let fraction = min(1, CGFloat(count) / CGFloat(max(1, target)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.7, blue: 0.36), ArenaMenuStyle.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * fraction))
                        .shadow(color: ArenaMenuStyle.ember.opacity(0.6), radius: 3)
                }
            }
            .frame(height: 5)
            if showsCount {
                Text("\(count)/\(target)").font(ArenaMenuStyle.font(13, .heavy)).monospacedDigit()
                    .foregroundStyle(ArenaMenuStyle.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(target) cards")
    }
}

// MARK: - Sleeves

/// A card in its sleeve: the card's art in a translucent pocket held by brass corner mounts, and under it
/// a strip with a brass minus, the count and a brass plus. The strip's buttons are what VoiceOver and the
/// UI tests press; tapping the card's own right or left half does the same. A card that cannot be
/// changed here (a read-only deck, or while selecting) is one button, `tapLabel`.
struct BinderSleeve: View {
    let name: String
    let quantity: Int
    let card: NativeDeckMetadataCatalogue.Card?
    var notes: [String] = []
    /// Non-nil while selecting cards: whether this one is selected.
    var selected: Bool? = nil
    var canEdit = true
    var addLabel: String? = nil
    var removeLabel: String? = nil
    var tapLabel: String? = nil
    /// The art this row chose; the catalogue shelf leaves it to the player's choice for the name.
    var art: CardArtSelection = .active
    let add: () -> Void
    let remove: () -> Void
    let tap: () -> Void
    @Environment(\.binderOverlayHost) private var host

    private var editing: Bool { canEdit && selected == nil }
    /// A long press that opens the card's menu must not also add or take away a copy.
    private func guarded(_ action: @escaping () -> Void) -> () -> Void { { if host?.tapAllowed ?? true { action() } } }

    var body: some View {
        VStack(spacing: 5) {
            // The card itself, as in Arena's collection (no sleeve).
            DeckStudioCardImageTile(name: name, card: card, art: art)
                .overlay(alignment: .topLeading) {
                    if let selected {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(selected ? DeckStudioPalette.accent : DeckStudioPalette.surfaceElevated)
                            .background(Circle().fill(selected ? DeckStudioPalette.surfaceElevated : DeckStudioPalette.ink.opacity(0.35)))
                            .padding(7).accessibilityHidden(true)
                    } else if !notes.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DeckStudioPalette.surfaceElevated)
                            .frame(width: 22, height: 22)
                            .background(DeckStudioPalette.warning.opacity(0.92), in: Circle())
                            .padding(7)
                            .accessibilityLabel("Quick check: " + notes.joined(separator: ", "))
                    }
                }
                .overlay {
                    if selected == true {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(DeckStudioPalette.accent, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if editing {
                        // The card's halves: left takes a copy away, right adds one. The strip's buttons
                        // say the same to VoiceOver, so these stay out of its way.
                        HStack(spacing: 0) {
                            Button(action: guarded { if quantity > 0 { remove() } }) { Color.clear.contentShape(Rectangle()) }
                            Button(action: guarded(add)) { Color.clear.contentShape(Rectangle()) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    } else {
                        Button(action: guarded(tap)) { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tapLabel ?? name)
                            .accessibilityAddTraits(selected == true ? [.isSelected] : [])
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 4, y: 3)
            strip
        }
        .sensoryFeedback(.selection, trigger: quantity)
    }

    private var strip: some View {
        HStack(spacing: 2) {
            if editing {
                // Nothing to take away from a card the deck does not hold yet: the minus keeps its place
                // but is not there.
                if quantity > 0 { coinButton("minus", label: removeLabel ?? "Remove one \(name)") { remove() } }
                else { Color.clear.frame(width: 36, height: 34).accessibilityHidden(true) }
            }
            Text("\(quantity)")
                .font(ArenaMenuStyle.font(14, .heavy)).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(ArenaMenuStyle.text)
                .frame(minWidth: 28, minHeight: 22)
                .background(Capsule().fill(.black.opacity(0.62)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                .accessibilityLabel("\(name), quantity \(quantity)")
            if editing {
                coinButton("plus", label: addLabel ?? "Add one \(name)") { add() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func coinButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .black)).foregroundStyle(ArenaMenuStyle.text)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
