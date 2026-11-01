import MetalKit
import QuartzCore
import SwiftUI
import UIKit

/// The living part of an Arena world (docs/ARENA_WORLDS.md "Motion"). It sits on the plate, under the cards, and never asks
/// SwiftUI to redraw the board: light and particles run in Core Animation, and flowing surfaces are small Metal layers on
/// one 24 Hz clock (mist, haze and wind at half that). It rests with `BoardActivity`, halves while the phone is hot, and
/// follows Board Effects.
struct ArenaWorldSpec: Decodable {
    struct Flow: Decodable {
        let kind: String
        let rect: [CGFloat]
        let dir: [Float]
        let speed: Float
        let strength: Float
        let seed: Float
    }
    struct Light: Decodable {
        let rect: [CGFloat]
        let colour: [CGFloat]
        let style: String
        let power: Float
        let halo: CGFloat
    }
    struct Emitter: Decodable {
        let kind: String
        let rect: [CGFloat]
        let rate: Float
    }
    struct Drifter: Decodable {
        let kind: String
        let every: Double?
        let opacity: Float?
    }
    struct Scene: Decodable {
        let flows: [Flow]
        let lights: [Light]
        let particles: [Emitter]
        let drifters: [Drifter]
        let cracks: Bool
        let hotspots: [[CGFloat]]
    }

    let landscape: Scene
    let portrait: Scene

    func scene(landscape wide: Bool) -> Scene { wide ? landscape : portrait }

    /// Resources/arena-worlds.json, built by scripts/brand/arena_world_motion.py.
    static let all: [String: ArenaWorldSpec] = {
        guard let url = Bundle.main.url(forResource: "arena-worlds", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ArenaWorldSpec].self, from: data)) ?? [:]
    }()
}

/// What happened in the game or on the table. Effects only decorate; nothing here reads or changes the game.
enum ArenaWorldEvent {
    case strike, death, spell(big: Bool), wipe, hit(big: Bool), poke(CGPoint)
}

/// Sends the board's events straight to the world's layers, so a reaction never redraws the board.
@MainActor
final class ArenaWorldEvents {
    static let shared = ArenaWorldEvents()
    private let views = NSHashTable<ArenaWorldLifeView>.weakObjects()

    func add(_ view: ArenaWorldLifeView) { views.add(view) }

    func send(_ event: ArenaWorldEvent) {
        for view in views.allObjects { view.react(event) }
    }
}

struct ArenaWorldLife: View {
    enum Band { case table, rail }

    let theme: ArenaTableTheme
    var band = Band.table
    /// How close the viewer is to losing: 0 to 1.
    var dread: CGFloat = 0
    /// A full-table screen covers the world.
    var covered = false
    @AppStorage(BoardFXLevel.key) private var level = BoardFXLevel.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var activity = BoardActivity.shared
    @ObservedObject private var heat = DeviceHeat.shared

    var body: some View {
        if ArenaWorldSpec.all[theme.rawValue] != nil {
            ArenaWorldLifeHost(state: state)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var state: ArenaWorldLifeView.State {
        let chosen = BoardFXLevel(rawValue: level) ?? .full
        let mode: ArenaWorldLifeView.Mode = reduceMotion || chosen == .off ? .still
            : chosen == .reduced || ProcessInfo.processInfo.isLowPowerModeEnabled ? .light : .full
        return .init(theme: theme, band: band, mode: mode, resting: activity.isIdle || covered, covered: covered, hot: heat.isHot, dread: dread)
    }
}

private struct ArenaWorldLifeHost: UIViewRepresentable {
    let state: ArenaWorldLifeView.State

    func makeUIView(context: Context) -> ArenaWorldLifeView { ArenaWorldLifeView() }
    func updateUIView(_ view: ArenaWorldLifeView, context: Context) { view.apply(state) }
}

/// Mirrors the Metal struct in ArenaWorldFlow.metal.
private struct ArenaFlowUniforms {
    var time: Float
    var kind: Float
    var speed: Float
    var strength: Float
    var seed: Float
    var surge: Float
    var dir: SIMD2<Float>
    var scale: SIMD2<Float>
    var pixel: SIMD2<Float>
    var rect: SIMD4<Float>
    var tint: SIMD4<Float>
}

/// A plate and its mask on the GPU, kept alive by the views showing them, so they leave with the table.
private final class ArenaWorldTextures {
    let plate: MTLTexture
    let mask: MTLTexture

    init(plate: MTLTexture, mask: MTLTexture) {
        self.plate = plate
        self.mask = mask
    }
}

/// One device, one pipeline, and the plate and mask of the table on screen, shared by the table and the rail.
@MainActor
private final class ArenaWorldGPU {
    static let shared = ArenaWorldGPU()
    let device = MTLCreateSystemDefaultDevice()
    lazy var queue = device?.makeCommandQueue()
    lazy var pipeline: MTLRenderPipelineState? = {
        guard let device, let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "arenaFlowVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "arenaFlowFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    private weak var loaded: ArenaWorldTextures?
    private var loadedKey = ""
    private var waiting: [String: [(ArenaWorldTextures) -> Void]] = [:]

    func textures(plate: String, mask: String, done: @escaping (ArenaWorldTextures) -> Void) {
        if let loaded, loadedKey == plate { return done(loaded) }
        if waiting[plate] != nil { waiting[plate]?.append(done); return }
        guard let device, let plateImage = UIImage(named: plate)?.cgImage, let maskImage = UIImage(named: mask)?.cgImage else { return }
        waiting[plate] = [done]
        DispatchQueue.global(qos: .userInitiated).async {
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue]
            let first = try? loader.newTexture(cgImage: plateImage, options: options)
            let second = try? loader.newTexture(cgImage: maskImage, options: options)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let calls = self.waiting.removeValue(forKey: plate) ?? []
                    guard let first, let second else { return }
                    let textures = ArenaWorldTextures(plate: first, mask: second)
                    self.loaded = textures
                    self.loadedKey = plate
                    calls.forEach { $0(textures) }
                }
            }
        }
    }
}

