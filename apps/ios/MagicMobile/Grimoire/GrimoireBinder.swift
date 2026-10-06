import SwiftUI
import UIKit

/// Deck Studio as a collector's binder (Caleb chose concept B of three, 2026-10-06): an oxblood
/// leather binder with brass corners holds the parchment pages; the deck's chapters are leather index
/// tabs on its outer edge; Done is a leather strap with a buckle, Save a brass plaque; the tools sit
/// on a brass rail; every card is in a sleeve with brass corner mounts and a minus, count and plus
/// strip beneath it. Everything is drawn from the tavern kit (leather, parchment, the brass rims and
/// coins) and brass gradients, plus three brass parts Caleb asked to be made with Meshy (the buckle, the
/// corner mounts and Play's ember jewel, scripts/brand/binder_parts.py). Android: studio/GrimoireBinder.kt.
enum Binder {
    static let oxblood = Color(red: 0.40, green: 0.09, blue: 0.07)
    static let leatherDark = Color(red: 0.17, green: 0.07, blue: 0.045)
    static let thread = Color(red: 0.90, green: 0.70, blue: 0.40).opacity(0.55)
    static let brassLight = Color(red: 1.0, green: 0.88, blue: 0.58)
    static let brassDeep = Color(red: 0.50, green: 0.32, blue: 0.11)
    static let engraved = Color(red: 0.24, green: 0.13, blue: 0.05)
    /// How wide the index tabs stand out from the page (the chosen one stands further out).
    static let tabWidth: CGFloat = 40

    static let brass = LinearGradient(colors: [brassLight, TavernPalette.brass, brassDeep], startPoint: .top, endPoint: .bottom)
    static let brassPressed = LinearGradient(colors: [brassDeep, TavernPalette.brass, brassLight.opacity(0.8)], startPoint: .top, endPoint: .bottom)

    /// A colour multiplied into the leather under it (oxblood for the cover, darker for the tucked tabs).
    static func dye(_ color: Color, _ amount: Double) -> some View {
        Rectangle().fill(color.opacity(amount)).blendMode(.multiply)
    }
}

// MARK: - The binder itself

/// The binder's oxblood leather, under the whole screen.
struct BinderCover: View {
    var body: some View {
        TavernFill(material: .leather)
            .overlay(Binder.dye(Binder.oxblood, 0.55))
            .overlay(RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 120, endRadius: 700))
            .accessibilityHidden(true)
    }
}

/// A page held in the binder: parchment with a dark edge, a stitched seam around it in the leather and
/// brass corner plates. Its content keeps its own layout; the page only frames and clips it. `gutter`
/// shades the edge that runs into the binder's spine.
struct BinderPage<Content: View>: View {
    var gutter: Edge? = nil
    @ViewBuilder var content: Content
    @Environment(\.binderScreen) private var screen
    @State private var id = UUID()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GrimoirePaper())
            .overlay { if let gutter { BinderGutter(edge: gutter).allowsHitTesting(false) } }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.black.opacity(0.45), lineWidth: 1).allowsHitTesting(false))
            .overlay { BinderCorners(size: 30).allowsHitTesting(false) }
            .padding(5)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Binder.thread, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).allowsHitTesting(false))
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.18)).shadow(color: .black.opacity(0.5), radius: 5, y: 2))
            // A page turn moves only this paper; the binder around it stays still (GrimoireStage).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if let screen { GrimoireStage.shared.setBinderPage(frame, page: id, screen: screen) }
            }
            .onDisappear { if let screen { GrimoireStage.shared.removeBinderPage(id, screen: screen) } }
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
            .scrollContentBackground(.hidden)
            .background { BinderCover().ignoresSafeArea() }
            .fontDesign(.serif)
    }
}

/// The shadow where a page runs into the binder's spine.
private struct BinderGutter: View {
    let edge: Edge

