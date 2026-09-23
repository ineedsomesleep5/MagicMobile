import SceneKit
import SwiftUI
import UIKit

/// A presentation of authoritative starting-roll data. The match coordinator owns
/// the dice values, tie rounds, and winner; this view only plays them back.
struct MultiplayerD20View: View {
    let roll: OnDeviceStartingRoll
    let seatNames: [String: String]
    let isLocalWinner: Bool
    let revealedStepCount: Int
    let localSeatID: String?
    let rollPending: Bool
    let onRollTap: () -> Void
    let onStepPlayed: () -> Void
    let onDismiss: () -> Void

    init(roll: OnDeviceStartingRoll, seatNames: [String: String], isLocalWinner: Bool,
         revealedStepCount: Int, localSeatID: String?, rollPending: Bool = false,
         onRollTap: @escaping () -> Void, onStepPlayed: @escaping () -> Void = {},
         onDismiss: @escaping () -> Void) {
        self.roll = roll
        self.seatNames = seatNames
        self.isLocalWinner = isLocalWinner
        self.revealedStepCount = revealedStepCount
        self.localSeatID = localSeatID
        self.rollPending = rollPending
        self.onRollTap = onRollTap
        self.onStepPlayed = onStepPlayed
        self.onDismiss = onDismiss
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var dieFlight
    @State private var shownRoundIndex: Int?
    @State private var activeSeatID: String?
    @State private var activeValue: Int?
    @State private var settledRolls: [String: Int] = [:]
    @State private var landed = false
    @State private var revealFace = false
    @State private var diePosition: CGPoint?
    @State private var stageSize: CGSize = .zero
    @State private var edgeHitTurn: Int?
    @State private var reboundTurn: Int?
    @State private var playbackFinished = false
    @State private var spinTurns = 0
    @State private var skipAnimation = false
    @State private var playedStepCount = 0
    @State private var unlockedStepCount = 0
    @State private var didAutoDismiss = false

    private var rounds: [[String: Int]] { roll.rounds.map(\.rolls) }
    private var steps: [OnDeviceStartingRoll.Step] { roll.steps }
    private var playerIDs: [String] {
        (rounds.first.map { Array($0.keys) } ?? Array(seatNames.keys)).sorted()
    }

    private var playbackKey: PlaybackKey {
        PlaybackKey(seatNames: seatNames, rounds: rounds, winnerID: roll.winnerSeatID,
                    reduceMotion: reduceMotion, skipAnimation: skipAnimation)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width >= 560
            let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : (wide ? playerIDs.count : 2)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columnCount))
            ZStack {
                if activeSeatID != nil && !landed && !reduceMotion {
                    D20SceneView(value: revealFace ? activeValue : nil, turns: spinTurns,
                                 spinning: !revealFace,
                                 arenaSize: geometry.size,
                                 onEdgeHit: { turn in
                                     guard turn == spinTurns, edgeHitTurn != turn else { return }
                                     edgeHitTurn = turn
                                     UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                 },
                                 onRebound: { turn in
                                     guard turn == spinTurns else { return }
                                     reboundTurn = turn
                                 },
                                 onRest: { turn, point in
                                     guard turn == spinTurns else { return }
                                     diePosition = point
                                 })
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("multiplayerD20.physicsArena")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: wide ? 12 : 22) {
                        header
                        if !playbackFinished {
                            Color.clear
                                .frame(height: wide ? min(52, max(32, geometry.size.height * 0.12))
                                                    : min(360, max(250, geometry.size.height * 0.40)))
                                .accessibilityElement()
                                .accessibilityLabel("D20 roll area")
                                .accessibilityValue(reboundTurn == spinTurns
                                                    ? "Rebounded from screen edge"
                                                    : edgeHitTurn == spinTurns ? "Touched screen edge" : "Rolling")
                                .accessibilityIdentifier("multiplayerD20.rollArea")
                        }
                        resultAndRollControl(wide: wide)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(playerIDs, id: \.self) { playerID in
                                playerCard(playerID, compact: wide)
                            }
                        }
                    }
                    .frame(maxWidth: wide ? 900 : 620)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                    .padding(.horizontal, wide ? 24 : 20)
                }
                .scrollIndicators(.hidden)
                if landed, let seat = activeSeatID, let diePosition {
                    D20Face(value: activeValue, spinning: false, turns: 0,
                            emphasized: true, compact: false)
                        .frame(width: 138, height: 138)
                        .matchedGeometryEffect(id: "die-\(seat)", in: dieFlight)
                        .position(diePosition)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { stageSize = geometry.size }
            .onChange(of: geometry.size) { _, size in stageSize = size }
        }
        .onAppear { unlockedStepCount = min(revealedStepCount, steps.count) }
        .onChange(of: revealedStepCount) { _, count in unlockedStepCount = min(count, steps.count) }
        .task(id: playbackKey) { await playSuppliedRounds() }
    }

    private func resultAndRollControl(wide: Bool) -> some View {
        ZStack {
            if landed, let activeValue {
                Text("Rolled \(activeValue)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Palette.surface, in: Capsule())
                    .accessibilityIdentifier("multiplayerD20.result")
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else if let nextSeat = nextWaitingSeatID {
                if nextSeat == localSeatID {
                    Button(rollPending ? "Sharing your roll…" : "Tap to roll D20", action: onRollTap)
                        .buttonStyle(CommanderActionStyle())
                        .disabled(rollPending)
                        .accessibilityIdentifier("multiplayerD20.tapToRoll")
                } else {
                    Text("Waiting for \(seatNames[nextSeat] ?? "the next player") to roll…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("multiplayerD20.waiting")
                }
            }
        }
        .frame(maxWidth: wide ? 340 : 440)
        .frame(maxWidth: .infinity)
        .frame(height: wide ? 62 : 72)
    }

    private var nextWaitingSeatID: String? {
        guard activeSeatID == nil, !playbackFinished, playedStepCount == unlockedStepCount,
              steps.indices.contains(playedStepCount) else { return nil }
        return steps[playedStepCount].seatID
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STARTING ROLL")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Palette.accent)
            Text(headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            if !playbackFinished && !reduceMotion {
                Button("Skip animation") { skipAnimation = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 5)
                    .accessibilityIdentifier("multiplayerD20.skipAnimation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        if playbackFinished, let winnerName {
            return isLocalWinner ? "You go first" : "\(winnerName) goes first"
        }
        if let activeSeatID { return "\(seatNames[activeSeatID] ?? "Player") rolls" }
        if let nextWaitingSeatID {
            return nextWaitingSeatID == localSeatID ? "Your roll" : "\(seatNames[nextWaitingSeatID] ?? "Player")'s roll"
        }
        if let shownRoundIndex, shownRoundIndex > 0 { return "Tie. Roll again." }
        return "Who goes first?"
    }

    private var detail: String {
        guard let shownRoundIndex else {
            return nextWaitingSeatID == localSeatID
                ? "Tap to roll D20. Highest starts; ties reroll."
                : "Waiting for the next player to roll."
        }
        if playbackFinished, winnerName != nil { return "Round \(shownRoundIndex + 1) of \(rounds.count) · D20" }
        return "Round \(shownRoundIndex + 1) of \(rounds.count) · Highest roll starts. Ties reroll."
    }

    private var winnerName: String? {
        guard playerIDs.contains(roll.winnerSeatID) else { return nil }
        return seatNames[roll.winnerSeatID] ?? "Player"
    }

    private func playerCard(_ playerID: String, compact: Bool) -> some View {
        let name = seatNames[playerID] ?? "Player"
        let value = settledRolls[playerID]
        let isRolling = activeSeatID == playerID
        let isWinner = playbackFinished && roll.winnerSeatID == playerID
        let isOut = shownRoundIndex.map { $0 > 0 && rounds[$0][playerID] == nil && value != nil } ?? false

        return VStack(spacing: compact ? 7 : 10) {
            Group {
                if let value, !isRolling {
                    D20Face(value: value, spinning: false, turns: 0,
                            emphasized: isWinner, compact: true)
                        .matchedGeometryEffect(id: "die-\(playerID)", in: dieFlight)
                } else {
                    Image(systemName: "dice")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(Palette.secondary.opacity(0.7))
                }
            }
            .frame(width: compact ? 56 : 76, height: compact ? 56 : 76)
            .accessibilityHidden(true)

            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(status(for: playerID, value: value, isRolling: isRolling,
                        isOut: isOut, isWinner: isWinner))
                .font(.caption.weight(.medium))
                .foregroundStyle(isWinner ? Palette.accent : Palette.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 8 : 18)
        .padding(.horizontal, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isWinner ? Palette.accent : Palette.ink.opacity(0.12), lineWidth: isWinner ? 2 : 1))
        .opacity(isOut ? 0.65 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(for: playerID, name: name,
                                                     displayedValue: value, isRolling: isRolling,
                                                     isOut: isOut, isWinner: isWinner))
        .accessibilityIdentifier("multiplayerD20.seat.\(playerID)")
    }

    private func status(for playerID: String, value: Int?, isRolling: Bool,
                        isOut: Bool, isWinner: Bool) -> String {
        if isWinner, let value { return "Rolled \(value) · Goes first" }
        if isOut { return "Out of the reroll" }
        if isRolling { return "Rolling…" }
        guard let value else { return "Ready" }
        if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
           tiedLeaders(in: shownRoundIndex).contains(playerID) { return "Tied · reroll" }
        return "Rolled \(value)"
    }

    private func accessibilityDescription(for playerID: String, name: String, displayedValue: Int?,
                                          isRolling: Bool, isOut: Bool, isWinner: Bool) -> String {
        if isRolling { return "\(name) is rolling a twenty-sided die" }
        guard let displayedValue else { return "\(name), waiting to roll" }
        let suffix: String
        if isWinner { suffix = "goes first" }
        else if isOut { suffix = "out of the reroll" }
        else if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
                tiedLeaders(in: shownRoundIndex).contains(playerID) {
            suffix = "tied for highest; rerolling"
        } else { suffix = "result" }
        return "\(name) rolled \(displayedValue) on a twenty-sided die; \(suffix)"
    }

    private func tiedLeaders(in index: Int) -> Set<String> {
        guard rounds.indices.contains(index), let highest = rounds[index].values.max() else { return [] }
        let leaders = rounds[index].filter { $0.value == highest }
        return leaders.count > 1 ? Set(leaders.map(\.key)) : []
    }

    @MainActor
    private func playSuppliedRounds() async {
        guard !steps.isEmpty else {
            shownRoundIndex = nil
            activeSeatID = nil
            settledRolls = [:]
            playbackFinished = false
            playedStepCount = 0
            return
        }
        playbackFinished = false
        while playedStepCount < steps.count {
            guard !Task.isCancelled else { return }
            guard playedStepCount < unlockedStepCount else {
                try? await Task.sleep(for: .milliseconds(80))
                continue
            }
            let step = steps[playedStepCount]
            let seat = step.seatID
            let value = step.value
            shownRoundIndex = step.roundIndex
            if reduceMotion || skipAnimation {
                settledRolls[seat] = value
                activeSeatID = nil
                activeValue = nil
                landed = false
                revealFace = false
                diePosition = nil
                playedStepCount += 1
                onStepPlayed()
                continue
            }
            settledRolls.removeValue(forKey: seat)
            activeSeatID = seat
            activeValue = value
            landed = false
            revealFace = false
            diePosition = nil
            edgeHitTurn = nil
            reboundTurn = nil
            spinTurns += 1
            // Physics decides the path, never the result. Wait for a measurable
            // reverse trip from the wall, with a bounded recovery if rendering pauses.
            for _ in 0..<48 where reboundTurn != spinTurns {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            revealFace = true
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            if diePosition == nil {
                diePosition = CGPoint(x: stageSize.width / 2, y: stageSize.height * 0.40)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) { landed = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Give each player long enough to read the result before the die
            // flies into their square, including when VoiceOver is not active.
            try? await Task.sleep(for: .milliseconds(1900))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                settledRolls[seat] = value
                activeSeatID = nil
                landed = false
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            playedStepCount += 1
            onStepPlayed()
        }
        withAnimation(.easeOut(duration: 0.28)) { playbackFinished = true }
        await dismissAfterResult()
    }

    @MainActor
    private func dismissAfterResult() async {
        guard winnerName != nil else { return }
        try? await Task.sleep(for: .milliseconds(reduceMotion || skipAnimation ? 1200 : 1900))
        guard !Task.isCancelled, !didAutoDismiss else { return }
        didAutoDismiss = true
        onDismiss()
    }

    private struct PlaybackKey: Equatable {
        let seatNames: [String: String]
        let rounds: [[String: Int]]
        let winnerID: String?
        let reduceMotion: Bool
        let skipAnimation: Bool
    }

    private enum Palette {
        static let surface = Color(red: 31 / 255, green: 33 / 255, blue: 37 / 255)
        static let ink = Color(red: 243 / 255, green: 241 / 255, blue: 236 / 255)
        static let secondary = Color(red: 177 / 255, green: 178 / 255, blue: 182 / 255)
        static let accent = Color(red: 1, green: 128 / 255, blue: 88 / 255)
    }

    private struct D20Face: View {
        let value: Int?
        let spinning: Bool
        let turns: Int
        let emphasized: Bool
        let compact: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Group {
                if reduceMotion {
                    staticFace
                } else {
                    D20SceneView(value: value, turns: turns, spinning: spinning)
                }
            }
            .shadow(color: Palette.accent.opacity(emphasized ? 0.38 : 0.18), radius: 14, y: 8)
        }

        private var staticFace: some View {
            ZStack {
                DieOutline()
                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.95), Palette.accent.opacity(0.45),
                                                  Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                DieFacets().stroke(Palette.ink.opacity(0.28), lineWidth: 1)
                DieOutline().strokeBorder(Palette.ink.opacity(0.7), lineWidth: 1.5)
                Text(value.map(String.init) ?? "D20")
                    .font(.system(size: compact ? 25 : 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// A real icosahedron: 12 vertices, 20 flat-shaded triangular faces, and 30 edges.
    /// Each face is numbered. The chosen face is oriented toward the camera before
    /// the full-turn tumble, so SceneKit never selects or changes a game result.
    private struct D20SceneView: UIViewRepresentable {
        let value: Int?
        let turns: Int
        let spinning: Bool
        var arenaSize: CGSize? = nil
        var onEdgeHit: ((Int) -> Void)? = nil
        var onRebound: ((Int) -> Void)? = nil
        var onRest: ((Int, CGPoint) -> Void)? = nil

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> SCNView {
            let view = SCNView(frame: .zero)
            view.scene = context.coordinator.scene
            view.backgroundColor = .clear
            view.isOpaque = false
            view.allowsCameraControl = false
            view.isUserInteractionEnabled = false
            view.autoenablesDefaultLighting = false
            view.antialiasingMode = .multisampling4X
            view.preferredFramesPerSecond = 60
            // The traveling die needs a live physics renderer; settled dice in
            // player squares should not keep extra 60 fps scenes running.
            view.rendersContinuously = arenaSize != nil
            view.isPlaying = true
            view.delegate = context.coordinator
            view.accessibilityElementsHidden = true
            return view
        }

        func updateUIView(_ view: SCNView, context: Context) {
            context.coordinator.onEdgeHit = onEdgeHit
            context.coordinator.onRebound = onRebound
            context.coordinator.onRest = onRest
            if let arenaSize { context.coordinator.configureArena(size: arenaSize) }
            context.coordinator.present(value: value, turns: turns, spinning: spinning,
                                        arena: arenaSize != nil)
        }

        final class Coordinator: NSObject, SCNPhysicsContactDelegate, SCNSceneRendererDelegate {
            let scene = SCNScene()
            private let die = SCNNode()
            private let labels = SCNNode()
            private let camera = SCNNode()
            private var faceOrientations: [simd_quatf] = []
            private var lastValue: Int?
            private var lastTurns = 0
            private var arenaSize: CGSize = .zero
            private var arenaScale: CGFloat = 1
            private var arenaBounds: CGSize = .zero
            private var travelDirection: CGFloat = 1
            private var wallImpactX: Float?
            private var didCorrectBounce = false
            private var didReportRebound = false
            var onEdgeHit: ((Int) -> Void)?
            var onRebound: ((Int) -> Void)?
            var onRest: ((Int, CGPoint) -> Void)?

            private enum Collision {
                static let die = 1
                static let wall = 2
                static let table = 4
            }

            override init() {
                super.init()
                buildDie()
                scene.rootNode.addChildNode(die)

                let optics = SCNCamera()
                optics.usesOrthographicProjection = true
                optics.orthographicScale = 2.15
                camera.camera = optics
                camera.position = SCNVector3(0, 0, 30)
                scene.rootNode.addChildNode(camera)

                let key = SCNNode()
                key.light = SCNLight()
                key.light?.type = .omni
                key.light?.intensity = 900
                key.position = SCNVector3(-2, 3, 4)
                scene.rootNode.addChildNode(key)

                let fill = SCNNode()
                fill.light = SCNLight()
                fill.light?.type = .ambient
                fill.light?.intensity = 350
                scene.rootNode.addChildNode(fill)
                scene.background.contents = UIColor.clear
            }

            func configureArena(size: CGSize) {
                guard size.width > 0, size.height > 0, size != arenaSize else { return }
                arenaSize = size
                // Orthographic projection keeps the die the same physical screen
                // size in portrait and landscape, while the walls follow the view.
                let diePoints = min(138.0, max(108.0, size.width * 0.29))
                arenaScale = diePoints / 2
                let halfWidth = size.width / (2 * arenaScale)
                let halfHeight = size.height / (2 * arenaScale)
                arenaBounds = CGSize(width: halfWidth, height: halfHeight)
                camera.camera?.orthographicScale = Double(halfHeight)
                scene.physicsWorld.gravity = SCNVector3(0, 0, -17)
                scene.physicsWorld.timeStep = 1.0 / 60.0
                scene.physicsWorld.contactDelegate = self
                scene.rootNode.childNodes.filter { $0.name == "arenaBoundary" || $0.name == "sideWall" }
                    .forEach { $0.removeFromParentNode() }

                func boundary(name: String, width: CGFloat, height: CGFloat, depth: CGFloat,
                              at position: SCNVector3, category: Int,
                              restitution: CGFloat, friction: CGFloat) {
                    let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
                    let node = SCNNode()
                    node.name = name
                    node.position = position
                    let body = SCNPhysicsBody(type: .static,
                                              shape: SCNPhysicsShape(geometry: box, options: nil))
                    body.categoryBitMask = category
                    body.collisionBitMask = Collision.die
                    body.contactTestBitMask = name == "sideWall" ? Collision.die : 0
                    body.restitution = restitution
                    body.friction = friction
                    node.physicsBody = body
                    scene.rootNode.addChildNode(node)
                }
                let w = halfWidth, h = halfHeight
                boundary(name: "arenaBoundary", width: w * 2 + 4, height: h * 2 + 4, depth: 0.2,
                         at: SCNVector3(0, 0, -1.12), category: Collision.table,
                         restitution: 0.27, friction: 0.15)
                for x in [-w - 0.12, w + 0.12] {
                    boundary(name: "sideWall", width: 0.24, height: h * 2 + 4, depth: 8,
                             at: SCNVector3(x, 0, 1.6), category: Collision.wall,
                             restitution: 0.88, friction: 0.08)
                }
                for y in [-h - 0.12, h + 0.12] {
                    boundary(name: "arenaBoundary", width: w * 2 + 4, height: 0.24, depth: 8,
                             at: SCNVector3(0, y, 1.6), category: Collision.wall,
                             restitution: 0.78, friction: 0.08)
                }
            }

            func present(value: Int?, turns: Int, spinning: Bool, arena: Bool) {
                labels.isHidden = value == nil
                let resultChanged = value != lastValue
                let newTurn = turns != lastTurns
                guard resultChanged || newTurn else { return }
                lastValue = value
                lastTurns = turns
                die.removeAction(forKey: "tumble")
                if arena {
                    if newTurn && spinning { launch(turn: turns) }
                    else if let value, (1...20).contains(value) { reveal(value: value, turn: turns) }
                    return
                }
                if let value, (1...20).contains(value) {
                    die.simdOrientation = simd_inverse(faceOrientations[value - 1])
                } else {
                    die.simdOrientation = simd_quatf(angle: 0.55, axis: SIMD3<Float>(0, 1, 0))
                }
                guard newTurn && spinning else { return }
                // Integral full turns end at the same orientation as the supplied face.
                let tumble = SCNAction.rotateBy(x: .pi * 2, y: .pi * 4, z: .pi * 2, duration: 2.05)
                tumble.timingMode = .easeInEaseOut
                die.runAction(tumble, forKey: "tumble")
            }

            private func launch(turn: Int) {
                guard let geometry = die.geometry else { return }
                let direction: CGFloat = turn.isMultiple(of: 2) ? 1 : -1
                travelDirection = direction
                wallImpactX = nil
                didCorrectBounce = false
                didReportRebound = false
                die.simdOrientation = simd_quatf(angle: 0.48, axis: SIMD3<Float>(1, 1, 0.2))
                die.position = SCNVector3(-direction * (arenaBounds.width - 1.2),
                                          min(arenaBounds.height - 1.3, 0.7), 1.35)
                let body = SCNPhysicsBody(type: .dynamic,
                    shape: SCNPhysicsShape(geometry: geometry,
                                           options: [.type: SCNPhysicsShape.ShapeType.convexHull]))
                body.mass = 1
                body.categoryBitMask = Collision.die
                body.collisionBitMask = Collision.wall | Collision.table
                body.contactTestBitMask = Collision.wall
                body.restitution = 0.68
                body.friction = 0.16
                body.damping = 0.05
                body.angularDamping = 0.26
                die.physicsBody = body
                // Cross the available width in about a second; SceneKit handles
                // the table impact, edge contact, bounce, and subsequent spin.
                let travel = max(2.4, arenaBounds.width * 2 - 2.4)
                body.velocity = SCNVector3(direction * travel / 1.05, -0.32, -0.3)
                body.angularVelocity = SCNVector4(0.5, 0.9, 0.65, direction * 13)
            }

            private func reveal(value: Int, turn: Int) {
                die.physicsBody?.type = .kinematic
                let location = die.presentation.position
                let point = CGPoint(x: arenaSize.width / 2 + CGFloat(location.x) * arenaScale,
                                    y: arenaSize.height / 2 - CGFloat(location.y) * arenaScale)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.24
                die.simdOrientation = simd_inverse(faceOrientations[value - 1])
                SCNTransaction.commit()
                let settledPoint = CGPoint(x: min(max(74, point.x), arenaSize.width - 74),
                                           y: min(max(74, point.y), arenaSize.height - 110))
                DispatchQueue.main.async { [weak self] in self?.onRest?(turn, settledPoint) }
            }

            func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
                guard contact.nodeA.name == "sideWall" || contact.nodeB.name == "sideWall",
                      wallImpactX == nil else { return }
                wallImpactX = die.presentation.position.x
                let turn = lastTurns
                DispatchQueue.main.async { [weak self] in self?.onEdgeHit?(turn) }
            }

            func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
                guard let impact = wallImpactX, let body = die.physicsBody,
                      body.type == .dynamic else { return }
                // A faceted die can lose almost all normal velocity when it hits
                // wall and table at once. Preserve a modest reflected component
                // only in that case; the rest of the path remains physics-driven.
                if !didCorrectBounce {
                    let velocity = body.velocity
                    if CGFloat(velocity.x) * travelDirection > -1.8 {
                        let reverseSpeed = max(Float(1.8), abs(velocity.x) * Float(0.65))
                        let reverseX = Float(-travelDirection) * reverseSpeed
                        body.velocity = SCNVector3(reverseX, velocity.y, velocity.z)
                    }
                    didCorrectBounce = true
                }
                guard !didReportRebound,
                      CGFloat(die.presentation.position.x - impact) * travelDirection < -0.65 else { return }
                didReportRebound = true
                let turn = lastTurns
                DispatchQueue.main.async { [weak self] in self?.onRebound?(turn) }
            }

            private func buildDie() {
                let phi = Float((1 + sqrt(5.0)) / 2)
                let raw: [SIMD3<Float>] = [
                    [-1, phi, 0], [1, phi, 0], [-1, -phi, 0], [1, -phi, 0],
                    [0, -1, phi], [0, 1, phi], [0, -1, -phi], [0, 1, -phi],
                    [phi, 0, -1], [phi, 0, 1], [-phi, 0, -1], [-phi, 0, 1]
                ]
                let vertices = raw.map(simd_normalize)
                let faces: [[Int]] = [
                    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
                    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
                    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
                    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
                ]

                var positions: [SCNVector3] = []
                var normals: [SCNVector3] = []
                for (faceIndex, face) in faces.enumerated() {
                    let a = vertices[face[0]]
                    var b = vertices[face[1]]
                    var c = vertices[face[2]]
                    var normal = simd_normalize(simd_cross(b - a, c - a))
                    if simd_dot(normal, a + b + c) < 0 {
                        swap(&b, &c)
                        normal = -normal
                    }
                    for vertex in [a, b, c] {
                        positions.append(SCNVector3(vertex.x, vertex.y, vertex.z))
                        normals.append(SCNVector3(normal.x, normal.y, normal.z))
                    }
                    let basis = Self.faceBasis(normal)
                    faceOrientations.append(basis)

                    let text = SCNText(string: String(faceIndex + 1), extrusionDepth: 0.003)
                    text.font = UIFont.monospacedDigitSystemFont(ofSize: 1, weight: .bold)
                    text.flatness = 0.006
                    let ink = SCNMaterial()
                    ink.lightingModel = .constant
                    ink.diffuse.contents = UIColor(red: 243 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1)
                    ink.isDoubleSided = true
                    text.materials = [ink]
                    let textNode = SCNNode(geometry: text)
                    let bounds = text.boundingBox
                    textNode.position = SCNVector3(-(bounds.min.x + bounds.max.x) * 0.18,
                                                   -(bounds.min.y + bounds.max.y) * 0.18, 0)
                    textNode.scale = SCNVector3(0.36, 0.36, 0.36)
                    let faceNode = SCNNode()
                    faceNode.simdOrientation = basis
                    faceNode.simdPosition = (a + b + c) / 3 + normal * 0.025
                    faceNode.addChildNode(textNode)
                    labels.addChildNode(faceNode)
                }

                let shell = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                    elements: [SCNGeometryElement(indices: (0..<positions.count).map(UInt16.init),
                                                  primitiveType: .triangles)]
                )
                let enamel = SCNMaterial()
                enamel.lightingModel = .physicallyBased
                enamel.diffuse.contents = UIColor(red: 0.73, green: 0.31, blue: 0.13, alpha: 1)
                enamel.metalness.contents = 0.22
                enamel.roughness.contents = 0.35
                shell.materials = [enamel]
                die.geometry = shell

                // Draw each physical edge once, including on the back of the die.
                let edgeIDs = Set(faces.flatMap { face in
                    [(face[0], face[1]), (face[1], face[2]), (face[2], face[0])].map {
                        min($0.0, $0.1) * vertices.count + max($0.0, $0.1)
                    }
                })
                let edgeIndices: [UInt16] = edgeIDs.sorted().flatMap { id in
                    [UInt16(id / vertices.count), UInt16(id % vertices.count)]
                }
                let wire = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices.map {
                    SCNVector3($0.x, $0.y, $0.z)
                })], elements: [SCNGeometryElement(indices: edgeIndices, primitiveType: .line)])
                let metal = SCNMaterial()
                metal.lightingModel = .constant
                metal.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.46, alpha: 1)
                wire.materials = [metal]
                die.addChildNode(SCNNode(geometry: wire))
                die.addChildNode(labels)
            }

            private static func faceBasis(_ normal: SIMD3<Float>) -> simd_quatf {
                let vertical = SIMD3<Float>(0, 1, 0)
                let fallback = SIMD3<Float>(1, 0, 0)
                let reference = abs(simd_dot(normal, vertical)) > 0.95 ? fallback : vertical
                let up = simd_normalize(reference - normal * simd_dot(reference, normal))
                let right = simd_normalize(simd_cross(up, normal))
                return simd_quatf(simd_float3x3(columns: (right, simd_cross(normal, right), normal)))
            }
        }
    }

    private struct DieOutline: InsettableShape {
        var insetAmount: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let points: [CGPoint] = [
                CGPoint(x: 0.5, y: 0.02), CGPoint(x: 0.91, y: 0.23),
                CGPoint(x: 0.97, y: 0.65), CGPoint(x: 0.5, y: 0.98),
                CGPoint(x: 0.03, y: 0.65), CGPoint(x: 0.09, y: 0.23)
            ]
            let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
            var path = Path()
            for (index, point) in points.enumerated() {
                let position = CGPoint(x: bounds.minX + point.x * bounds.width,
                                       y: bounds.minY + point.y * bounds.height)
                if index == 0 { path.move(to: position) }
                else { path.addLine(to: position) }
            }
            path.closeSubpath()
            return path
        }

        func inset(by amount: CGFloat) -> DieOutline {
            var copy = self
            copy.insetAmount += amount
            return copy
        }
    }

    private struct DieFacets: Shape {
        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            path.move(to: point(0.5, 0.02))
            path.addLine(to: point(0.5, 0.27))
            path.addLine(to: point(0.09, 0.23))
            path.move(to: point(0.5, 0.27))
            path.addLine(to: point(0.91, 0.23))
            path.move(to: point(0.09, 0.23))
            path.addLine(to: point(0.19, 0.7))
            path.addLine(to: point(0.5, 0.98))
            path.move(to: point(0.91, 0.23))
            path.addLine(to: point(0.81, 0.7))
            path.addLine(to: point(0.5, 0.98))
            return path
        }
    }
}