/// A display link holds its target strongly; this keeps the view free to go, and stops the link when it has.
private final class ArenaWorldTick: NSObject {
    weak var view: ArenaWorldLifeView?
    @objc func step(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            guard let view else { return link.invalidate() }
            view.step(link)
        }
    }
}

/// Small repeatable randomness, so a world moves the same way each time and no two lights agree.
private struct ArenaWorldRandom {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

final class ArenaWorldLifeView: UIView {
    enum Mode: Equatable { case full, light, still }

    struct State: Equatable {
        var theme: ArenaTableTheme
        var band: ArenaWorldLife.Band
        var mode: Mode
        var resting: Bool
        var covered: Bool
        var hot: Bool
        var dread: CGFloat
    }

    private struct Patch {
        let layer: CAMetalLayer
        let flow: ArenaWorldSpec.Flow
        let kind: Float
        let tint: SIMD4<Float>
    }

    private static let railLine: CGFloat = 815.0 / 956.0
    private static let kinds = ["lava": 0, "water": 1, "fall": 2, "sway": 3, "haze": 4, "mist": 5, "wind": 6]

    private var state: State?
    private var built: (State, CGSize)?
    private let stage = CALayer()
    private var patches: [Patch] = []
    private var lights: [CALayer] = []
    private var emitters: [CAEmitterLayer] = []
    private var crows: [CALayer] = []
    private var surgeLayer: CALayer?
    private var dreadLayer: CALayer?
    private var textures: ArenaWorldTextures?
    private var link: CADisplayLink?
    private let ticker = ArenaWorldTick()
    /// One frame on the GPU at a time, so waiting for a drawable can never stall the board.
    private let frameFree = DispatchSemaphore(value: 1)
    private var clock: Double = 0
    private var last: CFTimeInterval = 0
    private var pace: Double = 1
    private var surge: Float = 0
    private var beat = 0
    private var rest: DispatchWorkItem?
    private static let settling: TimeInterval = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(stage)
        ticker.view = self
        NotificationCenter.default.addObserver(self, selector: #selector(leftScreen), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cameBack), name: UIApplication.willEnterForegroundNotification, object: nil)
        ArenaWorldEvents.shared.add(self)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not from a storyboard") }

    func apply(_ next: State) {
        let before = state
        state = next
        if before?.dread != next.dread { setDread(next.dread) }
        rebuildIfNeeded()
        if before?.resting != next.resting || before?.hot != next.hot { settle() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stage.frame = bounds
        rebuildIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        settle()
    }

    @objc private func leftScreen() { link?.isPaused = true }
    @objc private func cameBack() { settle() }

    private func rebuildIfNeeded() {
        guard let state, bounds.width > 0 else { return }
        if let built, built.1 == bounds.size, built.0.theme == state.theme, built.0.mode == state.mode, built.0.band == state.band { return }
        built = (state, bounds.size)
        stage.sublayers?.forEach { $0.removeFromSuperlayer() }
        patches = []; lights = []; emitters = []; crows = []; surgeLayer = nil; dreadLayer = nil; textures = nil
        link?.invalidate(); link = nil
        guard state.mode != .still, let spec = ArenaWorldSpec.all[state.theme.rawValue] else { return }
        let wide = bounds.width > bounds.height
        let scene = spec.scene(landscape: wide)
        let name = "arena-world-\(state.theme.rawValue)-\(wide ? "landscape" : "portrait")"
        let inBand: ([CGFloat]) -> Bool = { rect in
            let middle = rect[1] + rect[3] / 2
            return wide || (state.band == .rail) == (middle > Self.railLine)
        }
        let table = state.band == .table
        if table { addEdgeLayers(theme: state.theme) }
        let glow = ArenaWorldSprites.glow("\(name)-glow")
        if table && scene.cracks, let glow { addCracks(glow) }
        addLights(scene.lights.filter { inBand($0.rect) }, image: glow)
        guard state.mode == .full else { settle(); return }
        #if DEBUG
        startDemoIfAsked()
        #endif
        addPatches(scene.flows.filter { inBand($0.rect) }, plate: state.theme.plate(landscape: wide), mask: "\(name)-mask")
        addEmitters(scene.particles.filter { inBand($0.rect) })
        if table { addDrifters(scene.drifters) }
        settle()
    }

    #if DEBUG
    /// Visual QA: MAGICMOBILE_WORLD_DEMO=1 plays one of each reaction, again and again. =dread shows the low-life edge, and
    /// MAGICMOBILE_WORLD_CLOCK starts the flows that many seconds into a game.
    private func startDemoIfAsked() {
        let environment = ProcessInfo.processInfo.environment
        let demo = environment["MAGICMOBILE_WORLD_DEMO"]
        if let late = environment["MAGICMOBILE_WORLD_CLOCK"].flatMap(Double.init) { clock = late }
        if demo == "dread" { setDread(0.85) }
        if demo == "rest" { BoardActivity.shared.note() }
        guard demo == "1", state?.band == .table else { return }
        let events: [ArenaWorldEvent] = [.strike, .spell(big: true), .death, .hit(big: true), .wipe]
        for index in 0..<30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(index) * 2.6) { [weak self] in self?.react(events[index % events.count]) }
        }
    }
    #endif

