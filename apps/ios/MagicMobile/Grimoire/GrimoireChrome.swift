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

    /// The height of a page's head (the plaques along its top): a drag that begins there turns nothing (PAGE_CURL.md).
    static var headBand: CGFloat = 64

    /// How far each page's content keeps clear of the fold of a spread, beyond its own margins.
    static let foldInset: CGFloat = 12

    /// Sideways the book lies open as a spread of two pages, each with its own content. Not at the
    /// accessibility text sizes: there every screen stays one page, so large type keeps the full width.
    static func isSpread(_ size: CGSize, accessibilitySize: Bool) -> Bool {
        size.width > size.height && !accessibilitySize
    }
}

extension View {
    /// Makes a full screen of Deck Studio a page of the book: grained parchment underneath (the same
    /// GrimoirePaper its bars and panels are cut from), and over it only the gutter's shadow and the
    /// leaf edges at the page's sides (they take no touches). Nothing is laid over the middle of the
    /// page, so card art keeps its own colours.
    func grimoirePage(_ leaf: Grimoire.Leaf = .bound) -> some View {
        modifier(GrimoirePageModifier(leaf: leaf))
    }

    /// A place to write on the page (a search or text field): paler paper inside a hairline of ink.
    func grimoireField(cornerRadius: CGFloat) -> some View {
        background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DeckStudioPalette.ink.opacity(0.2), lineWidth: 0.8))
    }

    /// Turns the page on a sideways drag anywhere on it: leftward for `next`, rightward for `previous`. The
    /// page curls under the finger (GrimoireStage, GrimoirePageCurl) and finishes or springs back when it lets
    /// go. A drag that starts on something that scrolls sideways (a row of cards) or slides (a slider) belongs
    /// to that control and turns nothing, and a mostly vertical one is the page's scroll. The drag is watched by
    /// a UIKit recognizer on the window that never takes a touch from anything else: a SwiftUI drag gesture
    /// over the whole screen swallowed the first tap after the page had scrolled (the binder's index tabs,
    /// 2026-10-06). With Reduce Motion, a swipe of more than 80 points turns the page when it ends.
    func grimoireSwipe(next: @escaping () -> Void, previous: @escaping () -> Void) -> some View {
        background(GrimoireSwipeWatcher(next: next, previous: previous).allowsHitTesting(false).accessibilityHidden(true))
    }
}

/// Registers a screen's chapter turns with the hub while the screen is on show.
private struct GrimoireSwipeWatcher: UIViewRepresentable {
    let next: () -> Void
    let previous: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }
    func updateUIView(_ view: WatcherView, context: Context) {
        context.coordinator.next = next
        context.coordinator.previous = previous
        context.coordinator.refresh()
    }
    static func dismantleUIView(_ view: WatcherView, coordinator: Coordinator) { coordinator.detach() }

    final class WatcherView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    @MainActor final class Coordinator {
        var next: () -> Void = {}
        var previous: () -> Void = {}
        private let token = UUID()
        private weak var window: UIWindow?

        func attach(to window: UIWindow?) {
            guard let window else { detach(); return }
            self.window = window
            refresh()
        }
        func refresh() {
            guard let window else { return }
            GrimoireSwipeHub.shared.register(token, window: window, next: { [weak self] in self?.next() }, previous: { [weak self] in self?.previous() })
        }
        func detach() {
            window = nil
            GrimoireSwipeHub.shared.unregister(token)
        }
    }
}

/// The one pan recognizer on the window, alongside every other gesture and without delaying or cancelling any
/// touch. It belongs to the hub, not to a screen: a turn that leaves the screen (back past the first chapter is
/// the library's page) removes the screen mid-drag, and the drag carries on.
@MainActor
final class GrimoireSwipeHub: NSObject, UIGestureRecognizerDelegate {
    static let shared = GrimoireSwipeHub()

    private struct Handler { let token: UUID; var next: () -> Void; var previous: () -> Void }
    private var handlers: [Handler] = []
    private var recognizer: UIPanGestureRecognizer?
    private weak var host: UIWindow?

    /// What the current gesture is doing.
    private enum Phase { case undecided, dragging, ignored, legacy }
    private var phase = Phase.undecided
    private var start = CGPoint.zero
    private var owner: Handler?

