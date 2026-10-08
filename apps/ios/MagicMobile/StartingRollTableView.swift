import SceneKit
import SwiftUI
import UIKit

/// The shared dice assets (scripts/brand/d20.py): the die and tables as .glb, the face list and the
/// bank of recorded throws as JSON. Loaded once; nil when a build does not carry them.
final class D20Assets {
    static let shared: D20Assets? = D20Assets()

    let model: D20Model
    let bank: D20ThrowBank
    let die: D20GLB
    let shadow: D20GLB
    let glow: D20GLB
    private let tables: [Bool: D20GLB]

    private init?() {
        func url(_ name: String, _ ext: String) -> URL? { Bundle.main.url(forResource: name, withExtension: ext) }
        guard let modelURL = url("d20", "json"), let bankURL = url("d20-throws", "json"), let dieURL = url("d20", "glb"),
              let shadowURL = url("d20-shadow", "glb"), let glowURL = url("d20-glow", "glb"), let portraitURL = url("d20-table-portrait", "glb"),
              let landscapeURL = url("d20-table-landscape", "glb"),
              let model = try? JSONDecoder().decode(D20Model.self, from: Data(contentsOf: modelURL)),
              let bank = try? JSONDecoder().decode(D20ThrowBank.self, from: Data(contentsOf: bankURL)),
              let die = try? D20GLB(data: Data(contentsOf: dieURL)), let shadow = try? D20GLB(data: Data(contentsOf: shadowURL)),
              let glow = try? D20GLB(data: Data(contentsOf: glowURL)),
              let portrait = try? D20GLB(data: Data(contentsOf: portraitURL)),
              let landscape = try? D20GLB(data: Data(contentsOf: landscapeURL)), !bank.recordings.isEmpty else { return nil }
        self.model = model
        self.bank = bank
        self.die = die
        self.shadow = shadow
        self.glow = glow
        tables = [false: portrait, true: landscape]
    }

    func table(landscape: Bool) -> D20GLB { tables[landscape]! }

    /// The mat's size in die radii, from the table plates d20.py renders (portrait is tall).
    static func matSize(landscape: Bool) -> SIMD2<Float> { landscape ? SIMD2(15.2, 9.6) : SIMD2(9.6, 15.2) }
}

/// What the table should be showing right now. The roll's view owns this; the scene follows it.
struct D20TableState: Equatable {
    struct Throw: Equatable {
        let seatID: String
        let value: Int
        let turn: Int
    }

    /// Every seat in lane order, left to right.
    var seatOrder: [String]
    /// The roll round: a new round clears the table and throws different paths.
    var round: Int
    /// Dice at rest on the table, by seat.
    var resting: [String: Int]
    var throwing: Throw?
    /// The seat whose die glows (the winner, once the roll is over).
    var highlighted: String?
}

/// SceneKit scene of the tavern table with up to four dice on it. Dice are posed from recorded throws
/// (D20ThrowPlan); there is no physics in the app, so the result can never differ from the game's.
final class D20TableScene: NSObject {
    let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let tableRoot = SCNNode()
    private let diceRoot = SCNNode()
    private let assets: D20Assets
    private var tableLandscape: Bool?
    private var layout: D20TableLayout?
    private var layoutInput: D20TableLayout.Input?
    private var dice: [String: Die] = [:]
    private var lastTurn = 0
    private var animations: [String: Animation] = [:]
    private var dying: [(die: Die, start: CFTimeInterval)] = []
    private var link: CADisplayLink?
    private var renderOff: DispatchWorkItem?
    private var ticks = 0
    private var dieGeometry: SCNGeometry
    private var shadowGeometry: SCNGeometry
    private var glowGeometry: SCNGeometry
    weak var view: SCNView?
    var onEdgeHit: ((Int) -> Void)?
    var onRebound: ((Int) -> Void)?
    var onRest: ((Int) -> Void)?
    /// DEBUG fixtures: a line of scene state for an on-screen label (MAGICMOBILE_D20_DEBUG=1).
    var onDebug: ((String) -> Void)?