    // MARK: Light

    private func frame(_ rect: [CGFloat]) -> CGRect {
        CGRect(x: rect[0] * bounds.width, y: rect[1] * bounds.height, width: rect[2] * bounds.width, height: rect[3] * bounds.height)
    }

    private func loop(_ values: [Double], over duration: Double, seed: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values + [values[0]]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = seed * duration
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 24, preferred: 20)
        return animation
    }

    private func curve(_ style: String, random: inout ArenaWorldRandom, power: Double) -> (values: [Double], duration: Double) {
        switch style {
        case "breathe":
            let steps = 14, phase = random.next() * 6.28
            return ((0..<steps).map { 0.42 * power * (1 + sin(Double($0) / Double(steps) * 6.283 + phase)) }, 5 + random.next() * 4)
        case "blink":
            return ([1, 1, 0.1, 0.05, 0.05, 0.05].map { $0 * power }, 2.4)
        case "lamp":
            // An old bulb: a slow hum, with a stutter now and then.
            var values = (0..<30).map { 0.5 * power * (1 + 0.28 * sin(Double($0) * 0.9) + 0.12 * random.next()) }
            for _ in 0..<2 {
                let at = Int(random.next() * 24)
                values[at] = 0.04; values[at + 1] = 0.85 * power; values[at + 2] = 0.12; values[at + 3] = 0.72 * power
            }
            return (values, 9 + random.next() * 4)
        default:
            // A flame: restless, with a dip now and then.
            let values = (0..<36).map { _ -> Double in
                let wobble = 0.35 + random.next() * 0.65
                return (random.next() < 0.1 ? wobble * 0.3 : wobble) * power
            }
            return (values, 4.5 + random.next() * 2.5)
        }
    }

    private func addCracks(_ image: CGImage) {
        let layer = CALayer()
        layer.frame = bounds
        layer.contents = image
        var random = ArenaWorldRandom(state: 7)
        let values = (0..<12).map { index in 0.32 + 0.3 * sin(Double(index) / 12 * 6.283) * (0.7 + random.next() * 0.3) }
        layer.add(loop(values, over: 7.5, seed: 0), forKey: "breathe")
        stage.addSublayer(layer)
        lights.append(layer)
    }

    private func addLights(_ list: [ArenaWorldSpec.Light], image: CGImage?) {
        var random = ArenaWorldRandom(state: 41)
        for light in list {
            let rect = frame(light.rect)
            let (values, duration) = curve(light.style, random: &random, power: Double(light.power))
            let seed = random.next()
            if let image {
                let shape = CALayer()
                shape.frame = rect
                shape.contents = image
                shape.contentsRect = CGRect(x: light.rect[0], y: light.rect[1], width: light.rect[2], height: light.rect[3])
                shape.add(loop(values, over: duration, seed: seed), forKey: "light")
                stage.addSublayer(shape)
                lights.append(shape)
            }
            if light.halo > 0 {
                let reach = max(rect.width, rect.height) * 1.25 * light.halo + 10
                let halo = CALayer()
                halo.frame = CGRect(x: rect.midX - reach, y: rect.midY - reach, width: reach * 2, height: reach * 2)
                halo.contents = ArenaWorldSprites.halo(light.colour)
                halo.add(loop(values.map { $0 * 0.75 }, over: duration, seed: seed), forKey: "light")
                stage.addSublayer(halo)
                lights.append(halo)
            }
        }
    }

    private func addEdgeLayers(theme: ArenaTableTheme) {
        let tone = ArenaWorldSprites.tone(theme)
        let pulse = CALayer()
        pulse.frame = bounds
        pulse.contents = ArenaWorldSprites.vignette(tone)
        pulse.opacity = 0
        stage.addSublayer(pulse)
        surgeLayer = pulse
        let dark = CALayer()
        dark.frame = bounds
        dark.contents = ArenaWorldSprites.vignette(UIColor.black)
        dark.opacity = Float(state?.dread ?? 0)
        stage.addSublayer(dark)
        dreadLayer = dark
    }

    private func setDread(_ value: CGFloat) {
        guard let dreadLayer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = dreadLayer.presentation()?.opacity ?? dreadLayer.opacity
        fade.toValue = Float(value)
        fade.duration = 2
        dreadLayer.opacity = Float(value)
        dreadLayer.add(fade, forKey: "dread")
    }

