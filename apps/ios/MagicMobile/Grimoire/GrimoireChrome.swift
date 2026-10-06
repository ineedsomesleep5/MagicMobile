import SwiftUI
import UIKit

/// Deck Studio as a spell book (Caleb, 2026-10-05): every screen is a parchment page of the grimoire
/// the opening film shows. The page's own colours stay the Deck Studio palette; this file adds what
/// makes it a book: the paper grain under everything, the shadow in the gutter by the spine, the cut
/// edges of the leaves beyond the page, ribbon markers for chapters and serif type throughout.
/// Android draws the same pieces (studio/GrimoireChrome.kt).
enum Grimoire {
    /// A page lying open in the book, or a loose leaf laid over it (a sheet).
    enum Leaf { case bound, loose }

    /// How wide the gutter's shadow and the stack of leaf edges are, in points.
    static let gutterWidth: CGFloat = 26
    static let edgeWidth: CGFloat = 7

    /// How far each page's content keeps clear of the fold of a spread, beyond its own margins.
    static let foldInset: CGFloat = 12

    /// Sideways the book lies open as a spread of two pages, each with its own content. Not at the
    /// accessibility text sizes: there every screen stays one page, so large type keeps the full width.
    static func isSpread(_ size: CGSize, accessibilitySize: Bool) -> Bool {
        size.width > size.height && !accessibilitySize
    }

    static let ribbonColors: [String: Color] = [
        "Cards": Color(red: 0.55, green: 0.10, blue: 0.08),
        "Ideas": Color(red: 0.66, green: 0.46, blue: 0.10),
        "Analysis": Color(red: 0.14, green: 0.36, blue: 0.22),
        "Playtest": Color(red: 0.13, green: 0.25, blue: 0.48),
    ]
}

extension View {
    /// Makes a full screen of Deck Studio a page of the book: grained parchment underneath (the same
    /// GrimoirePaper its bars and panels are cut from), and over it only the gutter's shadow and the
    /// leaf edges at the page's sides (they take no touches). Nothing is laid over the middle of the
    /// page, so card art keeps its own colours.
    func grimoirePage(_ leaf: Grimoire.Leaf = .bound) -> some View {
        modifier(GrimoirePageModifier(leaf: leaf))
    }

    /// A page's title in the book's hand (the system draws navigation titles in its own sans). The bar
    /// keeps the title for accessibility and tests; the drawn text replaces only how it looks. On a
    /// spread the middle of the bar is the fold, so nothing is drawn there (`onFold`).
    func grimoireTitle(_ title: String, onFold: Bool = false) -> some View {
        navigationTitle(title).toolbar {
            ToolbarItem(placement: .principal) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(DeckStudioPalette.ink).lineLimit(1).accessibilityHidden(true)
                    .opacity(onFold ? 0 : 1)
            }
        }
    }

    /// A place to write on the page (a search or text field): paler paper inside a hairline of ink.
    func grimoireField(cornerRadius: CGFloat) -> some View {
        background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DeckStudioPalette.ink.opacity(0.2), lineWidth: 0.8))
    }

    /// Turns the page on a sideways swipe anywhere on it: leftward for `next`, rightward for
    /// `previous`. A swipe that starts on something that scrolls sideways (a row of cards) or slides
    /// (a slider) belongs to that control and turns nothing.
    func grimoireSwipe(next: @escaping () -> Void, previous: @escaping () -> Void) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 30, coordinateSpace: .global).onEnded { drag in
            let across = drag.translation.width
            guard abs(across) > 80, abs(across) > 2.5 * abs(drag.translation.height),
                  !Grimoire.ownsSidewaysDrags(at: drag.startLocation) else { return }
            if across < 0 { next() } else { previous() }
        })
    }
}

extension Grimoire {
    /// Whether the control under this point (in the window) uses sideways drags itself.
    @MainActor static func ownsSidewaysDrags(at point: CGPoint) -> Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow), var view = window.hitTest(point, with: nil) else { return false }
        while true {
            if view is UISlider || view is UITextView || view is UITextField { return true }
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               scroll.contentSize.width > scroll.bounds.width + 1 { return true }
            guard let parent = view.superview else { return false }
            view = parent
        }
    }
}

/// The book's paper: a parchment tone with the tavern's paper grain multiplied into it.
///
/// The grain is baked into one small opaque tile per tone the first time it is asked for, and that
/// tile is repeated. Blending the texture live would cost an offscreen pass for every page, bar and
/// panel on screen, on every frame of a scroll.
struct GrimoirePaper: View {
    enum Tone { case page, plate }
    var tone: Tone = .page

    var body: some View {
        // A shape painted with the tile (made once per tone), so it takes whatever size it is given.
        if let paint = GrimoirePaperTile.paint(tone) {
            Rectangle().fill(paint).accessibilityHidden(true)
        } else {
            tone == .page ? DeckStudioPalette.background : DeckStudioPalette.surface
        }
    }
}

