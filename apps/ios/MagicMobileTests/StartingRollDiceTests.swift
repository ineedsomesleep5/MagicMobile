import XCTest
import simd
@testable import MagicMobile

/// The starting roll's dice: the one landing rule (a recorded throw, turned by an icosahedral symmetry, ends
/// with the game's number on top), checked against the real assets from scripts/brand/d20.py.
final class StartingRollDiceTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MagicMobile/Resources/D20")

    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: Self.resources.appendingPathComponent(name)))
    }

    private func model() throws -> D20Model { try load("d20.json", as: D20Model.self) }
    private func bank() throws -> D20ThrowBank { try load("d20-throws.json", as: D20ThrowBank.self) }

    func testOppositeFacesSumToTwentyOneAndEveryNumberAppearsOnce() throws {
        let model = try model()
        XCTAssertEqual(model.faces.map(\.number).sorted(), Array(1...20))
        for face in model.faces {
            let opposite = model.faces.first { simd_dot($0.normalVector, face.normalVector) < -0.99 }
            XCTAssertEqual((opposite?.number ?? 0) + face.number, 21, "face \(face.number)")
        }
    }

    func testSymmetriesCarryTheDieOntoItself() throws {
        let model = try model()
        let vertices = model.vertices.map { SIMD3<Float>($0[0], $0[1], $0[2]) }
        for target in model.faces {
            for resting in model.faces {
                for k in 0..<3 {
                    let s = D20Landing.symmetry(model: model, from: target, to: resting, corner: k)
                    XCTAssertLessThan(simd_length(s.act(target.normalVector) - resting.normalVector), 1e-4)
                    for v in vertices {
                        let moved = s.act(v)
                        XCTAssertTrue(vertices.contains { simd_length($0 - moved) < 1e-4 }, "a symmetry must map every corner to a corner")
                    }
                }
            }
        }
    }

    func testEveryThrowEndsWithTheChosenNumberOnTop() throws {
        let model = try model(), bank = try bank()
        XCTAssertGreaterThanOrEqual(bank.recordings.count, 6)
        for recorded in bank.recordings {
            for number in 1...20 {
                let plan = D20ThrowPlan(model: model, recorded: recorded, number: number, jitter: D20Landing.jitter(round: number, seatIndex: 1, range: 0.2))
                let pose = plan.restPose
                let top = model.faces.max { simd_dot(pose.orientation.act($0.normalVector), SIMD3(0, 1, 0)) <
                    simd_dot(pose.orientation.act($1.normalVector), SIMD3(0, 1, 0)) }!
                XCTAssertEqual(top.number, number, "throw ending on face \(recorded.faceUp) should land \(number)")
                XCTAssertGreaterThan(simd_dot(pose.orientation.act(top.normalVector), SIMD3(0, 1, 0)), 0.9999, "the die lies flat")
                XCTAssertEqual(pose.position.y, model.inradius, accuracy: 1e-3, "and rests on the table")
            }
        }
    }

    func testTheSamePathServesEveryNumber() throws {
        let model = try model(), recorded = try bank().recordings[0]
        let a = D20ThrowPlan(model: model, recorded: recorded, number: 3)
        let b = D20ThrowPlan(model: model, recorded: recorded, number: 17)
        for t in stride(from: Float(0), through: a.duration, by: 0.1) {
            XCTAssertEqual(a.pose(at: t).position, b.pose(at: t).position, "only the labelling differs, never the motion")
        }
    }

    func testTheNumeralEndsNearlyUpright() throws {
        let model = try model(), bank = try bank()
        for recorded in bank.recordings {
            for number in [1, 6, 9, 14, 20] {
                let plan = D20ThrowPlan(model: model, recorded: recorded, number: number)
                let face = model.face(numbered: number)!
                var up = plan.restPose.orientation.act(face.corner(0))
                up.y = 0
                XCTAssertLessThan(abs(D20Landing.yaw(from: up, to: SIMD3(0, 0, -1))), 0.02, "the numeral reads away from the viewer")
            }
        }
    }

    func testEveryPoseOfEveryThrowIsFiniteAndOnTheTable() throws {
        let model = try model(), bank = try bank()
        for (index, recorded) in bank.recordings.enumerated() {
            for number in [1, 7, 12, 20] {
                let plan = D20ThrowPlan(model: model, recorded: recorded, number: number, origin: SIMD3(2.45, 0, -7.6), footprint: 0.7,
                                        jitter: 0.2)
                var t: Float = 0
                while t <= plan.duration + 0.05 {
                    let pose = plan.pose(at: t)
                    XCTAssertTrue(pose.position.x.isFinite && pose.position.y.isFinite && pose.position.z.isFinite, "throw \(index) t \(t)")
                    XCTAssertEqual(simd_length(pose.orientation.vector), 1, accuracy: 1e-3, "throw \(index) t \(t)")
                    XCTAssertGreaterThan(pose.position.y, model.inradius - 0.2, "throw \(index) t \(t) is below the table")
                    XCTAssertLessThan(pose.position.y, 8, "throw \(index) t \(t) is out of sight above")
                    XCTAssertLessThan(abs(pose.position.x - 2.45), 0.6)
                    XCTAssertLessThan(pose.position.z, 1.2, "the die stays this side of the middle of the mat")
                    t += 1.0 / 60
                }
            }
        }
    }

    func testThrowsStayInTheirLaneAndHitTheRailLow() throws {
        let bank = try bank()
        for recorded in bank.recordings {
            XCTAssertGreaterThan(recorded.railTime, 0.3)
            XCTAssertLessThan(recorded.railTime, recorded.duration)
            for frame in 0..<recorded.frames {
                XCTAssertLessThan(abs(recorded.position(at: frame).x), 0.4, "the die stays in its lane")
            }
            XCTAssertGreaterThan(recorded.position(at: recorded.frames - 1).z, 1.2, "and rests clear of the rail")
        }
    }

    func testLayoutPutsTheRailAtTheTopOfTheRollAreaAndSpacesLanes() {
        let input = D20TableLayout.Input(size: CGSize(width: 390, height: 844), region: CGRect(x: 18, y: 250, width: 354, height: 338),
                                         seatCount: 3, matSize: SIMD2(9.6, 15.2))
        let layout = D20TableLayout(input)
        XCTAssertEqual(layout.laneX.count, 3)
        XCTAssertEqual(layout.laneX[1], 0, accuracy: 1e-5)
        XCTAssertEqual(layout.laneX[2] - layout.laneX[1], layout.laneX[1] - layout.laneX[0], accuracy: 1e-5)
        XCTAssertEqual(layout.railZ, -7.6, accuracy: 1e-5)
        XCTAssertLessThanOrEqual(layout.footprint, 1)
        XCTAssertGreaterThanOrEqual(layout.footprint, 0.5)
        XCTAssertLessThan(layout.cameraForward.y, 0, "the camera looks down at the table")
        XCTAssertLessThan(layout.cameraForward.z, 0, "and away from the viewer")
        XCTAssertGreaterThan(layout.cameraPosition.y, 5)
        // Four seats get smaller dice than two.
        let four = D20TableLayout(.init(size: input.size, region: input.region, seatCount: 4, matSize: input.matSize))
        let two = D20TableLayout(.init(size: input.size, region: input.region, seatCount: 2, matSize: input.matSize))
        XCTAssertLessThan(four.pointsPerUnit, two.pointsPerUnit)
        XCTAssertEqual(four.laneX.count, 4)
    }

    func testPlatformsAgreeOnTheDeterministicJitter() {
        // The Kotlin port asserts the same numbers (StartingRollDiceTest).
        XCTAssertEqual(D20Landing.jitter(round: 0, seatIndex: 0, range: 1), 0.01317, accuracy: 1e-3)
        XCTAssertEqual(D20Landing.jitter(round: 1, seatIndex: 2, range: 1), 0.76104, accuracy: 1e-3)
        XCTAssertEqual(D20Landing.jitter(round: 3, seatIndex: 1, range: 1), -0.55721, accuracy: 1e-3)
        XCTAssertEqual(D20Landing.throwIndex(round: 0, seatIndex: 0, count: 12), 0)
        XCTAssertEqual(D20Landing.throwIndex(round: 1, seatIndex: 2, count: 12), 0)
        XCTAssertEqual(D20Landing.throwIndex(round: 0, seatIndex: 3, count: 12), 9)
    }

    func testTheDieModelReadsBack() throws {
        let glb = try D20GLB(data: Data(contentsOf: Self.resources.appendingPathComponent("d20.glb")))
        XCTAssertGreaterThan(glb.positions.count, 100)
        XCTAssertEqual(glb.indices.count % 3, 0)
        XCTAssertEqual(glb.normals.count, glb.positions.count)
        XCTAssertEqual(glb.uvs.count, glb.positions.count)
        XCTAssertEqual(glb.tangents.count, glb.positions.count)
        XCTAssertEqual(glb.images.count, 3)
        XCTAssertNotNil(glb.material.baseColorTexture)
        XCTAssertNotNil(glb.material.normalTexture)
        XCTAssertNotNil(glb.material.metallicRoughnessTexture)
        XCTAssertFalse(glb.material.unlit)
        let radius = glb.positions.map { simd_length($0) }.max() ?? 0
        XCTAssertEqual(radius, 1, accuracy: 0.05, "the die's circumradius is 1")
        for table in ["d20-table-portrait.glb", "d20-table-landscape.glb"] {
            let quad = try D20GLB(data: Data(contentsOf: Self.resources.appendingPathComponent(table)))
            XCTAssertEqual(quad.positions.count, 4)
            XCTAssertTrue(quad.material.unlit)
        }
        XCTAssertTrue(try D20GLB(data: Data(contentsOf: Self.resources.appendingPathComponent("d20-shadow.glb"))).material.blend)
    }
}