    // MARK: Flow

    private func addPatches(_ flows: [ArenaWorldSpec.Flow], plate: String, mask: String) {
        let gpu = ArenaWorldGPU.shared
        guard !flows.isEmpty, let device = gpu.device, gpu.pipeline != nil else { return }
        let scale = min(traitCollection.displayScale, 2)
        for flow in flows {
            guard let kind = Self.kinds[flow.kind] else { continue }
            let layer = CAMetalLayer()
            layer.device = device
            layer.pixelFormat = .bgra8Unorm
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.isOpaque = false
            layer.framebufferOnly = true
            layer.frame = frame(flow.rect).integral
            layer.contentsScale = scale
            layer.drawableSize = CGSize(width: layer.bounds.width * scale, height: layer.bounds.height * scale)
            stage.addSublayer(layer)
            patches.append(Patch(layer: layer, flow: flow, kind: Float(kind), tint: tint(flow.kind)))
        }
        gpu.textures(plate: plate, mask: mask) { [weak self] loaded in
            self?.textures = loaded
            self?.settle()
        }
    }

    private func tint(_ kind: String) -> SIMD4<Float> {
        switch (kind, state?.theme) {
        case ("fall", .volcano?): return [1, 0.72, 0.22, 1]
        case ("fall", _): return [0.95, 0.99, 1, 1]
        case ("water", _): return [0.85, 0.97, 1, 1]
        case ("mist", .volcano?): return [0.09, 0.07, 0.07, 1]
        case ("mist", .halloween?): return [0.42, 0.36, 0.62, 1]
        case ("mist", _): return [0.86, 0.84, 0.9, 1]
        default: return [1, 1, 1, 1]
        }
    }

    /// One clock for every patch. It runs only while there's a world to move. Going to rest, nothing new is born, and what's
    /// in the air finishes before the world stops, so embers never hang frozen.
    private func settle() {
        guard let state else { return }
        rest?.cancel()
        rest = nil
        let resting = state.resting || window == nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !resting { resume(stage) }
        for emitter in emitters { emitter.birthRate = resting ? 0 : (state.hot ? 0.5 : 1) }
        CATransaction.commit()
        guard !resting else {
            let stop = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pause(self.stage)
                self.link?.isPaused = true
            }
            rest = stop
            DispatchQueue.main.asyncAfter(deadline: .now() + (window == nil ? 0 : Self.settling), execute: stop)
            return
        }
        guard !patches.isEmpty, textures != nil else { link?.isPaused = true; return }
        if link == nil {
            let created = CADisplayLink(target: ticker, selector: #selector(ArenaWorldTick.step(_:)))
            created.add(to: .main, forMode: .common)
            link = created
        }
        link?.preferredFrameRateRange = state.hot ? CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
                                                  : CAFrameRateRange(minimum: 15, maximum: 24, preferred: 24)
        last = 0
        link?.isPaused = false
    }

    private func pause(_ layer: CALayer) {
        guard layer.speed != 0 else { return }
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
    }

    private func resume(_ layer: CALayer) {
        guard layer.speed == 0 else { return }
        let paused = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
    }

    fileprivate func step(_ link: CADisplayLink) {
        guard let textures, let queue = ArenaWorldGPU.shared.queue, let pipeline = ArenaWorldGPU.shared.pipeline,
              frameFree.wait(timeout: .now()) == .success else { return }
        guard let buffer = queue.makeCommandBuffer() else { frameFree.signal(); return }
        buffer.addCompletedHandler { [frameFree] _ in frameFree.signal() }
        let now = link.timestamp
        let delta = last == 0 ? 0 : min(now - last, 0.1)
        last = now
        // Flows ease to a stop on the way to rest, and ease back, so the world never halts mid-stride.
        pace += ((state?.resting == true ? 0 : 1) - pace) * min(delta / 1.2, 1)
        clock += delta * pace
        surge *= Float(exp(-delta / 0.7))
        let board = bounds.width > bounds.height ? SIMD2<Float>(956, 440) : SIMD2<Float>(440, 956)
        beat &+= 1
        for patch in patches where patch.kind < 3 || beat % 2 == 0 {
            guard let drawable = patch.layer.nextDrawable() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            let flow = patch.flow
            let rect = patch.layer.frame
            var uniforms = ArenaFlowUniforms(
                time: Float(clock.truncatingRemainder(dividingBy: 3600)), kind: patch.kind, speed: flow.speed, strength: flow.strength,
                seed: flow.seed, surge: surge, dir: SIMD2(flow.dir[0], flow.dir[1]), scale: board / 100, pixel: 1 / board,
                rect: SIMD4(Float(rect.minX / bounds.width), Float(rect.minY / bounds.height),
                            Float(rect.width / bounds.width), Float(rect.height / bounds.height)),
                tint: patch.tint)
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ArenaFlowUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ArenaFlowUniforms>.stride, index: 0)
            encoder.setFragmentTexture(textures.plate, index: 0)
            encoder.setFragmentTexture(textures.mask, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            buffer.present(drawable)
        }
        buffer.commit()
    }

    // MARK: Particles and drifters