extension GrimoirePaper {
    /// The page's paper as a fill for navigation bars, so a bar is the head of the same page.
    @MainActor static var barStyle: AnyShapeStyle {
        guard let paint = GrimoirePaperTile.paint(.page) else { return AnyShapeStyle(DeckStudioPalette.background) }
        return AnyShapeStyle(paint)
    }
}

@MainActor
private enum GrimoirePaperTile {
    private static var tiles: [GrimoirePaper.Tone: UIImage] = [:]
    private static var paints: [GrimoirePaper.Tone: ImagePaint] = [:]

    /// The tile as a paint, made once per tone and handed out unchanged.
    static func paint(_ tone: GrimoirePaper.Tone) -> ImagePaint? {
        if let paint = paints[tone] { return paint }
        guard let tile = image(tone) else { return nil }
        let paint = ImagePaint(image: Image(uiImage: tile))
        paints[tone] = paint
        return paint
    }

    static func image(_ tone: GrimoirePaper.Tone) -> UIImage? {
        if let tile = tiles[tone] { return tile }
        guard let grain = UIImage(named: TavernFill.Material.parchment.rawValue) else { return nil }
        let color = UIColor(tone == .page ? DeckStudioPalette.background : DeckStudioPalette.surface)
        let format = UIGraphicsImageRendererFormat()
        format.scale = grain.scale
        format.opaque = true
        let rect = CGRect(origin: .zero, size: grain.size)
        let tile = UIGraphicsImageRenderer(size: grain.size, format: format).image { context in
            color.setFill()
            context.fill(rect)
            // A plate (panel) carries a little less grain than the page it lies on.
            grain.draw(in: rect, blendMode: .multiply, alpha: tone == .page ? 0.26 : 0.2)
        }
        tiles[tone] = tile
        return tile
    }
}

private struct GrimoirePageModifier: ViewModifier {
    let leaf: Grimoire.Leaf

    func body(content: Content) -> some View {
        content
            // Lists and forms on a page show the page, not the system's grouped grey.
            .scrollContentBackground(.hidden)
            .background { GrimoirePaper().ignoresSafeArea() }
            .overlay { if leaf == .bound { GrimoireSpineOverlay().ignoresSafeArea().allowsHitTesting(false) } }
            .fontDesign(.serif)
    }
}

/// What marks a bound page: the gutter's shadow at the spine and the cut edges of the leaves behind
/// it. Upright the spine is the leading edge. Sideways the book is a spread: the spine runs down the
/// middle (the screens lay their content out as two pages, clear of it) with leaf edges at both sides.
struct GrimoireSpineOverlay: View {
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        Canvas { context, size in
            if Grimoire.isSpread(size, accessibilitySize: dynamicType.isAccessibilitySize) {
                gutter(&context, x: size.width / 2, size: size, leading: true)
                gutter(&context, x: size.width / 2, size: size, leading: false)
                edges(&context, size: size, trailing: true)
                edges(&context, size: size, trailing: false)
            } else {
                gutter(&context, x: 0, size: size, leading: false)
                edges(&context, size: size, trailing: true)
            }
        }
        .accessibilityHidden(true)
    }

    /// The shadow where a page curves down into the spine at `x`, falling away to one side.
    private func gutter(_ context: inout GraphicsContext, x: CGFloat, size: CGSize, leading: Bool) {
        let width = Grimoire.gutterWidth
        let rect = CGRect(x: leading ? x - width : x, y: 0, width: width, height: size.height)
        let ink = DeckStudioPalette.ink
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [.init(color: ink.opacity(0.34), location: 0), .init(color: ink.opacity(0.12), location: 0.35),
                             .init(color: .clear, location: 1)]),
            startPoint: CGPoint(x: leading ? rect.maxX : rect.minX, y: 0),
            endPoint: CGPoint(x: leading ? rect.minX : rect.maxX, y: 0)))
    }

    /// The cut edges of the leaves behind this page: a few fine lines down the fore-edge.
    private func edges(_ context: inout GraphicsContext, size: CGSize, trailing: Bool) {
        let width = Grimoire.edgeWidth
        let ink = DeckStudioPalette.ink
        let origin = trailing ? size.width - width : 0
        context.fill(Path(CGRect(x: origin, y: 0, width: width, height: size.height)),
                     with: .linearGradient(Gradient(colors: [ink.opacity(trailing ? 0.02 : 0.16), ink.opacity(trailing ? 0.16 : 0.02)]),
                                           startPoint: CGPoint(x: origin, y: 0), endPoint: CGPoint(x: origin + width, y: 0)))
        for index in 0..<4 {
            let x = origin + (CGFloat(index) + 0.5) * width / 4
            context.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)), with: .color(ink.opacity(0.22)))
        }
    }
}

/// The two pages of an open spread, side by side: each has its own content, and both keep clear of
/// the fold between them, so nothing runs from one page onto the other.
struct GrimoireSpread<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.padding(.trailing, Grimoire.foldInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
            right.padding(.leading, Grimoire.foldInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
        }
    }
}

