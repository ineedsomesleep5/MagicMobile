import AVFoundation
import SwiftUI
import UIKit

/// The spell book's moving parts (Caleb, 2026-10-05): the film of the book opening when Decks is
/// tapped (and closing on Done), and the page that turns between Deck Studio's screens.
///
/// They are drawn in a window above the whole app, so they cover any sheet or full-screen cover and
/// what is underneath can change without its own animation. Android's GrimoireStage.kt matches.
///
/// Reduce Motion (and UI tests, unless they ask for it) skips all of it: the change simply happens.
@MainActor
final class GrimoireStage {
    static let shared = GrimoireStage()

    /// One turn or film at a time; anything asked for meanwhile just makes its change.
    private var busy = false

    /// The binder's pages on screen, by screen in the order the screens appeared, each page's frame in
    /// the window. A turn moves only the paper of the newest screen's pages; the binder around them (its
    /// leather, head and index tabs) stays still. With none registered the whole screen turns.
    private var binderScreens: [(screen: UUID, pages: [UUID: CGRect])] = []
    func setBinderPage(_ frame: CGRect, page: UUID, screen: UUID) {
        if let index = binderScreens.firstIndex(where: { $0.screen == screen }) { binderScreens[index].pages[page] = frame }
        else { binderScreens.append((screen, [page: frame])) }
    }
    func removeBinderPage(_ page: UUID, screen: UUID) {
        guard let index = binderScreens.firstIndex(where: { $0.screen == screen }) else { return }
        binderScreens[index].pages[page] = nil
        if binderScreens[index].pages.isEmpty { binderScreens.remove(at: index) }
    }
    /// The newest binder screen's pages, left to right.
    /// Whether a drag that begins at this point (in the window) may turn the page: it has to begin on the paper, below
    /// the page's head (Done, Save, the tags and the other plaques sit at the top of each page, and a finger that
    /// slides off one of them is not turning anything). With no binder pages registered, anywhere will do.
    func pageMayCurl(from point: CGPoint) -> Bool {
        let pages = binderPages
        guard !pages.isEmpty else { return true }
        guard let page = pages.first(where: { $0.contains(point) }) else { return false }
        return point.y >= page.minY + Grimoire.headBand
    }
    private var binderPages: [CGRect] { (binderScreens.last?.pages.values).map { $0.sorted { $0.minX < $1.minX } } ?? [] }
    private var window: UIWindow?
    private var endObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?

    /// UI tests run without the film and page turns unless MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION is set.
    static var motionEnabled: Bool {
        if UIAccessibility.isReduceMotionEnabled { return false }
        let environment = ProcessInfo.processInfo.environment
        if environment["MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION"] != nil { return true }
        return !HowToPlayLaunch.isAutomated(arguments: ProcessInfo.processInfo.arguments, environment: environment)
    }

    /// A state change with no animation of its own (a cover presented or dismissed in place).
    static func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    // MARK: Film

    /// Plays the book opening over the menu while `present` puts Deck Studio underneath; the film then
    /// fades into its first page.
    func open(present: @escaping () -> Void) {
        film(opening: true, change: present)
    }

    /// Fades the film's first frame (the open page) over Deck Studio, `dismiss` removes it underneath,
    /// and the book closes back onto the tavern table before the menu returns.
    func close(dismiss: @escaping () -> Void) {
        film(opening: false, change: dismiss)
    }

    private func film(opening: Bool, change: @escaping () -> Void) {
        guard Self.motionEnabled, !busy, let scene = Self.activeScene, let source = Self.keyWindow(in: scene) else {
            Self.withoutAnimation(change); return
        }
        let portrait = source.bounds.height >= source.bounds.width
        let name = "grimoire-\(opening ? "open" : "close")-\(portrait ? "portrait" : "landscape")"
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            Self.withoutAnimation(change); return
        }
        busy = true
        let stage = makeWindow(scene)
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        let view = FilmView(player: player)
        view.frame = stage.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.alpha = 0
        stage.addSubview(view)

