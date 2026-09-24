import Foundation
import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnDeviceMultiplayerTests: XCTestCase {
    func testSubmissionSchemaIsValidatedBeforeBuildMismatch() throws {
        let lobby = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice")
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let other = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue", adapterVersion: "other-build")
        let epoch = UUID()
        let valid: MagicMobileOnDevice.JSONValue = .object([
            "name": .string("Bob"), "deck": .object(["main": .array([]), "commanders": .array([])])
        ])
        let malformed: [MagicMobileOnDevice.JSONValue] = [
            .null, .string("Bob"), .object(["name": .string("Bob")]),
            .object(["name": .string("Bob"), "deck": .object(["main": .string("bad"), "commanders": .array([])])])
        ]
        for build in [identity, other] {
            var packet: [String: MagicMobileOnDevice.JSONValue] = [
                "type": .string("submission"), "epoch": .string(epoch.uuidString), "build": build.json,
                "roster": .array([.string("alice"), .string("bob")]), "aiSettings": lobby.aiSettings, "player": valid
            ]
            if build.json == identity.json {
                XCTAssertEqual(try lobby.verifyHandshake(.object(packet), from: "bob", identity: identity, epoch: epoch), epoch)
            } else {
                XCTAssertThrowsError(try lobby.verifyHandshake(.object(packet), from: "bob", identity: identity, epoch: epoch)) {
                    XCTAssertTrue($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                }
            }
            for player in malformed {
                packet["player"] = player
                XCTAssertThrowsError(try lobby.verifyHandshake(.object(packet), from: "bob", identity: identity, epoch: epoch)) {
                    XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                }
            }
        }
    }

    func testStartSchemaIsValidatedBeforeBuildMismatch() throws {
        var lobby = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "bob")
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let other = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue", adapterVersion: "other-build")
        let epoch = UUID()
        let offer: MagicMobileOnDevice.JSONValue = .object([
            "type": .string("offer"), "epoch": .string(epoch.uuidString), "build": identity.json,
            "roster": .array([.string("alice"), .string("bob")]), "aiSettings": lobby.aiSettings
        ])
        _ = try lobby.verifyHandshake(offer, from: "alice", identity: identity, epoch: nil)
        try lobby.acceptHostOffer(offer)
        var values = [8, 15]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: ["player1", "player2"]) { values.removeFirst() }
        for build in [identity, other] {
            var packet: [String: MagicMobileOnDevice.JSONValue] = [
                "type": .string("start"), "epoch": .string(epoch.uuidString), "build": build.json,
                "roster": .array([.string("alice"), .string("bob")]), "aiSettings": lobby.aiSettings,
                "matchId": .string(UUID().uuidString),
                "seatNames": .object(["player1": .string("Alice"), "player2": .string("Bob")]),
                "roll": try roll.encoded(seatIDs: ["player1", "player2"])
            ]
            if build.json == identity.json {
                XCTAssertEqual(try lobby.verifyHandshake(.object(packet), from: "alice", identity: identity, epoch: epoch), epoch)
            } else {
                XCTAssertThrowsError(try lobby.verifyHandshake(.object(packet), from: "alice", identity: identity, epoch: epoch)) {
                    XCTAssertTrue($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                }
            }
            let malformed: [MagicMobileOnDevice.JSONValue] = [.null, .integer(1), .string(""), .string("not-a-uuid")]
            for matchID in malformed {
                packet["matchId"] = matchID
                XCTAssertThrowsError(try lobby.verifyHandshake(.object(packet), from: "alice", identity: identity, epoch: epoch)) {
                    XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                }
            }
            packet["matchId"] = .string(UUID().uuidString)
            let badNames: [MagicMobileOnDevice.JSONValue] = [
                .object(["player1": .string("Alice")]),
                .object(["player1": .string("Alice"), "player2": .string("alice")]),
                .object(["player1": .string("Alice"), "player2": .string("Bob\n")])
            ]
            for names in badNames {
                packet["seatNames"] = names
                XCTAssertThrowsError(try lobby.verifyHandshake(.object(packet), from: "alice", identity: identity, epoch: epoch)) {
                    XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                }
            }
        }
    }

    func testOnlyAuthenticatedCurrentHandshakeReportsDifferentBuild() throws {
        let lobby = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob", "charlie"], localPeerID: "bob")
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID()
        let offer: MagicMobileOnDevice.JSONValue = .object([
            "type": .string("offer"), "epoch": .string(epoch.uuidString),
            "roster": .array(lobby.peerIDs.map(MagicMobileOnDevice.JSONValue.string)),
            "aiSettings": lobby.aiSettings,
            "build": BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue", adapterVersion: "other-build").json
        ])
        XCTAssertThrowsError(try lobby.verifyHandshake(offer, from: "alice", identity: identity, epoch: epoch)) {
            XCTAssertTrue($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
            XCTAssertTrue($0.localizedDescription.contains("same build"))
        }
        for peer in ["charlie", "unknown"] {
            XCTAssertThrowsError(try lobby.verifyHandshake(offer, from: peer, identity: identity, epoch: epoch)) {
                XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
            }
        }
        XCTAssertThrowsError(try lobby.verifyHandshake(offer, from: "alice", identity: identity, epoch: UUID())) {
            XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
        }
        var malformed = offer.object!
        malformed["build"] = .object(["protocolVersion": .string("bad")])
        XCTAssertThrowsError(try lobby.verifyHandshake(.object(malformed), from: "alice", identity: identity, epoch: epoch)) {
            XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
        }
    }

    func testAuthenticatedRosterDeterminesHostAndSeats() throws {
        let lobby = try OnDeviceMultiplayerLobby(peerIDs: ["charlie", "alice", "bob"], localPeerID: "bob")
        XCTAssertEqual(lobby.hostID, "alice")
        XCTAssertEqual(try lobby.seatID(for: "bob"), "player2")
        XCTAssertThrowsError(try lobby.seatID(for: "intruder"))
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby(peerIDs: ["alice", "alice"], localPeerID: "alice"))
    }

    func testMixedSeatsPreserveAuthenticatedHumansAndEngineSchema() throws {
        let deck: MagicMobileOnDevice.JSONValue = .object(["main": .array([]), "commanders": .array([])])
        for (humans, ais) in [(2, 1), (2, 2), (3, 1), (4, 0)] {
            let peers = Array(["dana", "alice", "charlie", "bob"].prefix(humans))
            let descriptors = (0..<ais).map { OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: $0 + 3) }
            var lobby = try OnDeviceMultiplayerLobby(peerIDs: peers, localPeerID: "alice", aiSeats: descriptors)
            XCTAssertFalse(lobby.isReady)
            XCTAssertThrowsError(try lobby.configuration())
            for peer in peers {
                try lobby.submit(.object(["name": .string(peer), "deck": deck]), from: peer)
            }
            XCTAssertTrue(lobby.isReady)
            let seats = try XCTUnwrap(lobby.configuration()["seats"]?.array)
            XCTAssertEqual(seats.count, humans + ais)
            XCTAssertEqual(lobby.seatNames.count, seats.count)
            for seat in seats {
                let seatID = try XCTUnwrap(seat["seatId"]?.string)
                XCTAssertEqual(seat["name"]?.string, lobby.seatNames[seatID])
            }
            for (index, peer) in lobby.peerIDs.enumerated() {
                XCTAssertEqual(seats[index]["seatId"]?.string, try lobby.seatID(for: peer))
                XCTAssertEqual(seats[index]["controller"]?.string, "human")
                XCTAssertNil(seats[index]["aiSkill"])
            }
            for index in 0..<ais {
                let seat = seats[humans + index]
                XCTAssertEqual(seat["seatId"]?.string, "player\(humans + index + 1)")
                XCTAssertEqual(seat["controller"]?.string, "ai")
                XCTAssertEqual(seat["deck"], deck)
                XCTAssertEqual(seat["aiSkill"]?.integer, Int64(index + 3))
            }
        }
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice",
            aiSeats: (0..<3).map { _ in OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 2) }))
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob", "charlie", "dana"], localPeerID: "alice",
            aiSeats: [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 2)]))
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice",
            aiSeats: [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 11)]))
    }

    func testDuplicateHumanAndBotNamesAreUniqueAndMatchEngineConfiguration() throws {
        let deck: MagicMobileOnDevice.JSONValue = .object(["main": .array([]), "commanders": .array([])])
        var lobby = try OnDeviceMultiplayerLobby(peerIDs: ["bob", "alice"], localPeerID: "alice",
            aiSeats: [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 2)])
        try lobby.submit(.object(["name": .string("AI 1"), "deck": deck]), from: "alice")
        try lobby.submit(.object(["name": .string("AI 1 (player1)"), "deck": deck]), from: "bob")
        let names = lobby.seatNames
        XCTAssertEqual(names["player1"], "AI 1 (player1)")
        XCTAssertEqual(names["player2"], "AI 1 (player1) (player2)")
        XCTAssertEqual(names["player3"], "AI 1 (player3)")
        XCTAssertEqual(Set(names.values).count, 3)
        let seats = try XCTUnwrap(lobby.configuration()["seats"]?.array)
        for seat in seats {
            let seatID = try XCTUnwrap(seat["seatId"]?.string)
            XCTAssertEqual(seat["name"]?.string, names[seatID])
        }

        var longNames = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice")
        let name = String(repeating: "A", count: 40)
        try longNames.submit(.object(["name": .string(name), "deck": deck]), from: "alice")
        try longNames.submit(.object(["name": .string(name), "deck": deck]), from: "bob")
        XCTAssertEqual(Set(longNames.seatNames.values).count, 2)
        XCTAssertTrue(longNames.seatNames.values.allSatisfy { $0.count <= 40 })
    }

    func testHandshakeRequiresEveryPeerToConfirmHostAIProposal() throws {
        let deck: MagicMobileOnDevice.JSONValue = .object(["main": .array([]), "commanders": .array([])])
        let expected = [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 4)]
        let host = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice", aiSeats: expected)
        var guest = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "bob",
            aiSeats: [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 5)])
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID()
        let shared: [String: MagicMobileOnDevice.JSONValue] = [
            "epoch": .string(epoch.uuidString), "build": identity.json,
            "roster": .array([.string("alice"), .string("bob")]), "aiSettings": host.aiSettings
        ]
        var offer = shared; offer["type"] = .string("offer")
        XCTAssertThrowsError(try guest.verifyHandshake(.object([
            "type": .string("start"), "epoch": .string(epoch.uuidString), "build": identity.json,
            "roster": shared["roster"]!, "aiSettings": host.aiSettings, "matchId": .string(UUID().uuidString),
            "seatNames": .object(["player1": .string("Alice"), "player2": .string("Bob"), "player3": .string("AI 1")])
        ]), from: "alice", identity: identity, epoch: epoch))
        XCTAssertEqual(try guest.verifyHandshake(.object(offer), from: "alice", identity: identity, epoch: nil), epoch)
        try guest.acceptHostOffer(.object(offer))
        XCTAssertEqual(guest.aiSettings, host.aiSettings)
        XCTAssertEqual(guest.hostAISeatSummary, "Host chose 1 AI seat: AI 1: selected deck, skill 4.")
        var submission = shared; submission["type"] = .string("submission")
        submission["player"] = .object(["name": .string("Bob"), "deck": deck])
        XCTAssertEqual(try host.verifyHandshake(.object(submission), from: "bob", identity: identity, epoch: epoch), epoch)
        var start = shared; start["type"] = .string("start"); start["matchId"] = .string(UUID().uuidString)
        start["seatNames"] = .object(["player1": .string("Alice"), "player2": .string("Bob"), "player3": .string("AI 1")])
        var values = [8, 15, 4]
        let roll = try OnDeviceStartingRoll.generate(seatIDs: ["player1", "player2", "player3"]) { values.removeFirst() }
        start["roll"] = try roll.encoded(seatIDs: ["player1", "player2", "player3"])
        XCTAssertEqual(try guest.verifyHandshake(.object(start), from: "alice", identity: identity, epoch: epoch), epoch)

        let wrong = try OnDeviceMultiplayerLobby.makeAISettings(
            seats: [OnDeviceMultiplayerAISeatDescriptor(deck: deck, skill: 5)], humanCount: 2)
        offer["aiSettings"] = wrong
        submission["aiSettings"] = wrong
        start["aiSettings"] = wrong
        for (packet, receiver, sender) in [(offer, guest, "alice"), (submission, host, "bob"), (start, guest, "alice")] {
            XCTAssertThrowsError(try receiver.verifyHandshake(.object(packet), from: sender, identity: identity, epoch: epoch)) {
                XCTAssertTrue($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
                XCTAssertTrue($0.localizedDescription.contains("AI settings"))
            }
        }
        var malformed = offer
        malformed["aiSettings"] = .object(["count": .integer(1), "seats": .array([])])
        XCTAssertThrowsError(try guest.verifyHandshake(.object(malformed), from: "alice", identity: identity, epoch: epoch)) {
            XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
        }
        malformed = offer; malformed["aiSettings"] = .object(["count": .integer(1), "seats": .array([
            .object(["deck": deck, "skill": .string("4")])
        ])])
        XCTAssertThrowsError(try guest.verifyHandshake(.object(malformed), from: "alice", identity: identity, epoch: epoch)) {
            XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
        }
        malformed = offer; malformed["aiSettings"] = .object(["count": .integer(1), "seats": .array([
            .object(["deck": .object(["main": .string("bad"), "commanders": .array([])]), "skill": .integer(4)])
        ])])
        XCTAssertThrowsError(try guest.verifyHandshake(.object(malformed), from: "alice", identity: identity, epoch: epoch)) {
            XCTAssertFalse($0 is OnDeviceMultiplayerLobby.HandshakeFailure)
        }
    }

    func testSubmissionCannotChooseAnotherSeatOrController() throws {
        var lobby = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob"], localPeerID: "alice")
        let deck: MagicMobileOnDevice.JSONValue = .object([
            "name": .string("Test"), "main": .array([]), "commanders": .array([]), "companions": .array([])
        ])
        let own: MagicMobileOnDevice.JSONValue = .object(["name": .string("Alice"), "deck": deck])
        var stolen = own.object!
        stolen["seatId"] = .string("player1")
        XCTAssertThrowsError(try lobby.submit(.object(stolen), from: "bob"))
        XCTAssertThrowsError(try lobby.submit(own, from: "unknown"))
        try lobby.submit(own, from: "alice")
        try lobby.submit(.object(["name": .string("Bob"), "deck": deck]), from: "bob")
        let seats = try lobby.configuration()["seats"]!.array!
        XCTAssertEqual(seats[1]["seatId"]?.string, "player2")
        XCTAssertEqual(seats[1]["controller"]?.string, "human")
        XCTAssertEqual(seats[1]["name"]?.string, "Bob")
    }

    func testHandshakeRejectsChangedBuildRosterAndEpoch() throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID()
        let lobby = try OnDeviceMultiplayerLobby(peerIDs: ["alice", "bob", "charlie"], localPeerID: "bob")
        let offer: MagicMobileOnDevice.JSONValue = .object(["type": .string("offer"), "epoch": .string(epoch.uuidString),
            "build": identity.json, "roster": .array([.string("alice"), .string("bob"), .string("charlie")]),
            "aiSettings": lobby.aiSettings])
        XCTAssertEqual(try lobby.verifyHandshake(offer, from: "alice", identity: identity, epoch: nil), epoch)
        XCTAssertThrowsError(try lobby.verifyHandshake(offer, from: "charlie", identity: identity, epoch: nil))
        XCTAssertThrowsError(try lobby.verifyHandshake(offer, from: "alice", identity: identity, epoch: UUID()))
        var wrong = offer.object!; wrong["build"] = BuildIdentity(upstreamCommit: "new", catalogueHash: "catalogue").json
        XCTAssertThrowsError(try lobby.verifyHandshake(.object(wrong), from: "alice", identity: identity, epoch: nil))
        wrong = offer.object!; wrong["roster"] = .array([.string("alice"), .string("bob")])
        XCTAssertThrowsError(try lobby.verifyHandshake(.object(wrong), from: "alice", identity: identity, epoch: nil))
        wrong = offer.object!; wrong["peerID"] = .string("alice")
        XCTAssertThrowsError(try lobby.verifyHandshake(.object(wrong), from: "alice", identity: identity, epoch: nil))
    }

    func testLobbyBoundsUntrustedDeckAndNameWithoutReplacingEngineLegality() throws {
        let row: MagicMobileOnDevice.JSONValue = .object(["name": .string("Plains"), "setCode": .string("M21"),
            "collectorNumber": .string("260"), "count": .integer(99)])
        let deck: MagicMobileOnDevice.JSONValue = .object(["main": .array([row]), "commanders": .array([])])
        // Empty commanders reaches the native validator; this layer only enforces transport/resource constraints.
        try OnDeviceMultiplayerLobby.validateSubmission(.object(["name": .string("Alice"), "deck": deck]))
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby.validateSubmission(.object(["name": .string("A\nB"), "deck": deck])))
        var malicious = row.object!; malicious["javaClass"] = .string("arbitrary.Class")
        var changed = deck.object!; changed["main"] = .array([.object(malicious)])
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby.validateSubmission(.object(["name": .string("Alice"), "deck": .object(changed)])))
        malicious = row.object!; malicious["count"] = .integer(2001)
        changed["main"] = .array([.object(malicious)])
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby.validateSubmission(.object(["name": .string("Alice"), "deck": .object(changed)])))
        changed = deck.object!; changed["name"] = .string(String(repeating: "x", count: 65_536))
        XCTAssertThrowsError(try OnDeviceMultiplayerLobby.validateSubmission(.object(["name": .string("Alice"), "deck": .object(changed)])))
    }

    @MainActor
    func testWrongPeerAndWrongCorrelationCannotCompleteHello() async throws {
        var sent: MagicMobileOnDevice.JSONValue?
        let epoch = UUID()
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let transport = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: epoch) { data, peer in
            XCTAssertEqual(peer, "host")
            sent = try MagicMobileOnDevice.JSONValue.decode(data)
        }
        let hello = Task { try await transport.hello(identity: identity) }
        defer { transport.close() }
        for _ in 0..<10_000 { if sent != nil { break }; await Task.yield() }
        let reply = Self.reply(to: try XCTUnwrap(sent), result: .object(["seatId": .string("player2"), "build": identity.json]))
        XCTAssertThrowsError(try transport.receive(reply, from: "impostor"))
        var incorrect = reply.object!
        incorrect["id"] = .string(UUID().uuidString)
        XCTAssertThrowsError(try transport.receive(.object(incorrect), from: "host"))
        incorrect = reply.object!; incorrect["sequence"] = .integer(99)
        XCTAssertThrowsError(try transport.receive(.object(incorrect), from: "host"))
        incorrect = reply.object!; incorrect["epoch"] = .string(UUID().uuidString)
        XCTAssertThrowsError(try transport.receive(.object(incorrect), from: "host"))
        try transport.receive(reply, from: "host")
        try await hello.value
        XCTAssertThrowsError(try transport.receive(reply, from: "host"))
        transport.close()
    }

    @MainActor
    func testTimeoutAndCloseReleasePendingRequests() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let timed = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: UUID(), timeoutNanoseconds: 10_000_000) { _, _ in }
        do { try await timed.hello(identity: identity); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("in time")) }
        timed.close()
        var sent = false
        let closed = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: UUID()) { _, _ in sent = true }
        let hello = Task { try await closed.hello(identity: identity) }
        for _ in 0..<10_000 { if sent { break }; await Task.yield() }
        XCTAssertTrue(sent)
        closed.close()
        do { try await hello.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testOutOfOrderRepliesCompleteOnlyTheirOwnPoll() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let link = MultiplayerTestLink()
        let remote = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: UUID()) { data, _ in
            let value = try MagicMobileOnDevice.JSONValue.decode(data)
            if value["operation"]?.string == "hello" {
                try link.remote?.receive(Self.reply(to: value, result: .object(["seatId": .string("player2"), "build": identity.json])), from: "host")
            } else { link.requests.append(value) }
        }
        link.remote = remote
        defer { remote.close() }
        try await remote.hello(identity: identity)
        let client = EngineClient(transport: remote)
        let first = Task { try await client.poll(matchID: "match", seatID: "player2", after: 11) }
        let second = Task { try await client.poll(matchID: "match", seatID: "player2", after: 22) }
        for _ in 0..<10_000 { if link.requests.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(link.requests.count, 2)
        for value in link.requests.reversed() {
            let result: MagicMobileOnDevice.JSONValue = .object(["matchId": .string("match"), "viewerId": .string("player2"),
                "revision": value["payload"]!["after"]!, "phase": .string("running"), "resyncRequired": .bool(false)])
            try remote.receive(Self.reply(to: value, result: result), from: "host")
        }
        let firstPoll = try await first.value, secondPoll = try await second.value
        XCTAssertEqual(firstPoll.revision, 11)
        XCTAssertEqual(secondPoll.revision, 22)
    }

    @MainActor
    func testHostDispatcherDrainsRequestsInArrivalOrder() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue"), epoch = UUID()
        let engine = MultiplayerRecordingEngine(holdFirstRequest: true)
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        var replies: [MagicMobileOnDevice.JSONValue] = []
        let dispatcher = OnDeviceHostRequestDispatcher(router: router, epoch: epoch, peerIDs: ["client"], send: { value, peer in
            XCTAssertEqual(peer, "client"); replies.append(value)
        }, onError: { XCTFail($0) })
        try dispatcher.receive(Self.request(sequence: 1, epoch: epoch, operation: "hello", payload: identity.json), from: "client")
        for sequence in 2...4 {
            try dispatcher.receive(Self.request(sequence: Int64(sequence), epoch: epoch, operation: "poll", payload: .object(["after": .integer(0)])), from: "client")
        }
        for _ in 0..<10_000 { if await engine.requests.count == 1 { break }; await Task.yield() }
        for _ in 0..<100 { await Task.yield() }
        let started = await engine.requests
        XCTAssertEqual(started.count, 1, "Later RPCs must wait for the active request to finish")
        XCTAssertEqual(replies.count, 1, "Only hello may have completed")
        await engine.release()
        for _ in 0..<10_000 { if replies.count == 4 { break }; await Task.yield() }
        XCTAssertEqual(replies.compactMap { $0["sequence"]?.integer }, [1, 2, 3, 4])
        XCTAssertTrue(replies.allSatisfy { $0["error"] == .null })
        await dispatcher.close()
    }

    @MainActor
    func testDispatcherShutdownWaitsForActiveWorkAndDiscardsQueuedCommands() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue"), epoch = UUID()
        let engine = MultiplayerRecordingEngine(holdFirstRequest: true)
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        var replies: [MagicMobileOnDevice.JSONValue] = []
        let dispatcher = OnDeviceHostRequestDispatcher(router: router, epoch: epoch, peerIDs: ["client"],
            send: { value, _ in replies.append(value) }, onError: { XCTFail($0) })
        try dispatcher.receive(Self.request(sequence: 1, epoch: epoch, operation: "hello", payload: identity.json), from: "client")
        try dispatcher.receive(Self.request(sequence: 2, epoch: epoch, operation: "poll", payload: .object(["after": .integer(0)])), from: "client")
        let command: MagicMobileOnDevice.JSONValue = .object(["requestId": .string(UUID().uuidString), "promptId": .string("prompt"),
            "promptRevision": .integer(1), "answer": .bool(true)])
        let queued = Self.request(sequence: 3, epoch: epoch, operation: "respond", payload: command)
        try dispatcher.receive(queued, from: "client")
        for _ in 0..<10_000 { if await engine.requests.count == 1 { break }; await Task.yield() }
        dispatcher.cancel()
        var didClose = false
        let close = Task { await dispatcher.close(); didClose = true }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(didClose, "Native ownership must survive until active work returns")
        XCTAssertThrowsError(try dispatcher.receive(queued, from: "client"))
        await engine.release(); await close.value
        XCTAssertTrue(didClose)
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["op"]?.string, "poll")
        XCTAssertEqual(replies.count, 1, "Shutdown must not send late replies")
    }

    @MainActor
    func testTimedOutCommandCanRetryAfterCorrelatedBusyWithoutLosingIdentity() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue"), epoch = UUID()
        let engine = MultiplayerRecordingEngine(holdFirstRequest: true)
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        let link = MultiplayerTestLink()
        let remote = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: epoch,
            timeoutNanoseconds: 50_000_000) { data, _ in
                let value = try MagicMobileOnDevice.JSONValue.decode(data)
                link.requests.append(value)
                try link.dispatcher?.receive(value, from: "client")
            }
        link.remote = remote
        var replies: [MagicMobileOnDevice.JSONValue] = [], fatalErrors: [String] = []
        let dispatcher = OnDeviceHostRequestDispatcher(router: router, epoch: epoch, peerIDs: ["client"], send: { value, _ in
            replies.append(value)
            do { try remote.receive(value, from: "host") } catch EngineError.replayedMessage { }
        }, onError: { fatalErrors.append($0) })
        link.dispatcher = dispatcher
        try await remote.hello(identity: identity)
        let client = EngineClient(transport: remote), commandID = UUID()
        let prompt = try EnginePrompt(.object(["promptId": .string("prompt"), "revision": .integer(3), "kind": .string("ASK"),
            "payload": .object([:]), "submitted": .bool(false), "responseTypes": .array([.string("boolean")]), "min": .integer(1), "max": .integer(1)]))
        let polls = (0..<3).map { _ in Task { try await client.poll(matchID: "match", seatID: "player2") } }
        let original = Task { try await client.respond(matchID: "match", seatID: "player2", prompt: prompt, answer: .bool(true), requestID: commandID) }
        for poll in polls { do { _ = try await poll.value; XCTFail("Expected timeout") } catch { } }
        do { _ = try await original.value; XCTFail("Expected timeout") } catch { }
        do {
            _ = try await client.respond(matchID: "match", seatID: "player2", prompt: prompt, answer: .bool(true), requestID: commandID)
            XCTFail("Expected correlated busy")
        } catch {
            // Session retains pending actions for transport failures; .rejected clears them.
            guard case .invalidMessage(let message) = error as? EngineError else {
                await engine.release(); await dispatcher.close(); remote.close()
                return XCTFail("Busy must be a retryable transport failure, got \(error)")
            }
            XCTAssertTrue(message.contains("busy"))
        }
        XCTAssertEqual(replies.last?["id"], link.requests.last?["id"])
        XCTAssertEqual(replies.last?["sequence"], link.requests.last?["sequence"])
        XCTAssertTrue(fatalErrors.isEmpty)
        await engine.release()
        for _ in 0..<10_000 { if replies.count == 6 { break }; await Task.yield() }
        XCTAssertEqual(replies.count, 6)
        _ = try await client.respond(matchID: "match", seatID: "player2", prompt: prompt, answer: .bool(true), requestID: commandID)
        let answers = await engine.requests.filter { $0["op"]?.string == "respond" }
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers.first?["command"], answers.last?["command"])
        XCTAssertEqual(answers.last?["command"]?["requestId"]?.string, commandID.uuidString.lowercased())
        XCTAssertTrue(fatalErrors.isEmpty)
        await dispatcher.close(); remote.close()
    }

    @MainActor
    func testDispatcherKeepsEpochSeatAndReplayValidationAndDoesNotWaitForGaps() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue"), epoch = UUID()
        let engine = MultiplayerRecordingEngine()
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        var replies: [MagicMobileOnDevice.JSONValue] = [], errors: [String] = []
        let dispatcher = OnDeviceHostRequestDispatcher(router: router, epoch: epoch, peerIDs: ["client"],
            send: { value, _ in replies.append(value) }, onError: { errors.append($0) })
        let hello = Self.request(sequence: 1, epoch: epoch, operation: "hello", payload: identity.json)
        XCTAssertThrowsError(try dispatcher.receive(hello, from: "intruder"))
        XCTAssertThrowsError(try dispatcher.receive(Self.request(sequence: 1, epoch: UUID(), operation: "hello", payload: identity.json), from: "client"))
        try dispatcher.receive(hello, from: "client")
        // Missing sequence 2 cannot stall the drain; replay validation remains in HostRouter.
        try dispatcher.receive(Self.request(sequence: 3, epoch: epoch, operation: "poll", payload: .object(["after": .integer(0)])), from: "client")
        try dispatcher.receive(Self.request(sequence: 2, epoch: epoch, operation: "poll", payload: .object(["after": .integer(0)])), from: "client")
        try dispatcher.receive(Self.request(sequence: 4, epoch: epoch, operation: "poll", payload: .object(["after": .integer(0), "viewerId": .string("player1")])), from: "client")
        for _ in 0..<10_000 { if replies.count == 4 { break }; await Task.yield() }
        XCTAssertEqual(replies.count, 4)
        XCTAssertEqual(replies[1]["result"]?["viewerId"]?.string, "player2")
        XCTAssertEqual(replies[2]["error"]?.string, EngineError.replayedMessage.localizedDescription)
        XCTAssertNotNil(replies[3]["error"]?.string)
        XCTAssertTrue(errors.isEmpty)
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 1)
        await dispatcher.close()
    }

    @MainActor
    func testRealHostRouterBindsPollAndPreservesCommandIdentityOnRetry() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID()
        let engineTransport = MultiplayerRecordingEngine()
        let router = HostRouter(engine: EngineClient(transport: engineTransport), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        let link = MultiplayerTestLink()
        let remote = OnDeviceRemoteEngineTransport(hostID: "host", matchID: "match", seatID: "player2", epoch: epoch, timeoutNanoseconds: 100_000_000) { data, peer in
            XCTAssertEqual(peer, "host")
            let value = try MagicMobileOnDevice.JSONValue.decode(data)
            link.requests.append(value)
            Task { @MainActor in
                let frame = PeerFrame(epoch: epoch, sequence: UInt64(value["sequence"]!.integer!), operation: value["operation"]!.string!, payload: value["payload"]!)
                do {
                    let result = try await router.handle(frame, authenticatedPeerID: "client")
                    if link.dropNextResponse { link.dropNextResponse = false; return }
                    try link.remote?.receive(Self.reply(to: value, result: result), from: "host")
                } catch { XCTFail("Authenticated roundtrip failed: \(error)"); link.remote?.close() }
            }
        }
        link.remote = remote
        defer { remote.close() }
        try await remote.hello(identity: identity)
        let client = EngineClient(transport: remote)
        let poll = try await client.poll(matchID: "match", seatID: "player2")
        XCTAssertEqual(poll.seatID, "player2")
        do { _ = try await client.poll(matchID: "match", seatID: "player1"); XCTFail("Seat theft accepted") }
        catch { XCTAssertEqual(error as? EngineError, .unboundPeer) }
        do { try await client.destroy(matchID: "match"); XCTFail("Remote destroy accepted") } catch { }
        let requestID = UUID()
        let prompt = try EnginePrompt(.object(["promptId": .string("prompt"), "revision": .integer(3),
            "kind": .string("ASK"), "payload": .object([:]), "submitted": .bool(false),
            "responseTypes": .array([.string("boolean")]), "min": .integer(1), "max": .integer(1)]))
        link.dropNextResponse = true
        do {
            _ = try await client.respond(matchID: "match", seatID: "player2", prompt: prompt,
                                         answer: .bool(true), requestID: requestID)
            XCTFail("Expected lost acknowledgement timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("in time")) }
        _ = try await client.respond(matchID: "match", seatID: "player2", prompt: prompt,
                                     answer: .bool(true), requestID: requestID)
        let answers = await engineTransport.requests.filter { $0["op"]?.string == "respond" }
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers[0]["command"]?["requestId"]?.string, requestID.uuidString.lowercased())
        XCTAssertEqual(answers[0]["command"], answers[1]["command"])
        XCTAssertEqual(answers[0]["viewerId"]?.string, "player2")
        XCTAssertNotEqual(link.requests[2]["id"], link.requests[3]["id"])
        XCTAssertNotEqual(link.requests[2]["sequence"], link.requests[3]["sequence"])
        remote.close()
    }

    func testHostRouterRejectsReplayOutOfOrderAndIncompatibleHello() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID()
        let engine = MultiplayerRecordingEngine()
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        let hello = PeerFrame(epoch: epoch, sequence: 1, operation: "hello", payload: identity.json)
        do { _ = try await router.handle(hello, authenticatedPeerID: "intruder"); XCTFail("Unbound peer accepted") }
        catch { XCTAssertEqual(error as? EngineError, .unboundPeer) }
        _ = try await router.handle(hello, authenticatedPeerID: "client")
        let poll = PeerFrame(epoch: epoch, sequence: 3, operation: "poll", payload: .object(["after": .integer(0)]))
        _ = try await router.handle(poll, authenticatedPeerID: "client")
        for number: UInt64 in [3, 2] {
            do { _ = try await router.handle(PeerFrame(epoch: epoch, sequence: number, operation: "poll", payload: poll.payload), authenticatedPeerID: "client"); XCTFail("Replay accepted") }
            catch { XCTAssertEqual(error as? EngineError, .replayedMessage) }
        }
        do {
            _ = try await router.handle(PeerFrame(epoch: epoch, sequence: 4, operation: "hello", payload: BuildIdentity(upstreamCommit: "other", catalogueHash: "catalogue").json), authenticatedPeerID: "client")
            XCTFail("Incompatible hello accepted")
        } catch { XCTAssertEqual(error as? EngineError, .incompatibleBuild) }
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testHostRouterSuspensionRejectsAnswersUntilResume() async throws {
        let identity = BuildIdentity(upstreamCommit: "commit", catalogueHash: "catalogue")
        let epoch = UUID(), engine = MultiplayerRecordingEngine()
        let router = HostRouter(engine: EngineClient(transport: engine), matchID: "match", identity: identity, epoch: epoch)
        try await router.bind(authenticatedPeerID: "client", seatID: "player2")
        _ = try await router.handle(PeerFrame(epoch: epoch, sequence: 1, operation: "hello", payload: identity.json), authenticatedPeerID: "client")
        let command: MagicMobileOnDevice.JSONValue = .object(["requestId": .string(UUID().uuidString), "promptId": .string("prompt"), "promptRevision": .integer(1), "answer": .bool(true)])
        await router.setSuspended(true)
        do {
            _ = try await router.handle(PeerFrame(epoch: epoch, sequence: 2, operation: "respond", payload: command), authenticatedPeerID: "client")
            XCTFail("Suspended host accepted answer")
        } catch { XCTAssertEqual(error as? EngineError, .hostSuspended) }
        let before = await engine.requests
        XCTAssertTrue(before.isEmpty)
        await router.setSuspended(false)
        _ = try await router.handle(PeerFrame(epoch: epoch, sequence: 3, operation: "respond", payload: command), authenticatedPeerID: "client")
        let after = await engine.requests
        XCTAssertEqual(after.count, 1)
    }

    private static func reply(to request: MagicMobileOnDevice.JSONValue, result: MagicMobileOnDevice.JSONValue) -> MagicMobileOnDevice.JSONValue {
        .object(["type": .string("reply"), "id": request["id"]!, "epoch": request["epoch"]!,
                 "sequence": request["sequence"]!, "result": result, "error": .null])
    }
    private static func request(sequence: Int64, epoch: UUID, operation: String, payload: MagicMobileOnDevice.JSONValue) -> MagicMobileOnDevice.JSONValue {
        .object(["type": .string("request"), "epoch": .string(epoch.uuidString), "id": .string(UUID().uuidString),
                 "sequence": .integer(sequence), "operation": .string(operation), "payload": payload])
    }
}

