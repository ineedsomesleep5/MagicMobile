import Metal
import QuartzCore
import UIKit

/// The spell book's page curl (docs/deck-studio/PAGE_CURL.md): the maths, the Metal renderer and one turn of
/// a page. GrimoireStage owns the window a turn is drawn in and decides when a turn starts; this file draws it
/// and follows the finger. Android's PageCurl.kt / PageCurlShader.kt match.

// MARK: - Model

/// Where the fold is for a given progress. The sheet bends over a cylinder of `radius` whose axis lies along
/// the fold, `foot` away from the origin across `normal`; the part of the sheet past the foot wraps over the
/// cylinder and lies back, face down, over the part still flat.
struct PageCurlPose: Equatable {
    var normal: SIMD2<Float>
    var foot: Float
    var radius: Float
}

enum PageCurlModel {
    /// The fold's lean at the start, in radians: the bottom corner is lifted first, as a hand would.
    static let tilt: CGFloat = 0.20
    /// The roll's radius as a share of the sheet's width, and its limits in points.
    static let radiusShare: CGFloat = 0.12
    static let radiusRange: ClosedRange<CGFloat> = 26...60
    /// Past this share of the way (or this speed along the way, points per second, once the page is past an eighth) a release finishes the turn.
    static let completeShare: CGFloat = 0.4
    static let flingSpeed: CGFloat = 300

    static func maxRadius(sheetWidth: CGFloat) -> CGFloat {
        min(max(sheetWidth * radiusShare, radiusRange.lowerBound), radiusRange.upperBound)
    }

    /// `progress` runs 0 (the sheet lies flat, nothing is curled) to 1 (it has turned over the spine). Lengths
    /// are in the unit of `size`, the sheet's rectangle with its spine at x = `spine` (a lone page: its left edge).
    /// The fold sweeps from the far corner to the spine, levelling out as it goes so that the finished page
    /// lies exactly over the one beside it; the roll is tight at both ends and fullest in the middle.
    static func pose(progress: CGFloat, size: CGSize, spine: CGFloat, tilt: CGFloat = PageCurlModel.tilt,
                     maxRadius: CGFloat) -> PageCurlPose {
        let k = min(max(progress, 0), 1)
        let lean = tilt * (1 - k)
        let far = size.width * cos(tilt) + size.height * sin(tilt) + 1
        let foot = far + (spine - far) * k
        let radius = maxRadius * pow(max(sin(.pi * k), 0), 0.55)
        return PageCurlPose(normal: SIMD2(Float(cos(lean)), Float(sin(lean))), foot: Float(foot), radius: Float(max(radius, 0.75)))
    }

    /// How far a sideways drag has turned the page. `travel` is the finger's way for a whole turn.
    static func progress(forDrag distance: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 1 else { return 0 }
        return min(max(distance / travel, 0), 1)
    }

    /// Whether letting go finishes the turn. `along` is the finger's speed in the direction of the turn.
    static func completes(progress: CGFloat, along: CGFloat) -> Bool {
        if progress >= 0.6 { return true }
        if along < -flingSpeed { return false }
        return progress >= completeShare || (along > flingSpeed && progress > 0.12)
    }
}

// MARK: - Renderer

/// Mirrors PageCurlUniforms in PageCurl.metal (112 bytes).
struct PageCurlUniforms {
    var size: SIMD2<Float>
    var normal: SIMD2<Float>
    var paper: SIMD4<Float>
    var pose: SIMD4<Float>
    var slots: SIMD4<Int32>
    var look: SIMD4<Float>
    var rectA: SIMD4<Float>
    var rectB: SIMD4<Float>
}

/// The Metal objects every turn shares. Nil on a device with no Metal, where turns crossfade instead.
@MainActor
final class PageCurlRenderer {
    static let shared = PageCurlRenderer()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "pageCurlVertex"),
              let fragment = library.makeFunction(name: "pageCurlFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device; self.queue = queue; self.pipeline = pipeline
    }

    /// A picture as a BGRA texture, its first row the top of the picture. (Drawn into a bitmap by hand: the texture
    /// loader failed now and then when memory was short, which left a turn waiting for a picture that never came.)
    func texture(_ image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let width = cgImage.width, height = cgImage.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let bytesPerRow = width * 4
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var drawn = false
        let data = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * height, alignment: 16)
        defer { data.deallocate() }
        if let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            drawn = true
        }
        guard drawn else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        return texture
    }
}