    func register(_ token: UUID, window: UIWindow, next: @escaping () -> Void, previous: @escaping () -> Void) {
        let handler = Handler(token: token, next: next, previous: previous)
        // The first turn should not pay for building the Metal pipeline.
        DispatchQueue.main.async { _ = PageCurlRenderer.shared }
        if let index = handlers.firstIndex(where: { $0.token == token }) { handlers[index] = handler } else { handlers.append(handler) }
        guard window !== host else { return }
        removeRecognizer()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        recognizer = pan; host = window
    }

    func unregister(_ token: UUID) {
        handlers.removeAll { $0.token == token }
        // The recognizer stays until a drag in progress is done.
        if handlers.isEmpty, phase != .dragging { removeRecognizer() }
    }

    private func removeRecognizer() {
        if let recognizer { host?.removeGestureRecognizer(recognizer) }
        recognizer = nil; host = nil
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let moved = gesture.translation(in: gesture.view)
        switch gesture.state {
        case .began:
            let at = gesture.location(in: gesture.view)
            start = CGPoint(x: at.x - moved.x, y: at.y - moved.y)
            owner = handlers.last
            phase = GrimoireStage.pageEffect == .curl ? .undecided : .legacy
            decide(moved)
        case .changed:
            if phase == .undecided { decide(moved) }
            if phase == .dragging { GrimoireStage.shared.dragChanged(moved) }
        case .ended, .cancelled, .failed:
            switch phase {
            case .dragging:
                // The last move may have arrived with the lift (a fast swipe sends few events).
                if gesture.state == .ended { GrimoireStage.shared.dragChanged(moved) }
                GrimoireStage.shared.dragEnded(speed: gesture.velocity(in: gesture.view).x, cancelled: gesture.state != .ended)
            case .legacy:
                // Without the curl a swipe turns the page when it ends: far enough, and mostly sideways.
                if gesture.state == .ended, abs(moved.x) > 80, abs(moved.x) > 2.5 * abs(moved.y),
                   !Grimoire.ownsSidewaysDrags(at: start), let owner {
                    if moved.x < 0 { owner.next() } else { owner.previous() }
                }
            case .undecided, .ignored:
                break
            }
            phase = .undecided; owner = nil
            if handlers.isEmpty { removeRecognizer() }
        default:
            break
        }
    }

    /// Once the finger has moved far enough to tell, a mostly sideways drag that starts on nothing that uses
    /// sideways drags turns the page; anything else is left alone for the rest of the gesture.
    private func decide(_ moved: CGPoint) {
        guard phase == .undecided, hypot(moved.x, moved.y) >= 12 else { return }
        guard let owner, abs(moved.x) > 2 * abs(moved.y), !Grimoire.ownsSidewaysDrags(at: start) else { phase = .ignored; return }
        let forward = moved.x < 0
        let begun = GrimoireStage.shared.beginDrag(forward: forward, start: start, probe: forward ? owner.next : owner.previous,
                                                   revert: forward ? owner.previous : owner.next)
        phase = begun ? .dragging : .ignored
        if begun { GrimoireStage.shared.dragChanged(moved) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

extension Grimoire {
    /// Whether a drag that begins at this point (in the window) is not the page's to turn: it begins off the paper or on
    /// a page's head (GrimoireStage.pageMayCurl), or on a control that uses sideways drags itself.
    @MainActor static func ownsSidewaysDrags(at point: CGPoint) -> Bool {
        if !GrimoireStage.shared.pageMayCurl(from: point) { return true }
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

/// A choice written on the page as inked chips, the chosen one filled (the library's filters wear the
/// same): where the system would draw a grey segmented control.
struct GrimoireChoice<Option: Hashable>: View {
    /// What the choice is, for VoiceOver.
    let title: String
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        // The binder's switch (concept B, 2026-10-06): a dark inset in a brass edge, the chosen option ember glass.
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option, label in
                let chosen = selection == option
                Button { selection = option } label: {
                    Text(label).font(.system(size: 14, weight: .bold, design: .serif)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(chosen ? Color(red: 1, green: 0.92, blue: 0.7) : TavernPalette.parchment.opacity(0.72))
                        .shadow(color: .black.opacity(0.7), radius: 0.5, y: 1)
                        .padding(.horizontal, 10).frame(minHeight: 36).frame(maxWidth: .infinity)
                        .background {
                            if chosen {
                                TavernFill(material: .ember).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Binder.brassLight.opacity(0.6), lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.12, green: 0.06, blue: 0.035).opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Binder.brass, lineWidth: 1.5))
        .frame(minHeight: 44)
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