@MainActor
private final class MultiplayerTestLink {
    weak var remote: OnDeviceRemoteEngineTransport?
    var requests: [MagicMobileOnDevice.JSONValue] = []
    var dropNextResponse = false
    var dispatcher: OnDeviceHostRequestDispatcher?
}

/// Only the native engine boundary is replaced; production HostRouter and RPC run unchanged.
private actor MultiplayerRecordingEngine: EngineTransport {
    private(set) var requests: [MagicMobileOnDevice.JSONValue] = []
    private var holdFirstRequest: Bool
    private var held: CheckedContinuation<Void, Never>?
    init(holdFirstRequest: Bool = false) { self.holdFirstRequest = holdFirstRequest }
    func release() { held?.resume(); held = nil; holdFirstRequest = false }
    func request(_ data: Data) async throws -> Data {
        let request = try MagicMobileOnDevice.JSONValue.decode(data)
        requests.append(request)
        if holdFirstRequest {
            holdFirstRequest = false
            await withCheckedContinuation { held = $0 }
        }
        let result: MagicMobileOnDevice.JSONValue = request["op"]?.string == "poll" ? .object([
            "matchId": .string("match"), "viewerId": request["viewerId"]!, "revision": .integer(1),
            "phase": .string("running"), "resyncRequired": .bool(false), "snapshot": .null, "prompt": .null
        ]) : .object(["accepted": .bool(true)])
        return try MagicMobileOnDevice.JSONValue.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }
}