/// A picture of part of a window as the screen shows it now.
func grimoirePicture(of window: UIWindow, in rect: CGRect, afterScreenUpdates: Bool) -> UIImage? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = window.traitCollection.displayScale
    format.opaque = true
    format.preferredRange = .standard
    let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
    return renderer.image { _ in
        _ = window.drawHierarchy(in: CGRect(x: -rect.minX, y: -rect.minY, width: window.bounds.width, height: window.bounds.height),
                                 afterScreenUpdates: afterScreenUpdates)
    }
}

/// Draws one frame of the curl into a Metal layer the size of the stage rectangle.
final class PageCurlView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    @MainActor init(frame: CGRect, renderer: PageCurlRenderer, scale: CGFloat) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: frame.width * scale, height: frame.height * scale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @MainActor func draw(_ uniforms: PageCurlUniforms, _ first: MTLTexture, _ second: MTLTexture, renderer: PageCurlRenderer) {
        guard let drawable = metalLayer.nextDrawable(), let buffer = renderer.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = uniforms
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PageCurlUniforms>.stride, index: 0)
        encoder.setFragmentTexture(first, index: 0)
        encoder.setFragmentTexture(second, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// MARK: - One turn

/// Where a turn happens: the paper that turns (a binder page, or the left and right pages of a spread), in
/// window points, with the spine's x in the rectangle's own coordinates (a lone page: its left edge).
struct PageCurlLayout: Equatable {
    var rect: CGRect
    var spine: CGFloat
    var spread: Bool
    /// The pages themselves in the rectangle's own coordinates, left to right (one upright, two sideways).
    var pages: [CGRect]
    /// The pages' rounded corners; nothing is drawn outside them but the strip between the two pages.
    var cornerRadius: CGFloat
}

/// One page turn on the stage: two pictures (the screen before and after) bent over a moving fold. It runs a
/// display link only while it moves, and draws on it only when something changed.
@MainActor
final class PageCurlTurn {
    let forward: Bool
    let layout: PageCurlLayout
    let view: PageCurlView
    private let renderer: PageCurlRenderer
    private let old: MTLTexture
    private var new: MTLTexture?
    private let maxRadius: CGFloat
    private let scale: CGFloat
    private var tilt = PageCurlModel.tilt
    private var link: CADisplayLink?
    private var dirty = true
    private var animation: Animation?

    /// How far the page has turned, 0 to 1 (shown the other way round when a lone page comes back: the
    /// returning page is the sheet, and it unrolls).
    private(set) var progress: CGFloat = 0 { didSet { if progress != oldValue { markDirty() } } }

    /// A turn that runs by itself. Core Animation keeps the clock (a layer's position carries the progress) so the
    /// system, and UI tests waiting for the app to be idle, can see that a page is still moving.
    private struct Animation {
        let target: CGFloat, end: CFTimeInterval
        let completion: () -> Void
    }
    private let clock = CALayer()

    init?(forward: Bool, layout: PageCurlLayout, old: UIImage, scale: CGFloat) {
        guard let renderer = PageCurlRenderer.shared, let texture = renderer.texture(old) else { return nil }
        self.forward = forward; self.layout = layout; self.renderer = renderer; self.old = texture; self.scale = scale
        let sheetWidth = layout.spread ? (layout.pages.last?.width ?? layout.rect.width - layout.spine) : layout.rect.width
        maxRadius = PageCurlModel.maxRadius(sheetWidth: sheetWidth)
        view = PageCurlView(frame: layout.rect, renderer: renderer, scale: scale)
        render()
    }

    /// The picture of the page that is arriving; until it is here the old page is shown flat. False if it cannot be used.
    @discardableResult
    func provideNew(_ image: UIImage) -> Bool {
        guard new == nil else { return true }
        guard let texture = renderer.texture(image) else { return false }
        new = texture
        markDirty()
        return true
    }
    var isReady: Bool { new != nil }

    // MARK: Following a finger

    /// The finger's way for a whole turn, from where it first touched.
    func dragTravel(startX: CGFloat) -> CGFloat {
        let unit = layout.spread ? layout.rect.width / 2 : layout.rect.width
        let farEnd = forward ? layout.rect.minX : layout.rect.maxX
        return min(max(abs(startX - farEnd) - 20, 0.5 * unit), 0.9 * unit)
    }

    /// Follows a sideways drag: `distance` is how far the finger has moved in the direction of the turn, and
    /// `lift` how far it has moved up (a finger held higher leans the fold further over).
    func drag(distance: CGFloat, travel: CGFloat, lift: CGFloat) {
        tilt = min(max(PageCurlModel.tilt + lift / max(layout.rect.height, 1) * 0.7, 0.05), 0.4)
        progress = PageCurlModel.progress(forDrag: distance, travel: travel)
    }

    // MARK: Animating

    /// Runs the turn to `target` (1: finished, 0: back where it was) and then calls `completion`.
    func animate(to target: CGFloat, duration: CFTimeInterval, easeOut: Bool, completion: @escaping () -> Void) {
        let length = max(duration, 0.05)
        if clock.superlayer == nil { view.layer.addSublayer(clock) }
        clock.removeAllAnimations()
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = progress
        move.toValue = target
        move.duration = length
        move.timingFunction = easeOut ? CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.3, 1) : CAMediaTimingFunction(name: .easeInEaseOut)
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clock.position = CGPoint(x: target, y: 0)
        clock.add(move, forKey: "progress")
        CATransaction.commit()
        animation = Animation(target: target, end: CACurrentMediaTime() + length, completion: completion)
        startLink()
    }

    func stop() {
        link?.invalidate(); link = nil
        animation = nil
        clock.removeAllAnimations()
        clock.removeFromSuperlayer()
    }

    private func markDirty() {
        dirty = true
        startLink()
    }

    private func startLink() {
        guard link == nil else { return }
        let proxy = LinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func tick() {
        if let animation {
            if CACurrentMediaTime() >= animation.end {
                self.animation = nil
                progress = animation.target
                render()
                link?.invalidate(); link = nil
                clock.removeAllAnimations()
                animation.completion()
                return
            }
            if let value = clock.presentation()?.position.x { progress = CGFloat(value) }
        }
        if dirty { render() }
        // Nothing moving and nothing to draw (a finger held still): the link rests until something changes.
        else if animation == nil { link?.invalidate(); link = nil }
    }

    /// Draws the page at the current progress.
    func render() {
        dirty = false
        let size = SIMD2<Float>(Float(layout.rect.width * scale), Float(layout.rect.height * scale))
        // A lone page that comes back is the new page, rolled up beside the spine, unrolling over the old one.
        let reversed = !forward && !layout.spread
        let shown = reversed ? 1 - progress : progress
        // A spread's left page turning onto the right one is the right page's turn seen in a mirror.
        let mirrored = !forward && layout.spread
        let spine = layout.spread ? (mirrored ? layout.rect.width - layout.spine : layout.spine) * scale : 0
        let pose = PageCurlModel.pose(progress: new == nil ? 0 : shown,
                                      size: CGSize(width: layout.rect.width * scale, height: layout.rect.height * scale),
                                      spine: spine, tilt: tilt, maxRadius: maxRadius * scale)
        let second = new ?? old
        // Which picture is the sheet's front, its back, and what lies under the sheet and on the landing side.
        let slots: SIMD4<Int32>
        if layout.spread { slots = SIMD4(0, 1, 1, 0) }
        else if forward { slots = SIMD4(0, -1, 1, 1) }
        else { slots = SIMD4(1, -1, 0, 0) }
        // The paper that turns (rectA) and the page it lands on (rectB), in the turn's own (possibly mirrored) pixels.
        let pages = layout.pages.map { SIMD4<Float>(Float($0.minX * scale), Float($0.minY * scale), Float($0.maxX * scale), Float($0.maxY * scale)) }
        var sheet = pages.first ?? SIMD4(0, 0, size.x, size.y)
        var landing = SIMD4<Float>(0, 0, 0, 0)
        if layout.spread, pages.count == 2 {
            sheet = forward ? pages[1] : pages[0]
            landing = forward ? pages[0] : pages[1]
        }
        if mirrored {
            sheet = SIMD4(size.x - sheet.z, sheet.y, size.x - sheet.x, sheet.w)
            if landing.z > landing.x { landing = SIMD4(size.x - landing.z, landing.y, size.x - landing.x, landing.w) }
        }
        let uniforms = PageCurlUniforms(
            size: size, normal: pose.normal,
            paper: SIMD4(0.80, 0.71, 0.55, 1),
            pose: SIMD4(pose.foot, pose.radius, Float(spine), mirrored ? 1 : 0),
            slots: slots, look: SIMD4(0.45, 0.10, Float(layout.cornerRadius * scale), 0),
            rectA: sheet, rectB: landing)
        // With no new picture yet, both are the old page so nothing shows through.
        view.draw(uniforms, old, new == nil ? old : second, renderer: renderer)
    }
}

/// CADisplayLink keeps its target alive; this stands in so a finished turn can go.
private final class LinkProxy: NSObject {
    weak var turn: PageCurlTurn?
    init(_ turn: PageCurlTurn) { self.turn = turn }
    @MainActor @objc func tick(_ link: CADisplayLink) {
        guard let turn else { link.invalidate(); return }
        turn.tick()
    }
}
