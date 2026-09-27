import Foundation
import Testing
@testable import MagicMobileOnDevice

// TEST-ONLY engine boundary fixture. No XMage checkpoint is written or read here.
private actor SaveResumeTransport: EngineTransport {
    var recorded: [JSONValue] = []
    let result: JSONValue
    init(result: JSONValue) { self.result = result }
    func request(_ data: Data) async throws -> Data {
        recorded.append(try JSONValue.decode(data))
        return try JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
    func calls() -> [JSONValue] { recorded }
}

private func seat(_ id: String, _ controller: String) -> JSONValue {
    .object(["seatId": .string(id), "name": .string(id), "controller": .string(controller), "deck": .object([:])])
}

private let soloConfiguration = JSONValue.object(["seats": .array([seat("player1", "human"), seat("player2", "ai")])])
private let checkpointCapabilities = JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(true)])
private let oldCapabilities = JSONValue.object(["engine": .string("xmage"), "saveResume": .bool(false)])

private func poll(checkpoint: JSONValue?) -> JSONValue {
    var object: [String: JSONValue] = ["matchId": .string("match"), "viewerId": .string("player1"), "revision": .integer(3),
                                       "phase": .string("running"), "resyncRequired": .bool(false), "snapshot": .null, "prompt": .null]
    if let checkpoint { object["checkpoint"] = checkpoint }
    return .object(object)
}

@Suite("Save/resume engine boundary; not XMage checkpoint execution")
struct SaveResumeTests {
    @Test func capabilityMustBeExplicitlyTrue() {
        #expect(EngineSaveResume.isSupported(checkpointCapabilities))
        #expect(!EngineSaveResume.isSupported(oldCapabilities))
        #expect(!EngineSaveResume.isSupported(.object(["engine": .string("xmage")])))
        #expect(!EngineSaveResume.isSupported(.object(["saveResume": .string("true")])))
        #expect(!EngineSaveResume.isSupported(nil))
    }

    @Test func checkpointFieldAddedOnlyForSupportedSoloGames() throws {
        let configured = try EngineSaveResume.configuration(soloConfiguration, checkpointPath: "/data/Resume/game.checkpoint",
                                                            capabilities: checkpointCapabilities)
        #expect(configured["checkpoint"] == .object(["path": .string("/data/Resume/game.checkpoint")]))
        #expect(configured["seats"] == soloConfiguration["seats"])
        #expect(throws: (any Error).self) {
            try EngineSaveResume.configuration(soloConfiguration, checkpointPath: "/data/game.checkpoint", capabilities: oldCapabilities)
        }
        #expect(throws: (any Error).self) {
            try EngineSaveResume.configuration(soloConfiguration, checkpointPath: "relative/game.checkpoint", capabilities: checkpointCapabilities)
        }
        let table = JSONValue.object(["seats": .array([seat("player1", "human"), seat("player2", "human")])])
        #expect(throws: (any Error).self) {
            try EngineSaveResume.configuration(table, checkpointPath: "/data/game.checkpoint", capabilities: checkpointCapabilities)
        }
    }

    @Test func restoreRequestShape() async throws {
        let transport = SaveResumeTransport(result: .object([
            "matchId": .string("restored-match"),
            "restored": .object(["turn": .integer(12), "savedAtMillis": .integer(1_790_000_000_000)])
        ]))
        let restored = try await EngineClient(transport: transport).restore(checkpointPath: "/data/Resume/game.checkpoint",
                                                                            capabilities: checkpointCapabilities)
        #expect(restored.matchID == "restored-match")
        #expect(restored.turn == 12)
        #expect(restored.savedAtMillis == 1_790_000_000_000)
        let calls = await transport.calls()
        #expect(calls == [.object(["protocol": .integer(1), "op": .string("restore"),
                                   "checkpoint": .object(["path": .string("/data/Resume/game.checkpoint")])])])
    }

    @Test func restoreIsNeverSentToAnEngineWithoutSaveResume() async {
        let transport = SaveResumeTransport(result: .object([:]))
        await #expect(throws: (any Error).self) {
            try await EngineClient(transport: transport).restore(checkpointPath: "/data/game.checkpoint", capabilities: oldCapabilities)
        }
        await #expect(throws: (any Error).self) {
            try await EngineClient(transport: transport).restore(checkpointPath: "/data/game.checkpoint", capabilities: nil)
        }
        #expect(await transport.calls().isEmpty)
    }

    @Test func restoreErrorCodesPassThrough() async {
        actor Rejecting: EngineTransport {
            func request(_ data: Data) async throws -> Data {
                try JSONValue.object(["protocol": .integer(1), "ok": .bool(false),
                                      "error": .object(["code": .string(EngineSaveResume.incompatibleCode),
                                                        "message": .string("Different engine build")])]).encoded()
            }
        }
        await #expect(throws: EngineError.rejected(code: "checkpoint_incompatible", message: "Different engine build")) {
            try await EngineClient(transport: Rejecting()).restore(checkpointPath: "/data/game.checkpoint", capabilities: checkpointCapabilities)
        }
    }

    @Test func malformedRestoreResultFails() {
        #expect(throws: (any Error).self) { try EngineRestoredMatch(.object(["matchId": .string("m")])) }
        #expect(throws: (any Error).self) {
            try EngineRestoredMatch(.object(["matchId": .string(""), "restored": .object(["turn": .integer(1), "savedAtMillis": .integer(1)])]))
        }
    }

    @Test func pollCheckpointIsOptionalAndAdvisory() throws {
        #expect(try MatchPoll(poll(checkpoint: nil)).checkpoint == nil)
        let info = JSONValue.object(["sequence": .integer(4), "savedAtMillis": .integer(1_790_000_000_000),
                                     "turn": .integer(9), "bytes": .integer(584_000)])
        #expect(try MatchPoll(poll(checkpoint: info)).checkpoint
                == EngineCheckpoint(sequence: 4, savedAtMillis: 1_790_000_000_000, turn: 9, bytes: 584_000))
        // A malformed progress report never blocks the game update that carries it.
        let malformed = try MatchPoll(poll(checkpoint: .object(["sequence": .string("4")])))
        #expect(malformed.checkpoint == nil)
        #expect(malformed.revision == 3)
    }
}