/// A form on a loose leaf: its rows are paler paper, not the system's white cells.
struct GrimoireForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { Group { content }.listRowBackground(DeckStudioPalette.surfaceElevated) }
    }
}

/// A text field written on the page: paler paper inside a hairline of ink (the system's rounded border
/// is a white box).
struct GrimoireFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(.horizontal, 10).frame(minHeight: 36).grimoireField(cornerRadius: 8)
    }
}

/// The chapters of a deck as ribbon markers hanging from the head of the page. The chosen ribbon
/// hangs longer and brighter; the others wait, darker, tucked up.
struct GrimoireRibbons: View {
    let chapters: [String]
    let selected: String
    let choose: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(chapters, id: \.self) { chapter in
                let chosen = chapter == selected
                Button { choose(chapter) } label: {
                    Text(chapter)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.84).opacity(chosen ? 1 : 0.82))
                        .shadow(color: .black.opacity(0.5), radius: 0.5, y: 0.5)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: chosen ? 50 : 44, alignment: .top)
                        .padding(.top, 11)
                        .background {
                            RibbonShape(notch: 8)
                                .fill(LinearGradient(colors: [ribbon(chapter).opacity(chosen ? 1 : 0.78), ribbon(chapter).opacity(chosen ? 0.86 : 0.6)],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay(alignment: .top) {
                                    // The ribbon passes under the head of the page.
                                    LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom).frame(height: 7)
                                }
                                .overlay(RibbonShape(notch: 8).stroke(Color.black.opacity(0.18), lineWidth: 0.6))
                                .shadow(color: DeckStudioPalette.ink.opacity(chosen ? 0.35 : 0.18), radius: chosen ? 3 : 1.5, y: chosen ? 2 : 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .frame(height: 62, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deck workspace")
    }

    private func ribbon(_ chapter: String) -> Color { Grimoire.ribbonColors[chapter] ?? DeckStudioPalette.accent }
}

/// A ribbon with a swallowtail end.
struct RibbonShape: Shape {
    var notch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A choice written on the page as inked chips, the chosen one filled (the library's filters wear the
/// same): where the system would draw a grey segmented control.
struct GrimoireChoice<Option: Hashable>: View {
    /// What the choice is, for VoiceOver.
    let title: String
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { option, label in
                let chosen = selection == option
                Button { selection = option } label: {
                    Text(label).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 12).frame(minHeight: 40).frame(maxWidth: .infinity)
                        .foregroundStyle(chosen ? DeckStudioPalette.surfaceElevated : DeckStudioPalette.ink)
                        .background(chosen ? DeckStudioPalette.ink : DeckStudioPalette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(DeckStudioPalette.ink.opacity(chosen ? 0 : 0.18), lineWidth: 0.8))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

/// A heading on a page (a section of the deck's cards): small capitals and a count over an inked rule.
///
/// The rule is drawn under the heading, not laid out beside the title: a flexible rule inside the row
/// of a section header kept the deck page's lazy list re-measuring under UI automation, and the app
/// never went idle (DeckStudioReleaseUITests). Here the row is the old plain one: title, spacer, count.
struct GrimoireSubheading: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold, design: .serif)).tracking(1.6)
                .foregroundStyle(DeckStudioPalette.ink)
            Spacer()
            if let count {
                Text("\(count)").font(.system(size: 12, weight: .semibold, design: .serif)).monospacedDigit()
                    .foregroundStyle(DeckStudioPalette.secondaryInk)
                    .accessibilityLabel(CardCountText.label(count))
            }
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DeckStudioPalette.ink.opacity(0.28)).frame(height: 1).accessibilityHidden(true)
        }
    }
}

/// A chapter heading in the book's hand: small capitals over a title, closed by an inked rule with
/// the brand's sparkle.
struct GrimoireHeading: View {
    let kicker: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .serif)).tracking(2.2)
                .foregroundStyle(DeckStudioPalette.accent)
            Text(title)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(DeckStudioPalette.ink)
            if let subtitle {
                Text(subtitle).font(.system(size: 15, design: .serif)).italic()
                    .foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            GrimoireRule()
        }
    }
}

/// An inked rule across the page with the sparkle at its centre.
struct GrimoireRule: View {
    var body: some View {
        HStack(spacing: 8) {
            line(leading: true)
            BrandSparkle(size: 9, color: DeckStudioPalette.accent)
            line(leading: false)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func line(leading: Bool) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [DeckStudioPalette.ink.opacity(0), DeckStudioPalette.ink.opacity(0.45)],
                                 startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading))
            .frame(height: 1)
    }
}

private struct GrimoireCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Leaves this page of the book by turning back to the one before it. Unset outside the book,
    /// where a screen dismisses itself as usual.
    var grimoireClose: (() -> Void)? {
        get { self[GrimoireCloseKey.self] }
        set { self[GrimoireCloseKey.self] = newValue }
    }
}