extension OnDeviceMultiplayerTests {
    func testMatchRoomReadyRosterComesOnlyFromTheHostAndCarriesPublicCommanders() throws {
        let deck: MagicMobileOnDevice.JSONValue = .object(["main": .array([]), "commanders": .array([
            .object(["name": .string("Chatterfang, Squirrel General"), "setCode": .string("MH2"), "collectorNumber": .string("151"), "count": .integer(1)]),
        ])])
        var host = try OnDeviceMultiplayerLobby(peerIDs: ["bob", "alice", "carol"], localPeerID: "alice")
        let guest = try OnDeviceMultiplayerLobby(peerIDs: ["bob", "alice", "carol"], localPeerID: "bob")
        let epoch = UUID()
        XCTAssertEqual(try host.readyPacket(epoch: epoch)["players"]?.array?.count, 0, "nobody is ready yet")
        try host.submit(.object(["name": .string("Alice"), "deck": deck]), from: "alice")
        XCTAssertFalse(host.isReady, "the game waits for every player to ready up")
        let packet = try host.readyPacket(epoch: epoch)
        XCTAssertEqual(try guest.acceptReadyPacket(packet, from: "alice"), ["alice": ["Chatterfang, Squirrel General"]])
        XCTAssertThrowsError(try guest.acceptReadyPacket(packet, from: "carol"), "only the host reports readiness")
        XCTAssertThrowsError(try guest.readyPacket(epoch: epoch), "guests never author the roster")
        var forged = packet.object!
        forged["players"] = .array([.object(["id": .string("intruder"), "commanders": .array([])])])
        XCTAssertThrowsError(try guest.acceptReadyPacket(.object(forged), from: "alice"), "unknown players are rejected")
        XCTAssertEqual(host.submittedPeers, ["alice"])
    }
}