    private final class Die {
        let root = SCNNode()
        let body = SCNNode()
        let shadow = SCNNode()
        let glow = SCNNode()
        var value: Int
        var plan: D20ThrowPlan
        let seatIndex: Int
        let round: Int
        init(value: Int, plan: D20ThrowPlan, seatIndex: Int, round: Int) {
            self.value = value
            self.plan = plan
            self.seatIndex = seatIndex
            self.round = round
        }
    }

    private final class Animation {
        let seat: String
        let turn: Int
        let die: Die
        var plan: D20ThrowPlan { die.plan }
        var start: TimeInterval?
        var firedEdge = false
        var firedRebound = false
        init(seat: String, turn: Int, die: Die) {
            self.seat = seat
            self.turn = turn
            self.die = die
        }
    }

    init?(assets: D20Assets?) {
        guard let assets else { return nil }
        self.assets = assets
        dieGeometry = Self.dieGeometry(assets.die)
        shadowGeometry = Self.texturedQuad(assets.shadow, lit: false)
        glowGeometry = Self.texturedQuad(assets.glow, lit: false)
        super.init()
        scene.background.contents = UIColor(red: 0.09, green: 0.05, blue: 0.03, alpha: 1)
        scene.rootNode.addChildNode(tableRoot)
        scene.rootNode.addChildNode(diceRoot)
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(D20TableLayout.verticalFieldOfView * 180 / .pi)
        camera.projectionDirection = .vertical
        camera.zNear = 1
        camera.zFar = 400
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        buildLights()
    }

    // MARK: Scene content

    private func buildLights() {
        // One warm lamp up and to the left of the table (the table picture is lit the same way) and a dim room.
        let lamp = SCNNode()
        lamp.light = SCNLight()
        lamp.light?.type = .omni
        lamp.light?.color = UIColor(red: 1, green: 0.82, blue: 0.62, alpha: 1)
        lamp.light?.intensity = 1500
        lamp.position = SCNVector3(-7, 13, -2)
        scene.rootNode.addChildNode(lamp)
        let room = SCNNode()
        room.light = SCNLight()
        room.light?.type = .ambient
        room.light?.color = UIColor(red: 0.62, green: 0.42, blue: 0.30, alpha: 1)
        room.light?.intensity = 240
        scene.rootNode.addChildNode(room)
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 0.55
    }

