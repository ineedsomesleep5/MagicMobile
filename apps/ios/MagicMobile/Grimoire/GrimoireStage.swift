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

    /// Turns the page. `change` swaps what is on screen (with no animation of its own) while a picture
    /// of the old page swings over the spine: forward, the old page lifts away to the left; back, the
    /// new page comes down from the left onto the old one. Upright, the spine is the screen's left
    /// edge; sideways, the book lies open as a spread with its spine down the middle, and the far
    /// half lifts while the near half of the new spread lands.
    func turnPage(forward: Bool, change: @escaping () -> Void) {
        guard Self.motionEnabled, !busy, let scene = Self.activeScene, let source = Self.keyWindow(in: scene),
              let old = source.snapshotView(afterScreenUpdates: false) else {
            Self.withoutAnimation(change); return
        }
        busy = true
        let stage = makeWindow(scene)
        let bounds = stage.bounds
        // In the binder only its pages turn: each picture is cut to the pages it shows.
        let oldPages = binderPages.filter { bounds.intersects($0) }
        old.frame = bounds
        let oldPage = oldPages.count == 1 ? piece(old, oldPages[0], in: bounds) : old
        stage.addSubview(oldPage)
        Self.withoutAnimation(change)
        GameAudio.shared.play(.pageFlip)
        // The new page needs a moment to be drawn underneath before it can be pictured or revealed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            guard let self else { return }
            if Grimoire.isSpread(bounds.size, accessibilitySize: UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory) {
                guard let new = source.snapshotView(afterScreenUpdates: true) else { self.tearDown(); return }
                let halves = oldPages.count == 2 ? (oldPages[0], oldPages[1])
                    : (CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height),
                       CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height))
                self.turnSpread(forward: forward, old: old, new: new, in: stage, left: halves.0, right: halves.1)
            } else if forward {
                self.swing(oldPage, anchorLeft: true, from: 0, to: -.pi / 2 * 0.98, duration: 0.42, easeIn: true) { self.tearDown() }
            } else {
                guard let new = source.snapshotView(afterScreenUpdates: true) else { self.tearDown(); return }
                new.frame = bounds
                let newPages = self.binderPages.filter { bounds.intersects($0) }
                let newPage = newPages.count == 1 ? self.piece(new, newPages[0], in: bounds) : new
                stage.addSubview(newPage)
                self.swing(newPage, anchorLeft: true, from: -.pi / 2 * 0.98, to: 0, duration: 0.42, easeIn: false) { self.tearDown() }
            }
        }
    }

    /// A spread's turn: the far half of the old spread lifts to upright, then the near half of the new
    /// one comes down on the other side, while the halves that do not move stay where they are.
    private func turnSpread(forward: Bool, old: UIView, new: UIView, in stage: UIWindow, left leftRect: CGRect, right rightRect: CGRect) {
        let bounds = stage.bounds
        // The old spread is pictured twice (one picture per page), the new one once for its moving page.
        guard let oldCopy = old.snapshotView(afterScreenUpdates: false) else { tearDown(); return }
        old.removeFromSuperview()
        let staying = piece(old, forward ? leftRect : rightRect, in: bounds)
        let lifting = piece(oldCopy, forward ? rightRect : leftRect, in: bounds)
        let landing = piece(new, forward ? leftRect : rightRect, in: bounds)
        stage.addSubview(staying)
        stage.addSubview(lifting)
        stage.addSubview(landing)
        landing.isHidden = true
        let upright = CGFloat.pi / 2 * 0.98
        // Forward: the right half lifts about its left edge (the spine); the new left half lands about its right edge.
        swing(lifting, anchorLeft: forward, from: 0, to: forward ? -upright : upright, duration: 0.24, easeIn: true) {
            lifting.isHidden = true
            landing.isHidden = false
            self.swing(landing, anchorLeft: !forward, from: forward ? upright : -upright, to: 0, duration: 0.26, easeIn: false) {
                self.tearDown()
            }
        }
    }

    /// A picture of the whole window cut down to one page's frame.
    private func piece(_ view: UIView, _ rect: CGRect, in bounds: CGRect) -> UIView {
        let container = UIView(frame: rect)
        container.clipsToBounds = true
        view.frame = CGRect(x: -rect.minX, y: -rect.minY, width: bounds.width, height: bounds.height)
        container.addSubview(view)
        return container
    }

    /// Swings a page about its left or right edge (the spine), with perspective and a shade that
    /// deepens as it stands up.
    private func swing(_ page: UIView, anchorLeft: Bool, from: CGFloat, to: CGFloat, duration: TimeInterval, easeIn: Bool,
                       completion: @escaping () -> Void) {
        let frame = page.frame
        page.layer.anchorPoint = CGPoint(x: anchorLeft ? 0 : 1, y: 0.5)
        page.frame = frame
        let shade = UIView(frame: page.bounds)
        shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shade.backgroundColor = .black
        page.addSubview(shade)
        func transform(_ angle: CGFloat) -> CATransform3D {
            var t = CATransform3DIdentity
            t.m34 = -1 / 1600
            return CATransform3DRotate(t, angle, 0, 1, 0)
        }
        func shadeAlpha(_ angle: CGFloat) -> CGFloat { 0.42 * abs(angle) / (.pi / 2) }
        page.layer.transform = transform(from)
        shade.alpha = shadeAlpha(from)
        UIView.animate(withDuration: duration, delay: 0, options: [easeIn ? .curveEaseIn : .curveEaseOut]) {
            page.layer.transform = transform(to)
            shade.alpha = shadeAlpha(to)
        } completion: { _ in completion() }
    }

    // MARK: Window

    private func makeWindow(_ scene: UIWindowScene) -> UIWindow {
        let stage = PassiveWindow(windowScene: scene)
        stage.frame = scene.coordinateSpace.bounds
        stage.windowLevel = .normal + 1
        stage.backgroundColor = .clear
        stage.rootViewController = StageController()
        stage.isHidden = false
        window = stage
        return stage
    }

    private func tearDown() {
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
    override var canBecomeKey: Bool { false }
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