        var finished = false
        let finish: () -> Void = { [weak self] in
            guard let self, !finished else { return }
            finished = true
            // The page (or the menu) underneath gets a moment to draw before the film lifts.
            UIView.animate(withDuration: opening ? 0.32 : 0.36, delay: 0.06, options: [.curveEaseInOut]) {
                view.alpha = 0
            } completion: { _ in
                player.pause()
                self.tearDown()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem,
                                                             queue: .main) { _ in
            Task { @MainActor in finish() }
        }
        // The film shows once its first frame is ready (a few hundredths of a second for a local file).
        var started = false
        let start: () -> Void = {
            guard !started else { return }
            started = true
            GameAudio.shared.play(.pageFlip)
            UIView.animate(withDuration: 0.2) { view.alpha = 1 } completion: { _ in
                player.play()
                // Underneath the film, once it covers the screen: Deck Studio arrives while the book
                // opens (building its first page costs nothing the player sees), and leaves as the
                // book starts to close. The film itself plays on whatever the main thread is doing.
                DispatchQueue.main.async { Self.withoutAnimation(change) }
            }
        }
        readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in start() }
        }
        // Never strand the player behind a film that fails to load or end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if !started { finished = true; Self.withoutAnimation(change); self.tearDown() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { finish() }
    }

    // MARK: Page turns

    /// What a page turn looks like right now: the curl, a quick crossfade under Reduce Motion, or nothing
    /// (UI tests, unless they ask for motion with MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION).
    enum PageEffect { case none, crossfade, curl }
    static var pageEffect: PageEffect {
        let environment = ProcessInfo.processInfo.environment
        let automated = HowToPlayLaunch.isAutomated(arguments: ProcessInfo.processInfo.arguments, environment: environment)
        if automated && environment["MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION"] == nil { return .none }
        if UIAccessibility.isReduceMotionEnabled { return .crossfade }
        return PageCurlRenderer.shared == nil ? .crossfade : .curl
    }

    /// A page turned by a finger. The swipe watcher arms one (`beginDrag`) and calls the screen's own "next
    /// chapter" or "previous chapter", which reaches `turnPage` as it always did; `turnPage` then follows the
    /// finger instead of playing the turn by itself.
    private final class DragSession {
        let forward: Bool
        let start: CGPoint
        let revert: () -> Void
        var turn: PageCurlTurn?
        var travel: CGFloat = 1
        var distance: CGFloat = 0
        var lift: CGFloat = 0
        var released: (speed: CGFloat, cancelled: Bool)?
        /// A turn that moved to another screen (the library, a deck) cannot be put back from here.
        var revertible = true
        var screenBefore: UUID?
        var finishing = false
        /// The turn is falling back and still has to put the screen back.
        var reverting = false
        init(forward: Bool, start: CGPoint, revert: @escaping () -> Void) { self.forward = forward; self.start = start; self.revert = revert }
    }
    private var armedDrag: DragSession?
    private var drag: DragSession?
    private var turn: PageCurlTurn?

    /// Starts a page turn that follows the finger. `probe` makes the screen's change (the same call a swipe
    /// always made); if it turns a page, the turn is live and this returns true. `revert` puts the screen
    /// back if the finger lets go before the turn is half done.
    func beginDrag(forward: Bool, start: CGPoint, probe: () -> Void, revert: @escaping () -> Void) -> Bool {
        finishAutomaticTurn()
        guard Self.pageEffect == .curl, !busy, drag == nil else { return false }
        let session = DragSession(forward: forward, start: start, revert: revert)
        armedDrag = session
        probe()
        armedDrag = nil
        return drag === session
    }

    /// The finger's total movement since it touched, in the window's points.
    func dragChanged(_ translation: CGPoint) {
        guard let drag else { return }
        drag.distance = drag.forward ? -translation.x : translation.x
        drag.lift = -translation.y
        drag.turn?.drag(distance: drag.distance, travel: drag.travel, lift: drag.lift)
    }

    /// The finger lifted (or the touch was cancelled). `speed` is its sideways speed in points per second.
    func dragEnded(speed: CGFloat, cancelled: Bool) {
        guard let drag else { return }
        drag.released = (drag.forward ? -speed : speed, cancelled)
        if drag.turn?.isReady == true { finishDrag(drag) }
    }

    private func finishDrag(_ session: DragSession) {
        guard let turn = session.turn, let released = session.released, !session.finishing else { return }
        session.finishing = true
        let complete = !session.revertible
            || (!released.cancelled && PageCurlModel.completes(progress: turn.progress, along: released.speed))
        let remaining = complete ? 1 - turn.progress : turn.progress
        session.reverting = !complete
        turn.animate(to: complete ? 1 : 0, duration: 0.16 + 0.34 * Double(remaining), easeOut: true) { [weak self] in
            guard let self else { return }
            if complete { self.tearDown(); return }
            // The page lies flat again over the old screen: put the screen back, give it a moment to draw, and go.
            session.reverting = false
            self.putBack(session)
            let current = self.turn
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { if self.turn === current { self.tearDown() } }
        }
    }

    /// A curl that plays by itself (or is settling after a finger let go) lets touches through, so a tap or a
    /// drag during it is never lost: it is taken to its end at once (what is underneath already shows the new
    /// page, or has the old one put back) and the new turn begins.
    private func finishAutomaticTurn() {
        guard busy, turn != nil else { return }
        if let session = drag {
            guard session.finishing else { return }
            if session.reverting { session.reverting = false; putBack(session) }
        }
        tearDown()
    }

    /// Puts the screen back as a plain change, with no turn of its own.
    private var applyingSilently = false
    private func putBack(_ session: DragSession) {
        applyingSilently = true
        session.revert()
        applyingSilently = false
    }

    /// Turns the page. `change` swaps what is on screen (with no animation of its own) while the paper of the
    /// binder's pages curls: forward, the old page peels away from its free corner toward the spine and the new
    /// page lies revealed under it; back, the new page unrolls from the spine over the old one. Upright, the
    /// spine is the page's left edge; sideways, the book lies open as a spread, the right page curling over the
    /// spine onto the left for forward and the left onto the right for back. Only the paper turns: the binder's
    /// leather, head and index tabs stay still.
    func turnPage(forward: Bool, change: @escaping () -> Void) {
        if applyingSilently { Self.withoutAnimation(change); return }
        let session = armedDrag
        armedDrag = nil
        finishAutomaticTurn()
        let effect = Self.pageEffect
        guard effect != .none, !busy, let scene = Self.activeScene, let source = Self.keyWindow(in: scene) else {
            Self.withoutAnimation(change); return
        }
        let bounds = source.bounds
        let layout = pageLayout(in: bounds)
        let scale = source.traitCollection.displayScale
        if effect == .curl, let picture = grimoirePicture(of: source, in: layout.rect, afterScreenUpdates: false),
           let turn = PageCurlTurn(forward: forward, layout: layout, old: picture, scale: scale) {
            busy = true
            self.turn = turn
            // A drag already has its finger on the screen; a curl that plays by itself lets touches through.
            let stage = makeWindow(scene, blocksTouches: false)
            turn.view.frame = layout.rect
            stage.addSubview(turn.view)
            let screenBefore = binderScreens.last?.screen
            Self.withoutAnimation(change)
            GameAudio.shared.play(.pageFlip)
            if let session {
                session.turn = turn; session.screenBefore = screenBefore
                session.travel = turn.dragTravel(startX: session.start.x)
                drag = session
            }
            // Never strand the stage behind a turn whose new page does not arrive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.turn === turn, !turn.isReady else { return }
                turn.stop(); self.tearDown()
            }
            // The new page needs a moment to be drawn underneath before it can be pictured or revealed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
                guard let self, self.window === stage else { return }
                // If the new page cannot be pictured the turn is given up: what is underneath already shows it.
                guard let new = grimoirePicture(of: source, in: layout.rect, afterScreenUpdates: true), turn.provideNew(new) else {
                    turn.stop(); self.tearDown(); return
                }
                if let session {
                    session.revertible = self.binderScreens.last?.screen == session.screenBefore
                    turn.drag(distance: session.distance, travel: session.travel, lift: session.lift)
                    if session.released != nil { self.finishDrag(session) }
                } else {
                    turn.animate(to: 1, duration: 0.5, easeOut: false) { self.tearDown() }
                }
            }
            return
        }
        // Reduce Motion (or no Metal): the old page fades into the new one.
        guard let old = source.snapshotView(afterScreenUpdates: false) else { Self.withoutAnimation(change); return }
        busy = true
        let stage = makeWindow(scene)
        old.frame = bounds
        let cut = piece(old, layout.rect, in: bounds)
        stage.addSubview(cut)
        Self.withoutAnimation(change)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) { cut.alpha = 0 } completion: { _ in self?.tearDown() }
        }
    }

    /// The paper that turns: the newest binder screen's page (one upright, two sideways), or the whole screen.
    private func pageLayout(in bounds: CGRect) -> PageCurlLayout {
        let registered = binderPages.filter { bounds.intersects($0) }
        let spread = Grimoire.isSpread(bounds.size, accessibilitySize: UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory)
        var frames = [bounds]
        var corner: CGFloat = 0
        if spread {
            if registered.count == 2 { frames = registered; corner = 13 }
            else { frames = [CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height),
                             CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)] }
        } else if registered.count == 1 {
            frames = registered; corner = 13
        }
        frames = frames.map { $0.intersection(bounds) }
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }.integral.intersection(bounds)
        let local = frames.map { $0.offsetBy(dx: -union.minX, dy: -union.minY) }
        var spine: CGFloat = 0
        if spread { spine = local.count == 2 ? (local[0].maxX + local[1].minX) / 2 : union.width / 2 }
        return PageCurlLayout(rect: union, spine: spine, spread: spread, pages: local, cornerRadius: corner)
    }

    /// A picture of the whole window cut down to one rectangle.
    private func piece(_ view: UIView, _ rect: CGRect, in bounds: CGRect) -> UIView {
        let container = UIView(frame: rect)
        container.clipsToBounds = true
        view.frame = CGRect(x: -rect.minX, y: -rect.minY, width: bounds.width, height: bounds.height)
        container.addSubview(view)
        return container
    }

    // MARK: Window

    private func makeWindow(_ scene: UIWindowScene, blocksTouches: Bool = true) -> UIWindow {
        let stage = PassiveWindow(windowScene: scene)
        stage.blocksTouches = blocksTouches
        stage.frame = scene.coordinateSpace.bounds
        stage.windowLevel = .normal + 1
        stage.backgroundColor = .clear
        stage.rootViewController = StageController()
        stage.isHidden = false
        window = stage
        return stage
    }

    private func tearDown() {
        turn?.stop()
        turn = nil
        drag = nil
        armedDrag = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        readyObservation = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        busy = false
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func keyWindow(in scene: UIWindowScene) -> UIWindow? {
        scene.windows.first { $0.isKeyWindow && !($0 is PassiveWindow) } ?? scene.windows.first { !($0 is PassiveWindow) }
    }
}

/// The stage's window: it takes touches while something plays (so nothing underneath is tapped
/// mid-turn) but never becomes the key window.
private final class PassiveWindow: UIWindow {
    var blocksTouches = true
    override var canBecomeKey: Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        blocksTouches ? super.hitTest(point, with: event) : nil
    }
}

/// Follows the app's own rotation rules and stays out of the status bar's way.
private final class StageController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
    override var prefersStatusBarHidden: Bool { false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}

/// The film, filling the screen (its edges crop on screens of another shape).
private final class FilmView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