    /// A small equirectangular room: dark walnut walls, a warm glow where the lamp hangs. It is what the
    /// resin and the gold numerals reflect.
    private static func environmentImage() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let sky = CGGradient(colorsSpace: space, colors: [UIColor(red: 0.42, green: 0.30, blue: 0.22, alpha: 1).cgColor,
                                                              UIColor(red: 0.30, green: 0.18, blue: 0.11, alpha: 1).cgColor,
                                                              UIColor(red: 0.08, green: 0.045, blue: 0.03, alpha: 1).cgColor] as CFArray,
                                 locations: [0, 0.5, 1])!
            cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let glow = CGGradient(colorsSpace: space, colors: [UIColor(red: 1, green: 0.86, blue: 0.62, alpha: 1).cgColor,
                                                               UIColor(red: 1, green: 0.7, blue: 0.4, alpha: 0).cgColor] as CFArray,
                                  locations: [0, 1])!
            cg.drawRadialGradient(glow, startCenter: CGPoint(x: 56, y: 24), startRadius: 0, endCenter: CGPoint(x: 56, y: 24),
                                  endRadius: 44, options: [])
        }
    }

    private static func image(_ data: Data?) -> UIImage? { data.flatMap(UIImage.init(data:)) }

    /// One mesh primitive as SceneKit geometry. glTF texture coordinates start at the top left and so do
    /// SceneKit's when the material's image is a UIImage, so they are used as they are (a flip puts every
    /// face on the wrong tile of the atlas).
    private static func geometry(_ glb: D20GLB) -> SCNGeometry {
        var sources = [
            SCNGeometrySource(vertices: glb.positions.map { SCNVector3($0.x, $0.y, $0.z) }),
            SCNGeometrySource(normals: glb.normals.map { SCNVector3($0.x, $0.y, $0.z) }),
            SCNGeometrySource(textureCoordinates: glb.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        ]
        if !glb.tangents.isEmpty {
            let data = glb.tangents.withUnsafeBytes { Data($0) }
            sources.append(SCNGeometrySource(data: data, semantic: .tangent, vectorCount: glb.tangents.count,
                                             usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                             dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride))
        }
        let element = SCNGeometryElement(indices: glb.indices, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    private static func dieGeometry(_ glb: D20GLB) -> SCNGeometry {
        let geometry = Self.geometry(glb)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image(glb.material.baseColorTexture.flatMap { glb.images[safe: $0] })
        material.normal.contents = image(glb.material.normalTexture.flatMap { glb.images[safe: $0] })
        let orm = image(glb.material.metallicRoughnessTexture.flatMap { glb.images[safe: $0] })
        material.roughness.contents = orm
        material.roughness.textureComponents = .green
        material.metalness.contents = orm
        material.metalness.textureComponents = .blue
        for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
            property.mipFilter = .linear
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            property.maxAnisotropy = 4
        }
        material.isDoubleSided = false
        geometry.materials = [material]
        return geometry
    }

    private static func texturedQuad(_ glb: D20GLB, lit: Bool) -> SCNGeometry {
        let geometry = Self.geometry(glb)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image(glb.material.baseColorTexture.flatMap { glb.images[safe: $0] })
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 8
        material.isDoubleSided = true
        if glb.material.blend {
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
        }
        geometry.materials = [material]
        return geometry
    }

    // MARK: Layout

    /// Fits the camera and lanes to the stage, and swaps the table picture for the orientation.
    func configure(size: CGSize, region: CGRect, seatCount: Int) {
        guard size.width > 0, size.height > 0 else { return }
        let landscape = size.width > size.height
        let region = region.width > 1 && region.height > 1 ? region : CGRect(x: 0, y: size.height * 0.2, width: size.width, height: size.height * 0.4)
        let input = D20TableLayout.Input(size: size, region: region, seatCount: seatCount, matSize: D20Assets.matSize(landscape: landscape))
        guard input != layoutInput else { return }
        layoutInput = input
        let layout = D20TableLayout(input)
        self.layout = layout
        if tableLandscape != landscape {
            tableLandscape = landscape
            tableRoot.childNodes.forEach { $0.removeFromParentNode() }
            let table = SCNNode(geometry: Self.texturedQuad(assets.table(landscape: landscape), lit: false))
            table.renderingOrder = -10
            tableRoot.addChildNode(table)
        }
        cameraNode.position = SCNVector3(layout.cameraPosition.x, layout.cameraPosition.y, layout.cameraPosition.z)
        let forward = layout.cameraForward
        cameraNode.look(at: SCNVector3(layout.cameraPosition.x + forward.x, layout.cameraPosition.y + forward.y,
                                       layout.cameraPosition.z + forward.z),
                        up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // The plans depend on the lanes and the throw's length: remake them and re-place everything.
        for (_, die) in dice {
            die.plan = makePlan(seatIndex: die.seatIndex, round: die.round, value: die.value, layout: layout)
            place(die)
        }
        requestRender()
    }

    // MARK: Following the state

    func apply(_ state: D20TableState, reduceMotion: Bool) {
        guard let layout else { return }
        let throwing = reduceMotion ? nil : state.throwing
        // Dice whose seats left the table, or whose value changed, go.
        for (seat, die) in dice where state.resting[seat] != die.value && throwing?.seatID != seat {
            remove(seat: seat, die: die, animated: !reduceMotion)
        }
        // A throw that is no longer wanted (Skip, Reduce Motion) ends at once, on its number.
        for (seat, animation) in animations where throwing?.seatID != seat {
            animations[seat] = nil
            let die = animation.die
            die.root.isHidden = false
            die.shadow.isHidden = false
            die.root.simdScale = SIMD3(repeating: 1)
            die.body.simdOrientation = die.plan.restPose.orientation
            place(die)
            let turn = animation.turn
            DispatchQueue.main.async { [weak self] in self?.onRest?(turn) }
        }
        for (seat, value) in state.resting where dice[seat] == nil && throwing?.seatID != seat {
            let die = makeDie(seat: seat, value: value, state: state, layout: layout)
            dice[seat] = die
            diceRoot.addChildNode(die.root)
            place(die)
            die.body.simdOrientation = die.plan.restPose.orientation
        }
        if let throwing, throwing.turn != lastTurn {
            lastTurn = throwing.turn
            if let old = dice[throwing.seatID] { remove(seat: throwing.seatID, die: old, animated: false) }
            let die = makeDie(seat: throwing.seatID, value: throwing.value, state: state, layout: layout)
            dice[throwing.seatID] = die
            diceRoot.addChildNode(die.root)
            die.root.isHidden = true
            die.shadow.isHidden = true
            animations[throwing.seatID] = Animation(seat: throwing.seatID, turn: throwing.turn, die: die)
            startLink()
        }
        for (seat, die) in dice {
            die.glow.isHidden = state.highlighted != seat
            die.glow.opacity = state.highlighted == seat ? 1 : 0
        }
        requestRender()
    }

    /// A seat's throw for this round, laid out in its lane. Which recording it gets depends only on the round and
    /// the seat, so a die's resting pose never changes when the layout does.
    private func makePlan(seatIndex: Int, round: Int, value: Int, layout: D20TableLayout) -> D20ThrowPlan {
        let bank = assets.bank
        let pick = bank.recordings[D20Landing.throwIndex(round: round, seatIndex: seatIndex, count: bank.recordings.count)]
        let lane = layout.laneX[min(seatIndex, layout.laneX.count - 1)]
        return D20ThrowPlan(model: assets.model, recorded: pick, number: value,
                            origin: SIMD3(lane, 0, layout.railZ), footprint: layout.footprint,
                            jitter: D20Landing.jitter(round: round, seatIndex: seatIndex, range: 0.2))
    }

    private func makeDie(seat: String, value: Int, state: D20TableState, layout: D20TableLayout) -> Die {
        let seatIndex = state.seatOrder.firstIndex(of: seat) ?? 0
        let die = Die(value: value, plan: makePlan(seatIndex: seatIndex, round: state.round, value: value, layout: layout),
                      seatIndex: seatIndex, round: state.round)
        die.body.geometry = dieGeometry
        die.root.addChildNode(die.body)
        let shadow = SCNNode(geometry: shadowGeometry)
        shadow.renderingOrder = -5
        die.shadow.addChildNode(shadow)
        scene.rootNode.addChildNode(die.shadow)
        die.glow.geometry = glowGeometry
        die.glow.renderingOrder = -6
        die.glow.isHidden = true
        scene.rootNode.addChildNode(die.glow)
        return die
    }

    /// Puts a die and its soft shadow and halo at its resting place.
    private func place(_ die: Die) {
        let pose = die.plan.restPose
        die.root.simdPosition = pose.position
        die.shadow.simdPosition = SIMD3(pose.position.x + 0.35, 0.02, pose.position.z + 0.35)
        die.glow.simdPosition = SIMD3(pose.position.x, 0.03, pose.position.z)
        die.shadow.opacity = 0.75
        die.shadow.simdScale = SIMD3(repeating: 0.9)
    }

    private func remove(seat: String, die: Die, animated: Bool) {
        dice[seat] = nil
        animations[seat] = nil
        if animated {
            dying.append((die, CACurrentMediaTime()))
            startLink()
        } else {
            [die.root, die.shadow, die.glow].forEach { $0.removeFromParentNode() }
        }
    }

    // MARK: Frames

    /// A display link runs only while a die is in the air or leaving; poses come from the recording and the
    /// clock, never from SceneKit's own animation loop, so a die is always where its throw says.
    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        view?.rendersContinuously = true
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        requestRender()
    }

    /// Draws a few frames after any change, then lets the view go back to sleep.
    private func requestRender() {
        view?.rendersContinuously = true
        renderOff?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.link == nil else { return }
            self.view?.rendersContinuously = false
        }
        renderOff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func shutdown() {
        link?.invalidate()
        link = nil
        renderOff?.cancel()
    }

    @objc private func tick(_ link: CADisplayLink) {
        advance(link.timestamp)
        if animations.isEmpty && dying.isEmpty { stopLink() }
    }

    private func advance(_ now: CFTimeInterval) {
        ticks += 1
        if let onDebug, ticks % 15 == 1 {
            let lines = animations.values.map { a in
                String(format: "%@ hid=%d pos=(%.1f,%.1f,%.1f)", a.seat, a.die.root.isHidden ? 1 : 0, a.die.root.simdPosition.x,
                       a.die.root.simdPosition.y, a.die.root.simdPosition.z)
            }
            onDebug("tick \(ticks) anim \(animations.count) dice \(dice.count)\n" + lines.joined(separator: "\n"))
        }
        var finished: [Animation] = []
        for animation in animations.values {
            let die = animation.die
            let start = animation.start ?? now
            animation.start = start
            let t = Float(now - start)
            let plan = animation.plan
            let pose = plan.pose(at: t)
            die.root.isHidden = false
            die.shadow.isHidden = false
            die.root.simdPosition = pose.position
            die.body.simdOrientation = pose.orientation
            let appear = min(1, t / 0.12)
            die.root.simdScale = SIMD3(repeating: 0.5 + 0.5 * appear)
            // The soft shadow slides away from the lamp and fades as the die rises.
            let height = max(pose.position.y - plan.model.inradius, 0)
            die.shadow.simdPosition = SIMD3(pose.position.x + 0.35 + height * 0.55, 0.02, pose.position.z + 0.35 + height * 0.55)
            die.shadow.simdScale = SIMD3(repeating: (1 + height * 0.5) * 0.9)
            die.shadow.opacity = CGFloat(max(0.15, 0.75 - height * 0.22) * appear)
            die.glow.simdPosition = SIMD3(pose.position.x, 0.03, pose.position.z)
            if !animation.firedEdge, t >= plan.railTime {
                animation.firedEdge = true
                onEdgeHit?(animation.turn)
            }
            if !animation.firedRebound, t >= plan.railTime + 0.3 {
                animation.firedRebound = true
                onRebound?(animation.turn)
            }
            if t >= plan.duration { finished.append(animation) }
        }
        for animation in finished {
            animations[animation.seat] = nil
            place(animation.die)
            animation.die.root.simdScale = SIMD3(repeating: 1)
            animation.die.body.simdOrientation = animation.plan.restPose.orientation
            onRest?(animation.turn)
        }
        // Dice that leave the table shrink and fade, then go.
        var staying: [(die: Die, start: CFTimeInterval)] = []
        for entry in dying {
            let t = Float((now - entry.start) / 0.22)
            if t >= 1 {
                [entry.die.root, entry.die.shadow, entry.die.glow].forEach { $0.removeFromParentNode() }
            } else {
                entry.die.root.simdScale = SIMD3(repeating: 1 - 0.4 * t)
                entry.die.shadow.opacity = CGFloat(0.75 * (1 - t))
                entry.die.glow.isHidden = true
                staying.append(entry)
            }
        }
        dying = staying
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The table behind the starting roll, as a SwiftUI view: transparent to touches and to VoiceOver.
struct D20TableView: UIViewRepresentable {
    let size: CGSize
    let region: CGRect
    let state: D20TableState
    let reduceMotion: Bool
    var onEdgeHit: ((Int) -> Void)?
    var onRebound: ((Int) -> Void)?
    var onRest: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let scene = D20TableScene(assets: D20Assets.shared)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 0.09, green: 0.05, blue: 0.03, alpha: 1)
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        // Nothing animates while the dice are at rest: the table only renders when its content changes.
        view.rendersContinuously = false
        view.isPlaying = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        if let table = context.coordinator.scene {
            view.scene = table.scene
            view.pointOfView = table.scene.rootNode.childNodes.first { $0.camera != nil }
            table.view = view
            #if DEBUG
            if ProcessInfo.processInfo.environment["MAGICMOBILE_D20_DEBUG"] == "1" {
                let label = UILabel(frame: CGRect(x: 6, y: 300, width: 378, height: 96))
                label.numberOfLines = 0
                label.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
                label.textColor = .yellow
                label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                view.addSubview(label)
                table.onDebug = { [weak label] text in label?.text = text }
            }
            #endif
        }
        return view
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.scene?.shutdown()
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let table = context.coordinator.scene else { return }
        table.onEdgeHit = onEdgeHit
        table.onRebound = onRebound
        table.onRest = onRest
        table.configure(size: size, region: region, seatCount: state.seatOrder.count)
        table.apply(state, reduceMotion: reduceMotion)
    }
}