    var body: some View {
        let ink = DeckStudioPalette.ink
        let leading = edge == .leading
        LinearGradient(stops: [.init(color: ink.opacity(0.28), location: 0), .init(color: ink.opacity(0.08), location: 0.4), .init(color: .clear, location: 1)],
                       startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading)
            .frame(width: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .trailing)
            .accessibilityHidden(true)
    }
}

/// A panel set into the page (the deck's title plate): lighter paper in a thin brass edge with small
/// brass corners.
struct BinderPlate: ViewModifier {
    var corners: BinderCorners.Style = .leaf
    func body(content: Content) -> some View {
        content
            .background(GrimoirePaper(tone: .plate))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Binder.brass, lineWidth: 1.5).allowsHitTesting(false))
            .overlay { BinderCorners(size: 20, style: corners).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

extension View {
    func binderPlate(corners: BinderCorners.Style = .leaf) -> some View { modifier(BinderPlate(corners: corners)) }

    /// A Deck Studio screen as the binder: oxblood leather under everything, serif type, and lists that
    /// show the page they sit on rather than the system's grey.
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

    var body: some View {
        if let art = Self.art(style) {
            let side = size * 1.35
            ZStack {
                Image(uiImage: art).resizable().interpolation(.high).frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Image(uiImage: art).resizable().interpolation(.high).frame(width: side, height: side).scaleEffect(x: -1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Image(uiImage: art).resizable().interpolation(.high).frame(width: side, height: side).scaleEffect(x: 1, y: -1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Image(uiImage: art).resizable().interpolation(.high).frame(width: side, height: side).scaleEffect(x: -1, y: -1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .accessibilityHidden(true)
        } else {
            drawn
        }
    }

    private static func art(_ style: Style) -> UIImage? {
        switch style {
        case .guardian: return guardian
        case .card: return card
        case .leaf: return leaf ?? guardian
        case .book: return book ?? guardian
        }
    }

    private var drawn: some View {
        Canvas { context, canvas in
            for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                let cx = x * canvas.width, cy = y * canvas.height
                let dx: CGFloat = x == 0 ? 1 : -1, dy: CGFloat = y == 0 ? 1 : -1
                var plate = Path()
                plate.move(to: CGPoint(x: cx, y: cy))
                plate.addLine(to: CGPoint(x: cx + dx * size, y: cy))
                plate.addQuadCurve(to: CGPoint(x: cx, y: cy + dy * size), control: CGPoint(x: cx + dx * size * 0.32, y: cy + dy * size * 0.32))
                plate.closeSubpath()
                context.fill(plate, with: .linearGradient(Gradient(colors: [Binder.brassLight, TavernPalette.brass, Binder.brassDeep]),
                                                          startPoint: CGPoint(x: cx, y: cy), endPoint: CGPoint(x: cx + dx * size * 0.6, y: cy + dy * size * 0.6)))
                context.stroke(plate, with: .color(Binder.brassDeep.opacity(0.9)), lineWidth: 0.8)
                let rivet = CGRect(x: cx + dx * size * 0.24 - 1.8, y: cy + dy * size * 0.24 - 1.8, width: 3.6, height: 3.6)
                context.fill(Path(ellipseIn: rivet), with: .color(Binder.brassLight))
                context.stroke(Path(ellipseIn: rivet), with: .color(Binder.brassDeep), lineWidth: 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The deck's chapters as leather index tabs standing out of the binder's outer edge. The chosen tab is
/// red leather and stands further out; the others are dark and tucked in.
struct BinderIndexTabs: View {
    let chapters: [String]
    let selected: String
    /// Shorter on a sideways spread, where the page is not as tall.
    var tabHeight: CGFloat = 102
    let choose: (String) -> Void

    static let icons = ["Cards": "rectangle.portrait.on.rectangle.portrait.fill", "Ideas": "lightbulb.fill",
                        "Analysis": "chart.bar.fill", "Playtest": "flag.2.crossed.fill"]
    /// How far each tab runs in under the page's edge: the page lies over it and shades it, so the tabs
    /// stand out of the binder rather than beside it. Put the page above the tabs (zIndex).
    static let tuck: CGFloat = 12
    /// The stitched leather tab with its brass rivet (Meshy image-to-3D, scripts/brand/binder_parts.py),
    /// 40 by 115 points. Its top cap keeps the rounded corner and the rivet whole; only plain leather
    /// between the rivet and the bottom corner stretches or shrinks to the tab's height.
    private static let art = UIImage(named: "tavern-binder-tab")
    private static let artInsets = EdgeInsets(top: 62, leading: 12, bottom: 14, trailing: 14)

    var body: some View {
        VStack(alignment: .leading, spacing: tabHeight < 100 ? 4 : 6) {
            ForEach(chapters, id: \.self) { chapter in
                let chosen = chapter == selected
                Button { choose(chapter) } label: {
                    VStack(spacing: tabHeight < 100 ? 5 : 8) {
                        Image(systemName: Self.icons[chapter] ?? "book.closed.fill").font(.system(size: 13, weight: .bold))
                        Text(chapter).font(.system(size: 13, weight: .bold, design: .serif)).fixedSize()
                            .rotationEffect(.degrees(90)).frame(width: 18, height: 64)
                    }
                    .foregroundStyle(chosen ? Binder.brassLight : TavernPalette.parchment.opacity(0.8))
                    .shadow(color: .black.opacity(0.75), radius: 0.5, y: 1)
                    // The chosen chapter's tab stands out furthest; the others sit further in, in the shade.
                    .frame(width: Binder.tabWidth - (chosen ? 0 : 6), height: tabHeight)
                    // Only the leather runs in under the page; the button is the part that stands out.
                    .background(alignment: .trailing) {
                        leather(chosen).frame(width: Binder.tabWidth - (chosen ? 0 : 6) + Self.tuck)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.18), value: chosen)
                .accessibilityLabel(chapter)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .frame(width: Binder.tabWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deck workspace")
    }

    /// The chosen tab is the leather's own lively red with a deep shadow; the others are dyed down to the
    /// binder's oxblood.
    @ViewBuilder private func leather(_ chosen: Bool) -> some View {
        if let art = Self.art {
            Image(uiImage: art)
                .resizable(capInsets: Self.artInsets, resizingMode: .stretch)
                .interpolation(.high)
                .colorMultiply(chosen ? Color(red: 1, green: 0.93, blue: 0.88) : Color(red: 0.6, green: 0.52, blue: 0.5))
                .shadow(color: .black.opacity(chosen ? 0.6 : 0.4), radius: chosen ? 3.5 : 1.5, x: chosen ? 2 : 1, y: chosen ? 2 : 1)
        } else {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 10, topTrailingRadius: 10)
            ZStack {
                TavernFill(material: .leather)
                Binder.dye(chosen ? Binder.oxblood : Binder.leatherDark, chosen ? 0.75 : 0.5)
            }
            .clipShape(shape)
            .overlay(shape.inset(by: 3).stroke(Binder.thread, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .overlay(shape.stroke(.black.opacity(0.5), lineWidth: 0.8))
            .shadow(color: .black.opacity(chosen ? 0.55 : 0.35), radius: chosen ? 3 : 1.5, x: 1, y: 1)
        }
    }
}

// MARK: - The binder's controls

/// "Done" as a leather strap with a brass buckle.
struct BinderStrapButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private static let buckle = UIImage(named: "tavern-binder-buckle")

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            // The buckle: the Meshy-made brass buckle, or a drawn frame and pin while that art is missing.
            Group {
                if let buckle = Self.buckle {
                    Image(uiImage: buckle).resizable().interpolation(.high).scaledToFit().frame(width: 32, height: 24)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Binder.brass, lineWidth: 3).frame(width: 16, height: 22)
                        Capsule().fill(Binder.brass).frame(width: 2.5, height: 14)
                    }
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            configuration.label
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(TavernPalette.parchment)
                .shadow(color: .black.opacity(0.7), radius: 0.5, y: 1)
        }
        .padding(.leading, 10).padding(.trailing, 14).frame(minHeight: 40)
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12)
            ZStack { TavernFill(material: .leather); Binder.dye(Binder.oxblood, 0.55) }
                .clipShape(shape)
                .overlay(shape.inset(by: 3).stroke(Binder.thread, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .overlay(shape.stroke(.black.opacity(0.55), lineWidth: 0.8))
        }
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
                Text(title).font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(TavernPalette.parchment).shadow(color: .black.opacity(0.7), radius: 0.5, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
            }
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// A brass plaque with engraved lettering (Save), or a square brass toggle with an engraved symbol
/// (the rail's tools). `on` presses it in. Menus use it as their label; buttons use
/// `BinderPlaqueButtonStyle`.
struct BinderPlaque<Label: View>: View {
    var square = false
    var on = false
    var pressed = false
    @ViewBuilder var label: Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let sunk = pressed || on
        let shape = RoundedRectangle(cornerRadius: square ? 7 : 8, style: .continuous)
        label
            .font(.system(size: 15, weight: .heavy, design: .serif))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(Binder.engraved)
            .shadow(color: Binder.brassLight.opacity(0.7), radius: 0, y: 1)
            .padding(.horizontal, square ? 0 : 14)
            .frame(width: square ? 38 : nil, height: square ? 38 : 34)
            .background(shape.fill(sunk ? Binder.brassPressed : Binder.brass))
            .overlay(shape.inset(by: 2.5).stroke(Binder.brassDeep.opacity(0.55), lineWidth: 0.8))
            .overlay(shape.stroke(.black.opacity(0.5), lineWidth: 0.8))
            .shadow(color: .black.opacity(sunk ? 0.15 : 0.45), radius: sunk ? 1 : 2.5, y: sunk ? 0 : 2)
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

/// A brass rail: the strip the binder's tools are mounted on, with a rivet at each end.
struct BinderRail<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                ZStack {
                    TavernFill(material: .leather)
                    Binder.dye(Binder.leatherDark, 0.35)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Binder.brass, lineWidth: 3))
                .overlay(shape.inset(by: 3).stroke(.black.opacity(0.45), lineWidth: 0.8))
                .overlay(alignment: .leading) { rivet.padding(.leading, 4) }
                .overlay(alignment: .trailing) { rivet.padding(.trailing, 4) }
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            }
    }

    private var rivet: some View {
        Circle().fill(Binder.brass).frame(width: 5, height: 5)
            .overlay(Circle().stroke(Binder.brassDeep, lineWidth: 0.6)).accessibilityHidden(true)
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
            ZStack {
                Circle().strokeBorder(Binder.brass, lineWidth: 2.5).frame(width: 16, height: 16)
                Capsule().fill(Binder.brass).frame(width: 3, height: 8).rotationEffect(.degrees(-45)).offset(x: 7, y: 7)
            }
            .frame(width: 24, height: 24).accessibilityHidden(true)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(TavernPalette.parchment.opacity(0.5)))
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(TavernPalette.parchment)
                .tint(Binder.brassLight)
                .autocorrectionDisabled()
                .focused(focus)
                .submitLabel(.search)
                .onSubmit { focus.wrappedValue = false }
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(TavernPalette.parchment.opacity(0.7)).frame(width: 32, height: 40)
                }.buttonStyle(.plain).accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 8).frame(height: 40)
        // The whole well is the place to write, not only the line of text in it.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.6), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).inset(by: -1).stroke(Binder.brassLight.opacity(0.25), lineWidth: 0.6))
    }
}

/// Which cards the binder's pages show: the deck's own, or every card there is to add.
enum BinderShelf: String { case deck, all }

/// The two shelves as a brass switch on the rail.
struct BinderShelfSwitch: View {
    @Binding var shelf: BinderShelf

    var body: some View {
        HStack(spacing: 0) {
            option(.deck, title: "My deck", icon: "rectangle.stack.fill")
            option(.all, title: "All cards", icon: "books.vertical.fill")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Binder.brass, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show cards")
    }

    private func option(_ value: BinderShelf, title: String, icon: String) -> some View {
        let chosen = shelf == value
        return Button { shelf = value } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(chosen ? Color(red: 1, green: 0.92, blue: 0.7) : TavernPalette.parchment.opacity(0.7))
                .shadow(color: .black.opacity(0.7), radius: 0.5, y: 1)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if chosen {
                        TavernFill(material: .ember).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Binder.brassLight.opacity(0.6), lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// Mana values 0 to 7+ as brass coins: tap one or more to see only those costs; none shows all.
struct BinderManaFilter: View {
    @Binding var selection: Set<Int>
    static let values = Array(0...7)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.values, id: \.self) { value in
                let on = selection.contains(value)
                Button { if on { selection.remove(value) } else { selection.insert(value) } } label: {
                    ZStack {
                        if on {
                            Circle().fill(TavernPalette.ember.opacity(0.55)).frame(width: 34, height: 34).blur(radius: 4)
                        }
                        TavernCoin(value: value, size: 30)
                            .overlay(alignment: .bottomTrailing) {
                                if value == 7 {
                                    Text("+").font(.system(size: 12, weight: .black, design: .serif)).foregroundStyle(Binder.engraved)
                                        .offset(x: 1, y: 1)
                                }
                            }
                            .opacity(on || selection.isEmpty ? 1 : 0.55)
                            .scaleEffect(on ? 1.08 : 1)
                    }
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
                    Capsule().fill(.black.opacity(0.55))
                    Capsule().fill(LinearGradient(colors: [TavernPalette.ember, Color(red: 0.75, green: 0.25, blue: 0.08)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(0, proxy.size.width * fraction))
                    // Segment marks every tenth of the way.
                    HStack(spacing: 0) {
                        ForEach(1..<10, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(.black.opacity(0.35)).frame(width: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .overlay(Capsule().strokeBorder(Binder.brass, lineWidth: 2))
            }
            .frame(height: 14)
            if showsCount {
                Text("\(count)/\(target)").font(.system(size: 13, weight: .heavy, design: .serif)).monospacedDigit()
                    .foregroundStyle(DeckStudioPalette.ink)
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
    let add: () -> Void
    let remove: () -> Void
    let tap: () -> Void

    private var editing: Bool { canEdit && selected == nil }

    var body: some View {
        VStack(spacing: 5) {
            DeckStudioCardImageTile(name: name, card: card)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.08), .white.opacity(0.20)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.8))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).inset(by: -0.5).stroke(.black.opacity(0.25), lineWidth: 0.5))
                }
                .overlay { BinderCorners(size: 16, style: .card).allowsHitTesting(false) }
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
                            Button { if quantity > 0 { remove() } } label: { Color.clear.contentShape(Rectangle()) }
                            Button(action: add) { Color.clear.contentShape(Rectangle()) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    } else {
                        Button(action: tap) { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tapLabel ?? name)
                            .accessibilityAddTraits(selected == true ? [.isSelected] : [])
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
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
                .font(.system(size: 14, weight: .heavy, design: .serif)).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(TavernPalette.parchment)
                .frame(minWidth: 28, minHeight: 22)
                .background(Capsule().fill(.black.opacity(0.62)))
                .overlay(Capsule().strokeBorder(Binder.brass, lineWidth: 1))
                .accessibilityLabel("\(name), quantity \(quantity)")
            if editing {
                coinButton("plus", label: addLabel ?? "Add one \(name)") { add() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func coinButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .black)).foregroundStyle(Binder.engraved)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Binder.brass))
                .overlay(Circle().stroke(Binder.brassDeep, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
