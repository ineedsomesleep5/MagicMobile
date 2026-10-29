import SwiftUI
import UIKit

/// Deck Studio's page chrome. It was a spell book's parchment (2026-10-05); since the Arena menus (Caleb,
/// 2026-10-22) a page is Arena's dark glass in the gold hairline, with gold headings and serif type. The names stay
/// so the screens keep their layout. Android still draws the book (studio/GrimoireChrome.kt).
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

    /// A place to write on the page (a search or text field): a darker pane in the gold hairline.
    func grimoireField(cornerRadius: CGFloat) -> some View {
        background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
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

/// A page's surface: Arena's dark glass, a little lighter at the top; a plate set into it is a lighter pane.
struct GrimoirePaper: View {
    enum Tone { case page, plate }
    var tone: Tone = .page

    var body: some View {
        Group {
            if tone == .page {
                LinearGradient(colors: [ArenaGlass.top.opacity(0.94), ArenaGlass.bottom.opacity(0.96)], startPoint: .top, endPoint: .bottom)
            } else {
                Color.white.opacity(0.055)
            }
        }
        .accessibilityHidden(true)
    }
}

extension GrimoirePaper {
    /// The page's surface as a fill for navigation bars, so a bar is the head of the same page.
    @MainActor static var barStyle: AnyShapeStyle { AnyShapeStyle(ArenaGlass.top) }
}

private struct GrimoirePageModifier: ViewModifier {
    let leaf: Grimoire.Leaf

    func body(content: Content) -> some View {
        content
            // Lists and forms on a page show the page, not the system's grouped grey.
            .scrollContentBackground(.hidden)
            .background { GrimoirePaper().ignoresSafeArea() }
            .fontDesign(.serif)
            .foregroundStyle(ArenaMenuStyle.text)
            .environment(\.arenaBoard, true)
            .preferredColorScheme(.dark)
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
        Form { Group { content }.listRowBackground(Color.white.opacity(0.06)) }
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
        // Arena's segmented choice: the chosen option filled gold with dark type.
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option, label in
                let chosen = selection == option
                Button { selection = option } label: {
                    Text(label).font(ArenaMenuStyle.font(14, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(chosen ? Color(red: 0.11, green: 0.06, blue: 0.03) : ArenaMenuStyle.dim)
                        .padding(.horizontal, 10).frame(minHeight: 36).frame(maxWidth: .infinity)
                        .background {
                            if chosen { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ArenaMenuStyle.goldFill) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
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
                .font(ArenaMenuStyle.font(11, .heavy)).tracking(1.8)
                .foregroundStyle(ArenaMenuStyle.gold)
            Spacer()
            if let count {
                Text("\(count)").font(ArenaMenuStyle.font(12, .bold)).monospacedDigit()
                    .foregroundStyle(ArenaMenuStyle.dim)
                    .accessibilityLabel(CardCountText.label(count))
            }
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.45).accessibilityHidden(true)
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
            ArenaCaps(text: kicker, size: 11)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(ArenaMenuStyle.text)
                .shadow(color: .black, radius: 2)
            if let subtitle {
                Text(subtitle).font(ArenaMenuStyle.font(14, .regular))
                    .foregroundStyle(ArenaMenuStyle.dim)
            }
        }
    }
}

/// A gold hairline across the page.
struct GrimoireRule: View {
    var body: some View {
        Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.5)
            .accessibilityHidden(true)
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