    private func addEmitters(_ list: [ArenaWorldSpec.Emitter]) {
        for spec in list {
            let rect = frame(spec.rect)
            let emitter = CAEmitterLayer()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: rect.midX, y: rect.midY)
            emitter.emitterSize = rect.size
            emitter.emitterShape = .rectangle
            emitter.emitterMode = .surface
            emitter.renderMode = ["ember", "firefly"].contains(spec.kind) ? .additive : .unordered
            emitter.emitterCells = [ArenaWorldSprites.cell(spec.kind, rate: spec.rate)]
            stage.addSublayer(emitter)
            emitters.append(emitter)
        }
    }

    private func burst(_ strength: Float, for seconds: Double) {
        let hot = state?.hot == true
        for emitter in emitters { emitter.birthRate = (hot ? 0.5 : 1) * strength }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, let state = self.state else { return }
            for emitter in self.emitters { emitter.birthRate = state.resting ? 0 : (state.hot ? 0.5 : 1) }
        }
    }

    private func addDrifters(_ list: [ArenaWorldSpec.Drifter]) {
        var random = ArenaWorldRandom(state: 99)
        for drifter in list {
            let every = drifter.every ?? 30
            switch drifter.kind {
            case "cloud":
                for index in 0..<2 {
                    let layer = CALayer()
                    let size = CGSize(width: bounds.width * 1.1, height: bounds.height * 1.1)
                    layer.bounds = CGRect(origin: .zero, size: size)
                    layer.contents = ArenaWorldSprites.cloud
                    layer.opacity = drifter.opacity ?? 0.2
                    let travel = CAKeyframeAnimation(keyPath: "position")
                    let y = bounds.height * (0.2 + 0.6 * CGFloat(index))
                    travel.values = [CGPoint(x: -size.width * 0.6, y: y), CGPoint(x: bounds.width + size.width * 0.6, y: y + 40)]
                    travel.duration = every
                    travel.repeatCount = .infinity
                    travel.timeOffset = every * (0.3 + 0.5 * Double(index))
                    travel.isRemovedOnCompletion = false
                    travel.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
                    layer.add(travel, forKey: "travel")
                    stage.addSublayer(layer)
                }
            default:
                let shadow = drifter.kind == "birdshadow"
                for index in 0..<(shadow ? 3 : 4) {
                    let layer = bird(shadow: shadow, opacity: drifter.opacity ?? (shadow ? 0.3 : 0.92))
                    let start = CGPoint(x: -40, y: bounds.height * (0.12 + random.next() * 0.2 + Double(index) * 0.03))
                    let end = CGPoint(x: bounds.width + 40, y: bounds.height * (0.04 + random.next() * 0.25))
                    let flight = min(every * 0.5, shadow ? 9 : 7)
                    let travel = CAKeyframeAnimation(keyPath: "position")
                    let gap = CGFloat(index) * 26
                    travel.values = [CGPoint(x: start.x - gap, y: start.y + gap * 0.4), CGPoint(x: end.x - gap, y: end.y + gap * 0.4),
                                     CGPoint(x: end.x + 200, y: end.y)]
                    travel.keyTimes = [0, NSNumber(value: flight / every), 1]
                    travel.duration = every
                    travel.repeatCount = .infinity
                    travel.isRemovedOnCompletion = false
                    travel.timeOffset = every * 0.8
                    travel.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
                    layer.position = CGPoint(x: -200, y: -200)
                    layer.add(travel, forKey: "travel")
                    stage.addSublayer(layer)
                    crows.append(layer)
                }
            }
        }
    }

    private func bird(shadow: Bool, opacity: Float) -> CALayer {
        let layer = CALayer()
        let size: CGFloat = shadow ? 34 : 26
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.opacity = opacity
        let flap = CAKeyframeAnimation(keyPath: "contents")
        flap.values = ArenaWorldSprites.bird(shadow: shadow)
        flap.calculationMode = .discrete
        flap.duration = shadow ? 0.5 : 0.42
        flap.repeatCount = .infinity
        flap.isRemovedOnCompletion = false
        layer.add(flap, forKey: "flap")
        return layer
    }

    // MARK: Reactions

    /// A reaction wakes a resting world: `note()` ends the idle spell, and the board's next update starts it moving.
    func react(_ event: ArenaWorldEvent) {
        guard let state, state.mode != .still, !state.covered, state.band == .table || isPoke(event) else { return }
        BoardActivity.shared.note()
        switch event {
        case .strike: flash(lights: 0.55, edge: 0.3); kick(0.5); burst(2.5, for: 0.3)
        case .hit(let big): flash(lights: big ? 0.9 : 0.5, edge: big ? 0.6 : 0.32); kick(big ? 1 : 0.5); burst(big ? 4 : 2.5, for: 0.4)
        case .spell(let big): flash(lights: big ? 0.9 : 0.35, edge: big ? 0.45 : 0.14); kick(big ? 0.9 : 0.3); if big { burst(3, for: 0.5) }
        case .death: scatter(); flash(lights: 0.3, edge: 0.12); burst(2, for: 0.25)
        case .wipe:
            if state.theme == .radioNight { blackout() } else { flash(lights: 1.2, edge: 0.85) }
            kick(1.6); burst(6, for: 0.9); scatter()
        case .poke(let point): poke(point)
        }
    }

    private func isPoke(_ event: ArenaWorldEvent) -> Bool {
        if case .poke = event { return true }
        return false
    }

    private func kick(_ amount: Float) { surge = max(surge, amount) }

    private func flash(lights lift: Double, edge: Double) {
        let pop = CAKeyframeAnimation(keyPath: "opacity")
        pop.values = [0, lift, lift * 0.5, 0]
        pop.keyTimes = [0, 0.1, 0.4, 1]
        pop.duration = 0.9
        pop.isAdditive = true
        for light in lights { light.add(pop, forKey: "pop") }
        if let surgeLayer {
            let glow = CAKeyframeAnimation(keyPath: "opacity")
            glow.values = [0, edge, edge * 0.55, 0]
            glow.keyTimes = [0, 0.08, 0.35, 1]
            glow.duration = 1.2
            surgeLayer.add(glow, forKey: "pop")
        }
    }

    /// Radio Night's power fails for a moment, then stutters back.
    private func blackout() {
        let out = CAKeyframeAnimation(keyPath: "opacity")
        out.values = [0, -1, -1, -0.2, -1, 0]
        out.keyTimes = [0, 0.1, 0.45, 0.55, 0.7, 1]
        out.duration = 1.4
        out.isAdditive = true
        for light in lights { light.add(out, forKey: "pop") }
        if let dreadLayer {
            let dark = CAKeyframeAnimation(keyPath: "opacity")
            dark.values = [0, 0.7, 0.7, 0.3, 0.6, 0]
            dark.keyTimes = out.keyTimes
            dark.duration = 1.4
            dark.isAdditive = true
            dreadLayer.add(dark, forKey: "pop")
        }
    }

    /// Crows lift off together when something dies or falls.
    private func scatter() {
        guard state?.theme == .halloween else { return }
        var random = ArenaWorldRandom(state: UInt64(clock * 1000) + 3)
        for _ in 0..<5 {
            let crow = bird(shadow: false, opacity: 0.95)
            let start = CGPoint(x: bounds.width * (0.86 + random.next() * 0.1), y: bounds.height * (0.1 + random.next() * 0.2))
            let end = CGPoint(x: bounds.width * random.next(), y: -60)
            let path = UIBezierPath()
            path.move(to: start)
            path.addQuadCurve(to: end, controlPoint: CGPoint(x: (start.x + end.x) / 2, y: start.y + 20))
            let flight = CAKeyframeAnimation(keyPath: "position")
            flight.path = path.cgPath
            flight.duration = 2.2 + random.next()
            flight.beginTime = CACurrentMediaTime() + random.next() * 0.3
            flight.fillMode = .both
            crow.position = CGPoint(x: -200, y: -200)
            crow.add(flight, forKey: "flight")
            stage.addSublayer(crow)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { crow.removeFromSuperlayer() }
        }
    }

    /// A tap on a lit thing in a corner: light opens under the finger, what's near flares, and the corner stirs.
    private func poke(_ point: CGPoint) {
        guard let state, let spec = ArenaWorldSpec.all[state.theme.rawValue] else { return }
        let wide = bounds.width > bounds.height
        let scene = spec.scene(landscape: wide)
        let local = CGPoint(x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1))
        guard scene.hotspots.contains(where: { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]).contains(local) }) else { return }
        // Both bands hear a poke, and only the one that holds the point answers under the finger.
        if (state.band == .rail) == (!wide && local.y > Self.railLine) { bloom(at: point, theme: state.theme) }
        let reach = min(bounds.width, bounds.height) * 0.22
        let near = lights.filter { hypot($0.frame.midX - point.x, $0.frame.midY - point.y) < reach }
        let pop = CAKeyframeAnimation(keyPath: "opacity")
        pop.values = [0, 1.4, 0.3, 0.9, 0]
        pop.duration = 1
        pop.isAdditive = true
        for light in near { light.add(pop, forKey: "poke") }
        kick(0.8)
        burst(3, for: 0.3)
        if state.theme == .halloween { scatter() }
    }

    private func bloom(at point: CGPoint, theme: ArenaTableTheme) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        ArenaWorldSprites.tone(theme).getRed(&red, green: &green, blue: &blue, alpha: nil)
        let size = min(bounds.width, bounds.height) * 0.46
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.position = point
        layer.contents = ArenaWorldSprites.halo([red, green, blue])
        layer.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0.45, 0]
        fade.keyTimes = [0, 0.12, 0.4, 1]
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.55
        grow.toValue = 1.2
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let opening = CAAnimationGroup()
        opening.animations = [fade, grow]
        opening.duration = 0.9
        layer.add(opening, forKey: "bloom")
        stage.addSublayer(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { layer.removeFromSuperlayer() }
    }
}

