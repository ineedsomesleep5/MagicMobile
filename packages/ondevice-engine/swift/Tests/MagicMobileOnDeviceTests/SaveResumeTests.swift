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

    @Test func onDemandNeedsBothCapabilities() {
        #expect(EngineSaveResume.supportsOnDemand(.object(["saveResume": .bool(true), "checkpointOnDemand": .bool(true)])))
        // Today's shipped engines save at every decision and say only saveResume.
        #expect(!EngineSaveResume.supportsOnDemand(checkpointCapabilities))
        #expect(!EngineSaveResume.supportsOnDemand(.object(["saveResume": .bool(false), "checkpointOnDemand": .bool(true)])))
        #expect(!EngineSaveResume.supportsOnDemand(.object(["saveResume": .bool(true), "checkpointOnDemand": .string("true")])))
        #expect(!EngineSaveResume.supportsOnDemand(nil))
    }

    @Test func checkpointRequestShapeAndResults() async throws {
        let saved = JSONValue.object(["state": .string("saved"), "checkpoint": .object([
            "sequence": .integer(5), "savedAtMillis": .integer(1_790_000_000_000), "turn": .integer(7),
            "bytes": .integer(600_000), "writeMillis": .integer(41)])])
        let transport = SaveResumeTransport(result: saved)
        let client = EngineClient(transport: transport)
        #expect(try await client.requestCheckpoint(matchID: "match", waitMillis: 1000)
                == .saved(EngineCheckpoint(sequence: 5, savedAtMillis: 1_790_000_000_000, turn: 7, bytes: 600_000, writeMillis: 41)))
        try await client.cancelCheckpoint(matchID: "match")
        #expect(await transport.calls() == [
            .object(["protocol": .integer(1), "op": .string("checkpoint"), "matchId": .string("match"), "waitMillis": .integer(1000)]),
            .object(["protocol": .integer(1), "op": .string("cancelCheckpoint"), "matchId": .string("match")])
        ])

        #expect(try EngineCheckpointResult(.object(["state": .string("pending"), "waitingFor": .string("engine")])) == .waitingForEngine)
        #expect(try EngineCheckpointResult(.object(["state": .string("pending"), "waitingFor": .string("player")])) == .waitingForPlayer)
        #expect(try EngineCheckpointResult(.object(["state": .string("over")])) == .over)
        let failure = JSONValue.object(["code": .string("io"), "message": .string("disk full")])
        #expect(try EngineCheckpointResult(.object(["state": .string("failed"), "checkpointFailure": failure])) == .failed(failure))
        for malformed: JSONValue in [.object([:]), .object(["state": .string("saving")]),
                                     .object(["state": .string("pending"), "waitingFor": .string("host")]),
                                     .object(["state": .string("saved"), "checkpoint": .object(["sequence": .integer(1)])])] {
            #expect(throws: (any Error).self) { try EngineCheckpointResult(malformed) }
        }
    }

    @Test func checkpointRequestBoundsAreCheckedBeforeSending() async {
        let transport = SaveResumeTransport(result: .object([:]))
        let client = EngineClient(transport: transport)
        for (match, wait) in [("match", -1), ("match", 1001), ("", 0)] {
            await #expect(throws: (any Error).self) { try await client.requestCheckpoint(matchID: match, waitMillis: wait) }
        }
        await #expect(throws: (any Error).self) { try await client.cancelCheckpoint(matchID: "") }
        #expect(await transport.calls().isEmpty)
    }

    @Test func unavailableCheckpointCodesAreResultsOtherErrorsThrow() async throws {
        actor Rejecting: EngineTransport {
            let code: String
            init(_ code: String) { self.code = code }
            func request(_ data: Data) async throws -> Data {
                try JSONValue.object(["protocol": .integer(1), "ok": .bool(false),
                                      "error": .object(["code": .string(code), "message": .string("No")])]).encoded()
            }
        }
        for code in ["checkpoint_unavailable", "match_unavailable"] {
            #expect(try await EngineClient(transport: Rejecting(code)).requestCheckpoint(matchID: "m", waitMillis: 0)
                    == .unavailable(code: code))
        }
        await #expect(throws: EngineError.rejected(code: "invalid_request", message: "No")) {
            try await EngineClient(transport: Rejecting("invalid_request")).requestCheckpoint(matchID: "m", waitMillis: 0)
        }
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
        #expect(EngineCheckpoint(info)?.writeMillis == nil, "writeMillis is optional")
        // A malformed progress report never blocks the game update that carries it.
        let malformed = try MatchPoll(poll(checkpoint: .object(["sequence": .string("4")])))
        #expect(malformed.checkpoint == nil)
        #expect(malformed.revision == 3)
    }
}
