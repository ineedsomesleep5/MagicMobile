import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnlineAPITests: XCTestCase {
    override func tearDown() { OnlineURLProtocol.handler = nil; super.tearDown() }

    @MainActor
    func testUnconfiguredOnlineCannotAuthenticateOrCreateLobby() async throws {
        let online = OnlineSession(configuration: nil)
        XCTAssertFalse(online.available)
        XCTAssertNil(online.api)
        await online.restore()
        await online.signIn(email: "a@example.test", password: "test", create: false)
        await online.enter(code: nil, name: "Player", playerCount: 2,
            identity: BuildIdentity(upstreamCommit: "test", catalogueHash: "test"), deck: .object([:]))
        await online.enter(code: "ABC123", name: "Player", playerCount: 2,
            identity: BuildIdentity(upstreamCommit: "test", catalogueHash: "test"), deck: .object([:]))
        await online.ready(true)
        await online.start()
        XCTAssertNil(online.userID)
        XCTAssertNil(online.lobby)
        XCTAssertFalse(online.busy)
    }

    func testProductionSessionDeniesEveryRedirect() throws {
        let session = OnlineRedirectPolicy.session()
        defer { session.invalidateAndCancel() }
        let delegate = try XCTUnwrap(session.delegate as? OnlineRedirectPolicy)
        let origin = URL(string: "https://game.example.test/v1/lobbies")!
        let task = session.dataTask(with: origin)
        for target in ["http://game.example.test/v1/lobbies", "https://other.example.test/capture", "https://game.example.test/elsewhere"] {
            var request = URLRequest(url: URL(string: target)!)
            request.httpMethod = "POST"; request.httpBody = Data("private-body".utf8)
            request.setValue("Bearer private-token", forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: origin, statusCode: 307, httpVersion: nil, headerFields: ["Location": target])!
            var answered = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected in
                answered = true
                XCTAssertNil(redirected, "Sensitive requests must not follow redirects")
            }
            XCTAssertTrue(answered)
        }
    }

    func testSignOutCannotBeUndoneByInFlightRefresh() async throws {
        let api = makeAPI()
        let refreshStarted = expectation(description: "Refresh entered")
        let release = DispatchSemaphore(value: 0)
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" {
                if request.url?.query == "grant_type=refresh_token" {
                    refreshStarted.fulfill()
                    guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
                    return (200, Self.credentials(token: "refreshed"))
                }
                return (200, Self.credentials())
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed"
                ? (200, Data("{}".utf8)) : (401, Data("{}".utf8))
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        let pending = Task { try await api.request(path: "v1/lobbies/current") }
        await fulfillment(of: [refreshStarted], timeout: 5)
        try await api.signOut()
        release.signal()
        _ = try? await pending.value
        let user = await api.userID()
        XCTAssertNil(user, "A late refresh must not sign the user back in")
    }

    func testSignOutCannotBeUndoneByInFlightSignIn() async throws {
        let api = makeAPI()
        let authStarted = expectation(description: "Sign-in entered")
        let release = DispatchSemaphore(value: 0)
        OnlineURLProtocol.handler = { _ in
            authStarted.fulfill()
            guard release.wait(timeout: .now() + 10) == .success else { throw URLError(.timedOut) }
            return (200, Self.credentials())
        }
        let pending = Task { try await api.authenticate(email: "a@example.test", password: "test", create: false) }
        await fulfillment(of: [authStarted], timeout: 5)
        try await api.signOut()
        release.signal()
        _ = try? await pending.value
        let user = await api.userID()
        XCTAssertNil(user, "A late sign-in must respect a newer sign-out")
    }

    func testGameTransportPreservesResponseAndAuthenticatesWithoutSendingPublishableKeyToGameServer() async throws {
        let api = makeAPI()
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" { return (200, Self.credentials()) }
            XCTAssertEqual(request.url?.path, "/v1/matches/match-1/engine")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-test")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            let body = try JSONValue.decode(XCTUnwrap(request.httpBody))
            XCTAssertEqual(body["op"]?.string, "poll")
            XCTAssertEqual(body["viewerId"]?.string, "user-1")
            return (200, Data("{\"protocol\":1,\"ok\":false,\"error\":{\"code\":\"stale_prompt\",\"message\":\"Refresh\"}}".utf8))
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        let client = EngineClient(transport: OnlineEngineTransport(api: api, matchID: "match-1"))
        do {
            _ = try await client.call("poll", fields: ["viewerId": .string("user-1")])
            XCTFail("Engine rejection was swallowed")
        } catch EngineError.rejected(let code, _) { XCTAssertEqual(code, "stale_prompt") }
    }

    func testUnauthorizedRequestRefreshesOnceAndRetainsRequestBody() async throws {
        let api = makeAPI()
        var calls = 0
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" {
                let refresh = request.url?.query == "grant_type=refresh_token"
                return (200, Self.credentials(token: refresh ? "refreshed" : "access-test"))
            }
            calls += 1
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
            if calls == 1 { return (401, Data("{}".utf8)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
            return (200, Data("{}".utf8))
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        _ = try await api.request(path: "v1/lobbies/one/ready", body: Data("{}".utf8))
        XCTAssertEqual(calls, 2)
    }

    func testEmailConfirmationDoesNotCreateAuthenticatedSession() async throws {
        let api = makeAPI()
        OnlineURLProtocol.handler = { _ in (200, Data("{\"id\":\"user-1\"}".utf8)) }
        let signedIn = try await api.authenticate(email: "a@example.test", password: "test", create: true)
        XCTAssertFalse(signedIn)
        let user = await api.userID()
        XCTAssertNil(user)
    }

    func testCurrentLobbySupportsNoMembership() async throws {
        let api = makeAPI()
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" { return (200, Self.credentials()) }
            XCTAssertEqual(request.url?.path, "/v1/lobbies/current")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, Data("null".utf8))
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        let lobby = try await api.currentLobby()
        XCTAssertNil(lobby)
    }

    @MainActor
    func testLostCreateResponseRecoversMembershipWithoutDuplicateCreate() async throws {
        let api = makeAPI()
        var creates = 0
        var hasMembership = false
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" { return (200, Self.credentials()) }
            if request.url?.path == "/v1/lobbies" {
                creates += 1; hasMembership = true
                throw URLError(.timedOut)
            }
            if request.url?.path == "/v1/lobbies/current" {
                return (200, hasMembership ? Self.lobby : Data("null".utf8))
            }
            return (200, Self.lobby)
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        let session = OnlineSession(api: api)
        await session.restore()
        await session.enter(code: nil, name: "Player", playerCount: 2,
            identity: BuildIdentity(upstreamCommit: "test", catalogueHash: "test"), deck: .object([:]))
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(session.lobby?.id, "lobby-1")
        XCTAssertNil(session.error)
        session.setForeground(false)
    }

    @MainActor
    func testInterruptedLobbyCanBeRestoredAndLeft() async throws {
        let api = makeAPI()
        let interrupted = Data(String(decoding: Self.lobby, as: UTF8.self).replacingOccurrences(of: "waiting", with: "interrupted").utf8)
        var left = false
        OnlineURLProtocol.handler = { request in
            if request.url?.host == "auth.example.test" { return (200, Self.credentials()) }
            if request.url?.path == "/v1/lobbies/lobby-1/leave" { left = true; return (200, Data("{}".utf8)) }
            return (200, interrupted)
        }
        _ = try await api.authenticate(email: "a@example.test", password: "test", create: false)
        let session = OnlineSession(api: api)
        await session.restore()
        XCTAssertEqual(session.lobby?.status, "interrupted")
        try await session.leave()
        XCTAssertTrue(left)
        XCTAssertNil(session.lobby)
    }

    private static let lobby = Data("""
        {"id":"lobby-1","code":"ABC123","status":"waiting","hostUserId":"user-1","playerCount":2,
        "players":[{"userId":"user-1","name":"Player","seatId":"user-1","ready":false,"deckSubmitted":true}],
        "matchId":null,"seatId":null}
        """.utf8)

    private func makeAPI() -> OnlineAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnlineURLProtocol.self]
        return OnlineAPI(configuration: OnlineConfiguration(serverURL: URL(string: "https://game.example.test")!,
            supabaseURL: URL(string: "https://auth.example.test")!, publishableKey: "public-test"),
            session: URLSession(configuration: config), persistsCredentials: false)
    }
    private static func credentials(token: String = "access-test") -> Data {
        Data("{\"access_token\":\"\(token)\",\"refresh_token\":\"refresh-test\",\"expires_at\":4102444800,\"user\":{\"id\":\"user-1\",\"email\":\"a@example.test\"}}".utf8)
    }
}

private final class OnlineURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            // URLSession may convert an HTTP body to a stream before interception.
            var request = request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; data.append(buffer, count: count)
                }
                request.httpBody = data
            }
            let (status, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