/// The world's small pictures, drawn once.
@MainActor
enum ArenaWorldSprites {
    private static var cache: [String: CGImage] = [:]

    private static func drawn(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        if let image = cache[key] { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage
        cache[key] = image
        return image
    }

    private static func radial(_ context: CGContext, _ colours: [CGColor], _ stops: [CGFloat], _ size: CGSize) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: stops) else { return }
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: min(size.width, size.height) / 2, options: [])
    }

    /// A glow map, painted over black, as light that only adds: each pixel's alpha is its brightest channel, so laying it over
    /// the plate brightens it the way a screen blend would. (iOS doesn't blend a layer with a SwiftUI view behind it.)
    static func glow(_ name: String) -> CGImage? {
        if let image = cache[name] { return image }
        guard let source = UIImage(named: name)?.cgImage,
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        for offset in stride(from: 0, to: source.width * source.height * 4, by: 4) {
            pixels[offset + 3] = max(pixels[offset], pixels[offset + 1], pixels[offset + 2])
        }
        let image = context.makeImage()
        cache[name] = image
        return image
    }

    static func halo(_ colour: [CGFloat]) -> CGImage? {
        let key = "halo-\(colour.map { Int($0 * 8) })"
        let size = CGSize(width: 128, height: 128)
        return drawn(key, size) { context in
            let tone = UIColor(red: colour[0], green: colour[1], blue: colour[2], alpha: 1)
            radial(context, [tone.withAlphaComponent(0.55).cgColor, tone.withAlphaComponent(0.16).cgColor, tone.withAlphaComponent(0).cgColor], [0, 0.45, 1], size)
        }
    }

    static func tone(_ theme: ArenaTableTheme) -> UIColor {
        switch theme {
        case .volcano: UIColor(red: 1, green: 0.34, blue: 0.08, alpha: 1)
        case .halloween: UIColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1)
        case .utopia: UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1)
        default: UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1)
        }
    }

    /// Light or dark around the edges, nothing in the middle.
    static func vignette(_ tone: UIColor) -> CGImage? {
        let size = CGSize(width: 256, height: 256)
        return drawn("edge-\(tone.hash)", size) { context in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [tone.withAlphaComponent(0).cgColor, tone.withAlphaComponent(0.12).cgColor, tone.withAlphaComponent(0.8).cgColor] as CFArray,
                                            locations: [0.45, 0.75, 1]) else { return }
            let middle = CGPoint(x: 128, y: 128)
            context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: 181, options: [.drawsAfterEndLocation])
        }
    }

    static var cloud: CGImage? {
        let size = CGSize(width: 256, height: 256)
        return drawn("cloud", size) { context in
            var random = ArenaWorldRandom(state: 5)
            for _ in 0..<14 {
                let radius = 36 + random.next() * 44
                let middle = CGPoint(x: 60 + random.next() * 136, y: 60 + random.next() * 136)
                let box = CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2)
                context.saveGState()
                context.clip(to: box)
                let tone = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [tone.withAlphaComponent(0.34).cgColor, tone.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                    context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: radius, options: [])
                }
                context.restoreGState()
            }
        }
    }

    /// Three wing positions.
    static func bird(shadow: Bool) -> [CGImage] {
        (0..<3).compactMap { frame in
            let size = CGSize(width: 48, height: 48)
            return drawn("bird-\(shadow)-\(frame)", size) { context in
                let lift: CGFloat = [11, 2, -8][frame]
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 3, y: 24 - lift))
                path.addQuadCurve(to: CGPoint(x: 24, y: 25), controlPoint: CGPoint(x: 13, y: 16 - lift * 0.3))
                path.addQuadCurve(to: CGPoint(x: 45, y: 24 - lift), controlPoint: CGPoint(x: 35, y: 16 - lift * 0.3))
                path.addQuadCurve(to: CGPoint(x: 27, y: 31), controlPoint: CGPoint(x: 35, y: 25))
                path.addLine(to: CGPoint(x: 24, y: 37))
                path.addLine(to: CGPoint(x: 21, y: 31))
                path.addQuadCurve(to: CGPoint(x: 3, y: 24 - lift), controlPoint: CGPoint(x: 13, y: 25))
                path.close()
                let tone = shadow ? UIColor(red: 0.2, green: 0.12, blue: 0.08, alpha: 1) : UIColor(red: 0.03, green: 0.02, blue: 0.05, alpha: 1)
                context.setFillColor(tone.cgColor)
                if shadow {
                    // Only the blur lands on the sprite: the bird flies high, so its shadow has no edge.
                    context.setShadow(offset: CGSize(width: 96, height: 0), blur: 7, color: tone.cgColor)
                    context.translateBy(x: -96, y: 0)
                }
                context.addPath(path.cgPath)
                context.fillPath()
            }
        }
    }

    private static func shape(_ kind: String) -> CGImage? {
        let size = CGSize(width: 32, height: 32)
        return drawn("particle-\(kind)", size) { context in
            switch kind {
            case "leaf", "petal":
                let tones = kind == "leaf" ? UIColor(red: 0.78, green: 0.36, blue: 0.1, alpha: 1) : UIColor(red: 0.98, green: 0.72, blue: 0.82, alpha: 1)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 16, y: 2))
                path.addQuadCurve(to: CGPoint(x: 16, y: 30), controlPoint: CGPoint(x: 31, y: 15))
                path.addQuadCurve(to: CGPoint(x: 16, y: 2), controlPoint: CGPoint(x: 1, y: 15))
                context.setFillColor(tones.cgColor)
                context.addPath(path.cgPath)
                context.fillPath()
                context.setStrokeColor(tones.withAlphaComponent(0.5).cgColor)
                context.setBlendMode(.multiply)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: 16, y: 3))
                context.addLine(to: CGPoint(x: 16, y: 29))
                context.strokePath()
            case "ash":
                context.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: 10, y: 12, width: 12, height: 7))
            default:
                radial(context, [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0).cgColor], [0, 0.3, 1], size)
            }
        }
    }

    static func cell(_ kind: String, rate: Float) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = shape(kind)
        cell.birthRate = rate
        switch kind {
        case "ember":
            cell.color = UIColor(red: 1, green: 0.55, blue: 0.16, alpha: 1).cgColor
            cell.lifetime = 4.2; cell.lifetimeRange = 1.8
            cell.velocity = 30; cell.velocityRange = 16
            cell.emissionLongitude = -.pi / 2; cell.emissionRange = 0.7
            cell.yAcceleration = -9; cell.xAcceleration = 3
            cell.scale = 0.3; cell.scaleRange = 0.16; cell.scaleSpeed = -0.04
            cell.alphaSpeed = -0.17
            cell.redRange = 0.1; cell.greenRange = 0.2
        case "ash":
            cell.color = UIColor(white: 0.7, alpha: 0.55).cgColor
            cell.lifetime = 9; cell.lifetimeRange = 3
            cell.velocity = 7; cell.velocityRange = 5
            cell.emissionRange = .pi * 2
            cell.yAcceleration = 2.4; cell.xAcceleration = 1.6
            cell.scale = 0.26; cell.scaleRange = 0.16; cell.spin = 0.5; cell.spinRange = 1.6
            cell.alphaSpeed = -0.05
        case "leaf":
            cell.lifetime = 11; cell.lifetimeRange = 3
            cell.velocity = 34; cell.velocityRange = 18
            cell.emissionLongitude = 0.35; cell.emissionRange = 0.5
            cell.yAcceleration = 2; cell.xAcceleration = -1.5
            cell.scale = 0.36; cell.scaleRange = 0.16; cell.spin = 1.1; cell.spinRange = 2.2
            cell.redRange = 0.12; cell.greenRange = 0.16
            cell.alphaSpeed = -0.06
        case "petal":
            cell.lifetime = 11; cell.lifetimeRange = 3
            cell.velocity = 22; cell.velocityRange = 12
            cell.emissionLongitude = 0.5; cell.emissionRange = 0.7
            cell.yAcceleration = 3; cell.xAcceleration = 1
            cell.scale = 0.24; cell.scaleRange = 0.1; cell.spin = 1.3; cell.spinRange = 2.6
            cell.alphaSpeed = -0.05
        case "firefly":
            cell.color = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 0.9).cgColor
            cell.lifetime = 5; cell.lifetimeRange = 2
            cell.velocity = 9; cell.velocityRange = 7
            cell.emissionRange = .pi * 2
            cell.scale = 0.14; cell.scaleRange = 0.07
            cell.alphaRange = 0.4; cell.alphaSpeed = -0.16
        case "moth":
            cell.color = UIColor(red: 1, green: 0.9, blue: 0.72, alpha: 1).cgColor
            cell.lifetime = 2.6; cell.lifetimeRange = 1
            cell.velocity = 26; cell.velocityRange = 18
            cell.emissionRange = .pi * 2
            cell.scale = 0.11; cell.scaleRange = 0.05
            cell.alphaSpeed = -0.3
        default:              // Dust.
            cell.color = UIColor(red: 0.85, green: 0.8, blue: 0.9, alpha: 0.2).cgColor
            cell.lifetime = 9; cell.lifetimeRange = 3
            cell.velocity = 12; cell.velocityRange = 7
            cell.emissionLongitude = 0.1; cell.emissionRange = 0.9
            cell.scale = 0.12; cell.scaleRange = 0.08
            cell.alphaSpeed = -0.02
        }
        return cell
    }
}

extension NativeGameView {
    /// The world answers the game: each effect's moment, sent straight to the world's layers.
    func arenaWorldReactions(_ scheduled: [ScheduledBoardFX], viewerID: String?) {
        guard isArenaBoard, ArenaTableTheme.resolved(arenaTable) != .walnut else { return }
        var moments: [(at: TimeInterval, event: ArenaWorldEvent)] = []
        let leaving = scheduled.filter { if case .leftBattlefield = $0.event { return true } else { return false } }
        if leaving.count >= 3, let first = leaving.first { moments.append((first.delay, .wipe)) }
        for fx in scheduled {
            switch fx.event {
            case .combatStrike: moments.append((fx.delay, .strike))
            case .leftBattlefield where leaving.count < 3: moments.append((fx.delay, .death))
            case let .spellCast(_, _, _, _, weight) where weight != .ability:
                moments.append((fx.delay, .spell(big: weight == .big || weight == .commander)))
            case let .lifeChanged(id, delta) where delta < 0 && id == viewerID:
                moments.append((fx.delay, .hit(big: delta <= -5)))
            default: break
            }
        }
        for moment in moments.prefix(6) {
            DispatchQueue.main.asyncAfter(deadline: .now() + moment.at) {
                ArenaWorldEvents.shared.send(moment.event)
            }
        }
    }
}
